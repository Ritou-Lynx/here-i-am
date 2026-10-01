package com.memexlab.memex.activity

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityPermissionEpochAuthorityTest {
    private class MemoryStore(
        var value: ActivityPermissionEpochState? = null,
        var readFailure: String? = null,
        var writeFailure: String? = null,
    ) : ActivityPermissionEpochStore {
        override fun read(): ActivityPermissionEpochState? {
            readFailure?.let { throw ActivityEpochException(it) }
            return value
        }

        override fun write(state: ActivityPermissionEpochState) {
            writeFailure?.let { throw ActivityEpochException(it) }
            value = state
        }
    }

    private var id = 0
    private fun authority(store: ActivityPermissionEpochStore) =
        ActivityPermissionEpochAuthority(store) { "epoch-${++id}" }

    private fun startEvidence(
        now: Long = 1_000L,
        optIn: Boolean = true,
        foreground: Boolean = true,
        visible: Boolean = true,
        watcher: Boolean = true,
        allowed: Boolean = true,
        debug: Boolean = true,
        boot: Long? = 7L,
        owner: String = "owner-a",
        service: String = "service-a",
    ) = ActivityObservationStartEvidence(
        explicitOptIn = optIn,
        foregroundStarted = foreground,
        notificationVisible = visible,
        watcherRegistered = watcher,
        appOpsAllowed = allowed,
        debugDiagnostic = debug,
        bootMarker = boot,
        ownerFence = owner,
        serviceInstanceId = service,
        observedAtMs = now,
    )

    private fun queryEvidence(
        now: Long,
        foreground: Boolean = true,
        visible: Boolean = true,
        watcher: Boolean = true,
        allowed: Boolean = true,
        boot: Long? = 7L,
        owner: String = "owner-a",
        service: String = "service-a",
    ) = ActivityQueryEvidence(
        foregroundStarted = foreground,
        notificationVisible = visible,
        watcherRegistered = watcher,
        appOpsAllowed = allowed,
        bootMarker = boot,
        ownerFence = owner,
        serviceInstanceId = service,
        observedAtMs = now,
    )

    @Test
    fun `activation requires opt in visible foreground watcher permission boot and debug`() {
        val cases = listOf(
            startEvidence(optIn = false) to "activity_opt_in_required",
            startEvidence(debug = false) to "debug_diagnostic_required",
            startEvidence(foreground = false) to "foreground_start_failed",
            startEvidence(visible = false) to "notification_not_visible",
            startEvidence(watcher = false) to "appops_watcher_unavailable",
            startEvidence(allowed = false) to "usage_permission_denied",
            startEvidence(boot = null) to "boot_marker_unavailable",
        )
        for ((evidence, code) in cases) {
            val store = MemoryStore()
            val decision = authority(store).start(evidence)
            assertFalse(code, decision.ready)
            assertEquals(code, decision.fixedCode)
            assertNull(store.value)
        }
    }

    @Test
    fun `2201 event delivered at 0017 cannot become a fresh unlock`() {
        val store = MemoryStore()
        val authority = authority(store)
        val queuedAt = 1_789_480_870_402L
        val receivedAt = 1_789_489_013_448L
        assertTrue(authority.start(startEvidence(now = receivedAt)).ready)
        val (permit, _) = authority.prepareQuery(
            queuedAt,
            receivedAt + 1L,
            queryEvidence(receivedAt),
        )
        requireNotNull(permit)
        assertEquals(receivedAt, permit.startMs)
        val reduced = ActivityUsageEventReducer.reduce(
            listOf(RawActivityUsageEvent(null, ActivityUsageEventReducer.KEYGUARD_HIDDEN, queuedAt)),
            permit.startMs,
            permit.endMs,
            emptyMap(),
        )
        assertTrue(reduced.screenSignals.isEmpty())
    }

    @Test
    fun `screen and keyguard occurrence timestamps pass through unchanged`() {
        val events = listOf(
            RawActivityUsageEvent(null, ActivityUsageEventReducer.SCREEN_NON_INTERACTIVE, 101L),
            RawActivityUsageEvent(null, ActivityUsageEventReducer.SCREEN_INTERACTIVE, 102L),
            RawActivityUsageEvent(null, ActivityUsageEventReducer.KEYGUARD_HIDDEN, 103L),
            RawActivityUsageEvent("private.app", ActivitySignalPolicy.ACTIVITY_RESUMED, 104L),
        )
        val reduced = ActivityUsageEventReducer.reduce(events, 100L, 200L, mapOf("private.app" to "other"))
        assertEquals(listOf(101L, 102L, 103L), reduced.screenSignals.map { it.signalAtMs })
        assertEquals(
            listOf("screen_non_interactive", "screen_interactive", "user_present"),
            reduced.screenSignals.map { it.type },
        )
        assertEquals(104L, reduced.usageSignals.single().signalAtMs)
        assertFalse(reduced.toString().contains("private.app"))
    }

    @Test
    fun `revoke regrant and rapid edges reject an in flight batch and never cross epoch`() {
        val authority = authority(MemoryStore())
        assertTrue(authority.start(startEvidence()).ready)
        val oldEpoch = authority.currentStateForTest()!!.epochId
        val (permit, _) = authority.prepareQuery(1_000L, 1_100L, queryEvidence(1_050L))
        requireNotNull(permit)
        authority.onAppOpsEdge(false, 1_060L)
        authority.onAppOpsEdge(true, 1_061L)
        val rejected = authority.completeQuery(
            permit,
            ActivityUsageQueryOutcome.EVENTS,
            queryEvidence(1_070L),
        )
        assertFalse(rejected.accepted)
        assertEquals("query_epoch_tainted", rejected.fixedCode)
        val (reopenPermit, reopenCode) = authority.prepareQuery(1_000L, 1_200L, queryEvidence(1_100L))
        assertNull(reopenPermit)
        assertEquals("epoch_opened_no_backfill", reopenCode)
        val newEpoch = authority.currentStateForTest()!!
        assertNotEquals(oldEpoch, newEpoch.epochId)
        assertEquals(1_100L, newEpoch.openedAtMs)
    }

    @Test
    fun `precheck postcheck race and owner boot service mismatches fail closed`() {
        val variants = listOf(
            queryEvidence(1_060L, allowed = false) to "usage_permission_revoked",
            queryEvidence(1_060L, visible = false) to "notification_not_visible",
            queryEvidence(1_060L, foreground = false) to "foreground_state_lost",
            queryEvidence(1_060L, watcher = false) to "appops_watcher_unavailable",
            queryEvidence(1_060L, boot = 8L) to "boot_marker_changed",
            queryEvidence(1_060L, owner = "owner-b") to "owner_fence_mismatch",
            queryEvidence(1_060L, service = "service-b") to "service_instance_mismatch",
        )
        for ((post, code) in variants) {
            val authority = authority(MemoryStore())
            assertTrue(authority.start(startEvidence()).ready)
            val (permit, _) = authority.prepareQuery(1_000L, 1_100L, queryEvidence(1_050L))
            val decision = authority.completeQuery(
                requireNotNull(permit),
                ActivityUsageQueryOutcome.EVENTS,
                post,
            )
            assertFalse(code, decision.accepted)
            assertEquals(code, decision.fixedCode)
            val (retry, retryCode) = authority.prepareQuery(1_060L, 1_100L, queryEvidence(1_070L))
            assertNull(retry)
            assertEquals(
                if (code == "usage_permission_revoked") {
                    "epoch_opened_no_backfill"
                } else {
                    "activity_source_unavailable"
                },
                retryCode,
            )
        }
    }

    @Test
    fun `process death unsealed tail is tainted and recovery starts only now`() {
        val store = MemoryStore()
        val first = authority(store)
        assertTrue(first.start(startEvidence(now = 1_000L)).ready)
        val firstEpoch = store.value!!.epochId
        val recovered = authority(store)
        assertTrue(
            recovered.start(
                startEvidence(now = 5_000L, owner = "owner-new", service = "service-new"),
            ).ready,
        )
        assertNotEquals(firstEpoch, store.value!!.epochId)
        assertEquals(5_000L, store.value!!.openedAtMs)
        assertEquals("owner-new", store.value!!.ownerFence)
    }

    @Test
    fun `stop closes acceptance and reboot cannot reuse prior authority`() {
        val authority = authority(MemoryStore())
        assertTrue(authority.start(startEvidence()).ready)
        assertEquals("collector_disabled", authority.stop("task_manager_stop", 1_010L))
        val (permit, code) = authority.prepareQuery(1_000L, 1_100L, queryEvidence(1_020L))
        assertNull(permit)
        assertEquals("activity_source_unavailable", code)
        assertEquals("tainted", authority.currentStateForTest()!!.status)
        assertEquals("task_manager_stop", authority.currentStateForTest()!!.taintReason)
    }

    @Test
    fun `null exception locked expired and empty remain distinct`() {
        val outcomes = listOf(
            ActivityUsageQueryOutcome.NULL_RESULT to "usage_query_null",
            ActivityUsageQueryOutcome.EXCEPTION to "usage_query_failed",
            ActivityUsageQueryOutcome.DEVICE_LOCKED to "device_locked",
            ActivityUsageQueryOutcome.EXPIRED to "usage_events_expired",
        )
        for ((outcome, code) in outcomes) {
            val authority = authority(MemoryStore())
            assertTrue(authority.start(startEvidence()).ready)
            val (permit, _) = authority.prepareQuery(1_000L, 1_100L, queryEvidence(1_050L))
            val decision = authority.completeQuery(requireNotNull(permit), outcome, queryEvidence(1_060L))
            assertFalse(decision.accepted)
            assertEquals(code, decision.fixedCode)
            val (retry, retryCode) = authority.prepareQuery(1_060L, 1_100L, queryEvidence(1_070L))
            assertNull(retry)
            assertEquals("activity_source_unavailable", retryCode)
        }
        val emptyAuthority = authority(MemoryStore())
        assertTrue(emptyAuthority.start(startEvidence()).ready)
        val (emptyPermit, _) = emptyAuthority.prepareQuery(1_000L, 1_100L, queryEvidence(1_050L))
        val empty = emptyAuthority.completeQuery(
            requireNotNull(emptyPermit),
            ActivityUsageQueryOutcome.EMPTY,
            queryEvidence(1_060L),
        )
        assertFalse(empty.accepted)
        assertEquals("usage_query_empty_unproven", empty.fixedCode)
        assertEquals(1_100L, empty.sealedThroughMs)
    }

    @Test
    fun `corrupt and write failing state never establishes readiness`() {
        val corrupt = authority(MemoryStore(readFailure = "epoch_state_corrupt"))
        assertEquals("epoch_state_corrupt", corrupt.start(startEvidence()).fixedCode)
        val unwritable = authority(MemoryStore(writeFailure = "epoch_state_write_failed"))
        assertEquals("epoch_state_write_failed", unwritable.start(startEvidence()).fixedCode)
    }

    @Test
    fun `file store round trips exact state and rejects damaged state`() {
        val root = Files.createTempDirectory("mda2-a3f-epoch").toFile()
        try {
            val file = File(root, "epoch.properties")
            val store = FileActivityPermissionEpochStore(file)
            val state = ActivityPermissionEpochState(
                ACTIVITY_EPOCH_SCHEMA_VERSION,
                7L,
                "epoch-a",
                "owner-a",
                "service-a",
                100L,
                120L,
                "allowed",
                "open",
                "",
            )
            store.write(state)
            assertEquals(state, store.read())
            file.appendText("unexpected=field\n")
            val failure = runCatching { store.read() }.exceptionOrNull() as ActivityEpochException
            assertEquals("epoch_state_corrupt", failure.fixedCode)
        } finally {
            root.deleteRecursively()
        }
    }
}
