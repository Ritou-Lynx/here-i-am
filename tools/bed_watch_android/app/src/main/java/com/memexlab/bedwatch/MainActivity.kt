package com.memexlab.bedwatch

import android.Manifest
import android.app.Activity
import android.app.ForegroundServiceStartNotAllowedException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.time.LocalTime
import java.time.ZonedDateTime
import java.util.concurrent.Executors

class MainActivity : Activity() {
    private lateinit var store: Settings
    private lateinit var enabled: CheckBox
    private lateinit var front: CheckBox
    private lateinit var release: CheckBox
    private lateinit var lookEnabled: CheckBox
    private lateinit var invertPan: CheckBox
    private lateinit var invertTilt: CheckBox
    private lateinit var rows: TextView
    private lateinit var status: TextView
    private val fields = linkedMapOf<String, EditText>()
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var visible = false
    private var pendingEnable = false
    private val refresh = object : Runnable {
        override fun run() {
            worker.execute {
                frameLog().cleanup(java.time.LocalDate.now())
                val recent = frameLog().recent().joinToString("\n")
                runOnUiThread { if (visible) rows.text = recent.ifEmpty { "暂无采样" } }
            }
            handler.postDelayed(this, 5000)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = Settings(this)
        val config = store.read()
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 32, 24, 32) }
        setContentView(ScrollView(this).apply { addView(layout) })
        fun label(text: String) = TextView(this).apply { this.text = text; textSize = 18f; layout.addView(this) }
        fun field(key: String, title: String, value: String, numeric: Boolean = false) {
            label(title)
            fields[key] = EditText(this).apply {
                setText(value); isSingleLine = true
                inputType = if (numeric) InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
                    else InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                layout.addView(this)
            }
        }
        fun button(title: String, action: () -> Unit) { layout.addView(Button(this).apply { text = title; setOnClickListener { action() } }) }
        label("床头哨兵 · 图像仅在内存处理").textSize = 24f
        enabled = CheckBox(this).apply { text = "启用监测（保存后生效）"; isChecked = config.enabled; layout.addView(this) }
        field("start", "监测开始 HH:mm", config.start.toString())
        field("end", "监测结束 HH:mm（与开始相同表示全天）", config.end.toString())
        field("interval", "间隔秒数（30–300）", config.intervalSeconds.toString(), true)
        field("cooldown", "推送冷却分钟（1–1440）", config.cooldownMinutes.toString(), true)
        front = CheckBox(this).apply { text = "使用前摄（默认后摄）"; isChecked = config.front; layout.addView(this) }
        field("open", "睁眼阈值（默认 0.6）", config.thresholds.open.toString(), true)
        field("glow", "屏幕亮光阈值（默认 1.6）", config.thresholds.glow.toString(), true)
        field("closed", "闭眼阈值（默认 0.3）", config.thresholds.closed.toString(), true)
        field("dimGlow", "暗光阈值（默认 1.3）", config.thresholds.dimGlow.toString(), true)
        field("dark", "无人暗帧亮度阈值（默认 40）", config.thresholds.dark.toString(), true)
        field("server", "ntfy 服务器（https）", config.server)
        field("topic", "ntfy topic（只保存在本机）", config.topic)
        release = CheckBox(this).apply {
            text = "今晚放行（首次开启到次日 12:00，保存生效）"
            isChecked = config.releaseUntil > System.currentTimeMillis(); layout.addView(this)
        }
        val lookConfig = store.readLook()
        label("林埃按需看一眼（只在家里局域网）").textSize = 20f
        lookEnabled = CheckBox(this).apply { text = "允许林埃按需看一眼（保存后生效）"; isChecked = lookConfig.enabled; layout.addView(this) }
        field("look_server", "家里电脑地址（如 http://192.168.x.x:47867）", lookConfig.server)
        field("look_token", "相机口令（与电脑上的 camera.json 对应，只保存在本机）", lookConfig.token)
        field("look_gimbal", "云台地址（如 http://192.168.x.y，没有云台就留空）", lookConfig.gimbal)
        field("look_gimbal_token", "云台口令（与 ESP32 的 secrets.h 一致）", lookConfig.gimbalToken)
        field("look_positions", "预置位：名字=左右角,上下角;…（如 床=90,70;书桌=150,85;门口=30,90）",
            LookProtocol.formatPositions(lookConfig.positions))
        field("look_fov", "镜头水平视角（找人时用，默认 70）", lookConfig.fovDegrees.toString(), true)
        invertPan = CheckBox(this).apply { text = "找人时左右方向反了就勾上"; isChecked = lookConfig.invertPan; layout.addView(this) }
        invertTilt = CheckBox(this).apply { text = "找人时上下方向反了就勾上"; isChecked = lookConfig.invertTilt; layout.addView(this) }
        button("现在别看（1 小时）/ 恢复") {
            val paused = store.lookPausedUntil > System.currentTimeMillis()
            store.lookPausedUntil = if (paused) 0 else System.currentTimeMillis() + 3_600_000L
            status.text = if (paused) "已恢复：林埃可以按需看一眼" else "1 小时内林埃看不了"
        }
        button("测试云台（转到第一个预置位）") {
            try {
                val l = readLookForm()
                val first = l.positions.entries.firstOrNull() ?: throw IllegalArgumentException()
                status.text = "正在转到 ${first.key}…"
                worker.execute {
                    val ok = Gimbal(l.gimbal, l.gimbalToken).move(first.value)
                    runOnUiThread { if (visible) status.text = if (ok) "已转到 ${first.key}" else "云台没有响应：检查地址、口令和电源" }
                }
            } catch (_: Exception) { status.text = "请先填写云台地址、口令和至少一个预置位。" }
        }
        status = label("")
        button("保存设置") {
            try {
                val next = readForm(requireEndpoint = enabled.isChecked)
                val nextLook = readLookForm()
                if ((next.enabled || nextLook.enabled) && !permissionsReady()) {
                    pendingEnable = true
                    requestPermissions(requiredPermissions(), 10)
                } else { saveAndApply(next, nextLook) }
            } catch (_: Exception) { status.text = "设置无效：请核对时间、数值范围、HTTPS 地址和局域网地址。" }
        }
        button("调角度 · 实时预览") {
            if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.CAMERA), 11)
            } else {
                try {
                    // Persist selected camera/thresholds, but do not enable monitoring from preview.
                    val next = readForm(requireEndpoint = false).copy(enabled = store.read().enabled)
                    store.write(next)
                    stopService(Intent(this, BedWatchService::class.java))
                    startActivity(Intent(this, PreviewActivity::class.java))
                } catch (_: Exception) { status.text = "请先核对设置。" }
            }
        }
        button("测试推送") {
            try {
                val next = readForm()
                status.text = "正在发送测试推送…"
                worker.execute {
                    val ok = runCatching { NtfyNotifier().send(next.server, next.topic, "床头哨兵测试推送。") }.getOrDefault(false)
                    runOnUiThread { if (visible) status.text = if (ok) "测试推送成功" else "测试推送失败（已按 5 秒、30 秒重试）" }
                }
            } catch (_: Exception) { status.text = "请填写有效的 HTTPS 服务器和 topic。" }
        }
        label("最近 20 帧：verdict 0=清醒 / 1=似睡 / 2=未知；pushed -1=推送失败")
        rows = label("暂无采样").apply { textSize = 14f }
    }
    private fun readForm(requireEndpoint: Boolean = true): WatchSettings {
        fun text(key: String) = fields.getValue(key).text.toString().trim()
        if (requireEndpoint || text("server").isNotEmpty() || text("topic").isNotEmpty()) {
            NtfyNotifier.endpoint(text("server"), text("topic"))
        }
        val previous = store.read()
        val until = if (!release.isChecked) 0 else previous.releaseUntil.takeIf { it > System.currentTimeMillis() }
            ?: NightWindow.releaseUntil(ZonedDateTime.now())
        return WatchSettings(enabled.isChecked, LocalTime.parse(text("start")), LocalTime.parse(text("end")),
            text("interval").toInt(), front.isChecked,
            Thresholds(text("open").toFloat(), text("glow").toFloat(), text("closed").toFloat(),
                text("dimGlow").toFloat(), text("dark").toFloat()), text("cooldown").toInt(),
            text("server"), text("topic"), until)
    }
    private fun readLookForm(): LookConfig {
        fun text(key: String) = fields.getValue(key).text.toString().trim()
        val on = lookEnabled.isChecked
        val server = text("look_server")
        val gimbal = text("look_gimbal")
        if (on || server.isNotEmpty()) LookProtocol.lanBase(server)
        if (on) require(text("look_token").length >= 32) { "相机口令至少 32 个字符" }
        if (gimbal.isNotEmpty()) { LookProtocol.lanBase(gimbal); require(text("look_gimbal_token").length >= 16) }
        return LookConfig(on, server, text("look_token"), gimbal, text("look_gimbal_token"),
            LookProtocol.parsePositions(text("look_positions")), store.lookPausedUntil,
            invertPan.isChecked, invertTilt.isChecked, text("look_fov").toFloat())
    }
    private fun requiredPermissions() = mutableListOf(Manifest.permission.CAMERA).apply {
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }.toTypedArray()
    private fun permissionsReady() = requiredPermissions().all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED } &&
        WatchNotifications.allowed(this)
    private fun saveAndApply(config: WatchSettings, look: LookConfig = store.readLook()) {
        store.write(config)
        store.writeLook(look)
        stopService(Intent(this, BedWatchService::class.java))
        if (config.enabled || look.enabled) handler.postDelayed({ if (visible && store.serviceWanted()) startMonitoring() }, 300)
        else WatchNotifications.clearRecovery(this)
        status.text = when {
            config.enabled && look.enabled -> "已保存：夜间监测 + 按需看一眼"
            config.enabled -> "已保存，监测仅在窗口内采样"
            look.enabled -> "已保存：只开按需看一眼"
            else -> "已停止监测"
        }
    }
    private fun startMonitoring() {
        if (!permissionsReady()) { status.text = "请允许相机与通知，再保存设置以恢复监测。"; return }
        try { startForegroundService(Intent(this, BedWatchService::class.java)) }
        catch (_: ForegroundServiceStartNotAllowedException) {
            WatchNotifications.recover(this, RecoveryCause.FOREGROUND_REJECTED)
            status.text = "系统暂不允许启动，请保持此页在前台后重试保存。"
        } catch (_: SecurityException) {
            WatchNotifications.recover(this, RecoveryCause.FOREGROUND_REJECTED)
            status.text = "相机或前台服务权限不可用。"
        }
    }
    override fun onResume() {
        super.onResume(); visible = true
        release.isChecked = store.read().releaseUntil > System.currentTimeMillis()
        if (store.serviceWanted()) startMonitoring()
        handler.post(refresh)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (visible && store.serviceWanted()) startMonitoring()
    }
    override fun onPause() {
        visible = false; handler.removeCallbacksAndMessages(null); super.onPause()
    }
    override fun onDestroy() { worker.shutdownNow(); super.onDestroy() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 10 && pendingEnable) {
            pendingEnable = false
            if (permissionsReady()) runCatching { saveAndApply(readForm(requireEndpoint = enabled.isChecked), readLookForm()) }
            else { enabled.isChecked = false; lookEnabled.isChecked = false; status.text = "监测需要相机和通知权限。" }
        } else if (requestCode == 11) { status.text = "相机权限处理完成，请再点一次调角度。" }
    }
}
