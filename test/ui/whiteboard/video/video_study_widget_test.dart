import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/repository_video_annotation_store.dart';
import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory_stub.dart';
import 'package:memex/ui/whiteboard/video/session_store.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';
import 'package:memex/ui/whiteboard/video/view_models/video_study_view_model.dart';
import 'package:memex/ui/whiteboard/video/widgets/annotation_editor.dart';
import 'package:memex/ui/whiteboard/video/widgets/subtitle_list_view.dart';

/// Builds a FixturePlayerAdapter + track for widget testing.
FixturePlayerAdapter _buildFixture() {
  return FixturePlayerAdapter(durationMs: 200000);
}

TimedTextTrack _buildTrack() {
  return const TimedTextTrack(
    trackId: 'track_test',
    sourceId: 'src_video_test',
    sourceVersionId: 'ver_video_test_v1',
    sourceKind: TimedTextSourceKind.userImport,
    language: 'zh',
    reliability: TimedTextReliability.reliable,
    cues: [
      TimedTextCue(cueId: 'cue_1', startMs: 2000, endMs: 5000, text: '灯光切换'),
      TimedTextCue(cueId: 'cue_2', startMs: 6000, endMs: 9500, text: '烟雾升起'),
      TimedTextCue(cueId: 'cue_3', startMs: 10000, endMs: 14000, text: '副歌开始'),
    ],
  );
}

VideoAnnotationSession _sessionWithVideoNotes() {
  final createdAt = DateTime.utc(2026, 8, 23, 9);
  final specs = List<TimeRangeAnchorSpec>.generate(
    12,
    (index) => index == 1
        ? TimeRangeAnchorSpec.range(6000, 9500)
        : TimeRangeAnchorSpec.point(2000 + index * 4000),
  );
  final anchors = <AnchorContract>[];
  final cards = <CardContract>[];
  final bindings = <String, String>{};
  for (var index = 0; index < specs.length; index++) {
    final anchor = TimeRangeAnchorSpec.buildAnchor(
      anchorId: 'anchor_note_$index',
      sourceId: 'src_video_test',
      sourceVersionId: 'ver_video_test_v1',
      spec: specs[index],
      createdAt: createdAt.add(Duration(minutes: index)),
    );
    final card = CardContract(
      cardId: 'card_note_$index',
      cardKind: CardKind.annotation,
      sourceId: 'src_video_test',
      title: '视频笔记 ${index + 1}',
      body: '第 ${index + 1} 条笔记摘要，用于验证窄右栏纵向排列。',
      createdAt: createdAt.add(Duration(minutes: index)),
    );
    anchors.add(anchor);
    cards.add(card);
    bindings[anchor.anchorId] = card.cardId;
  }
  return VideoAnnotationSession(
    sourceId: 'src_video_test',
    sourceVersionId: 'ver_video_test_v1',
    lastPositionMs: 0,
    anchors: anchors,
    annotationCards: cards,
    anchorToCard: bindings,
    dockOrientation: 'right',
    dockRatio: 0.35,
    savedAt: createdAt,
  );
}

/// Fake timedtext service with a scripted result (no network in tests).
class _FakeTimedTextService extends YouTubeTimedTextService {
  final YouTubeTimedTextResult result;
  int calls = 0;

  _FakeTimedTextService(this.result);

  @override
  Future<YouTubeTimedTextResult> fetchForVideo(
    String videoIdOrUrl, {
    required String sourceId,
    String? sourceVersionId,
  }) async {
    calls++;
    return result;
  }
}

class _RecordingSessionStore implements VideoSessionStore {
  _RecordingSessionStore({this.restored});

  VideoAnnotationSession? restored;
  VideoAnnotationSession? saved;

  @override
  Future<void> clear() async {
    restored = null;
    saved = null;
  }

  @override
  Future<VideoAnnotationSession?> load() async => restored;

  @override
  Future<void> save(VideoAnnotationSession session) async {
    saved = session;
    restored = session;
  }
}

class _ThrowingAnnotationStore implements VideoAnnotationStore {
  const _ThrowingAnnotationStore();

  @override
  Future<VideoAnnotationResult> createAnnotation({
    required String sourceId,
    required String sourceVersionId,
    required AnnotationCreationRequest request,
  }) {
    throw StateError('annotation-store-secret-token');
  }

  @override
  Future<List<VideoAnnotationResult>> listAnnotations({
    required String sourceId,
    required String currentVersionId,
    int? currentDurationMs,
  }) async =>
      const [];

  @override
  Future<CardContract> updateAnnotationCard({
    required String cardId,
    required String title,
    required String body,
  }) {
    throw StateError('annotation-store-secret-token');
  }
}

class _ThrowingSessionStore implements VideoSessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<VideoAnnotationSession?> load() async {
    throw StateError('session-secret-token=do-not-render');
  }

  @override
  Future<void> save(VideoAnnotationSession session) async {
    throw StateError('session-save-secret-token=do-not-render');
  }
}

class _LinkOnlyAdapter implements PlayerAdapter {
  _LinkOnlyAdapter(this.providerId);

  @override
  final String providerId;

  @override
  PlayerCapability get capability => const PlayerCapability();

  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();

  @override
  Future<int> currentPositionMs() async => 0;

  @override
  Future<int?> durationMs() async => null;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seekTo(int positionMs) async {}
}

/// Player whose authoritative current position changes but whose event stream
/// stays silent. This reproduces native-player event lag: range boundaries
/// must be captured by reading the adapter, not from a stale UI cache.
class _SilentTimeEventAdapter implements PlayerAdapter {
  int _positionMs = 0;

  @override
  String get providerId => 'fixture';

  @override
  PlayerCapability get capability => const PlayerCapability(
        canSeek: true,
        canReadDuration: true,
        canReadPosition: true,
        canEmbedPlayer: true,
        canCreateTimeAnchor: true,
      );

  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();

  @override
  Future<int> currentPositionMs() async => _positionMs;

  @override
  Future<int?> durationMs() async => 200000;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seekTo(int positionMs) async {
    _positionMs = positionMs;
  }
}

class _DelayedPauseAdapter implements PlayerAdapter {
  final _events = StreamController<PlayerTimeEvent>.broadcast();
  Completer<void>? pauseCompleter;
  int positionMs = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  bool playing = false;

  @override
  String get providerId => 'delayed-pause';

  @override
  PlayerCapability get capability => const PlayerCapability(
        canSeek: true,
        canReadDuration: true,
        canReadPosition: true,
        canEmbedPlayer: true,
        canCreateTimeAnchor: true,
      );

  @override
  Stream<PlayerTimeEvent> get timeEvents => _events.stream;

  @override
  Future<int> currentPositionMs() async => positionMs;

