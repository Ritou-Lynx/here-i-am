package com.memexlab.memex.ble

/** Pure gate used before a cancelled/stale alarm is allowed to start an FGS. */
internal object BleHeartRateWatchdogReceiverPolicy {
    const val ACTION_CONNECT_WATCHDOG_ALARM =
        "com.memexlab.memex.ble.CONNECT_WATCHDOG_ALARM"

    fun shouldForward(
        action: String?,
        token: Long,
        generation: Long,
        persisted: BleConnectWatchdogPlan?,
    ): Boolean =
        action == ACTION_CONNECT_WATCHDOG_ALARM &&
            token > 0L &&
            generation > 0L &&
            persisted != null &&
            persisted.token == token &&
            persisted.generation == generation
}
