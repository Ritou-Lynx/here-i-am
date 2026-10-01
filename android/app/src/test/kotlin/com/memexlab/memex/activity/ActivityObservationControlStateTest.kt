package com.memexlab.memex.activity

import org.junit.Assert.*
import org.junit.Test

class ActivityObservationControlStateTest {
    private fun running() = ActivityObservationControlState("session").also { assertTrue(it.begin("one")); assertTrue(it.running("one")) }
    @Test fun initialAbsenceIsUnknownNotStopped() { val state = ActivityObservationControlState("s").snapshot(); assertEquals("unknown", state.state); assertFalse(state.enabled) }
    @Test fun drainAloneCannotConfirmStopped() { val gate = running(); gate.stopping("one", "notification_stop"); gate.drained("one", true); assertEquals("stopping", gate.snapshot().state); gate.destroyed("one"); assertEquals("stopped", gate.snapshot().state) }
    @Test fun destroyAloneCannotConfirmStopped() { val gate = running(); gate.stopping("one", "service_destroyed"); gate.destroyed("one"); assertEquals("stopping", gate.snapshot().state); gate.drained("one", true); assertEquals("stopped", gate.snapshot().state) }
    @Test fun drainFailureStaysUnknownAndCannotStartSuccessor() { val gate = running(); gate.stopping("one", "user_stop"); gate.drained("one", false); gate.destroyed("one"); assertEquals("unknown", gate.snapshot().state); assertEquals("observation_stop_failed", gate.snapshot().reason); assertFalse(gate.begin("two")) }
    @Test fun stoppingImmediatelyClosesEnabledGate() { val gate = running(); assertTrue(gate.snapshot().enabled); gate.stopping("one", "notification_not_visible"); assertFalse(gate.snapshot().enabled); assertFalse(gate.running("one")) }
    @Test fun lateOldLifecycleCannotStopSuccessor() { val gate = running(); gate.stopping("one", "user_stop"); gate.drained("one", true); gate.destroyed("one"); assertTrue(gate.begin("two")); assertTrue(gate.running("two")); gate.destroyed("one"); gate.drained("one", false); assertFalse(gate.stopping("one", "service_destroyed")); assertEquals("running", gate.snapshot().state) }
    @Test fun unclaimedCancellationHasNoWorkToDrain() { val gate = ActivityObservationControlState("s"); gate.begin("one"); gate.unclaimedStopped("one", "user_stop"); assertEquals("stopped", gate.snapshot().state); assertFalse(gate.running("one")) }
    @Test fun identitiesAndRevisionAreStrict() { val gate = running(); assertTrue(gate.matches("session", "one")); assertFalse(gate.matches("other", "one")); assertFalse(gate.matches("session", "")); val revision = gate.snapshot().revision; gate.stopping("one", "user_stop"); assertTrue(gate.snapshot().revision > revision) }
    @Test fun duplicateTerminalSignalsKeepRevisionStable() { val gate = running(); gate.stopping("one", "user_stop"); gate.drained("one", true); gate.destroyed("one"); val expected = gate.snapshot(); gate.destroyed("one"); gate.drained("one", true); assertEquals(expected, gate.snapshot()) }
    @Test fun twoSourcesAreIndependentAndSameSourceExclusive() { var next = 0; val gate = ActivityDiagnosticOutboxLeaseBroker { "token-${++next}" }; assertNotNull(gate.acquire(ANDROID_USAGE_EVENTS_SOURCE)); assertNull(gate.acquire(ANDROID_USAGE_EVENTS_SOURCE)); assertNotNull(gate.acquire(ANDROID_SCREEN_STATE_SOURCE)) }
    @Test fun oldLeaseReleaseCannotReleaseSuccessor() { var next = 0; val gate = ActivityDiagnosticOutboxLeaseBroker { "token-${++next}" }; val old = gate.acquire(ANDROID_USAGE_EVENTS_SOURCE)!!; assertTrue(gate.release(ANDROID_USAGE_EVENTS_SOURCE, old)); val successor = gate.acquire(ANDROID_USAGE_EVENTS_SOURCE)!!; assertFalse(gate.release(ANDROID_USAGE_EVENTS_SOURCE, old)); assertNull(gate.acquire(ANDROID_USAGE_EVENTS_SOURCE)); assertTrue(gate.release(ANDROID_USAGE_EVENTS_SOURCE, successor)) }
    @Test(expected = IllegalArgumentException::class) fun arbitrarySourceIsRejected() { ActivityDiagnosticOutboxLeaseBroker { "token" }.acquire("arbitrary") }
    @Test fun recoveryRequiresExactStoppedAndNoLiveLeases() {
        val state = running(); var serial = 0; val broker = ActivityDiagnosticOutboxLeaseBroker { "token-${++serial}" }
        assertNull(broker.beginRelease(state.snapshot(), "session", "one"))
        state.stopping("one", "user_stop"); state.drained("one", true); state.destroyed("one")
        val lease = broker.acquire(ANDROID_USAGE_EVENTS_SOURCE)!!
        assertNull(broker.beginRelease(state.snapshot(), "session", "one"))
        assertTrue(broker.release(ANDROID_USAGE_EVENTS_SOURCE, lease))
        assertNull(broker.beginRelease(state.snapshot(), "wrong", "one"))
        assertNotNull(broker.beginRelease(state.snapshot(), "session", "one"))
    }
    @Test fun permitSerializesBothSourcesAndBlocksActivationAndCompetingRecovery() {
        val state = running(); state.stopping("one", "user_stop"); state.drained("one", true); state.destroyed("one")
        var serial = 0; val broker = ActivityDiagnosticOutboxLeaseBroker { "token-${++serial}" }
        val permit = broker.beginRelease(state.snapshot(), "session", "one")!!
        assertNull(broker.acquire(ANDROID_USAGE_EVENTS_SOURCE))
        assertNull(broker.acquire(ANDROID_USAGE_EVENTS_SOURCE, "other"))
        assertNull(broker.acquire(ANDROID_SCREEN_STATE_SOURCE, permit))
        val usage = broker.acquire(ANDROID_USAGE_EVENTS_SOURCE, permit)!!
        val screen = broker.acquire(ANDROID_SCREEN_STATE_SOURCE, permit)!!
        assertFalse(broker.authorizesActivation(mapOf(ANDROID_USAGE_EVENTS_SOURCE to usage, ANDROID_SCREEN_STATE_SOURCE to screen)))
        assertNull(broker.beginRelease(state.snapshot(), "session", "one"))
        assertFalse(broker.endRelease(permit))
        assertTrue(broker.release(ANDROID_USAGE_EVENTS_SOURCE, usage)); assertTrue(broker.release(ANDROID_SCREEN_STATE_SOURCE, screen))
        assertFalse(broker.endRelease("other")); assertTrue(broker.endRelease(permit)); assertTrue(broker.endRelease(permit))
        assertNull(broker.acquire(ANDROID_USAGE_EVENTS_SOURCE, permit))
    }
    @Test fun activationRequiresBothCurrentTokens() {
        var serial = 0; val broker = ActivityDiagnosticOutboxLeaseBroker { "token-${++serial}" }
        val usage = broker.acquire(ANDROID_USAGE_EVENTS_SOURCE)!!; val screen = broker.acquire(ANDROID_SCREEN_STATE_SOURCE)!!
        assertFalse(broker.authorizesActivation(mapOf(ANDROID_USAGE_EVENTS_SOURCE to usage)))
        assertFalse(broker.authorizesActivation(mapOf(ANDROID_USAGE_EVENTS_SOURCE to usage, ANDROID_SCREEN_STATE_SOURCE to "wrong")))
        assertTrue(broker.authorizesActivation(mapOf(ANDROID_USAGE_EVENTS_SOURCE to usage, ANDROID_SCREEN_STATE_SOURCE to screen)))
    }
    @Test fun concurrentHandlersHaveOnlyOneLeaseWinner() {
        val broker = ActivityDiagnosticOutboxLeaseBroker { java.util.UUID.randomUUID().toString() }
        val start = java.util.concurrent.CountDownLatch(1)
        val winners = java.util.concurrent.CopyOnWriteArrayList<String>()
        val threads = (1..12).map { Thread { start.await(); broker.acquire(ANDROID_USAGE_EVENTS_SOURCE)?.let(winners::add) }.also { it.start() } }
        start.countDown(); threads.forEach { it.join(2000); assertFalse(it.isAlive) }
        assertEquals(1, winners.size)
    }
    @Test fun unknownStopReasonNeverExportsArbitraryText() {
        val state = running(); state.stopping("one", "sensitive arbitrary detail")
        assertEquals("observation_stop_failed", state.snapshot().reason)
        assertEquals(setOf("version", "session_id", "observation_id", "revision", "state", "enabled", "reason"), state.snapshot().toMap().keys)
    }
    @Test fun epochStopWriteFailureCannotConfirmCleanup() {
        var fail = false
        val store = object : ActivityPermissionEpochStore {
            var value: ActivityPermissionEpochState? = null
            override fun read() = value
            override fun write(state: ActivityPermissionEpochState) {
                if (fail) throw ActivityEpochException("epoch_state_write_failed")
                value = state
            }
        }
        val authority = ActivityPermissionEpochAuthority(store) { "epoch" }
        assertTrue(authority.start(ActivityObservationStartEvidence(true, true, true, true, true, true, 1L, "owner", "instance", 100L)).ready)
        fail = true
        authority.stop("user_stop", 110L)
        assertFalse(activityEpochStopConfirmed(true, authority.currentStateForTest()?.status))
        assertEquals("open", store.value?.status) // Durable write never succeeded.
        val control = running(); control.stopping("one", "user_stop"); control.destroyed("one")
        control.drained("one", activityEpochStopConfirmed(true, authority.currentStateForTest()?.status))
        assertEquals("unknown", control.snapshot().state)
    }
    @Test fun oldStopIntentOnFreshUnclaimedServiceStopsOnlyEmptyInstance() {
        assertEquals(ActivityStopIntentAction.STOP_EMPTY_INSTANCE, activityStopIntentAction("old", null, false))
        val control = running()
        // Empty-instance destroy carries no observation identity into control.
        assertFalse(control.stopping("", "service_destroyed"))
        control.destroyed("")
        assertEquals("running", control.snapshot().state)
    }
    @Test fun oldNotificationCannotStopRunningSuccessor() {
        assertEquals(ActivityStopIntentAction.IGNORE, activityStopIntentAction("old", "successor", true))
        assertEquals(ActivityStopIntentAction.IGNORE, activityStopIntentAction(null, "successor", true))
        assertEquals(ActivityStopIntentAction.STOP_OBSERVATION, activityStopIntentAction("successor", "successor", true))
    }
    @Test fun staleStartCanStopEmptyInstanceButCannotStopClaimedSuccessor() {
        assertTrue(activityEmptyInstanceShouldStop(null, false))
        assertFalse(activityEmptyInstanceShouldStop("successor", true))
        assertFalse(activityEmptyInstanceShouldStop("successor", false))
        assertFalse(activityEmptyInstanceShouldStop(null, true))
    }

