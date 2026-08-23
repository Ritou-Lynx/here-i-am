import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/player_adapter.dart';
import 'package:memex/domain/whiteboard/video/bilibili_safe_http_transport.dart';
import 'package:memex/domain/whiteboard/video/bilibili_timedtext_service.dart';
import 'package:memex/domain/whiteboard/video/platform_timed_text_resolver.dart';
import 'package:memex/domain/whiteboard/video/youtube_timedtext_service.dart';

class _UnusedTransport implements BilibiliHttpTransport {
  @override
  Future<BilibiliHttpFetchResult> getText(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async =>
      const BilibiliHttpFetchResult(
        failureKind: BilibiliHttpFailureKind.network,
      );

  @override
  void dispose() {}
}

class _BilibiliService extends BilibiliTimedTextService {
  _BilibiliService(this.result) : super(transport: _UnusedTransport());

  final BilibiliTimedTextResult result;

  @override
  Future<BilibiliTimedTextResult> fetchForVideo(
    String videoIdOrUrl, {
    required String sourceId,
    String? sourceVersionId,
  }) async =>
      result;
}

class _Probe implements BilibiliSameOriginSubtitleProbe {
  _Probe(this.result);
  final BilibiliSameOriginProbeResult result;

  @override
  Future<BilibiliSameOriginProbeResult> probe(String bvid) async => result;
}

class _ThrowingProbe implements BilibiliSameOriginSubtitleProbe {
  const _ThrowingProbe();

  @override
  Future<BilibiliSameOriginProbeResult> probe(String bvid) async =>
      throw StateError('offline');
}

class _YouTubeService extends YouTubeTimedTextService {
  _YouTubeService(this.result);
  final YouTubeTimedTextResult result;

  @override
  Future<YouTubeTimedTextResult> fetchForVideo(
    String videoIdOrUrl, {
    required String sourceId,
    String? sourceVersionId,
  }) async =>
      result;
}

const _request = PlatformTimedTextRequest(
  providerId: 'bilibili',
  videoRef: 'https://www.bilibili.com/video/BV1E8KV6QEu7',
  sourceId: 'src_bili',
  sourceVersionId: 'ver_bili_v1',
);

void main() {
  group('Bilibili public/same-origin resolver', () {
    test('maps the anonymous transport result into the unified contract',
        () async {
      final resolver = UnifiedPlatformTimedTextResolver(
        youtube: _YouTubeService(const YouTubeTimedTextResult()),
        bilibili: BilibiliPublicTimedTextResolver(
          service: _BilibiliService(const BilibiliTimedTextResult(
            track: TimedTextTrack(
              trackId: 'bili_BV1E8KV6QEu7_zh-CN',
              sourceId: 'src_bili',
              sourceKind: TimedTextSourceKind.platform,
              language: 'zh-CN',
              format: 'bcc-json',
              cues: [
                TimedTextCue(
                  cueId: 'cue_1',
                  startMs: 0,
                  endMs: 1000,
                  text: '真实字幕',
                ),
              ],
            ),
          )),
        ),
      );

      final result = await resolver.resolve(_request);

      expect(result.isSuccess, isTrue);
      expect(result.track!.format, 'bcc-json');
      expect(result.track!.cues.single.text, '真实字幕');
    });

    test('maps anonymous login-only visibility to accessRestricted', () async {
      final resolver = BilibiliPublicTimedTextResolver(
        service: _BilibiliService(const BilibiliTimedTextResult(
          error: '匿名不可见',
          failureKind: BilibiliTimedTextFailureKind.needsAuthorization,
        )),
      );

      final result = await resolver.resolve(_request);

      expect(result.failureKind, PlatformTimedTextFailureKind.accessRestricted);
      expect(result.message, '匿名不可见');
    });

    test('maps response size rejection to parserFailure', () async {
      final resolver = BilibiliPublicTimedTextResolver(
        service: _BilibiliService(const BilibiliTimedTextResult(
          error: '响应过大',
          failureKind: BilibiliTimedTextFailureKind.responseTooLarge,
        )),
      );

      final result = await resolver.resolve(_request);

      expect(result.failureKind, PlatformTimedTextFailureKind.parserFailure);
      expect(result.message, '响应过大');
    });

    test('parses an ephemeral SRT fixture into a platform track', () async {
      final resolver = BilibiliPublicTimedTextResolver(
        probe: _Probe(
          const BilibiliSameOriginProbeResult(
            subtitleText: '1\n00:00:01,000 --> 00:00:02,500\n第一句\n\n'
                '2\n00:00:03,000 --> 00:00:04,000\n第二句',
            language: 'zh-CN',
          ),
        ),
      );

      final result = await resolver.resolve(_request);
      expect(result.isSuccess, isTrue);
      expect(result.track!.sourceId, 'src_bili');
      expect(result.track!.sourceVersionId, 'ver_bili_v1');
      expect(result.track!.sourceKind.name, 'platform');
      expect(result.track!.cues, hasLength(2));
    });

    test('keeps access restriction distinct from no track', () async {
      final restricted = BilibiliPublicTimedTextResolver(
        probe: _Probe(
          const BilibiliSameOriginProbeResult(
            failureKind: PlatformTimedTextFailureKind.accessRestricted,
            message: '该字幕需要平台权限',
          ),
        ),
      );
      final noTrack = BilibiliPublicTimedTextResolver(
        probe: _Probe(const BilibiliSameOriginProbeResult()),
      );

      expect(
        (await restricted.resolve(_request)).failureKind,
        PlatformTimedTextFailureKind.accessRestricted,
      );
      expect(
        (await noTrack.resolve(_request)).failureKind,
        PlatformTimedTextFailureKind.noTrack,
      );
    });

    test('classifies transport and parser failures precisely', () async {
      final network = await BilibiliPublicTimedTextResolver(
        probe: const _ThrowingProbe(),
      ).resolve(_request);
      final parser = await BilibiliPublicTimedTextResolver(
        probe: _Probe(
          const BilibiliSameOriginProbeResult(subtitleText: 'not timed text'),
        ),
      ).resolve(_request);

      expect(network.failureKind, PlatformTimedTextFailureKind.network);
      expect(parser.failureKind, PlatformTimedTextFailureKind.parserFailure);
    });

    test(
      'default probe is honest and keeps SRT/VTT fallback visible',
      () async {
        final result = await BilibiliPublicTimedTextResolver(
          probe: const DisabledBilibiliSameOriginSubtitleProbe(),
        ).resolve(_request);
        expect(result.failureKind, PlatformTimedTextFailureKind.unsupported);
        expect(result.message, contains('SRT / VTT'));
      },
    );
  });

  test('unified resolver preserves YouTube failure classification', () async {
    final resolver = UnifiedPlatformTimedTextResolver(
      youtube: _YouTubeService(
        const YouTubeTimedTextResult(
          failureKind: YouTubeTimedTextFailureKind.accessRestricted,
          error: '地区限制',
        ),
      ),
    );
    final result = await resolver.resolve(
      const PlatformTimedTextRequest(
        providerId: 'youtube',
        videoRef: 'https://youtu.be/dQw4w9WgXcQ',
        sourceId: 'src_yt',
      ),
    );

    expect(result.failureKind, PlatformTimedTextFailureKind.accessRestricted);
    expect(result.message, '地区限制');
  });
}
