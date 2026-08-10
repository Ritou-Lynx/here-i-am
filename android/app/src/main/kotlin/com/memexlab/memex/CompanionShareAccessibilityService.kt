package com.memexlab.memex

import android.accessibilityservice.AccessibilityService
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs

/**
 * User-invoked global shortcut for handing the current screen or a copied link
 * to the companion. The service does not inspect window content and only takes
 * a screenshot after an explicit tap on the overlay.
 */
class CompanionShareAccessibilityService : AccessibilityService() {
    companion object {
        const val CLIPBOARD_LINK_MARKER = "__here_i_am_share_copied_link__"

        private const val LONG_PRESS_MS = 650L
        private const val SCREENSHOT_DELAY_MS = 90L
        private const val DRAG_SLOP_DP = 10
        private val HTTP_URL = Regex("https?://\\S+", RegexOption.IGNORE_CASE)

        @Volatile
        private var connected = false

        fun isConnected(): Boolean = connected
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private var bubble: TextView? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var bubbleAttached = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = true
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createBubble()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val foregroundPackage = event.packageName?.toString() ?: return
        if (foregroundPackage == packageName || isKeyguardLocked()) {
            hideBubble()
        } else {
            showBubble()
        }
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        connected = false
        removeBubble()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        connected = false
        removeBubble()
        super.onDestroy()
    }

    private fun createBubble() {
        if (bubble != null) return

        val size = dp(52)
        val background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.rgb(208, 218, 190))
            setStroke(dp(1), Color.argb(110, 74, 87, 63))
        }
        val view = TextView(this).apply {
            text = "i"
            textSize = 25f
            setTextColor(Color.rgb(42, 52, 38))
            gravity = Gravity.CENTER
            contentDescription = getString(R.string.companion_share_bubble_description)
            elevation = dp(8).toFloat()
            this.background = background
            setOnTouchListener(BubbleTouchListener())
        }
        val metrics = resources.displayMetrics
        val params = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (metrics.widthPixels - size - dp(10)).coerceAtLeast(0)
            y = (metrics.heightPixels / 2 - size / 2).coerceAtLeast(0)
        }
        bubble = view
        bubbleParams = params
        showBubble()
    }

    private fun showBubble() {
        val view = bubble ?: return
        val params = bubbleParams ?: return
        if (bubbleAttached || isKeyguardLocked()) return
        try {
            windowManager.addView(view, params)
            bubbleAttached = true
        } catch (_: Throwable) {
            bubbleAttached = false
        }
    }

    private fun hideBubble() {
        val view = bubble ?: return
        if (!bubbleAttached) return
        try {
            windowManager.removeView(view)
        } catch (_: Throwable) {
            // The system may already have detached the accessibility overlay.
        } finally {
            bubbleAttached = false
        }
    }

    private fun removeBubble() {
        hideBubble()
        bubble = null
        bubbleParams = null
    }

    private fun shareCurrentScreen() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            toast(getString(R.string.companion_share_screenshot_unsupported))
            return
        }
        hideBubble()
        mainHandler.postDelayed({
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val buffer = screenshot.hardwareBuffer
                        try {
                            val hardwareBitmap = Bitmap.wrapHardwareBuffer(
                                buffer,
                                screenshot.colorSpace,
                            )
                            val bitmap = hardwareBitmap?.copy(Bitmap.Config.ARGB_8888, false)
                            if (bitmap == null) {
                                restoreAfterFailure(R.string.companion_share_screenshot_failed)
                                return
                            }
                            val file = persistScreenshot(bitmap)
                            bitmap.recycle()
                            launchImageShare(file)
                        } catch (_: Throwable) {
                            restoreAfterFailure(R.string.companion_share_screenshot_failed)
                        } finally {
                            buffer.close()
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        restoreAfterFailure(R.string.companion_share_screenshot_failed)
                    }
                },
            )
        }, SCREENSHOT_DELAY_MS)
    }

    private fun shareCopiedLink() {
        val clipboardText = readClipboardText()
        val sharedText = clipboardText?.takeIf { HTTP_URL.containsMatchIn(it) }
            ?: CLIPBOARD_LINK_MARKER
        hideBubble()
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, sharedText)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        startActivity(intent)
    }

    private fun launchImageShare(file: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = "image/jpeg"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            clipData = android.content.ClipData.newUri(
                contentResolver,
                getString(R.string.companion_share_screenshot_label),
                uri,
            )
        }
        startActivity(intent)
    }

    private fun persistScreenshot(bitmap: Bitmap): File {
        val directory = File(cacheDir, "companion_shares").apply { mkdirs() }
        directory.listFiles()
            ?.filter { it.isFile && System.currentTimeMillis() - it.lastModified() > 24 * 60 * 60 * 1000L }
            ?.forEach { it.delete() }
        val file = File(directory, "screen_${System.currentTimeMillis()}.jpg")
        FileOutputStream(file).use { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 92, output)) {
                throw IllegalStateException("Screenshot compression failed")
            }
        }
        return file
    }

    private fun readClipboardText(): String? {
        return try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            if (!clipboard.hasPrimaryClip()) return null
            clipboard.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.coerceToText(this)
                ?.toString()
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        }
    }

    private fun restoreAfterFailure(message: Int) {
        toast(getString(message))
        showBubble()
    }

    private fun isKeyguardLocked(): Boolean {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        return keyguard.isKeyguardLocked
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private inner class BubbleTouchListener : View.OnTouchListener {
        private var downAt = 0L
        private var downRawX = 0f
        private var downRawY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val params = bubbleParams ?: return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downAt = System.currentTimeMillis()
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!dragging && (abs(dx) > dp(DRAG_SLOP_DP) || abs(dy) > dp(DRAG_SLOP_DP))) {
                        dragging = true
                    }
                    if (dragging) {
                        val metrics = resources.displayMetrics
                        params.x = (startX + dx.toInt()).coerceIn(0, metrics.widthPixels - view.width)
                        params.y = (startY + dy.toInt()).coerceIn(0, metrics.heightPixels - view.height)
                        windowManager.updateViewLayout(view, params)
                    }
                    return true
                }

                MotionEvent.ACTION_UP -> {
                    if (!dragging) {
                        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                        if (System.currentTimeMillis() - downAt >= LONG_PRESS_MS) {
                            shareCopiedLink()
                        } else {
                            shareCurrentScreen()
                        }
                    }
                    return true
                }

                MotionEvent.ACTION_CANCEL -> return true
            }
            return false
        }
    }
}
