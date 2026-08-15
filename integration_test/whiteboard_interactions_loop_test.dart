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
import 'package:integration_test/integration_test.dart';
import 'package:drift/native.dart';

import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('interactions → Drift → restart recovery → 500-card frames',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('w1_itest_');
    final dbFile = File('${dir.path}/w1_itest.sqlite');
    addTearDown(() {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {
        // The sqlite file may still be held by the engine on failure paths.
      }
    });

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final store = WhiteboardDriftStore(db);

    // ── Board data through the SHARED WRITE PATH (snapshot → store) ──
    final now = DateTime.now();
    final boardId = await store.createBoard(name: '交互验收板');
    final cards = [
      for (final (i, title) in ['验收卡 A', '验收卡 B', '验收卡 C'].indexed)
        CardContract(
          cardId: 'itest_card_$i',
          cardKind: CardKind.note,
          title: title,
          body: '交互验收卡 $i 正文',
          createdAt: now,
        ),
    ];
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
      cards: cards,
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
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: boardId,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await _waitFor(
      tester,
      () => find.text('交互验收板').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: 'canvas floating bar shows board name',
    );
    debugPrint('W1IT: canvas opened');

    // Screen geometry of the real window (logical px).
    final logicalSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
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
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
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
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
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
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
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
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    saved = await store.load(boardId);
    expect(saved.snapshot!.groups.first.collapsed, isTrue,
        reason: 'collapse state must persist');
    debugPrint('W1IT: group collapsed and persisted');

    // ── ⑥ Restart recovery via a second connection on the same file ──
    final reopened = AppDatabase.forTesting(NativeDatabase(dbFile));
    final reopenedStore = WhiteboardDriftStore(reopened);
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
    debugPrint('W1IT: restart recovery verified');
    await reopened.close();

    // ── ⑦ 500-card board: real-window frame data ──
    final perfBoardId = await store.createBoard(name: '帧率验收板');
    final perfCards = <CardContract>[];
    final perfItems = <BoardItem>[];
    for (int i = 0; i < 500; i++) {
      final row = i ~/ 20;
      final col = i % 20;
      perfCards.add(CardContract(
        cardId: 'perf_card_$i',
        cardKind: CardKind.note,
        title: 'Card $i',
        body: 'Performance card $i body.',
        tags: const ['perf'],
        createdAt: now,
      ));
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
      await store.save(
        perfBoardId,
        WhiteboardSnapshot(
          boards: [
            Board(
              boardId: perfBoardId,
              name: '帧率验收板',
              createdAt: now,
            ),
          ],
          cards: perfCards,
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
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await _waitFor(
      tester,
      () => find.text('帧率验收板').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: '500-card canvas opened',
    );
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
    await db.close();
  });
}
