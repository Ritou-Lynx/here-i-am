import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:memex/utils/logger.dart';

/// Knows whether the user has a valid 小红书 web session, and exposes a
/// listener for state changes so settings UI / fetcher registration can
/// react.
///
/// 小红书 stores its web session under the `xiaohongshu.com` domain in a
/// cookie named `web_session`. Presence of that cookie is the simplest
/// proxy for "logged in". The cookie is HttpOnly so we can't read it from
/// JS; instead we use webview_flutter's `runJavaScriptReturningResult` on
/// document.cookie which only sees non-HttpOnly cookies — but `web_session`
/// IS non-HttpOnly on xiaohongshu.com (verified manually). Still, we wrap
/// the check in a try/catch and use a "loaded a probe page" strategy via
/// the hidden WebView host so we can keep the API simple here.
///
/// This class is intentionally tiny — the actual cookie I/O happens inside
/// XhsHiddenWebViewHost (where a WebViewController is alive); this class
/// just caches the most recent answer and notifies listeners.
class XhsCookieRepository {
  XhsCookieRepository._();

  static final XhsCookieRepository instance = XhsCookieRepository._();

  static const _prefsConnectedKey = 'xhs_user_marked_connected';

  final Logger _logger = getLogger('XhsCookieRepository');

  /// True once we have observed a valid web_session cookie. Initially
  /// false; flipped to true after a successful login (or after a startup
  /// probe finds an existing session).
  final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);

  bool _restored = false;

  /// Restore the persisted "user marked connected" flag from
  /// SharedPreferences. Called once during app boot — the cookie itself is
  /// kept by the system WebView store across restarts, but our internal
  /// "I've confirmed I'm logged in" bit lives in prefs.
  Future<void> restoreFromPrefs() async {
    if (_restored) {
      _logger.fine('restoreFromPrefs: skipping (already restored)');
      return;
    }
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final connected = prefs.getBool(_prefsConnectedKey) ?? false;
      _logger.info(
          'restoreFromPrefs: prefs[$_prefsConnectedKey]=$connected');
      if (connected) {
        _lastKnownSessionCookie = '<restored-from-prefs>';
        isLoggedIn.value = true;
      }
    } catch (e) {
      _logger.warning('restoreFromPrefs failed: $e');
    }
  }

  /// Last-known session cookie value. Kept in memory for diagnostics
  /// (e.g. surfacing in dev tools); never written to disk by this app —
  /// webview_flutter persists cookies in the system WebView cookie store
  /// across app restarts on its own.
  String? _lastKnownSessionCookie;

  /// Called by XhsHiddenWebViewHost / XhsLoginPage when a cookie probe
  /// returns. Passing an empty string clears the flag.
  void recordSessionCookie(String? cookieValue) {
    _lastKnownSessionCookie = cookieValue;
    final logged = cookieValue != null && cookieValue.isNotEmpty;
    if (isLoggedIn.value != logged) {
      _logger.info('xhs login state -> $logged');
      isLoggedIn.value = logged;
    }
  }

  /// User-asserted "I have logged in" — used by the connect page when our
  /// passive cookie probe can't see HttpOnly session tokens (XHS marks
  /// `web_session` HttpOnly so document.cookie never exposes it). The user
  /// is the source of truth here.
  ///
  /// Also persists to SharedPreferences so the bit survives app restarts
  /// — the system WebView keeps the cookie itself, but without this our
  /// in-memory isLoggedIn would default back to false on reboot and the
  /// user would have to re-confirm even though their session is still
  /// alive.
  Future<void> markConnectedByUser() async {
    _lastKnownSessionCookie = '<user-asserted>';
    if (!isLoggedIn.value) {
      _logger.info('xhs login state -> true (user asserted)');
      isLoggedIn.value = true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setBool(_prefsConnectedKey, true);
      // Verify the write took effect — useful for diagnosing prefs being
      // re-cleared by something else.
      final readback = prefs.getBool(_prefsConnectedKey);
      _logger.info(
          'markConnectedByUser: setBool=$ok, readback=$readback');
    } catch (e) {
      _logger.warning('Failed to persist xhs connected flag: $e');
    }
  }

  /// Force-forgets the current session. Caller is responsible for actually
  /// clearing system cookies (via WebViewCookieManager).
  Future<void> clear() async {
    _lastKnownSessionCookie = null;
    if (isLoggedIn.value) {
      isLoggedIn.value = false;
    }
    try {
      await WebViewCookieManager().clearCookies();
    } catch (e) {
      _logger.warning('Failed to clear cookies: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsConnectedKey);
    } catch (e) {
      _logger.warning('Failed to clear persisted xhs flag: $e');
    }
  }

  String? get lastKnownSessionCookieForDiagnostics =>
      _lastKnownSessionCookie;
}
