/// Honest Bilibili subtitle capability discovery.
///
/// Bilibili documents its external player, including an initial `t` query
/// parameter, but does not document a stable third-party subtitle discovery
/// API. Here I am therefore does not scrape private endpoints, reuse WebView
/// cookies, or infer that an embedded/login-capable player exposes captions.
/// The result is an explicit unsupported state and the UI keeps SRT/VTT import
/// available. This service exists so Bilibili is classified deliberately
/// instead of being silently skipped as though discovery had succeeded.
library;

import '../player_adapter.dart';

enum BilibiliTimedTextFailureKind {
  invalidVideo,
  unsupported,
  needsAuthorization,
  network,
  parserFailure,
}

class BilibiliTimedTextResult {
  const BilibiliTimedTextResult({this.track, this.error, this.failureKind});

  final TimedTextTrack? track;
  final String? error;
  final BilibiliTimedTextFailureKind? failureKind;

  bool get isSuccess => track != null;
}

/// Reports the currently supportable Bilibili caption path.
///
/// No network request is made because the official external-player
/// documentation does not expose a stable subtitle endpoint. A later
/// authorized provider can replace this service without changing
/// [TimedTextTrack] or [PlayerAdapter].
class BilibiliTimedTextService {
  const BilibiliTimedTextService();

  String? extractBvid(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return RegExp(r'BV[0-9A-Za-z]{10}').firstMatch(value.trim())?.group(0);
  }

  Future<BilibiliTimedTextResult> fetchForVideo(
    String videoIdOrUrl, {
    required String sourceId,
    String? sourceVersionId,
  }) async {
    if (extractBvid(videoIdOrUrl) == null) {
      return const BilibiliTimedTextResult(
        error: '来源无效：无法识别哔哩哔哩 BV 号',
        failureKind: BilibiliTimedTextFailureKind.invalidVideo,
      );
    }
    return const BilibiliTimedTextResult(
      error: '平台未提供稳定公开的字幕发现接口；应用不会读取嵌入页登录态。可导入 SRT / VTT 继续整理字幕。',
      failureKind: BilibiliTimedTextFailureKind.unsupported,
    );
  }

  void dispose() {}
}