  @override
  Future<int?> durationMs() async => 200000;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    emit(positionMs);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    final delayed = pauseCompleter;
    if (delayed != null) await delayed.future;
    playing = false;
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
  }

  @override
  Future<void> seekTo(int positionMs) async {
    this.positionMs = positionMs;
    emit(positionMs);
  }

  void emit(int ms) {
    positionMs = ms;
    _events.add(PlayerTimeEvent(
      positionMs: ms,
      durationMs: 200000,
      at: DateTime.now(),
    ));
  }

  void dispose() => _events.close();
}

class _CountingSessionStore extends _RecordingSessionStore {
  int loadCalls = 0;

  @override
  Future<VideoAnnotationSession?> load() async {
    loadCalls++;
    return super.load();
  }
}

class _DelayedLoadAdapter extends _LinkOnlyAdapter {
  _DelayedLoadAdapter(super.providerId);

  final loadCompleter = Completer<void>();

  @override
  Future<void> load(String sourceId, {String? embedUrl}) =>
      loadCompleter.future;

  void dispose() {}
}

class _DelayedBiliProbe implements BilibiliSameOriginSubtitleProbe {
  final completer = Completer<BilibiliSameOriginProbeResult>();

  @override
  Future<BilibiliSameOriginProbeResult> probe(String bvid) => completer.future;
}

class _RuntimeNegotiatedAdapter implements PlayerAdapter {
  final _events = StreamController<PlayerTimeEvent>.broadcast();
  PlayerCapability _capability = const PlayerCapability(canEmbedPlayer: true);

  @override
  String get providerId => 'runtime-negotiated';

  @override
  PlayerCapability get capability => _capability;

  @override
  Stream<PlayerTimeEvent> get timeEvents => _events.stream;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}

  void promote() {
    _capability = const PlayerCapability(
      canSeek: true,
      canReadDuration: true,
      canReadPosition: true,
      canEmbedPlayer: true,
      canCreateTimeAnchor: true,
    );
    _events.add(PlayerTimeEvent(
      positionMs: 12000,
      durationMs: 60000,
      at: DateTime.now(),
    ));
  }

  void revoke() {
    _capability = const PlayerCapability(canEmbedPlayer: true);
    _events.add(PlayerTimeEvent(
      positionMs: 12000,
      durationMs: 60000,
      at: DateTime.now(),
    ));
  }

  @override
  Future<int> currentPositionMs() async => 12000;

  @override
  Future<int?> durationMs() async => 60000;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seekTo(int positionMs) async {}

  void dispose() => _events.close();
}

class _FakeWindowsBilibiliAdapter extends WindowsBilibiliPlayerAdapter {
  int currentPositionCalls = 0;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}

  @override
  Future<int> currentPositionMs() async {
    currentPositionCalls++;
    return super.currentPositionMs();
  }
}

class _RetryableAdapter extends _LinkOnlyAdapter {
  _RetryableAdapter() : super('fixture');

  int loadCalls = 0;

  @override
  PlayerCapability get capability => const PlayerCapability(
        canEmbedPlayer: true,
      );

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    loadCalls++;
    if (loadCalls == 1) throw StateError('temporary surface failure');
  }
}

/// Simulates a native player whose event stream lags behind its readable
/// current position. Range boundaries must query currentPositionMs at click
/// time instead of persisting the stale event position.
class _LaggingTimeAdapter implements PlayerAdapter {
  int currentMs = 0;

  @override
  String get providerId => 'fixture';

  @override
  PlayerCapability get capability => const PlayerCapability(
        canSeek: true,
        canReadDuration: true,
        canReadPosition: true,
        canEmbedPlayer: true,
        canCreateTimeAnchor: true,
      );

  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<int> currentPositionMs() async => currentMs;

  @override
  Future<int?> durationMs() async => 200000;

  @override
  Future<void> seekTo(int positionMs) async {
    currentMs = positionMs;
  }
}

class _ThrowingTimeAdapter extends _LaggingTimeAdapter {
  @override
  Future<int> currentPositionMs() async {
    throw StateError('provider-secret-token=do-not-render');
  }
}

