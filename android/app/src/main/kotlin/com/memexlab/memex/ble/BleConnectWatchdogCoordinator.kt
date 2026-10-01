package com.memexlab.memex.ble

/** Persisted identity for one in-flight GATT connection attempt. */
internal data class BleConnectWatchdogPlan(
    val token: Long,
    val generation: Long,
    val dueAtMs: Long,
    val deviceAddress: String,
)

internal enum class BleWatchdogSignalResult {
    IGNORED,
    WAITING,
    CONSUMED,
}

/**
 * Owns the Handler fast path for a single connect-watchdog deadline.
 *
 * The Android service persists [BleConnectWatchdogPlan] and schedules a
 * separate AlarmManager wake-up. Handler, alarm and periodic reconciliation
 * all enter through this coordinator, so only one source can consume a plan.
 * All calls are confined to BleHeartRateService's main thread.
 */
internal class BleConnectWatchdogCoordinator(
    private val nowMs: () -> Long,
    private val nextToken: () -> Long,
    private val postDelayed: (Runnable, Long) -> Unit,
    private val removeCallbacks: (Runnable) -> Unit,
    private val onTimeoutDue: (BleConnectWatchdogPlan) -> Unit,
) {
    private data class PendingWatchdog(
        val plan: BleConnectWatchdogPlan,
        val runnable: Runnable,
    )

    private var pending: PendingWatchdog? = null

    val currentPlan: BleConnectWatchdogPlan?
        get() = pending?.plan

    fun arm(generation: Long, deviceAddress: String, delayMs: Long): BleConnectWatchdogPlan {
        require(generation > 0L) { "generation must be positive" }
        require(deviceAddress.isNotBlank()) { "deviceAddress must not be blank" }
        require(delayMs >= 0L) { "delayMs must be non-negative" }

        cancel()
        val plan = BleConnectWatchdogPlan(
            token = nextToken(),
            generation = generation,
            dueAtMs = nowMs() + delayMs,
            deviceAddress = deviceAddress,
        )
        install(plan)
        return plan
    }

    /** Rebuilds or refreshes the Handler fast path from durable state. */
    fun reconcilePersisted(plan: BleConnectWatchdogPlan): BleWatchdogSignalResult {
        val current = pending
        if (current == null || current.plan.token != plan.token) {
            cancel()
            install(plan)
        } else if (current.plan != plan) {
            return BleWatchdogSignalResult.IGNORED
        }
        return dispatchIfCurrent(plan.token, plan.generation)
    }

    /** Handles an explicit AlarmManager wake-up or a captured Handler callback. */
    fun signal(token: Long, generation: Long): BleWatchdogSignalResult =
        dispatchIfCurrent(token, generation)

    fun cancel(): BleConnectWatchdogPlan? {
        val previous = pending ?: return null
        pending = null
        removeCallbacks(previous.runnable)
        return previous.plan
    }

    private fun install(plan: BleConnectWatchdogPlan) {
        val runnable = Runnable { dispatchIfCurrent(plan.token, plan.generation) }
        pending = PendingWatchdog(plan, runnable)
        postDelayed(runnable, (plan.dueAtMs - nowMs()).coerceAtLeast(0L))
    }

    private fun dispatchIfCurrent(token: Long, generation: Long): BleWatchdogSignalResult {
        val current = pending ?: return BleWatchdogSignalResult.IGNORED
        if (current.plan.token != token || current.plan.generation != generation) {
            return BleWatchdogSignalResult.IGNORED
        }

        val remainingMs = current.plan.dueAtMs - nowMs()
        if (remainingMs > 0L) {
            // AlarmManager and vendor callbacks may arrive early. Keep the same
            // logical plan and refresh only the Handler fast path.
            removeCallbacks(current.runnable)
            postDelayed(current.runnable, remainingMs)
            return BleWatchdogSignalResult.WAITING
        }

        pending = null
        removeCallbacks(current.runnable)
        onTimeoutDue(current.plan)
        return BleWatchdogSignalResult.CONSUMED
    }
}
