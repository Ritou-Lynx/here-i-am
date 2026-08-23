/// Provider-neutral platform subtitle resolution.
///
/// YouTube keeps its existing public watch-page/caption-track path.
/// Bilibili accepts only subtitle text returned by an explicitly injected
/// public or same-origin probe. The probe contract never exposes cookies or a
/// signed track URL to Dart, so neither can be persisted by this resolver.
library;

import '../player_adapter.dart';
import 'bilibili_timedtext_service.dart';
import 'subtitle_parser.dart';
import 'youtube_timedtext_service.dart';

enum PlatformTimedTextFailureKind {
  invalidSource,
  noTrack,
  accessRestricted,
  network,
  parserFailure,
  unsupported,
}

class PlatformTimedTextRequest {
  const PlatformTimedTextRequest({
    required this.providerId,
    required this.videoRef,
    required this.sourceId,
    this.sourceVersionId,
  });

  final String providerId;
  final String videoRef;
  final String sourceId;
  final String? sourceVersionId;
}

class PlatformTimedTextResolution {
  const PlatformTimedTextResolution({
    this.track,
    this.failureKind,
    this.message,
    this.youtubeTracks = const [],
    this.selectedYouTubeTrack,
  });

  final TimedTextTrack? track;
  final PlatformTimedTextFailureKind? failureKind;
  final String? message;
  final List<YouTubeCaptionTrack> youtubeTracks;
  final YouTubeCaptionTrack? selectedYouTubeTrack;

  bool get isSuccess => track != null;
}

abstract class PlatformTimedTextResolver {
  Future<PlatformTimedTextResolution> resolve(PlatformTimedTextRequest request);
}

class BilibiliSameOriginProbeResult {
  const BilibiliSameOriginProbeResult({
    this.subtitleText,
    this.language = 'zh',
    this.failureKind,
    this.message,
  });

  /// Ephemeral subtitle text only. A signed URL is intentionally absent.
  final String? subtitleText;
  final String language;
  final PlatformTimedTextFailureKind? failureKind;
  final String? message;
}

abstract class BilibiliSameOriginSubtitleProbe {
  Future<BilibiliSameOriginProbeResult> probe(String bvid);
}

class DisabledBilibiliSameOriginSubtitleProbe
    implements BilibiliSameOriginSubtitleProbe {
  const DisabledBilibiliSameOriginSubtitleProbe();

  @override
  Future<BilibiliSameOriginProbeResult> probe(String bvid) async =>
      const BilibiliSameOriginProbeResult(
        failureKind: PlatformTimedTextFailureKind.unsupported,
        message: '尚未连接经验证的公开 / 同源字幕探测器；可导入 SRT / VTT。',
      );
}

class BilibiliPublicTimedTextResolver implements PlatformTimedTextResolver {
  BilibiliPublicTimedTextResolver({
    BilibiliSameOriginSubtitleProbe? probe,
    BilibiliTimedTextService? service,
  }) : assert(probe == null || service == null),
       probe = probe,
       _service =
           service ?? (probe == null ? BilibiliTimedTextService() : null),
       _ownsService = service == null && probe == null;

  /// Compatibility seam for same-origin/test providers. Production defaults
  /// to the anonymous HTTP service and never reads the player WebView session.
  final BilibiliSameOriginSubtitleProbe? probe;
  final BilibiliTimedTextService? _service;
  final bool _ownsService;

  static String? extractBvid(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return RegExp(r'BV[0-9A-Za-z]{10}').firstMatch(value)?.group(0);
  }

