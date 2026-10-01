package com.memexlab.memex.ble

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.util.UUID

class BleHeartRateService : Service() {
    companion object {
        const val ACTION_START = "com.memexlab.memex.ble.START"
        const val ACTION_STOP = "com.memexlab.memex.ble.STOP"
        const val ACTION_FORGET = "com.memexlab.memex.ble.FORGET"
        const val EXTRA_USER_KEY = "user_key"
        internal const val ACTION_CONNECT_WATCHDOG =
            "com.memexlab.memex.ble.CONNECT_WATCHDOG"
        private const val EXTRA_WATCHDOG_TOKEN = "watchdog_token"
        private const val EXTRA_WATCHDOG_GENERATION = "watchdog_generation"

        private const val NOTIFICATION_CHANNEL = "ble_heart_rate_connection"
        private const val NOTIFICATION_ID = 0x180d
        private const val STALE_AFTER_MS = 15_000L
        private const val RECONNECT_AFTER_STALE_MS = 60_000L
        private const val CONNECT_WATCHDOG_MS = 25_000L
        private val HEART_RATE_SERVICE = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
        private val HEART_RATE_MEASUREMENT = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
        private val CLIENT_CHARACTERISTIC_CONFIG = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private val RETRY_DELAYS_MS = longArrayOf(2_000, 5_000, 15_000, 30_000, 60_000, 300_000)

        fun start(context: Context): Boolean {
            return try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, BleHeartRateService::class.java).setAction(ACTION_START),
                )
                true
            } catch (_: RuntimeException) {
                false
            }
        }

        fun stop(context: Context) {
            runCatching {
                context.startService(
                    Intent(context, BleHeartRateService::class.java).setAction(ACTION_STOP),
                )
            }
        }

        fun forget(context: Context, userKey: String) {
            runCatching {
                context.startService(
                    Intent(context, BleHeartRateService::class.java)
                        .setAction(ACTION_FORGET)
                        .putExtra(EXTRA_USER_KEY, userKey),
                )
            }
        }

        internal fun startWatchdogReconcile(
            context: Context,
            token: Long,
            generation: Long,
        ): Boolean = try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BleHeartRateService::class.java)
                    .setAction(ACTION_CONNECT_WATCHDOG)
                    .putExtra(EXTRA_WATCHDOG_TOKEN, token)
                    .putExtra(EXTRA_WATCHDOG_GENERATION, generation),
            )
            true
        } catch (_: RuntimeException) {
            // The persisted plan remains available to the next service start.
            false
        }
    }

    private lateinit var store: BleHeartRateStore
    private lateinit var bluetoothManager: BluetoothManager
    private val handler = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var activeAddress: String? = null
    private var activeGeneration = 0L
    private var activeUserKey: String? = null
    private var reconnectAttempt = 0
    private var lastSampleAtMs = 0L
    private var currentStatus = "starting"
    private var stoppedExplicitly = false
    private var lastNotificationAtMs = 0L
    private var lastNotificationStatus: String? = null
    private var adapterOnReconnect: Runnable? = null
    private lateinit var reconnectCoordinator: BleReconnectCoordinator
    private lateinit var connectWatchdogAlarmScheduler: BleConnectWatchdogAlarmScheduler
    private lateinit var connectWatchdogController: BleConnectWatchdogServiceController

    private val staleTick = object : Runnable {
        override fun run() {
            recoverConnectWatchdog()
            recoverOverdueReconnect()
            val key = activeUserKey
            if (key != null && currentStatus == "live" && lastSampleAtMs > 0L &&
                System.currentTimeMillis() - lastSampleAtMs > STALE_AFTER_MS
            ) {
                publishStatus(key, "stale", "sample_timeout")
            } else if (key != null && currentStatus == "stale" && lastSampleAtMs > 0L &&
                System.currentTimeMillis() - lastSampleAtMs > RECONNECT_AFTER_STALE_MS
            ) {
                publishStatus(key, "disconnected", "sample_timeout_reconnect", recordGap = true)
                closeGatt()
                scheduleReconnect("sample_timeout_reconnect")
            }
            handler.postDelayed(this, 5_000L)
        }
    }

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_OFF, BluetoothAdapter.STATE_TURNING_OFF -> {
                    cancelAdapterOnReconnect()
                    cancelPendingReconnect()
                    closeGatt()
                    activeUserKey?.let {
                        publishStatus(it, "bluetoothOff", "adapter_off", recordGap = true)
                    }
                }
                BluetoothAdapter.STATE_ON -> {
                    reconnectAttempt = 0
                    scheduleAdapterOnReconnect()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        store = BleHeartRateStore(applicationContext)
        bluetoothManager = getSystemService(BluetoothManager::class.java)
        reconnectCoordinator = BleReconnectCoordinator(
            nowMs = System::currentTimeMillis,
            postDelayed = { runnable, delayMs -> handler.postDelayed(runnable, delayMs) },
            removeCallbacks = handler::removeCallbacks,
            onRetryDue = { performReconnect("bounded_retry") },
        )
        connectWatchdogAlarmScheduler = BleConnectWatchdogAlarmScheduler(applicationContext)
        connectWatchdogController = BleConnectWatchdogServiceController(
            nowMs = System::currentTimeMillis,
            nextToken = store::nextConnectWatchdogToken,
            postDelayed = { runnable, delayMs -> handler.postDelayed(runnable, delayMs) },
            removeCallbacks = handler::removeCallbacks,
            loadPersisted = store::activeConnectWatchdog,
            savePersisted = { plan ->
                val key = activeUserKey ?: store.activeConfig()?.userKey
                key != null && store.saveConnectWatchdog(key, plan)
            },
            clearPersisted = store::clearActiveConnectWatchdog,
            scheduleAlarm = { plan ->
                when (connectWatchdogAlarmScheduler.schedule(plan)) {
                    BleWatchdogAlarmMode.EXACT_ALLOW_IDLE -> {
                        recordConnectWatchdogDiagnostic("connect_watchdog_alarm_exact_allow_idle")
                        true
                    }
                    BleWatchdogAlarmMode.INEXACT_ALLOW_IDLE -> {
                        recordConnectWatchdogDiagnostic("connect_watchdog_alarm_inexact_allow_idle")
                        true
                    }
                    BleWatchdogAlarmMode.FAILED -> false
                }
            },
            cancelAlarm = connectWatchdogAlarmScheduler::cancel,
            stateProvider = ::connectWatchdogState,
            onTimeoutAction = ::handleConnectWatchdogAction,
            onDiagnostic = ::recordConnectWatchdogDiagnostic,
        )
        createNotificationChannel()
        ContextCompat.registerReceiver(
            this,
            bluetoothStateReceiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            // Bluetooth state is emitted by a highly privileged system component.
            // AndroidX documents RECEIVER_EXPORTED for that class of sender.
            ContextCompat.RECEIVER_EXPORTED,
        )
        handler.post(staleTick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_FORGET) {
            stoppedExplicitly = true
            cancelAdapterOnReconnect()
            cancelPendingReconnect()
            cancelConnectWatchdog()
            closeGatt()
            intent.getStringExtra(EXTRA_USER_KEY)?.let(store::forget)
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            stoppedExplicitly = true
            cancelAdapterOnReconnect()
            cancelPendingReconnect()
            cancelConnectWatchdog()
            store.activeConfig()?.let { config ->
                store.setEnabled(config.userKey, false)
                publishStatus(config.userKey, "stopped", "user_stopped", recordGap = true)
            }
            closeGatt()
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        stoppedExplicitly = false
        val config = store.activeConfig()
        if (config == null || !config.enabled) {
            cancelAdapterOnReconnect()
            cancelPendingReconnect()
            cancelConnectWatchdog()
            closeGatt()
            stopSelf()
            return START_NOT_STICKY
        }
        activeUserKey = config.userKey
        if (!hasConnectPermission()) {
            cancelPendingReconnect()
            cancelConnectWatchdog()
            store.updateStatus(config.userKey, "permissionDenied", "bluetooth_connect_denied", recordGap = true)
            stopSelf()
            return START_NOT_STICKY
        }
        if (!startAsConnectedDeviceForeground(buildNotification("正在准备心率连接"))) {
            cancelPendingReconnect()
            cancelConnectWatchdog()
            store.updateStatus(config.userKey, "permissionDenied", "foreground_connected_device_denied", recordGap = true)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_CONNECT_WATCHDOG) {
            val token = intent.getLongExtra(EXTRA_WATCHDOG_TOKEN, -1L)
            val generation = intent.getLongExtra(EXTRA_WATCHDOG_GENERATION, -1L)
            val reconciled = token > 0L && generation > 0L &&
                reconcileConnectWatchdog(token, generation)
            if (!reconciled && currentStatus == "starting" && gatt == null) {
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelfResult(startId)
                return START_NOT_STICKY
            }
            return START_STICKY
        }
        if (recoverConnectWatchdog()) return START_STICKY
        connectKnownDevice(if (intent == null) "process_recreated" else "user_enabled")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stoppedExplicitly = true
        cancelAdapterOnReconnect()
        cancelPendingReconnect()
        cancelConnectWatchdog()
        handler.removeCallbacksAndMessages(null)
        closeGatt()
        runCatching { unregisterReceiver(bluetoothStateReceiver) }
        store.close()
        super.onDestroy()
    }

    private fun connectKnownDevice(reason: String) {
        val config = store.activeConfig()
        if (stoppedExplicitly || config == null || !config.enabled) {
            cancelPendingReconnect()
            cancelConnectWatchdog()
            return
        }
        activeUserKey = config.userKey

        if (!hasConnectPermission()) {
            cancelPendingReconnect()
            cancelConnectWatchdog()
            publishStatus(config.userKey, "permissionDenied", "bluetooth_connect_denied", recordGap = true)
            return
        }
        val adapter = bluetoothManager.adapter
        if (adapter == null) {
            cancelPendingReconnect()
            cancelConnectWatchdog()
            publishStatus(config.userKey, "unsupported", "ble_unavailable", recordGap = true)
            return
        }
        if (!adapter.isEnabled) {
            cancelPendingReconnect()
            cancelConnectWatchdog()
            publishStatus(config.userKey, "bluetoothOff", "adapter_off", recordGap = true)
            return
        }
        if (gatt != null && activeAddress == config.address) {
            cancelPendingReconnect()
            return
        }
        cancelPendingReconnect()
        cancelConnectWatchdog()
        if (gatt != null && activeAddress != config.address) closeGatt()

        val device = runCatching { adapter.getRemoteDevice(config.address) }.getOrNull()
        if (device == null) {
            cancelPendingReconnect()
            publishStatus(config.userKey, "unsupported", "invalid_device_identifier", recordGap = true)
            return
        }
        publishStatus(
            config.userKey,
            if (reconnectAttempt == 0) "connecting" else "reconnecting",
            reason,
        )
        val generation = ++activeGeneration
        activeAddress = config.address
        val newGatt = try {
            device.connectGatt(
                this,
                false,
                createGattCallback(generation),
                android.bluetooth.BluetoothDevice.TRANSPORT_LE,
            )
        } catch (_: SecurityException) {
            publishStatus(config.userKey, "permissionDenied", "bluetooth_connect_denied", recordGap = true)
            null
        } catch (_: Throwable) {
            null
        }
        if (activeGeneration == generation) gatt = newGatt else runCatching { newGatt?.close() }
        if (newGatt == null && currentStatus != "permissionDenied") {
            scheduleReconnect("connect_start_failed")
        } else if (newGatt != null) {
            armConnectWatchdog(generation, config.address)
        }
    }

    private fun createGattCallback(generation: Long) = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            onServiceThread {
                if (!isCurrent(gatt, generation)) {
                    runCatching { gatt.close() }
                    return@onServiceThread
                }
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        if (status != BluetoothGatt.GATT_SUCCESS) {
                            failGatt(gatt, "connect_status_$status")
                            return@onServiceThread
                        }
                        cancelPendingReconnect()
                        reconnectAttempt = 0
                        activeUserKey?.let { publishStatus(it, "connecting", "discovering_services") }
                        val started = try {
                            gatt.discoverServices()
                        } catch (_: SecurityException) {
                            false
                        }
                        if (!started) failGatt(gatt, "service_discovery_not_started")
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        cancelConnectWatchdog()
                        this@BleHeartRateService.gatt = null
                        activeGeneration += 1
                        activeAddress = null
                        runCatching { gatt.close() }
                        activeUserKey?.let {
                            publishStatus(it, "disconnected", "gatt_status_$status", recordGap = true)
                        }
                        scheduleReconnect("disconnected")
                    }
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            onServiceThread {
                if (!isCurrent(gatt, generation)) return@onServiceThread
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failGatt(gatt, "service_discovery_$status")
                    return@onServiceThread
                }
                val characteristic = gatt.getService(HEART_RATE_SERVICE)
                    ?.getCharacteristic(HEART_RATE_MEASUREMENT)
                val cccd = characteristic?.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG)
                if (characteristic == null || cccd == null || !supportsUpdates(characteristic)) {
                    cancelPendingReconnect()
                    activeUserKey?.let {
                        publishStatus(it, "unsupported", "heart_rate_measurement_missing", recordGap = true)
                    }
                    closeGatt()
                    return@onServiceThread
                }
                val notificationEnabled = try {
                    gatt.setCharacteristicNotification(characteristic, true)
                } catch (_: SecurityException) {
                    false
                }
                if (!notificationEnabled) {
                    failGatt(gatt, "notification_enable_failed")
                    return@onServiceThread
                }
                val descriptorValue = if ((characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0 &&
                    (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) == 0
                ) BluetoothGattDescriptor.ENABLE_INDICATION_VALUE else BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                val writeStarted = try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        gatt.writeDescriptor(cccd, descriptorValue) == BluetoothGatt.GATT_SUCCESS
                    } else {
                        @Suppress("DEPRECATION")
                        cccd.value = descriptorValue
                        @Suppress("DEPRECATION")
                        gatt.writeDescriptor(cccd)
                    }
                } catch (_: SecurityException) {
                    false
                }
                if (!writeStarted) failGatt(gatt, "cccd_write_not_started")
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            onServiceThread {
                if (!isCurrent(gatt, generation)) return@onServiceThread
                if (descriptor.uuid != CLIENT_CHARACTERISTIC_CONFIG) return@onServiceThread
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    activeUserKey?.let { publishStatus(it, "connecting", "awaiting_first_sample") }
                } else {
                    failGatt(gatt, "cccd_write_$status")
                }
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val uuid = characteristic.uuid
            val value = (characteristic.value ?: byteArrayOf()).copyOf()
            onServiceThread {
                if (!isCurrent(gatt, generation)) return@onServiceThread
                handleMeasurement(uuid, value)
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            val uuid = characteristic.uuid
            val safeValue = value.copyOf()
            onServiceThread {
                if (!isCurrent(gatt, generation)) return@onServiceThread
                handleMeasurement(uuid, safeValue)
            }
        }
    }

    private fun onServiceThread(action: () -> Unit) {
        // Always enqueue, even if a vendor invokes a GATT callback on main,
        // so connectGatt() can return and publish the authoritative GATT first.
        handler.post(action)
    }

    private fun isCurrent(callbackGatt: BluetoothGatt, generation: Long): Boolean =
        generation == activeGeneration && gatt === callbackGatt

    private fun handleMeasurement(uuid: UUID, value: ByteArray) {
        if (uuid != HEART_RATE_MEASUREMENT) return
        val key = activeUserKey ?: return
        when (val parsed = HeartRateMeasurementParser.parse(value)) {
            is HeartRateParseResult.Valid -> {
                cancelPendingReconnect()
                cancelConnectWatchdog()
                lastSampleAtMs = System.currentTimeMillis()
                reconnectAttempt = 0
                currentStatus = "live"
                store.recordSample(key, parsed.measurement, lastSampleAtMs)
                updateNotification("${parsed.measurement.bpm} BPM · 正在接收", force = false)
            }
            is HeartRateParseResult.Malformed -> {
                if (lastSampleAtMs == 0L) {
                    publishStatus(key, "malformedData", parsed.reason)
                } else {
                    store.updateStatus(key, currentStatus, "malformed_${parsed.reason}")
                }
            }
        }
    }

    private fun failGatt(gatt: BluetoothGatt, reason: String) {
        cancelConnectWatchdog()
        if (this.gatt === gatt) {
            this.gatt = null
            activeGeneration += 1
            activeAddress = null
        }
        runCatching { gatt.disconnect() }
        runCatching { gatt.close() }
        activeUserKey?.let { publishStatus(it, "disconnected", reason, recordGap = true) }
        scheduleReconnect(reason)
    }

    private fun scheduleReconnect(reason: String) {
        val config = store.activeConfig()
        if (config == null) {
            cancelPendingReconnect()
            return
        }
        if (stoppedExplicitly || !config.enabled || currentStatus == "unsupported" ||
            currentStatus == "permissionDenied" || currentStatus == "bluetoothOff"
        ) {
            cancelPendingReconnect()
            return
        }
        val delay = RETRY_DELAYS_MS[reconnectAttempt.coerceAtMost(RETRY_DELAYS_MS.lastIndex)]
        reconnectAttempt = (reconnectAttempt + 1).coerceAtMost(RETRY_DELAYS_MS.lastIndex)
        val plan = reconnectCoordinator.schedule(delay)
        publishStatus(config.userKey, "reconnecting", reason, retryAtMs = plan.dueAtMs)
    }

    private fun performReconnect(reason: String) {
        closeGatt()
        connectKnownDevice(reason)
    }

    private fun recoverOverdueReconnect() {
        if (stoppedExplicitly || currentStatus != "reconnecting" || gatt != null) return
        if (reconnectCoordinator.recoverOverdue()) return
        if (reconnectCoordinator.pendingDueAtMs != null) return

        val persistedRetryAtMs = store.activeRetryAtMs() ?: return
        reconnectCoordinator.reconcilePersistedDeadline(persistedRetryAtMs)
    }

    private fun cancelPendingReconnect() {
        reconnectCoordinator.cancel()
    }

    private fun scheduleAdapterOnReconnect() {
        cancelAdapterOnReconnect()
        val reconnect = Runnable {
            adapterOnReconnect = null
            connectKnownDevice("adapter_on")
        }
        adapterOnReconnect = reconnect
        handler.postDelayed(reconnect, 1_000L)
    }

    private fun cancelAdapterOnReconnect() {
        adapterOnReconnect?.let(handler::removeCallbacks)
        adapterOnReconnect = null
    }

    private fun armConnectWatchdog(generation: Long, deviceAddress: String) {
        val result = connectWatchdogController.arm(
            generation = generation,
            deviceAddress = deviceAddress,
            delayMs = CONNECT_WATCHDOG_MS,
        )
        if (result != BleWatchdogArmResult.PERSIST_FAILED) return
        val key = activeUserKey ?: return
        publishStatus(key, "disconnected", "connect_watchdog_persist_failed", recordGap = true)
        closeGatt()
        scheduleReconnect("connect_watchdog_persist_failed")
    }

    /**
     * Rebuilds a lost Handler from durable state, or consumes an overdue plan.
     * Returns true whenever a persisted attempt owns the current start command.
     */
    private fun recoverConnectWatchdog(): Boolean =
        connectWatchdogController.reconcilePersisted()

    private fun reconcileConnectWatchdog(token: Long, generation: Long): Boolean =
        connectWatchdogController.reconcileSignal(token, generation)

    private fun connectWatchdogState(): BleConnectAttemptState? {
        val config = store.activeConfig() ?: return null
        val adapterEnabled = runCatching {
            bluetoothManager.adapter?.isEnabled == true
        }.getOrDefault(false)
        return BleConnectAttemptState(
            stoppedExplicitly = stoppedExplicitly,
            enabled = config.enabled,
            adapterEnabled = adapterEnabled,
            status = currentStatus,
            activeGeneration = activeGeneration,
            activeAddress = activeAddress,
            hasGatt = gatt != null,
        )
    }

    @Suppress("UNUSED_PARAMETER")
    private fun handleConnectWatchdogAction(
        plan: BleConnectWatchdogPlan,
        action: BleConnectWatchdogAction,
    ) {
        if (action == BleConnectWatchdogAction.IGNORE) return
        val config = store.activeConfig() ?: return
        activeUserKey = config.userKey
        publishStatus(
            config.userKey,
            "disconnected",
            "connect_watchdog_timeout",
            recordGap = true,
        )
        closeGatt()
        scheduleReconnect("connect_watchdog_timeout")
    }

    private fun recordConnectWatchdogDiagnostic(reason: String) {
        val key = activeUserKey ?: store.activeConfig()?.userKey ?: return
        store.updateStatus(key, currentStatus, reason)
    }

    private fun cancelConnectWatchdog() {
        connectWatchdogController.cancel()
    }

    private fun publishStatus(
        userKey: String,
        status: String,
        reason: String? = null,
        retryAtMs: Long? = null,
        recordGap: Boolean = false,
    ) {
        val changed = currentStatus != status
        currentStatus = status
        store.updateStatus(userKey, status, reason, retryAtMs, recordGap = recordGap)
        updateNotification(notificationText(status), force = changed)
    }

    private fun supportsUpdates(characteristic: BluetoothGattCharacteristic): Boolean =
        (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0 ||
            (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0

    private fun hasConnectPermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
        PackageManager.PERMISSION_GRANTED

    private fun closeGatt() {
        cancelConnectWatchdog()
        activeGeneration += 1
        val closing = gatt
        gatt = null
        activeAddress = null
        if (closing != null && hasConnectPermission()) runCatching { closing.disconnect() }
        runCatching { closing?.close() }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "实时心率连接",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持已启用的蓝牙心率设备连接"
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            android.app.PendingIntent.getActivity(
                this,
                0,
                it,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
            .setSmallIcon(com.memexlab.memex.R.drawable.ic_stat_here_i_am)
            .setContentTitle("故我在 · 实时心率")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun startAsConnectedDeviceForeground(notification: Notification): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun updateNotification(text: String, force: Boolean = true) {
        val now = System.currentTimeMillis()
        val statusChanged = lastNotificationStatus != currentStatus
        if (!BleNotificationRefreshPolicy.shouldNotify(
                force = force,
                statusChanged = statusChanged,
                elapsedSinceLastMs = now - lastNotificationAtMs,
            )
        ) return
        lastNotificationAtMs = now
        lastNotificationStatus = currentStatus
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun notificationText(status: String): String = when (status) {
        "live" -> "正在接收心率"
        "stale" -> "样本已陈旧，等待恢复"
        "reconnecting" -> "连接中断，正在重连"
        "bluetoothOff" -> "蓝牙已关闭"
        "permissionDenied" -> "需要蓝牙权限"
        "unsupported" -> "设备不支持标准心率服务"
        "stopped" -> "实时心率已停止"
        else -> "正在连接心率设备"
    }
}
