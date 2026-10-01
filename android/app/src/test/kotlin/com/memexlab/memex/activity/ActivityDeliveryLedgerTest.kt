package com.memexlab.memex.activity

import org.junit.Assert.*
import org.junit.Test

class ActivityDeliveryLedgerTest {
    private fun signal(at: Long, type: String = "screen_interactive") = ReducedActivitySignal(type, at)
    private fun ledger(capacity: Int = 2048) = ActivityDeliveryLedger(capacity).also { it.reset("epoch-a") }

    @Test fun lostAckKeepsOneImmutableFlightAndAcceptedRetryDoesNotReplay() {
        val ledger = ledger()
        ledger.append(listOf(signal(100)), 110)
        val first = ledger.batch(110)!!
        ledger.append(listOf(signal(120)), 130)
        assertEquals(first, ledger.batch(130))
        assertEquals(2, ledger.pendingCount)
        assertFalse(ledger.acknowledge("old-epoch", first.id, listOf("accepted")))
        assertFalse(ledger.acknowledge(first.epoch, "wrong-id", listOf("accepted")))
        assertEquals(2, ledger.pendingCount)
        assertTrue(ledger.acknowledge(first.epoch, first.id, listOf("accepted")))
        ledger.append(listOf(signal(100)), 130)
        assertEquals(listOf(signal(120)), ledger.batch(130)!!.signals)
    }

    @Test fun partialDurableFailureRetainsRetryAndInvalidAckCannotRetirePrefix() {
        val ledger = ledger()
        ledger.append(listOf(signal(100), signal(101)), 110)
        val batch = ledger.batch(110)!!
        assertFalse(ledger.acknowledge(batch.epoch, batch.id, listOf("accepted", "invented")))
        assertEquals(2, ledger.pendingCount)
        assertTrue(ledger.acknowledge(batch.epoch, batch.id, listOf("accepted", "retry")))
        assertEquals(1, ledger.pendingCount)
        assertEquals(batch, ledger.batch(120))
        assertTrue(ledger.acknowledge(batch.epoch, batch.id, listOf("duplicate", "accepted")))
        assertNull(ledger.batch(120))
    }

    @Test fun queryCrossesExpiryNewlyReducedEventIsCountedOnce() {
        val ledger = ledger()
        ledger.append(listOf(signal(100)), 300101)
        assertEquals(1, ledger.expired)
        assertNull(ledger.batch(300101))
        ledger.append(listOf(signal(100)), 300102)
        assertEquals(1, ledger.expired)
    }

    @Test fun engineUnavailableExpiresPendingWithoutNeedingANewEvent() {
        val ledger = ledger()
        ledger.append(listOf(signal(100)), 110)
        ledger.batch(110)
        assertNull(ledger.batch(300101))
        assertEquals(1, ledger.expired)
        assertEquals(0, ledger.pendingCount)
    }

    @Test fun overflowIsVisibleAndDedupMemoryStaysBounded() {
        val ledger = ledger(2)
        ledger.append(listOf(signal(100), signal(101), signal(102)), 110)
        assertEquals(2, ledger.retainedCount)
        assertEquals(1, ledger.overflowBatches)
        assertEquals(2, ledger.pendingCount)
    }

    @Test fun sameMillisecondDifferentScreenKindsSurviveRescan() {
        val events = listOf(15,16,18).map { RawActivityUsageEvent(null, it, 100) }
        val reduced = ActivityUsageEventReducer.reduce(events, 90, 110, emptyMap()).screenSignals
        val ledger = ledger()
        ledger.append(reduced, 110)
        ledger.append(reduced, 120)
        val batch = ledger.batch(120)!!
        assertEquals(3, batch.signals.size)
        ledger.acknowledge(batch.epoch, batch.id, List(3) { "accepted" })
        ledger.append(reduced, 120)
        assertNull(ledger.batch(120))
    }

    @Test fun resetAbandonsOldEpochResponsibilityAndRejectsItsAck() {
        val ledger = ledger()
        ledger.append(listOf(signal(100)), 110)
        val batch = ledger.batch(110)!!
        ledger.reset("epoch-new")
        assertEquals(1, ledger.abandoned)
        assertFalse(ledger.acknowledge(batch.epoch, batch.id, listOf("accepted")))
        assertNull(ledger.batch(120))
    }
}
