/// Windows Bilibili external-player embed hosted inside Edge WebView2.
///
/// This adapter deliberately exposes playback *surface* only. Bilibili's
/// external player does not provide a stable public API for current time,
/// duration or seek, so those capabilities remain false in the shared
/// [PlayerCapability].
library;

import 'dart:io';

import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

class WindowsBilibiliPlayerAdapter implements PlayerAdapter {
  WebviewController? _controller;
  bool _initialized = false;
  bool _disposed = false;
  String? _lastFailure;

  WebviewController? get webviewController => _controller;
  bool get isAvailable => Platform.isWindows && !_disposed;
  String? get lastFailure => _lastFailure;

  @override
  String get providerId => 'bilibili';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor(providerId);

  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();

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
    _lastFailure = null;
    try {
      await _controller!.loadUrl(buildEmbedUrl(bvid));
    } catch (error) {
      _lastFailure = '哔哩哔哩内嵌播放器加载失败：$error';
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
      await controller.initialize();
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setDefaultContextMenusEnabled(false);
      _initialized = true;
    } catch (error) {
      _lastFailure = 'Windows WebView2 初始化失败：$error';
      throw StateError(_lastFailure!);
    }
  }

  static String buildEmbedUrl(String bvid) => Uri.https(
        'player.bilibili.com',
        '/player.html',
        <String, String>{
          'bvid': bvid,
          'autoplay': '0',
          'danmaku': '0',
          'high_quality': '1',
        },
      ).toString();

  static String? extractBvid(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match = RegExp(r'BV[0-9A-Za-z]{10}').firstMatch(value.trim());
    return match?.group(0);
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<int> currentPositionMs() async => 0;

  @override
  Future<int?> durationMs() async => null;

  @override
  Future<void> seekTo(int positionMs) async {}

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller?.dispose();
    _controller = null;
  }
}
