package com.memexlab.memex

import android.content.Intent
import com.memexlab.memex.channels.BackupImportChannelHandler
import com.memexlab.memex.channels.BackupStorageChannelHandler
import com.memexlab.memex.channels.ChannelRegistrar
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import com.pravera.flutter_foreground_task.service.ForegroundService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import android.util.Log
import android.view.KeyEvent

class MainActivity : FlutterFragmentActivity() {
    private var mediaButtonBridge: MediaButtonBridge? = null
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
        registerForegroundTaskPlugins()
    }

    /**
     * The foreground task runs in its own FlutterEngine (separate Dart isolate).
     * By default that engine registers NO plugins, so MethodChannel-based
     * plugins (record / just_audio / path_provider / shared_preferences) are
     * unavailable in the background isolate. Registering the generated plugin
     * registrant here gives the background voice session the same plugin
     * surface as the main engine.
     */
    private fun registerForegroundTaskPlugins() {
        ForegroundService.addTaskLifecycleListener(
            object : FlutterForegroundTaskLifecycleListener {
                override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                    flutterEngine?.let { GeneratedPluginRegistrant.registerWith(it) }
                }

                override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

                override fun onTaskRepeatEvent() {}

                override fun onTaskDestroy() {}

                override fun onEngineWillDestroy() {}
            }
        )
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
            "com.memexlab.memex/media_buttons"
        )
        mediaButtonChannel = channel
        mediaButtonBridge = MediaButtonBridge(
            onToggle = {
                runOnUiThread {
                    mediaButtonChannel?.invokeMethod("voiceToggle", null)
                }
            },
            onCancel = {
                runOnUiThread {
                    mediaButtonChannel?.invokeMethod("voiceCancel", null)
                }
            }
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "activate" -> {
                    mediaButtonBridge?.activate(applicationContext)
                    result.success(null)
                }

                "deactivate" -> {
                    mediaButtonBridge?.deactivate()
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

        val method = when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "voiceCancel"
            else -> "voiceToggle"
        }
        mediaButtonChannel?.invokeMethod(method, null)
        return true
    }

    override fun onDestroy() {
        mediaButtonBridge?.deactivate()
        super.onDestroy()
    }
}
