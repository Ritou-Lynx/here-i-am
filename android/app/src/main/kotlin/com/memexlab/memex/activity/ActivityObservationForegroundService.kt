package com.memexlab.memex.activity

import android.Manifest
import android.app.AppOpsManager
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

internal data class ActivityObservationServiceConfig(
    val explicitOptIn: Boolean,
    val categoryMapping: Map<String, String>,
)

internal data class ActivityObservationServiceResult(
    val enabled: Boolean,
    val readiness: String,
    val observationStatus: ActivityObservationStatus? = null,
)

internal data class ActivityObservationQueryResult(
    val permission: String,
    val readiness: String,
    val usageSignals: List<ReducedActivitySignal>,
    val screenSignals: List<ReducedActivitySignal>,
    val queryStartedAtMs: Long,
    val queryFinishedAtMs: Long,
    val nativeReceivedAtMs: Long,
    val counters: Map<String, Int>,
    val deliveryEpoch: String = "",
    val deliveryId: String = "",
    val observationStatus: ActivityObservationStatus? = null,
)

/**
 * Debug-only, explicitly started Activity observation FGS. It owns no BLE,
 * Companion, check-in, boot receiver, or restart path.
 */
class ActivityObservationForegroundService : Service() {
    companion object {
        private const val ACTION_START = "com.memexlab.memex.activity.START"
        private const val ACTION_STOP = "com.memexlab.memex.activity.STOP"
        private const val EXTRA_TOKEN = "token"
        private const val CHANNEL_ID = "mda2_activity_observation_debug"
        private const val NOTIFICATION_ID = 0x4DDA3F
        private const val QUERY_INTERVAL_MS = 30_000L
        private const val START_CONFIRM_TIMEOUT_MS = 10_000L
        private const val DELIVERY_RETRY_MS = 5_000L
        private const val HERE_I_AM_V3_PACKAGE = "com.memexlab.hereiam.v3"
        private val terminalContinuityFailures = setOf(
            "activity_source_unavailable",
            "appops_watcher_unavailable",
            "boot_marker_changed",
            "boot_marker_unavailable",
            "device_locked",
            "epoch_state_corrupt",
            "epoch_state_write_failed",
            "foreground_state_lost",
            "notification_not_visible",
            "owner_fence_mismatch",
            "service_instance_mismatch",
            "usage_events_expired",
            "usage_query_failed",
            "usage_query_null",
        )

        private val control = ActivityObservationControlState(UUID.randomUUID().toString())
        internal val outboxLeases = ActivityDiagnosticOutboxLeaseBroker { UUID.randomUUID().toString() }
        private val statusListeners = mutableMapOf<String, (ActivityObservationStatus) -> Unit>()
        internal fun observationStatus(): ActivityObservationStatus = control.snapshot()
        internal fun setStatusListener(token: String, listener: ((ActivityObservationStatus) -> Unit)?) {
            if (listener == null) statusListeners.remove(token) else statusListeners[token] = listener
        }
        private fun publishStatus() {
            val snapshot = control.snapshot()
            Handler(Looper.getMainLooper()).post {
                statusListeners.values.toList().forEach { it(snapshot) }
            }
        }
        private fun statusFor(token: String): ActivityObservationStatus? = control.snapshot().takeIf { it.observationId == token }
        private val startup = ActivityStartupConfirmation<ActivityObservationServiceConfig>()
        private const val START_CONFIRM_POLL_MS = 100L
        @Volatile private var live: ActivityObservationForegroundService? = null
        private var deliveryListener: ((ActivityObservationQueryResult, (List<String>?) -> Unit) -> Unit)? = null
        private var deliveryListenerToken: String? = null

        internal fun setDeliveryListener(token: String, listener: ((ActivityObservationQueryResult, (List<String>?) -> Unit) -> Unit)?) {
            if (listener == null && deliveryListenerToken != token) return
            deliveryListenerToken = if (listener == null) null else token
            deliveryListener = listener
            if (listener != null) live?.mainHandler?.post { live?.pushPending() }
            if (listener == null) live?.let { service ->
                synchronized(service) { service.counters["bridge_disconnects"] = service.counters.getValue("bridge_disconnects") + 1 }
            }
        }

        internal fun acknowledge(epoch: String, id: String, dispositions: List<String>): Boolean {
            val service = live ?: return false
            return synchronized(service) {
                if (!service.deliveryAllowed(epoch)) return@synchronized false
                service.delivery.acknowledge(epoch, id, dispositions)
            }
        }

        internal fun requestStart(
            context: Context,
            config: ActivityObservationServiceConfig,
            requestToken: String,
            callback: (ActivityObservationServiceResult) -> Unit,
        ): Boolean {
            if (!config.explicitOptIn) {
                callback(ActivityObservationServiceResult(false, "activity_opt_in_required"))
                return false
            }
            if (!control.begin(requestToken)) {
                callback(ActivityObservationServiceResult(false, "collector_already_active"))
                return false
            }
            publishStatus()
            val deadline = SystemClock.elapsedRealtime() + START_CONFIRM_TIMEOUT_MS
            if (!startup.begin(requestToken, config, deadline) { enabled, code ->
                    Handler(Looper.getMainLooper()).post {
                        // A stop/destroy may have won after completion but before reply dispatch.
                        val service = live
                        val stillActive = service != null && service.active &&
                            startup.isActive(requestToken, service.serviceInstanceId)
                        if (!enabled && !startup.hasOwner(requestToken)) {
                            control.unclaimedStopped(requestToken, code)
                            publishStatus()
                        }
                        callback((if (enabled && !stillActive) {
                            ActivityObservationServiceResult(false, "collector_disabled")
                        } else ActivityObservationServiceResult(enabled, code)).copy(observationStatus = statusFor(requestToken)))
                    }
                }) return false
            val intent = Intent(context, ActivityObservationForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TOKEN, requestToken)
            }
            try {
                context.startForegroundService(intent)
                Handler(Looper.getMainLooper()).postDelayed({
                    if (startup.expire(requestToken, SystemClock.elapsedRealtime())) {
                        live?.stopMatchingStartup(requestToken, startup.failure(requestToken))
                    }
                }, START_CONFIRM_TIMEOUT_MS)
            } catch (_: RuntimeException) {
                startup.cancelPending(requestToken, "foreground_start_not_allowed")
                return false
            }
            return true
        }

