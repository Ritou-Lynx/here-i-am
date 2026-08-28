package com.memexlab.memex.ble

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedWriter
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.LocalDate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

data class SelectedHeartRateDevice(
    val userKey: String,
    val address: String,
    val name: String?,
    val enabled: Boolean,
)

object BleHeartRateEventBus {
    private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()

    fun add(listener: (Map<String, Any?>) -> Unit) = listeners.add(listener)
    fun remove(listener: (Map<String, Any?>) -> Unit) = listeners.remove(listener)
    fun emit(event: Map<String, Any?>) = listeners.forEach { it(event) }
}

/** App-private, user-isolated configuration, snapshot and append-only telemetry. */
class BleHeartRateStore(private val context: Context) {
    companion object {
        private const val PREFS = "ble_heart_rate_gateway_v1"
        private const val ACTIVE_USER = "active_user_key"
        private const val RETENTION_DAYS = 14L
        private const val MAX_DIAGNOSTICS = 40
        private const val FLUSH_INTERVAL_MS = 7_000L
        private const val SNAPSHOT_PERSIST_INTERVAL_MS = 5_000L

        fun userKey(userId: String): String {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(userId.toByteArray(StandardCharsets.UTF_8))
            return digest.take(16).joinToString("") { "%02x".format(it) }
        }
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val ioExecutorDelegate = lazy {
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "ble-heart-rate-io").apply { isDaemon = true }
        }
    }
    private val ioExecutor by ioExecutorDelegate
    private val snapshotCache = ConcurrentHashMap<String, String>()
    private val lastSnapshotPersistAt = mutableMapOf<String, Long>()
    private var writer: BufferedWriter? = null
    private var writerUserKey: String? = null
    private var writerDate: LocalDate? = null
    private var lastFlushAtMs = 0L

    @Synchronized
    fun select(userId: String, address: String, name: String?): SelectedHeartRateDevice {
        val key = userKey(userId)
        val config = SelectedHeartRateDevice(key, address, name?.take(120), true)
        prefs.edit()
            .putString(ACTIVE_USER, key)
            .putString(configKey(key), JSONObject().apply {
                put("address", config.address)
                put("name", config.name)
                put("enabled", true)
            }.toString())
            .apply()
        prefs.edit().remove(snapshotKey(key)).apply()
        snapshotCache.remove(key)
        updateStatus(key, "connecting", "selected", configured = true, enabled = true)
        return config
    }

    @Synchronized
    fun activeConfig(): SelectedHeartRateDevice? =
        prefs.getString(ACTIVE_USER, null)?.let(::loadConfig)

    @Synchronized
    fun configForUser(userId: String): SelectedHeartRateDevice? = loadConfig(userKey(userId))

    @Synchronized
    fun setEnabled(userKey: String, enabled: Boolean) {
        val config = loadConfig(userKey) ?: return
        prefs.edit().putString(configKey(userKey), JSONObject().apply {
            put("address", config.address)
            put("name", config.name)
            put("enabled", enabled)
        }.toString()).apply()
        if (enabled) prefs.edit().putString(ACTIVE_USER, userKey).apply()
    }

    @Synchronized
    fun forget(userKey: String) {
        if (prefs.getString(ACTIVE_USER, null) == userKey) {
            prefs.edit().remove(ACTIVE_USER).apply()
        }
        snapshotCache.remove(userKey)
        ioExecutor.execute {
            if (writerUserKey == userKey) closeWriterOnIo()
            prefs.edit()
                .remove(configKey(userKey))
                .remove(snapshotKey(userKey))
                .remove(diagnosticsKey(userKey))
                .commit()
            lastSnapshotPersistAt.remove(userKey)
        }
        emitSnapshot(userKey, baseSnapshot(userKey, "unconfigured", "forgotten", false, false))
    }

    @Synchronized
    fun updateStatus(
        userKey: String,
        status: String,
        reason: String? = null,
        retryAtMs: Long? = null,
        configured: Boolean? = null,
        enabled: Boolean? = null,
        recordGap: Boolean = false,
    ) {
        val previous = readSnapshotJson(userKey)
        val config = loadConfig(userKey)
        val snapshot = JSONObject(previous?.toString() ?: "{}")
        snapshot.put("status", status)
        snapshot.put("reason", reason)
        snapshot.put("updatedAtMs", System.currentTimeMillis())
        snapshot.put("configured", configured ?: (config != null))
        snapshot.put("enabled", enabled ?: (config?.enabled == true))
        snapshot.put("deviceName", config?.name)
        snapshot.put("deviceId", config?.address)
        snapshot.put("retryAtMs", retryAtMs)
        cacheSnapshot(userKey, snapshot)
        addDiagnostic(userKey, status, reason)
        emitSnapshot(userKey, snapshot)
        val snapshotText = snapshot.toString()
        ioExecutor.execute {
            persistSnapshotOnIo(userKey, snapshotText, force = true)
            if (recordGap) appendStatusEventOnIo(userKey, status, reason)
            flushWriterOnIo(force = true)
        }
    }

    @Synchronized
    fun recordSample(userKey: String, measurement: HeartRateMeasurement, timestampMs: Long) {
        val previous = readSnapshotJson(userKey)
        val rrSeen = (previous?.optBoolean("rrSeen", false) == true) ||
            measurement.rrIntervalsSeconds.isNotEmpty()
        val sample = JSONObject().apply {
            put("timestampMs", timestampMs)
            put("bpm", measurement.bpm)
            put("contactSupported", measurement.contactSupported)
            put("contactDetected", measurement.contactDetected)
            put("energyExpended", measurement.energyExpended)
            put("rrIntervalsSeconds", JSONArray(measurement.rrIntervalsSeconds))
        }
        val config = loadConfig(userKey)
        val snapshot = JSONObject(previous?.toString() ?: "{}").apply {
            put("status", "live")
            put("reason", JSONObject.NULL)
            put("updatedAtMs", timestampMs)
            put("configured", config != null)
            put("enabled", config?.enabled == true)
            put("deviceName", config?.name)
            put("deviceId", config?.address)
            put("retryAtMs", JSONObject.NULL)
            put("rrSeen", rrSeen)
            put("lastSample", sample)
        }
        cacheSnapshot(userKey, snapshot)
        emitSnapshot(userKey, snapshot)
        val snapshotText = snapshot.toString()
        val line = JSONObject().apply {
            put("type", "sample")
            put("timestampMs", timestampMs)
            put("bpm", measurement.bpm)
            put("contactSupported", measurement.contactSupported)
            put("contactDetected", measurement.contactDetected)
            put("energyExpended", measurement.energyExpended)
            put("rrIntervalsSeconds", JSONArray(measurement.rrIntervalsSeconds))
        }.toString()
        ioExecutor.execute {
            appendJsonLineOnIo(userKey, line)
            persistSnapshotOnIo(userKey, snapshotText, force = false)
            flushWriterOnIo(force = false)
        }
    }

    @Synchronized
    fun snapshot(userId: String): Map<String, Any?> {
        val key = userKey(userId)
        val config = loadConfig(key)
        val json = readSnapshotJson(key) ?: baseSnapshot(
            key,
            if (config == null) "unconfigured" else if (config.enabled) "connecting" else "stopped",
            null,
            config != null,
            config?.enabled == true,
        )
        if (json.optString("status") == "live") {
            val lastMs = json.optJSONObject("lastSample")?.optLong("timestampMs", 0L) ?: 0L
            if (lastMs > 0L && System.currentTimeMillis() - lastMs > 15_000L) {
                json.put("status", "stale")
                json.put("reason", "sample_timeout")
            }
        }
        return json.toMap()
    }

    @Synchronized
    fun diagnostics(userId: String): List<Map<String, Any?>> {
        val array = readDiagnostics(userKey(userId))
        return (0 until array.length()).mapNotNull { array.optJSONObject(it)?.toMap() }
    }

    fun close() {
        if (!ioExecutorDelegate.isInitialized()) return
        val snapshots = snapshotCache.toMap()
        ioExecutor.execute {
            snapshots.forEach { (userKey, snapshotText) ->
                persistSnapshotOnIo(userKey, snapshotText, force = true)
            }
            flushWriterOnIo(force = true)
            closeWriterOnIo()
        }
        ioExecutor.shutdown()
        runCatching { ioExecutor.awaitTermination(5, TimeUnit.SECONDS) }
    }

    private fun loadConfig(key: String): SelectedHeartRateDevice? {
        val raw = prefs.getString(configKey(key), null) ?: return null
        return runCatching {
            val json = JSONObject(raw)
            SelectedHeartRateDevice(
                userKey = key,
                address = json.getString("address"),
                name = json.optString("name").takeIf { it.isNotBlank() && it != "null" },
                enabled = json.optBoolean("enabled", false),
            )
        }.getOrNull()
    }

    private fun baseSnapshot(
        userKey: String,
        status: String,
        reason: String?,
        configured: Boolean,
        enabled: Boolean,
    ): JSONObject {
        val config = loadConfig(userKey)
        return JSONObject().apply {
            put("status", status)
            put("reason", reason)
            put("configured", configured)
            put("enabled", enabled)
            put("deviceName", config?.name)
            put("deviceId", config?.address)
            put("updatedAtMs", System.currentTimeMillis())
            put("rrSeen", false)
        }
    }

    private fun cacheSnapshot(userKey: String, snapshot: JSONObject) {
        snapshotCache[userKey] = snapshot.toString()
    }

    private fun readSnapshotJson(userKey: String): JSONObject? =
        (snapshotCache[userKey] ?: prefs.getString(snapshotKey(userKey), null))
            ?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun emitSnapshot(userKey: String, snapshot: JSONObject) {
        BleHeartRateEventBus.emit(
            mapOf(
                "type" to "snapshot",
                "userKey" to userKey,
                "snapshot" to snapshot.toMap(),
            ),
        )
    }

    private fun appendStatusEventOnIo(userKey: String, status: String, reason: String?) {
        appendJsonLineOnIo(userKey, JSONObject().apply {
            put("type", "status")
            put("timestampMs", System.currentTimeMillis())
            put("status", status)
            put("reason", reason)
        }.toString())
    }

    private fun addDiagnostic(userKey: String, status: String, reason: String?) {
        val current = readDiagnostics(userKey)
        current.put(JSONObject().apply {
            put("timestampMs", System.currentTimeMillis())
            put("status", status)
            put("reason", reason)
        })
        val trimmed = JSONArray()
        val start = (current.length() - MAX_DIAGNOSTICS).coerceAtLeast(0)
        for (index in start until current.length()) trimmed.put(current.get(index))
        prefs.edit().putString(diagnosticsKey(userKey), trimmed.toString()).apply()
    }

    private fun readDiagnostics(userKey: String): JSONArray =
        prefs.getString(diagnosticsKey(userKey), null)
            ?.let { runCatching { JSONArray(it) }.getOrNull() }
            ?: JSONArray()

    private fun appendJsonLineOnIo(userKey: String, jsonLine: String) {
        val date = LocalDate.now()
        if (writer == null || writerUserKey != userKey || writerDate != date) {
            closeWriterOnIo()
            val directory = File(context.filesDir, "ble_heart_rate/$userKey")
            directory.mkdirs()
            prune(directory, date)
            writer = BufferedWriter(
                OutputStreamWriter(
                    FileOutputStream(File(directory, "$date.jsonl"), true),
                    StandardCharsets.UTF_8,
                ),
            )
            writerUserKey = userKey
            writerDate = date
            lastFlushAtMs = System.currentTimeMillis()
        }
        writer?.apply {
            write(jsonLine)
            newLine()
        }
    }

    private fun persistSnapshotOnIo(userKey: String, snapshotText: String, force: Boolean) {
        val now = System.currentTimeMillis()
        val last = lastSnapshotPersistAt[userKey] ?: 0L
        if (!force && now - last < SNAPSHOT_PERSIST_INTERVAL_MS) return
        prefs.edit().putString(snapshotKey(userKey), snapshotText).commit()
        lastSnapshotPersistAt[userKey] = now
    }

    private fun flushWriterOnIo(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lastFlushAtMs < FLUSH_INTERVAL_MS) return
        writer?.flush()
        lastFlushAtMs = now
    }

    private fun prune(directory: File, today: LocalDate) {
        directory.listFiles { file -> file.extension == "jsonl" }?.forEach { file ->
            val date = runCatching { LocalDate.parse(file.nameWithoutExtension) }.getOrNull()
            if (date != null && date.isBefore(today.minusDays(RETENTION_DAYS - 1))) file.delete()
        }
    }

    private fun closeWriterOnIo() {
        runCatching { writer?.flush() }
        runCatching { writer?.close() }
        writer = null
        writerUserKey = null
        writerDate = null
        lastFlushAtMs = 0L
    }

    private fun configKey(userKey: String) = "config_$userKey"
    private fun snapshotKey(userKey: String) = "snapshot_$userKey"
    private fun diagnosticsKey(userKey: String) = "diagnostics_$userKey"
}

private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { key ->
    when (val value = get(key)) {
        JSONObject.NULL -> null
        is JSONObject -> value.toMap()
        is JSONArray -> value.toList()
        else -> value
    }
}

private fun JSONArray.toList(): List<Any?> = (0 until length()).map { index ->
    when (val value = get(index)) {
        JSONObject.NULL -> null
        is JSONObject -> value.toMap()
        is JSONArray -> value.toList()
        else -> value
    }
}
