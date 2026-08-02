package com.memexlab.memex

import android.content.Intent
import com.memexlab.memex.channels.BackupImportChannelHandler
import com.memexlab.memex.channels.BackupStorageChannelHandler
import com.memexlab.memex.channels.ChannelRegistrar
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import android.view.KeyEvent

class MainActivity : FlutterFragmentActivity() {
    private var mediaButtonChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // If the Activity is being recreated (system killed it in background),
        // clear the stale shortcut extra so the quick_actions plugin won't
        // re-deliver an already-consumed action on the next attach cycle.
        if (savedInstanceState != null) {
            intent?.removeExtra("some unique action key")
        }
        super.onCreate(savedInstanceState)
        BackupImportChannelHandler.handleIntent(this, intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        BackupImportChannelHandler.handleIntent(this, intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register all MethodChannel handlers
        ChannelRegistrar.registerAll(flutterEngine, this)
        registerMediaButtonChannel(flutterEngine)
    }

    private fun registerMediaButtonChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.memexlab.memex/media_buttons",
        )
        mediaButtonChannel = channel
        // The bridge is process-scoped: attach the channel here, detach on
        // destroy, never release the MediaSession with the Activity.
        MediaButtonBridge.attachChannel(channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "activate" -> {
                    MediaButtonBridge.activate(applicationContext)
                    result.success(null)
                }

                "deactivate" -> {
                    MediaButtonBridge.deactivate()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (BackupStorageChannelHandler.handleActivityResult(requestCode, resultCode, data)) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (handleMediaKeyEvent(event)) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun handleMediaKeyEvent(event: KeyEvent): Boolean {
        val isMediaVoiceKey = when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_MEDIA_NEXT,
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> true
            else -> false
        }
        if (!isMediaVoiceKey) return false

        Log.d("MediaButtonBridge", "activity keyCode=${event.keyCode} action=${event.action}")
        if (event.action != KeyEvent.ACTION_DOWN) {
            return true
        }

        if (event.keyCode == KeyEvent.KEYCODE_MEDIA_PREVIOUS) {
            MediaButtonBridge.dispatchCancel()
        } else {
            MediaButtonBridge.dispatchToggle()
        }
        return true
    }

    override fun onDestroy() {
        // Do NOT deactivate the MediaSession here: the bridge is process-scoped
        // and must survive Activity destruction so headset keys keep working
        // with the app backgrounded. Events are routed to the main isolate via
        // the channel while it is alive, and fall back to the foreground-task
        // isolate (ForegroundService.sendData) once the engine is gone.
        MediaButtonBridge.detachChannel()
        super.onDestroy()
    }
}
