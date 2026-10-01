package com.memexlab.memex.ble

internal enum class BleWatchdogArmResult {
    ARMED,
    PERSIST_FAILED,
}

/**
 * Pure Kotlin service-level orchestration for the connect watchdog.
 *
 * Android Handler and AlarmManager are injected as ports. A timeout effect is
 * emitted only after the durable token has been compared and synchronously
 * cleared, making Handler/alarm/periodic reconciliation an exactly-once race.
 */
internal class BleConnectWatchdogServiceController(
    private val nowMs: () -> Long,
    nextToken: () -> Long,
    postDelayed: (Runnable, Long) -> Unit,
    removeCallbacks: (Runnable) -> Unit,
    private val loadPersisted: () -> BleConnectWatchdogPlan?,
    private val savePersisted: (BleConnectWatchdogPlan) -> Boolean,
    private val clearPersisted: (Long?) -> Boolean,
    private val scheduleAlarm: (BleConnectWatchdogPlan) -> Boolean,
    private val cancelAlarm: () -> Unit,
    private val stateProvider: () -> BleConnectAttemptState?,
    private val onTimeoutAction: (BleConnectWatchdogPlan, BleConnectWatchdogAction) -> Unit,
    private val onDiagnostic: (String) -> Unit,
) {
    // Starts unknown so the first service reconciliation still cancels any
    // orphaned AlarmManager entry left behind by an older process.
    private var cleanupKnownComplete = false

    private val coordinator = BleConnectWatchdogCoordinator(
        nowMs = nowMs,
        nextToken = nextToken,
        postDelayed = postDelayed,
        removeCallbacks = removeCallbacks,
        onTimeoutDue = ::consumeTimeout,
    )

    val currentPlan: BleConnectWatchdogPlan?
        get() = coordinator.currentPlan

    fun arm(
        generation: Long,
        deviceAddress: String,
        delayMs: Long,
    ): BleWatchdogArmResult {
        if (!cancel()) {
            onDiagnostic("connect_watchdog_cleanup_failed")
            return BleWatchdogArmResult.PERSIST_FAILED
        }
        val plan = coordinator.arm(generation, deviceAddress, delayMs)
        if (!savePersisted(plan)) {
            coordinator.cancel()
            onDiagnostic("connect_watchdog_persist_failed")
            return BleWatchdogArmResult.PERSIST_FAILED
        }
        cleanupKnownComplete = false
        scheduleAlarmOrDiagnose(plan)
        return BleWatchdogArmResult.ARMED
    }

    /** Returns true when a durable attempt owns the service start/tick. */
    fun reconcilePersisted(): Boolean {
        val plan = loadPersisted()
        if (plan == null) {
            coordinator.cancel()
            if (!cleanupKnownComplete) cancelAlarm()
            cleanupKnownComplete = true
            return false
        }

        cleanupKnownComplete = false
        val current = coordinator.currentPlan
        if (current == plan && nowMs() < plan.dueAtMs) return true
        if (current != null && current != plan) coordinator.cancel()
        reconcilePlan(plan)
        return true
    }

    /** Returns false for a stale or malformed AlarmManager delivery. */
    fun reconcileSignal(token: Long, generation: Long): Boolean {
        val plan = loadPersisted() ?: return false
        if (plan.token != token || plan.generation != generation) return false
        cleanupKnownComplete = false
        val current = coordinator.currentPlan
        if (current != null && current != plan) coordinator.cancel()
        reconcilePlan(plan)
        return true
    }

    /** Returns false while a durable token could not be synchronously cleared. */
    fun cancel(): Boolean {
        val current = coordinator.currentPlan
        if (cleanupKnownComplete && current == null) return true
        coordinator.cancel()
        val hadDurablePlan = current != null || loadPersisted() != null
        val persistenceCleared = !hadDurablePlan || clearPersisted(null)
        // Keep the existing system wake-up armed while its durable token could
        // not be cleared. A later tick/start can then retry or consume it.
        if (persistenceCleared) cancelAlarm()
        // A failed synchronous clear must remain retryable; otherwise a stale
        // durable token could be resurrected after the live connection ends.
        cleanupKnownComplete = persistenceCleared
        return persistenceCleared
    }

    private fun reconcilePlan(plan: BleConnectWatchdogPlan) {
        when (coordinator.reconcilePersisted(plan)) {
            BleWatchdogSignalResult.WAITING -> scheduleAlarmOrDiagnose(plan)
            BleWatchdogSignalResult.CONSUMED,
            BleWatchdogSignalResult.IGNORED -> Unit
        }
    }

    private fun consumeTimeout(plan: BleConnectWatchdogPlan) {
        val persisted = loadPersisted() ?: return
        if (persisted != plan || !clearPersisted(plan.token)) return
        cancelAlarm()
        cleanupKnownComplete = true

        val state = stateProvider() ?: return
        val action = BleConnectWatchdogPolicy.decide(plan, state)
        if (action != BleConnectWatchdogAction.IGNORE) {
            onTimeoutAction(plan, action)
        }
    }

    private fun scheduleAlarmOrDiagnose(plan: BleConnectWatchdogPlan) {
        if (!scheduleAlarm(plan)) onDiagnostic("connect_watchdog_alarm_failed")
    }
}
