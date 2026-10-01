package com.memexlab.memex.activity

import org.junit.Assert.*
import org.junit.Test

class ActivityStartupConfirmationTest {
    private val gate = ActivityStartupConfirmation<String>()
    private val replies = mutableListOf<Pair<Boolean, String>>()
    private fun begin(token: String = "a", deadline: Long = 100) = gate.begin(token, "config", deadline) { enabled, code -> replies += enabled to code }
    private fun claim(token: String = "a", owner: String = "one", now: Long = 0) = gate.claim(token, owner, now)
    private fun observe(now: Long, fg: Boolean = true, notification: Boolean = true,
        usage: Boolean = true, permitted: Boolean = true) = gate.observe("a", "one", now, usage, permitted, fg, notification)

    @Test fun delayedNotificationAndForegroundWaitWithoutCallback() {
        begin(); claim()
        assertEquals(ActivityStartupStep.WAITING, observe(1, fg = false))
        assertEquals(ActivityStartupStep.WAITING, observe(2, notification = false))
        assertTrue(replies.isEmpty())
        assertEquals(ActivityStartupStep.CONFIRMED, observe(90))
        assertTrue(gate.complete("a", "one", 91, true, "ready"))
        assertEquals(listOf(true to "ready"), replies)
    }
    @Test fun totalDeadlineIncludesDispatchAndCannotBeExtendedByClaim() {
        begin(); assertEquals("config", claim(now = 99))
        assertEquals(ActivityStartupStep.TERMINAL, observe(100))
        assertEquals(listOf(false to "notification_not_visible"), replies)
        assertEquals(ActivityStartupStep.STALE, observe(101))
    }
    @Test fun queuedTimeoutCannotBeClaimedOrKillSuccessor() {
        begin(); assertTrue(gate.expire("a", 100)); assertNull(claim())
        assertTrue(begin("b", 300)); assertFalse(gate.expire("a", 500))
        assertEquals("config", claim("b", "two", 200))
        gate.release("one", "service_destroyed")
        assertTrue(gate.owns("b", "two"))
    }
    @Test fun explicitStopWaitingFailsOnceUntilExactOwnerDestroyed() {
        begin(); claim(); assertTrue(gate.cancelPending("a", "user_stop"))
        assertFalse(gate.cancelPending("a", "user_stop"))
        assertFalse(gate.complete("a", "one", 2, true, "ready"))
        gate.release("wrong", "service_destroyed"); assertTrue(gate.hasRequest())
        gate.release("one", "service_destroyed"); assertFalse(gate.hasRequest())
        assertEquals(listOf(false to "user_stop"), replies)
    }
    @Test fun queuedStopLeavesLateIntentUnclaimable() {
        begin(); gate.cancelUnclaimed("user_stop"); assertNull(claim()); assertFalse(gate.hasRequest())
        assertEquals(listOf(false to "user_stop"), replies)
    }
    @Test fun deniedUsageDoesNotResumeWhenLaterGranted() {
        begin(); claim(); assertEquals(ActivityStartupStep.TERMINAL, observe(1, usage = false))
        assertEquals(ActivityStartupStep.STALE, observe(2)); assertFalse(gate.complete("a", "one", 2, true, "ready"))
        assertEquals(listOf(false to "usage_permission_revoked"), replies)
    }
    @Test fun permissionEdgeFencesAlreadyConfirmingAttempt() {
        begin(); claim(); assertEquals(ActivityStartupStep.CONFIRMED, observe(1))
        assertTrue(gate.cancelPending("a", "authorization_recheck_required"))
        assertFalse(gate.complete("a", "one", 2, true, "ready"))
        assertEquals(listOf(false to "authorization_recheck_required"), replies)
    }
    @Test fun notificationPolicyDenialIsImmediateNotDeferred() {
        begin(); claim(); assertEquals(ActivityStartupStep.TERMINAL, observe(1, permitted = false))
        assertEquals(listOf(false to "notification_not_visible"), replies)
    }
    @Test fun completionPastDeadlineAndActivationExceptionFailOnce() {
        begin(); claim(); observe(99)
        assertFalse(gate.complete("a", "one", 100, true, "ready"))
        assertFalse(gate.cancelPending("a", "exception"))
        assertEquals(listOf(false to "foreground_start_failed"), replies)
    }
    @Test fun failedActivationDoesNotBecomeActive() {
        begin(); claim(); observe(1)
        assertFalse(gate.complete("a", "one", 2, false, "epoch_state_write_failed"))
        gate.release("one", "service_destroyed")
        assertEquals(listOf(false to "epoch_state_write_failed"), replies)
    }
    @Test fun activeRejectsNewOptInAndOldTimerCannotRenewOrStopIt() {
        begin(); claim(); observe(1); gate.complete("a", "one", 2, true, "ready")
        assertFalse(begin("b", 999)); assertFalse(gate.expire("a", 1000))
        assertNull(claim()); assertFalse(gate.complete("a", "one", 3, true, "ready"))
        gate.release("one", "service_destroyed")
        assertEquals(listOf(true to "ready", false to "collector_already_active"), replies)
    }
    @Test fun destroyBeforeConfirmationAndStaleOwnerAfterRestart() {
        begin(); claim(); gate.release("one", "service_destroyed")
        begin("b", 300); claim("b", "two", 10)
        gate.release("one", "service_destroyed")
        assertFalse(gate.cancelPending("a", "user_stop"))
        assertTrue(gate.owns("b", "two"))
        assertEquals(listOf(false to "service_destroyed"), replies)
    }
    @Test fun wrongTokenOwnerAndDoubleClaimCannotConfirm() {
        begin(); assertNull(claim("wrong")); claim(); assertNull(claim())
        assertEquals(ActivityStartupStep.STALE, gate.observe("a", "wrong", 1, true, true, true, true))
        assertFalse(gate.complete("a", "wrong", 1, true, "ready")); assertTrue(replies.isEmpty())
    }
    @Test fun bridgeStopGenerationRejectsOldReplyAndAllowsOneNewReply() {
        val bridge = ActivityStartupReplyGate()
        val old = bridge.begin("a")!!; assertNull(bridge.begin("duplicate"))
        assertEquals("a", bridge.invalidate(false))
        val next = bridge.begin("b")!!
        assertFalse(bridge.accept("a", old)); assertTrue(bridge.accept("b", next))
        assertFalse(bridge.accept("b", next)); assertTrue(bridge.isCurrent(next))
    }
    @Test fun bridgeDetachInvalidatesPendingAndActiveDeliveryWithoutCancellingActiveService() {
        val pending = ActivityStartupReplyGate(); val gen = pending.begin("a")!!
        assertEquals("a", pending.invalidate(true)); assertFalse(pending.accept("a", gen)); assertNull(pending.begin("b"))
        val active = ActivityStartupReplyGate(); val generation = active.begin("c")!!
        assertTrue(active.accept("c", generation)); assertNull(active.invalidate(true))
        assertFalse(active.isCurrent(generation))
    }
    @Test fun postedSuccessMustRevalidateAfterDestroyOrSuccessor() {
        begin(); claim(); observe(1); gate.complete("a", "one", 2, true, "ready")
        assertTrue(gate.isActive("a", "one"))
        gate.release("one", "service_destroyed")
        assertFalse(gate.isActive("a", "one"))
        begin("b", 300); claim("b", "two", 10)
        assertFalse(gate.isActive("a", "two"))
        assertEquals(listOf(true to "ready"), replies) // coordinator answers once; bridge dispatch revalidates.
    }
}
