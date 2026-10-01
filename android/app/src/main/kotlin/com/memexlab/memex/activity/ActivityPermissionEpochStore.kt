package com.memexlab.memex.activity

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Properties
import java.util.UUID

internal const val ACTIVITY_EPOCH_SCHEMA_VERSION = 1
internal const val ACTIVITY_RESCAN_AGE_MS = 300_000L

internal class ActivityEpochException(val fixedCode: String) : Exception(fixedCode)

internal data class ActivityPermissionEpochState(
    val schemaVersion: Int,
    val bootMarker: Long,
    val epochId: String,
    val ownerFence: String,
    val serviceInstanceId: String,
    val openedAtMs: Long,
    val sealedThroughMs: Long,
    val lastMode: String,
    val status: String,
    val taintReason: String,
)

internal interface ActivityPermissionEpochStore {
    fun read(): ActivityPermissionEpochState?
    fun write(state: ActivityPermissionEpochState)
}

/**
 * Exact, atomic state for the Android-only observation authority. The file is
 * not authority by itself: every query also proves the live watcher, foreground
 * visibility, boot marker, owner fence, service instance, and AppOps mode.
 */
internal class FileActivityPermissionEpochStore(private val file: File) : ActivityPermissionEpochStore {
    private val exactKeys = setOf(
        "schema_version",
        "boot_marker",
        "epoch_id",
        "owner_fence",
        "service_instance_id",
        "opened_at_ms",
        "sealed_through_ms",
        "last_mode",
        "status",
        "taint_reason",
    )

    override fun read(): ActivityPermissionEpochState? {
        if (!file.exists()) return null
        val properties = Properties()
        try {
            FileInputStream(file).use(properties::load)
        } catch (_: Exception) {
            throw ActivityEpochException("epoch_state_corrupt")
        }
        if (properties.stringPropertyNames() != exactKeys) {
            throw ActivityEpochException("epoch_state_corrupt")
        }
        val state = try {
            ActivityPermissionEpochState(
                schemaVersion = properties.required("schema_version").toInt(),
                bootMarker = properties.required("boot_marker").toLong(),
                epochId = properties.required("epoch_id"),
                ownerFence = properties.required("owner_fence"),
                serviceInstanceId = properties.required("service_instance_id"),
                openedAtMs = properties.required("opened_at_ms").toLong(),
                sealedThroughMs = properties.required("sealed_through_ms").toLong(),
                lastMode = properties.required("last_mode"),
                status = properties.required("status"),
                taintReason = properties.getProperty("taint_reason")
                    ?: throw ActivityEpochException("epoch_state_corrupt"),
            )
        } catch (_: Exception) {
            throw ActivityEpochException("epoch_state_corrupt")
        }
        validate(state)
        return state
    }

