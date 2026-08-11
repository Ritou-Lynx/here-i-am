package com.memexlab.memex.channels

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import com.memexlab.memex.CompanionShareAccessibilityService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Exposes the companion-share accessibility setup state to Flutter. */
object CompanionShareChannelHandler {
    private const val CHANNEL = "com.memexlab.memex/companion_share"
    private var channel: MethodChannel? = null

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityServiceEnabled" -> {
                        result.success(isAccessibilityServiceEnabled(activity))
                    }

                    "isServiceConnected" -> {
                        result.success(CompanionShareAccessibilityService.isConnected())
                    }

                    "openAccessibilitySettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    fun pushShare(text: String?, imagePath: String?) {
        val map = HashMap<String, Any?>()
        map["text"] = text
        map["imagePath"] = imagePath
        channel?.invokeMethod("onShareReceived", map)
    }

    private fun isAccessibilityServiceEnabled(context: Context): Boolean {
        val accessibilityEnabled = Settings.Secure.getInt(
            context.contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0,
        ) == 1
        if (!accessibilityEnabled) return false

        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val component = ComponentName(context, CompanionShareAccessibilityService::class.java)
        return enabledServices.split(':').any { enabled ->
            enabled.equals(component.flattenToString(), ignoreCase = true) ||
                enabled.equals(component.flattenToShortString(), ignoreCase = true)
        }
    }
}
