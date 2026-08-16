package com.memexlab.memex.channels

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.memexlab.memex.CallToForegroundBridgeReceiver
import com.memexlab.memex.R
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host channels for the global call:
 *
 * `com.memexlab.memex/audio_route`
 *   - setSpeakerphone({enabled: bool}) — route call audio to loudspeaker /
 *     earpiece (AudioManager.setSpeakerphoneOn; effective in
 *     MODE_IN_COMMUNICATION which the call session holds).
 *   - getSpeakerphone() -> bool
 *
 * `com.memexlab.memex/call_control`
 *   - show({muted, speaker, name}) — show/refresh the in-call control
 *     notification (mute / speaker / hang-up actions).
 *   - cancel() — remove it.
 *
 * Uses applicationContext only, so it can be registered on BOTH the main
 * Flutter engine (ChannelRegistrar) and the foreground-task isolate engine
 * (HereIAmApplication lifecycle listener) — the call audio pipeline runs in
 * the isolate, so it is the one that calls these methods.
 */
class AudioRouteChannelHandler(private val context: Context) {

    companion object {
        private const val TAG = "AudioRouteChannel"

        const val AUDIO_ROUTE_CHANNEL = "com.memexlab.memex/audio_route"
        const val CALL_CONTROL_CHANNEL = "com.memexlab.memex/call_control"

        fun register(flutterEngine: FlutterEngine, context: Context) {
            val handler = AudioRouteChannelHandler(context.applicationContext)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_ROUTE_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setSpeakerphone" -> {
                            val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
                                ?: true
                            handler.setSpeakerphone(enabled)
                            result.success(true)
                        }
                        "getSpeakerphone" -> result.success(handler.isSpeakerphoneOn())
                        else -> result.notImplemented()
                    }
                }
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CONTROL_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "show" -> {
                            val args = call.arguments as? Map<*, *>
                            handler.showCallControls(
                                muted = args?.get("muted") as? Boolean ?: false,
                                speaker = args?.get("speaker") as? Boolean ?: true,
                                name = args?.get("name") as? String ?: "Memex",
                            )
                            result.success(true)
                        }
                        "cancel" -> {
                            CallControlNotification.cancel(context)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    private val audioManager: AudioManager?
        get() = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    fun setSpeakerphone(enabled: Boolean) {
        try {
            audioManager?.isSpeakerphoneOn = enabled
            Log.d(TAG, "setSpeakerphoneOn=$enabled")
        } catch (e: Exception) {
            Log.w(TAG, "setSpeakerphoneOn failed: ${e.message}")
        }
    }

    fun isSpeakerphoneOn(): Boolean = audioManager?.isSpeakerphoneOn ?: false

    fun showCallControls(muted: Boolean, speaker: Boolean, name: String) {
        CallControlNotification.show(context, muted = muted, speaker = speaker, name = name)
    }
}

/**
 * In-call control notification: mute / speaker / hang-up actions that work
 * while the app is backgrounded (the CallKit CallStyle notification only
 * supports a hang-up action on Android 14+). Actions fire explicit broadcasts
 * that [CallToForegroundBridgeReceiver] forwards into the foreground-task
 * isolate, where the call session lives.
 */
object CallControlNotification {
    private const val TAG = "CallControlNotification"
    private const val CHANNEL_ID = "companion_call_controls"
    private const val NOTIFICATION_ID = 0x4841 // "HIA" hex-ish

    const val ACTION_MUTE = "ACTION_CALL_CONTROL_MUTE"
    const val ACTION_SPEAKER = "ACTION_CALL_CONTROL_SPEAKER"
    const val ACTION_HANGUP = "ACTION_CALL_CONTROL_HANGUP"

    fun show(context: Context, muted: Boolean, speaker: Boolean, name: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)

        val title = "📞 与 $name 通话中"
        val text = when {
            muted && !speaker -> "已静音 · 听筒"
            muted -> "已静音 · 外放"
            !speaker -> "通话中 · 听筒"
            else -> "通话中 · 外放"
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_here_i_am)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_HIGH)

        builder.addAction(
            if (muted) 0 else R.drawable.ic_stat_here_i_am,
            if (muted) "取消静音" else "静音",
            pendingIntent(context, ACTION_MUTE, muted = !muted),
        )
        builder.addAction(
            if (speaker) R.drawable.ic_stat_here_i_am else 0,
            if (speaker) "听筒" else "外放",
            pendingIntent(context, ACTION_SPEAKER, enabled = !speaker),
        )
        builder.addAction(
            R.drawable.ic_stat_here_i_am,
            "挂断",
            pendingIntent(context, ACTION_HANGUP),
        )

        try {
            nm.notify(NOTIFICATION_ID, builder.build())
        } catch (e: Exception) {
            Log.w(TAG, "call controls notify failed: ${e.message}")
        }
    }

    fun cancel(context: Context) {
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.w(TAG, "call controls cancel failed: ${e.message}")
        }
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "通话控制",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "通话中的静音 / 外放 / 挂断控制"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun pendingIntent(context: Context, action: String, muted: Boolean? = null, enabled: Boolean? = null): PendingIntent {
        val intent = CallToForegroundBridgeReceiver.intent(
            context,
            action,
            muted = muted,
            enabled = enabled,
        )
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getBroadcast(context, action.hashCode(), intent, flags)
    }
}
