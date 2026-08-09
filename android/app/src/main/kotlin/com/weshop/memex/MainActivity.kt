package com.memexlab.memex

import android.content.Intent
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import com.memexlab.memex.channels.BackupImportChannelHandler
import com.memexlab.memex.channels.BackupStorageChannelHandler
import com.memexlab.memex.channels.ChannelRegistrar
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val OPENING_SPLASH_CHANNEL = "com.memexlab.memex/opening_splash"
        private const val HERE_I_AM_V3_PACKAGE = "com.memexlab.hereiam.v3"
        private const val NATIVE_SPLASH_ASSET =
            "flutter_assets/assets/images/spring_rain_daydream_splash_v6_native.mp4"
        private const val SPLASH_FAILSAFE_MS = 20_000L
    }

    private var mediaButtonChannel: MethodChannel? = null
    private var openingSplashChannel: MethodChannel? = null
    private var openingSplashOverlay: FrameLayout? = null
    private var openingSplashTexture: TextureView? = null
    private var openingSplashPlayer: MediaPlayer? = null
    private var openingSplashSurface: Surface? = null
    private var openingSplashPrepared = false
    private var webViewRenderProcessGuard: WebViewRenderProcessGuard? = null
    private val openingSplashHandler = Handler(Looper.getMainLooper())
    private val openingSplashFailsafe = Runnable { dismissNativeOpeningSplash() }

    override fun getRenderMode(): RenderMode {
        // A SurfaceView keeps Android's system splash visible until Flutter's
        // first raster frame. Texture mode lets this Activity draw the native
        // video immediately while Flutter continues booting underneath it.
        return if (packageName == HERE_I_AM_V3_PACKAGE) RenderMode.texture
        else super.getRenderMode()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // If the Activity is being recreated (system killed it in background),
        // clear the stale shortcut extra so the quick_actions plugin won't
        // re-deliver an already-consumed action on the next attach cycle.
        if (savedInstanceState != null) {
            intent?.removeExtra("some unique action key")
        }
        super.onCreate(savedInstanceState)
        webViewRenderProcessGuard = WebViewRenderProcessGuard(window.decorView).also {
            it.install()
        }
        BackupImportChannelHandler.handleIntent(this, intent)
        if (packageName == HERE_I_AM_V3_PACKAGE && savedInstanceState == null) {
            showNativeOpeningSplash()
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        BackupImportChannelHandler.handleIntent(this, intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register all MethodChannel handlers
        ChannelRegistrar.registerAll(flutterEngine, this)
        registerMediaButtonChannel(flutterEngine)
        registerOpeningSplashChannel(flutterEngine)
    }

    private fun registerMediaButtonChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.memexlab.memex/media_buttons",
        )
        mediaButtonChannel = channel
        // The bridge is process-scoped: attach the channel here, detach on
        // destroy, never release the MediaSession with the Activity.
        MediaButtonBridge.attachChannel(channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "activate" -> {
                    MediaButtonBridge.activate(applicationContext)
                    result.success(null)
                }

                "deactivate" -> {
                    MediaButtonBridge.deactivate()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun registerOpeningSplashChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OPENING_SPLASH_CHANNEL,
        )
        openingSplashChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "dismiss" -> {
                    dismissNativeOpeningSplash()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun showNativeOpeningSplash() {
        if (openingSplashOverlay != null) return

        val overlay = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(243, 243, 236))
            isClickable = true
            isFocusable = true
            elevation = 10_000f
        }
        val poster = ImageView(this).apply {
            setImageResource(R.drawable.spring_rain_daydream_launch)
            scaleType = ImageView.ScaleType.FIT_XY
        }
        val texture = TextureView(this).apply {
            alpha = 0f
            isOpaque = true
        }

        overlay.addView(
            poster,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        overlay.addView(
            texture,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        addContentView(
            overlay,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        openingSplashOverlay = overlay
        openingSplashTexture = texture
        texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(
                surfaceTexture: SurfaceTexture,
                width: Int,
                height: Int,
            ) {
                prepareNativeOpeningVideo(surfaceTexture)
            }

            override fun onSurfaceTextureSizeChanged(
                surfaceTexture: SurfaceTexture,
                width: Int,
                height: Int,
            ) = Unit

            override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
                releaseNativeOpeningPlayer()
                return true
            }

            override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = Unit
        }
        openingSplashHandler.postDelayed(openingSplashFailsafe, SPLASH_FAILSAFE_MS)
    }

    private fun prepareNativeOpeningVideo(surfaceTexture: SurfaceTexture) {
        releaseNativeOpeningPlayer()
        val surface = Surface(surfaceTexture)
        openingSplashSurface = surface
        val player = MediaPlayer()
        openingSplashPlayer = player
        try {
            assets.openFd(NATIVE_SPLASH_ASSET).use { descriptor ->
                player.setDataSource(
                    descriptor.fileDescriptor,
                    descriptor.startOffset,
                    descriptor.length,
                )
            }
            player.setSurface(surface)
            player.isLooping = true
            player.setVolume(0f, 0f)
            player.setOnPreparedListener {
                openingSplashPrepared = true
                it.start()
            }
            player.setOnInfoListener { _, what, _ ->
                if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) {
                    openingSplashTexture?.animate()?.alpha(1f)?.setDuration(80L)?.start()
                }
                false
            }
            player.setOnErrorListener { _, what, extra ->
                Log.e("NativeOpeningSplash", "MediaPlayer error what=$what extra=$extra")
                openingSplashPrepared = false
                openingSplashTexture?.visibility = View.INVISIBLE
                true
            }
            player.prepareAsync()
        } catch (error: Exception) {
            Log.e("NativeOpeningSplash", "Unable to prepare native opening video", error)
            releaseNativeOpeningPlayer()
        }
    }

    private fun dismissNativeOpeningSplash() {
        openingSplashHandler.removeCallbacks(openingSplashFailsafe)
        val overlay = openingSplashOverlay ?: return
        openingSplashOverlay = null
        overlay.animate()
            .alpha(0f)
            .setDuration(120L)
            .withEndAction {
                (overlay.parent as? ViewGroup)?.removeView(overlay)
                releaseNativeOpeningPlayer()
                openingSplashTexture = null
            }
            .start()
    }

    private fun releaseNativeOpeningPlayer() {
        openingSplashPrepared = false
        val player = openingSplashPlayer
        openingSplashPlayer = null
        player?.runCatching { setSurface(null) }
        player?.runCatching { stop() }
        player?.runCatching { reset() }
        player?.runCatching { release() }
        openingSplashSurface?.release()
        openingSplashSurface = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (BackupStorageChannelHandler.handleActivityResult(requestCode, resultCode, data)) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (handleMediaKeyEvent(event)) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun handleMediaKeyEvent(event: KeyEvent): Boolean {
        val isMediaVoiceKey = when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_MEDIA_NEXT,
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> true
            else -> false
        }
        if (!isMediaVoiceKey) return false

        Log.d("MediaButtonBridge", "activity keyCode=${event.keyCode} action=${event.action}")
        if (event.action != KeyEvent.ACTION_DOWN) {
            return true
        }

        if (event.keyCode == KeyEvent.KEYCODE_MEDIA_PREVIOUS) {
            MediaButtonBridge.dispatchCancel()
        } else {
            MediaButtonBridge.dispatchToggle()
        }
        return true
    }

    override fun onResume() {
        super.onResume()
        MediaButtonBridge.setAppBackground(false)
        val player = openingSplashPlayer
        if (openingSplashPrepared && player != null) {
            player.runCatching {
                if (!isPlaying) start()
            }
        }
    }

    override fun onPause() {
        val player = openingSplashPlayer
        if (openingSplashPrepared && player != null) {
            player.runCatching {
                if (isPlaying) pause()
            }
        }
        super.onPause()
        MediaButtonBridge.setAppBackground(true)
    }

    override fun onDestroy() {
        webViewRenderProcessGuard?.uninstall()
        webViewRenderProcessGuard = null
        openingSplashHandler.removeCallbacks(openingSplashFailsafe)
        openingSplashChannel?.setMethodCallHandler(null)
        openingSplashChannel = null
        releaseNativeOpeningPlayer()
        // Do NOT deactivate the MediaSession here: the bridge is process-scoped
        // and must survive Activity destruction so headset keys keep working
        // with the app backgrounded. Events are routed to the main isolate via
        // the channel while it is alive, and fall back to the foreground-task
        // isolate (ForegroundService.sendData) once the engine is gone.
        MediaButtonBridge.detachChannel()
        super.onDestroy()
    }
}
