package com.memexlab.memex.ble

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Alarm entrypoint only; all GATT and state work remains in the foreground service. */
class BleHeartRateWatchdogReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_CONNECT_WATCHDOG_ALARM =
            BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM
        const val EXTRA_TOKEN = "watchdog_token"
        const val EXTRA_GENERATION = "watchdog_generation"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CONNECT_WATCHDOG_ALARM) return
        val token = intent.getLongExtra(EXTRA_TOKEN, -1L)
        val generation = intent.getLongExtra(EXTRA_GENERATION, -1L)
        if (token <= 0L || generation <= 0L) return
        val store = BleHeartRateStore(context.applicationContext)
        try {
            val scheduler = BleConnectWatchdogAlarmScheduler(context.applicationContext)
            BleHeartRateWatchdogReceiverController(
                nowMs = System::currentTimeMillis,
                startService = { currentToken, currentGeneration ->
                    BleHeartRateService.startWatchdogReconcile(
                        context.applicationContext,
                        currentToken,
                        currentGeneration,
                    )
                },
                persistRetry = store::replaceActiveConnectWatchdog,
                rearmAlarm = { retryPlan ->
                    when (scheduler.schedule(retryPlan)) {
                        BleWatchdogAlarmMode.EXACT_ALLOW_IDLE -> {
                            store.recordActiveDiagnostic(
                                "connecting",
                                "connect_watchdog_alarm_exact_allow_idle",
                            )
                            true
                        }
                        BleWatchdogAlarmMode.INEXACT_ALLOW_IDLE -> {
                            store.recordActiveDiagnostic(
                                "connecting",
                                "connect_watchdog_alarm_inexact_allow_idle",
                            )
                            true
                        }
                        BleWatchdogAlarmMode.FAILED -> false
                    }
                },
                onDiagnostic = { reason ->
                    store.recordActiveDiagnostic("connecting", reason)
                },
            ).onAlarm(
                intent.action,
                token,
                generation,
                store.activeConnectWatchdog(),
            )
        } finally {
            store.close()
        }
    }
}
