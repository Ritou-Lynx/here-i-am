import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:memex/data/services/reading/xhs/xhs_cookie_repository.dart';
import 'package:memex/data/services/reading/xhs/xhs_hidden_webview_host.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/logger.dart';

/// Full-screen page that lets the user log into 小红书 inside an in-app
/// WebView. The cookie is persisted by the system WebView store and shared
/// with [XhsHiddenWebViewHost], so once the login completes here the
/// background fetcher inherits the session for free.
///
/// Login detection: we poll `document.cookie` on every page finish until
/// a `web_session=...` entry appears, then close the page with success.
class XhsConnectPage extends StatefulWidget {
  const XhsConnectPage({super.key});

  @override
  State<XhsConnectPage> createState() => _XhsConnectPageState();
}

class _XhsConnectPageState extends State<XhsConnectPage> {
  static const _loginUrl = 'https://www.xiaohongshu.com/explore';
  // Desktop UA. The mobile XHS web shell is just a "download our App"
  // landing page with no login controls — only the desktop view renders
  // the QR / phone-number login. We use the same UA in the hidden fetcher
  // host so the session cookie minted here stays valid there.
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  final Logger _logger = getLogger('XhsConnectPage');
  WebViewController? _controller;
  Timer? _pollTimer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _startWebView();
  }

  void _startWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _scheduleCookiePoll(),
          onNavigationRequest: (request) {
            // Block deep-link / app-scheme navigations the page tries to
            // trigger (e.g. xhsdiscover://, intent://). Without this, the
            // user sees an ugly NET::ERR_UNKNOWN_URL_SCHEME page.
            if (!_isHttp(request.url)) {
              _logger.info('Blocked non-http navigation: ${request.url}');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
    setState(() => _controller = controller);
  }

  bool _isHttp(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  void _scheduleCookiePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_completed) {
        timer.cancel();
        return;
      }
      final controller = _controller;
      if (controller == null) return;
      try {
        final raw = await controller
            .runJavaScriptReturningResult('document.cookie');
        String s = raw.toString();
        if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
          s = s.substring(1, s.length - 1).replaceAll(r'\"', '"');
        }
        // XHS keeps `web_session` HttpOnly so document.cookie can't see it.
        // Instead, use total cookie string length as a soft "looks logged
        // in" signal — pre-login is typically <150 chars, post-login is
        // 500+ chars after the server sets webId/gid/userId/etc.
        // The user-pressed "I've logged in" button is the authoritative
        // path; this is just a convenience.
        if (s.length > 350) {
          _logger.info('Cookie string length=${s.length}, auto-confirming.');
          _onLoginDetected(s);
          timer.cancel();
        }
      } catch (e) {
        _logger.fine('Cookie poll failed: $e');
      }
    });
  }

  Future<void> _onLoginDetected(String sessionCookie) async {
    if (_completed) return;
    _completed = true;
    XhsCookieRepository.instance.recordSessionCookie(sessionCookie);
    // Auto-detected login is also persisted to prefs so it survives app
    // restarts. (markConnectedByUser does the prefs write.)
    await XhsCookieRepository.instance.markConnectedByUser();
    // Also trigger a background probe so the hidden host caches the same
    // state without waiting for the next app restart.
    XhsHiddenWebViewHost.probeLoginState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已连接小红书账号'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  /// User taps the "我已登录" action — authoritative confirmation that
  /// bypasses cookie auto-detection. Needed because XHS marks the main
  /// session cookie HttpOnly, so JS-side detection often misses it.
  Future<void> _onUserAssertedLogin() async {
    if (_completed) return;
    _completed = true;
    await XhsCookieRepository.instance.markConnectedByUser();
    XhsHiddenWebViewHost.probeLoginState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已连接小红书账号'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpringRainUiTokens.daylightCanvas,
      appBar: AppBar(
        title: const Text('连接小红书账号'),
        backgroundColor: SpringRainUiTokens.daylightCanvas,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _onUserAssertedLogin,
            child: const Text(
              '我已登录',
              style: TextStyle(
                color: SpringRainUiTokens.daylightAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            color: SpringRainUiTokens.daylightCanvas,
            child: const Text(
              '在下方页面登录你的小红书账号（推荐用手机号或扫码）。'
              '登录成功后请点击右上角的「我已登录」按钮完成连接。\n\n'
              '提示：登录后请不要在电脑版小红书同时登录同一账号，否则其中一个会被踢下线。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          Expanded(
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller!),
          ),
        ],
      ),
    );
  }
}
