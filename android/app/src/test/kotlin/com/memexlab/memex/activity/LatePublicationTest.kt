package com.memexlab.memex.activity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LatePublicationTest {
    private class MemoryStore : ActivityPermissionEpochStore {
        var value: ActivityPermissionEpochState? = null
        override fun read() = value
        override fun write(state: ActivityPermissionEpochState) { value = state }
    }

    private fun evidence(now: Long) = ActivityQueryEvidence(
        foregroundStarted = true, notificationVisible = true,
        watcherRegistered = true, appOpsAllowed = true,
        bootMarker = 7L, ownerFence = "owner", serviceInstanceId = "service",
        observedAtMs = now,
    )

    @Test fun latePublicationInsideLiveEpochMustRemainObservable() {
        val authority = ActivityPermissionEpochAuthority(MemoryStore()) { "epoch" }
        val started = authority.start(ActivityObservationStartEvidence(
            explicitOptIn = true, foregroundStarted = true,
            notificationVisible = true, watcherRegistered = true,
            appOpsAllowed = true, debugDiagnostic = true, bootMarker = 7L,
            ownerFence = "owner", serviceInstanceId = "service", observedAtMs = 1000L,
        ))
        assertTrue(started.ready)
        val first = authority.prepareQuery(1000L, 1100L, evidence(1100L)).first!!
        authority.completeQuery(first, ActivityUsageQueryOutcome.EMPTY, evidence(1101L))
        // The system publishes this event only after the first query returned.
        // Its original occurrence time and live authorization epoch are unchanged.
        val newlyVisible = RawActivityUsageEvent(null, ActivityUsageEventReducer.SCREEN_INTERACTIVE, 1050L)
        val second = authority.prepareQuery(1000L, 1200L, evidence(1200L)).first!!
        val reduced = ActivityUsageEventReducer.reduce(
            listOf(newlyVisible), second.startMs, second.endMs, emptyMap(),
        )
        assertEquals("late screen event must not vanish after an unproven empty query", 1, reduced.screenSignals.size)
    }
    @Test fun latePublicationAfterUnrelatedRawAlsoIgnoresRequestedProgress() {
        val authority = ActivityPermissionEpochAuthority(MemoryStore()) { "epoch" }
        val started = authority.start(ActivityObservationStartEvidence(
            explicitOptIn = true, foregroundStarted = true,
            notificationVisible = true, watcherRegistered = true,
            appOpsAllowed = true, debugDiagnostic = true, bootMarker = 7L,
            ownerFence = "owner", serviceInstanceId = "service", observedAtMs = 1000L,
        ))
        assertTrue(started.ready)
        val first = authority.prepareQuery(1000L, 1100L, evidence(1100L)).first!!
        authority.completeQuery(first, ActivityUsageQueryOutcome.EVENTS, evidence(1101L))
        // The system publishes this event only after the first query returned.
        // Its original occurrence time and live authorization epoch are unchanged.
        val newlyVisible = RawActivityUsageEvent(null, ActivityUsageEventReducer.SCREEN_INTERACTIVE, 1050L)
        val second = authority.prepareQuery(1100L, 1200L, evidence(1200L)).first!!
        val reduced = ActivityUsageEventReducer.reduce(
            listOf(newlyVisible), second.startMs, second.endMs, emptyMap(),
        )
        assertEquals("late screen event must not vanish after an unproven empty query", 1, reduced.screenSignals.size)
    }
}