    override fun write(state: ActivityPermissionEpochState) {
        validate(state)
        val parent = file.parentFile ?: throw ActivityEpochException("epoch_state_write_failed")
        if ((!parent.exists() && !parent.mkdirs()) || !parent.isDirectory) {
            throw ActivityEpochException("epoch_state_write_failed")
        }
        val temporary = File(parent, "${file.name}.tmp")
        val properties = Properties().apply {
            setProperty("schema_version", state.schemaVersion.toString())
            setProperty("boot_marker", state.bootMarker.toString())
            setProperty("epoch_id", state.epochId)
            setProperty("owner_fence", state.ownerFence)
            setProperty("service_instance_id", state.serviceInstanceId)
            setProperty("opened_at_ms", state.openedAtMs.toString())
            setProperty("sealed_through_ms", state.sealedThroughMs.toString())
            setProperty("last_mode", state.lastMode)
            setProperty("status", state.status)
            setProperty("taint_reason", state.taintReason)
        }
        try {
            FileOutputStream(temporary, false).use { output ->
                properties.store(output, null)
                output.fd.sync()
            }
            Files.move(
                temporary.toPath(),
                file.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (error: ActivityEpochException) {
            throw error
        } catch (_: Exception) {
            throw ActivityEpochException("epoch_state_write_failed")
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun Properties.required(key: String): String =
        getProperty(key)?.takeIf { it.isNotBlank() }
            ?: throw ActivityEpochException("epoch_state_corrupt")

    private fun validate(state: ActivityPermissionEpochState) {
        if (state.schemaVersion != ACTIVITY_EPOCH_SCHEMA_VERSION ||
            state.bootMarker < 0L ||
            state.openedAtMs < 0L ||
            state.sealedThroughMs < state.openedAtMs ||
            state.lastMode !in setOf("allowed", "denied", "unknown") ||
            state.status !in setOf("open", "tainted", "closed") ||
            state.epochId.isBlank() ||
            state.ownerFence.isBlank() ||
            state.serviceInstanceId.isBlank() ||
            (state.status == "open" && state.taintReason.isNotEmpty()) ||
            (state.status != "open" && state.taintReason.isEmpty())
        ) {
            throw ActivityEpochException("epoch_state_corrupt")
        }
    }
}

internal data class ActivityObservationStartEvidence(
    val explicitOptIn: Boolean,
    val foregroundStarted: Boolean,
    val notificationVisible: Boolean,
    val watcherRegistered: Boolean,
    val appOpsAllowed: Boolean,
    val debugDiagnostic: Boolean,
    val bootMarker: Long?,
    val ownerFence: String,
    val serviceInstanceId: String,
    val observedAtMs: Long,
)

internal data class ActivityQueryEvidence(
    val foregroundStarted: Boolean,
    val notificationVisible: Boolean,
    val watcherRegistered: Boolean,
    val appOpsAllowed: Boolean,
    val bootMarker: Long?,
    val ownerFence: String,
    val serviceInstanceId: String,
    val observedAtMs: Long,
)

internal data class ActivityEpochStartDecision(val ready: Boolean, val fixedCode: String)

internal data class ActivityEpochQueryPermit(
    val epochId: String,
    val generation: Long,
    val startMs: Long,
    val endMs: Long,
    val queryStartedAtMs: Long,
)

internal data class ActivityEpochQueryDecision(
    val accepted: Boolean,
    val fixedCode: String,
    val sealedThroughMs: Long,
)

internal enum class ActivityUsageQueryOutcome {
    EVENTS,
    EMPTY,
    NULL_RESULT,
    EXCEPTION,
    DEVICE_LOCKED,
    EXPIRED,
}

/** The service uses this exact state machine; tests do not mirror it. */
internal class ActivityPermissionEpochAuthority(
    private val store: ActivityPermissionEpochStore,
    private val newId: () -> String = { UUID.randomUUID().toString() },
) {
    private var state: ActivityPermissionEpochState? = null
    private var generation = 0L
    private var live = false
    private var watcherRegistered = false
    private var foregroundStarted = false
    private var notificationVisible = false

    @Synchronized
    fun start(evidence: ActivityObservationStartEvidence): ActivityEpochStartDecision {
        if (!evidence.explicitOptIn) return ActivityEpochStartDecision(false, "activity_opt_in_required")
        if (!evidence.debugDiagnostic) return ActivityEpochStartDecision(false, "debug_diagnostic_required")
        if (!evidence.foregroundStarted) return ActivityEpochStartDecision(false, "foreground_start_failed")
        if (!evidence.notificationVisible) return ActivityEpochStartDecision(false, "notification_not_visible")
        if (!evidence.watcherRegistered) return ActivityEpochStartDecision(false, "appops_watcher_unavailable")
        if (!evidence.appOpsAllowed) return ActivityEpochStartDecision(false, "usage_permission_denied")
        val boot = evidence.bootMarker ?: return ActivityEpochStartDecision(false, "boot_marker_unavailable")
        if (evidence.observedAtMs < 0L || evidence.ownerFence.isBlank() || evidence.serviceInstanceId.isBlank()) {
            return ActivityEpochStartDecision(false, "activity_authority_invalid")
        }
        try {
            val previous = store.read()
            if (previous != null && previous.status == "open") {
                store.write(previous.copy(status = "tainted", taintReason = "unclean_previous_owner"))
            }
            state = ActivityPermissionEpochState(
                schemaVersion = ACTIVITY_EPOCH_SCHEMA_VERSION,
                bootMarker = boot,
                epochId = newId(),
                ownerFence = evidence.ownerFence,
                serviceInstanceId = evidence.serviceInstanceId,
                openedAtMs = evidence.observedAtMs,
                sealedThroughMs = evidence.observedAtMs,
                lastMode = "allowed",
                status = "open",
                taintReason = "",
            ).also(store::write)
        } catch (error: ActivityEpochException) {
            state = null
            return ActivityEpochStartDecision(false, error.fixedCode)
        }
        generation++
        live = true
        watcherRegistered = true
        foregroundStarted = true
        notificationVisible = true
        return ActivityEpochStartDecision(true, "ready")
    }

    @Synchronized
    fun onAppOpsEdge(allowed: Boolean, observedAtMs: Long): String {
        generation++
        val current = state
        if (current != null && current.status == "open") {
            val reason = if (allowed) "appops_edge_allowed" else "appops_edge_denied"
            try {
                state = current.copy(
                    lastMode = if (allowed) "allowed" else "denied",
                    status = "tainted",
                    taintReason = reason,
                    sealedThroughMs = maxOf(current.sealedThroughMs, observedAtMs),
                ).also(store::write)
            } catch (_: ActivityEpochException) {
                state = null
                live = false
                return "epoch_state_write_failed"
            }
        }
        return if (allowed) "authorization_recheck_required" else "usage_permission_revoked"
    }

    @Synchronized
    fun prepareQuery(
        requestedStartMs: Long,
        requestedEndMs: Long,
        evidence: ActivityQueryEvidence,
    ): Pair<ActivityEpochQueryPermit?, String> {
        if (!live) return null to "activity_source_unavailable"
        val invalid = liveEvidenceFailure(evidence)
        if (invalid != null) {
            taint(invalid, evidence.observedAtMs)
            if (invalid != "usage_permission_revoked") live = false
            return null to invalid
        }
        val current = state ?: return null to "activity_source_unavailable"
        if (current.status != "open") {
            if (current.taintReason !in recoverableAuthorizationTaints) {
                live = false
                return null to "activity_source_unavailable"
            }
            return reopenFromCurrent(evidence)
        }
        if (requestedStartMs < 0L || requestedEndMs <= requestedStartMs) {
            return null to "invalid_query_window"
        }
        // Query progress is NOT a UsageEvents publication watermark. Revisit the
        // still-eligible tail of this live authorization epoch, including EMPTY.
        val start = maxOf(current.openedAtMs, evidence.observedAtMs - ACTIVITY_RESCAN_AGE_MS)
        if (requestedEndMs <= start) return null to "usage_query_window_consumed"
        return ActivityEpochQueryPermit(
            epochId = current.epochId,
            generation = generation,
            startMs = start,
            endMs = requestedEndMs,
            queryStartedAtMs = evidence.observedAtMs,
        ) to "query_quarantined"
    }

    @Synchronized
    fun completeQuery(
        permit: ActivityEpochQueryPermit,
        outcome: ActivityUsageQueryOutcome,
        evidence: ActivityQueryEvidence,
    ): ActivityEpochQueryDecision {
        val invalid = liveEvidenceFailure(evidence)
        val current = state
        if (invalid != null ||
            current == null ||
            current.status != "open" ||
            current.epochId != permit.epochId ||
            permit.generation != generation
        ) {
            val code = invalid ?: "query_epoch_tainted"
            taint(code, evidence.observedAtMs)
            if (invalid != null && invalid != "usage_permission_revoked") live = false
            return ActivityEpochQueryDecision(false, code, current?.sealedThroughMs ?: 0L)
        }
        if (outcome !in setOf(ActivityUsageQueryOutcome.EVENTS, ActivityUsageQueryOutcome.EMPTY)) {
            val code = when (outcome) {
                ActivityUsageQueryOutcome.NULL_RESULT -> "usage_query_null"
                ActivityUsageQueryOutcome.EXCEPTION -> "usage_query_failed"
                ActivityUsageQueryOutcome.DEVICE_LOCKED -> "device_locked"
                ActivityUsageQueryOutcome.EXPIRED -> "usage_events_expired"
                else -> "usage_query_failed"
            }
            taint(code, evidence.observedAtMs)
            live = false
            return ActivityEpochQueryDecision(false, code, current.sealedThroughMs)
        }
        // Legacy persisted field records query progress only; never used to exclude events.
        val sealed = current.copy(sealedThroughMs = maxOf(current.sealedThroughMs, permit.endMs), lastMode = "allowed")
        try {
            store.write(sealed)
            state = sealed
        } catch (_: ActivityEpochException) {
            state = null
            live = false
            return ActivityEpochQueryDecision(false, "epoch_state_write_failed", current.sealedThroughMs)
        }
        return ActivityEpochQueryDecision(
            accepted = outcome == ActivityUsageQueryOutcome.EVENTS,
            fixedCode = if (outcome == ActivityUsageQueryOutcome.EMPTY) {
                "usage_query_empty_unproven"
            } else {
                "ready"
            },
            sealedThroughMs = permit.endMs,
        )
    }

    @Synchronized
    fun stop(reason: String, observedAtMs: Long): String {
        generation++
        taint(reason, observedAtMs)
        live = false
        watcherRegistered = false
        foregroundStarted = false
        notificationVisible = false
        return "collector_disabled"
    }

    @Synchronized
    fun currentStateForTest(): ActivityPermissionEpochState? = state

    private fun reopenFromCurrent(evidence: ActivityQueryEvidence): Pair<ActivityEpochQueryPermit?, String> {
        val boot = evidence.bootMarker ?: return null to "boot_marker_unavailable"
        val reopened = ActivityPermissionEpochState(
            schemaVersion = ACTIVITY_EPOCH_SCHEMA_VERSION,
            bootMarker = boot,
            epochId = newId(),
            ownerFence = evidence.ownerFence,
            serviceInstanceId = evidence.serviceInstanceId,
            openedAtMs = evidence.observedAtMs,
            sealedThroughMs = evidence.observedAtMs,
            lastMode = "allowed",
            status = "open",
            taintReason = "",
        )
        return try {
            store.write(reopened)
            state = reopened
            generation++
            null to "epoch_opened_no_backfill"
        } catch (_: ActivityEpochException) {
            state = null
            live = false
            null to "epoch_state_write_failed"
        }
    }

    private fun liveEvidenceFailure(evidence: ActivityQueryEvidence): String? {
        val current = state ?: return "activity_source_unavailable"
        return when {
            !foregroundStarted || !evidence.foregroundStarted -> "foreground_state_lost"
            !notificationVisible || !evidence.notificationVisible -> "notification_not_visible"
            !watcherRegistered || !evidence.watcherRegistered -> "appops_watcher_unavailable"
            !evidence.appOpsAllowed -> "usage_permission_revoked"
            evidence.bootMarker == null -> "boot_marker_unavailable"
            evidence.bootMarker != current.bootMarker -> "boot_marker_changed"
            evidence.ownerFence != current.ownerFence -> "owner_fence_mismatch"
            evidence.serviceInstanceId != current.serviceInstanceId -> "service_instance_mismatch"
            else -> null
        }
    }

    private fun taint(reason: String, observedAtMs: Long) {
        val current = state ?: return
        if (current.status != "open") return
        try {
            state = current.copy(
                status = "tainted",
                taintReason = reason,
                sealedThroughMs = maxOf(current.sealedThroughMs, observedAtMs),
                lastMode = if (reason.contains("permission")) "denied" else current.lastMode,
            ).also(store::write)
        } catch (_: ActivityEpochException) {
            state = null
            live = false
        }
    }

    private companion object {
        val recoverableAuthorizationTaints = setOf(
            "appops_edge_allowed",
            "appops_edge_denied",
            "usage_permission_revoked",
        )
    }
}