  @override
  Future<PlatformTimedTextResolution> resolve(
    PlatformTimedTextRequest request,
  ) async {
    final bvid = extractBvid(request.videoRef);
    if (bvid == null) {
      return const PlatformTimedTextResolution(
        failureKind: PlatformTimedTextFailureKind.invalidSource,
        message: '来源无效：无法识别 Bilibili BV 号',
      );
    }

    final service = _service;
    if (service != null) {
      final result = await service.fetchForVideo(
        request.videoRef,
        sourceId: request.sourceId,
        sourceVersionId: request.sourceVersionId,
      );
      return PlatformTimedTextResolution(
        track: result.track,
        failureKind: _mapBilibiliFailure(result.failureKind),
        message: result.error,
      );
    }

    BilibiliSameOriginProbeResult result;
    try {
      result = await probe!.probe(bvid);
    } catch (error) {
      return PlatformTimedTextResolution(
        failureKind: PlatformTimedTextFailureKind.network,
        message: 'Bilibili 字幕探测失败：$error',
      );
    }
    final raw = result.subtitleText;
    if (raw == null || raw.trim().isEmpty) {
      return PlatformTimedTextResolution(
        failureKind: result.failureKind ?? PlatformTimedTextFailureKind.noTrack,
        message: result.message ?? '当前视频未发现公开字幕轨',
      );
    }

    final parsed = SubtitleParser.parse(
      raw,
      sourceId: request.sourceId,
      sourceVersionId: request.sourceVersionId,
      language: result.language,
      sourceKind: TimedTextSourceKind.platform,
    );
    if (!parsed.isSuccess || parsed.track == null) {
      return PlatformTimedTextResolution(
        failureKind: PlatformTimedTextFailureKind.parserFailure,
        message: parsed.error ?? 'Bilibili 字幕解析器失效',
      );
    }
    return PlatformTimedTextResolution(track: parsed.track);
  }

  static PlatformTimedTextFailureKind? _mapBilibiliFailure(
    BilibiliTimedTextFailureKind? kind,
  ) => switch (kind) {
    BilibiliTimedTextFailureKind.invalidVideo =>
      PlatformTimedTextFailureKind.invalidSource,
    BilibiliTimedTextFailureKind.noTrack =>
      PlatformTimedTextFailureKind.noTrack,
    BilibiliTimedTextFailureKind.needsAuthorization =>
      PlatformTimedTextFailureKind.accessRestricted,
    BilibiliTimedTextFailureKind.network =>
      PlatformTimedTextFailureKind.network,
    BilibiliTimedTextFailureKind.parserFailure =>
      PlatformTimedTextFailureKind.parserFailure,
    null => null,
  };

  void dispose() {
    if (_ownsService) _service?.dispose();
  }
}

class YouTubePublicTimedTextResolver implements PlatformTimedTextResolver {
  YouTubePublicTimedTextResolver(this.service);

  final YouTubeTimedTextService service;

  @override
  Future<PlatformTimedTextResolution> resolve(
    PlatformTimedTextRequest request,
  ) async {
    final result = await service.fetchForVideo(
      request.videoRef,
      sourceId: request.sourceId,
      sourceVersionId: request.sourceVersionId,
    );
    return PlatformTimedTextResolution(
      track: result.track,
      failureKind: _mapYouTubeFailure(result.failureKind),
      message: result.error,
      youtubeTracks: result.availableTracks,
      selectedYouTubeTrack: result.selectedTrack,
    );
  }

  static PlatformTimedTextFailureKind? _mapYouTubeFailure(
    YouTubeTimedTextFailureKind? kind,
  ) =>
      switch (kind) {
        YouTubeTimedTextFailureKind.invalidVideo =>
          PlatformTimedTextFailureKind.invalidSource,
        YouTubeTimedTextFailureKind.noTrack =>
          PlatformTimedTextFailureKind.noTrack,
        YouTubeTimedTextFailureKind.accessRestricted =>
          PlatformTimedTextFailureKind.accessRestricted,
        YouTubeTimedTextFailureKind.network =>
          PlatformTimedTextFailureKind.network,
        YouTubeTimedTextFailureKind.parserFailure =>
          PlatformTimedTextFailureKind.parserFailure,
        null => null,
      };
}

class UnifiedPlatformTimedTextResolver implements PlatformTimedTextResolver {
  UnifiedPlatformTimedTextResolver({
    required YouTubeTimedTextService youtube,
    BilibiliPublicTimedTextResolver? bilibili,
  }) : _youtube = YouTubePublicTimedTextResolver(youtube),
       _bilibili = bilibili ?? BilibiliPublicTimedTextResolver();

  final YouTubePublicTimedTextResolver _youtube;
  final BilibiliPublicTimedTextResolver _bilibili;

  @override
  Future<PlatformTimedTextResolution> resolve(
    PlatformTimedTextRequest request,
  ) =>
      switch (request.providerId.trim().toLowerCase()) {
        'youtube' => _youtube.resolve(request),
        'bilibili' => _bilibili.resolve(request),
        _ => Future.value(const PlatformTimedTextResolution(
            failureKind: PlatformTimedTextFailureKind.unsupported,
            message: '当前平台没有字幕 resolver；可导入 SRT / VTT。',
          )),
      };

  void dispose() => _bilibili.dispose();
}
