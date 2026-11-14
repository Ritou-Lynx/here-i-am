package com.memexlab.bedwatch

import android.content.Context
import java.io.File
import java.time.LocalTime

data class WatchSettings(
    val enabled: Boolean = false,
    val start: LocalTime = LocalTime.of(23, 30),
    val end: LocalTime = LocalTime.of(6, 0),
    val intervalSeconds: Int = 60,
    val front: Boolean = false,
    val thresholds: Thresholds = Thresholds(),
    val cooldownMinutes: Int = 10,
    val server: String = "",
    val topic: String = "",
    val releaseUntil: Long = 0,
) {
    init { require(intervalSeconds in 30..300 && cooldownMinutes in 1..1440) }
}

class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("bedwatch", Context.MODE_PRIVATE)
    fun read(): WatchSettings = WatchSettings(
        enabled = prefs.getBoolean("enabled", false),
        start = LocalTime.parse(prefs.getString("start", "23:30")),
        end = LocalTime.parse(prefs.getString("end", "06:00")),
        intervalSeconds = prefs.getInt("interval", 60), front = prefs.getBoolean("front", false),
        thresholds = Thresholds(prefs.getFloat("open", .6f), prefs.getFloat("glow", 1.6f),
            prefs.getFloat("closed", .3f), prefs.getFloat("dimGlow", 1.3f), prefs.getFloat("dark", 40f)),
        cooldownMinutes = prefs.getInt("cooldown", 10),
        server = prefs.getString("server", "")!!, topic = prefs.getString("topic", "")!!,
        releaseUntil = prefs.getLong("release", 0),
    )
    fun write(s: WatchSettings) {
        check(prefs.edit().putBoolean("enabled", s.enabled).putString("start", s.start.toString())
            .putString("end", s.end.toString()).putInt("interval", s.intervalSeconds).putBoolean("front", s.front)
            .putFloat("open", s.thresholds.open).putFloat("glow", s.thresholds.glow)
            .putFloat("closed", s.thresholds.closed).putFloat("dimGlow", s.thresholds.dimGlow)
            .putFloat("dark", s.thresholds.dark).putInt("cooldown", s.cooldownMinutes)
            .putString("server", s.server).putString("topic", s.topic).putLong("release", s.releaseUntil).commit())
    }
    fun readLook(): LookConfig = LookConfig(
        enabled = prefs.getBoolean("look_enabled", false),
        server = prefs.getString("look_server", "")!!, token = prefs.getString("look_token", "")!!,
        gimbal = prefs.getString("look_gimbal", "")!!, gimbalToken = prefs.getString("look_gimbal_token", "")!!,
        positions = runCatching { LookProtocol.parsePositions(prefs.getString("look_positions", "")!!) }.getOrDefault(linkedMapOf()),
        pausedUntil = prefs.getLong("look_paused_until", 0),
        invertPan = prefs.getBoolean("look_invert_pan", false), invertTilt = prefs.getBoolean("look_invert_tilt", false),
        fovDegrees = prefs.getFloat("look_fov", 70f),
    )
    fun writeLook(l: LookConfig) {
        check(prefs.edit().putBoolean("look_enabled", l.enabled).putString("look_server", l.server)
            .putString("look_token", l.token).putString("look_gimbal", l.gimbal).putString("look_gimbal_token", l.gimbalToken)
            .putString("look_positions", LookProtocol.formatPositions(l.positions)).putLong("look_paused_until", l.pausedUntil)
            .putBoolean("look_invert_pan", l.invertPan).putBoolean("look_invert_tilt", l.invertTilt)
            .putFloat("look_fov", l.fovDegrees).commit())
    }
    var lookPausedUntil: Long
        get() = prefs.getLong("look_paused_until", 0)
        set(value) { check(prefs.edit().putLong("look_paused_until", value).commit()) }
    /** The foreground service is needed for night monitoring, on-demand looks, or both. */
    fun serviceWanted(): Boolean = read().enabled || readLook().enabled
    var lastPush: Long?
        get() = prefs.getLong("lastPush", -1).takeIf { it >= 0 }
        set(value) { check(prefs.edit().putLong("lastPush", value ?: -1).commit()) }
}

fun Context.frameLog(): JsonlLog = JsonlLog(File(filesDir, "bedwatch"))
