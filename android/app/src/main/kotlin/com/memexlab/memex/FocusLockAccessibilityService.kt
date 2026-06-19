package com.memexlab.memex

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class FocusLockAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "MemexFocusLock"
        private const val PREFS = "memex_focus_lock"
        private const val KEY_LOCKED = "locked"
        private const val KEY_UNTIL_MS = "until_ms"
        private const val RETURN_DEBOUNCE_MS = 1200L

        @Volatile
        private var locked = false

        @Volatile
        private var untilMs: Long = 0L

        @Volatile
        private var serviceConnected = false

        fun setLocked(context: Context, enabled: Boolean, until: Long?) {
            locked = enabled
            untilMs = until ?: 0L
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_LOCKED, enabled)
                .putLong(KEY_UNTIL_MS, untilMs)
                .apply()
        }

        fun isLocked(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            locked = prefs.getBoolean(KEY_LOCKED, locked)
            untilMs = prefs.getLong(KEY_UNTIL_MS, untilMs)
            if (locked && untilMs > 0L && System.currentTimeMillis() > untilMs) {
                setLocked(context, false, null)
            }
            return locked
        }

        fun isServiceConnected(): Boolean = serviceConnected
    }

    private val handler = Handler(Looper.getMainLooper())
    private var returning = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceConnected = true
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        serviceConnected = false
        Log.d(TAG, "Accessibility service unbound")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        serviceConnected = false
        Log.d(TAG, "Accessibility service destroyed")
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            handleAccessibilityEvent(event)
        } catch (error: Throwable) {
            Log.e(TAG, "Focus lock event handling failed", error)
        }
    }

    private fun handleAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        if (!isLocked(this)) return

        val packageName = event.packageName?.toString() ?: return
        val className = event.className?.toString().orEmpty()
        if (packageName == applicationContext.packageName) {
            returning = false
            return
        }
        if (shouldIgnorePackage(packageName, className)) {
            Log.d(TAG, "Allowed window while locked: $packageName/$className")
            return
        }
        if (returning) return
        returning = true
        Log.d(TAG, "Returning from $packageName/$className")
        returnToApp()
    }

    override fun onInterrupt() = Unit

    private fun shouldIgnorePackage(packageName: String, className: String): Boolean {
        if (packageName == "android") return true
        if (packageName == "com.android.systemui") {
            return isAllowedSystemUiWindow(className)
        }
        return isInputMethodWindow(packageName, className)
    }

    private fun returnToApp() {
        handler.removeCallbacksAndMessages(null)
        val launchIntent =
            packageManager.getLaunchIntentForPackage(applicationContext.packageName)
                ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        )
        startActivity(launchIntent)
        handler.postDelayed({
            returning = false
        }, RETURN_DEBOUNCE_MS)
    }

    private fun isAllowedSystemUiWindow(className: String): Boolean {
        val normalized = className.lowercase()
        return normalized.contains("notification") ||
            normalized.contains("shade") ||
            normalized.contains("quicksettings") ||
            normalized.contains("statusbar") ||
            normalized.contains("volume")
    }

    private fun isInputMethodWindow(packageName: String, className: String): Boolean {
        val normalizedPackage = packageName.lowercase()
        val normalizedClass = className.lowercase()
        return currentInputMethodPackages().contains(packageName) ||
            normalizedClass.contains("inputmethod") ||
            normalizedClass.contains("softinput") ||
            normalizedClass.contains("keyboard") ||
            normalizedPackage.contains("inputmethod") ||
            normalizedPackage.contains("keyboard") ||
            normalizedPackage.contains("honeyboard") ||
            normalizedPackage.contains("wetype")
    }

    private fun currentInputMethodPackages(): Set<String> {
        return try {
            val resolver = contentResolver
            val values = listOfNotNull(
                Settings.Secure.getString(resolver, Settings.Secure.DEFAULT_INPUT_METHOD),
                Settings.Secure.getString(resolver, Settings.Secure.ENABLED_INPUT_METHODS)
            )
            values
                .flatMap { it.split(':', ';') }
                .mapNotNull { value ->
                    val trimmed = value.trim()
                    if (trimmed.isEmpty()) {
                        null
                    } else {
                        trimmed.substringBefore('/').takeIf { it.isNotBlank() }
                    }
                }
                .toSet()
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to read input method packages", error)
            emptySet()
        }
    }
}
