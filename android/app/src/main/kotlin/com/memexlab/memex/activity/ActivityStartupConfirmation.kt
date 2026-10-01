package com.memexlab.memex.activity

internal enum class ActivityStartupStep { STALE, WAITING, CONFIRMED, TERMINAL }

/** One request owns the whole dispatch -> visible notification -> epoch startup.
 * All times are supplied monotonic milliseconds. A claimed terminal attempt is
 * retained until its exact service instance releases it; no old callback can
 * cancel a successor. This is notification readiness, not an event watermark.
 */
internal class ActivityStartupConfirmation<T> {
    private enum class Phase { REQUESTED, WAITING, CONFIRMING, ACTIVE, TERMINAL }
    private data class Attempt<T>(
        val token: String, val config: T, val deadlineMs: Long,
        val callback: (Boolean, String) -> Unit,
        var owner: String? = null, var phase: Phase = Phase.REQUESTED,
        var answered: Boolean = false, var failure: String = "foreground_start_failed",
    )
    private var current: Attempt<T>? = null

    @Synchronized fun begin(token: String, config: T, deadlineMs: Long, callback: (Boolean, String) -> Unit): Boolean {
        if (current != null) { callback(false, "collector_already_active"); return false }
        current = Attempt(token, config, deadlineMs, callback)
        return true
    }

    @Synchronized fun claim(token: String, owner: String, nowMs: Long): T? {
        val attempt = current ?: return null
        if (attempt.token != token || attempt.phase != Phase.REQUESTED) return null
        if (nowMs >= attempt.deadlineMs) { fail(attempt, "foreground_start_failed"); return null }
        attempt.owner = owner
        attempt.phase = Phase.WAITING
        return attempt.config
    }

    @Synchronized fun observe(token: String, owner: String, nowMs: Long,
        usageAllowed: Boolean, notificationsAllowed: Boolean,
        foregroundVisible: Boolean, notificationVisible: Boolean): ActivityStartupStep {
        val attempt = matching(token, owner) ?: return ActivityStartupStep.STALE
        if (attempt.phase != Phase.WAITING) return ActivityStartupStep.STALE
        val failure = when {
            !usageAllowed -> "usage_permission_revoked"
            !notificationsAllowed -> "notification_not_visible"
            nowMs >= attempt.deadlineMs -> if (foregroundVisible) "notification_not_visible" else "foreground_start_failed"
            else -> null
        }
        if (failure != null) { fail(attempt, failure); return ActivityStartupStep.TERMINAL }
        if (!foregroundVisible || !notificationVisible) return ActivityStartupStep.WAITING
        attempt.phase = Phase.CONFIRMING
        return ActivityStartupStep.CONFIRMED
    }

    @Synchronized fun complete(token: String, owner: String, nowMs: Long, enabled: Boolean, code: String): Boolean {
        val attempt = matching(token, owner) ?: return false
        if (attempt.phase != Phase.CONFIRMING) return false
        if (!enabled || nowMs >= attempt.deadlineMs) {
            fail(attempt, if (nowMs >= attempt.deadlineMs) "foreground_start_failed" else code)
            return false
        }
        attempt.phase = Phase.ACTIVE
        answer(attempt, true, code)
        return true
    }

    @Synchronized fun cancelPending(token: String, reason: String): Boolean {
        val attempt = current ?: return false
        if (attempt.token != token || attempt.phase !in setOf(Phase.REQUESTED, Phase.WAITING, Phase.CONFIRMING)) return false
        fail(attempt, reason)
        return true
    }

    @Synchronized fun cancelUnclaimed(reason: String) {
        val attempt = current ?: return
        if (attempt.owner == null) cancelPending(attempt.token, reason)
    }

    @Synchronized fun expire(token: String, nowMs: Long): Boolean {
        val attempt = current ?: return false
        if (attempt.token != token || nowMs < attempt.deadlineMs) return false
        return cancelPending(token, if (attempt.owner == null) "foreground_start_failed" else "notification_not_visible")
    }

    @Synchronized fun failure(token: String): String = current?.takeIf { it.token == token }?.failure ?: "foreground_start_failed"
    @Synchronized fun hasRequest(): Boolean = current != null
    @Synchronized fun hasOwner(token: String): Boolean = current?.let { it.token == token && it.owner != null } == true
    @Synchronized fun isActive(token: String, owner: String): Boolean = matching(token, owner)?.phase == Phase.ACTIVE
    @Synchronized fun owns(token: String, owner: String): Boolean = matching(token, owner) != null

    @Synchronized fun release(owner: String, reason: String) {
        val attempt = current ?: return
        if (attempt.owner != owner) return
        current = null
        attempt.phase = Phase.TERMINAL
        answer(attempt, false, reason)
    }

    private fun matching(token: String, owner: String) = current?.takeIf { it.token == token && it.owner == owner }
    private fun fail(attempt: Attempt<T>, code: String) {
        attempt.phase = Phase.TERMINAL
        attempt.failure = code
        if (attempt.owner == null) current = null
        answer(attempt, false, code)
    }
    private fun answer(attempt: Attempt<T>, enabled: Boolean, code: String) {
        if (attempt.answered) return
        attempt.answered = true
        attempt.callback(enabled, code)
    }
}

/** The bridge owns replies separately from the independent foreground service. */
internal class ActivityStartupReplyGate {
    private var generation = 0L
    private var attached = true
    var pendingToken: String? = null; private set
    fun begin(token: String): Long? {
        if (!attached || pendingToken != null) return null
        pendingToken = token
        return ++generation
    }
    fun isCurrent(value: Long): Boolean = attached && value == generation
    fun accept(token: String, value: Long): Boolean {
        if (!isCurrent(value) || pendingToken != token) return false
        pendingToken = null
        return true
    }
    fun invalidate(detach: Boolean): String? {
        val token = pendingToken
        pendingToken = null
        generation++
        if (detach) attached = false
        return token
    }
}
