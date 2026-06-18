package com.memexlab.memex

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

class FocusLockAccessibilityService : AccessibilityService() {
    companion object {
        private const val PREFS = "memex_focus_lock"
        private const val KEY_LOCKED = "locked"
        private const val KEY_UNTIL_MS = "until_ms"
        private const val RETURN_DELAY_MS = 350L

        @Volatile
        private var locked = false

        @Volatile
        private var untilMs: Long = 0L

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
    }

    private val handler = Handler(Looper.getMainLooper())
    private var returning = false

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        if (!isLocked(this)) return

        val packageName = event.packageName?.toString() ?: return
        if (packageName == applicationContext.packageName) {
            returning = false
            return
        }
        if (returning) return
        returning = true
        performGlobalAction(GLOBAL_ACTION_HOME)
        handler.postDelayed({
            val launchIntent =
                packageManager.getLaunchIntentForPackage(applicationContext.packageName)
                    ?: Intent(this, MainActivity::class.java)
            launchIntent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            startActivity(launchIntent)
        }, RETURN_DELAY_MS)
    }

    override fun onInterrupt() = Unit
}
