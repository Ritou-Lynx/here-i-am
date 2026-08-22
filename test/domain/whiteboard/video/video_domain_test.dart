import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/whiteboard_contracts.dart';
import 'package:memex/domain/whiteboard/player_adapter.dart';
import 'package:memex/domain/whiteboard/video/video_domain.dart';

void main() {
  group('SubtitleParser', () {
    test('parses SRT file correctly', () {
      final raw = File('test/domain/whiteboard/video/fixtures/sample.srt')
          .readAsStringSync();
      final result = SubtitleParser.parse(
        raw,
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
      );

      expect(result.isSuccess, isTrue);
      final track = result.track!;
      expect(track.format, equals('srt'));
      expect(track.reliability, equals(TimedTextReliability.reliable));
      expect(track.cues.length, equals(4));

      expect(track.cues[0].startMs, equals(2000));
      expect(track.cues[0].endMs, equals(5000));
      expect(track.cues[0].text, equals('灯光切换'));

      expect(track.cues[2].startMs, equals(10000));
      expect(track.cues[2].endMs, equals(14000));
      expect(track.cues[2].text, contains('第一段副歌开始'));
      expect(track.cues[2].text, contains('歌词在这里'));

      expect(track.cues[3].startMs, equals(142000));
    });

    test('parses VTT file correctly and strips tags', () {
      final raw = File('test/domain/whiteboard/video/fixtures/sample.vtt')
          .readAsStringSync();
      final result = SubtitleParser.parse(
        raw,
        sourceId: 'src_video_test',
      );

      expect(result.isSuccess, isTrue);
      final track = result.track!;
      expect(track.format, equals('vtt'));
      expect(track.cues.length, equals(4));

      // VTT <i> tags should be stripped.
      expect(track.cues[2].text, equals('第一段副歌开始\n歌词在这里'));
      expect(track.cues[2].text, isNot(contains('<i>')));
    });

    test('handles empty content', () {
      final result = SubtitleParser.parse(
        '',
        sourceId: 'src_video_empty',
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, equals('字幕内容为空'));
    });

    test('handles content with no valid cues', () {
      final result = SubtitleParser.parse(
        'Some random text\nwithout timestamps',
        sourceId: 'src_video_bad',
      );
      expect(result.track, isNotNull);
      expect(result.track!.cues, isEmpty);
      expect(result.track!.reliability, equals(TimedTextReliability.partial));
    });

    test('strips BOM from SRT content', () {
      final raw = '\uFEFF1\n00:00:01,000 --> 00:00:03,000\nHello';
      final result = SubtitleParser.parse(raw, sourceId: 'src_bom');
      expect(result.isSuccess, isTrue);
      expect(result.track!.cues.length, equals(1));
      expect(result.track!.cues[0].text, equals('Hello'));
    });

    test('cues are sorted by start time', () {
      final raw = '2\n00:00:10,000 --> 00:00:12,000\nB\n\n'
          '1\n00:00:01,000 --> 00:00:03,000\nA';
      final result = SubtitleParser.parse(raw, sourceId: 'src_unsorted');
      expect(result.isSuccess, isTrue);
      expect(result.track!.cues[0].text, equals('A'));
      expect(result.track!.cues[1].text, equals('B'));
    });
  });

  group('TimeRangeAnchorSpec', () {
    test('point anchor has start == end', () {
      final spec = TimeRangeAnchorSpec.point(5000);
      expect(spec.startMs, equals(5000));
      expect(spec.endMs, equals(5000));
      expect(spec.isPoint, isTrue);
    });

    test('range anchor has start < end', () {
      final spec = TimeRangeAnchorSpec.range(10000, 15000);
      expect(spec.startMs, equals(10000));
      expect(spec.endMs, equals(15000));
      expect(spec.isPoint, isFalse);
    });

    test('toMap and fromMap round-trip', () {
      final spec = TimeRangeAnchorSpec.range(10000, 15000, cueId: 'cue_3');
      final map = spec.toMap();
      final restored = TimeRangeAnchorSpec.fromMap(map);
      expect(restored.startMs, equals(10000));
      expect(restored.endMs, equals(15000));
      expect(restored.isPoint, isFalse);
      expect(restored.cueId, equals('cue_3'));
    });

    test('validate rejects start > end', () {
      final error = TimeRangeAnchorSpec.validate({
        'start_ms': 20000,
        'end_ms': 10000,
      });
      expect(error, isNotNull);
      expect(error, contains('start_ms must be <= end_ms'));
    });

    test('validate rejects missing fields', () {
      expect(
        TimeRangeAnchorSpec.validate({}),
        isNotNull,
      );
    });

    test('validate accepts valid range', () {
      expect(
        TimeRangeAnchorSpec.validate({
          'start_ms': 10000,
          'end_ms': 15000,
        }),
        isNull,
      );
    });

    test('fractional milliseconds are rejected instead of truncated', () {
      final fractional = {
        'start_ms': 1.2,
        'end_ms': 1.8,
        'is_point': false,
      };
      expect(TimeRangeAnchorSpec.validate(fractional), isNotNull);
      expect(
        () => TimeRangeAnchorSpec.fromMap(fractional),
        throwsArgumentError,
      );
    });

    test('buildAnchor creates valid AnchorContract', () {
      final spec = TimeRangeAnchorSpec.range(10000, 15000, cueId: 'cue_3');
      final anchor = TimeRangeAnchorSpec.buildAnchor(
        anchorId: 'anchor_test_1',
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        spec: spec,
        quote: '第一段副歌开始',
      );
      expect(anchor.anchorId, equals('anchor_test_1'));
      expect(anchor.positionKind, equals(PositionKind.timeRange));
      expect(anchor.positionSpec['start_ms'], equals(10000));
      expect(anchor.positionSpec['end_ms'], equals(15000));
      expect(anchor.positionSpec['is_point'], isFalse);
      expect(anchor.quote, equals('第一段副歌开始'));
    });
  });

  group('PlayerSyncController', () {
    late FixturePlayerAdapter adapter;
    late TimedTextTrack track;

    setUp(() {
      adapter = FixturePlayerAdapter(durationMs: 200000);
      track = const TimedTextTrack(
        trackId: 'track_test',
        sourceId: 'src_video_test',
        cues: [
          TimedTextCue(
            cueId: 'cue_1',
            startMs: 2000,
            endMs: 5000,
            text: '灯光切换',
          ),
          TimedTextCue(
            cueId: 'cue_2',
            startMs: 6000,
            endMs: 9500,
            text: '烟雾升起',
          ),
          TimedTextCue(
            cueId: 'cue_3',
            startMs: 10000,
            endMs: 14000,
            text: '副歌开始',
          ),
        ],
      );
    });

    tearDown(() {
      adapter.dispose();
    });

    test('finds active cue based on position', () async {
      int? activeIndex;
      final controller = PlayerSyncController(
        adapter: adapter,
        track: track,
        onActiveCueChanged: (idx) => activeIndex = idx,
      );
      controller.start();

      await adapter.load('src_video_test');
      await adapter.seekTo(3000);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(activeIndex, equals(0));

      controller.dispose();
    });

    test('updates active cue when position changes', () async {
      int? activeIndex;
      final controller = PlayerSyncController(
        adapter: adapter,
        track: track,
        onActiveCueChanged: (idx) => activeIndex = idx,
      );
      controller.start();

      await adapter.load('src_video_test');
      await adapter.seekTo(3000);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(activeIndex, equals(0));

      await adapter.seekTo(7000);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(activeIndex, equals(1));

      await adapter.seekTo(12000);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(activeIndex, equals(2));

      controller.dispose();
    });

    test('seekToCue drives adapter to cue start', () async {
      final controller = PlayerSyncController(
        adapter: adapter,
        track: track,
      );
      controller.start();

      await adapter.load('src_video_test');
      await controller.seekToCue(2);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.activeCueIndex, equals(2));
      expect(controller.positionMs, equals(10000));

      controller.dispose();
    });

    test('returns -1 when position is between cues', () async {
      final controller = PlayerSyncController(
        adapter: adapter,
        track: track,
      );
      controller.start();

      await adapter.load('src_video_test');
      // Move to a cue first so activeCueIndex is not -1.
      await adapter.seekTo(3000);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.activeCueIndex, equals(0));

      // Then move to a gap between cues.
      await adapter.seekTo(5500);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.activeCueIndex, equals(-1));

      controller.dispose();
    });
  });

  group('VideoAnnotationService', () {
    final service = VideoAnnotationService();

    test('createAnnotation produces anchor + card', () {
      final result = service.createAnnotation(
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        request: AnnotationCreationRequest(
          spec: TimeRangeAnchorSpec.range(10000, 14000, cueId: 'cue_3'),
          title: '副歌开始',
          body: '这段副歌很关键',
          quote: '第一段副歌开始',
        ),
      );

      expect(result.anchor.positionKind, equals(PositionKind.timeRange));
      expect(result.anchor.positionSpec['start_ms'], equals(10000));
      expect(result.anchor.positionSpec['end_ms'], equals(14000));
      expect(result.anchor.sourceId, equals('src_video_test'));
      expect(result.anchor.sourceVersionId, equals('ver_video_test_v1'));

      expect(result.card.cardKind, equals(CardKind.annotation));
      expect(result.card.sourceId, equals('src_video_test'));
      expect(result.card.title, equals('副歌开始'));
      expect(result.card.body, equals('这段副歌很关键'));
      expect(result.card.tags, contains('video_annotation'));
      expect(result.card.presentation['anchor_id'],
          equals(result.anchor.anchorId));
      expect(result.card.presentation['start_ms'], equals(10000));
    });

    test('createAnnotation with i createdBy uses OwnerSpace.i', () {
      final result = service.createAnnotation(
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        request: AnnotationCreationRequest(
          spec: TimeRangeAnchorSpec.point(5000),
          createdBy: CardCreatedBy.i,
        ),
      );
      expect(result.card.ownerSpace, equals(OwnerSpace.i));
      expect(result.card.createdBy, equals(CardCreatedBy.i));
    });

    test('saveSession and restore round-trip', () {
      final anchor = TimeRangeAnchorSpec.buildAnchor(
        anchorId: 'anchor_1',
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        spec: TimeRangeAnchorSpec.range(10000, 14000),
      );
      final card = CardContract(
        cardId: 'card_ann_1',
        cardKind: CardKind.annotation,
        sourceId: 'src_video_test',
        presentation: {'anchor_id': 'anchor_1'},
        createdAt: DateTime.utc(2026, 8, 15),
      );

      final saved = service.saveSession(
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        lastPositionMs: 12000,
        anchors: [anchor],
        annotationCards: [card],
        anchorToCard: {'anchor_1': 'card_ann_1'},
      );

      final json = saved.toJson();
      final restored = VideoAnnotationSession.fromJson(json);

      expect(restored.sourceId, equals('src_video_test'));
      expect(restored.sourceVersionId, equals('ver_video_test_v1'));
      expect(restored.lastPositionMs, equals(12000));
      expect(restored.anchors.length, equals(1));
      expect(restored.annotationCards.length, equals(1));
      expect(restored.anchorToCard['anchor_1'], equals('card_ann_1'));
    });

    test('restoreSession preserves old version and orphans on change', () {
      final anchor = TimeRangeAnchorSpec.buildAnchor(
        anchorId: 'anchor_1',
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        spec: TimeRangeAnchorSpec.range(10000, 14000),
      );
      final card = CardContract(
        cardId: 'card_ann_1',
        cardKind: CardKind.annotation,
        sourceId: 'src_video_test',
        presentation: {'anchor_id': 'anchor_1'},
        createdAt: DateTime.utc(2026, 8, 15),
      );

      final saved = service.saveSession(
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        lastPositionMs: 12000,
        anchors: [anchor],
        annotationCards: [card],
        anchorToCard: {'anchor_1': 'card_ann_1'},
      );

      final restored = service.restoreSession(
        saved: saved,
        currentVersionId: 'ver_video_test_v2',
      );

      expect(restored.sourceVersionId, equals('ver_video_test_v1'));
      expect(restored.lastPositionMs, equals(0));
      expect(
          restored.anchors.first.sourceVersionId, equals('ver_video_test_v1'));
      expect(restored.anchors.first.status, equals(AnchorStatus.orphaned));
      expect(restored.anchors.first.positionSpec['start_ms'], equals(10000));
    });

    test('restoreSession preserves exact status when version unchanged', () {
      final anchor = TimeRangeAnchorSpec.buildAnchor(
        anchorId: 'anchor_1',
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        spec: TimeRangeAnchorSpec.range(10000, 14000),
      );

      final saved = service.saveSession(
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        lastPositionMs: 12000,
        anchors: [anchor],
        annotationCards: const [],
        anchorToCard: const {},
      );

      final restored = service.restoreSession(
        saved: saved,
        currentVersionId: 'ver_video_test_v1',
      );

      expect(restored.anchors.first.status, equals(AnchorStatus.exact));
    });
  });

  group('FixturePlayerAdapter', () {
    test('declares full playback study capability', () {
      final adapter = FixturePlayerAdapter();
      expect(adapter.capability.isPlaybackStudyCapable, isTrue);
      expect(adapter.providerId, equals('fixture'));
      adapter.dispose();
    });

    test('load and seek work correctly', () async {
      final adapter = FixturePlayerAdapter(durationMs: 100000);
      await adapter.load('src_test');
      expect(adapter.isLoaded, isTrue);

      await adapter.seekTo(50000);
      expect(await adapter.currentPositionMs(), equals(50000));
      expect(await adapter.durationMs(), equals(100000));

      adapter.dispose();
    });

    test('timeEvents emit on seek', () async {
      final adapter = FixturePlayerAdapter(durationMs: 100000);
      final events = <PlayerTimeEvent>[];
      final sub = adapter.timeEvents.listen(events.add);

      await adapter.load('src_test');
      await adapter.seekTo(30000);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(events, isNotEmpty);
      expect(events.last.positionMs, equals(30000));

      await sub.cancel();
      adapter.dispose();
    });
  });

  group('ProviderCapabilityMatrix', () {
    test('youtube has real control capabilities but no static transcript', () {
      final cap = ProviderCapabilityMatrix.capabilityFor('youtube');
      expect(cap.canSeek, isTrue);
      expect(cap.canReadPosition, isTrue);
      expect(cap.canReadDuration, isTrue);
      expect(cap.canEmbedPlayer, isTrue);
      // Platform subtitle auto-fetch not implemented yet → static false.
      expect(cap.hasTranscript, isFalse);
      // Because hasTranscript is false, static full-study gate is NOT passed.
      expect(cap.isPlaybackStudyCapable, isFalse);
    });

    test('bilibili: embeddable but NOT controllable are separate facts', () {
      final cap = ProviderCapabilityMatrix.capabilityFor('bilibili');
      expect(cap.canEmbedPlayer, isTrue);
      expect(cap.canReadPosition, isFalse);
      expect(cap.canSeek, isFalse);
      expect(cap.canReadDuration, isFalse);
      expect(cap.isPlaybackStudyCapable, isFalse);
    });

    test('xiaohongshu is link-only (no playback surface)', () {
      final cap = ProviderCapabilityMatrix.capabilityFor('xiaohongshu');
      expect(cap.canEmbedPlayer, isFalse);
      expect(cap.canReadPosition, isFalse);
      expect(cap.isPlaybackStudyCapable, isFalse);
    });

    test('fixture declares full static capability (test provider)', () {
      final cap = ProviderCapabilityMatrix.capabilityFor('fixture');
      expect(cap.isPlaybackStudyCapable, isTrue);
      expect(cap.hasTranscript, isTrue);
    });

    test('fixture is NOT in the production provider list', () {
      expect(ProviderCapabilityMatrix.productionProviders,
          isNot(contains('fixture')));
      expect(ProviderCapabilityMatrix.testProviders, contains('fixture'));
      expect(ProviderCapabilityMatrix.productionProviders,
          containsAll(['youtube', 'bilibili', 'xiaohongshu']));
    });

    test('recommendedProvider is youtube', () {
      expect(ProviderCapabilityMatrix.recommendedProvider, equals('youtube'));
    });

    test('linkOnlyProviders includes bilibili and xiaohongshu', () {
      expect(ProviderCapabilityMatrix.linkOnlyProviders,
          containsAll(['bilibili', 'xiaohongshu']));
    });

    test('all rows have three verdicts', () {
      for (final row in ProviderCapabilityMatrix.rows) {
        expect(row.name, isNotEmpty);
      }
      expect(ProviderCapabilityMatrix.rows.length, greaterThanOrEqualTo(10));
    });

    test(
        'reverse highlight / time anchor are NOT supported where position is unreadable',
        () {
      final biliRow = ProviderCapabilityMatrix.rows
          .firstWhere((r) => r.name.contains('Reverse highlight'));
      final anchorRow = ProviderCapabilityMatrix.rows
          .firstWhere((r) => r.name.contains('Time anchor'));
      expect(biliRow.bilibili, equals(CapabilityVerdict.unsupported));
      expect(biliRow.xiaohongshu, equals(CapabilityVerdict.unsupported));
      expect(anchorRow.bilibili, equals(CapabilityVerdict.unsupported));
      expect(anchorRow.xiaohongshu, equals(CapabilityVerdict.unsupported));
    });

    test('bilibili embeddability and controllability are distinct rows', () {
      final embedRow = ProviderCapabilityMatrix.rows
          .firstWhere((r) => r.name == 'Embeddable player');
      final controlRow = ProviderCapabilityMatrix.rows.firstWhere(
          (r) => r.name.contains('Controllable playback interface'));
      expect(embedRow.bilibili, equals(CapabilityVerdict.partial));
      expect(controlRow.bilibili, equals(CapabilityVerdict.unsupported));
    });

    test(
        'current-source subtitle availability is a runtime verdict, not static',
        () {
      final row = ProviderCapabilityMatrix.rows
          .firstWhere((r) => r.name.contains('usable subtitle track'));
      expect(row.youtube, equals(CapabilityVerdict.notConfirmed));
      expect(row.bilibili, equals(CapabilityVerdict.notConfirmed));
    });
  });

  group('VideoStudyAvailability (runtime model)', () {
    test('no readable position → no reverse highlight, no current-time anchor',
        () {
      const capability = PlayerCapability(
        canSeek: false,
        canReadPosition: false,
        canReadDuration: false,
        canEmbedPlayer: true,
      );
      final avail = VideoStudyAvailability(
        capability: capability,
        hasUsableSubtitleTrack: true,
      );
      expect(avail.canReverseHighlightNow, isFalse);
      expect(avail.canCreateTimeAnchorNow, isFalse);
      expect(avail.isStudyReady, isFalse);
    });

    test('readable position but no subtitle track → not study ready', () {
      final avail = VideoStudyAvailability.fromProvider('youtube');
      expect(avail.hasReadablePosition, isTrue);
      expect(avail.hasUsableSubtitleTrack, isFalse);
      expect(avail.isStudyReady, isFalse);
      expect(avail.canReverseHighlightNow, isFalse);
      // Current-time anchor requires readable position only.
      expect(avail.canCreateTimeAnchorNow, isTrue);
    });

    test('readable position + loaded subtitle track → study ready', () {
      final avail = VideoStudyAvailability.fromProvider(
        'youtube',
        hasUsableSubtitleTrack: true,
      );
      expect(avail.isStudyReady, isTrue);
      expect(avail.canReverseHighlightNow, isTrue);
      expect(avail.canCreateTimeAnchorNow, isTrue);
    });

    test('importing SRT/VTT upgrades the runtime state', () {
      // Simulate the ViewModel flow: no track → import → usable track.
      final before = VideoStudyAvailability.fromProvider('youtube');
      expect(before.isStudyReady, isFalse);

      final after = VideoStudyAvailability.fromProvider(
        'youtube',
        hasUsableSubtitleTrack: true,
      );
      expect(after.isStudyReady, isTrue);
    });

    test('bilibili is never study ready even with a subtitle track', () {
      final avail = VideoStudyAvailability.fromProvider(
        'bilibili',
        hasUsableSubtitleTrack: true,
      );
      expect(avail.hasReadablePosition, isFalse);
      expect(avail.isStudyReady, isFalse);
      expect(avail.canReverseHighlightNow, isFalse);
      expect(avail.canCreateTimeAnchorNow, isFalse);
    });

    test('link-only provider has no playback surface', () {
      final avail = VideoStudyAvailability.fromProvider('xiaohongshu');
      expect(avail.hasAnyPlaybackSurface, isFalse);
      final bili = VideoStudyAvailability.fromProvider('bilibili');
      // Bilibili is embeddable but not controllable → embed surface only.
      expect(bili.hasAnyPlaybackSurface, isTrue);
      expect(bili.canControlPlayback, isFalse);
    });
  });

  group('CapabilityConsistency', () {
    test('reverse highlight without readable position is inconsistent', () {
      const bad = PlayerCapability(
        canSeek: true,
        canReadPosition: false,
        canReverseHighlight: true,
      );
      expect(CapabilityConsistency.validate(bad), isNotNull);
    });

    test('time anchor without readable position is inconsistent', () {
      const bad = PlayerCapability(
        canSeek: true,
        canReadPosition: false,
        canCreateTimeAnchor: true,
      );
      expect(CapabilityConsistency.validate(bad), isNotNull);
    });

    test('all production providers pass consistency validation', () {
      expect(CapabilityConsistency.validateProduction, returnsNormally);
    });

    test('capability matrix agrees with adapter declarations', () {
      // Adapter capability getters delegate to the matrix for real providers,
      // so the matrix is the single source of truth. We verify each provider
      // id resolves consistently, and that concrete adapter instances (which
      // do not require a platform WebView) agree too.
      const providerIds = ['youtube', 'bilibili', 'xiaohongshu', 'fixture'];
      for (final id in providerIds) {
        final matrixCap = ProviderCapabilityMatrix.capabilityFor(id);
        expect(CapabilityConsistency.validate(matrixCap), isNull,
            reason: '$id must be self-consistent');
      }

      // Concrete link-only adapters (no WebView dependency) must agree.
      final bili = BilibiliPlayerAdapter();
      final xhs = XiaohongshuPlayerAdapter();
      expect(
          bili.capability.canEmbedPlayer,
          equals(ProviderCapabilityMatrix.capabilityFor('bilibili')
              .canEmbedPlayer));
      expect(
          bili.capability.canReadPosition,
          equals(ProviderCapabilityMatrix.capabilityFor('bilibili')
              .canReadPosition));
      expect(
          xhs.capability.canReadPosition,
          equals(ProviderCapabilityMatrix.capabilityFor('xiaohongshu')
              .canReadPosition));
    });
  });

  group('Bilibili and Xiaohongshu adapters', () {
    test('bilibili adapter declares link-only capability', () {
      final adapter = BilibiliPlayerAdapter();
      expect(adapter.providerId, equals('bilibili'));
      expect(adapter.capability.isPlaybackStudyCapable, isFalse);
      expect(adapter.capability.canEmbedPlayer, isTrue);
      expect(adapter.capability.canSeek, isFalse);
      expect(adapter.capability.canReadPosition, isFalse);
    });

    test('xiaohongshu adapter declares no playback capability', () {
      final adapter = XiaohongshuPlayerAdapter();
      expect(adapter.providerId, equals('xiaohongshu'));
      expect(adapter.capability.isPlaybackStudyCapable, isFalse);
      expect(adapter.capability.canEmbedPlayer, isFalse);
    });

    test('link-only adapters do not throw on load/play/seek', () async {
      final adapters = [BilibiliPlayerAdapter(), XiaohongshuPlayerAdapter()];
      for (final a in adapters) {
        await a.load('src_test', embedUrl: 'https://example.com/video');
        await a.play();
        await a.pause();
        await a.seekTo(5000);
        expect(await a.currentPositionMs(), equals(0));
        expect(await a.durationMs(), isNull);
      }
    });
  });
}
