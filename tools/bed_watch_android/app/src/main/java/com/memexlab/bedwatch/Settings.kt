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
    var lastPush: Long?
        get() = prefs.getLong("lastPush", -1).takeIf { it >= 0 }
        set(value) { check(prefs.edit().putLong("lastPush", value ?: -1).commit()) }
}

fun Context.frameLog(): JsonlLog = JsonlLog(File(filesDir, "bedwatch"))
