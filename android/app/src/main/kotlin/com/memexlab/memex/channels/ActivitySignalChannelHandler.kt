package com.memexlab.memex.channels

import android.app.Activity
import android.content.pm.ApplicationInfo
import com.memexlab.memex.activity.ANDROID_SCREEN_STATE_SOURCE
import com.memexlab.memex.activity.ANDROID_USAGE_EVENTS_SOURCE
import com.memexlab.memex.activity.ActivityActivationGate
import com.memexlab.memex.activity.ActivityObservationForegroundService
import com.memexlab.memex.activity.ActivityObservationServiceConfig
import com.memexlab.memex.activity.ActivityObservationStatus
import com.memexlab.memex.activity.ActivityObservationQueryResult
import com.memexlab.memex.activity.ActivityStartupReplyGate
import com.memexlab.memex.activity.ActivitySignalPolicyException
import com.memexlab.memex.activity.ActivitySignalRequestPolicy
import com.memexlab.memex.activity.UsagePermissionLifecycle
import com.memexlab.memex.activity.UsagePermissionState
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Activity-only bridge. It never calls or reuses PhoneUsageChannelHandler and
 * never returns package names, application names, or raw UsageEvents.
 */
class ActivitySignalChannelHandler private constructor(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    companion object {
        private const val CHANNEL = "com.memexlab.memex/activity_signal"

        fun register(flutterEngine: FlutterEngine, activity: Activity) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            val handler = ActivitySignalChannelHandler(activity, channel)
            channel.setMethodCallHandler(handler::onMethodCall)
            flutterEngine.addEngineLifecycleListener(
                object : FlutterEngine.EngineLifecycleListener {
                    override fun onPreEngineRestart() {
                        handler.detachBridge()
                    }

                    override fun onEngineWillDestroy() {
                        handler.detachBridge()
                        channel.setMethodCallHandler(null)
                    }
                },
            )
        }
    }

    private val appContext = activity.applicationContext
    private val permissionLifecycle = UsagePermissionLifecycle()
    private val counters = linkedMapOf(
        "query_failures" to 0,
        "dropped_events" to 0,
    )
    private var active = false
    private val startupReplies = ActivityStartupReplyGate()
    private var pendingActivationResult: MethodChannel.Result? = null
    private var deliveryToken: String? = null
    private var categoryMapping: Map<String, String> = emptyMap()
    private var permission = UsagePermissionState.DENIED
    private val statusListenerToken = UUID.randomUUID().toString()
    private var attached = true
    private var ownedObservation: ActivityObservationStatus? = null
    private var currentGeneration: Long? = null

    init {
        ActivityObservationForegroundService.setStatusListener(statusListenerToken) { status ->
            if (attached) {
                if (status.observationId == ownedObservation?.observationId) {
                    ownedObservation = status
                    if (!status.enabled) active = false
                }
                channel.invokeMethod("onObservationStatus", status.toMap())
            }
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method in setOf("activateObservation", "stopObservation", "debugInvalidateObservationNotification",
                "acquireDiagnosticOutboxLease", "releaseDiagnosticOutboxLease", "beginDiagnosticOwnerRelease", "endDiagnosticOwnerRelease") &&
            (appContext.packageName != "com.memexlab.hereiam.v3" || (appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0)) {
            return fixedError(result, "debug_diagnostic_required")
        }
        when (call.method) {
            "acknowledgeBatch" -> {
                val ack = call.arguments as? Map<*, *>
                val epoch = ack?.get("delivery_epoch") as? String
                val id = ack?.get("delivery_id") as? String
                val dispositions = ack?.get("dispositions") as? List<*>
                if (ack?.keys != setOf("delivery_epoch", "delivery_id", "dispositions") ||
                    epoch == null || id == null || dispositions == null || dispositions.any { it !is String }) {
                    fixedError(result, "invalid_delivery_ack")
                } else {
                    result.success(ActivityObservationForegroundService.acknowledge(epoch, id, dispositions.filterIsInstance<String>()))
                }
            }
            "activate" -> fixedError(result, "observation_control_required")
            "activateObservation" -> activate(call.arguments, result)
            "getObservationStatus" -> result.success(ActivityObservationForegroundService.observationStatus().toMap())
            "stopObservation" -> stopTarget(call.arguments, result)
            "debugInvalidateObservationNotification" -> {
                val target = target(call.arguments) ?: return fixedError(result, "observation_status_invalid")
                result.success(mapOf("accepted" to ActivityObservationForegroundService.injectNotificationEvidenceLoss(target.first, target.second)))
            }
            "acquireDiagnosticOutboxLease" -> {
                val args = exactStrings(call.arguments, setOf("source", "permit_token"))
                    ?: return fixedError(result, "diagnostic_outbox_lease_invalid")
                val source = args.getValue("source")
                if (source !in sourceNames) return fixedError(result, "diagnostic_outbox_lease_invalid")
                val lease = ActivityObservationForegroundService.outboxLeases.acquire(source, args.getValue("permit_token"))
                    ?: return fixedError(result, "diagnostic_outbox_lease_held")
                result.success(mapOf("source" to source, "lease_token" to lease))
            }
            "releaseDiagnosticOutboxLease" -> {
                val args = exactStrings(call.arguments, setOf("source", "lease_token"))
                    ?: return fixedError(result, "diagnostic_outbox_lease_invalid")
                val source = args.getValue("source")
                if (source !in sourceNames) return fixedError(result, "diagnostic_outbox_lease_invalid")
                result.success(mapOf("released" to ActivityObservationForegroundService.outboxLeases.release(source, args.getValue("lease_token"))))
            }
            "beginDiagnosticOwnerRelease" -> {
                val target = target(call.arguments) ?: return fixedError(result, "observation_status_invalid")
                val status = ActivityObservationForegroundService.observationStatus()
                val permit = ActivityObservationForegroundService.outboxLeases.beginRelease(status, target.first, target.second)
                    ?: return fixedError(result, "diagnostic_owner_release_refused")
                result.success(mapOf("permit_token" to permit, "status" to status.toMap()))
            }
            "endDiagnosticOwnerRelease" -> {
                val args = exactStrings(call.arguments, setOf("permit_token"))
                    ?: return fixedError(result, "diagnostic_outbox_lease_invalid")
                result.success(mapOf("released" to ActivityObservationForegroundService.outboxLeases.endRelease(args.getValue("permit_token"))))
            }
            "deactivate" -> {
                val owned = ownedObservation
                if (owned == null) return fixedError(result, "observation_control_required")
                shutdown()
                ActivityObservationForegroundService.requestStop(owned.sessionId, owned.observationId) { outcome, status ->
                    if (attached) result.success(readiness(if (outcome == "stopped") "collector_disabled" else "activity_source_unavailable") + mapOf("observation_status" to status.toMap()))
                }
            }
            "getReadiness" -> {
                val service = ActivityObservationForegroundService.readiness()
                active = service.enabled
                result.success(readiness(service.readiness))
            }
            "getOutboxRoot" -> result.success(
                mapOf(
                    "path" to File(appContext.noBackupFilesDir, "mda2_activity").absolutePath,
                    "storage_scope" to "no_backup_private",
                ),
            )
            "queryUsageEvents" -> queryUsageEvents(call.arguments, result)
            else -> result.notImplemented()
        }
    }

    private fun activate(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *> ?: return fixedError(result, "invalid_activation_request")
        val tokens = exactStrings(args["lease_tokens"], sourceNames)
            ?: return fixedError(result, "diagnostic_outbox_lease_invalid")
        if (!ActivityObservationForegroundService.outboxLeases.authorizesActivation(tokens)) {
            return fixedError(result, "diagnostic_outbox_lease_held")
        }
        val request = try {
            ActivitySignalRequestPolicy.parseActivation(args.filterKeys { it != "lease_tokens" })
        } catch (error: ActivitySignalPolicyException) {
            return fixedError(result, error.fixedCode)
        }
        if (active || startupReplies.pendingToken != null) return fixedError(result, "collector_already_active")
        val decision = ActivityActivationGate.decide(
            request.enabled,
            request.integrityAuthorityReady,
            request.boundSources,
        )
        if (!decision.active) {
            shutdown()
            result.success(readiness(decision.fixedCode) + mapOf("observation_status" to null))
            return
        }
        categoryMapping = request.categoryMapping
        val requestToken = UUID.randomUUID().toString()
        val requestGeneration = startupReplies.begin(requestToken)
            ?: return fixedError(result, "collector_disabled")
        pendingActivationResult = result
        currentGeneration = requestGeneration
        val accepted = ActivityObservationForegroundService.requestStart(
            appContext,
            ActivityObservationServiceConfig(
                explicitOptIn = request.enabled,
                categoryMapping = categoryMapping,
            ),
            requestToken = requestToken,
        ) { service ->
            if (!startupReplies.accept(requestToken, requestGeneration)) return@requestStart
            pendingActivationResult = null
            ownedObservation = service.observationStatus
            active = service.enabled && service.observationStatus?.enabled == true
            permission = if (service.enabled) {
                permissionLifecycle.observe(true)
            } else {
                permissionLifecycle.observe(false)
            }
            result.success(readiness(service.readiness) + mapOf("observation_status" to service.observationStatus?.toMap()))
        }
        if (accepted && startupReplies.isCurrent(requestGeneration)) {
            ownedObservation = ActivityObservationForegroundService.observationStatus().takeIf { it.observationId == requestToken }
            deliveryToken = requestToken
            ActivityObservationForegroundService.setDeliveryListener(requestToken) { batch, acknowledge ->
                if (!startupReplies.isCurrent(requestGeneration) || !active || batch.observationStatus?.observationId != requestToken) {
                    acknowledge(null)
                    return@setDeliveryListener
                }
                channel.invokeMethod("onBatch", batchResult(batch), object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (!startupReplies.isCurrent(requestGeneration) || !active) { acknowledge(null); return }
                        val ack = result as? Map<*, *>
                        val outcomes = ack?.get("dispositions") as? List<*>
                        if (ack?.keys == setOf("delivery_epoch", "delivery_id", "dispositions") &&
                            ack["delivery_epoch"] == batch.deliveryEpoch && ack["delivery_id"] == batch.deliveryId &&
                            outcomes != null && outcomes.all { it is String }) {
                            acknowledge(outcomes.filterIsInstance<String>())
                        } else acknowledge(null)
                    }
                    override fun error(code: String, message: String?, details: Any?) { acknowledge(null) }
                    override fun notImplemented() { acknowledge(null) }
                })
            }
        }

    }

    private fun queryUsageEvents(arguments: Any?, result: MethodChannel.Result) {
        val window = try {
            ActivitySignalRequestPolicy.parseQuery(arguments)
        } catch (error: ActivitySignalPolicyException) {
            return fixedError(result, error.fixedCode)
        }
        if (!active) {
            result.success(
                queryResult(
                    code = "collector_disabled",
                    usageSignals = emptyList(),
                    screenSignals = emptyList(),
                    queryStartedAtMs = 0L,
                    queryFinishedAtMs = 0L,
                    nativeReceivedAtMs = System.currentTimeMillis(),
                ) + mapOf("observation_status" to ownedObservation?.toMap()),
            )
            return
        }

        val requestedObservation = ownedObservation ?: return fixedError(result, "observation_control_required")
        val generation = currentGeneration
        ActivityObservationForegroundService.requestQuery(requestedObservation.observationId, window.startMs, window.endMs) { batch ->
            if (!attached) return@requestQuery
            if (generation == null || !startupReplies.isCurrent(generation) || !active ||
                batch.observationStatus?.observationId != requestedObservation.observationId) {
                result.success(batchResult(batch.copy(readiness = "collector_disabled", usageSignals = emptyList(), screenSignals = emptyList(), deliveryEpoch = "", deliveryId = "")))
                return@requestQuery
            }
            permission = permissionLifecycle.observe(batch.permission == "granted")
            counters.putAll(batch.counters)
            result.success(batchResult(batch))
        }
    }

    private fun batchResult(batch: ActivityObservationQueryResult): Map<String, Any?> =
        queryResult(batch.readiness, batch.usageSignals.map { it.toFlutterMap() },
            batch.screenSignals.map { it.toFlutterMap() }, batch.queryStartedAtMs,
            batch.queryFinishedAtMs, batch.nativeReceivedAtMs) + mapOf(
            "permission" to batch.permission, "counters" to batch.counters,
            "delivery_epoch" to batch.deliveryEpoch, "delivery_id" to batch.deliveryId,
            "observation_status" to batch.observationStatus?.toMap(),
        )

    private fun queryResult(
        code: String,
        usageSignals: List<Map<String, Any>>,
        screenSignals: List<Map<String, Any>>,
        queryStartedAtMs: Long,
        queryFinishedAtMs: Long,
        nativeReceivedAtMs: Long,
    ): Map<String, Any> = mapOf(
        "source" to ANDROID_USAGE_EVENTS_SOURCE,
        "permission" to permission.wireValue,
        "readiness" to code,
        "signals" to usageSignals,
        "screen_signals" to screenSignals,
        "query_started_at_ms" to queryStartedAtMs,
        "query_finished_at_ms" to queryFinishedAtMs,
        "native_received_at_ms" to nativeReceivedAtMs,
        "counters" to counters.toMap(),
    )

    private fun readiness(code: String): Map<String, Any> = mapOf(
        "enabled" to active,
        "readiness" to code,
        "usage_source" to ANDROID_USAGE_EVENTS_SOURCE,
        "screen_source" to ANDROID_SCREEN_STATE_SOURCE,
        "usage_permission" to permission.wireValue,
        "counters" to counters.toMap(),
    )

    private fun fixedError(result: MethodChannel.Result, code: String) {
        result.error(code, null, null)
    }

    private val sourceNames get() = setOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_SCREEN_STATE_SOURCE)
    private fun exactStrings(value: Any?, keys: Set<String>): Map<String, String>? {
        val map = value as? Map<*, *> ?: return null
        if (map.keys != keys || map.values.any { it !is String }) return null
        return keys.associateWith { map[it] as String }
    }
    private fun target(value: Any?): Pair<String, String>? {
        val args = exactStrings(value, setOf("session_id", "observation_id")) ?: return null
        if (args.values.any { it.isEmpty() }) return null
        return args.getValue("session_id") to args.getValue("observation_id")
    }
    private fun stopTarget(arguments: Any?, result: MethodChannel.Result) {
        val target = target(arguments) ?: return fixedError(result, "observation_status_invalid")
        if (target.second == ownedObservation?.observationId && target.first == ownedObservation?.sessionId) shutdown()
        ActivityObservationForegroundService.requestStop(target.first, target.second) { outcome, status ->
            if (attached) result.success(mapOf("outcome" to outcome, "status" to status.toMap()))
        }
    }

    private fun clearDeliveryListener() {
        deliveryToken?.let { ActivityObservationForegroundService.setDeliveryListener(it, null) }
        deliveryToken = null
    }

    private fun shutdown() {
        val pending = startupReplies.invalidate(detach = false)
        val reply = pendingActivationResult
        pendingActivationResult = null
        active = false
        clearDeliveryListener()
        if (pending != null) ActivityObservationForegroundService.cancelPendingStart(pending, "collector_disabled")
        // The caller performs an exact targeted stop after invalidating this bridge.
        categoryMapping = emptyMap()
        // A live engine receives exactly one cancellation; the later startup result is stale.
        reply?.success(readiness("collector_disabled") + mapOf("observation_status" to ownedObservation?.toMap()))
    }

    /** Detach cancels only an unconfirmed start. An active FGS remains independent. */
    private fun detachBridge() {
        attached = false
        ActivityObservationForegroundService.setStatusListener(statusListenerToken, null)
        val pending = startupReplies.invalidate(detach = true)
        pendingActivationResult = null // never invoke a result owned by a dead engine
        active = false
        clearDeliveryListener()
        if (pending != null) ActivityObservationForegroundService.cancelPendingStart(pending, "collector_disabled")
        categoryMapping = emptyMap()
    }
}
