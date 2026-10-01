package com.memexlab.memex.activity

import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Process

internal interface UsageAccessGate {
    fun isGranted(): Boolean
}

internal class AndroidUsageAccessGate(private val context: Context) : UsageAccessGate {
    override fun isGranted(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        return appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }
}

/** Dynamic receiver used only as a query wake hint. Receipt time is never a signal time. */
internal class DynamicScreenSignalReceiver(
    context: Context,
    private val onQueryHint: (String) -> Unit,
) {
    private val appContext = context.applicationContext
    private var registered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            if (action == Intent.ACTION_SCREEN_ON ||
                action == Intent.ACTION_SCREEN_OFF ||
                action == Intent.ACTION_USER_PRESENT
            ) {
                onQueryHint(action)
            }
        }
    }

    fun start() {
        if (registered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // These three framework actions are protected broadcasts, so
            // ordinary apps cannot spoof them. Samsung emits USER_PRESENT
            // from the privileged SystemUI UID rather than the system UID;
            // A non-exported registration silently excludes that real signal.
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(receiver, filter)
        }
        registered = true
    }

    fun stop(): Boolean {
        if (!registered) return true
        if (runCatching { appContext.unregisterReceiver(receiver) }.isFailure) return false
        registered = false
        return true
    }
}
