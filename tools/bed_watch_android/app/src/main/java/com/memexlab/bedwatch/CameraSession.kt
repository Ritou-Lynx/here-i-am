package com.memexlab.bedwatch

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.SystemClock
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Owns only in-memory CameraX buffers. No ImageCapture or file API. Night frames are reduced to numbers;
 * only an explicit on-demand snapshot (CAM1) is encoded to JPEG, in memory, and handed to the caller.
 */
class CameraSession(private val context: Context, private val owner: LifecycleOwner) {
    private val executor = Executors.newSingleThreadExecutor()
    private val detector = FaceDetection.getClient(FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL).build())
    private var provider: ProcessCameraProvider? = null
    private var analysis: ImageAnalysis? = null
    private var preview: Preview? = null
    @Volatile private var active = false
    @Volatile private var closed = false
    @Volatile private var generation = 0
    private var lastSample = Long.MIN_VALUE
    private var inFlight = false
    @Volatile private var snapshotCallback: ((Snapshot?) -> Unit)? = null
    @Volatile private var snapshotNotBefore = 0L
    val isActive: Boolean get() = active

    /** The next frame after [warmupMs] is encoded and passed to [callback] (on the camera thread). */
    fun requestSnapshot(warmupMs: Long, callback: (Snapshot?) -> Unit) {
        snapshotNotBefore = SystemClock.elapsedRealtime() + warmupMs
        snapshotCallback = callback
    }
    fun cancelSnapshot() { snapshotCallback = null }

    fun start(front: Boolean, intervalMs: Long, surface: Preview.SurfaceProvider? = null,
        onError: () -> Unit, onFrame: (FrameFeatures) -> Unit) {
        if (active || closed) return
        active = true
        val token = ++generation
        lastSample = Long.MIN_VALUE
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (!active || token != generation || closed) return@addListener
            try {
                val p = future.get()
                provider = p
                val a = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                analysis = a
                a.setAnalyzer(executor) { image ->
                    val now = SystemClock.elapsedRealtime()
                    val regular = lastSample == Long.MIN_VALUE || now - lastSample >= intervalMs
                    val snapshot = snapshotCallback != null && now >= snapshotNotBefore
                    if (!active || inFlight || (!regular && !snapshot)) {
                        image.close()
                    } else {
                        inFlight = true
                        if (regular) lastSample = now
                        analyze(image, token, onError, onFrame, regular, snapshot)
                    }
                }
                val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                preview = surface?.let { Preview.Builder().build().also { it.setSurfaceProvider(surface) } }
                val useCases = listOfNotNull(a, preview).toTypedArray()
                val camera = p.bindToLifecycle(owner, selector, *useCases)
                camera.cameraControl.setExposureCompensationIndex(0)
                // Ordinary CameraX only: no HDR/night extension provider is installed or enabled.
                camera.cameraControl.enableTorch(false)
            } catch (_: Exception) {
                stop()
                onError()
            }
        }, ContextCompat.getMainExecutor(context))
    }

    @androidx.annotation.OptIn(ExperimentalGetImage::class)
    private fun analyze(proxy: ImageProxy, token: Int, onError: () -> Unit, onFrame: (FrameFeatures) -> Unit,
        regular: Boolean = true, snapshot: Boolean = false) {
        val media = proxy.image
        if (media == null) { proxy.close(); inFlight = false; return }
        try {
            detector.process(InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees))
                .addOnCompleteListener(executor) { task ->
                    try {
                        if (!active || token != generation || closed) return@addOnCompleteListener
                        if (!task.isSuccessful) { ContextCompat.getMainExecutor(context).execute { onError() }; return@addOnCompleteListener }
                        val face = task.result.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }
                        val eye = face?.let { listOfNotNull(it.leftEyeOpenProbability, it.rightEyeOpenProbability).maxOrNull() }
                        val plane = proxy.planes[0]
                        val buffer = plane.buffer.duplicate()
                        val base = buffer.position()
                        val raw = ByteArray(proxy.width * proxy.height)
                        for (row in 0 until proxy.height) for (col in 0 until proxy.width) {
                            raw[row * proxy.width + col] = buffer.get(base + row * plane.rowStride + col * plane.pixelStride)
                        }
                        val rotation = proxy.imageInfo.rotationDegrees
                        val upright = LumaStats.rotate(raw, proxy.width, proxy.height, rotation)
                        raw.fill(0)
                        val width = if (rotation % 180 == 0) proxy.width else proxy.height
                        val height = if (rotation % 180 == 0) proxy.height else proxy.width
                        val box = face?.boundingBox?.let { FaceBox(it.left, it.top, it.right, it.bottom) }
                        val features = try { LumaStats.features(upright, width, height, box, eye) } finally { upright.fill(0) }
                        if (snapshot) {
                            val callback = snapshotCallback
                            snapshotCallback = null
                            val jpeg = runCatching { encodeJpeg(proxy, rotation) }.getOrNull()
                            callback?.invoke(jpeg?.let { Snapshot(it, features,
                                box?.let { b -> (b.left + b.right) / 2f / width }, box?.let { b -> (b.top + b.bottom) / 2f / height }) })
                        }
                        if (regular) onFrame(features)
                    } catch (_: Exception) {
                        ContextCompat.getMainExecutor(context).execute { onError() }
                    } finally {
                        proxy.close()
                        inFlight = false
                        if (closed) { detector.close(); executor.shutdown() }
                    }
                }
        } catch (_: Exception) {
            proxy.close(); inFlight = false
            ContextCompat.getMainExecutor(context).execute { onError() }
        }
    }

    /** YUV_420_888 -> upright JPEG (long side <= 960 px), entirely in memory. */
    private fun encodeJpeg(proxy: ImageProxy, rotation: Int): ByteArray {
        val w = proxy.width
        val h = proxy.height
        val nv21 = ByteArray(w * h * 3 / 2)
        val yPlane = proxy.planes[0]
        val yBuf = yPlane.buffer.duplicate()
        val yBase = yBuf.position()
        for (row in 0 until h) for (col in 0 until w) {
            nv21[row * w + col] = yBuf.get(yBase + row * yPlane.rowStride + col * yPlane.pixelStride)
        }
        val uPlane = proxy.planes[1]
        val vPlane = proxy.planes[2]
        val uBuf = uPlane.buffer.duplicate()
        val vBuf = vPlane.buffer.duplicate()
        val uBase = uBuf.position()
        val vBase = vBuf.position()
        var out = w * h
        for (row in 0 until h / 2) for (col in 0 until w / 2) {
            nv21[out++] = vBuf.get(vBase + row * vPlane.rowStride + col * vPlane.pixelStride)
            nv21[out++] = uBuf.get(uBase + row * uPlane.rowStride + col * uPlane.pixelStride)
        }
        val raw = ByteArrayOutputStream()
        YuvImage(nv21, ImageFormat.NV21, w, h, null).compressToJpeg(Rect(0, 0, w, h), 90, raw)
        nv21.fill(0)
        val decoded = BitmapFactory.decodeByteArray(raw.toByteArray(), 0, raw.size())
        val scale = minOf(1f, 960f / maxOf(w, h))
        val matrix = Matrix().apply { postScale(scale, scale); postRotate(rotation.toFloat()) }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        val jpeg = ByteArrayOutputStream()
        upright.compress(Bitmap.CompressFormat.JPEG, 80, jpeg)
        if (upright !== decoded) upright.recycle()
        decoded.recycle()
        return jpeg.toByteArray()
    }

    fun stop() {
        active = false
        snapshotCallback?.let { snapshotCallback = null; it(null) }
        generation++
        analysis?.clearAnalyzer()
        listOfNotNull(analysis, preview).takeIf { it.isNotEmpty() }?.let { provider?.unbind(*it.toTypedArray()) }
        analysis = null
        preview = null
    }
    fun close() {
        stop()
        closed = true
        executor.execute { if (!inFlight) { detector.close(); executor.shutdown() } }
    }
}
