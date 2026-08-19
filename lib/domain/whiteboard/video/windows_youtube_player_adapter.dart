/// Windows-native YouTube IFrame adapter hosted inside Edge WebView2.
///
/// Uses only the public YouTube IFrame Player API. It never downloads media,
/// bypasses provider restrictions, or claims playback when WebView2/network/
/// embedding is unavailable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

class WindowsYouTubePlayerAdapter implements PlayerAdapter {
  static const String virtualHost = 'hereiam-player.local';

  final StreamController<PlayerTimeEvent> _timeController =
      StreamController<PlayerTimeEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  WebviewController? _controller;
  Directory? _hostDirectory;
  Completer<void>? _readyCompleter;
  int _positionMs = 0;
  int _durationMs = 0;
  bool _initialized = false;
  bool _playerReady = false;
  bool _disposed = false;
  String? _lastFailure;

  WebviewController? get webviewController => _controller;
  bool get isAvailable => Platform.isWindows && !_disposed;
  bool get isReady => _initialized && _playerReady;
  String? get lastFailure => _lastFailure;

  @override
  String get providerId => 'youtube';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor('youtube');

  @override
  Stream<PlayerTimeEvent> get timeEvents => _timeController.stream;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows YouTube 播放器只能在 Windows 原生 App 使用');
    }
    final videoId = extractVideoId(embedUrl);
    if (videoId == null) {
      throw const FormatException('无法从来源链接识别 YouTube video id');
    }
    await _ensureInitialized();
    _positionMs = 0;
    _durationMs = 0;
    _playerReady = false;
    _lastFailure = null;
    _readyCompleter = Completer<void>();
    await _controller!.loadUrl(
      'https://$virtualHost/player.html?v=${Uri.encodeQueryComponent(videoId)}',
    );
    try {
      await _readyCompleter!.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _lastFailure = 'YouTube 播放器加载超时（网络不可用或视频禁止嵌入）';
      throw StateError(_lastFailure!);
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final version = await WebviewController.getWebViewVersion();
      final runtimeFailure = runtimeFailureMessage(version);
      if (runtimeFailure != null) {
        throw StateError(runtimeFailure);
      }
      final controller = WebviewController();
      _controller = controller;
      _subscriptions
        ..add(controller.webMessage.listen(_handleMessage))
        ..add(controller.onLoadError.listen((status) {
          _failReady(pageLoadFailureMessage(status.name));
        }));
      await controller.initialize();
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setDefaultContextMenusEnabled(false);
      final hostDirectory = await Directory.systemTemp.createTemp(
        'hereiam_youtube_player_',
      );
      _hostDirectory = hostDirectory;
      await File('${hostDirectory.path}${Platform.pathSeparator}player.html')
          .writeAsString(_playerHtml, flush: true);
      await controller.addVirtualHostNameMapping(
        virtualHost,
        hostDirectory.path,
        WebviewHostResourceAccessKind.deny,
      );
      _initialized = true;
    } catch (error) {
      _lastFailure = 'Windows WebView2 初始化失败：$error';
      throw StateError(_lastFailure!);
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      switch (message['type']) {
        case 'ready':
          _durationMs = (message['duration_ms'] as num?)?.toInt() ?? 0;
          _playerReady = true;
          final ready = _readyCompleter;
          if (ready != null && !ready.isCompleted) ready.complete();
        case 'time':
          _positionMs = (message['position_ms'] as num?)?.toInt() ?? 0;
          final duration = (message['duration_ms'] as num?)?.toInt() ?? 0;
          if (duration > 0) _durationMs = duration;
          _timeController.add(PlayerTimeEvent(
            positionMs: _positionMs,
            durationMs: _durationMs > 0 ? _durationMs : null,
            at: DateTime.now(),
          ));
        case 'error':
          final code = (message['code'] as num?)?.toInt();
          _failReady(youtubeErrorMessage(code));
      }
    } catch (_) {
      // Ignore malformed page messages. No capability is inferred from them.
    }
  }

  void _failReady(String message) {
    _playerReady = false;
    _lastFailure = message;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError(message));
    }
  }

  static String? runtimeFailureMessage(String? version) =>
      version == null || version.trim().isEmpty
          ? '未安装 Microsoft Edge WebView2 Runtime'
          : null;

  static String pageLoadFailureMessage(String status) =>
      'WebView2 页面加载失败：$status';

  static String youtubeErrorMessage(int? code) => switch (code) {
        2 => 'YouTube 拒绝了无效的视频参数',
        5 => 'YouTube HTML5 播放器无法播放该视频',
        100 => 'YouTube 视频不存在或已设为私有',
        101 || 150 => '视频所有者禁止在第三方应用中嵌入播放',
        153 => 'YouTube 拒绝了缺少有效来源标识的嵌入请求',
        _ => 'YouTube 播放器失败${code == null ? '' : '（错误 $code）'}',
      };

  @override
  Future<void> play() async {
    await _execute('window.hereIamPlayer && window.hereIamPlayer.play();');
  }

  @override
  Future<void> pause() async {
    await _execute('window.hereIamPlayer && window.hereIamPlayer.pause();');
  }

  Future<void> setMuted(bool muted) async {
    await _execute(
      'window.hereIamPlayer && window.hereIamPlayer.setMuted(${muted ? 'true' : 'false'});',
    );
  }

  @override
  Future<int> currentPositionMs() async {
    final result = await _execute(
      'window.hereIamPlayer ? window.hereIamPlayer.currentMs() : 0;',
    );
    if (result is num) _positionMs = result.toInt();
    return _positionMs;
  }

  @override
  Future<int?> durationMs() async {
    final result = await _execute(
      'window.hereIamPlayer ? window.hereIamPlayer.durationMs() : 0;',
    );
    if (result is num && result.toInt() > 0) _durationMs = result.toInt();
    return _durationMs > 0 ? _durationMs : null;
  }

  @override
  Future<void> seekTo(int positionMs) async {
    final safeMs = positionMs < 0 ? 0 : positionMs;
    await _execute(
      'window.hereIamPlayer && window.hereIamPlayer.seekMs($safeMs);',
    );
    _positionMs = safeMs;
    _timeController.add(PlayerTimeEvent(
      positionMs: _positionMs,
      durationMs: _durationMs > 0 ? _durationMs : null,
      at: DateTime.now(),
    ));
  }

  Future<dynamic> _execute(String script) async {
    if (!_initialized || _controller == null || _lastFailure != null) {
      throw StateError(_lastFailure ?? 'Windows YouTube 播放器尚未就绪');
    }
    return _controller!.executeScript(script);
  }

  static String? extractVideoId(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final raw = value.trim();
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(raw)) return raw;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
      final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
      return _validId(id);
    }
    if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      final watchId = _validId(uri.queryParameters['v']);
      if (watchId != null) return watchId;
      final segments = uri.pathSegments;
      for (final marker in const ['embed', 'shorts', 'live']) {
        final index = segments.indexOf(marker);
        if (index >= 0 && index + 1 < segments.length) {
          final id = _validId(segments[index + 1]);
          if (id != null) return id;
        }
      }
    }
    return null;
  }

  static String? _validId(String? value) =>
      value != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(value)
          ? value
          : null;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _controller?.dispose();
    _controller = null;
    unawaited(_timeController.close());
    final directory = _hostDirectory;
    if (directory != null) {
      unawaited(
        directory.delete(recursive: true).then<void>((_) {}, onError: (_) {}),
      );
    }
  }
}

