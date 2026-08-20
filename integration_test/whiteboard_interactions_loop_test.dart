/// W1 interaction completion — real desktop window loop (hermetic).
///
/// Runs in a real Windows desktop window against a REAL Drift database on a
/// temp file, WITHOUT `app.main()` (no chat-app background services, so the
/// integration binding teardown stays clean). Exercises every new W1
/// interaction through the shared write path and verifies restart recovery
/// via a second connection on the same file, then collects real frame
/// timings on a 500-card board.
///
/// Run: flutter test integration_test/whiteboard_interactions_loop_test.dart -d windows
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' as gestures;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/native.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty)
          .take(30)
          .join(' | ');
      fail('timed out waiting for: $description\nvisible texts: $texts');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _waitForCanvasReady(WidgetTester tester, String description) =>
    _waitFor(
      tester,
      () =>
          find
              .byKey(const ValueKey('wb_canvas_chrome_launcher'))
              .evaluate()
              .isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
      timeout: const Duration(seconds: 15),
      description: description,
    );

Future<void> _openCanvasNavigation(WidgetTester tester) async {
  if (find.byKey(const ValueKey('wb_navigation_group')).evaluate().isEmpty) {
    await tester.tap(
      find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
  expect(find.byKey(const ValueKey('wb_navigation_group')), findsOneWidget);
}

Future<void> _openCanvasTools(WidgetTester tester) async {
  await _openCanvasNavigation(tester);
  if (find.byKey(const ValueKey('wb_action_tools')).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('画布工具'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
  expect(find.byKey(const ValueKey('wb_action_tools')), findsOneWidget);
  expect(find.byKey(const ValueKey('wb_view_tools')), findsOneWidget);
}

Future<void> _saveCanvas(WidgetTester tester) async {
  await _openCanvasTools(tester);
  await tester.tap(find.byTooltip('保存快照 (Ctrl+S)'));
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('interactions → Drift → restart recovery → 500-card frames',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('w1_itest_');
    final dbFile = File('${dir.path}/w1_itest.sqlite');

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    var dbOpen = true;
    AppDatabase? reopenedDb;
    var reopenedDbOpen = false;
    final store = WhiteboardDriftStore(db);
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: dir);
    addTearDown(() async {
      if (dbOpen) await db.close();
      if (reopenedDbOpen) await reopenedDb?.close();
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {
        // The sqlite file may still be held by the engine on failure paths.
      }
    });

    // ── Board data through the SHARED WRITE PATH (snapshot → store) ──
    final now = DateTime.now();
    final boardId = await store.createBoard(name: '交互验收板');
    for (final (i, title) in ['验收卡 A', '验收卡 B', '验收卡 C'].indexed) {
      await repository.createTextCard(
        cardId: 'itest_card_$i',
        title: title,
        body: '交互验收卡 $i 正文',
      );
    }
    final boardItems = [
      BoardItem(
        itemId: 'itest_item_a',
        boardId: boardId,
        cardId: 'itest_card_0',
        x: 0,
        y: 0,
        width: 140,
        height: 120,
      ),
      BoardItem(
        itemId: 'itest_item_b',
        boardId: boardId,
        cardId: 'itest_card_1',
        x: 160,
        y: 0,
        width: 140,
        height: 120,
      ),
      BoardItem(
        itemId: 'itest_item_c',
        boardId: boardId,
        cardId: 'itest_card_2',
        x: 320,
        y: 0,
        width: 140,
        height: 120,
      ),
    ];
    final snapshot = WhiteboardSnapshot(
      boards: [
        Board(boardId: boardId, name: '交互验收板', createdAt: now),
      ],
      boardItems: boardItems,
      groups: [
        BoardGroup(
          groupId: 'itest_group',
          boardId: boardId,
          name: '验收分组',
        ),
      ],
      groupMembers: const [
        GroupMember(groupId: 'itest_group', itemId: 'itest_item_a', order: 0),
        GroupMember(groupId: 'itest_group', itemId: 'itest_item_b', order: 1),
      ],
      edges: [
        BoardEdge(
          edgeId: 'itest_edge',
          boardId: boardId,
          fromItemId: 'itest_item_a',
          toItemId: 'itest_item_b',
          createdAt: now,
        ),
      ],
    );
    expect(await store.save(boardId, snapshot), isTrue,
        reason: 'shared write path must persist the fixture board');

    // ── Open the full-screen canvas through the production route screen ──
    final navigationRouter = GoRouter(
      initialLocation: AppRoutes.whiteboardCanvasPath(boardId),
      routes: [
        GoRoute(
          path: AppRoutes.whiteboard,
          builder: (_, __) => const Scaffold(
            key: ValueKey('w1_exit_target'),
            body: Center(child: Text('白板索引')),
          ),
        ),
        GoRoute(
          path: AppRoutes.whiteboardCanvas,
          builder: (_, state) => WhiteboardCanvasRouteScreen(
            boardId: state.pathParameters['boardId']!,
            store: store,
            cardRepository: repository,
          ),
        ),
      ],
    );
    addTearDown(navigationRouter.dispose);
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: navigationRouter),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await _waitForCanvasReady(tester, 'canvas launcher replaces loading state');
    expect(find.byKey(const ValueKey('wb_navigation_group')), findsNothing);
    expect(find.byKey(const ValueKey('wb_action_tools')), findsNothing);
    expect(find.byKey(const ValueKey('wb_view_tools')), findsNothing);
    expect(find.byKey(const ValueKey('wb_card_library_panel')), findsNothing);
    expect(find.text('交互验收板'), findsNothing);
    debugPrint('W1IT: canvas opened with all optional chrome retreated');

    await _openCanvasNavigation(tester);
    expect(find.text('交互验收板'), findsOneWidget);
    await _openCanvasTools(tester);
    debugPrint('W1IT: navigation and tools opened from launcher');

    // Screen geometry of the real window (logical px).
    final logicalSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final center = Offset(logicalSize.width / 2, logicalSize.height / 2);
    Offset toScreen(Offset canvas) => Offset(
          canvas.dx + center.dx,
          canvas.dy + center.dy,
        );
    final midAB = toScreen(const Offset(150, 60)); // edge midpoint (gap)
    final cCenter = toScreen(const Offset(390, 60)); // card C center

    // ── ① Keyboard: Ctrl+A selects all three cards ──
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('已选 3'), findsOneWidget);
    debugPrint('W1IT: Ctrl+A selected 3');

    // ── ② Arrow nudge + save ──
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _saveCanvas(tester);
    var saved = await store.load(boardId);
    expect(
      saved.snapshot!.boardItems
          .firstWhere((i) => i.itemId == 'itest_item_a')
          .x,
      equals(8),
      reason: 'arrow nudge must persist via the shared write path',
    );
    debugPrint('W1IT: nudge persisted (x=8)');

    // ── ③ Rotation handle ──
    await tester.tapAt(toScreen(const Offset(70, 60))); // select card A
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final rotateHandle = find.byKey(const Key('wb_rotate_itest_item_a'));
    expect(rotateHandle, findsOneWidget);
    await tester.drag(rotateHandle, const Offset(0, 90));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _saveCanvas(tester);
    saved = await store.load(boardId);
    final rotated = saved.snapshot!.boardItems
        .firstWhere((i) => i.itemId == 'itest_item_a');
    expect(rotated.rotation, greaterThan(45),
        reason: 'rotation handle drag must persist');
    debugPrint('W1IT: rotation persisted (${rotated.rotation})');

    // ── ④ Edge endpoint retarget ──
    await tester.tapAt(midAB); // select the edge
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.drag(
      find.byKey(const Key('wb_edge_itest_edge_to')),
      cCenter - toScreen(const Offset(230, 60)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _saveCanvas(tester);
    saved = await store.load(boardId);
    expect(
      saved.snapshot!.edges.first.toItemId,
      equals('itest_item_c'),
      reason: 'edge endpoint drag must persist',
    );
    debugPrint('W1IT: edge retargeted to card C');

    // ── ⑤ Group collapse ──
    await tester.tap(find.text('验收分组'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('验收卡 A'), findsNothing,
        reason: 'collapsed group hides members on the real window');
    await _saveCanvas(tester);
    saved = await store.load(boardId);
    expect(saved.snapshot!.groups.first.collapsed, isTrue,
        reason: 'collapse state must persist');
    debugPrint('W1IT: group collapsed and persisted');

    // ── ⑥ Exit, close the first connection, and reopen the window ──
    await _openCanvasNavigation(tester);
    await tester.tap(find.byTooltip('退出白板 (Esc)'));
    await _waitFor(
      tester,
      () => find.byKey(const ValueKey('w1_exit_target')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: 'save and exit to the whiteboard index',
    );
    debugPrint('W1IT: exit saved and reached whiteboard index');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await db.close();
    dbOpen = false;

    reopenedDb = AppDatabase.forTesting(NativeDatabase(dbFile));
    reopenedDbOpen = true;
    final reopenedStore = WhiteboardDriftStore(reopenedDb);
    final reopenedRepository = UnifiedCardRepository(
      db: reopenedDb,
      whiteboardRoot: dir,
    );
    final afterRestart = await reopenedStore.load(boardId);
    expect(afterRestart.isSuccess, isTrue);
    final rs = afterRestart.snapshot!;
    final rItemA = rs.boardItems.firstWhere((i) => i.itemId == 'itest_item_a');
    expect(rItemA.x, equals(8), reason: 'nudge survives restart');
    expect(rItemA.rotation, greaterThan(45),
        reason: 'rotation survives restart');
    expect(rs.edges.first.toItemId, equals('itest_item_c'),
        reason: 'retarget survives restart');
    expect(rs.groups.first.collapsed, isTrue,
        reason: 'collapse survives restart');
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          key: UniqueKey(),
          boardId: boardId,
          store: reopenedStore,
          cardRepository: reopenedRepository,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await _waitForCanvasReady(
      tester,
      'restarted canvas launcher replaces loading state',
    );
    expect(find.byKey(const ValueKey('wb_navigation_group')), findsNothing);
    await _openCanvasNavigation(tester);
    expect(find.text('交互验收板'), findsOneWidget);
    expect(find.text('验收卡 A'), findsNothing,
        reason: 'collapsed members stay hidden after the window reopens');
    expect(find.text('验收卡 C'), findsOneWidget);
    debugPrint('W1IT: restart recovery verified in reopened window');

    // ── ⑦ 500-card board: real-window frame data ──
    final perfBoardId = await reopenedStore.createBoard(name: '帧率验收板');
    final perfItems = <BoardItem>[];
    for (int i = 0; i < 500; i++) {
      final row = i ~/ 20;
      final col = i % 20;
      await reopenedRepository.createTextCard(
        cardId: 'perf_card_$i',
        title: 'Card $i',
        body: 'Performance card $i body.',
        tags: const ['perf'],
      );
      perfItems.add(BoardItem(
        itemId: 'perf_item_$i',
        boardId: perfBoardId,
        cardId: 'perf_card_$i',
        x: 100.0 + col * 150,
        y: 100.0 + row * 130,
        width: 140,
        height: 110,
        zIndex: i,
      ));
    }
    expect(
      await reopenedStore.save(
        perfBoardId,
        WhiteboardSnapshot(
          boards: [
            Board(
              boardId: perfBoardId,
              name: '帧率验收板',
              createdAt: now,
            ),
          ],
          boardItems: perfItems,
        ),
      ),
      isTrue,
    );

    // A fresh key forces a new route-screen state (the previous one keeps
    // the interaction board loaded otherwise).
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          key: UniqueKey(),
          boardId: perfBoardId,
          store: reopenedStore,
          cardRepository: reopenedRepository,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await _waitForCanvasReady(
      tester,
      '500-card canvas launcher replaces loading state',
    );
    expect(find.text('帧率验收板'), findsNothing);
    debugPrint('W1IT: 500-card canvas opened');

    final timings = <FrameTiming>[];
    void timingsCallback(List<FrameTiming> batch) => timings.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(timingsCallback);
    try {
      // Pan (right-drag) + zoom (scroll) bursts on the real window.
      for (var i = 0; i < 20; i++) {
        final g = await tester.startGesture(
          center + const Offset(120, 80),
          kind: ui.PointerDeviceKind.mouse,
          buttons: gestures.kSecondaryMouseButton,
        );
        await g.moveBy(const Offset(-60, -40));
        await tester.pump(const Duration(milliseconds: 16));
        await g.up();
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 10; i++) {
        await tester.sendEventToBinding(
          gestures.PointerScrollEvent(
            position: center,
            scrollDelta: Offset(0, i.isEven ? -120 : 120),
            kind: ui.PointerDeviceKind.mouse,
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(timingsCallback);
    }

    final frames = timings.length;
    final avgBuildMs = timings.isEmpty
        ? 0.0
        : timings
                .map((t) => t.buildDuration.inMicroseconds)
                .reduce((a, b) => a + b) /
            frames /
            1000;
    final avgRasterMs = timings.isEmpty
        ? 0.0
        : timings
                .map((t) => t.rasterDuration.inMicroseconds)
                .reduce((a, b) => a + b) /
            frames /
            1000;
    debugPrint(
        'W1IT: W1FRAME frames=$frames avgBuildMs=$avgBuildMs avgRasterMs=$avgRasterMs');
    final itBinding = IntegrationTestWidgetsFlutterBinding.instance;
    final reportData = itBinding.reportData;
    if (reportData != null) {
      reportData['w1_500_frames'] = frames;
      reportData['w1_500_avg_build_ms'] = avgBuildMs;
      reportData['w1_500_avg_raster_ms'] = avgRasterMs;
    } else {
      debugPrint('W1IT: reportData unavailable — values printed above');
    }
    expect(frames, greaterThan(0),
        reason: 'real-window pan/zoom must produce frames');

    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException();
    debugPrint('W1IT: ALL DONE');
    await reopenedDb.close();
    reopenedDbOpen = false;
  });
}
