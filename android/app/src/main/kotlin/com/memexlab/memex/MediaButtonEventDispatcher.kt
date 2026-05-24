package com.memexlab.memex

import android.util.Log
import android.view.KeyEvent

object MediaButtonEventDispatcher {
    private var onToggle: (() -> Unit)? = null
    private var onCancel: (() -> Unit)? = null

    fun configure(
        onToggle: () -> Unit,
        onCancel: () -> Unit,
    ) {
        this.onToggle = onToggle
        this.onCancel = onCancel
    }

    fun clear() {
        onToggle = null
        onCancel = null
    }

    fun handleKeyEvent(keyEvent: KeyEvent): Boolean {
        if (keyEvent.action != KeyEvent.ACTION_DOWN) {
            return true
        }

        Log.d(TAG, "media button keyCode=${keyEvent.keyCode}")
        return when (keyEvent.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_MEDIA_NEXT -> {
                onToggle?.invoke() ?: return false
                true
            }

            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                onCancel?.invoke() ?: return false
                true
            }

            else -> false
        }
    }

    private const val TAG = "MediaButtonBridge"
}
