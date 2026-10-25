package com.kuhy.kartka

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The WebView cookie jar for kartka's HTTP (docs/DOCS-contracts-webview.md
    // §5). getCookie returns the raw Cookie header, HttpOnly cookies included,
    // which webview_flutter's own getCookies mangles (it splits values on '=').
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kartka/webview_cookies")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCookie" ->
                        result.success(CookieManager.getInstance().getCookie(call.arguments as String))
                    "flush" -> {
                        CookieManager.getInstance().flush()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
