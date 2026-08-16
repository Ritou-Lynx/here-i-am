package com.memexlab.memex

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.pravera.flutter_foreground_task.service.ForegroundService

/**
 * Bridges the CallKit plugin's hang-up broadcast and the in-call control
 * notification actions into the foreground-task isolate, which hosts the
 * continuous global call session ([CallVoiceSession]).
 *
 * The plugin's own `sendEventFlutter` reaches the main isolate only; when the
 * app is backgrounded the main engine is suspended and the hang-up button on
 * the CallKit ongoing notification would otherwise leave the call audio
 * running forever. This receiver turns those broadcasts/actions into task
 * messages the isolate handles (tear down mic/TTS/VoIP, mute, speaker route).
 */
class CallToForegroundBridgeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallToForegroundBridge"

        const val EXTRA_MUTED = "muted"
        const val EXTRA_ENABLED = "enabled"

        /** Intent builder shared by the plugin bridge + call-control actions. */
        fun intent(context: Context, suffix: String, muted: Boolean? = null, enabled: Boolean? = null): Intent {
            val action = "${context.packageName}.$suffix"
            return Intent(action).setPackage(context.packageName).apply {
                if (muted != null) putExtra(EXTRA_MUTED, muted)
                if (enabled != null) putExtra(EXTRA_ENABLED, enabled)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val packagePrefix = "${context.packageName}."

        when {
            action == "${packagePrefix}ACTION_CALL_ENDED_TO_BACKGROUND" ||
                action == "${packagePrefix}ACTION_CALL_CONTROL_HANGUP" -> {
                Log.d(TAG, "call ended → foreground-task isolate")
                sendToTask(mapOf("type" to "call_ended"))
            }
            action == "${packagePrefix}ACTION_CALL_CONTROL_MUTE" -> {
                val muted = intent.getBooleanExtra(EXTRA_MUTED, true)
                Log.d(TAG, "call mute=$muted → foreground-task isolate")
                sendToTask(mapOf("type" to "call_mute", "muted" to muted))
            }
            action == "${packagePrefix}ACTION_CALL_CONTROL_SPEAKER" -> {
                val enabled = intent.getBooleanExtra(EXTRA_ENABLED, true)
                Log.d(TAG, "call speaker=$enabled → foreground-task isolate")
                sendToTask(mapOf("type" to "call_speaker", "enabled" to enabled))
            }
        }
    }

    private fun sendToTask(data: Map<String, Any>) {
        try {
            ForegroundService.sendData(data)
        } catch (e: Exception) {
            Log.w(TAG, "sendData failed: ${e.message}")
        }
    }
}
