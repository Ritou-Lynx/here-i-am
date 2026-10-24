package com.memexlab.bedwatch

import android.app.ForegroundServiceStartNotAllowedException
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.lifecycle.LifecycleService
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors

class BedWatchService : LifecycleService() {
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var settings: Settings
    private lateinit var camera: CameraSession
    private var wakeLock: PowerManager.WakeLock? = null
    private var config = WatchSettings()
    private var judge = AwakeJudge()
    @Volatile private var running = false
    private var inWindow = false
    private var lastLabel = "--:--"
    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            if (!settings.read().enabled) { stopSelf(); return }
            val inside = NightWindow.contains(LocalTime.now(), config.start, config.end)
            if (inside && !inWindow) {
                inWindow = true
                camera.start(config.front, config.intervalSeconds * 1000L,
                    onError = { failToRecovery() }, onFrame = { frame -> process(frame) })
            } else if (!inside && inWindow) {
                camera.stop()
                inWindow = false
                // Do not carry yesterday's votes into the next monitoring window.
                worker.execute { judge = newJudge() }
            }
            handler.postDelayed(this, 1000)
        }
    }
    override fun onCreate() {
        super.onCreate()
        settings = Settings(this)
        camera = CameraSession(this, this)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (!settings.read().enabled) { stopSelf(); return START_NOT_STICKY }
        try {
            startForeground(WatchNotifications.RUNNING_ID, WatchNotifications.running(this, lastLabel),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } catch (_: ForegroundServiceStartNotAllowedException) {
            failToRecovery(); return START_NOT_STICKY
        } catch (_: SecurityException) {
            failToRecovery(); return START_NOT_STICKY
        }
        WatchNotifications.clearRecovery(this)
        if (!running) {
            config = settings.read()
            judge = newJudge()
            running = true
            // The device is plugged in. A partial lock keeps window scheduling and samples timely
            // with the screen off; it does not request a battery/FGS exemption.
            wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,
                "BedWatch:monitoring").also { it.acquire() }
            worker.execute { frameLog().cleanup(java.time.LocalDate.now()) }
            handler.post(tick)
        }
        return START_STICKY
    }
    private fun newJudge() = AwakeJudge(config.thresholds, config.cooldownMinutes * 60_000L)
        .also { it.restoreLastPush(settings.lastPush) }
    private fun process(frame: FrameFeatures) {
        val now = System.currentTimeMillis()
        worker.execute {
            if (!running || !settings.read().enabled) return@execute
            val result = judge.accept(frame, now, settings.read().releaseUntil)
            var pushed = false
            var failed = false
            if (result.push) {
                settings.lastPush = now
                try {
                    pushed = NtfyNotifier(shouldContinue = {
                        val current = settings.read()
                        running && current.enabled && System.currentTimeMillis() >= current.releaseUntil &&
                            NightWindow.contains(LocalTime.now(), config.start, config.end)
                    }).send(config.server, config.topic,
                        "${LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))} 检测到睁眼或屏幕亮光，最近4帧至少3帧清醒。")
                    failed = !pushed
                } catch (_: Exception) { failed = true }
            }
            frameLog().append(FrameRecord(now, frame, result.verdict, pushed, failed))
            handler.post {
                if (running) {
                    lastLabel = java.time.Instant.ofEpochMilli(now).atZone(java.time.ZoneId.systemDefault())
                        .format(DateTimeFormatter.ofPattern("HH:mm"))
                    if (WatchNotifications.allowed(this)) {
                        try {
                            getSystemService(NotificationManager::class.java).notify(WatchNotifications.RUNNING_ID,
                                WatchNotifications.running(this, lastLabel))
                        } catch (_: SecurityException) { failToRecovery() }
                    }
                }
            }
        }
    }
    private fun failToRecovery() {
        running = false
        WatchNotifications.recover(this, RecoveryCause.FOREGROUND_REJECTED)
        stopSelf()
    }
    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        camera.close()
        worker.shutdownNow()
        wakeLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }
}
