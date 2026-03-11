package com.memexlab.memex

import android.webkit.WebView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.memexlab.memex/webview"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "disableScrolling") {
                disableWebViewScrolling()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun disableWebViewScrolling() {
        // Find all WebView instances in the view hierarchy and disable scrolling.
        val rootView = window.decorView.rootView
        disableScrollingInView(rootView)
    }

    private fun disableScrollingInView(view: View) {
        if (view is WebView) {
            // Disable scrolling on the WebView scroll container.
            view.isVerticalScrollBarEnabled = false
            view.isHorizontalScrollBarEnabled = false
            view.overScrollMode = View.OVER_SCROLL_NEVER
        }
        
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                disableScrollingInView(view.getChildAt(i))
            }
        }
    }
}