const String _playerHtml = r'''<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    html,body,#player { width:100%; height:100%; margin:0; background:#000; overflow:hidden; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script src="https://www.youtube.com/iframe_api"></script>
  <script>
    (() => {
      const send = (value) => window.chrome.webview.postMessage(JSON.stringify(value));
      const videoId = new URLSearchParams(location.search).get('v');
      let player = null;
      let timer = null;
      window.onYouTubeIframeAPIReady = () => {
        player = new YT.Player('player', {
          width: '100%', height: '100%', videoId,
          playerVars: { playsinline: 1, modestbranding: 1, rel: 0, origin: location.origin },
          events: {
            onReady: (event) => {
              send({ type: 'ready', duration_ms: Math.round(event.target.getDuration() * 1000) });
              timer = setInterval(() => {
                if (!player || typeof player.getCurrentTime !== 'function') return;
                send({
                  type: 'time',
                  position_ms: Math.round(player.getCurrentTime() * 1000),
                  duration_ms: Math.round(player.getDuration() * 1000)
                });
              }, 200);
            },
            onError: (event) => send({ type: 'error', code: event.data })
          }
        });
      };
      window.hereIamPlayer = {
        play: () => player && player.playVideo(),
        pause: () => player && player.pauseVideo(),
        setMuted: (muted) => player && (muted ? player.mute() : player.unMute()),
        seekMs: (ms) => player && player.seekTo(ms / 1000, true),
        currentMs: () => player ? Math.round(player.getCurrentTime() * 1000) : 0,
        durationMs: () => player ? Math.round(player.getDuration() * 1000) : 0
      };
      window.addEventListener('beforeunload', () => timer && clearInterval(timer));
    })();
  </script>
</body>
</html>''';
