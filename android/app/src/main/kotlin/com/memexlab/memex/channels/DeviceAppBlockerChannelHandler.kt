package com.memexlab.memex.channels

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.memexlab.memex.FocusLockAccessibilityService

/**
 * Handles app-blocker commands.
 *
 * Native focus lock uses AccessibilityService. Tasker can still receive
 * fallback commands with:
 *   Profile -> Event -> System -> Intent Received
 *   Action: com.memexlab.hereiam.APP_BLOCKER_COMMAND
 */
object DeviceAppBlockerChannelHandler {
    private const val CHANNEL = "com.memexlab.memex/device_app_blocker"

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityServiceEnabled" -> {
                        result.success(isAccessibilityServiceEnabled(activity))
                    }
                    "openAccessibilitySettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "setNativeFocusLock" -> {
                        setNativeFocusLock(activity, call.arguments, result)
                    }
                    "isNativeFocusLockActive" -> {
                        result.success(FocusLockAccessibilityService.isLocked(activity))
                    }
                    "sendTaskerIntent" -> {
                        sendTaskerIntent(activity, call.arguments, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setNativeFocusLock(
        activity: Activity,
        arguments: Any?,
        result: MethodChannel.Result
    ) {
        val args = arguments as? Map<*, *>
        val enabled = args?.get("enabled") as? Boolean ?: false
        val untilMs = (args?.get("untilMs") as? Number)?.toLong()
        if (enabled && !isAccessibilityServiceEnabled(activity)) {
            result.error(
                "SERVICE_NOT_ENABLED",
                "Accessibility service is not enabled.",
                null
            )
            return
        }
        FocusLockAccessibilityService.setLocked(activity, enabled, untilMs)
        result.success(FocusLockAccessibilityService.isLocked(activity))
    }

    private fun sendTaskerIntent(
        activity: Activity,
        arguments: Any?,
        result: MethodChannel.Result
    ) {
        val args = arguments as? Map<*, *>
        val action = args?.get("intentAction") as? String
        val payloadJson = args?.get("payloadJson") as? String
        if (action.isNullOrBlank() || payloadJson.isNullOrBlank()) {
            result.error(
                "INVALID_ARGS",
                "intentAction and payloadJson are required",
                null
            )
            return
        }

        val intent = Intent(action).apply {
            putExtra("payload_json", payloadJson)
            putExtra("source", "memex")
            addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
        }
        activity.sendBroadcast(intent)
        result.success(true)
    }

    private fun isAccessibilityServiceEnabled(context: Context): Boolean {
        val accessibilityEnabled = Settings.Secure.getInt(
            context.contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0
        ) == 1
        if (!accessibilityEnabled) return false

        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val component = ComponentName(
            context,
            FocusLockAccessibilityService::class.java
        )
        return enabledServices.split(':').any { enabled ->
            enabled.equals(component.flattenToString(), ignoreCase = true) ||
                enabled.equals(component.flattenToShortString(), ignoreCase = true)
        }
    }
}
