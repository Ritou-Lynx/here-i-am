package com.memexlab.bedwatch

import android.app.Activity
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.os.Bundle
import android.view.Surface
import android.view.TextureView
import android.widget.FrameLayout
import android.widget.TextView
import androidx.camera.core.Preview
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry

class PreviewActivity : Activity(), LifecycleOwner {
    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry
    private lateinit var camera: CameraSession
    private lateinit var texture: TextureView
    private lateinit var readout: TextView
    private var foreground = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        camera = CameraSession(this, this)
        texture = TextureView(this)
        readout = TextView(this).apply {
            text = "仅前台预览 · 不保存\n返回后恢复监测"
            textSize = 20f; setTextColor(android.graphics.Color.WHITE); setBackgroundColor(0x99000000.toInt())
        }
        setContentView(FrameLayout(this).apply {
            addView(texture, FrameLayout.LayoutParams(-1, -1))
            addView(readout, FrameLayout.LayoutParams(-1, -2))
        })
        texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) { startPreview() }
            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
                camera.stop(); startPreview()
            }
            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean { camera.stop(); return true }
            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
        }
    }
    private fun startPreview() {
        if (!foreground || !texture.isAvailable) return
        val config = Settings(this).read()
        val judge = AwakeJudge(config.thresholds)
        val main = ContextCompat.getMainExecutor(this)
        val surfaceProvider = Preview.SurfaceProvider { request ->
            val surfaceTexture = texture.surfaceTexture
            if (!foreground || surfaceTexture == null) { request.willNotProvideSurface() }
            else {
                val size = request.resolution
                surfaceTexture.setDefaultBufferSize(size.width, size.height)
                request.setTransformationInfoListener(main) { info ->
                    // Undo TextureView's initial stretch, then rotate and fit the upright buffer.
                    val w = texture.width.toFloat(); val h = texture.height.toFloat()
                    val rotated = info.rotationDegrees % 180 != 0
                    val scale = minOf(w / (if (rotated) size.height else size.width),
                        h / (if (rotated) size.width else size.height))
                    val matrix = Matrix()
                    matrix.postTranslate(-w / 2, -h / 2)
                    matrix.postScale(size.width / w, size.height / h)
                    matrix.postRotate(info.rotationDegrees.toFloat())
                    matrix.postScale(if (config.front) -scale else scale, scale)
                    matrix.postTranslate(w / 2, h / 2)
                    texture.setTransform(matrix)
                }
                val surface = Surface(surfaceTexture)
                request.provideSurface(surface, main) { surface.release() }
            }
        }
        camera.start(config.front, 500, surfaceProvider,
            onError = { readout.text = "相机不可用，请返回检查权限和相机选择。" },
            onFrame = { f ->
                val verdict = judge.classify(f)
                runOnUiThread { if (foreground) readout.text = "face=${if (f.face) 1 else 0}  eyesOpen=${f.eyesOpen ?: -1f}\n" +
                    "glow=%.2f  luma=%.1f\n%s\n返回后恢复监测".format(f.glow, f.frameLuma, verdict) }
            })
    }
    override fun onStart() { super.onStart(); registry.handleLifecycleEvent(Lifecycle.Event.ON_START) }
    override fun onResume() {
        super.onResume(); registry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
        foreground = true; startPreview()
    }
    override fun onPause() {
        foreground = false; camera.stop(); registry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE); super.onPause()
    }
    override fun onStop() { registry.handleLifecycleEvent(Lifecycle.Event.ON_STOP); super.onStop() }
    override fun onDestroy() { camera.close(); registry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY); super.onDestroy() }
}
