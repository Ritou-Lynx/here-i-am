import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory_stub.dart';
import 'package:memex/ui/whiteboard/video/session_store.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';

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

class _FakeWindowsBilibiliAdapter extends WindowsBilibiliPlayerAdapter {
  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}
}

void _useDesktopSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('VideoStudyScreen shows player and subtitle dock',
      (tester) async {
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

    // Dock header should show subtitle status.
    expect(find.text('字幕 / 时间轴'), findsOneWidget);
    expect(find.textContaining('用户导入'), findsOneWidget);

    // Player controls visible.
    expect(find.byIcon(Icons.play_arrow), findsWidgets);

    adapter.dispose();
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

  testWidgets('splitter changes real layout and persists the adjusted ratio',
      (tester) async {
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

  testWidgets('restored bottom dock ratio controls the restarted layout',
      (tester) async {
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

  testWidgets('narrow desktop automatically moves the dock to the bottom',
      (tester) async {
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

  testWidgets('player and dock minimum sizes hold at 1024 by 720',
      (tester) async {
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

  testWidgets('Bilibili, Xiaohongshu and unknown providers stay link-only',
      (tester) async {
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

  testWidgets('Fixture surface icon follows paused and playing state',
      (tester) async {
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

  testWidgets('NeedsSubtitle state shows import prompt when no track',
      (tester) async {
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

  testWidgets('Windows Bilibili is playable in-app but time-study limited',
      (tester) async {
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
      find.byKey(const ValueKey('video_annotate_current_position')),
      findsNothing,
      reason: 'without readable current time the UI must not forge anchors',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('point annotation at current time does not depend on subtitles',
      (tester) async {
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
    expect(find.byKey(const ValueKey('video_annotation_editor')),
        findsOneWidget);
    expect(find.text('在 00:07 创建标注'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '无字幕点标注');
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
    await tester.tap(find.byKey(const ValueKey('video_begin_range_annotation')));
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
    expect(find.text('无字幕区间标注'), findsOneWidget);
    await restartedAdapter.seekTo(50000);
    await tester.pump();
    await tester.tap(find.text('无字幕区间标注'));
    await tester.pumpAndSettle();
    expect(await restartedAdapter.currentPositionMs(), 10000);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

  testWidgets('timeline seek keeps the real player position in sync',
      (tester) async {
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

    final timeline = find.byKey(
      const ValueKey('video_timeline_anchor_bar'),
    );
    final rect = tester.getRect(timeline);
    await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
    await tester.pumpAndSettle();

    expect(await adapter.currentPositionMs(), closeTo(100000, 1000));

    await tester.pumpWidget(const SizedBox.shrink());
    adapter.dispose();
  });

  testWidgets('Annotation flow creates card and shows confirmation',
      (tester) async {
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
    expect(await adapter.currentPositionMs(), equals(2000));

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

    Widget buildYoutubeScreen({
      required YouTubeTimedTextService service,
    }) {
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

      expect(service.calls, equals(1),
          reason: 'auto-fetch ran for YouTube on Windows');
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
    });

    testWidgets('auto-fetch failure shows honest "需要字幕" with reason',
        (tester) async {
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
      expect(
        find.text('无字幕轨：该视频没有向平台播放器公开 CC 字幕'),
        findsOneWidget,
      );
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
