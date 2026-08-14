import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';
import 'package:memex/ui/whiteboard/video/widgets/subtitle_list_view.dart';
import 'package:memex/ui/whiteboard/video/widgets/context_dock.dart';

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

void main() {
  testWidgets('VideoStudyScreen shows player and subtitle dock', (tester) async {
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

  testWidgets('NeedsSubtitle state shows import prompt when no track', (tester) async {
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

  testWidgets('Annotation flow creates card and shows confirmation', (tester) async {
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

    // Find the annotation square next to a cue — tap it.
    final annotateButton = find.byKey(const ValueKey('annotate_cue_1'));
    expect(annotateButton, findsOneWidget);

    await tester.tap(annotateButton);
    await tester.pumpAndSettle();

    // Pending annotation should show the editor.
    expect(find.text('时间标注'), findsOneWidget);
    expect(find.text('保存标注'), findsOneWidget);

    // Enter title and body.
    await tester.enterText(find.byType(TextField).first, '副歌观察');
    await tester.enterText(find.byType(TextField).at(1), '这段副歌很有记忆点');

    // Save.
    await tester.ensureVisible(find.text('保存标注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();

    // Confirmation shown.
    expect(find.text('标注已保存'), findsOneWidget);

    // Let the auto-dismiss timer fire so no timers are pending at teardown.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // Confirmation dismissed, back to subtitle list.
    expect(find.text('标注已保存'), findsNothing);

    adapter.dispose();
  });
}