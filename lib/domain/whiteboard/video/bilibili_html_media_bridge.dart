/// Narrow runtime bridge for a standard HTMLMediaElement on a top-level
/// Bilibili video page.
///
/// The bridge only reads/writes `currentTime`, reads `duration`, and observes
/// standard media events. It does not inspect cookies, credentials, network
/// requests, media URLs, DRM state, or Bilibili private player objects.
library;

import 'dart:async';

import '../player_adapter.dart';

typedef BilibiliBridgeScriptExecutor = Future<dynamic> Function(String script);

class BilibiliBridgeSnapshot {
  const BilibiliBridgeSnapshot({
    required this.positionMs,
    required this.durationMs,
  });

  final int positionMs;
  final int durationMs;

  static BilibiliBridgeSnapshot? fromValue(dynamic value) {
    if (value is! Map) return null;
    final position = value['position_ms'];
    final duration = value['duration_ms'];
    if (position is! num || duration is! num) return null;
    final positionMs = position.toInt();
    final durationMs = duration.toInt();
    if (positionMs < 0 || durationMs <= 0 || positionMs > durationMs + 2000) {
      return null;
    }
    return BilibiliBridgeSnapshot(
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }
}

class BilibiliHtmlMediaBridge {
  bool _verified = false;
  int _generation = 0;
  int _positionMs = 0;
  int _durationMs = 0;
  String? _failure;

  bool get isVerified => _verified;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  String? get failure => _failure;
  int get generation => _generation;

  PlayerCapability get capability => _verified
      ? const PlayerCapability(
          canSeek: true,
          canReadDuration: true,
          canReadPosition: true,
          hasTranscript: false,
          canEmbedPlayer: true,
          canReverseHighlight: false,
          canCreateTimeAnchor: true,
        )
      : const PlayerCapability(canEmbedPlayer: true);

  /// Verifies both readback and a no-op seek before exposing time capability.
  void noteCandidate(int generation) {
    if (generation < _generation) return;
    _generation = generation;
    downgrade('正在验证新的视频元素');
  }

  void invalidate(String reason) {
    _generation++;
    downgrade(reason);
  }

  Future<bool> verify(
    BilibiliBridgeScriptExecutor execute, {
    int? generation,
  }) async {
    final expectedGeneration = generation ?? _generation;
    try {
      final first = BilibiliBridgeSnapshot.fromValue(
        await execute(readSnapshotScript),
      );
      if (expectedGeneration != _generation) return false;
      if (first == null) return _reject('未找到可验证的标准视频时间轴');

      final writeAccepted = await execute(seekScript(first.positionMs));
      if (expectedGeneration != _generation) return false;
      if (writeAccepted != true) return _reject('播放器拒绝时间写入验证');

      final second = BilibiliBridgeSnapshot.fromValue(
        await execute(readSnapshotScript),
      );
      if (expectedGeneration != _generation) return false;
      if (second == null ||
          (second.positionMs - first.positionMs).abs() > 2000) {
        return _reject('播放器时间读写验证不一致');
      }
      _positionMs = second.positionMs;
      _durationMs = second.durationMs;
      _failure = null;
      _verified = true;
      return true;
    } catch (error) {
      return _reject('时间桥验证失败：$error');
    }
  }

  BilibiliBridgeSnapshot? acceptEvent(dynamic message) {
    if (!_verified || message is! Map) return null;
    if (message['type'] != 'hereiam:bilibili-media' ||
        message['event'] != 'time') {
      return null;
    }
    final snapshot = BilibiliBridgeSnapshot.fromValue(message);
    if (snapshot == null) return null;
    _positionMs = snapshot.positionMs;
    _durationMs = snapshot.durationMs;
    return snapshot;
  }

  void downgrade(String reason) {
    _verified = false;
    _failure = reason;
  }

  bool _reject(String reason) {
    downgrade(reason);
    return false;
  }

  static const String readSnapshotScript = 'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.read();';

  static String seekScript(int positionMs) =>
      'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.seekMs($positionMs);';

  static const String playScript = 'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.play();';

