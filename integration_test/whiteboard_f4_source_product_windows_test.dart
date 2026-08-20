import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/video/windows_youtube_player_adapter.dart';
import 'package:memex/domain/whiteboard/video/youtube_timedtext_service.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/source_study_screen.dart';
import 'package:memex/ui/whiteboard/video/session_store.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Windows native YouTube product loop: preview, play, subtitles, annotation, restart',
      (tester) async {
    final root = await Directory.systemTemp.createTemp('f4_windows_product_');
    final dbFile = File('${root.path}${Platform.pathSeparator}cards.sqlite');
    late AppDatabase db;
    late UnifiedCardRepository repository;
    const youtubeUrl = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';

    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final service = LinkIngestionService(repository: repository);
    final preview = await service.ingestUrl(youtubeUrl, createCard: false);
    final source = preview.result.source!;
    final sourceId = source.sourceId;
    await createVideoSessionStore(sourceId: sourceId).clear();
    addTearDown(() async {
      await createVideoSessionStore(sourceId: sourceId).clear();
      await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    expect(await repository.getSource(sourceId), isNull);
    expect(await repository.listCards(), isEmpty);
    final committed = await service.commitResult(preview.result);
    expect(committed.cardCreated, isTrue);
    expect(await repository.getSource(sourceId), isNotNull);

    final timedTextService = _UnavailableTimedTextService();
    final adapter = WindowsYouTubePlayerAdapter();
    await tester.pumpWidget(MaterialApp(
      home: SourceStudyScreen(
        sourceId: sourceId,
        repository: repository,
        adapterFactory: (_) => adapter,
        timedTextService: timedTextService,
      ),
    ));
    await _pumpUntil(tester, () => adapter.isReady);
    await _pumpUntilFinder(tester, find.text('导入字幕'));
    expect(find.byType(VideoStudyScreen), findsOneWidget);
    expect(find.text('Fixture Player'), findsNothing);
    expect(timedTextService.calls, 1);
    expect(find.textContaining('当前视频没有可用平台字幕'), findsOneWidget);

    await tester.tap(find.text('导入字幕'));
    await tester.pumpAndSettle();
    expect(find.text('选择 SRT / VTT 文件'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, _windowsVtt);
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();
    expect(find.text('Windows cue one'), findsOneWidget);
    expect(find.text('Windows cue two'), findsOneWidget);

    final duration = await adapter.durationMs();
    expect(duration, isNotNull);
    expect(duration!, greaterThan(25000));
    await adapter.seekTo(20000);
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(await adapter.currentPositionMs(), inInclusiveRange(18000, 24000));
    await adapter.setMuted(true);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    final beforePlay = await adapter.currentPositionMs();
    var afterPlay = beforePlay;
    for (var attempt = 0; attempt < 3 && afterPlay <= beforePlay; attempt++) {
      await adapter.play();
      await _pumpFor(tester, const Duration(seconds: 3));
      afterPlay = await adapter.currentPositionMs();
    }
    expect(afterPlay, greaterThan(beforePlay),
        reason: 'muted YouTube playback must advance after bounded buffering');

    await tester.tap(find.text('Windows cue one'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(await adapter.currentPositionMs(), inInclusiveRange(8000, 15000));
    final activeCue = tester.widget<Text>(find.text('Windows cue one'));
    expect(
      activeCue.style?.color,
      DesktopWorkspaceTokens.lieflatPalm.textPrimary,
    );

    await tester.tap(
      find.byKey(ValueKey('annotate_cue_${sourceId}_0')),
    );
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).at(0), 'Windows 原生标注');
    await tester.enterText(find.byType(TextField).at(1), '来自真实 WebView2 播放位置');
    await tester.ensureVisible(find.text('保存标注'));
    await tester.tap(find.text('保存标注'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    final annotations = await repository.listCards(
      const CardLibraryQuery(kinds: {CardKind.annotation}),
    );
    expect(annotations, hasLength(1));
    expect(annotations.single.card.sourceId, sourceId);

    await adapter.pause();
    final savedPosition = await adapter.currentPositionMs();
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final restartedAdapter = WindowsYouTubePlayerAdapter();
    await tester.pumpWidget(MaterialApp(
      home: SourceStudyScreen(
        sourceId: sourceId,
        repository: repository,
        adapterFactory: (_) => restartedAdapter,
        timedTextService: timedTextService,
      ),
    ));
    await _pumpUntil(tester, () => restartedAdapter.isReady);
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(
      await restartedAdapter.currentPositionMs(),
      inInclusiveRange(savedPosition - 3000, savedPosition + 3000),
    );
    final restored = await repository.listCards(
      const CardLibraryQuery(kinds: {CardKind.annotation}),
    );
    expect(restored, hasLength(1));
    expect(find.text('Windows 原生标注'), findsWidgets);
    expect(timedTextService.calls, 2,
        reason: 'Windows retries platform subtitles for each real study load');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class _UnavailableTimedTextService extends YouTubeTimedTextService {
  int calls = 0;

  @override
  Future<YouTubeTimedTextResult> fetchForVideo(
    String videoIdOrUrl, {
    required String sourceId,
    String? sourceVersionId,
  }) async {
    calls++;
    return const YouTubeTimedTextResult(
      error: '当前视频没有可用平台字幕；请导入 SRT 或 VTT',
    );
  }
}

const String _windowsVtt = '''WEBVTT

00:10.000 --> 00:18.000
Windows cue one

00:20.000 --> 00:28.000
Windows cue two
''';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 120; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for Windows WebView2 YouTube player');
}

Future<void> _pumpUntilFinder(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    if (tester.any(finder)) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pump();
}
