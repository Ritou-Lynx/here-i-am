package com.memexlab.memex.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BleConnectWatchdogCoordinatorTest {
    @Test
    fun `lost Handler is recovered from persisted overdue plan once`() {
        val harness = Harness(nowMs = 1_000L)
        val plan = harness.coordinator.arm(7L, ADDRESS, 25_000L)
        harness.scheduled.clear()
        harness.nowMs = plan.dueAtMs

        assertEquals(
            BleWatchdogSignalResult.CONSUMED,
            harness.coordinator.reconcilePersisted(plan),
        )
        assertEquals(listOf(plan), harness.timeouts)
        assertNull(harness.coordinator.currentPlan)
        assertEquals(
            BleWatchdogSignalResult.IGNORED,
            harness.coordinator.signal(plan.token, plan.generation),
        )
    }

    @Test
    fun `Handler and alarm racing consume the plan exactly once`() {
        val harness = Harness(nowMs = 10_000L)
        val plan = harness.coordinator.arm(8L, ADDRESS, 25_000L)
        val handlerCallback = harness.lastScheduled()
        harness.nowMs = plan.dueAtMs

        assertEquals(
            BleWatchdogSignalResult.CONSUMED,
            harness.coordinator.signal(plan.token, plan.generation),
        )
        handlerCallback.run()

        assertEquals(listOf(plan), harness.timeouts)
    }

    @Test
    fun `early alarm keeps the same plan and reposts remaining delay`() {
        val harness = Harness(nowMs = 20_000L)
        val plan = harness.coordinator.arm(9L, ADDRESS, 25_000L)
        harness.nowMs += 5_000L

        assertEquals(
            BleWatchdogSignalResult.WAITING,
            harness.coordinator.signal(plan.token, plan.generation),
        )
        assertEquals(plan, harness.coordinator.currentPlan)
        assertEquals(20_000L, harness.scheduled.single().delayMs)
        assertEquals(emptyList<BleConnectWatchdogPlan>(), harness.timeouts)
    }

    @Test
    fun `future persisted plan rebuilds the Handler fast path`() {
        val harness = Harness(nowMs = 30_000L)
        val plan = BleConnectWatchdogPlan(41L, 10L, 40_000L, ADDRESS)

        assertEquals(
            BleWatchdogSignalResult.WAITING,
            harness.coordinator.reconcilePersisted(plan),
        )
        assertEquals(plan, harness.coordinator.currentPlan)
        assertEquals(10_000L, harness.scheduled.single().delayMs)
    }

    @Test
    fun `fresh coordinator consumes persisted overdue plan once`() {
        val harness = Harness(nowMs = 45_000L)
        val plan = BleConnectWatchdogPlan(42L, 10L, 40_000L, ADDRESS)

        assertEquals(
            BleWatchdogSignalResult.CONSUMED,
            harness.coordinator.reconcilePersisted(plan),
        )
        assertEquals(listOf(plan), harness.timeouts)
        assertNull(harness.coordinator.currentPlan)
        assertEquals(
            BleWatchdogSignalResult.IGNORED,
            harness.coordinator.signal(plan.token, plan.generation),
        )
    }

    @Test
    fun `replaced plan rejects old alarm token and generation`() {
        val harness = Harness(nowMs = 40_000L)
        val old = harness.coordinator.arm(11L, ADDRESS, 25_000L)
        val replacement = harness.coordinator.arm(12L, ADDRESS, 25_000L)
        harness.nowMs = replacement.dueAtMs

        assertEquals(
            BleWatchdogSignalResult.IGNORED,
            harness.coordinator.signal(old.token, old.generation),
        )
        assertEquals(replacement, harness.coordinator.currentPlan)
        assertEquals(
            BleWatchdogSignalResult.CONSUMED,
            harness.coordinator.signal(replacement.token, replacement.generation),
        )
        assertEquals(listOf(replacement), harness.timeouts)
    }

    @Test
    fun `terminal cancellation makes every late source a no-op`() {
        val harness = Harness(nowMs = 50_000L)
        val plan = harness.coordinator.arm(13L, ADDRESS, 25_000L)
        val lateHandler = harness.lastScheduled()

        assertEquals(plan, harness.coordinator.cancel())
        harness.nowMs = plan.dueAtMs
        lateHandler.run()

        assertEquals(
            BleWatchdogSignalResult.IGNORED,
            harness.coordinator.signal(plan.token, plan.generation),
        )
        assertEquals(emptyList<BleConnectWatchdogPlan>(), harness.timeouts)
    }

    private class Harness(nowMs: Long) {
        data class Scheduled(val runnable: Runnable, val delayMs: Long)

        var nowMs = nowMs
        var nextToken = 100L
        val scheduled = mutableListOf<Scheduled>()
        val timeouts = mutableListOf<BleConnectWatchdogPlan>()
        val coordinator = BleConnectWatchdogCoordinator(
            nowMs = { this.nowMs },
            nextToken = { ++nextToken },
            postDelayed = { runnable, delayMs -> scheduled += Scheduled(runnable, delayMs) },
            removeCallbacks = { runnable -> scheduled.removeAll { it.runnable === runnable } },
            onTimeoutDue = timeouts::add,
        )

        fun lastScheduled(): Runnable = scheduled.last().runnable
    }

    companion object {
        private const val ADDRESS = "AA:BB:CC:DD:EE:FF"
    }
}