  static const String pauseScript = 'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.pause();';
}

/// Serializes bridge verification while retaining candidates that arrive
/// during an in-flight read/write handshake (for example after SPA quality
/// switches replace the `<video>` element).
class BilibiliBridgeVerificationCoordinator {
  BilibiliBridgeVerificationCoordinator({
    required this.bridge,
    required this.execute,
    required this.onSettled,
  });

  final BilibiliHtmlMediaBridge bridge;
  final BilibiliBridgeScriptExecutor execute;
  final void Function() onSettled;

  bool _running = false;
  bool _queued = false;
  int _latestGeneration = 0;
  int? _latestPageGeneration;
  Completer<void>? _idleCompleter;

  bool get isRunning => _running;
  int? get latestPageGeneration => _latestPageGeneration;

  void candidate(int? pageGeneration) {
    if (pageGeneration != null &&
        _latestPageGeneration != null &&
        pageGeneration < _latestPageGeneration!) {
      return;
    }
    _latestPageGeneration = pageGeneration;
    _latestGeneration++;
    bridge.noteCandidate(_latestGeneration);
    if (_running) {
      _queued = true;
      return;
    }
    _idleCompleter = Completer<void>();
    unawaited(_drain());
  }

  void invalidate(String reason) {
    _latestGeneration++;
    _latestPageGeneration = null;
    _queued = false;
    bridge.invalidate(reason);
    onSettled();
  }

  Future<void> waitForIdle() => _idleCompleter?.future ?? Future<void>.value();

  Future<void> _drain() async {
    _running = true;
    do {
      _queued = false;
      final generation = _latestGeneration;
      await bridge.verify(execute, generation: generation);
      onSettled();
    } while (_queued);
    _running = false;
    final idle = _idleCompleter;
    if (idle != null && !idle.isCompleted) idle.complete();
  }
}

/// Injected before document parsing. It is inert outside a top-level
/// `www.bilibili.com/video/...` page and only touches a standard `<video>`.
const String bilibiliHtmlMediaBridgeScript = r'''
(() => {
  if (location.hostname !== 'www.bilibili.com' ||
      !location.pathname.startsWith('/video/')) return;
  const send = (event, video, extra = {}) => {
    if (!video || !Number.isFinite(video.duration) || video.duration <= 0) return;
    window.chrome.webview.postMessage(JSON.stringify({
      type: 'hereiam:bilibili-media', event,
      position_ms: Math.max(0, Math.round(video.currentTime * 1000)),
      duration_ms: Math.max(1, Math.round(video.duration * 1000)),
      ...extra
    }));
  };
  const sendCandidate = () => window.chrome.webview.postMessage(JSON.stringify({
    type: 'hereiam:bilibili-media', event: 'candidate', generation
  }));
  const mediaEvents = ['loadedmetadata', 'durationchange', 'timeupdate', 'seeked'];
  let attached = null;
  let generation = 0;
  const onMediaEvent = () => send('time', attached, { generation });
  const detach = () => {
    if (!attached) return;
    for (const event of mediaEvents) attached.removeEventListener(event, onMediaEvent);
    attached = null;
  };
  const attach = () => {
    const video = document.querySelector('video');
    if (!video || video === attached) return false;
    detach();
    attached = video;
    generation += 1;
    for (const event of mediaEvents) video.addEventListener(event, onMediaEvent);
    sendCandidate();
    return true;
  };
  window.__hereIamBilibiliMedia = {
    read: () => {
      attach();
      if (!attached || !Number.isFinite(attached.duration) || attached.duration <= 0) return null;
      return {
        position_ms: Math.max(0, Math.round(attached.currentTime * 1000)),
        duration_ms: Math.max(1, Math.round(attached.duration * 1000))
      };
    },
    seekMs: (ms) => {
      attach();
      if (!attached || !Number.isFinite(ms)) return false;
      attached.currentTime = Math.max(0, Math.min(attached.duration || Infinity, ms / 1000));
      return true;
    },
    play: async () => {
      attach();
      if (!attached) return false;
      try { await attached.play(); return true; } catch (_) { return false; }
    },
    pause: () => { attach(); return attached ? (attached.pause(), true) : false; }
  };
  const observer = new MutationObserver(() => attach());
  observer.observe(document, { childList: true, subtree: true });
  attach();
})();
''';