    @Test fun exactLeaseReleaseRetriesAfterLostReceiptWithoutTouchingSuccessor() {
        var serial = 0
        val broker = ActivityDiagnosticOutboxLeaseBroker { "token-${++serial}" }
        val old = broker.acquire(ANDROID_USAGE_EVENTS_SOURCE)!!
        val lost = runCatching {
            assertTrue(broker.release(ANDROID_USAGE_EVENTS_SOURCE, old))
            error("synthetic reply lost after native release")
        }
        assertTrue(lost.isFailure)
        assertTrue(broker.release(ANDROID_USAGE_EVENTS_SOURCE, old))
        assertFalse(broker.release(ANDROID_USAGE_EVENTS_SOURCE, "unknown"))
        val successor = broker.acquire(ANDROID_USAGE_EVENTS_SOURCE)!!
        assertFalse(broker.release(ANDROID_USAGE_EVENTS_SOURCE, old))
        assertNull(broker.acquire(ANDROID_USAGE_EVENTS_SOURCE))
        assertTrue(broker.release(ANDROID_USAGE_EVENTS_SOURCE, successor))
        assertFalse(broker.release(ANDROID_USAGE_EVENTS_SOURCE, old))
        assertTrue(broker.release(ANDROID_USAGE_EVENTS_SOURCE, successor))
    }

