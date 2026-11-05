package com.memexlab.memex.ble

import android.content.Context

/**
 * HR1 sync settings in app-private SharedPreferences. Only addresses and outcomes live here;
 * there is no credential (the computer trusts the phone's Tailscale login).
 * The derived address comes from the Core sync address (same computer, port 8447) and is pushed
 * by Flutter; an override typed in settings wins over it.
 */
internal class BleHeartRateUploadSettings(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun enabled(): Boolean = prefs.getBoolean(KEY_ENABLED, true)

    fun effectiveBaseUrl(): String? {
        if (!enabled()) return null
        return prefs.getString(KEY_OVERRIDE, null)?.takeIf { it.isNotBlank() }
            ?: prefs.getString(KEY_DERIVED, null)?.takeIf { it.isNotBlank() }
    }

    /** Applies only the keys present in [args]; returns false when an address is not a plain HTTPS root. */
    fun configure(args: Map<*, *>): Boolean {
        val editor = prefs.edit()
        for (key in listOf(KEY_DERIVED, KEY_OVERRIDE)) {
            if (!args.containsKey(key)) continue
            val value = (args[key] as? String)?.trim()?.trimEnd('/')
            if (value.isNullOrEmpty()) {
                editor.remove(key)
            } else {
                if (BleHeartRateUploadProtocol.samplesUrl(value) == null) return false
                editor.putString(key, value)
            }
        }
        (args[KEY_ENABLED] as? Boolean)?.let { editor.putBoolean(KEY_ENABLED, it) }
        editor.apply()
        return true
    }

    fun record(outcome: BleHeartRateUploadOutcome) {
        val editor = prefs.edit()
        if (outcome.success) {
            editor.putLong(KEY_LAST_SUCCESS, outcome.atMs).remove(KEY_LAST_ERROR).remove(KEY_LAST_ERROR_AT)
        } else {
            editor.putString(KEY_LAST_ERROR, outcome.errorCode ?: "unknown").putLong(KEY_LAST_ERROR_AT, outcome.atMs)
        }
        editor.apply()
    }

    fun status(): Map<String, Any?> = mapOf(
        KEY_ENABLED to enabled(),
        KEY_DERIVED to prefs.getString(KEY_DERIVED, null),
        KEY_OVERRIDE to prefs.getString(KEY_OVERRIDE, null),
        "effectiveUrl" to effectiveBaseUrl(),
        KEY_LAST_SUCCESS to prefs.getLong(KEY_LAST_SUCCESS, 0L).takeIf { it > 0L },
        KEY_LAST_ERROR to prefs.getString(KEY_LAST_ERROR, null),
        KEY_LAST_ERROR_AT to prefs.getLong(KEY_LAST_ERROR_AT, 0L).takeIf { it > 0L },
    )

    companion object {
        private const val PREFS = "ble_heart_rate_upload"
        const val KEY_ENABLED = "enabled"
        const val KEY_DERIVED = "derivedUrl"
        const val KEY_OVERRIDE = "overrideUrl"
        private const val KEY_LAST_SUCCESS = "lastSuccessAtMs"
        private const val KEY_LAST_ERROR = "lastErrorCode"
        private const val KEY_LAST_ERROR_AT = "lastErrorAtMs"
    }
}
