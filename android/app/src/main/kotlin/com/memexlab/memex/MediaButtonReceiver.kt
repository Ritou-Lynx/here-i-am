package com.memexlab.memex

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.KeyEvent

class MediaButtonReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return

        val keyEvent = intent.keyEvent() ?: return
        Log.d(TAG, "receiver keyCode=${keyEvent.keyCode} action=${keyEvent.action}")
        MediaButtonEventDispatcher.handleKeyEvent(keyEvent)
    }

    @Suppress("DEPRECATION")
    private fun Intent.keyEvent(): KeyEvent? =
        getParcelableExtra(Intent.EXTRA_KEY_EVENT)

    private companion object {
        const val TAG = "MediaButtonBridge"
    }
}
