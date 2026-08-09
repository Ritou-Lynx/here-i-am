package com.memexlab.memex

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Message
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.RequiresApi

/**
 * Prevents a vendor WebView renderer crash from terminating the whole app.
 *
 * Android requires every WebView associated with a dead renderer to return
 * true from WebViewClient.onRenderProcessGone(). webview_flutter currently
 * leaves the default false implementation in place, so Chromium deliberately
 * aborts the application when a renderer dies. This guard wraps each WebView
 * client while preserving all callbacks used by the Flutter plugin.
 */
class WebViewRenderProcessGuard(private val root: View) {
    companion object {
        private const val TAG = "WebViewProcessGuard"
    }

    private val layoutListener = ViewTreeObserver.OnGlobalLayoutListener {
        wrapWebViews(root)
    }

    fun install() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        root.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
        root.post { wrapWebViews(root) }
    }

    fun uninstall() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (root.viewTreeObserver.isAlive) {
            root.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
        }
    }

    private fun wrapWebViews(view: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (view is WebView) {
            wrap(view)
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                wrapWebViews(view.getChildAt(index))
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @SuppressLint("RequiresFeature")
    private fun wrap(webView: WebView) {
        val current = webView.webViewClient
        if (current is GuardedWebViewClient) return
        webView.webViewClient = GuardedWebViewClient(current)
        Log.d(TAG, "Installed renderer guard on WebView")
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private class GuardedWebViewClient(
        private val delegate: WebViewClient,
    ) : WebViewClient() {
        override fun onRenderProcessGone(
            view: WebView,
            detail: RenderProcessGoneDetail,
        ): Boolean {
            Log.e(
                TAG,
                "WebView renderer gone; keeping app alive " +
                    "(didCrash=${detail.didCrash()}, priority=${detail.rendererPriorityAtExit()})",
            )
            view.post {
                try {
                    (view.parent as? ViewGroup)?.removeView(view)
                    view.stopLoading()
                    view.destroy()
                } catch (error: Throwable) {
                    Log.w(TAG, "Failed to dispose crashed WebView", error)
                }
            }
            return true
        }

        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) =
            delegate.onPageStarted(view, url, favicon)

        override fun onPageFinished(view: WebView, url: String) =
            delegate.onPageFinished(view, url)

        override fun onPageCommitVisible(view: WebView, url: String) =
            delegate.onPageCommitVisible(view, url)

        override fun onLoadResource(view: WebView, url: String) =
            delegate.onLoadResource(view, url)

        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) =
            delegate.doUpdateVisitedHistory(view, url, isReload)

        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean = delegate.shouldOverrideUrlLoading(view, request)

        @Suppress("DEPRECATION")
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
            delegate.shouldOverrideUrlLoading(view, url)

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) = delegate.onReceivedError(view, request, error)

        @Suppress("DEPRECATION")
        override fun onReceivedError(
            view: WebView,
            errorCode: Int,
            description: String,
            failingUrl: String,
        ) = delegate.onReceivedError(view, errorCode, description, failingUrl)

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: WebResourceResponse,
        ) = delegate.onReceivedHttpError(view, request, errorResponse)

        override fun onReceivedHttpAuthRequest(
            view: WebView,
            handler: HttpAuthHandler,
            host: String,
            realm: String,
        ) = delegate.onReceivedHttpAuthRequest(view, handler, host, realm)

        override fun onReceivedSslError(
            view: WebView,
            handler: SslErrorHandler,
            error: SslError,
        ) = delegate.onReceivedSslError(view, handler, error)

        override fun onReceivedClientCertRequest(
            view: WebView,
            request: ClientCertRequest,
        ) = delegate.onReceivedClientCertRequest(view, request)

        override fun onReceivedLoginRequest(
            view: WebView,
            realm: String,
            account: String?,
            args: String,
        ) = delegate.onReceivedLoginRequest(view, realm, account, args)

        override fun onFormResubmission(
            view: WebView,
            dontResend: Message,
            resend: Message,
        ) = delegate.onFormResubmission(view, dontResend, resend)

        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) =
            delegate.onScaleChanged(view, oldScale, newScale)

        override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) =
            delegate.onUnhandledKeyEvent(view, event)
    }
}
