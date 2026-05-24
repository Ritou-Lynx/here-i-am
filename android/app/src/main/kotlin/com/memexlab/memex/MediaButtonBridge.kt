package com.memexlab.memex

import android.app.Activity
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

class MediaButtonBridge(
    private val onToggle: () -> Unit,
    private val onCancel: () -> Unit,
) {
    private var mediaSession: MediaSessionCompat? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var receiverComponent: ComponentName? = null

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        Log.d(TAG, "audio focus changed: $change")
    }

    fun activate(activity: Activity) {
        deactivate()

        MediaButtonEventDispatcher.configure(onToggle, onCancel)
        requestAudioFocus(activity)

        val receiver = ComponentName(activity, MediaButtonReceiver::class.java)
        receiverComponent = receiver
        audioManager?.registerMediaButtonEventReceiver(receiver)
        val receiverIntent = Intent(Intent.ACTION_MEDIA_BUTTON).setComponent(receiver)
        val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        val receiverPendingIntent = PendingIntent.getBroadcast(
            activity,
            0,
            receiverIntent,
            pendingIntentFlags
        )
        val session = MediaSessionCompat(
            activity,
            "MemexVoiceInputMediaButtons",
            receiver,
            receiverPendingIntent
        )
        @Suppress("DEPRECATION")
        session.setMediaButtonReceiver(receiverPendingIntent)
        session.setFlags(
            MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
        )
        session.setCallback(
            object : MediaSessionCompat.Callback() {
                override fun onMediaButtonEvent(mediaButtonEvent: Intent): Boolean {
                    val keyEvent = mediaButtonEvent.keyEvent()
                        ?: return super.onMediaButtonEvent(mediaButtonEvent)
                    return MediaButtonEventDispatcher.handleKeyEvent(keyEvent) ||
                        super.onMediaButtonEvent(mediaButtonEvent)
                }

                override fun onPlay() {
                    onToggle()
                }

                override fun onPause() {
                    onToggle()
                }

                override fun onSkipToNext() {
                    onToggle()
                }

                override fun onSkipToPrevious() {
                    onCancel()
                }
            }
        )
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                )
                .setState(
                    PlaybackStateCompat.STATE_PLAYING,
                    PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                    1.0f
                )
                .build()
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

    private fun requestAudioFocus(activity: Activity) {
        val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
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

    private companion object {
        const val TAG = "MediaButtonBridge"
    }
}
