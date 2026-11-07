package com.memexlab.bedwatch

import java.net.URI
import java.util.Base64

/** Pan/tilt angles in degrees for the ESP32 mount. */
data class Aim(val pan: Int, val tilt: Int) {
    init { require(pan in 0..180 && tilt in 0..180) }
}

/** CAM1 on-demand look settings. Addresses and tokens stay on this phone only. */
data class LookConfig(
    val enabled: Boolean = false,
    val server: String = "",
    val token: String = "",
    val gimbal: String = "",
    val gimbalToken: String = "",
    val positions: Map<String, Aim> = emptyMap(),
    val pausedUntil: Long = 0,
    val invertPan: Boolean = false,
    val invertTilt: Boolean = false,
    val fovDegrees: Float = 70f,
) {
    init { require(fovDegrees.isFinite() && fovDegrees in 20f..140f) }
    val hasGimbal: Boolean get() = gimbal.isNotBlank()
}

/** One on-demand frame: JPEG bytes in memory plus the same numeric features the night judge uses. */
class Snapshot(val jpeg: ByteArray, val features: FrameFeatures, val faceX: Float?, val faceY: Float?)

data class LookRequest(val id: String, val position: String)

/** Pure helpers for the look channel: address checks, preset parsing, request/meta encoding, recentring. */
object LookProtocol {
    const val CURRENT = "current"
    const val FIND_ME = "find_me"

    fun isPrivateIpv4(host: String): Boolean {
        if (!Regex("^\\d{1,3}(\\.\\d{1,3}){3}$").matches(host)) return false
        val p = host.split('.').map { it.toInt() }
        if (p.any { it > 255 }) return false
        return p[0] == 10 || (p[0] == 172 && p[1] in 16..31) || (p[0] == 192 && p[1] == 168)
    }

    /** Only plain http to a private IPv4 literal on the home LAN; returns the base without a trailing slash. */
    fun lanBase(url: String): String {
        val text = url.trim()
        val uri = URI(text)
        require(uri.scheme == "http" && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null)
        val host = uri.host ?: throw IllegalArgumentException("host")
        require(isPrivateIpv4(host)) { "只允许家里局域网地址" }
        require(uri.rawPath.isNullOrEmpty() || uri.rawPath == "/")
        require(uri.port == -1 || uri.port in 1..65535)
        return "http://" + host + (if (uri.port == -1) "" else ":" + uri.port)
    }

    fun validName(name: String): Boolean = name.length in 1..16 && name != CURRENT && name != FIND_ME &&
        name.none { it.isWhitespace() || it.isISOControl() || it == ',' || it == ';' || it == '=' }

    /** "床=90,70;书桌=150,85" -> ordered map. Blank text means no presets. */
    fun parsePositions(text: String): LinkedHashMap<String, Aim> {
        val out = linkedMapOf<String, Aim>()
        for (part in text.split(';').map { it.trim() }.filter { it.isNotEmpty() }) {
            val eq = part.indexOf('=')
            require(eq > 0) { "预置位格式：名字=左右角,上下角" }
            val name = part.substring(0, eq).trim()
            val angles = part.substring(eq + 1).split(',').map { it.trim().toInt() }
            require(validName(name) && angles.size == 2 && name !in out)
            out[name] = Aim(angles[0], angles[1])
        }
        require(out.size <= 8)
        return out
    }

    fun formatPositions(map: Map<String, Aim>): String = map.entries.joinToString(";") { "${it.key}=${it.value.pan},${it.value.tilt}" }

    private fun jsonString(value: String): String {
        val sb = StringBuilder("\"")
        for (c in value) when {
            c == '"' -> sb.append("\\\"")
            c == '\\' -> sb.append("\\\\")
            c < ' ' -> sb.append(String.format("\\u%04x", c.code))
            else -> sb.append(c)
        }
        return sb.append('"').toString()
    }

    private fun jsonUnescape(raw: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < raw.length) {
            val c = raw[i]
            if (c != '\\') { sb.append(c); i++; continue }
            require(i + 1 < raw.length)
            when (val e = raw[i + 1]) {
                '"', '\\', '/' -> { sb.append(e); i += 2 }
                'n' -> { sb.append('\n'); i += 2 }
                't' -> { sb.append('\t'); i += 2 }
                'r' -> { sb.append('\r'); i += 2 }
                'b' -> { sb.append('\b'); i += 2 }
                'f' -> { sb.append('\u000c'); i += 2 }
                'u' -> { require(i + 6 <= raw.length); sb.append(raw.substring(i + 2, i + 6).toInt(16).toChar()); i += 6 }
                else -> throw IllegalArgumentException("escape")
            }
        }
        return sb.toString()
    }

    /** Parses the server's {"id":"<24 hex>","position":"..."}; anything else is rejected. */
    fun parseRequest(json: String): LookRequest {
        val id = Regex("\"id\"\\s*:\\s*\"([0-9a-f]{24})\"").find(json)?.groupValues?.get(1)
            ?: throw IllegalArgumentException("id")
        val raw = Regex("\"position\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.){1,64})\"").find(json)?.groupValues?.get(1)
            ?: throw IllegalArgumentException("position")
        val position = jsonUnescape(raw)
        require(position == CURRENT || position == FIND_ME || validName(position))
        return LookRequest(id, position)
    }

    /** Small numeric description of the frame, base64 so the header stays ASCII. No pixels, no coordinates. */
    fun meta(face: Boolean?, eyesOpen: Float?, luma: Float?, found: Boolean?, reached: String?): String {
        val fields = mutableListOf<String>()
        face?.let { fields += "\"face\":$it" }
        eyesOpen?.takeIf { it.isFinite() }?.let { fields += "\"eyes_open\":${round2(it)}" }
        luma?.takeIf { it.isFinite() }?.let { fields += "\"luma\":${round2(it)}" }
        found?.let { fields += "\"found\":$it" }
        reached?.let { fields += "\"reached\":${jsonString(it.take(24))}" }
        return Base64.getEncoder().encodeToString("{${fields.joinToString(",")}}".toByteArray(Charsets.UTF_8))
    }
    private fun round2(v: Float): String = String.format(java.util.Locale.ROOT, "%.2f", v)

    /**
     * Turn so the face centre (0..1 in the upright frame) moves to the middle.
     * One step only; the vertical field of view is taken as 3/4 of the horizontal one.
     */
    fun recenter(aim: Aim, faceX: Float, faceY: Float, fovDegrees: Float, invertPan: Boolean, invertTilt: Boolean): Aim {
        require(faceX.isFinite() && faceY.isFinite())
        val dx = (faceX.coerceIn(0f, 1f) - 0.5f) * fovDegrees
        val dy = (faceY.coerceIn(0f, 1f) - 0.5f) * fovDegrees * 0.75f
        val pan = aim.pan + Math.round(if (invertPan) dx else -dx)
        val tilt = aim.tilt + Math.round(if (invertTilt) -dy else dy)
        return Aim(pan.coerceIn(0, 180), tilt.coerceIn(0, 180))
    }
}