        internal fun cancelPendingStart(token: String, reason: String) {
            if (startup.cancelPending(token, reason)) live?.stopMatchingStartup(token, reason)
        }

        internal fun requestQuery(
            observationId: String,
            startMs: Long,
            endMs: Long,
            callback: (ActivityObservationQueryResult) -> Unit,
        ) {
            val service = live
            if (service == null || !service.active || service.startupToken != observationId) {
                callback(unavailableQuery("activity_source_unavailable").copy(observationStatus = statusFor(observationId)))
                return
            }
            service.queryAsync(startMs, endMs, callback)
        }

        internal fun requestStop(session: String, observation: String, callback: (String, ActivityObservationStatus) -> Unit) {
            val snapshot = control.snapshot()
            if (!control.matches(session, observation)) { callback("target_changed", snapshot); return }
            if (snapshot.state == "stopped") { callback("stopped", snapshot); return }
            if (snapshot.state == "unknown") { callback("unknown", snapshot); return }
            val service = live
            if (service != null && service.startupToken == observation) {
                var answered = false
                val reply: (String, ActivityObservationStatus) -> Unit = { outcome, status ->
                    if (!answered) { answered = true; callback(outcome, status) }
                }
                service.stopReplies.add(reply)
                service.mainHandler.postDelayed({
                    if (!answered) {
                        service.stopReplies.remove(reply)
                        reply("unknown", control.snapshot())
                    }
                }, 3_000L)
                service.stopObservation("user_stop")
            } else if (!startup.hasOwner(observation) && startup.cancelPending(observation, "user_stop")) {
                control.unclaimedStopped(observation, "user_stop")
                publishStatus()
                callback("stopped", control.snapshot())
            } else callback("unknown", snapshot)
        }

