package com.hiennv.flutter_callkit_incoming

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Log
import android.widget.ImageView
import coil.ImageLoader
import coil.request.ImageRequest
import coil.target.Target
import com.hiennv.flutter_callkit_incoming.widgets.CircleTransform
import okhttp3.OkHttpClient

object ImageLoaderProvider {
    @SuppressLint("StaticFieldLeak")
    private var instance: ImageLoader? = null

    // MEMEX PATCH: the plugin's call screens unconditionally prefix any
    // non-http avatar with "file:///android_asset/flutter_assets/", which
    // breaks real on-disk file paths (e.g. user-uploaded character avatars).
    // Coil can load file:// URIs and absolute paths directly, so here we undo
    // that wrong prefix when the original value was actually a local file.
    private const val ASSET_PREFIX = "file:///android_asset/flutter_assets/"

    private fun sanitizeLocalPath(url: String): String {
        if (url.startsWith(ASSET_PREFIX)) {
            val rest = url.removePrefix(ASSET_PREFIX)
            if (rest.startsWith("file://") || rest.startsWith("/")) {
                return rest
            }
        }
        return url
    }

    fun get(context: Context, headers: HashMap<String, Any?>?): ImageLoader {
        if (instance == null) {
            val imageLoader = ImageLoader.Builder(context)
            val client = OkHttpClient.Builder()
                .followRedirects(true)
                .followSslRedirects(true)
                .addNetworkInterceptor { chain ->
                    val newRequestBuilder: okhttp3.Request.Builder = chain.request().newBuilder()
                    if (headers != null) {
                        for ((key, value) in headers) {
                            newRequestBuilder.addHeader(key, value.toString())
                        }
                    }
                    chain.proceed(newRequestBuilder.build())
                }
                .build()
            instance = imageLoader.okHttpClient(client).build()
        }
        return instance!!
    }

    fun loadImage(context: Context, url: String, headers: HashMap<String, Any?>?, target: Target?) {
        val imageLoader = get(context, headers)
        val requestBuilder = ImageRequest.Builder(context)
        headers?.forEach { (key, value) ->
            value?.toString()?.let {
                requestBuilder.addHeader(key, it)
            }
        }
        requestBuilder.data(sanitizeLocalPath(url))
        requestBuilder.allowHardware(false)
        requestBuilder.transformations(CircleTransform())
        requestBuilder.target(target)

        imageLoader.enqueue(requestBuilder.build())
    }

    fun loadImage(context: Context, url: String, headers: HashMap<String, Any?>?, placeholder: Int, target: ImageView) {
        val imageLoader = get(context, headers)
        val requestBuilder = ImageRequest.Builder(context)
        headers?.forEach { (key, value) ->
            value?.toString()?.let {
                requestBuilder.addHeader(key, it)
            }
        }
        requestBuilder.data(sanitizeLocalPath(url))
        requestBuilder.allowHardware(false)
        requestBuilder.placeholder(placeholder)
        requestBuilder.error(placeholder)
        requestBuilder.target(target)

        imageLoader.enqueue(requestBuilder.build())
    }


}


open class SafeTarget(
    private val notificationId: Int,
    private val onLoaded: (Bitmap) -> Unit
) : Target {

    var isCancelled = false

    override fun onSuccess(result: Drawable) {
        super.onSuccess(result)
        Log.d("onSuccess", "-")
        if (!isCancelled) {
            onLoaded((result as BitmapDrawable).bitmap)
        }
    }

    override fun onStart(placeholder: Drawable?) {
        super.onStart(placeholder)
        Log.d("onStart", "-")
    }

    override fun onError(error: Drawable?) {
        super.onError(error)
        Log.d("onError", "-")
    }


}