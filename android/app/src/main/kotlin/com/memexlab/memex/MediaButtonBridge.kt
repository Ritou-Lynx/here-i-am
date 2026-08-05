package com.memexlab.memex

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.KeyEvent
import com.pravera.flutter_foreground_task.service.ForegroundService
import io.flutter.plugin.common.MethodChannel

/**
 * Process-wide media-button (headset key) takeover.
 *
 * The MediaSession is process-scoped (application context) so it survives
 * MainActivity destruction: when the app is backgrounded the system may
 * destroy the Activity (memory pressure, recent-apps swipe). Releasing the
 * session there would stop headset keys from ever reaching us again.
 *
 * Event routing (two paths):
 *  - While the Flutter engine is alive (channel attached by MainActivity),
 *    events go to the main isolate, where MediaButtonService runs the owner
 *    stack (chat screen first, then VoiceSessionRouter).
 *  - If the engine is gone (Activity destroyed / app swiped away), events are
 *    forwarded straight to the foreground-task isolate via
 *    [ForegroundService.sendData], which drives BackgroundVoiceSession.
 */
object MediaButtonBridge {
    private const val TAG = "MediaButtonBridge"

    @Volatile
    private var channel: MethodChannel? = null

    private var mediaSession: MediaSessionCompat? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var receiverComponent: ComponentName? = null
    private var isBackground = false

    private val focusChangeListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            Log.d(TAG, "audio focus changed: $change")
        }

    /**
     * Switch between foreground (MAY_DUCK - other music keeps playing) and
     * background (GAIN - win key routing from music apps) focus modes.
     */
    fun setAppBackground(background: Boolean) {
        if (isBackground == background) return
        isBackground = background
        Log.d(TAG, "setAppBackground=$background")
        reapplyAudioFocus()
    }

    private fun reapplyAudioFocus() {
        audioFocusRequest?.let { request ->
            audioManager?.abandonAudioFocusRequest(request)
        }
        val manager = audioManager
        if (manager != null) {
            val focusType = if (isBackground) {
                AudioManager.AUDIOFOCUS_GAIN
            } else {
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            }
            val request =
                AudioFocusRequest.Builder(focusType)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setAcceptsDelayedFocusGain(false)
                    .setOnAudioFocusChangeListener(focusChangeListener)
                    .build()
            val result = manager.requestAudioFocus(request)
            audioFocusRequest = request
            Log.d(TAG, "reapplyAudioFocus focusType=$focusType result=$result")
        }
    }

    /** Attach the live main-isolate channel (called by MainActivity). */
    fun attachChannel(channel: MethodChannel) {
        this.channel = channel
        Log.d(TAG, "channel attached")
    }

    /** Detach the channel without touching the session (called by MainActivity). */
    fun detachChannel() {
        channel = null
        Log.d(TAG, "channel detached; session kept")
    }

    /**
     * Activate the media-button takeover with an application [Context] so the
     * MediaSession survives Activity recreation. Callers should pass
     * `applicationContext`.
     */
    fun activate(context: Context) {
        deactivate()

        MediaButtonEventDispatcher.configure(::dispatchToggle, ::dispatchCancel)
        requestAudioFocus(context)

        val receiver = ComponentName(context, MediaButtonReceiver::class.java)
        receiverComponent = receiver
        audioManager?.registerMediaButtonEventReceiver(receiver)
        val receiverIntent = Intent(Intent.ACTION_MEDIA_BUTTON).setComponent(receiver)
        val pendingIntentFlags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }
        val receiverPendingIntent =
            PendingIntent.getBroadcast(context, 0, receiverIntent, pendingIntentFlags)
        val session =
            MediaSessionCompat(
                context,
                "MemexVoiceInputMediaButtons",
                receiver,
                receiverPendingIntent,
            )
        @Suppress("DEPRECATION")
        session.setMediaButtonReceiver(receiverPendingIntent)
        session.setFlags(
            MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
        )
        session.setCallback(
            object : MediaSessionCompat.Callback() {
                override fun onMediaButtonEvent(mediaButtonEvent: Intent): Boolean {
                    val keyEvent =
                        mediaButtonEvent.keyEvent()
                            ?: return super.onMediaButtonEvent(mediaButtonEvent)
                    return MediaButtonEventDispatcher.handleKeyEvent(keyEvent) ||
                        super.onMediaButtonEvent(mediaButtonEvent)
                }

                override fun onPlay() {
                    dispatchToggle()
                }

                override fun onPause() {
                    dispatchToggle()
                }

                override fun onSkipToNext() {
                    dispatchToggle()
                }

                override fun onSkipToPrevious() {
                    dispatchCancel()
                }
            },
        )
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS,
                )
                .setState(
                    PlaybackStateCompat.STATE_PLAYING,
                    PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                    1.0f,
                )
                .build(),
        )
        session.isActive = true
        mediaSession = session
        Log.d(TAG, "MediaSession activated")
    }

    fun deactivate() {
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        MediaButtonEventDispatcher.clear()
        abandonAudioFocus()
        Log.d(TAG, "MediaSession deactivated")
    }

    /**
     * Deliver a toggle (middle key / play-pause) event: main-isolate channel
     * when alive, otherwise the foreground-task isolate.
     */
    fun dispatchToggle() {
        Log.d(TAG, "dispatchToggle channel=${channel != null}")
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("voiceToggle", null)
        } else {
            // Main isolate is gone (Activity destroyed / app swiped away):
            // drive the background voice session directly.
            ForegroundService.sendData(mapOf("type" to "voice_toggle"))
        }
    }

    /** Deliver a cancel (previous key) event. */
    fun dispatchCancel() {
        Log.d(TAG, "dispatchCancel channel=${channel != null}")
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("voiceCancel", null)
        } else {
            ForegroundService.sendData(mapOf("type" to "voice_cancel"))
        }
    }

    private fun requestAudioFocus(context: Context) {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val request =
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .build()

        val result = manager.requestAudioFocus(request)
        audioManager = manager
        audioFocusRequest = request
        Log.d(TAG, "requestAudioFocus result=$result")
    }

    private fun abandonAudioFocus() {
        val request = audioFocusRequest
        if (request != null) {
            audioManager?.abandonAudioFocusRequest(request)
        }
        receiverComponent?.let { audioManager?.unregisterMediaButtonEventReceiver(it) }
        receiverComponent = null
        audioFocusRequest = null
        audioManager = null
    }

    @Suppress("DEPRECATION")
    private fun Intent.keyEvent(): KeyEvent? =
        getParcelableExtra(Intent.EXTRA_KEY_EVENT)
}
