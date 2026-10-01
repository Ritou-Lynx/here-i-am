package com.memexlab.memex.ble

/**
 * Owns the single pending reconnect deadline independently from the Android
 * Handler queue. The deadline remains recoverable even if the queued Runnable
 * is lost, while a token prevents removed or replaced callbacks from firing.
 *
 * All calls are confined to [BleHeartRateService]'s main thread.
 */
internal class BleReconnectCoordinator(
    private val nowMs: () -> Long,
    private val postDelayed: (Runnable, Long) -> Unit,
    private val removeCallbacks: (Runnable) -> Unit,
    private val onRetryDue: () -> Unit,
) {
    data class RetryPlan(
        val token: Long,
        val dueAtMs: Long,
    )

    private data class PendingRetry(
        val plan: RetryPlan,
        val runnable: Runnable,
    )

    private var nextToken = 0L
    private var pending: PendingRetry? = null

    val pendingDueAtMs: Long?
        get() = pending?.plan?.dueAtMs

    fun schedule(delayMs: Long): RetryPlan {
        require(delayMs >= 0L) { "delayMs must be non-negative" }
        return scheduleAt(nowMs() + delayMs)
    }

    private fun scheduleAt(dueAtMs: Long): RetryPlan {
        cancel()

        val token = ++nextToken
        val plan = RetryPlan(token = token, dueAtMs = dueAtMs)
        val runnable = Runnable { dispatchIfCurrent(token) }
        pending = PendingRetry(plan, runnable)
        postDelayed(runnable, (dueAtMs - nowMs()).coerceAtLeast(0L))
        return plan
    }

    fun cancel(): Boolean {
        val previous = pending ?: return false
        pending = null
        removeCallbacks(previous.runnable)
        return true
    }

    /**
     * Safety net for a Handler callback that disappeared while the service and
     * its deadline remained alive. Returns true only when a retry was consumed.
     */
    fun recoverOverdue(): Boolean {
        val current = pending ?: return false
        if (nowMs() < current.plan.dueAtMs) return false
        removeCallbacks(current.runnable)
        dispatchIfCurrent(current.plan.token)
        return true
    }

    /**
     * Rebuilds a missing in-memory schedule from the persisted status
     * projection. A future deadline is re-posted; an overdue one is consumed
     * immediately and exactly once.
     */
    fun reconcilePersistedDeadline(dueAtMs: Long): Boolean {
        if (pending == null) scheduleAt(dueAtMs)
        return recoverOverdue()
    }

    private fun dispatchIfCurrent(token: Long) {
        val current = pending ?: return
        if (current.plan.token != token) return

        val remainingMs = current.plan.dueAtMs - nowMs()
        if (remainingMs > 0L) {
            // Defend against an early or manually invoked callback without
            // allowing a second logical retry.
            removeCallbacks(current.runnable)
            postDelayed(current.runnable, remainingMs)
            return
        }

        pending = null
        onRetryDue()
    }
}
