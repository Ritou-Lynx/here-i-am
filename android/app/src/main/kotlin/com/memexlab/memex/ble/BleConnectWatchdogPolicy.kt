package com.memexlab.memex.ble

internal data class BleConnectAttemptState(
    val stoppedExplicitly: Boolean,
    val enabled: Boolean,
    val adapterEnabled: Boolean,
    val status: String,
    val activeGeneration: Long,
    val activeAddress: String?,
    val hasGatt: Boolean,
)

internal enum class BleConnectWatchdogAction {
    TIMEOUT_ACTIVE_ATTEMPT,
    RECOVER_ABANDONED_ATTEMPT,
    IGNORE,
}

/** Pure service-level guard applied after a watchdog plan is consumed. */
internal object BleConnectWatchdogPolicy {
    fun decide(
        plan: BleConnectWatchdogPlan,
        state: BleConnectAttemptState,
    ): BleConnectWatchdogAction {
        if (state.stoppedExplicitly || !state.enabled || !state.adapterEnabled) {
            return BleConnectWatchdogAction.IGNORE
        }

        if (state.hasGatt) {
            val isCurrentAttempt =
                (state.status == "connecting" || state.status == "reconnecting") &&
                    state.activeGeneration == plan.generation &&
                    state.activeAddress == plan.deviceAddress
            return if (isCurrentAttempt) {
                BleConnectWatchdogAction.TIMEOUT_ACTIVE_ATTEMPT
            } else {
                BleConnectWatchdogAction.IGNORE
            }
        }

        // A process can die without onDestroy after persisting the plan. An
        // alarm-started replacement service begins at "starting" with no GATT;
        // consuming that overdue plan should create one fresh reconnect intent.
        return if (state.status == "starting") {
            BleConnectWatchdogAction.RECOVER_ABANDONED_ATTEMPT
        } else {
            BleConnectWatchdogAction.IGNORE
        }
    }
}
