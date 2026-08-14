/// YouTube IFrame Player Adapter (Android / mobile).
///
/// Uses [WebView] to embed the official YouTube IFrame Player API, providing
/// compliant playback control: play, pause, seek, getCurrentTime, getDuration.
///
/// **Compliance**: This adapter only uses the official YouTube IFrame Player
/// API. It does not download videos, remove DRM, bypass age/login restrictions,
/// or access private content. Videos that require login or are region-restricted
/// will show the platform's own restriction UI — the adapter does not circumvent.
///
/// **Platform routing**:
/// - **Flutter Web**: use [createYouTubeAdapter] (returns
///   [WebYouTubePlayerAdapter] driving the IFrame API via `dart:js_interop`).
/// - **Android**: this adapter (webview_flutter). Call [createYouTubeAdapter].
/// - **Other platforms**: no-op stub — callers must check `isAvailable`.
///
/// Prefer [createYouTubeAdapter] (from `youtube_adapter_factory.dart`) over
/// constructing this class directly so the correct platform implementation is
/// returned.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

/// YouTube IFrame Player Adapter.
///
/// On Android, this embeds a WebView with the YouTube IFrame Player API.
/// On other platforms, construction is a no-op stub — use
/// [createYouTubeAdapter] or [FixturePlayerAdapter] instead.
class YouTubePlayerAdapter implements PlayerAdapter {
  WebViewController? _controller;
  bool _isLoaded = false;
  int _durationMs = 0;
  int _positionMs = 0;
  Timer? _pollTimer;

  final StreamController<PlayerTimeEvent> _timeController =
      StreamController<PlayerTimeEvent>.broadcast();

  /// The WebViewController for embedding in the UI tree.
  ///
  /// Returns null on platforms where WebView is unavailable.
  WebViewController? get webViewController => _controller;

  YouTubePlayerAdapter() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      // On non-Android platforms, the adapter is a stub that cannot load.
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
  }

  @override
  String get providerId => 'youtube';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor('youtube');

  @override
  Stream<PlayerTimeEvent> get timeEvents => _timeController.stream;

  /// Whether this adapter is available on the current platform.
  bool get isAvailable => _controller != null;

  /// Loads a YouTube video by its video ID.
  ///
  /// [sourceId] is the stable source identifier; [embedUrl] is the YouTube
  /// watch URL or video ID. The adapter extracts the video ID and constructs
  /// an IFrame embed URL.
  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    if (_controller == null) return;
    final videoId = _extractVideoId(embedUrl);
    if (videoId == null) return;

    final html = _buildEmbedHtml(videoId);
    await _controller!.loadHtmlString(html, baseUrl: 'https://www.youtube.com');
    _isLoaded = true;
  }

  @override
  Future<void> play() async {
    if (!_isLoaded || _controller == null) return;
    await _controller!.runJavaScript('if(window.ytPlayer) ytPlayer.playVideo();');
    _startPolling();
  }

  @override
  Future<void> pause() async {
    if (!_isLoaded || _controller == null) return;
    await _controller!.runJavaScript('if(window.ytPlayer) ytPlayer.pauseVideo();');
    _stopPolling();
  }

  @override
  Future<int> currentPositionMs() async {
    if (!_isLoaded || _controller == null) return 0;
    try {
      final result =
          await _controller!.runJavaScriptReturningResult(
              'window.ytPlayer ? Math.round(ytPlayer.getCurrentTime() * 1000) : 0');
      _positionMs = (result as num).toInt();
      return _positionMs;
    } catch (_) {
      return _positionMs;
    }
  }

  @override
  Future<int?> durationMs() async {
    if (!_isLoaded || _controller == null) return null;
    try {
      final result =
          await _controller!.runJavaScriptReturningResult(
              'window.ytPlayer ? Math.round(ytPlayer.getDuration() * 1000) : 0');
      _durationMs = (result as num).toInt();
      return _durationMs;
    } catch (_) {
      return _durationMs > 0 ? _durationMs : null;
    }
  }

  @override
  Future<void> seekTo(int positionMs) async {
    if (!_isLoaded || _controller == null) return;
    final seconds = (positionMs / 1000).toStringAsFixed(2);
    await _controller!.runJavaScript(
        'if(window.ytPlayer) ytPlayer.seekTo($seconds, true);');
    _positionMs = positionMs;
    _timeController.add(PlayerTimeEvent(
      positionMs: _positionMs,
      durationMs: _durationMs > 0 ? _durationMs : null,
      at: DateTime.now(),
    ));
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (_controller == null) return;
      try {
        final posResult = await _controller!.runJavaScriptReturningResult(
            'window.ytPlayer ? Math.round(ytPlayer.getCurrentTime() * 1000) : -1');
        final durResult = await _controller!.runJavaScriptReturningResult(
            'window.ytPlayer ? Math.round(ytPlayer.getDuration() * 1000) : 0');
        final pos = (posResult as num).toInt();
        final dur = (durResult as num).toInt();
        if (pos >= 0) {
          _positionMs = pos;
          if (dur > 0) _durationMs = dur;
          _timeController.add(PlayerTimeEvent(
            positionMs: _positionMs,
            durationMs: _durationMs > 0 ? _durationMs : null,
            at: DateTime.now(),
          ));
        }
      } catch (_) {
        // Player not ready yet — skip.
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  String? _extractVideoId(String? url) {
    if (url == null || url.isEmpty) return null;
    // Direct video ID (11 chars).
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;
    // watch?v=ID
    final watchMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (watchMatch != null) return watchMatch.group(1);
    // youtu.be/ID
    final shortMatch = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (shortMatch != null) return shortMatch.group(1);
    // embed/ID
    final embedMatch = RegExp(r'embed/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (embedMatch != null) return embedMatch.group(1);
    return null;
  }

  String _buildEmbedHtml(String videoId) {
    return '''
<!DOCTYPE html>
<html style="margin:0;padding:0;background:#000;">
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin: 0; padding: 0; background: #000; overflow: hidden; }
    #player { width: 100vw; height: 100vh; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script src="https://www.youtube.com/iframe_api"></script>
  <script>
    var ytPlayer;
    function onYouTubeIframeAPIReady() {
      ytPlayer = new YT.Player('player', {
        videoId: '$videoId',
        playerVars: {
          'playsinline': 1,
          'modestbranding': 1,
          'rel': 0
        },
        events: {
          'onReady': function() { window.ytReady = true; },
          'onStateChange': function(e) { window.ytState = e.data; }
        }
      });
    }
  </script>
</body>
</html>
''';
  }

  /// Disposes the adapter.
  void dispose() {
    _stopPolling();
    _timeController.close();
  }
}