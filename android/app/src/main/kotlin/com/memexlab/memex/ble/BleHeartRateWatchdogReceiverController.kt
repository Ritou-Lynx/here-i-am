package com.memexlab.memex.ble

internal enum class BleWatchdogReceiverOutcome {
    IGNORED,
    EARLY_REARMED,
    EARLY_REARM_FAILED,
    FORWARDED,
    START_FAILED_REARMED,
    START_FAILED_REARM_PERSIST_FAILED,
    START_FAILED_REARM_FAILED,
}

/** Pure orchestration for the alarm -> foreground-service boundary. */
internal class BleHeartRateWatchdogReceiverController(
    private val nowMs: () -> Long,
    private val startService: (token: Long, generation: Long) -> Boolean,
    private val persistRetry: (
        expected: BleConnectWatchdogPlan,
        replacement: BleConnectWatchdogPlan,
    ) -> Boolean,
    private val rearmAlarm: (BleConnectWatchdogPlan) -> Boolean,
    private val onDiagnostic: (String) -> Unit,
) {
    companion object {
        internal const val START_FAILURE_RETRY_MS = 60_000L
    }

    fun onAlarm(
        action: String?,
        token: Long,
        generation: Long,
        persisted: BleConnectWatchdogPlan?,
    ): BleWatchdogReceiverOutcome {
        if (!BleHeartRateWatchdogReceiverPolicy.shouldForward(
                action,
                token,
                generation,
                persisted,
            )
        ) {
            return BleWatchdogReceiverOutcome.IGNORED
        }

        checkNotNull(persisted)
        val now = nowMs()
        if (now < persisted.dueAtMs) {
            return if (rearmAlarm(persisted)) {
                onDiagnostic("connect_watchdog_early_alarm_rearmed")
                BleWatchdogReceiverOutcome.EARLY_REARMED
            } else {
                onDiagnostic("connect_watchdog_early_alarm_rearm_failed")
                BleWatchdogReceiverOutcome.EARLY_REARM_FAILED
            }
        }
        if (startService(token, generation)) {
            return BleWatchdogReceiverOutcome.FORWARDED
        }

        onDiagnostic("connect_watchdog_fgs_start_failed")
        val retryPlan = persisted.copy(
            dueAtMs = now + START_FAILURE_RETRY_MS,
        )
        if (!persistRetry(persisted, retryPlan)) {
            onDiagnostic("connect_watchdog_rearm_persist_failed_after_fgs_start_failed")
            return BleWatchdogReceiverOutcome.START_FAILED_REARM_PERSIST_FAILED
        }
        return if (rearmAlarm(retryPlan)) {
            onDiagnostic("connect_watchdog_alarm_rearmed_after_fgs_start_failed")
            BleWatchdogReceiverOutcome.START_FAILED_REARMED
        } else {
            onDiagnostic("connect_watchdog_alarm_rearm_failed_after_fgs_start_failed")
            BleWatchdogReceiverOutcome.START_FAILED_REARM_FAILED
        }
    }
}
