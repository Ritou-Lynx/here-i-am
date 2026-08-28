package com.memexlab.memex.channels

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.memexlab.memex.ble.BleHeartRateEventBus
import com.memexlab.memex.ble.BleHeartRateService
import com.memexlab.memex.ble.BleHeartRateStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Narrow Flutter bridge; BLE ownership remains entirely native. */
object BleHeartRateChannelHandler {
    private const val METHOD_CHANNEL = "com.memexlab.memex/ble_heart_rate"
    private const val EVENT_CHANNEL = "com.memexlab.memex/ble_heart_rate_events"
    private const val PERMISSION_REQUEST = 0x180d
    private val HRS_UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var observedUserKey: String? = null
    private var scanCallback: ScanCallback? = null
    private var scanStopRunnable: Runnable? = null
    private var scanCount = 0
    private var processStore: BleHeartRateStore? = null

    private val busListener: (Map<String, Any?>) -> Unit = { event ->
        val eventUserKey = event["userKey"] as? String
        if (eventUserKey == null || observedUserKey == null || eventUserKey == observedUserKey) {
            mainHandler.post { eventSink?.success(event) }
        }
    }

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        val store = processStore ?: BleHeartRateStore(activity.applicationContext).also {
            processStore = it
        }
        BleHeartRateEventBus.remove(busListener)
        BleHeartRateEventBus.add(busListener)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *>
                val userId = args?.get("userId") as? String
                if (!userId.isNullOrBlank()) observedUserKey = BleHeartRateStore.userKey(userId)
                when (call.method) {
                    "getSnapshot" -> {
                        if (userId.isNullOrBlank()) result.error("USER_REQUIRED", "userId is required", null)
                        else result.success(enrichSnapshot(activity, store.snapshot(userId)))
                    }
                    "getPlatformState" -> result.success(platformState(activity))
                    "requestPermissions" -> {
                        val missing = requestablePermissions(activity).filter {
                            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
                        }
                        if (missing.isNotEmpty()) {
                            ActivityCompat.requestPermissions(activity, missing.toTypedArray(), PERMISSION_REQUEST)
                        }
                        result.success(mapOf("requested" to missing.isNotEmpty(), "permissions" to missing))
                    }
                    "openAppSettings" -> {
                        activity.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", activity.packageName, null)
                            },
                        )
                        result.success(true)
                    }
                    "openBluetoothSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    }
                    "startScan" -> {
                        if (userId.isNullOrBlank()) {
                            result.error("USER_REQUIRED", "userId is required", null)
                        } else {
                            startScan(activity, (args?.get("timeoutMs") as? Number)?.toLong() ?: 10_000L, result)
                        }
                    }
                    "stopScan" -> {
                        stopScan(activity, "stopped")
                        result.success(true)
                    }
                    "selectAndEnable" -> {
                        val address = args?.get("deviceId") as? String
                        val name = args?.get("name") as? String
                        if (userId.isNullOrBlank() || address.isNullOrBlank() ||
                            !BluetoothAdapter.checkBluetoothAddress(address)
                        ) {
                            result.error("INVALID_DEVICE", "A valid user and Bluetooth device are required", null)
                        } else if (!hasConnectPermission(activity)) {
                            result.error("PERMISSION_DENIED", "Bluetooth connect permission is required", null)
                        } else {
                            stopScan(activity, "selected")
                            val config = store.select(userId, address, name)
                            if (!BleHeartRateService.start(activity.applicationContext)) {
                                store.updateStatus(
                                    config.userKey,
                                    "disconnected",
                                    "background_start_denied",
                                    recordGap = true,
                                )
                            }
                            result.success(enrichSnapshot(activity, store.snapshot(userId)))
                        }
                    }
                    "stop" -> {
                        if (userId.isNullOrBlank()) {
                            result.error("USER_REQUIRED", "userId is required", null)
                        } else {
                            store.configForUser(userId)?.let {
                                store.setEnabled(it.userKey, false)
                                store.updateStatus(it.userKey, "stopped", "user_stopped", recordGap = true)
                            }
                            BleHeartRateService.stop(activity.applicationContext)
                            result.success(enrichSnapshot(activity, store.snapshot(userId)))
                        }
                    }
                    "forget" -> {
                        if (userId.isNullOrBlank()) {
                            result.error("USER_REQUIRED", "userId is required", null)
                        } else {
                            val config = store.configForUser(userId)
                            if (config != null && store.activeConfig()?.userKey == config.userKey) {
                                store.setEnabled(config.userKey, false)
                                BleHeartRateService.forget(activity.applicationContext, config.userKey)
                            } else {
                                store.forget(BleHeartRateStore.userKey(userId))
                            }
                            result.success(enrichSnapshot(activity, mapOf(
                                "status" to "unconfigured",
                                "reason" to "forgotten",
                                "configured" to false,
                                "enabled" to false,
                                "updatedAtMs" to System.currentTimeMillis(),
                                "rrSeen" to false,
                            )))
                        }
                    }
                    "getRecentDiagnostics" -> {
                        if (userId.isNullOrBlank()) result.error("USER_REQUIRED", "userId is required", null)
                        else result.success(store.diagnostics(userId))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startScan(activity: Activity, requestedTimeoutMs: Long, result: MethodChannel.Result) {
        val state = platformState(activity)
        if (state["supported"] != true) {
            result.error("UNSUPPORTED", "Bluetooth LE is unavailable", state)
            return
        }
        if (state["permissionState"] != "granted") {
            result.error("PERMISSION_DENIED", "Bluetooth scan permission is required", state)
            return
        }
        if (state["bluetoothState"] != "on") {
            result.error("BLUETOOTH_OFF", "Bluetooth is turned off", state)
            return
        }
        stopScan(activity, "restarted")
        val scanner = activity.getSystemService(BluetoothManager::class.java).adapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("SCAN_UNAVAILABLE", "BLE scanner is unavailable", null)
            return
        }
        scanCount = 0
        val seen = mutableSetOf<String>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                val address = scanResult.device.address ?: return
                if (!seen.add(address)) return
                scanCount += 1
                val name = if (hasConnectPermission(activity)) {
                    runCatching { scanResult.device.name }.getOrNull()
                } else null
                emit(mapOf(
                    "type" to "scanResult",
                    "device" to mapOf(
                        "deviceId" to address,
                        "name" to (name ?: scanResult.scanRecord?.deviceName),
                        "rssi" to scanResult.rssi,
                    ),
                ))
            }

            override fun onScanFailed(errorCode: Int) {
                emit(mapOf("type" to "scanState", "state" to "failed", "errorCode" to errorCode))
                stopScan(activity, "failed")
            }
        }
        scanCallback = callback
        val timeout = requestedTimeoutMs.coerceIn(3_000L, 20_000L)
        emit(mapOf("type" to "scanState", "state" to "scanning"))
        try {
            scanner.startScan(
                listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(HRS_UUID)).build()),
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
                callback,
            )
        } catch (_: SecurityException) {
            scanCallback = null
            result.error("PERMISSION_DENIED", "Bluetooth scan permission is required", null)
            return
        }
        val stop = Runnable { stopScan(activity, if (scanCount == 0) "notFound" else "complete") }
        scanStopRunnable = stop
        mainHandler.postDelayed(stop, timeout)
        result.success(true)
    }

    private fun stopScan(activity: Activity, state: String) {
        scanStopRunnable?.let(mainHandler::removeCallbacks)
        scanStopRunnable = null
        val callback = scanCallback ?: return
        scanCallback = null
        runCatching {
            activity.getSystemService(BluetoothManager::class.java)
                .adapter?.bluetoothLeScanner?.stopScan(callback)
        }
        emit(mapOf("type" to "scanState", "state" to state, "count" to scanCount))
    }

    private fun platformState(activity: Activity): Map<String, Any?> {
        val manager = activity.getSystemService(BluetoothManager::class.java)
        val adapter = manager.adapter
        return mapOf(
            "supported" to (adapter != null && activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)),
            "permissionState" to if (blePermissions().all {
                ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
            }) "granted" else "denied",
            "notificationPermission" to if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            ) "granted" else "denied",
            "bluetoothState" to when {
                adapter == null -> "unsupported"
                adapter.isEnabled -> "on"
                else -> "off"
            },
        )
    }

    private fun enrichSnapshot(activity: Activity, snapshot: Map<String, Any?>): Map<String, Any?> =
        snapshot + platformState(activity)

    private fun requestablePermissions(activity: Activity): List<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> blePermissions() +
            Manifest.permission.POST_NOTIFICATIONS
        else -> blePermissions()
    }

    private fun blePermissions(): List<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> listOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
        else -> listOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun hasConnectPermission(activity: Activity): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun emit(event: Map<String, Any?>) = mainHandler.post { eventSink?.success(event) }
}
