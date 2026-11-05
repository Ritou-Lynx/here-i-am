package com.memexlab.memex.ble

import java.net.HttpURLConnection
import java.net.URI
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * HR1: pushes 1 Hz samples to the home computer's i MCP heart-rate listener
 * (`https://<computer>.ts.net:8447/v1/heart-rate/samples`, reached through `tailscale serve`,
 * which authenticates the phone by its Tailscale login; no token is stored on the phone).
 *
 * Pure JVM: no Android types, so the queue, body and URL rules run in plain unit tests.
 * Only bpm and timestamps leave the phone; RR intervals, device address and userKey never do.
 */
internal class BleHeartRateUploadQueue(
    private val maxAgeMs: Long = 10 * 60_000L,
    private val maxBatch: Int = 300,
    private val minBackoffMs: Long = 5_000L,
    private val maxBackoffMs: Long = 60_000L,
) {
    data class Sample(val timestampMs: Long, val bpm: Int)

    private val samples = ArrayDeque<Sample>()
    private var lastTimestampMs = Long.MIN_VALUE
    private var failures = 0
    private var nextAttemptAtMs = 0L

    @Synchronized
    fun offer(timestampMs: Long, bpm: Int) {
        if (bpm !in MIN_BPM..MAX_BPM || timestampMs <= lastTimestampMs) return
        samples.addLast(Sample(timestampMs, bpm))
        lastTimestampMs = timestampMs
    }

    @Synchronized
    fun size(): Int = samples.size

    @Synchronized
    fun nextAttemptAtMs(): Long = nextAttemptAtMs

    /** Oldest-first batch, or empty while backing off. Samples older than [maxAgeMs] are dropped. */
    @Synchronized
    fun batch(nowMs: Long): List<Sample> {
        while (samples.isNotEmpty() && samples.peekFirst().timestampMs < nowMs - maxAgeMs) samples.removeFirst()
        if (nowMs < nextAttemptAtMs) return emptyList()
        return samples.take(maxBatch)
    }

    /** Removes a batch that the computer accepted (or rejected for good). */
    @Synchronized
    fun acknowledge(batch: List<Sample>) {
        val last = batch.lastOrNull()?.timestampMs ?: return
        while (samples.isNotEmpty() && samples.peekFirst().timestampMs <= last) samples.removeFirst()
        failures = 0
        nextAttemptAtMs = 0L
    }

    /** Keeps the batch and backs off 5 s, 10 s, 20 s, 40 s, then 60 s. */
    @Synchronized
    fun fail(nowMs: Long) {
        failures = (failures + 1).coerceAtMost(16)
        val delay = (minBackoffMs shl (failures - 1).coerceAtMost(10)).coerceAtMost(maxBackoffMs)
        nextAttemptAtMs = nowMs + delay
    }

    @Synchronized
    fun clear() {
        samples.clear()
        failures = 0
        nextAttemptAtMs = 0L
    }

    companion object {
        const val MIN_BPM = 30
        const val MAX_BPM = 220
    }
}

internal object BleHeartRateUploadProtocol {
    const val SAMPLES_PATH = "/v1/heart-rate/samples"
    private val STATUS = Regex("[A-Za-z]{1,32}")

    /**
     * Accepts a root address such as `https://pc.example.ts.net:8447` and returns the samples URL,
     * or null when it is not a plain HTTPS root (loopback HTTP is allowed for local testing).
     */
    fun samplesUrl(base: String?): String? {
        val trimmed = base?.trim()?.trimEnd('/') ?: return null
        if (trimmed.isEmpty()) return null
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        val host = uri.host ?: return null
        val loopback = host == "127.0.0.1" || host == "localhost"
        if (uri.scheme != "https" && !(uri.scheme == "http" && loopback)) return null
        if (uri.rawUserInfo != null || uri.rawQuery != null || uri.rawFragment != null) return null
        if (!uri.rawPath.isNullOrEmpty()) return null
        return trimmed + SAMPLES_PATH
    }

