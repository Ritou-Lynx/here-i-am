/// Windows Bilibili top-level video page hosted inside Edge WebView2.
///
/// A narrow bridge probes only a standard HTMLMediaElement. Time capability
/// is promoted at runtime after readback and a no-op seek both succeed; any
/// failure immediately returns the adapter to playable-but-limited mode.
/// No media URL, cookie, credential, DRM state, or private player API is read.
library;

import 'dart:async';
import 'dart:io';

import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../player_adapter.dart';
import 'bilibili_html_media_bridge.dart';

class WindowsBilibiliPlayerAdapter implements PlayerAdapter {
  final StreamController<PlayerTimeEvent> _timeController =
      StreamController<PlayerTimeEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final BilibiliHtmlMediaBridge _bridge = BilibiliHtmlMediaBridge();

  WebviewController? _controller;
  bool _bridgeVerificationRunning = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _showingLoginPage = false;
  String? _currentBvid;
  String? _lastFailure;

  WebviewController? get webviewController => _controller;
  bool get isAvailable => Platform.isWindows && !_disposed;
  bool get hasVerifiedTimeBridge => _bridge.isVerified;
  bool get showingLoginPage => _showingLoginPage;
  String? get lastFailure => _lastFailure ?? _bridge.failure;

  @override
  String get providerId => 'bilibili';

  @override
  PlayerCapability get capability => _bridge.capability;

  @override
  Stream<PlayerTimeEvent> get timeEvents => _timeController.stream;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows 哔哩哔哩播放器只能在 Windows 原生 App 使用');
    }
    final bvid = extractBvid(embedUrl) ?? extractBvid(sourceId);
    if (bvid == null) {
      throw const FormatException('无法从来源链接识别 Bilibili BV 号');
    }
    await _ensureInitialized();
    _currentBvid = bvid;
    _showingLoginPage = false;
    _lastFailure = null;
    _bridge.downgrade('正在探测标准视频时间轴');
    try {
      await _controller!.loadUrl(buildVideoPageUrl(bvid));
    } catch (error) {
      _lastFailure = '哔哩哔哩页面加载失败：$error';
      throw StateError(_lastFailure!);
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null || version.trim().isEmpty) {
        throw StateError('未安装 Microsoft Edge WebView2 Runtime');
      }
      final controller = WebviewController();
      _controller = controller;
      _subscriptions
        ..add(controller.webMessage.listen(_handleMessage))
        ..add(controller.url.listen(_handleUrlChanged));
      await controller.initialize();
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setDefaultContextMenusEnabled(false);
      await controller.addScriptToExecuteOnDocumentCreated(
        bilibiliHtmlMediaBridgeScript,
      );
      _initialized = true;
    } catch (error) {
      _lastFailure = 'Windows WebView2 初始化失败：$error';
      throw StateError(_lastFailure!);
    }
  }

  void _handleUrlChanged(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    final isVideoPage = uri?.host == 'www.bilibili.com' &&
        uri!.path.startsWith('/video/');
    if (!isVideoPage) {
      _bridge.downgrade('当前页面不是可探测的视频页');
      _emitCurrentSnapshot();
    }
  }

  void _handleMessage(dynamic raw) {
    if (raw is! Map || raw['type'] != 'hereiam:bilibili-media') return;
    if (raw['event'] == 'candidate') {
      unawaited(_verifyBridge());
      return;
    }
    final snapshot = _bridge.acceptEvent(raw);
    if (snapshot != null && !_timeController.isClosed) {
      _timeController.add(PlayerTimeEvent(
        positionMs: snapshot.positionMs,
        durationMs: snapshot.durationMs,
        at: DateTime.now(),
      ));
    }
  }

  Future<void> _verifyBridge() async {
    if (_bridgeVerificationRunning || _controller == null) return;
    _bridgeVerificationRunning = true;
    final verified = await _bridge.verify(_controller!.executeScript);
    _bridgeVerificationRunning = false;
    if (verified && !_timeController.isClosed) {
      _emitCurrentSnapshot();
    }
  }

  /// Opens Bilibili's own login page in the plugin's existing default session.
  /// This adapter does not configure a fixed profile or promise persistence.
  Future<void> openLoginPage() async {
    await _ensureInitialized();
    _showingLoginPage = true;
    _bridge.downgrade('登录页不提供视频时间轴');
    await _controller!.loadUrl('https://passport.bilibili.com/login');
  }

  Future<void> returnToVideo() async {
    final bvid = _currentBvid;
    if (bvid == null) throw StateError('尚未加载 Bilibili 视频');
    await load(bvid, embedUrl: buildVideoPageUrl(bvid));
  }

  static String buildVideoPageUrl(String bvid) =>
      Uri.https('www.bilibili.com', '/video/$bvid').toString();

  static String? extractBvid(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match = RegExp(r'BV[0-9A-Za-z]{10}').firstMatch(value.trim());
    return match?.group(0);
  }

  @override
  Future<void> play() async => _executeVerified(
        BilibiliHtmlMediaBridge.playScript,
        action: '播放',
      );

  @override
  Future<void> pause() async => _executeVerified(
        BilibiliHtmlMediaBridge.pauseScript,
        action: '暂停',
      );

  @override
  Future<int> currentPositionMs() async {
    final snapshot = await _readVerifiedSnapshot();
    return snapshot.positionMs;
  }

  @override
  Future<int?> durationMs() async {
    final snapshot = await _readVerifiedSnapshot();
    return snapshot.durationMs;
  }

  @override
  Future<void> seekTo(int positionMs) async {
    final safeMs = positionMs < 0 ? 0 : positionMs;
    final accepted = await _executeVerified(
      BilibiliHtmlMediaBridge.seekScript(safeMs),
      action: '跳转',
    );
    if (accepted != true) {
      _downgradeAndThrow('播放器拒绝跳转');
    }
    final snapshot = await _readVerifiedSnapshot();
    if ((snapshot.positionMs - safeMs).abs() > 2500) {
      _downgradeAndThrow('跳转读写验证不一致');
    }
  }

  Future<BilibiliBridgeSnapshot> _readVerifiedSnapshot() async {
    final value = await _executeVerified(
      BilibiliHtmlMediaBridge.readSnapshotScript,
      action: '读取时间',
    );
    final snapshot = BilibiliBridgeSnapshot.fromValue(value);
    if (snapshot == null) _downgradeAndThrow('播放器时间读取失效');
    return snapshot;
  }

  Future<dynamic> _executeVerified(
    String script, {
    required String action,
  }) async {
    if (!_bridge.isVerified || _controller == null) {
      throw StateError(_bridge.failure ?? '时间研读能力尚未验证');
    }
    try {
      return await _controller!.executeScript(script);
    } catch (error) {
      _downgradeAndThrow('$action失败：$error');
    }
  }

  Never _downgradeAndThrow(String reason) {
    _bridge.downgrade(reason);
    _lastFailure = reason;
    _emitCurrentSnapshot();
    throw StateError(reason);
  }

  void _emitCurrentSnapshot() {
    if (_timeController.isClosed) return;
    _timeController.add(PlayerTimeEvent(
      positionMs: _bridge.positionMs,
      durationMs: _bridge.durationMs > 0 ? _bridge.durationMs : null,
      at: DateTime.now(),
    ));
  }

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
  }
}
