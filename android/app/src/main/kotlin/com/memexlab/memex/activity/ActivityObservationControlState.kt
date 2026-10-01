package com.memexlab.memex.activity

/** Process-local control identity. Never an authority for the Dart owner.json. */
internal data class ActivityObservationStatus(
    val sessionId: String,
    val observationId: String,
    val revision: Long,
    val state: String,
    val reason: String,
) {
    val enabled: Boolean get() = state == "running"
    fun toMap(): Map<String, Any> = mapOf(
        "version" to 1, "session_id" to sessionId, "observation_id" to observationId,
        "revision" to revision, "state" to state, "enabled" to enabled, "reason" to reason,
    )
}

/** A terminal receipt requires both worker drain and Service destruction. */
internal class ActivityObservationControlState(private val sessionId: String) {
    private var current = ActivityObservationStatus(sessionId, "", 0, "unknown", "activity_source_unavailable")
    private val reasons = setOf(
        "activity_source_unavailable", "activity_starting", "ready", "collector_disabled", "user_stop", "notification_stop",
        "service_destroyed", "foreground_start_not_allowed", "foreground_start_failed", "foreground_state_lost", "notification_not_visible",
        "appops_watcher_unavailable", "boot_marker_unavailable", "boot_marker_changed", "owner_fence_mismatch", "service_instance_mismatch",
        "usage_permission_denied", "usage_permission_revoked", "activity_opt_in_required", "debug_diagnostic_required", "activity_authority_invalid",
        "epoch_state_corrupt", "epoch_state_write_failed", "device_locked", "usage_events_expired", "usage_query_failed", "usage_query_null", "observation_stop_failed",
    )
    private var drained = false
    private var destroyed = false
    private var cleanupFailed = false

    @Synchronized fun snapshot(): ActivityObservationStatus = current
    @Synchronized fun matches(session: String, observation: String): Boolean =
        session == sessionId && observation.isNotEmpty() && observation == current.observationId
    @Synchronized fun begin(observation: String): Boolean {
        if (observation.isEmpty() || (current.observationId.isNotEmpty() && current.state != "stopped")) return false
        drained = false; destroyed = false; cleanupFailed = false
        current = ActivityObservationStatus(sessionId, observation, current.revision + 1, "starting", "activity_starting")
        return true
    }
    @Synchronized fun running(observation: String): Boolean {
        if (current.observationId != observation || current.state != "starting") return false
        update("running", "ready"); return true
    }
    @Synchronized fun stopping(observation: String, reason: String): Boolean {
        if (current.observationId != observation || current.state !in setOf("starting", "running")) return false
        update("stopping", if (reason in reasons) reason else "observation_stop_failed"); return true
    }
    @Synchronized fun drained(observation: String, succeeded: Boolean) {
        if (current.observationId != observation || current.state !in setOf("stopping", "unknown")) return
        drained = true; cleanupFailed = cleanupFailed || !succeeded; finish()
    }
    @Synchronized fun destroyed(observation: String) {
        if (current.observationId != observation || current.state !in setOf("stopping", "unknown")) return
        destroyed = true; finish()
    }
    @Synchronized fun unclaimedStopped(observation: String, reason: String) {
        if (!stopping(observation, reason)) return
        drained = true; destroyed = true; finish()
    }
    private fun finish() {
        if (cleanupFailed) {
            if (current.state != "unknown") update("unknown", "observation_stop_failed")
        } else if (drained && destroyed && current.state != "stopped") update("stopped", current.reason)
    }
    private fun update(state: String, reason: String) { current = current.copy(revision = current.revision + 1, state = state, reason = reason) }
}

/** Supplements POSIX process-scoped file locks across engines and Dart isolates.
 * A lease is never dropped on bridge detach: a writer may still hold an FD.
 */
internal class ActivityDiagnosticOutboxLeaseBroker(private val newToken: () -> String) {
    private val leases = mutableMapOf<String, String>()
    private val sources = setOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_SCREEN_STATE_SOURCE)
    private var permit: String? = null
    private val lastReleased = mutableMapOf<String, String>()
    private var lastEndedPermit: String? = null
    @Synchronized fun acquire(source: String, permitToken: String = ""): String? {
        require(source in sources)
        if ((permit == null && permitToken.isNotEmpty()) || (permit != null && permit != permitToken)) return null
        if (source in leases) return null
        if (permit != null && source == ANDROID_SCREEN_STATE_SOURCE && ANDROID_USAGE_EVENTS_SOURCE !in leases) return null
        return newToken().also { leases[source] = it; lastReleased.remove(source) }
    }
    @Synchronized fun release(source: String, token: String): Boolean {
        require(source in sources)
        val current = leases[source]
        if (current == null) return token.isNotEmpty() && lastReleased[source] == token
        if (current != token) return false
        leases.remove(source)
        lastReleased[source] = token
        return true
    }
    @Synchronized fun authorizesActivation(tokens: Map<String, String>): Boolean =
        permit == null && tokens.keys == sources && tokens.all { (source, token) -> leases[source] == token }
    @Synchronized fun beginRelease(status: ActivityObservationStatus, session: String, observation: String): String? {
        if (permit != null || leases.isNotEmpty() || status.state != "stopped" ||
            status.sessionId != session || status.observationId != observation || observation.isEmpty()) return null
        return newToken().also { permit = it; lastEndedPermit = null }
    }
    @Synchronized fun endRelease(token: String): Boolean {
        if (token.isEmpty() || leases.isNotEmpty()) return false
        val current = permit
        if (current == null) return lastEndedPermit == token
        if (current != token) return false
        permit = null
        lastEndedPermit = token
        return true
    }
}

internal fun activityEpochStopConfirmed(wasActivated: Boolean, status: String?): Boolean =
    !wasActivated || (status != null && status != "open")

internal enum class ActivityStopIntentAction { STOP_OBSERVATION, STOP_EMPTY_INSTANCE, IGNORE }
internal fun activityStopIntentAction(incomingToken: String?, instanceToken: String?, ownsLive: Boolean): ActivityStopIntentAction = when {
    instanceToken == null && !ownsLive -> ActivityStopIntentAction.STOP_EMPTY_INSTANCE
    instanceToken != null && incomingToken == instanceToken && ownsLive -> ActivityStopIntentAction.STOP_OBSERVATION
    else -> ActivityStopIntentAction.IGNORE
}
internal fun activityEmptyInstanceShouldStop(instanceToken: String?, ownsLive: Boolean): Boolean =
    instanceToken == null && !ownsLive
