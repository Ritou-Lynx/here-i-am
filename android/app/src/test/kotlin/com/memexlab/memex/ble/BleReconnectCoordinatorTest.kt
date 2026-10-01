package com.memexlab.memex.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BleReconnectCoordinatorTest {
    @Test
    fun `lost handler callback is recovered once after deadline`() {
        val harness = Harness(nowMs = 1_000L)
        val plan = harness.coordinator.schedule(delayMs = 2_000L)

        harness.scheduled.clear() // Simulate a silently removed Handler callback.
        harness.nowMs = plan.dueAtMs

        assertTrue(harness.coordinator.recoverOverdue())
        assertEquals(1, harness.retryCount)
        assertNull(harness.coordinator.pendingDueAtMs)
        assertFalse(harness.coordinator.recoverOverdue())
        assertEquals(1, harness.retryCount)
    }

    @Test
    fun `replaced callback cannot fire the newer retry`() {
        val harness = Harness(nowMs = 10_000L)
        harness.coordinator.schedule(delayMs = 2_000L)
        val oldRunnable = harness.lastScheduled()

        val replacement = harness.coordinator.schedule(delayMs = 5_000L)
        val newRunnable = harness.lastScheduled()
        harness.nowMs = replacement.dueAtMs

        oldRunnable.run()
        assertEquals(0, harness.retryCount)
        assertEquals(replacement.dueAtMs, harness.coordinator.pendingDueAtMs)

        newRunnable.run()
        assertEquals(1, harness.retryCount)
        assertNull(harness.coordinator.pendingDueAtMs)
    }

    @Test
    fun `terminal cancellation prevents a removed callback from reconnecting`() {
        val harness = Harness(nowMs = 20_000L)
        val plan = harness.coordinator.schedule(delayMs = 2_000L)
        val removedRunnable = harness.lastScheduled()

        assertTrue(harness.coordinator.cancel())
        harness.nowMs = plan.dueAtMs
        removedRunnable.run()

        assertEquals(0, harness.retryCount)
        assertNull(harness.coordinator.pendingDueAtMs)
        assertFalse(harness.coordinator.recoverOverdue())
    }

    @Test
    fun `early callback is rescheduled for the remaining deadline`() {
        val harness = Harness(nowMs = 30_000L)
        val plan = harness.coordinator.schedule(delayMs = 5_000L)
        val runnable = harness.lastScheduled()

        harness.nowMs += 2_000L
        runnable.run()

        assertEquals(0, harness.retryCount)
        assertEquals(plan.dueAtMs, harness.coordinator.pendingDueAtMs)
        assertEquals(3_000L, harness.scheduled.single().delayMs)

        harness.nowMs = plan.dueAtMs
        harness.lastScheduled().run()
        assertEquals(1, harness.retryCount)
    }

    @Test
    fun `overdue recovery does nothing before deadline`() {
        val harness = Harness(nowMs = 40_000L)
        val plan = harness.coordinator.schedule(delayMs = 5_000L)

        harness.nowMs = plan.dueAtMs - 1L

        assertFalse(harness.coordinator.recoverOverdue())
        assertEquals(0, harness.retryCount)
        assertEquals(plan.dueAtMs, harness.coordinator.pendingDueAtMs)
    }

    @Test
    fun `persisted future deadline recreates a missing in-memory callback`() {
        val harness = Harness(nowMs = 50_000L)

        assertFalse(harness.coordinator.reconcilePersistedDeadline(55_000L))
        assertEquals(55_000L, harness.coordinator.pendingDueAtMs)
        assertEquals(5_000L, harness.scheduled.single().delayMs)

        harness.nowMs = 55_000L
        harness.lastScheduled().run()
        assertEquals(1, harness.retryCount)
        assertNull(harness.coordinator.pendingDueAtMs)
    }

    @Test
    fun `persisted overdue deadline is recovered immediately once`() {
        val harness = Harness(nowMs = 60_000L)

        assertTrue(harness.coordinator.reconcilePersistedDeadline(59_000L))
        assertEquals(1, harness.retryCount)
        assertNull(harness.coordinator.pendingDueAtMs)
        assertTrue(harness.scheduled.isEmpty())
    }

    private class Harness(nowMs: Long) {
        data class Scheduled(val runnable: Runnable, val delayMs: Long)

        var nowMs = nowMs
        var retryCount = 0
        val scheduled = mutableListOf<Scheduled>()
        val coordinator = BleReconnectCoordinator(
            nowMs = { this.nowMs },
            postDelayed = { runnable, delayMs -> scheduled += Scheduled(runnable, delayMs) },
            removeCallbacks = { runnable -> scheduled.removeAll { it.runnable === runnable } },
            onRetryDue = { retryCount += 1 },
        )

        fun lastScheduled(): Runnable = scheduled.last().runnable
    }
}
