package com.memexlab.memex.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BleNotificationRefreshPolicyTest {
    @Test
    fun `first live state is shown immediately`() {
        assertTrue(shouldNotify(statusChanged = true, elapsedMs = 0L))
    }

    @Test
    fun `stable live redraw is suppressed inside one minute`() {
        assertFalse(shouldNotify(statusChanged = false, elapsedMs = 59_999L))
    }

    @Test
    fun `stable live redraw is allowed at one minute boundary`() {
        assertTrue(shouldNotify(statusChanged = false, elapsedMs = 60_000L))
    }

    @Test
    fun `forced status update bypasses live throttle`() {
        assertTrue(
            BleNotificationRefreshPolicy.shouldNotify(
                force = true,
                statusChanged = false,
                elapsedSinceLastMs = 1L,
            ),
        )
    }

    private fun shouldNotify(statusChanged: Boolean, elapsedMs: Long): Boolean =
        BleNotificationRefreshPolicy.shouldNotify(
            force = false,
            statusChanged = statusChanged,
            elapsedSinceLastMs = elapsedMs,
        )
}
