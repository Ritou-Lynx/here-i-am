package com.memexlab.memex.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BleConnectWatchdogServiceControllerTest {
    @Test
    fun `fresh service consumes persisted overdue attempt exactly once`() {
        val plan = plan(token = 71L, generation = 7L, dueAtMs = 9_000L)
        val harness = Harness(nowMs = 10_000L, persisted = plan).apply {
            state = startingWithoutGatt()
        }

        assertTrue(harness.controller.reconcilePersisted())
        assertEquals(
            listOf(plan to BleConnectWatchdogAction.RECOVER_ABANDONED_ATTEMPT),
            harness.timeoutActions,
        )
        assertNull(harness.persisted)
        assertFalse(harness.controller.reconcileSignal(plan.token, plan.generation))
        assertEquals(1, harness.timeoutActions.size)
    }

    @Test
    fun `future persisted attempt rebuilds Handler and system alarm`() {
        val plan = plan(token = 72L, generation = 8L, dueAtMs = 20_000L)
        val harness = Harness(nowMs = 10_000L, persisted = plan)

        assertTrue(harness.controller.reconcilePersisted())

        assertEquals(10_000L, harness.scheduled.single().delayMs)
        assertEquals(listOf(plan), harness.alarmSchedules)
        assertEquals(emptyList<Pair<BleConnectWatchdogPlan, BleConnectWatchdogAction>>(), harness.timeoutActions)
    }

    @Test
    fun `alarm and late Handler share one durable consume gate`() {
        val harness = Harness(nowMs = 30_000L)
        assertEquals(
            BleWatchdogArmResult.ARMED,
            harness.controller.arm(9L, ADDRESS, 25_000L),
        )
        val plan = requireNotNull(harness.persisted)
        harness.state = activeState(plan.generation)
        val lateHandler = harness.lastScheduled()
        harness.nowMs = plan.dueAtMs

        assertTrue(harness.controller.reconcileSignal(plan.token, plan.generation))
        lateHandler.run()

        assertNull(harness.persisted)
        assertEquals(listOf(plan.token), harness.tokenClears)
        assertEquals(
            listOf(plan to BleConnectWatchdogAction.TIMEOUT_ACTIVE_ATTEMPT),
            harness.timeoutActions,
        )
    }

    @Test
    fun `durable save failure cancels Handler and never schedules alarm or timeout`() {
        val harness = Harness(nowMs = 40_000L).apply { saveSucceeds = false }

        assertEquals(
            BleWatchdogArmResult.PERSIST_FAILED,
            harness.controller.arm(10L, ADDRESS, 25_000L),
        )

        assertNull(harness.persisted)
        assertNull(harness.controller.currentPlan)
        assertEquals(emptyList<BleConnectWatchdogPlan>(), harness.alarmSchedules)
        assertEquals(emptyList<Pair<BleConnectWatchdogPlan, BleConnectWatchdogAction>>(), harness.timeoutActions)
        assertEquals(listOf("connect_watchdog_persist_failed"), harness.diagnostics)
    }

    @Test
    fun `alarm scheduling failure retains durable Handler reconciliation`() {
        val harness = Harness(nowMs = 50_000L).apply { alarmSucceeds = false }
        assertEquals(
            BleWatchdogArmResult.ARMED,
            harness.controller.arm(11L, ADDRESS, 25_000L),
        )
        val plan = requireNotNull(harness.persisted)
        harness.state = activeState(plan.generation)
        val handler = harness.lastScheduled()
        harness.nowMs = plan.dueAtMs

        handler.run()

        assertNull(harness.persisted)
        assertEquals(1, harness.timeoutActions.size)
        assertEquals(listOf("connect_watchdog_alarm_failed"), harness.diagnostics)
    }

    @Test
    fun `terminal cancellation rejects Handler alarm and periodic late sources`() {
        val harness = Harness(nowMs = 60_000L)
        harness.controller.arm(12L, ADDRESS, 25_000L)
        val plan = requireNotNull(harness.persisted)
        val lateHandler = harness.lastScheduled()

        harness.controller.cancel()
        harness.nowMs = plan.dueAtMs
        lateHandler.run()

        assertFalse(harness.controller.reconcileSignal(plan.token, plan.generation))
        assertFalse(harness.controller.reconcilePersisted())
        assertNull(harness.persisted)
        assertEquals(emptyList<Pair<BleConnectWatchdogPlan, BleConnectWatchdogAction>>(), harness.timeoutActions)
    }

    @Test
    fun `stable live cancellation becomes a pure no-op after watchdog cleanup`() {
        val harness = Harness(nowMs = 70_000L)
        harness.controller.arm(13L, ADDRESS, 25_000L)
        harness.clearCalls = 0
        harness.alarmCancelCount = 0

        harness.controller.cancel()
        repeat(120) {
            harness.controller.cancel()
            assertFalse(harness.controller.reconcilePersisted())
        }

        assertNull(harness.persisted)
        assertEquals(1, harness.clearCalls)
        assertEquals(1, harness.alarmCancelCount)
    }

    @Test
    fun `empty startup reconciliation cancels an orphan alarm only once`() {
        val harness = Harness(nowMs = 75_000L)

        repeat(120) { assertFalse(harness.controller.reconcilePersisted()) }

        assertEquals(0, harness.clearCalls)
        assertEquals(1, harness.alarmCancelCount)
    }

    @Test
    fun `failed durable cancellation stays retryable`() {
        val harness = Harness(nowMs = 77_000L)
        harness.controller.arm(14L, ADDRESS, 25_000L)
        harness.clearCalls = 0
        harness.alarmCancelCount = 0
        harness.clearSucceeds = false

        harness.controller.cancel()
        assertEquals(1, harness.clearCalls)
        assertTrue(harness.persisted != null)

        harness.clearSucceeds = true
        harness.controller.cancel()
        harness.controller.cancel()

        assertNull(harness.persisted)
        assertEquals(2, harness.clearCalls)
        assertEquals(1, harness.alarmCancelCount)
    }

    @Test
    fun `arm aborts before creating a replacement when old cleanup fails`() {
        val harness = Harness(nowMs = 78_000L)
        assertEquals(BleWatchdogArmResult.ARMED, harness.controller.arm(15L, ADDRESS, 25_000L))
        val oldPlan = requireNotNull(harness.persisted)
        harness.clearCalls = 0
        harness.saveCalls = 0
        harness.alarmCancelCount = 0
        harness.clearSucceeds = false
        harness.saveSucceeds = false

        assertEquals(
            BleWatchdogArmResult.PERSIST_FAILED,
            harness.controller.arm(16L, ADDRESS, 25_000L),
        )

        assertEquals(oldPlan, harness.persisted)
        assertNull(harness.controller.currentPlan)
        assertEquals(1, harness.clearCalls)
        assertEquals(0, harness.saveCalls)
        assertEquals(0, harness.alarmCancelCount)
        assertEquals(listOf("connect_watchdog_cleanup_failed"), harness.diagnostics)
    }

    @Test
    fun `timeout clear failure retries and emits one action after durable consume`() {
        val harness = Harness(nowMs = 79_000L)
        assertEquals(BleWatchdogArmResult.ARMED, harness.controller.arm(17L, ADDRESS, 25_000L))
        val plan = requireNotNull(harness.persisted)
        harness.state = activeState(plan.generation)
        val handler = harness.lastScheduled()
        harness.clearCalls = 0
        harness.alarmCancelCount = 0
        harness.clearSucceeds = false
        harness.nowMs = plan.dueAtMs

        handler.run()
        assertEquals(plan, harness.persisted)
        assertEquals(emptyList<Pair<BleConnectWatchdogPlan, BleConnectWatchdogAction>>(), harness.timeoutActions)
        assertEquals(0, harness.alarmCancelCount)

        harness.clearSucceeds = true
        assertTrue(harness.controller.reconcilePersisted())
        assertFalse(harness.controller.reconcilePersisted())

        assertNull(harness.persisted)
        assertEquals(listOf(plan.token), harness.tokenClears)
        assertEquals(
            listOf(plan to BleConnectWatchdogAction.TIMEOUT_ACTIVE_ATTEMPT),
            harness.timeoutActions,
        )
        assertEquals(1, harness.alarmCancelCount)
    }

    @Test
    fun `old alarm cannot clear or close a newer GATT attempt`() {
        val replacement = plan(token = 90L, generation = 14L, dueAtMs = 100_000L)
        val harness = Harness(nowMs = 80_000L, persisted = replacement).apply {
            state = activeState(generation = 14L)
        }

        assertFalse(harness.controller.reconcileSignal(89L, 13L))

        assertEquals(replacement, harness.persisted)
        assertEquals(emptyList<Long>(), harness.tokenClears)
        assertEquals(emptyList<Pair<BleConnectWatchdogPlan, BleConnectWatchdogAction>>(), harness.timeoutActions)
    }

    private class Harness(
        nowMs: Long,
        persisted: BleConnectWatchdogPlan? = null,
    ) {
        data class Scheduled(val runnable: Runnable, val delayMs: Long)

        var nowMs = nowMs
        var persisted = persisted
        var nextToken = 100L
        var saveSucceeds = true
        var clearSucceeds = true
        var alarmSucceeds = true
        var saveCalls = 0
        var state: BleConnectAttemptState? = activeState(generation = persisted?.generation ?: 1L)
        val scheduled = mutableListOf<Scheduled>()
        val alarmSchedules = mutableListOf<BleConnectWatchdogPlan>()
        val tokenClears = mutableListOf<Long>()
        val timeoutActions = mutableListOf<Pair<BleConnectWatchdogPlan, BleConnectWatchdogAction>>()
        val diagnostics = mutableListOf<String>()
        var clearCalls = 0
        var alarmCancelCount = 0

        val controller = BleConnectWatchdogServiceController(
            nowMs = { this.nowMs },
            nextToken = { ++nextToken },
            postDelayed = { runnable, delayMs -> scheduled += Scheduled(runnable, delayMs) },
            removeCallbacks = { runnable -> scheduled.removeAll { it.runnable === runnable } },
            loadPersisted = { this.persisted },
            savePersisted = { plan ->
                saveCalls += 1
                if (saveSucceeds) this.persisted = plan
                saveSucceeds
            },
            clearPersisted = { expectedToken ->
                clearCalls += 1
                if (!clearSucceeds) {
                    false
                } else if (expectedToken != null && this.persisted?.token != expectedToken) {
                    false
                } else {
                    if (expectedToken != null) tokenClears += expectedToken
                    this.persisted = null
                    true
                }
            },
            scheduleAlarm = { plan ->
                if (alarmSucceeds) alarmSchedules += plan
                alarmSucceeds
            },
            cancelAlarm = { alarmCancelCount += 1 },
            stateProvider = { state },
            onTimeoutAction = { plan, action -> timeoutActions += plan to action },
            onDiagnostic = diagnostics::add,
        )

        fun lastScheduled(): Runnable = scheduled.last().runnable
    }

    companion object {
        private const val ADDRESS = "AA:BB:CC:DD:EE:FF"

        private fun plan(token: Long, generation: Long, dueAtMs: Long) =
            BleConnectWatchdogPlan(token, generation, dueAtMs, ADDRESS)

        private fun activeState(generation: Long) = BleConnectAttemptState(
            stoppedExplicitly = false,
            enabled = true,
            adapterEnabled = true,
            status = "connecting",
            activeGeneration = generation,
            activeAddress = ADDRESS,
            hasGatt = true,
        )

        private fun startingWithoutGatt() = BleConnectAttemptState(
            stoppedExplicitly = false,
            enabled = true,
            adapterEnabled = true,
            status = "starting",
            activeGeneration = 0L,
            activeAddress = null,
            hasGatt = false,
        )
    }
}
