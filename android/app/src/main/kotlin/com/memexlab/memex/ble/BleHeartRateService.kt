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
    private var connectWatchdog: Runnable? = null

    private val staleTick = object : Runnable {
        override fun run() {
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
                    handler.removeCallbacksAndMessages(null)
                    handler.post(staleTick)
                    closeGatt()
                    activeUserKey?.let {
                        publishStatus(it, "bluetoothOff", "adapter_off", recordGap = true)
                    }
                }
                BluetoothAdapter.STATE_ON -> {
                    reconnectAttempt = 0
                    handler.postDelayed({ connectKnownDevice("adapter_on") }, 1_000L)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        store = BleHeartRateStore(applicationContext)
        bluetoothManager = getSystemService(BluetoothManager::class.java)
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
            closeGatt()
            intent.getStringExtra(EXTRA_USER_KEY)?.let(store::forget)
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            stoppedExplicitly = true
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
            stopSelf()
            return START_NOT_STICKY
        }
        activeUserKey = config.userKey
        if (!hasConnectPermission()) {
            store.updateStatus(config.userKey, "permissionDenied", "bluetooth_connect_denied", recordGap = true)
            stopSelf()
            return START_NOT_STICKY
        }
        if (!startAsConnectedDeviceForeground(buildNotification("正在准备心率连接"))) {
            store.updateStatus(config.userKey, "permissionDenied", "foreground_connected_device_denied", recordGap = true)
            stopSelf()
            return START_NOT_STICKY
        }
        connectKnownDevice(if (intent == null) "process_recreated" else "user_enabled")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        closeGatt()
        runCatching { unregisterReceiver(bluetoothStateReceiver) }
        store.close()
        super.onDestroy()
    }

    private fun connectKnownDevice(reason: String) {
        val config = store.activeConfig()
        if (stoppedExplicitly || config == null || !config.enabled) return
        activeUserKey = config.userKey

        if (!hasConnectPermission()) {
            publishStatus(config.userKey, "permissionDenied", "bluetooth_connect_denied", recordGap = true)
            return
        }
        val adapter = bluetoothManager.adapter
        if (adapter == null) {
            publishStatus(config.userKey, "unsupported", "ble_unavailable", recordGap = true)
            return
        }
        if (!adapter.isEnabled) {
            publishStatus(config.userKey, "bluetoothOff", "adapter_off", recordGap = true)
            return
        }
        if (gatt != null && activeAddress == config.address) return
        if (gatt != null && activeAddress != config.address) closeGatt()

        val device = runCatching { adapter.getRemoteDevice(config.address) }.getOrNull()
        if (device == null) {
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
            armConnectWatchdog(generation)
        }
    }

    private fun createGattCallback(generation: Long) = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (!isCurrent(gatt, generation)) {
                runCatching { gatt.close() }
                return
            }
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        failGatt(gatt, "connect_status_$status")
                        return
                    }
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

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (!isCurrent(gatt, generation)) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failGatt(gatt, "service_discovery_$status")
                return
            }
            val characteristic = gatt.getService(HEART_RATE_SERVICE)
                ?.getCharacteristic(HEART_RATE_MEASUREMENT)
            val cccd = characteristic?.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG)
            if (characteristic == null || cccd == null || !supportsUpdates(characteristic)) {
                activeUserKey?.let {
                    publishStatus(it, "unsupported", "heart_rate_measurement_missing", recordGap = true)
                }
                closeGatt()
                return
            }
            val notificationEnabled = try {
                gatt.setCharacteristicNotification(characteristic, true)
            } catch (_: SecurityException) {
                false
            }
            if (!notificationEnabled) {
                failGatt(gatt, "notification_enable_failed")
                return
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

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (!isCurrent(gatt, generation)) return
            if (descriptor.uuid != CLIENT_CHARACTERISTIC_CONFIG) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                activeUserKey?.let { publishStatus(it, "connecting", "awaiting_first_sample") }
            } else {
                failGatt(gatt, "cccd_write_$status")
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (!isCurrent(gatt, generation)) return
            handleMeasurement(characteristic.uuid, characteristic.value ?: byteArrayOf())
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            if (!isCurrent(gatt, generation)) return
            handleMeasurement(characteristic.uuid, value)
        }
    }

    private fun isCurrent(callbackGatt: BluetoothGatt, generation: Long): Boolean =
        generation == activeGeneration && (gatt == null || gatt === callbackGatt)

    private fun handleMeasurement(uuid: UUID, value: ByteArray) {
        if (uuid != HEART_RATE_MEASUREMENT) return
        val key = activeUserKey ?: return
        when (val parsed = HeartRateMeasurementParser.parse(value)) {
            is HeartRateParseResult.Valid -> {
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
        val config = store.activeConfig() ?: return
        if (stoppedExplicitly || !config.enabled || currentStatus == "unsupported" ||
            currentStatus == "permissionDenied" || currentStatus == "bluetoothOff"
        ) return
        val delay = RETRY_DELAYS_MS[reconnectAttempt.coerceAtMost(RETRY_DELAYS_MS.lastIndex)]
        reconnectAttempt = (reconnectAttempt + 1).coerceAtMost(RETRY_DELAYS_MS.lastIndex)
        val retryAt = System.currentTimeMillis() + delay
        publishStatus(config.userKey, "reconnecting", reason, retryAtMs = retryAt)
        handler.removeCallbacks(reconnectRunnable)
        handler.postDelayed(reconnectRunnable, delay)
    }

    private val reconnectRunnable = Runnable {
        closeGatt(cancelReconnect = false)
        connectKnownDevice("bounded_retry")
    }

    private fun armConnectWatchdog(generation: Long) {
        cancelConnectWatchdog()
        val watchdog = Runnable {
            val key = activeUserKey ?: return@Runnable
            if (generation == activeGeneration &&
                (currentStatus == "connecting" || currentStatus == "reconnecting")
            ) {
                publishStatus(key, "disconnected", "connect_watchdog_timeout", recordGap = true)
                closeGatt()
                scheduleReconnect("connect_watchdog_timeout")
            }
        }
        connectWatchdog = watchdog
        handler.postDelayed(watchdog, CONNECT_WATCHDOG_MS)
    }

    private fun cancelConnectWatchdog() {
        connectWatchdog?.let(handler::removeCallbacks)
        connectWatchdog = null
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

    private fun closeGatt(cancelReconnect: Boolean = true) {
        if (cancelReconnect) handler.removeCallbacks(reconnectRunnable)
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
        if (!force && !statusChanged && now - lastNotificationAtMs < 12_000L) return
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
