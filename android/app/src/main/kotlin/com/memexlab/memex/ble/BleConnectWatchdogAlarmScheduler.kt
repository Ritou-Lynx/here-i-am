package com.memexlab.memex.ble

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

internal enum class BleWatchdogAlarmMode {
    EXACT_ALLOW_IDLE,
    INEXACT_ALLOW_IDLE,
    FAILED,
}

/** Thin AlarmManager boundary; the receiver still validates the durable token. */
internal class BleConnectWatchdogAlarmScheduler(context: Context) {
    companion object {
        private const val REQUEST_CODE = 0x2a37
    }

    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)

    fun schedule(plan: BleConnectWatchdogPlan): BleWatchdogAlarmMode {
        cancel()
        val pendingIntent = pendingIntent(plan, PendingIntent.FLAG_UPDATE_CURRENT)
        val triggerAtElapsedMs = SystemClock.elapsedRealtime() +
            (plan.dueAtMs - System.currentTimeMillis()).coerceAtLeast(0L)

        val exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        if (exactAllowed) {
            try {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtElapsedMs,
                    pendingIntent,
                )
                return BleWatchdogAlarmMode.EXACT_ALLOW_IDLE
            } catch (_: SecurityException) {
                // Permission can be revoked after the capability check.
            } catch (_: RuntimeException) {
                // Fall through to the inexact idle-aware recovery opportunity.
            }
        }

        return try {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAtElapsedMs,
                pendingIntent,
            )
            BleWatchdogAlarmMode.INEXACT_ALLOW_IDLE
        } catch (_: RuntimeException) {
            BleWatchdogAlarmMode.FAILED
        }
    }

    fun cancel() {
        val existing = PendingIntent.getBroadcast(
            appContext,
            REQUEST_CODE,
            baseIntent(),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        alarmManager.cancel(existing)
        existing.cancel()
    }

    private fun pendingIntent(plan: BleConnectWatchdogPlan, flags: Int): PendingIntent =
        PendingIntent.getBroadcast(
            appContext,
            REQUEST_CODE,
            baseIntent()
                .putExtra(BleHeartRateWatchdogReceiver.EXTRA_TOKEN, plan.token)
                .putExtra(BleHeartRateWatchdogReceiver.EXTRA_GENERATION, plan.generation),
            flags or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun baseIntent(): Intent = Intent(
        BleHeartRateWatchdogReceiver.ACTION_CONNECT_WATCHDOG_ALARM,
        null,
        appContext,
        BleHeartRateWatchdogReceiver::class.java,
    )
}