    @Test fun exactPermitEndRetriesAfterLostReceiptAndRejectsSuccessor() {
        val state = running()
        state.stopping("one", "user_stop")
        state.drained("one", true)
        state.destroyed("one")
        var serial = 0
        val broker = ActivityDiagnosticOutboxLeaseBroker { "token-${++serial}" }
        val old = broker.beginRelease(state.snapshot(), "session", "one")!!
        val lost = runCatching {
            assertTrue(broker.endRelease(old))
            error("synthetic reply lost after native permit end")
        }
        assertTrue(lost.isFailure)
        assertTrue(broker.endRelease(old))
        assertFalse(broker.endRelease("unknown"))
        val successor = broker.beginRelease(state.snapshot(), "session", "one")!!
        assertFalse(broker.endRelease(old))
        assertNull(broker.acquire(ANDROID_USAGE_EVENTS_SOURCE))
        assertTrue(broker.endRelease(successor))
        assertFalse(broker.endRelease(old))
        assertTrue(broker.endRelease(successor))
    }

    @Test fun retiredPermitNeverConfirmsWhileNewWriterLeasesAreHeld() {
        val state = running()
        state.stopping("one", "user_stop")
        state.drained("one", true)
        state.destroyed("one")
        var serial = 0
        val broker = ActivityDiagnosticOutboxLeaseBroker { "token-${++serial}" }
        val permit = broker.beginRelease(state.snapshot(), "session", "one")!!
        assertTrue(broker.endRelease(permit))
        val writer = broker.acquire(ANDROID_USAGE_EVENTS_SOURCE)!!
        assertFalse(broker.endRelease(permit))
        assertNull(broker.acquire(ANDROID_USAGE_EVENTS_SOURCE))
        assertTrue(broker.release(ANDROID_USAGE_EVENTS_SOURCE, writer))
    }
}
