package com.memexlab.memex.ble

import org.junit.Assert.assertEquals
import org.junit.Test

class BleConnectWatchdogPolicyTest {
    private val plan = BleConnectWatchdogPlan(
        token = 10L,
        generation = 4L,
        dueAtMs = 25_000L,
        deviceAddress = ADDRESS,
    )

    @Test
    fun `current GATT attempt times out`() {
        assertEquals(
            BleConnectWatchdogAction.TIMEOUT_ACTIVE_ATTEMPT,
            decide(),
        )
    }

    @Test
    fun `process replacement recovers one abandoned persisted attempt`() {
        assertEquals(
            BleConnectWatchdogAction.RECOVER_ABANDONED_ATTEMPT,
            decide(status = "starting", hasGatt = false, activeGeneration = 0L, activeAddress = null),
        )
    }

    @Test
    fun `old generation and old address cannot close a newer GATT`() {
        assertEquals(
            BleConnectWatchdogAction.IGNORE,
            decide(activeGeneration = 5L),
        )
        assertEquals(
            BleConnectWatchdogAction.IGNORE,
            decide(activeAddress = "11:22:33:44:55:66"),
        )
    }

    @Test
    fun `retry waiting without a GATT is not mistaken for abandoned connect`() {
        assertEquals(
            BleConnectWatchdogAction.IGNORE,
            decide(status = "reconnecting", hasGatt = false),
        )
    }

    @Test
    fun `terminal adapter and live states never reconnect`() {
        assertEquals(BleConnectWatchdogAction.IGNORE, decide(stoppedExplicitly = true))
        assertEquals(BleConnectWatchdogAction.IGNORE, decide(enabled = false))
        assertEquals(BleConnectWatchdogAction.IGNORE, decide(adapterEnabled = false))
        assertEquals(BleConnectWatchdogAction.IGNORE, decide(status = "live"))
    }

    private fun decide(
        stoppedExplicitly: Boolean = false,
        enabled: Boolean = true,
        adapterEnabled: Boolean = true,
        status: String = "connecting",
        activeGeneration: Long = 4L,
        activeAddress: String? = ADDRESS,
        hasGatt: Boolean = true,
    ): BleConnectWatchdogAction = BleConnectWatchdogPolicy.decide(
        plan,
        BleConnectAttemptState(
            stoppedExplicitly = stoppedExplicitly,
            enabled = enabled,
            adapterEnabled = adapterEnabled,
            status = status,
            activeGeneration = activeGeneration,
            activeAddress = activeAddress,
            hasGatt = hasGatt,
        ),
    )

    companion object {
        private const val ADDRESS = "AA:BB:CC:DD:EE:FF"
    }
}