void _useDesktopSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('VideoStudyScreen shows player and subtitle dock', (
    tester,
  ) async {
    final adapter = _buildFixture();
    final track = _buildTrack();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: track,
        ),
      ),
    );

    // Wait for load to complete.
    await tester.pumpAndSettle();

    // Subtitle cues should be visible.
    expect(find.text('灯光切换'), findsOneWidget);
    expect(find.text('烟雾升起'), findsOneWidget);
    expect(find.text('副歌开始'), findsOneWidget);

    // Dock header and tabs should expose both study contexts.
    expect(find.text('研读辅助'), findsOneWidget);
    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('视频笔记'), findsOneWidget);
    expect(find.textContaining('用户导入'), findsOneWidget);

    // Player controls visible.
    expect(find.byIcon(Icons.play_arrow), findsWidgets);

    adapter.dispose();
  });

  testWidgets('dock tabs separate subtitle and honest empty notes states',
      (tester) async {
    _useDesktopSurface(tester, const Size(640, 360));
    final adapter = _buildFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('video_dock_tab_subtitles')), findsOneWidget);
    expect(find.byKey(const ValueKey('video_dock_tab_notes')), findsOneWidget);
    expect(find.byKey(const ValueKey('video_subtitles_tab_content')),
        findsOneWidget);
    expect(find.text('需要字幕'), findsWidgets);
    expect(find.byKey(const ValueKey('subtitle_empty_state_scroll')),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('video_dock_tab_notes')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('video_notes_tab_content')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('video_notes_empty_state')), findsOneWidget);
    expect(find.text('还没有视频笔记'), findsOneWidget);
    expect(find.textContaining('可在当前位置创建'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('video_dock_tab_subtitles')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_subtitles_tab_content')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restored video notes are vertical, scrollable, and seekable',
      (tester) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = _buildFixture();
    final store = _RecordingSessionStore(restored: _sessionWithVideoNotes());
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
          sessionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('灯光切换'), findsOneWidget);
    expect(find.text('视频笔记 1'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('video_dock_tab_notes')));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('video_note_card_card_note_0'));
    final second = find.byKey(const ValueKey('video_note_card_card_note_1'));
    final third = find.byKey(const ValueKey('video_note_card_card_note_2'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(third, findsOneWidget);
    final firstRect = tester.getRect(first);
    final secondRect = tester.getRect(second);
    final thirdRect = tester.getRect(third);
    expect(secondRect.top, greaterThan(firstRect.bottom));
    expect(thirdRect.top, greaterThan(secondRect.bottom));
    expect(secondRect.left, closeTo(firstRect.left, 0.1));

    final list = find.byKey(const ValueKey('video_notes_list'));
    final scrollableFinder =
        find.descendant(of: list, matching: find.byType(Scrollable)).first;
    final scrollable = tester.widget<Scrollable>(scrollableFinder);
    final scrollableState = tester.state<ScrollableState>(scrollableFinder);
    expect(scrollable.axisDirection, AxisDirection.down);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0));

    await adapter.seekTo(50000);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(await adapter.currentPositionMs(), inInclusiveRange(6000, 9500));
    expect(
      adapter.isPlaying,
      isTrue,
      reason: 'range notes play from start toward their end boundary',
    );

    final last = find.byKey(const ValueKey('video_note_card_card_note_11'));
    await tester.scrollUntilVisible(
      last,
      280,
      scrollable: scrollableFinder,
    );
    await tester.pumpAndSettle();
    expect(last, findsOneWidget);
    expect(
      scrollableState.position.pixels,
      greaterThan(scrollableState.position.minScrollExtent),
    );
    await adapter.seekTo(50000);
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(await adapter.currentPositionMs(), 46000);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('video notes sort by timeline and edit inline on double click',
      (tester) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final createdAt = DateTime.utc(2026, 8, 23, 9);
    final session = VideoAnnotationSession(
      sourceId: 'src_video_test',
      sourceVersionId: 'ver_video_test_v1',
      lastPositionMs: 0,
      anchors: [
        TimeRangeAnchorSpec.buildAnchor(
          anchorId: 'late_anchor',
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          spec: TimeRangeAnchorSpec.point(60000),
          createdAt: createdAt,
        ),
        TimeRangeAnchorSpec.buildAnchor(
          anchorId: 'early_anchor',
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          spec: TimeRangeAnchorSpec.point(10000),
          createdAt: createdAt.add(const Duration(minutes: 1)),
        ),
      ],
      annotationCards: [
        CardContract(
          cardId: 'late_card',
          cardKind: CardKind.annotation,
          title: '后段笔记',
          body: '后段正文',
          createdAt: createdAt,
        ),
        CardContract(
          cardId: 'early_card',
          cardKind: CardKind.annotation,
          title: '前段笔记',
          body: '前段正文',
          createdAt: createdAt.add(const Duration(minutes: 1)),
        ),
      ],
      anchorToCard: const {
        'late_anchor': 'late_card',
        'early_anchor': 'early_card',
      },
      savedAt: createdAt,
    );
    final store = _RecordingSessionStore(restored: session);
    final adapter = _buildFixture();
    await tester.pumpWidget(MaterialApp(
      home: VideoStudyScreen(
        adapter: adapter,
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        sessionStore: store,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video_dock_tab_notes')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('前段笔记')).dy,
      lessThan(tester.getTopLeft(find.text('后段笔记')).dy),
    );

    final earlyCard = find.byKey(const ValueKey('video_note_card_early_card'));
    await tester.tap(earlyCard);
    await tester.pumpAndSettle();
    expect(await adapter.currentPositionMs(), 10000);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(earlyCard);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(earlyCard);
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('video_note_editor_early_card'));
    expect(editor, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(editor, '改后的标题\n改后的连续正文');
    await tester.tap(find.descendant(of: earlyCard, matching: find.text('保存')));
    await tester.pumpAndSettle();
    expect(find.text('改后的标题'), findsOneWidget);
    expect(find.text('改后的连续正文'), findsOneWidget);
    expect(
        store.saved!.annotationCards
            .firstWhere(
              (card) => card.cardId == 'early_card',
            )
            .title,
        '改后的标题');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(earlyCard);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(earlyCard);
    await tester.pumpAndSettle();
    await tester.enterText(editor, '不应保存的标题\n临时正文');
    await tester.tap(
      find.descendant(of: earlyCard, matching: find.text('取消')),
    );
    await tester.pumpAndSettle();
    expect(find.text('改后的标题'), findsOneWidget);
    expect(find.text('不应保存的标题'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('annotation ordering has deterministic same-time tie breakers',
      () async {
    final adapter = _DelayedPauseAdapter();
    final viewModel = VideoStudyViewModel(
      adapter: adapter,
      sourceId: 'src_video_test',
      sourceVersionId: 'ver_video_test_v1',
      providerId: 'fixture',
    );
    await viewModel.initialize();
    final created = DateTime.utc(2026, 8, 23, 9);
    AnchorContract anchor(String id) => TimeRangeAnchorSpec.buildAnchor(
          anchorId: id,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          spec: TimeRangeAnchorSpec.point(10000),
          createdAt: created,
        );
    CardContract card(String id, DateTime at) => CardContract(
          cardId: id,
          cardKind: CardKind.annotation,
          title: id,
          createdAt: at,
        );
    viewModel.restoreFromSession(VideoAnnotationSession(
      sourceId: 'src_video_test',
      sourceVersionId: 'ver_video_test_v1',
      lastPositionMs: 0,
      anchors: [anchor('z_anchor'), anchor('b_anchor'), anchor('a_anchor')],
      annotationCards: [
        card('z_card', created.add(const Duration(minutes: 1))),
        card('b_card', created),
        card('a_card', created),
      ],
      anchorToCard: const {
        'z_anchor': 'z_card',
        'b_anchor': 'b_card',
        'a_anchor': 'a_card',
      },
      savedAt: created,
    ));
    expect(
      viewModel.annotations.map((item) => item.card.cardId),
      ['a_card', 'b_card', 'z_card'],
    );
    viewModel.dispose(disposeAdapter: false);
    adapter.dispose();
  });

  test('range playback pauses at end and loops when enabled', () async {
    final adapter = _DelayedPauseAdapter();
    final viewModel = VideoStudyViewModel(
      adapter: adapter,
      sourceId: 'src_video_test',
      sourceVersionId: 'ver_video_test_v1',
      providerId: 'fixture',
    );
    await viewModel.initialize();
    viewModel.restoreFromSession(_sessionWithVideoNotes());
    final range = viewModel.annotations.firstWhere((item) => !item.isPoint);

    await viewModel.activateAnnotation(range);
    expect(adapter.positionMs, range.startMs);
    expect(adapter.playing, isTrue);
    adapter.emit(range.endMs);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.playing, isFalse);
    expect(adapter.positionMs, range.endMs);
    expect(viewModel.activeSegmentCardId, isNull);

    await viewModel.toggleSegmentLoop(range);
    expect(viewModel.isSegmentLoopEnabled(range.card.cardId), isTrue);
    adapter.emit(range.endMs);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.positionMs, range.startMs);
    expect(adapter.playing, isTrue);
    expect(viewModel.activeSegmentCardId, range.card.cardId);
    viewModel.dispose(disposeAdapter: false);
    adapter.dispose();
  });

  test('point annotation seeks without entering segment playback', () async {
    final adapter = _DelayedPauseAdapter();
    final viewModel = VideoStudyViewModel(
      adapter: adapter,
      sourceId: 'src_video_test',
      sourceVersionId: 'ver_video_test_v1',
      providerId: 'fixture',
    );
    await viewModel.initialize();
    viewModel.restoreFromSession(_sessionWithVideoNotes());
    final point = viewModel.annotations.firstWhere((item) => item.isPoint);
    await viewModel.activateAnnotation(point);
    expect(adapter.positionMs, point.startMs);
    expect(adapter.playCalls, 0);
    expect(viewModel.activeSegmentCardId, isNull);
    viewModel.dispose(disposeAdapter: false);
    adapter.dispose();
  });

  test('switching ranges awaits delayed pause before the new play', () async {
    final adapter = _DelayedPauseAdapter();
    final viewModel = VideoStudyViewModel(
      adapter: adapter,
      sourceId: 'src_video_test',
      sourceVersionId: 'ver_video_test_v1',
      providerId: 'fixture',
    );
    await viewModel.initialize();
    final session = _sessionWithVideoNotes();
    viewModel.restoreFromSession(session);
    final first = viewModel.annotations.firstWhere((item) => !item.isPoint);
    final second = UIAnnotation(
      anchor: TimeRangeAnchorSpec.buildAnchor(
        anchorId: 'second_range',
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        spec: TimeRangeAnchorSpec.range(20000, 24000),
        createdAt: DateTime.utc(2026, 8, 23),
      ),
      card: CardContract(
        cardId: 'second_range_card',
        cardKind: CardKind.annotation,
        title: '第二段',
        createdAt: DateTime.utc(2026, 8, 23),
      ),
    );
    await viewModel.activateAnnotation(first);
    expect(adapter.playCalls, 1);

    adapter.pauseCompleter = Completer<void>();
    final switching = viewModel.activateAnnotation(second);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.pauseCalls, 1);
    expect(adapter.playCalls, 1,
        reason: 'new play must wait for the previous native pause');
    adapter.pauseCompleter!.complete();
    await switching;
    expect(adapter.playCalls, 2);
    expect(adapter.positionMs, 20000);
    expect(adapter.playing, isTrue);
    viewModel.dispose(disposeAdapter: false);
    adapter.dispose();
  });

  testWidgets('switching tabs and hiding dock cancel active segment playback',
      (tester) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = FixturePlayerAdapter(
      durationMs: 200000,
      tickInterval: const Duration(milliseconds: 10),
      tickMs: 100,
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoStudyScreen(
        adapter: adapter,
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        sessionStore: _RecordingSessionStore(
          restored: _sessionWithVideoNotes(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video_dock_tab_notes')));
    await tester.pumpAndSettle();
    final rangeCard = find.byKey(
      const ValueKey('video_note_card_card_note_1'),
    );

    await tester.tap(rangeCard);
    await tester.pump(const Duration(milliseconds: 20));
    expect(adapter.isPlaying, isTrue);
    await tester.tap(find.byKey(const ValueKey('video_dock_tab_subtitles')));
    await tester.pump();
    expect(adapter.isPlaying, isFalse);

    await tester.tap(find.byKey(const ValueKey('video_dock_tab_notes')));
    await tester.pump();
    await tester.tap(rangeCard);
    await tester.pump(const Duration(milliseconds: 20));
    expect(adapter.isPlaying, isTrue);
    await tester.tap(find.byKey(const ValueKey('video_close_dock')));
    await tester.pump();
    expect(adapter.isPlaying, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('runtime capability downgrade cancels active segment', () async {
    final adapter = _RuntimeNegotiatedAdapter();
    final viewModel = VideoStudyViewModel(
      adapter: adapter,
      sourceId: 'src_runtime_segment',
      sourceVersionId: 'ver_runtime_segment_v1',
      providerId: 'bilibili',
    );
    await viewModel.initialize();
    adapter.promote();
    await Future<void>.delayed(Duration.zero);
    final annotation = UIAnnotation(
      anchor: TimeRangeAnchorSpec.buildAnchor(
        anchorId: 'runtime_range',
        sourceId: 'src_runtime_segment',
        sourceVersionId: 'ver_runtime_segment_v1',
        spec: TimeRangeAnchorSpec.range(10000, 14000),
        createdAt: DateTime.utc(2026, 8, 23),
      ),
      card: CardContract(
        cardId: 'runtime_range_card',
        cardKind: CardKind.annotation,
        title: '运行时区间',
        createdAt: DateTime.utc(2026, 8, 23),
      ),
    );
    await viewModel.activateAnnotation(annotation);
    expect(viewModel.activeSegmentCardId, annotation.card.cardId);
    adapter.revoke();
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.activeSegmentCardId, isNull);
    viewModel.dispose();
  });

  testWidgets('dock uses 65:35 right, 70:30 bottom, and fully leaves',
      (tester) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = _buildFixture();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var playerSize = tester.getSize(
      find.byKey(const ValueKey('video_player_region')),
    );
    var dockSize = tester.getSize(
      find.byKey(const ValueKey('video_context_dock_region')),
    );
    expect(find.byKey(const ValueKey('video_layout_right')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('video_dock_tab_subtitles')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('video_dock_tab_notes')), findsOneWidget);
    final playerLeft = tester.getTopLeft(
      find.byKey(const ValueKey('video_player_region')),
    );
    final dockLeft = tester.getTopLeft(
      find.byKey(const ValueKey('video_context_dock_region')),
    );
    expect(playerLeft.dx, lessThan(dockLeft.dx));
    expect(
      playerSize.width / (playerSize.width + dockSize.width),
      closeTo(0.65, 0.01),
    );
    expect(playerSize.width, greaterThanOrEqualTo(420));
    expect(dockSize.width, greaterThanOrEqualTo(320));

    await tester.tap(find.byTooltip('停靠到底部'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_layout_bottom')), findsOneWidget);
    playerSize = tester.getSize(
      find.byKey(const ValueKey('video_player_region')),
    );
    dockSize = tester.getSize(
      find.byKey(const ValueKey('video_context_dock_region')),
    );
    expect(
      playerSize.height / (playerSize.height + dockSize.height),
      closeTo(0.70, 0.01),
    );
    expect(playerSize.height, greaterThanOrEqualTo(300));
    expect(dockSize.height, greaterThanOrEqualTo(220));

    await tester.tap(find.byKey(const ValueKey('video_close_dock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_context_dock')), findsNothing);
    expect(find.byKey(const ValueKey('video_dock_splitter')), findsNothing);
    playerSize = tester.getSize(
      find.byKey(const ValueKey('video_player_region')),
    );
    expect(playerSize, const Size(1440, 900));

    await tester.tap(find.byKey(const ValueKey('video_open_dock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_context_dock')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('splitter changes real layout and persists the adjusted ratio', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = _buildFixture();
    final store = _RecordingSessionStore();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
          sessionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dockBefore = tester.getSize(
      find.byKey(const ValueKey('video_context_dock_region')),
    );
    await tester.drag(
      find.byKey(const ValueKey('video_dock_splitter')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    final dockAfter = tester.getSize(
      find.byKey(const ValueKey('video_context_dock_region')),
    );

    expect(dockAfter.width, greaterThan(dockBefore.width + 80));
    expect(store.saved, isNotNull);
    expect(store.saved!.dockOrientation, 'right');
    expect(store.saved!.dockRatio, greaterThan(0.35));

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('restored bottom dock ratio controls the restarted layout', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = _buildFixture();
    final store = _RecordingSessionStore(
      restored: VideoAnnotationSession(
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        lastPositionMs: 0,
        anchors: const [],
        annotationCards: const [],
        anchorToCard: const {},
        dockOrientation: 'bottom',
        dockRatio: 0.28,
        savedAt: DateTime.utc(2026, 8, 20),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
          sessionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video_layout_bottom')), findsOneWidget);
    final playerSize = tester.getSize(
      find.byKey(const ValueKey('video_player_region')),
    );
    final dockSize = tester.getSize(
      find.byKey(const ValueKey('video_context_dock_region')),
    );
    expect(
      dockSize.height / (playerSize.height + dockSize.height),
      closeTo(0.28, 0.01),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('narrow desktop automatically moves the dock to the bottom', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(720, 720));
    final adapter = _buildFixture();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video_layout_bottom')), findsOneWidget);
    expect(find.byTooltip('窗口较窄，已自动停靠底部'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets(
    'compact dock exposes focusable subtitle and notes tabs and exits',
    (tester) async {
      _useDesktopSurface(tester, const Size(640, 720));
      final adapter = _buildFixture();

      await tester.pumpWidget(
        MaterialApp(
          home: VideoStudyScreen(
            adapter: adapter,
            sourceId: 'src_video_test',
            sourceVersionId: 'ver_video_test_v1',
            initialTrack: _buildTrack(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final transcriptTab = find.byKey(
        const ValueKey('video_dock_tab_subtitles'),
      );
      final notesTab = find.byKey(const ValueKey('video_dock_tab_notes'));
      expect(transcriptTab, findsOneWidget);
      expect(notesTab, findsOneWidget);
      expect(
        find.descendant(of: transcriptTab, matching: find.byType(InkWell)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: notesTab, matching: find.byType(InkWell)),
        findsOneWidget,
      );

      await tester.tap(notesTab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('video_notes_empty_state')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('video_close_dock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video_context_dock')), findsNothing);
      expect(find.byKey(const ValueKey('video_open_dock')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('bottom dock header keeps tags and controls inside narrow width',
      (tester) async {
    _useDesktopSurface(tester, const Size(640, 360));
    final adapter = _buildFixture();
    var tagCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: VideoStudyScreen(
        adapter: adapter,
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        initialTrack: _buildTrack(),
        onEditTags: () => tagCalls++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video_layout_bottom')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('source-video-tags-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('video_close_dock')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('source-video-tags-action')));
    expect(tagCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('player and dock minimum sizes hold at 1024 by 720', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(1024, 720));
    final adapter = _buildFixture();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var playerSize = tester.getSize(
      find.byKey(const ValueKey('video_player_region')),
    );
    var dockSize = tester.getSize(
      find.byKey(const ValueKey('video_context_dock_region')),
    );
    expect(playerSize.width, greaterThanOrEqualTo(420));
    expect(dockSize.width, greaterThanOrEqualTo(320));

    await tester.tap(find.byTooltip('停靠到底部'));
    await tester.pumpAndSettle();
    playerSize = tester.getSize(
      find.byKey(const ValueKey('video_player_region')),
    );
    dockSize = tester.getSize(
      find.byKey(const ValueKey('video_context_dock_region')),
    );
    expect(playerSize.height, greaterThanOrEqualTo(300));
    expect(dockSize.height, greaterThanOrEqualTo(220));

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('Bilibili, Xiaohongshu and unknown providers stay link-only', (
    tester,
  ) async {
    for (final provider in const ['bilibili', 'xiaohongshu', 'unknown']) {
      final adapter = _LinkOnlyAdapter(provider);
      final url = 'https://example.com/$provider/video';
      await tester.pumpWidget(
        MaterialApp(
          home: VideoStudyScreen(
            adapter: adapter,
            sourceId: 'src_$provider',
            sourceVersionId: 'ver_${provider}_v1',
            providerId: provider,
            embedUrl: url,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('当前为链接模式'), findsOneWidget);
      expect(find.text(url), findsOneWidget);
      expect(
        find.byKey(const ValueKey('open_video_source_link')),
        findsOneWidget,
      );
      expect(find.text('Fixture Player'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Fixture surface icon follows paused and playing state', (
    tester,
  ) async {
    final adapter = _buildFixture();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);

    await tester.tap(find.byIcon(Icons.pause).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('NeedsSubtitle state shows import prompt when no track', (
    tester,
  ) async {
    final adapter = _buildFixture();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('需要字幕'), findsWidgets);
    expect(find.text('导入字幕'), findsOneWidget);

    adapter.dispose();
  });

  testWidgets('Windows Bilibili is playable in-app but time-study limited', (
    tester,
  ) async {
    final adapter = _FakeWindowsBilibiliAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_bilibili_acceptance',
          sourceVersionId: 'ver_bilibili_acceptance_v1',
          providerId: 'bilibili',
          embedUrl: 'https://www.bilibili.com/video/BV1E8KV6QEu7',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前为链接模式'), findsNothing);
    expect(find.text('可播放 · 时间研读受限'), findsWidgets);
    expect(
      find.byKey(const ValueKey('video_playback_level_limited')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bilibili_login_boundary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('bilibili_open_login')), findsOneWidget);
    expect(find.byKey(const ValueKey('bilibili_return_video')), findsOneWidget);
    expect(find.byKey(const ValueKey('bilibili_retry_player')), findsOneWidget);
    expect(find.textContaining('清除'), findsNothing);
    expect(find.text('失败分类：公开路径不可用'), findsOneWidget);
    expect(find.textContaining('应用不读取或保存登录态'), findsOneWidget);
    expect(find.textContaining('SRT / VTT'), findsOneWidget);
    expect(find.text('导入字幕'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bilibili_open_login')));
    await tester.pumpAndSettle();
    expect(find.text('打开 Bilibili 登录页？'), findsOneWidget);
    expect(find.textContaining('不会读取或记录密码、Cookie'), findsOneWidget);
    expect(find.textContaining('清除站点数据尚未获得授权'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('video_annotate_current_position')),
      findsNothing,
      reason: 'without readable current time the UI must not forge anchors',
    );
    expect(
      adapter.currentPositionCalls,
      0,
      reason: 'capability guards must prevent reading the frozen fake value',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('runtime bridge promotion immediately enables time anchors',
      (tester) async {
    final adapter = _RuntimeNegotiatedAdapter();
    expect(adapter.capability.canReadPosition, isFalse);
    await tester.pumpWidget(MaterialApp(
      home: VideoStudyScreen(
        adapter: adapter,
        sourceId: 'src_runtime_bridge',
        sourceVersionId: 'ver_runtime_bridge_v1',
      ),
    ));
    await tester.pumpAndSettle();

    expect(adapter.capability.canReadPosition, isFalse);
    expect(
      find.byKey(const ValueKey('video_annotate_current_position')),
      findsNothing,
    );
    adapter.promote();
    await tester.pumpAndSettle();
    expect(adapter.capability.canReadPosition, isTrue);
    expect(
      find.byKey(const ValueKey('video_annotate_current_position')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('runtime downgrade clears range selection and annotation draft',
      (tester) async {
    final adapter = _RuntimeNegotiatedAdapter();
    await tester.pumpWidget(MaterialApp(
      home: VideoStudyScreen(
        adapter: adapter,
        sourceId: 'src_runtime_revoke',
        sourceVersionId: 'ver_runtime_revoke_v1',
      ),
    ));
    await tester.pumpAndSettle();
    adapter.promote();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('video_begin_range_annotation')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('video_finish_range_annotation')),
      findsOneWidget,
    );
    adapter.revoke();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('video_finish_range_annotation')),
      findsNothing,
    );

    adapter.promote();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('video_annotate_current_position')),
    );
    await tester.pump();
    expect(
        find.byKey(const ValueKey('video_annotation_editor')), findsOneWidget);
    adapter.revoke();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_annotation_editor')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed player load can retry without changing the source', (
    tester,
  ) async {
    final adapter = _RetryableAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_retry',
          sourceVersionId: 'ver_retry_v1',
          providerId: 'fixture',
          embedUrl: 'https://example.com/retry',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('视频加载失败，请检查网络或稍后重试。'),
      findsOneWidget,
    );
    expect(find.textContaining('temporary surface failure'), findsNothing);
    expect(find.byKey(const ValueKey('video_retry_load')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video_retry_load')));
    await tester.pumpAndSettle();

    expect(adapter.loadCalls, 2);
    expect(find.byKey(const ValueKey('video_retry_load')), findsNothing);
    expect(find.byKey(const ValueKey('video_player_region')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('session restore failure never exposes storage internals', (
    tester,
  ) async {
    final adapter = _buildFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_restore_error',
          sourceVersionId: 'ver_restore_error_v1',
          sessionStore: _ThrowingSessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('研读进度恢复失败，请稍后重试。'),
      findsOneWidget,
    );
    expect(find.textContaining('session-secret-token'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('current-position failure never exposes provider internals', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = _ThrowingTimeAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_safe_error',
          sourceVersionId: 'ver_safe_error_v1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('video_annotate_current_position')),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法读取当前播放位置，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('provider-secret-token'), findsNothing);
    expect(find.byKey(const ValueKey('video_annotation_editor')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('disposed view model discards a late Bilibili resolver result',
      () async {
    final probe = _DelayedBiliProbe();
    final viewModel = VideoStudyViewModel(
      adapter: _LinkOnlyAdapter('bilibili'),
      sourceId: 'src_bili_late',
      sourceVersionId: 'ver_bili_late_v1',
      providerId: 'bilibili',
      bilibiliTimedTextResolver: BilibiliPublicTimedTextResolver(probe: probe),
    );
    await viewModel.initialize(
      embedUrl: 'https://www.bilibili.com/video/BV1E8KV6QEu7',
    );
    expect(viewModel.subtitleFetchStatus, SubtitleAutoFetchStatus.fetching);
    viewModel.dispose();
    probe.completer.complete(const BilibiliSameOriginProbeResult(
      subtitleText: '1\n00:00:01,000 --> 00:00:02,000\nlate result',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.subtitleFetchStatus, SubtitleAutoFetchStatus.fetching);
    expect(viewModel.track, isNull);
  });

  testWidgets('source switch ignores the previous initialize restore callback',
      (tester) async {
    final oldAdapter = _DelayedLoadAdapter('fixture');
    final oldStore = _CountingSessionStore();
    final newStore = _CountingSessionStore();

    await tester.pumpWidget(MaterialApp(
      home: VideoStudyScreen(
        adapter: oldAdapter,
        sourceId: 'src_old',
        sourceVersionId: 'ver_old',
        sessionStore: oldStore,
      ),
    ));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
      home: VideoStudyScreen(
        adapter: oldAdapter,
        sourceId: 'src_new',
        sourceVersionId: 'ver_new',
        sessionStore: newStore,
      ),
    ));
    oldAdapter.loadCompleter.complete();
    await tester.pumpAndSettle();
    expect(oldStore.loadCalls, 0);
    expect(newStore.loadCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('annotation draft and focus survive responsive rebuilds', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = _buildFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_draft_resize',
          sourceVersionId: 'ver_draft_resize_v1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await adapter.seekTo(22000);
    await tester.tap(
      find.byKey(const ValueKey('video_annotate_current_position')),
    );
    await tester.pumpAndSettle();

    final documentFinder = find.byKey(
      const ValueKey('video_annotation_document'),
    );
    await tester.enterText(documentFinder, '跨尺寸标题\n跨尺寸正文草稿');
    expect(
      tester.widget<TextField>(documentFinder).focusNode!.hasFocus,
      isTrue,
    );

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_dock_tab_notes')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('video_annotation_editor')), findsOneWidget);
    expect(
      tester.widget<TextField>(documentFinder).controller!.text,
      '跨尺寸标题\n跨尺寸正文草稿',
    );
    expect(
      tester.widget<TextField>(documentFinder).focusNode!.hasFocus,
      isTrue,
    );

    tester.view.physicalSize = const Size(720, 720);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_layout_bottom')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('video_annotation_editor')), findsOneWidget);
    expect(
      tester.widget<TextField>(documentFinder).controller!.text,
      '跨尺寸标题\n跨尺寸正文草稿',
    );
    expect(
      tester.widget<TextField>(documentFinder).focusNode!.hasFocus,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('video_close_dock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_annotation_editor')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('video_open_dock')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('video_annotation_editor')), findsOneWidget);
    expect(
      tester.widget<TextField>(documentFinder).controller!.text,
      '跨尺寸标题\n跨尺寸正文草稿',
    );
    expect(
      tester.widget<TextField>(documentFinder).focusNode!.hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('recorded draft focus gates focus restoration', (tester) async {
    final vm = VideoStudyViewModel(
      adapter: _buildFixture(),
      sourceId: 'src_focus_gate',
      sourceVersionId: 'ver_focus_gate_v1',
      providerId: 'fixture',
      initialTrack: _buildTrack(),
    );
    vm.beginAnnotation(cueIndex: 0);
    vm.initializeAnnotationDraft(quote: '灯光切换');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 700,
            child: AnnotationEditor(
              key: const ValueKey('unfocused_editor'),
              viewModel: vm,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var field = tester.widget<TextField>(
      find.byKey(const ValueKey('video_annotation_document')),
    );
    expect(field.focusNode!.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    vm.rememberAnnotationDraftFocus();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 700,
            child: AnnotationEditor(
              key: const ValueKey('focused_editor'),
              viewModel: vm,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    field = tester.widget<TextField>(
      find.byKey(const ValueKey('video_annotation_document')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
  });

  testWidgets('subtitle picker failure uses fixed safe copy', (tester) async {
    final vm = VideoStudyViewModel(
      adapter: _buildFixture(),
      sourceId: 'src_subtitle_error',
      sourceVersionId: 'ver_subtitle_error_v1',
      providerId: 'fixture',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 600,
            child: SubtitleListView(
              viewModel: vm,
              fileBytesPicker: () async {
                throw StateError('subtitle-provider-secret-token');
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('导入字幕'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择 SRT / VTT 文件'));
    await tester.pumpAndSettle();

    expect(
      find.text('字幕文件读取失败，请确认文件仍可访问后重试。'),
      findsOneWidget,
    );
    expect(find.textContaining('subtitle-provider-secret-token'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
  });

  testWidgets('annotation store failure uses fixed safe copy', (tester) async {
    final adapter = _buildFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_widget_source',
          sourceVersionId: 'ver_widget_source_v1',
          initialTrack: _buildTrack(),
          annotationStore: const _ThrowingAnnotationStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('annotate_cue_1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('video_annotation_document')),
      '保存失败仍保留的草稿',
    );
    await tester.ensureVisible(find.text('保存标注'));
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();

    expect(find.text('标注保存失败，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('annotation-store-secret-token'), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('video_annotation_document')),
          )
          .controller!
          .text,
      '保存失败仍保留的草稿',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending draft cannot be replaced by another subtitle cue', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(900, 900));
    final adapter = _buildFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_pending_guard',
          sourceVersionId: 'ver_pending_guard_v1',
          initialTrack: _buildTrack(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('annotate_cue_1')));
    await tester.pumpAndSettle();
    expect(find.text('在 00:02–00:05 创建标注'), findsOneWidget);
    final documentFinder = find.byKey(
      const ValueKey('video_annotation_document'),
    );
    expect(
      tester.widget<TextField>(documentFinder).controller!.text,
      contains('灯光切换'),
    );
    await tester.enterText(documentFinder, '不可覆盖标题\n不可覆盖正文');

    tester.view.physicalSize = const Size(720, 720);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(documentFinder).controller!.text,
      '不可覆盖标题\n不可覆盖正文',
    );

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(documentFinder).controller!.text,
      '不可覆盖标题\n不可覆盖正文',
    );
    await tester.tap(
      find.byKey(const ValueKey('video_dock_tab_subtitles')),
    );
    await tester.pumpAndSettle();
    final secondAnnotate = find.byKey(const ValueKey('annotate_cue_2'));
    expect(tester.widget<IconButton>(secondAnnotate).onPressed, isNull);
    await tester.tap(secondAnnotate, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('video_dock_tab_notes')));
    await tester.pumpAndSettle();
    expect(find.text('在 00:02–00:05 创建标注'), findsOneWidget);
    expect(
      tester.widget<TextField>(documentFinder).controller!.text,
      '不可覆盖标题\n不可覆盖正文',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('point annotation at current time does not depend on subtitles', (
    tester,
  ) async {
    _useDesktopSurface(tester, const Size(1440, 900));
    final adapter = _buildFixture();
    final store = _RecordingSessionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          sessionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await adapter.seekTo(7000);
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('video_annotate_current_position')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('video_annotation_editor')),
      findsOneWidget,
    );
    expect(find.text('在 00:07 创建标注'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '无字幕点标注');
    await tester.ensureVisible(find.text('保存标注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();
    final anchor = store.saved!.anchors.single;
    expect(anchor.positionSpec['start_ms'], 7000);
    expect(anchor.positionSpec['end_ms'], 7000);
    expect(anchor.positionSpec['is_point'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('range annotation captures two player positions without cues',
      (tester) async {
    final adapter = _SilentTimeEventAdapter();
    final store = _RecordingSessionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          sessionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await adapter.seekTo(10000);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('video_begin_range_annotation')),
    );
    await tester.pump();
    expect(find.text('起点 00:10'), findsOneWidget);

    await adapter.seekTo(14000);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('video_finish_range_annotation')),
    );
    await tester.pumpAndSettle();
    expect(find.text('00:10–00:14'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '无字幕区间标注');
    await tester.ensureVisible(find.text('保存标注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();
    final anchor = store.saved!.anchors.single;
    expect(anchor.positionSpec['start_ms'], 10000);
    expect(anchor.positionSpec['end_ms'], 14000);
    expect(anchor.positionSpec['is_point'], isFalse);

    // A fresh study surface restores the full range and clicking the saved
    // card returns to its start boundary, without requiring subtitles.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final restartedAdapter = _SilentTimeEventAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: restartedAdapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          sessionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video_dock_tab_notes')));
    await tester.pumpAndSettle();
    expect(find.text('无字幕区间标注'), findsOneWidget);
    await restartedAdapter.seekTo(50000);
    await tester.pump();
    await tester.tap(find.text('无字幕区间标注'));
    await tester.pumpAndSettle();
    expect(await restartedAdapter.currentPositionMs(), 10000);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'range boundaries read the player at click time and never collapse to a point',
    (tester) async {
      _useDesktopSurface(tester, const Size(1440, 900));
      final adapter = _LaggingTimeAdapter();
      final store = _RecordingSessionStore();
      await tester.pumpWidget(
        MaterialApp(
          home: VideoStudyScreen(
            adapter: adapter,
            sourceId: 'src_video_test',
            sourceVersionId: 'ver_video_test_v1',
            sessionStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      adapter.currentMs = 12000;
      await tester.tap(
        find.byKey(const ValueKey('video_begin_range_annotation')),
      );
      await tester.pumpAndSettle();
      expect(find.text('起点 00:12'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('video_finish_range_annotation')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('video_annotation_editor')),
        findsNothing,
      );
      expect(find.textContaining('区间终点仍与起点相同'), findsOneWidget);
      expect(store.saved?.anchors ?? const [], isEmpty);

      adapter.currentMs = 18500;
      await tester.tap(
        find.byKey(const ValueKey('video_finish_range_annotation')),
      );
      await tester.pumpAndSettle();
      expect(find.text('在 00:12–00:18 创建标注'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '真实区间');
      await tester.tap(find.text('保存标注'));
      await tester.pumpAndSettle();

      final anchor = store.saved!.anchors.single;
      expect(anchor.positionSpec['start_ms'], 12000);
      expect(anchor.positionSpec['end_ms'], 18500);
      expect(anchor.positionSpec['is_point'], isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Clicking a subtitle cue triggers seek', (tester) async {
    final adapter = _buildFixture();
    final track = _buildTrack();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: track,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap the third cue ("副歌开始").
    await tester.tap(find.text('副歌开始'));
    await tester.pumpAndSettle();

    // The fixture adapter should have seeked to 10000ms.
    expect(await adapter.currentPositionMs(), equals(10000));

    adapter.dispose();
  });

  testWidgets('timeline seek keeps the real player position in sync', (
    tester,
  ) async {
    final adapter = _buildFixture();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timeline = find.byKey(const ValueKey('video_timeline_anchor_bar'));
    final rect = tester.getRect(timeline);
    await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
    await tester.pumpAndSettle();

    expect(await adapter.currentPositionMs(), closeTo(100000, 1000));

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('Annotation flow creates card and shows confirmation', (
    tester,
  ) async {
    final adapter = _buildFixture();
    final track = _buildTrack();
    final store = _RecordingSessionStore();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: track,
          sessionStore: store,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Find the annotation square next to a cue — tap it.
    final annotateButton = find.byKey(const ValueKey('annotate_cue_1'));
    expect(annotateButton, findsOneWidget);

    await tester.tap(annotateButton);
    await tester.pumpAndSettle();

    // Pending annotation should show the editor.
    expect(find.text('时间标注'), findsOneWidget);
    expect(find.text('保存标注'), findsOneWidget);
    final editor = find.byKey(const ValueKey('video_annotation_editor'));
    expect(find.descendant(of: editor, matching: find.byType(TextField)),
        findsOneWidget);
    final documentField = tester.widget<TextField>(
      find.byKey(const ValueKey('video_annotation_document')),
    );
    expect(documentField.decoration?.border, InputBorder.none);
    expect(documentField.decoration?.enabledBorder, InputBorder.none);
    expect(documentField.decoration?.focusedBorder, InputBorder.none);
    expect(documentField.decoration?.filled, isFalse);
    expect(documentField.decoration?.fillColor, Colors.transparent);
    expect(documentField.controller!.text, contains('原文引用'));
    expect(documentField.controller!.text, contains('灯光切换'));

    // Title, body and editable quote stay in one continuous document.
    await tester.enterText(
      find.byKey(const ValueKey('video_annotation_document')),
      '副歌观察\n这段副歌很有记忆点\n\n原文引用\n编辑后的灯光切换',
    );

    // Save.
    await tester.ensureVisible(find.text('保存标注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();

    // Confirmation shown.
    expect(find.text('标注已保存'), findsOneWidget);
    expect(store.saved!.annotationCards.single.title, '副歌观察');
    expect(
      store.saved!.annotationCards.single.body,
      '这段副歌很有记忆点\n\n原文引用\n编辑后的灯光切换',
    );
    expect(store.saved!.anchors.single.quote, '编辑后的灯光切换');

    // Let the auto-dismiss timer fire so no timers are pending at teardown.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // Confirmation dismissed, back to subtitle list.
    expect(find.text('标注已保存'), findsNothing);

    await adapter.seekTo(50000);
    await tester.pump();
    await tester.tap(find.text('副歌观察'));
    await tester.pumpAndSettle();
    expect(await adapter.currentPositionMs(), inInclusiveRange(2000, 5000));
    expect(adapter.isPlaying, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('automatically inserted cue quote can be deleted from document',
      (tester) async {
    final adapter = _buildFixture();
    final store = _RecordingSessionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_video_test',
          sourceVersionId: 'ver_video_test_v1',
          initialTrack: _buildTrack(),
          sessionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('annotate_cue_1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('video_annotation_document')),
          )
          .controller!
          .text,
      contains('灯光切换'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('video_annotation_document')),
      '只保留笔记\n引用已由用户删除',
    );
    await tester.ensureVisible(find.text('保存标注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();
    expect(store.saved!.annotationCards.single.title, '只保留笔记');
    expect(store.saved!.annotationCards.single.body, '引用已由用户删除');
    expect(store.saved!.anchors.single.quote, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('YouTube platform subtitle auto-fetch', () {
    TimedTextTrack platformTrack() {
      return const TimedTextTrack(
        trackId: 'yt_en_test',
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v1',
        sourceKind: TimedTextSourceKind.platform,
        language: 'en',
        reliability: TimedTextReliability.reliable,
        cues: [
          TimedTextCue(
            cueId: 'cue_1',
            startMs: 2000,
            endMs: 5000,
            text: 'Light switch, night begins',
          ),
          TimedTextCue(
            cueId: 'cue_2',
            startMs: 6000,
            endMs: 9500,
            text: 'Smoke rises on stage',
          ),
        ],
      );
    }

    Widget buildYoutubeScreen({required YouTubeTimedTextService service}) {
      final adapter = StubYouTubePlayerAdapter();
      return MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_yt_test',
          sourceVersionId: 'ver_yt_v1',
          providerId: 'youtube',
          embedUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          timedTextService: service,
        ),
      );
    }

    testWidgets(
      'auto-fetch success loads the platform track and study is ready',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final service = _FakeTimedTextService(
          YouTubeTimedTextResult(
            track: platformTrack(),
            availableTracks: const [
              YouTubeCaptionTrack(
                languageCode: 'zh-Hans',
                displayName: '中文（简体）',
                baseUrl: 'https://captions.test/zh',
              ),
              YouTubeCaptionTrack(
                languageCode: 'en',
                displayName: 'English',
                baseUrl: 'https://captions.test/en',
              ),
            ],
            selectedTrack: const YouTubeCaptionTrack(
              languageCode: 'en',
              displayName: 'English',
              baseUrl: 'https://captions.test/en',
            ),
          ),
        );

        await tester.pumpWidget(buildYoutubeScreen(service: service));
        await tester.pumpAndSettle();

        expect(
          service.calls,
          equals(1),
          reason: 'auto-fetch ran for YouTube on Windows',
        );
        expect(find.text('需要字幕'), findsNothing);
        expect(find.text('Light switch, night begins'), findsOneWidget);
        expect(find.text('Smoke rises on stage'), findsOneWidget);
        expect(find.textContaining('平台字幕'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('youtube_caption_track_picker')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('auto-fetch failure shows honest "需要字幕" with reason', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final service = _FakeTimedTextService(
        const YouTubeTimedTextResult(
          error: '无字幕轨：该视频没有向平台播放器公开 CC 字幕',
          failureKind: YouTubeTimedTextFailureKind.noTrack,
        ),
      );

      await tester.pumpWidget(buildYoutubeScreen(service: service));
      await tester.pumpAndSettle();

      expect(service.calls, equals(1));
      expect(find.text('需要字幕'), findsWidgets);
      expect(find.text('导入字幕'), findsOneWidget);
      expect(find.text('无字幕轨：该视频没有向平台播放器公开 CC 字幕'), findsOneWidget);
      expect(find.text('失败分类：无字幕轨'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('fixture provider does not trigger auto-fetch', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final service = _FakeTimedTextService(
        YouTubeTimedTextResult(track: platformTrack()),
      );
      final adapter = _buildFixture();

      await tester.pumpWidget(
        MaterialApp(
          home: VideoStudyScreen(
            adapter: adapter,
            sourceId: 'src_video_test',
            sourceVersionId: 'ver_video_test_v1',
            providerId: 'fixture',
            timedTextService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.calls, equals(0));
      expect(find.text('需要字幕'), findsWidgets);

      adapter.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
