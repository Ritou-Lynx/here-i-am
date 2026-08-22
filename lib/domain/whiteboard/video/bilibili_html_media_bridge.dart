/// Narrow runtime bridge for a standard HTMLMediaElement on a top-level
/// Bilibili video page.
///
/// The bridge only reads/writes `currentTime`, reads `duration`, and observes
/// standard media events. It does not inspect cookies, credentials, network
/// requests, media URLs, DRM state, or Bilibili private player objects.
library;

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
  int _positionMs = 0;
  int _durationMs = 0;
  String? _failure;

  bool get isVerified => _verified;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  String? get failure => _failure;

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
  Future<bool> verify(BilibiliBridgeScriptExecutor execute) async {
    try {
      final first = BilibiliBridgeSnapshot.fromValue(
        await execute(readSnapshotScript),
      );
      if (first == null) return _reject('未找到可验证的标准视频时间轴');

      final writeAccepted = await execute(seekScript(first.positionMs));
      if (writeAccepted != true) return _reject('播放器拒绝时间写入验证');

      final second = BilibiliBridgeSnapshot.fromValue(
        await execute(readSnapshotScript),
      );
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

  static const String readSnapshotScript =
      'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.read();';

  static String seekScript(int positionMs) =>
      'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.seekMs($positionMs);';

  static const String playScript =
      'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.play();';

  static const String pauseScript =
      'window.__hereIamBilibiliMedia && '
      'window.__hereIamBilibiliMedia.pause();';
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
  let attached = null;
  const attach = () => {
    const video = document.querySelector('video');
    if (!video || video === attached) return false;
    attached = video;
    for (const event of ['loadedmetadata', 'durationchange', 'timeupdate', 'seeked']) {
      video.addEventListener(event, () => send('time', video));
    }
    send('candidate', video);
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
    play: () => { attach(); return attached ? (attached.play(), true) : false; },
    pause: () => { attach(); return attached ? (attached.pause(), true) : false; }
  };
  const timer = setInterval(() => attach() && clearInterval(timer), 250);
  setTimeout(() => clearInterval(timer), 15000);
})();
''';
