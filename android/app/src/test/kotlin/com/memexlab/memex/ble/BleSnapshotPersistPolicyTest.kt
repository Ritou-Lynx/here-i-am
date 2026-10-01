package com.memexlab.memex.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BleSnapshotPersistPolicyTest {
    @Test
    fun `first live snapshot persists`() {
        assertTrue(
            BleSnapshotPersistPolicy.shouldPersist(
                lastPersistAtMs = null,
                nowMs = 10_000L,
                force = false,
                intervalMs = 30_000L,
            ),
        )
    }

    @Test
    fun `regular live snapshots are throttled for thirty seconds`() {
        assertFalse(
            BleSnapshotPersistPolicy.shouldPersist(
                lastPersistAtMs = 10_000L,
                nowMs = 39_999L,
                force = false,
                intervalMs = 30_000L,
            ),
        )
        assertTrue(
            BleSnapshotPersistPolicy.shouldPersist(
                lastPersistAtMs = 10_000L,
                nowMs = 40_000L,
                force = false,
                intervalMs = 30_000L,
            ),
        )
    }

    @Test
    fun `forced status and lifecycle snapshots bypass throttle`() {
        assertTrue(
            BleSnapshotPersistPolicy.shouldPersist(
                lastPersistAtMs = 10_000L,
                nowMs = 10_001L,
                force = true,
                intervalMs = 30_000L,
            ),
        )
    }

    @Test
    fun `wall clock rollback allows a fresh persisted snapshot`() {
        assertTrue(
            BleSnapshotPersistPolicy.shouldPersist(
                lastPersistAtMs = 100_000L,
                nowMs = 1_000L,
                force = false,
                intervalMs = 30_000L,
            ),
        )
    }
}
