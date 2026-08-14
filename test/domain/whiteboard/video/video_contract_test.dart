import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/whiteboard_contracts.dart';
import 'package:memex/domain/whiteboard/video/video_domain.dart';

/// Cross-boundary contract test for the W4 video study closed loop.
///
/// This is the W4 integration test that crosses multiple shared contracts:
/// `PlayerAdapter` (fixture) → `TimedTextTrack` (subtitle parse) →
/// `PlayerSyncController` (bidirectional sync) → `AnchorContract` +
/// `CardContract` (annotation creation) → `VideoAnnotationSession`
/// (serialization) → restore with re-anchoring.
///
/// It mirrors the real workflow: load → play → reverse highlight →
/// cue click seek → create annotation → save session → restart → restore →
/// re-locate.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('w4_contract_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('full closed loop: playback → sync → anchor → save → restore',
      () async {
    // ── 1. Fixture player (real-time simulation of an online player)
    final adapter = FixturePlayerAdapter(durationMs: 36000);

    // ── 2. Subtitle parse → TimedTextTrack (user imported SRT)
    final srt = '''
1
00:00:02,000 --> 00:00:05,000
灯光切换，夜场开始

2
00:00:06,000 --> 00:00:09,500
舞台中央升起烟雾

3
00:00:10,000 --> 00:00:14,000
第一段副歌开始
''';
    final parseResult = SubtitleParser.parse(
      srt,
      sourceId: 'src_concert',
      sourceVersionId: 'ver_concert_v1',
      sourceKind: TimedTextSourceKind.userImport,
    );
    expect(parseResult.isSuccess, isTrue);
    final track = parseResult.track!;
    expect(track.cues.length, equals(3));
    expect(track.reliability, equals(TimedTextReliability.reliable));

    // ── 3. Load player and start sync controller
    await adapter.load('src_concert');
    final activeCueEvents = <int>[];
    final controller = PlayerSyncController(
      adapter: adapter,
      track: track,
      onActiveCueChanged: (idx) => activeCueEvents.add(idx),
    );
    controller.start();

    // ── 4. Reverse highlight: playback position → active cue
    await adapter.seekTo(3000);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(controller.activeCueIndex, equals(0));

    await adapter.seekTo(12000);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(controller.activeCueIndex, equals(2));

    // ── 5. Cue click → seek player
    await controller.seekToCue(1);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(controller.positionMs, equals(6000));
    expect(controller.activeCueIndex, equals(1));

    // ── 6. Create time range anchor + annotation card
    final service = VideoAnnotationService();
    final anchorResult = service.createAnnotation(
      sourceId: 'src_concert',
      sourceVersionId: 'ver_concert_v1',
      request: AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec.range(10000, 14000, cueId: 'cue_2'),
        title: '副歌段落',
        body: '这里值得再看一遍',
      ),
    );

    // Anchor is a shared contract type bound to source + version
    expect(anchorResult.anchor.anchorId, isNotEmpty);
    expect(anchorResult.anchor.sourceId, equals('src_concert'));
    expect(anchorResult.anchor.sourceVersionId, equals('ver_concert_v1'));
    expect(anchorResult.anchor.positionKind, equals(PositionKind.timeRange));
    expect(anchorResult.anchor.positionSpec['start_ms'], equals(10000));
    expect(anchorResult.anchor.positionSpec['end_ms'], equals(14000));

    // Card is a shared contract type (annotation kind, no board coords)
    expect(anchorResult.card.cardId, isNotEmpty);
    expect(anchorResult.card.cardKind, equals(CardKind.annotation));
    expect(anchorResult.card.sourceId, equals('src_concert'));
    expect(anchorResult.card.title, equals('副歌段落'));
    expect(anchorResult.card.presentation['anchor_id'],
        equals(anchorResult.anchor.anchorId));

    // ── 7. Save session to disk (restart recovery)
    final session = service.saveSession(
      sourceId: 'src_concert',
      sourceVersionId: 'ver_concert_v1',
      lastPositionMs: controller.positionMs,
      anchors: [anchorResult.anchor],
      annotationCards: [anchorResult.card],
      anchorToCard: {
        anchorResult.anchor.anchorId: anchorResult.card.cardId,
      },
    );
    final sessionPath =
        '${tempDir.path}${Platform.pathSeparator}session.json';
    await File(sessionPath)
        .writeAsString(jsonEncode(session.toJson()));

    controller.dispose();
    adapter.dispose();

    // ── 8. "Restart" — create fresh adapter + fresh controller
    final restartedAdapter = FixturePlayerAdapter(durationMs: 36000);
    final restartedController = PlayerSyncController(
      adapter: restartedAdapter,
      track: track,
    );
    restartedController.start();
    await restartedAdapter.load('src_concert');

    // ── 9. Restore session from disk
    final restoredJson =
        jsonDecode(await File(sessionPath).readAsString())
            as Map<String, dynamic>;
    final restoredSession = VideoAnnotationSession.fromJson(restoredJson);
    expect(restoredSession.sourceVersionId, equals('ver_concert_v1'));
    expect(restoredSession.lastPositionMs, equals(6000));
    expect(restoredSession.anchors.length, equals(1));
    expect(restoredSession.annotationCards.length, equals(1));
    expect(restoredSession.anchorToCard[anchorResult.anchor.anchorId],
        equals(anchorResult.card.cardId));

    // ── 10. Re-locate: seek to the restored position
    await restartedController.seekToPosition(restoredSession.lastPositionMs);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(restartedController.positionMs, equals(6000));
    expect(restartedController.activeCueIndex, equals(1));

    // ── 11. Version change → anchors re-anchor (not orphaned, not lost)
    final reanchored = service.restoreSession(
      saved: restoredSession,
      currentVersionId: 'ver_concert_v2',
    );
    expect(reanchored.sourceVersionId, equals('ver_concert_v2'));
    expect(reanchored.anchors.first.status, equals(AnchorStatus.reanchored));
    expect(reanchored.anchors.first.positionSpec['start_ms'], equals(10000),
        reason: 'time positions survive version change');

    restartedController.dispose();
    restartedAdapter.dispose();
  });

  test('capability contract: UI must respect adapter declarations', () {
    // The UI reads capability — it never pretends a provider supports
    // what it cannot. This test locks the contract.
    final yt = ProviderCapabilityMatrix.capabilityFor('youtube');
    expect(yt.isPlaybackStudyCapable, isTrue);

    final bili = ProviderCapabilityMatrix.capabilityFor('bilibili');
    expect(bili.isPlaybackStudyCapable, isFalse);
    expect(bili.canSeek, isFalse);

    final xhs = ProviderCapabilityMatrix.capabilityFor('xiaohongshu');
    expect(xhs.isPlaybackStudyCapable, isFalse);
    expect(xhs.canEmbedPlayer, isFalse);
  });
}