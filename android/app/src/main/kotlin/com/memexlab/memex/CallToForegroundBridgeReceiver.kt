package com.memexlab.memex

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.pravera.flutter_foreground_task.service.ForegroundService

/**
 * Bridges the CallKit plugin's hang-up broadcast into the foreground-task
 * isolate, which hosts the continuous global call session ([CallVoiceSession]).
 *
 * The plugin's own `sendEventFlutter` reaches the main isolate only; when the
 * app is backgrounded the main engine is suspended and the hang-up button on
 * the CallKit ongoing notification would otherwise leave the call audio
 * running forever. This receiver turns the plugin's `ACTION_CALL_ENDED` into
 * a `call_ended` task message that the isolate handles by tearing down the
 * mic / TTS / VoIP session and clearing the CallKit session itself.
 */
class CallToForegroundBridgeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallToForegroundBridge"

        /** Action the plugin fires when a CallKit call ends. */
        fun action(context: Context) =
            "${context.packageName}.ACTION_CALL_ENDED_TO_BACKGROUND"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != action(context)) return
        Log.d(TAG, "call ended broadcast → foreground-task isolate")
        try {
            ForegroundService.sendData(mapOf("type" to "call_ended"))
        } catch (e: Exception) {
            Log.w(TAG, "sendData failed: ${e.message}")
        }
    }
}
