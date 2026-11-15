package com.memexlab.bedwatch

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder

/** Minimal blocking HTTP for the home LAN (private IPv4 literals only, enforced by [LookProtocol.lanBase]). */
class LanHttp(base: String, private val headerName: String, private val headerValue: String) {
    private val base = LookProtocol.lanBase(base)
    data class Reply(val code: Int, val body: String)

    fun call(method: String, path: String, body: ByteArray? = null, contentType: String? = null,
        extra: Map<String, String> = emptyMap(), connectMs: Int = 4000, readMs: Int = 10_000): Reply {
        val connection = URI(base + path).toURL().openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = method
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = connectMs
            connection.readTimeout = readMs
            connection.setRequestProperty(headerName, headerValue)
            extra.forEach { (k, v) -> connection.setRequestProperty(k, v) }
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", contentType ?: "application/octet-stream")
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            } else if (method == "POST") {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(0)
                connection.outputStream.close()
            }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.use { input -> String(input.readNBytes(4096), Charsets.UTF_8) } ?: ""
            Reply(code, text)
        } finally { connection.disconnect() }
    }
}

/** The home PC side of camera_look: long poll for a request, then post the JPEG or a failure code. */
class LookServer(base: String, token: String) {
    private val http = LanHttp(base, "Authorization", "Bearer $token")
    class Unauthorized : IOException("unauthorized")

    fun next(): LookRequest? {
        val reply = http.call("GET", "/v1/camera/next", readMs = 40_000)
        return when (reply.code) {
            200 -> LookProtocol.parseRequest(reply.body)
            204 -> null
            401 -> throw Unauthorized()
            else -> throw IOException("poll ${reply.code}")
        }
    }
    fun frame(id: String, jpeg: ByteArray, meta: String): Boolean =
        http.call("POST", "/v1/camera/frame?id=$id", jpeg, "image/jpeg", mapOf("X-Camera-Meta" to meta), readMs = 15_000).code == 200
    fun fail(id: String, code: String) {
        runCatching { http.call("POST", "/v1/camera/fail?id=$id&code=" + URLEncoder.encode(code, "UTF-8")) }
    }
}

/** ESP32 pan-tilt mount (tools/bed_watch_gimbal). Answers only after the move has settled. */
class Gimbal(base: String, token: String) {
    private val http = LanHttp(base, "X-Gimbal-Token", token)
    fun move(aim: Aim): Boolean = runCatching {
        http.call("POST", "/move?pan=${aim.pan}&tilt=${aim.tilt}", readMs = 8000).code == 200
    }.getOrDefault(false)
}

/** Camera access the runner needs; implemented by the service around [CameraSession]. */
interface LookCamera {
    /** Blocks until one frame is captured (or null on failure/timeout). */
    fun snap(warmupMs: Long): Snapshot?
    /** Called once per request when the runner is finished with the camera. */
    fun release()
}

data class LookResult(val snapshot: Snapshot?, val failure: String?, val found: Boolean?, val reached: String?)

/** Pure orchestration of one request: pause check, turning, find-me scan and recentring, one final frame. */
class LookRunner(private val camera: LookCamera, private val gimbal: (LookConfig) -> ((Aim) -> Boolean)?) {
    fun run(request: LookRequest, config: LookConfig, now: Long): LookResult {
        if (now < config.pausedUntil) return LookResult(null, "paused", null, null)
        try {
            val move = gimbal(config)
            return when {
                request.position == LookProtocol.FIND_ME -> findMe(config, move)
                request.position == LookProtocol.CURRENT || move == null -> shoot(LookProtocol.CURRENT, 0)
                else -> {
                    val aim = config.positions[request.position] ?: return LookResult(null, "gimbal_error", null, null)
                    if (!move(aim)) LookResult(null, "gimbal_error", null, null) else shoot(request.position, AFTER_MOVE_MS)
                }
            }
        } finally { camera.release() }
    }

    private fun shoot(reached: String, warmup: Long, found: Boolean? = null): LookResult {
        val snap = camera.snap(warmup) ?: return LookResult(null, "camera_error", null, null)
        return LookResult(snap, null, found, reached)
    }

    private fun findMe(config: LookConfig, move: ((Aim) -> Boolean)?): LookResult {
        if (move == null || config.positions.isEmpty()) {
            val snap = camera.snap(0) ?: return LookResult(null, "camera_error", null, null)
            return if (snap.features.face) LookResult(snap, null, true, LookProtocol.CURRENT) else LookResult(null, "not_found", false, null)
        }
        for ((name, aim) in config.positions) {
            if (!move(aim)) return LookResult(null, "gimbal_error", null, null)
            val snap = camera.snap(AFTER_MOVE_MS) ?: return LookResult(null, "camera_error", null, null)
            val fx = snap.faceX
            val fy = snap.faceY
            if (!snap.features.face || fx == null || fy == null) continue
            val centred = LookProtocol.recenter(aim, fx, fy, config.fovDegrees, config.invertPan, config.invertTilt)
            if (centred == aim || !move(centred)) return LookResult(snap, null, true, name)
            val final = camera.snap(AFTER_MOVE_MS) ?: snap
            return LookResult(final, null, true, name)
        }
        return LookResult(null, "not_found", false, null)
    }

    companion object { const val AFTER_MOVE_MS = 600L }
}

/** Background long-poll loop. Stops when [stop] is called; backs off on network errors. */
class LookClient(
    private val settings: () -> LookConfig,
    private val runner: LookRunner,
    private val onLooked: () -> Unit,
) {
    @Volatile private var running = false
    private var thread: Thread? = null

    fun start() {
        if (running) return
        running = true
        thread = Thread({ loop() }, "look-client").also { it.isDaemon = true; it.start() }
    }
    fun stop() { running = false; thread?.interrupt(); thread = null }

    private fun loop() {
        var backoff = 2000L
        while (running) {
            val config = settings()
            if (!config.enabled) { sleep(5000); continue }
            try {
                val server = LookServer(config.server, config.token)
                val request = server.next()
                backoff = 2000L
                if (request == null || !running) continue
                val result = runner.run(request, settings(), System.currentTimeMillis())
                val snap = result.snapshot
                if (result.failure != null || snap == null) {
                    server.fail(request.id, result.failure ?: "camera_error")
                } else {
                    val f = snap.features
                    val ok = server.frame(request.id, snap.jpeg,
                        LookProtocol.meta(f.face, f.eyesOpen, f.frameLuma, result.found, result.reached))
                    snap.jpeg.fill(0)
                    if (ok) onLooked()
                }
            } catch (_: LookServer.Unauthorized) {
                sleep(60_000)
            } catch (_: InterruptedException) {
                return
            } catch (_: Exception) {
                sleep(backoff)
                backoff = (backoff * 2).coerceAtMost(30_000L)
            }
        }
    }
    private fun sleep(ms: Long) { try { Thread.sleep(ms) } catch (_: InterruptedException) { running = running } }
}
