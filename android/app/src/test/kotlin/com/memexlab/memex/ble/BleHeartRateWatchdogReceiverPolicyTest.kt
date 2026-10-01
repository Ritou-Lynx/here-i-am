package com.memexlab.memex.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BleHeartRateWatchdogReceiverPolicyTest {
    private val plan = BleConnectWatchdogPlan(12L, 4L, 25_000L, "AA:BB:CC:DD:EE:FF")

    @Test
    fun `matching durable alarm is forwarded`() {
        assertTrue(
            BleHeartRateWatchdogReceiverPolicy.shouldForward(
                BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM,
                plan.token,
                plan.generation,
                plan,
            ),
        )
    }

    @Test
    fun `invalid or stale alarm never starts the service`() {
        val action = BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM
        assertFalse(BleHeartRateWatchdogReceiverPolicy.shouldForward(null, plan.token, plan.generation, plan))
        assertFalse(BleHeartRateWatchdogReceiverPolicy.shouldForward(action, 0L, plan.generation, plan))
        assertFalse(BleHeartRateWatchdogReceiverPolicy.shouldForward(action, plan.token, 0L, plan))
        assertFalse(BleHeartRateWatchdogReceiverPolicy.shouldForward(action, 11L, plan.generation, plan))
        assertFalse(BleHeartRateWatchdogReceiverPolicy.shouldForward(action, plan.token, 5L, plan))
        assertFalse(BleHeartRateWatchdogReceiverPolicy.shouldForward(action, plan.token, plan.generation, null))
    }

    @Test
    fun `foreground service start failure is diagnosed and rearmed without changing identity`() {
        val diagnostics = mutableListOf<String>()
        var persisted = plan
        var rearmed: BleConnectWatchdogPlan? = null
        val controller = BleHeartRateWatchdogReceiverController(
            nowMs = { 30_000L },
            startService = { _, _ -> false },
            persistRetry = { expected, replacement ->
                if (persisted != expected) {
                    false
                } else {
                    persisted = replacement
                    true
                }
            },
            rearmAlarm = {
                rearmed = it
                true
            },
            onDiagnostic = diagnostics::add,
        )

        val outcome = controller.onAlarm(
            BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM,
            plan.token,
            plan.generation,
            plan,
        )

        assertEquals(BleWatchdogReceiverOutcome.START_FAILED_REARMED, outcome)
        assertEquals(plan.token, rearmed?.token)
        assertEquals(plan.generation, rearmed?.generation)
        assertEquals(plan.deviceAddress, rearmed?.deviceAddress)
        assertEquals(90_000L, rearmed?.dueAtMs)
        assertEquals(rearmed, persisted)
        assertEquals(
            listOf(
                "connect_watchdog_fgs_start_failed",
                "connect_watchdog_alarm_rearmed_after_fgs_start_failed",
            ),
            diagnostics,
        )
    }

    @Test
    fun `failed alarm rearm is explicit and stale alarms never invoke effects`() {
        val diagnostics = mutableListOf<String>()
        var starts = 0
        var rearms = 0
        val controller = BleHeartRateWatchdogReceiverController(
            nowMs = { 30_000L },
            startService = { _, _ ->
                starts += 1
                false
            },
            persistRetry = { _, _ -> true },
            rearmAlarm = {
                rearms += 1
                false
            },
            onDiagnostic = diagnostics::add,
        )

        assertEquals(
            BleWatchdogReceiverOutcome.IGNORED,
            controller.onAlarm(
                BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM,
                plan.token + 1L,
                plan.generation,
                plan,
            ),
        )
        assertEquals(0, starts)
        assertEquals(0, rearms)
        assertTrue(diagnostics.isEmpty())

        assertEquals(
            BleWatchdogReceiverOutcome.START_FAILED_REARM_FAILED,
            controller.onAlarm(
                BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM,
                plan.token,
                plan.generation,
                plan,
            ),
        )
        assertEquals(1, starts)
        assertEquals(1, rearms)
        assertEquals(
            listOf(
                "connect_watchdog_fgs_start_failed",
                "connect_watchdog_alarm_rearm_failed_after_fgs_start_failed",
            ),
            diagnostics,
        )
    }

    @Test
    fun `same identity late delivery before persisted retry deadline never starts service`() {
        val retryPlan = plan.copy(dueAtMs = 90_000L)
        val diagnostics = mutableListOf<String>()
        var starts = 0
        var rearmed: BleConnectWatchdogPlan? = null
        val controller = BleHeartRateWatchdogReceiverController(
            nowMs = { 31_000L },
            startService = { _, _ ->
                starts += 1
                true
            },
            persistRetry = { _, _ -> error("early alarm must not replace durable plan") },
            rearmAlarm = {
                rearmed = it
                true
            },
            onDiagnostic = diagnostics::add,
        )

        assertEquals(
            BleWatchdogReceiverOutcome.EARLY_REARMED,
            controller.onAlarm(
                BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM,
                retryPlan.token,
                retryPlan.generation,
                retryPlan,
            ),
        )
        assertEquals(0, starts)
        assertEquals(retryPlan, rearmed)
        assertEquals(listOf("connect_watchdog_early_alarm_rearmed"), diagnostics)
    }

    @Test
    fun `failed retry persistence never schedules an unowned replacement alarm`() {
        val diagnostics = mutableListOf<String>()
        var rearms = 0
        val controller = BleHeartRateWatchdogReceiverController(
            nowMs = { 30_000L },
            startService = { _, _ -> false },
            persistRetry = { _, _ -> false },
            rearmAlarm = {
                rearms += 1
                true
            },
            onDiagnostic = diagnostics::add,
        )

        assertEquals(
            BleWatchdogReceiverOutcome.START_FAILED_REARM_PERSIST_FAILED,
            controller.onAlarm(
                BleHeartRateWatchdogReceiverPolicy.ACTION_CONNECT_WATCHDOG_ALARM,
                plan.token,
                plan.generation,
                plan,
            ),
        )
        assertEquals(0, rearms)
        assertEquals(
            listOf(
                "connect_watchdog_fgs_start_failed",
                "connect_watchdog_rearm_persist_failed_after_fgs_start_failed",
            ),
            diagnostics,
        )
    }
}