        internal fun injectNotificationEvidenceLoss(session: String, observation: String): Boolean {
            val service = live ?: return false
            if (!control.matches(session, observation) || service.startupToken != observation || !service.active ||
                service.packageName != HERE_I_AM_V3_PACKAGE ||
                (service.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return false
            service.debugNotificationEvidenceLost = true
            // Uses the production epoch continuity check; never calls stop directly.
            service.queryExecutor.execute { service.queryAndAccumulate(System.currentTimeMillis() + 1L) }
            return true
        }

        internal fun readiness(): ActivityObservationServiceResult {
            val service = live ?: return ActivityObservationServiceResult(false, "collector_disabled")
            return ActivityObservationServiceResult(service.active, service.readiness)
        }

        private fun unavailableQuery(code: String) = ActivityObservationQueryResult(
            permission = "denied",
            readiness = code,
            usageSignals = emptyList(),
            screenSignals = emptyList(),
            queryStartedAtMs = 0L,
            queryFinishedAtMs = 0L,
            nativeReceivedAtMs = System.currentTimeMillis(),
            counters = mapOf("query_failures" to 0, "dropped_events" to 0),
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val queryExecutor = Executors.newSingleThreadExecutor()
    private val accessGate by lazy { AndroidUsageAccessGate(applicationContext) }
    private val eventSource by lazy { AndroidActivityUsageEventSource(applicationContext) }
    private val epochAuthority by lazy {
        ActivityPermissionEpochAuthority(
            FileActivityPermissionEpochStore(
                File(noBackupFilesDir, "mda2_activity_authority/epoch.properties"),
            ),
        )
    }
    private val ownerFence = UUID.randomUUID().toString()
    private val serviceInstanceId = UUID.randomUUID().toString()
    private val delivery = ActivityDeliveryLedger()
    private var pushInFlight = false
    private val counters = linkedMapOf("query_failures" to 0, "dropped_events" to 0, "bridge_disconnects" to 0, "bridge_failures" to 0)
    private var categoryMapping: Map<String, String> = emptyMap()
    private var watcherRegistered = false
    private var foregroundStarted = false
    private var epochActivated = false
    @Volatile private var active = false
    private var readiness = "collector_disabled"
    private var permission = "denied"
    private var screenReceiver: DynamicScreenSignalReceiver? = null
    private var appOps: AppOpsManager? = null
    private var appOpsListener: AppOpsManager.OnOpChangedListener? = null
    @Volatile private var stopping = false
    @Volatile private var startupToken: String? = null
    private var startupPoll: Runnable? = null
    @Volatile private var debugNotificationEvidenceLost = false
    private var cleanupSucceeded = true
    private val stopReplies = mutableListOf<(String, ActivityObservationStatus) -> Unit>()
    private val periodicQuery = object : Runnable {
        override fun run() {
            if (!active) return
            queryExecutor.execute { queryAndAccumulate(System.currentTimeMillis() + 1L); mainHandler.post { pushPending() } }
            mainHandler.postDelayed(this, QUERY_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            when (activityStopIntentAction(intent.getStringExtra(EXTRA_TOKEN), startupToken, live === this)) {
                ActivityStopIntentAction.STOP_OBSERVATION -> stopObservation("notification_stop")
                ActivityStopIntentAction.STOP_EMPTY_INSTANCE -> stopSelfResult(startId)
                ActivityStopIntentAction.IGNORE -> Unit
            }
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START) {
            if (activityEmptyInstanceShouldStop(startupToken, live === this)) stopSelfResult(startId)
            return START_NOT_STICKY
        }
        val token = intent.getStringExtra(EXTRA_TOKEN)
        if (stopping) {
            if (token != null) startup.cancelPending(token, "foreground_start_failed")
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        val config = token?.let { startup.claim(it, serviceInstanceId, SystemClock.elapsedRealtime()) }
        if (config == null) {
            // A stale intent must not stop a live or queued successor request.
            if (activityEmptyInstanceShouldStop(startupToken, live === this)) stopSelfResult(startId)
            return START_NOT_STICKY
        }
        startupToken = token
        live = this
        beginActivation(requireNotNull(token), config)
        return START_NOT_STICKY
    }

    private fun beginActivation(token: String, config: ActivityObservationServiceConfig) {
        readiness = "activity_starting"
        val debugDiagnostic = packageName == HERE_I_AM_V3_PACKAGE &&
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debugDiagnostic) return failStartup(token, "debug_diagnostic_required")
        // Only the permission watcher is allowed before notification confirmation.
        if (!registerAppOpsWatcher()) return failStartup(token, "appops_watcher_unavailable")
        try {
            if (!accessGate.isGranted()) return failStartup(token, "usage_permission_denied")
            createNotificationChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foregroundStarted = true
        } catch (_: Exception) {
            return failStartup(token, "foreground_start_failed")
        }
        scheduleStartupConfirmation(token, config)
    }

    private fun scheduleStartupConfirmation(token: String, config: ActivityObservationServiceConfig) {
        val poll = object : Runnable {
            override fun run() {
                if (stopping || !startup.owns(token, serviceInstanceId)) return
                try {
                    val step = startup.observe(
                        token, serviceInstanceId, SystemClock.elapsedRealtime(),
                        usageAllowed = accessGate.isGranted(),
                        notificationsAllowed = isNotificationPermitted(),
                        foregroundVisible = isForegroundActuallyRunning(),
                        notificationVisible = isNotificationVisible(),
                    )
                    when (step) {
                        ActivityStartupStep.WAITING -> mainHandler.postDelayed(this, START_CONFIRM_POLL_MS)
                        ActivityStartupStep.CONFIRMED -> {
                            val result = activateConfirmed(config)
                            if (!startup.complete(token, serviceInstanceId, SystemClock.elapsedRealtime(), result.enabled, result.readiness)) {
                                stopMatchingStartup(token, startup.failure(token))
                            } else {
                                control.running(token)
                                publishStatus()
                            }
                        }
                        ActivityStartupStep.TERMINAL -> stopMatchingStartup(token, startup.failure(token))
                        ActivityStartupStep.STALE -> Unit
                    }
                } catch (_: Exception) {
                    failStartup(token, "foreground_start_failed")
                }
            }
        }
        startupPoll = poll
        mainHandler.post(poll)
    }

    private fun failStartup(token: String, code: String) {
        startup.cancelPending(token, code)
        stopMatchingStartup(token, code)
    }

    private fun stopMatchingStartup(token: String, reason: String) {
        if (startupToken == token && startup.owns(token, serviceInstanceId)) stopObservation(reason)
    }

    private fun activateConfirmed(config: ActivityObservationServiceConfig): ActivityObservationServiceResult {
        val foregroundConfirmed = isForegroundActuallyRunning()
        if (!foregroundConfirmed) {
            return ActivityObservationServiceResult(false, "foreground_state_lost")
        }
        val notificationVisible = isNotificationVisible()
        // A visibility loss after confirmation is a real continuity failure.
        if (!notificationVisible || !watcherRegistered) {
            return ActivityObservationServiceResult(false, "notification_not_visible")
        }
        val allowed = accessGate.isGranted()
        permission = if (allowed) "granted" else "denied"
        categoryMapping = config.categoryMapping
        val decision = epochAuthority.start(
            ActivityObservationStartEvidence(
                explicitOptIn = config.explicitOptIn,
                foregroundStarted = foregroundConfirmed,
                notificationVisible = notificationVisible,
                watcherRegistered = watcherRegistered,
                appOpsAllowed = allowed,
                debugDiagnostic = true,
                bootMarker = bootMarker(),
                ownerFence = ownerFence,
                serviceInstanceId = serviceInstanceId,
                observedAtMs = System.currentTimeMillis(),
            ),
        )
        if (!decision.ready) return ActivityObservationServiceResult(false, decision.fixedCode)
        epochActivated = true
        delivery.reset(epochAuthority.currentStateForTest()!!.epochId)
        try {
            screenReceiver = DynamicScreenSignalReceiver(applicationContext) {
                if (active) queryExecutor.execute { queryAndAccumulate(System.currentTimeMillis() + 1L); mainHandler.post { pushPending() } }
            }.also { it.start() }
        } catch (_: RuntimeException) {
            return ActivityObservationServiceResult(false, "foreground_start_failed")
        }
        active = true
        readiness = "ready"
        mainHandler.postDelayed(periodicQuery, QUERY_INTERVAL_MS)
        return ActivityObservationServiceResult(true, "ready")
    }

    private fun queryAsync(
        startMs: Long,
        endMs: Long,
        callback: (ActivityObservationQueryResult) -> Unit,
    ) {
        queryExecutor.execute {
            val direct = queryAndAccumulate(endMs, startMs)
            val result = synchronized(this) { deliveryResult(direct) }
            mainHandler.post {
                if (!active || stopping || (result.deliveryId.isNotEmpty() && !deliveryAllowed(result.deliveryEpoch))) {
                    callback(emptyQuery("query_epoch_tainted", result.queryStartedAtMs, System.currentTimeMillis()))
                } else callback(result)
            }
        }
    }

    private fun queryAndAccumulate(
        requestedEndMs: Long,
        requestedStartMs: Long = 0L,
    ): ActivityObservationQueryResult {
        val queryStartClock = System.currentTimeMillis()
        if (!active || stopping) return emptyQuery("collector_disabled", queryStartClock, queryStartClock)
        val evidence = queryEvidence(queryStartClock)
        val (permit, code) = epochAuthority.prepareQuery(requestedStartMs, requestedEndMs, evidence)
        if (permit == null) {
            if (code == "epoch_opened_no_backfill") synchronized(this) {
                delivery.reset(epochAuthority.currentStateForTest()!!.epochId)
            }
            readiness = code
            stopForContinuityLoss(code)
            return emptyQuery(code, queryStartClock, System.currentTimeMillis())
        }
        val raw = eventSource.query(permit.startMs, permit.endMs)
        val outcome = when (raw) {
            is ActivityUsageEventQueryResult.Available -> if (raw.events.isEmpty()) {
                ActivityUsageQueryOutcome.EMPTY
            } else {
                ActivityUsageQueryOutcome.EVENTS
            }
            ActivityUsageEventQueryResult.NullResult -> ActivityUsageQueryOutcome.NULL_RESULT
            ActivityUsageEventQueryResult.DeviceLocked -> ActivityUsageQueryOutcome.DEVICE_LOCKED
            ActivityUsageEventQueryResult.Failed -> ActivityUsageQueryOutcome.EXCEPTION
        }
        val finishedAt = System.currentTimeMillis()
        val decision = epochAuthority.completeQuery(permit, outcome, queryEvidence(finishedAt))
        readiness = decision.fixedCode
        if (decision.fixedCode == "usage_permission_revoked") permission = "revoked"
        if (!decision.accepted) {
            if (outcome !in setOf(ActivityUsageQueryOutcome.EMPTY, ActivityUsageQueryOutcome.EVENTS)) {
                counters["query_failures"] = counters.getValue("query_failures") + 1
            }
            stopForContinuityLoss(decision.fixedCode)
            return emptyQuery(decision.fixedCode, permit.queryStartedAtMs, finishedAt)
        }
        val reduced = ActivityUsageEventReducer.reduce(
            (raw as ActivityUsageEventQueryResult.Available).events,
            permit.startMs,
            permit.endMs,
            categoryMapping,
        )
        synchronized(this) {
            if (deliveryAllowed(permit.epochId)) {
                delivery.append(reduced.usageSignals + reduced.screenSignals, finishedAt)
            } else {
                counters["dropped_events"] = counters.getValue("dropped_events") +
                    reduced.usageSignals.size + reduced.screenSignals.size
            }
        }
        return emptyQuery(decision.fixedCode, permit.queryStartedAtMs, finishedAt)
    }

    private fun emptyQuery(code: String, startedAt: Long, finishedAt: Long) =
        ActivityObservationQueryResult(
            permission = permission,
            readiness = code,
            usageSignals = emptyList(),
            screenSignals = emptyList(),
            queryStartedAtMs = startedAt,
            queryFinishedAtMs = finishedAt,
            nativeReceivedAtMs = finishedAt,
            counters = counters.toMap(),
            observationStatus = startupToken?.let(::statusFor),
        )

    private fun deliveryAllowed(epoch: String): Boolean {
        val state = epochAuthority.currentStateForTest() ?: return false
        val evidence = queryEvidence(System.currentTimeMillis())
        return active && !stopping && state.status == "open" && state.epochId == epoch &&
            evidence.foregroundStarted && evidence.notificationVisible && evidence.watcherRegistered &&
            evidence.appOpsAllowed && evidence.bootMarker == state.bootMarker &&
            evidence.ownerFence == state.ownerFence && evidence.serviceInstanceId == state.serviceInstanceId
    }

    private fun deliveryResult(direct: ActivityObservationQueryResult): ActivityObservationQueryResult {
        val epoch = epochAuthority.currentStateForTest()?.epochId ?: ""
        val batch = if (deliveryAllowed(epoch)) delivery.batch(System.currentTimeMillis()) else null
        val diagnostics = counters + mapOf(
            "expired_before_acceptance" to delivery.expired,
            "overflow_batches" to delivery.overflowBatches,
            "abandoned_events" to delivery.abandoned,
            "terminal_rejections" to delivery.rejected,
        )
        return direct.copy(
            usageSignals = batch?.signals?.filter { it.type == "usage_category" } ?: emptyList(),
            screenSignals = batch?.signals?.filter { it.type != "usage_category" } ?: emptyList(),
            deliveryEpoch = batch?.epoch ?: "", deliveryId = batch?.id ?: "",
            nativeReceivedAtMs = System.currentTimeMillis(), counters = diagnostics,
        )
    }

    private fun pushPending() {
        if (!active || pushInFlight) return
        if (deliveryListenerToken != startupToken) return
        val listener = deliveryListener ?: return
        val result = synchronized(this) { deliveryResult(emptyQuery(readiness, 0L, 0L)) }
        pushInFlight = true
        var completed = false
        val finish: (List<String>?) -> Unit = { outcomes ->
            if (!completed) {
                completed = true
                pushInFlight = false
                if (outcomes == null || (result.deliveryId.isNotEmpty() && !acknowledge(result.deliveryEpoch, result.deliveryId, outcomes))) {
                    synchronized(this) { counters["bridge_failures"] = counters.getValue("bridge_failures") + 1 }
                }
                // Retry scheduling is not evidence of system publication completeness.
                if (active && result.deliveryId.isNotEmpty()) mainHandler.postDelayed({ pushPending() }, DELIVERY_RETRY_MS)
            }
        }
        mainHandler.postDelayed({ finish(null) }, DELIVERY_RETRY_MS)
        try {
            if (result.deliveryId.isEmpty() || deliveryAllowed(result.deliveryEpoch)) listener(result, finish) else finish(null)
        } catch (_: RuntimeException) {
            finish(null)
        }
    }

    private fun queryEvidence(nowMs: Long) = ActivityQueryEvidence(
        foregroundStarted = isForegroundActuallyRunning(),
        notificationVisible = isNotificationVisible(),
        watcherRegistered = watcherRegistered,
        appOpsAllowed = accessGate.isGranted(),
        bootMarker = bootMarker(),
        ownerFence = ownerFence,
        serviceInstanceId = serviceInstanceId,
        observedAtMs = nowMs,
    )

    private fun registerAppOpsWatcher(): Boolean = try {
        val manager = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val listener = AppOpsManager.OnOpChangedListener { _, changedPackage ->
            if (changedPackage != null && changedPackage != packageName) return@OnOpChangedListener
            if (stopping) return@OnOpChangedListener
            val token = startupToken
            // Fence completion synchronously even if AppOps delivers on a binder thread.
            // Reply delivery and all Service/receiver cleanup run on the main looper.
            val cancelled = token != null && startup.cancelPending(token, "authorization_recheck_required")
            mainHandler.post {
                if (stopping) return@post
                if (cancelled) {
                    stopMatchingStartup(token, "authorization_recheck_required")
                    return@post
                }
                val allowed = runCatching { accessGate.isGranted() }.getOrDefault(false)
                permission = if (allowed) "granted" else "revoked"
                readiness = epochAuthority.onAppOpsEdge(allowed, System.currentTimeMillis())
                synchronized(this) { delivery.reset("") }
                stopForContinuityLoss(readiness)
            }
        }
        manager.startWatchingMode(AppOpsManager.OPSTR_GET_USAGE_STATS, packageName, listener)
        appOps = manager
        appOpsListener = listener
        watcherRegistered = true
        true
    } catch (_: Exception) {
        false
    }

    private fun unregisterAppOpsWatcher() {
        val listener = appOpsListener
        if (listener != null) appOps?.stopWatchingMode(listener)
        appOpsListener = null
        appOps = null
        watcherRegistered = false
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Activity observation diagnostic",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Visible notice for opt-in coarse activity and screen observation"
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, ActivityObservationForegroundService::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_TOKEN, startupToken)
            data = android.net.Uri.parse("activity-observation-stop:" + startupToken)
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            NOTIFICATION_ID,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                }
            }
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle("活动观察正在运行")
            .setContentText("仅采集粗类别和屏幕状态；可随时停止")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                    "停止活动观察",
                    stopPendingIntent,
                ).build(),
            )
            .build()
    }

    private fun isNotificationPermitted(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return false
        val channel = manager.getNotificationChannel(CHANNEL_ID) ?: return false
        return channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun isNotificationVisible(): Boolean {
        if (debugNotificationEvidenceLost || !foregroundStarted || !isNotificationPermitted()) return false
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return runCatching {
            manager.activeNotifications.any { it.id == NOTIFICATION_ID }
        }.getOrDefault(false)
    }

    @Suppress("DEPRECATION")
    private fun isForegroundActuallyRunning(): Boolean {
        if (!foregroundStarted) return false
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return runCatching {
            manager.getRunningServices(Int.MAX_VALUE).any {
                it.service.className == ActivityObservationForegroundService::class.java.name &&
                    it.foreground
            }
        }.getOrDefault(false)
    }

    private fun bootMarker(): Long? = runCatching {
        Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT).toLong()
    }.getOrNull()

    private fun stopForContinuityLoss(code: String) {
        if (code !in terminalContinuityFailures) return
        mainHandler.post { stopObservation(code) }
    }

    private fun stopObservation(reason: String) {
        if (stopping) return
        stopping = true
        active = false // Close delivery before cleanup or asynchronous drain.
        val token = startupToken ?: return
        control.stopping(token, reason)
        publishStatus()
        startupPoll?.let(mainHandler::removeCallbacks)
        startupPoll = null
        startup.cancelPending(token, reason)
        mainHandler.removeCallbacks(periodicQuery)
        val receiverStopped = runCatching { screenReceiver?.stop() ?: true }.getOrDefault(false)
        cleanupSucceeded = receiverStopped && cleanupSucceeded
        if (receiverStopped) screenReceiver = null
        cleanupSucceeded = runCatching { unregisterAppOpsWatcher() }.isSuccess && cleanupSucceeded
        synchronized(this) { delivery.reset("") }
        readiness = reason
        cleanupSucceeded = runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }.isSuccess && cleanupSucceeded
        // A serial barrier runs only after all accepted worker tasks. Neither
        // shutdownNow nor live == null establishes this terminal condition.
        queryExecutor.execute {
            val epochStopped = runCatching {
                if (foregroundStarted) epochAuthority.stop(reason, System.currentTimeMillis())
                activityEpochStopConfirmed(epochActivated, epochAuthority.currentStateForTest()?.status)
            }.getOrDefault(false)
            mainHandler.post {
                categoryMapping = emptyMap()
                control.drained(token, cleanupSucceeded && epochStopped)
                finishStopIfKnown()
            }
        }
        queryExecutor.shutdown()
        if (runCatching { stopSelf() }.isFailure) cleanupSucceeded = false
    }

    private fun finishStopIfKnown() {
        val status = control.snapshot()
        publishStatus()
        if (status.observationId != startupToken || status.state !in setOf("stopped", "unknown")) return
        if (status.state == "stopped") startup.release(serviceInstanceId, status.reason)
        val replies = stopReplies.toList(); stopReplies.clear()
        replies.forEach { it(if (status.state == "stopped") "stopped" else "failed", status) }
    }

    override fun onDestroy() {
        if (!stopping) stopObservation("service_destroyed")
        if (live === this) live = null
        startupToken?.let { control.destroyed(it) }
        finishStopIfKnown()
        super.onDestroy()
    }
}