    fun body(batch: List<BleHeartRateUploadQueue.Sample>, status: String?): String = buildString {
        append("{\"format\":\"hr-samples-v1\"")
        if (status != null && STATUS.matches(status)) append(",\"status\":\"").append(status).append('"')
        append(",\"samples\":[")
        batch.forEachIndexed { index, sample ->
            if (index > 0) append(',')
            append("{\"t\":").append(sample.timestampMs).append(",\"bpm\":").append(sample.bpm).append('}')
        }
        append("]}")
    }
}

internal data class BleHeartRateUploadOutcome(
    val atMs: Long,
    val success: Boolean,
    val accepted: Int = 0,
    val errorCode: String? = null,
)

internal class BleHeartRateUploader(
    /** Root address to push to, or null when syncing is off or no address is known. Read on every pump. */
    private val target: () -> String?,
    private val onOutcome: (BleHeartRateUploadOutcome) -> Unit,
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val post: (url: String, body: String) -> Int = ::httpPost,
    private val queue: BleHeartRateUploadQueue = BleHeartRateUploadQueue(),
    private val executorFactory: () -> ScheduledExecutorService = {
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "ble-heart-rate-upload").apply { isDaemon = true }
        }
    },
) {
    @Volatile private var status: String? = null
    private var executor: ScheduledExecutorService? = null

    @Synchronized
    fun start() {
        if (executor != null) return
        executor = executorFactory().also {
            it.scheduleWithFixedDelay({ runCatching { pump() } }, PUMP_SECONDS, PUMP_SECONDS, TimeUnit.SECONDS)
        }
    }

    @Synchronized
    fun stop() {
        executor?.shutdownNow()
        executor = null
        queue.clear()
    }

    fun offer(timestampMs: Long, bpm: Int) = queue.offer(timestampMs, bpm)

    fun setStatus(value: String) {
        status = value
    }

    /** Sends up to [MAX_BATCHES_PER_PUMP] batches; runs on the upload thread (or directly in tests). */
    internal fun pump() {
        val url = BleHeartRateUploadProtocol.samplesUrl(target())
        if (url == null) {
            // Off, or no usable address: never keep a backlog that would leave the phone later.
            queue.clear()
            return
        }
        repeat(MAX_BATCHES_PER_PUMP) {
            val batch = queue.batch(nowMs())
            if (batch.isEmpty()) return
            val code = try {
                post(url, BleHeartRateUploadProtocol.body(batch, status))
            } catch (_: Exception) {
                -1
            }
            when {
                code in 200..299 -> {
                    queue.acknowledge(batch)
                    onOutcome(BleHeartRateUploadOutcome(nowMs(), success = true, accepted = batch.size))
                }
                code == 400 || code == 413 -> {
                    // The computer will never take this batch; drop it instead of retrying forever.
                    queue.acknowledge(batch)
                    onOutcome(BleHeartRateUploadOutcome(nowMs(), success = false, errorCode = "rejected_$code"))
                }
                else -> {
                    queue.fail(nowMs())
                    val reason = when (code) {
                        -1 -> "network"
                        401 -> "unauthorized"
                        403 -> "forbidden"
                        else -> "http_$code"
                    }
                    onOutcome(BleHeartRateUploadOutcome(nowMs(), success = false, errorCode = reason))
                    return
                }
            }
        }
    }

    companion object {
        const val PUMP_SECONDS = 5L
        const val MAX_BATCHES_PER_PUMP = 4

        private fun httpPost(url: String, body: String): Int {
            val connection = URI(url).toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "POST"
                connection.connectTimeout = 10_000
                connection.readTimeout = 10_000
                connection.instanceFollowRedirects = false
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                val bytes = body.toByteArray(Charsets.UTF_8)
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.outputStream.use { it.write(bytes) }
                val code = connection.responseCode
                runCatching { (if (code < 400) connection.inputStream else connection.errorStream)?.use { it.readBytes() } }
                return code
            } finally {
                connection.disconnect()
            }
        }
    }
}
