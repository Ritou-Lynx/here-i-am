package com.memexlab.memex

import android.app.Application
import com.memexlab.memex.channels.AudioRouteChannelHandler
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import com.pravera.flutter_foreground_task.service.ForegroundService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Registers the foreground-task plugin bridge at process start, so the
 * background isolate always gets its plugins (record / just_audio /
 * path_provider / shared_preferences) regardless of when the service starts —
 * including autoRunOnBoot and START_STICKY restarts where MainActivity does
 * not exist yet and would never see onEngineCreate.
 *
 * The host audio-route / call-control channels are registered on the isolate
 * engine too (applicationContext-based handlers), because the global call
 * audio pipeline runs in that isolate and needs to switch the speaker route
 * and drive the in-call control notification from there.
 */
class HereIAmApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ForegroundService.addTaskLifecycleListener(
            object : FlutterForegroundTaskLifecycleListener {
                override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                    flutterEngine?.let {
                        GeneratedPluginRegistrant.registerWith(it)
                        AudioRouteChannelHandler.register(it, applicationContext)
                    }
                }

                override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

                override fun onTaskRepeatEvent() {}

                override fun onTaskDestroy() {}

                override fun onEngineWillDestroy() {}
            },
        )
    }
}
