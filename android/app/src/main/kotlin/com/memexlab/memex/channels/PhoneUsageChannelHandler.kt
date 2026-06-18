package com.memexlab.memex.channels

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Handles `com.memexlab.memex/phone_usage` MethodChannel.
 *
 * Android usage access is a special AppOps permission. Apps cannot request it
 * with a runtime dialog, so Flutter must guide the user to system settings.
 */
class PhoneUsageChannelHandler(private val activity: Activity) {

    companion object {
        private const val CHANNEL = "com.memexlab.memex/phone_usage"

        fun register(flutterEngine: FlutterEngine, activity: Activity) {
            val handler = PhoneUsageChannelHandler(activity)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isUsageAccessGranted" -> result.success(handler.isUsageAccessGranted())
                        "openUsageAccessSettings" -> handler.openUsageAccessSettings(result)
                        "queryUsageStats" -> handler.queryUsageStats(call.arguments, result)
                        else -> result.notImplemented()
                    }
                }
        }
    }

    private fun isUsageAccessGranted(): Boolean {
        val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            activity.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            activity.startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            activity.startActivity(Intent(Settings.ACTION_SETTINGS))
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_SETTINGS_FAILED", e.message, null)
        }
    }

    private fun queryUsageStats(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *>
        val startMs = (args?.get("startTime") as? Number)?.toLong()
        val endMs = (args?.get("endTime") as? Number)?.toLong()
        val limit = ((args?.get("limit") as? Number)?.toInt() ?: 20).coerceIn(1, 200)

        if (startMs == null || endMs == null || endMs <= startMs) {
            result.error("INVALID_ARGUMENTS", "Invalid usage query window", null)
            return
        }
        if (!isUsageAccessGranted()) {
            result.error("PERMISSION_DENIED", "Usage access is not granted", null)
            return
        }

        try {
            val usageManager =
                activity.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val stats = usageManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startMs,
                endMs
            )
            val merged = mergeStats(stats)
            val rows = merged.values
                .filter { it.totalTimeInForeground > 0 }
                .sortedByDescending { it.totalTimeInForeground }
                .take(limit)
                .map { stat ->
                    mapOf(
                        "packageName" to stat.packageName,
                        "appName" to resolveAppName(stat.packageName),
                        "totalTimeMs" to stat.totalTimeInForeground,
                        "lastTimeUsedMs" to stat.lastTimeUsed
                    )
                }
            result.success(rows)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Usage access is not granted", null)
        } catch (e: Exception) {
            result.error("QUERY_FAILED", e.message, null)
        }
    }

    private fun mergeStats(stats: List<UsageStats>): Map<String, UsageStats> {
        val merged = linkedMapOf<String, UsageStats>()
        for (stat in stats) {
            val current = merged[stat.packageName]
            if (current == null) {
                merged[stat.packageName] = stat
            } else {
                current.add(stat)
            }
        }
        return merged
    }

    private fun resolveAppName(packageName: String): String {
        return try {
            val appInfo = activity.packageManager.getApplicationInfo(packageName, 0)
            activity.packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
    }
}
