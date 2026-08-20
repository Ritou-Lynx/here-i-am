/// Widget tests for the W1 whiteboard canvas 鈥?real Flutter rendering
/// verification of core interactions.
///
/// These tests pump the actual [WhiteboardCanvasScreen] and simulate pointer
/// gestures (tap, drag, scroll), verifying selection, move, undo/redo,
/// delete, zoom, and save/restore against the real widget tree.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show PointerDeviceKind;

import 'package:flutter/gestures.dart' as gestures show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart';

WhiteboardSnapshot _singleCardSnapshot() {
  final now = DateTime(2026, 8, 15);
  return WhiteboardSnapshot(
    boards: [
      Board(
        boardId: 'board_widget',
        name: 'Widget Test Board',
        createdAt: now,
      ),
    ],
    cards: [
      CardContract(
        cardId: 'card_a',
        cardKind: CardKind.note,
        title: 'Card A',
        body: 'Body of card A for widget testing.',
        createdAt: now,
      ),
      CardContract(
        cardId: 'card_b',
        cardKind: CardKind.note,
        title: 'Card B',
        body: 'Body of card B.',
        createdAt: now,
      ),
    ],
    boardItems: [
      const BoardItem(
        itemId: 'item_a',
        boardId: 'board_widget',
        cardId: 'card_a',
        x: 100,
        y: 100,
        width: 200,
        height: 120,
        zIndex: 1,
      ),
      const BoardItem(
        itemId: 'item_b',
        boardId: 'board_widget',
        cardId: 'card_b',
        x: 360,
        y: 100,
        width: 200,
        height: 120,
        zIndex: 2,
      ),
    ],
  );
}

Future<void> _pumpCanvas(
    WidgetTester tester, WhiteboardSnapshot snapshot) async {
  final vm = WhiteboardCanvasViewModel(
    initialSnapshot: snapshot,
    boardId: snapshot.boards.isNotEmpty ? snapshot.boards.first.boardId : 'b',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WhiteboardCanvasScreen(
          viewModel: vm,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCanvasTools(WidgetTester tester) async {
  if (find.byKey(const Key('wb_navigation_group')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('wb_canvas_chrome_launcher')));
    await tester.pumpAndSettle();
  }
  if (find.byKey(const Key('wb_action_tools')).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('画布工具'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('WhiteboardCanvasScreen widget', () {
    testWidgets('renders card titles on the canvas', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      expect(find.text('Card A'), findsOneWidget);
      expect(find.text('Card B'), findsOneWidget);
    });

    testWidgets('tap on card selects it', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      // Tap directly on the card's title text
      await tester.tap(find.text('Card A'));
      await tester.pumpAndSettle();

      expect(_getVm(tester).selection.length, 1);
    });

    testWidgets('drag on card moves it and updates snapshot', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());
      final vm = _getVm(tester);

      final before =
          vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a');

      // Drag card A by (100, 60) — start at the card center.
      await tester.drag(
        find.text('Card A'),
        const Offset(100, 60),
      );
      await tester.pumpAndSettle();

      final after =
          vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a');
      expect(after.x, greaterThan(before.x + 50));
      expect(after.y, greaterThan(before.y + 30));
      // Position must have changed by the full drag minus touch slop.
      expect(after.x, closeTo(before.x + 100, 25));
    });

    testWidgets('marquee selection selects multiple cards', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      // Compute canvas positions of both card rects on screen.
      final a = tester.getRect(find.text('Card A'));
      final b = tester.getRect(find.text('Card B'));

      // Marquee from top-left of card A to bottom-right of card B.
      final gesture =
          await tester.startGesture(a.topLeft - const Offset(20, 20));
      await gesture.moveTo(b.bottomRight + const Offset(20, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_getVm(tester).selection.length, 2);
    });

    testWidgets('delete removes BoardItem but not Card', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      // Select card A
      await tester.tap(find.text('Card A'));
      await tester.pumpAndSettle();

      final vm = _getVm(tester);
      final cardCount = vm.exportForSave().cards.length;

      await _openCanvasTools(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(vm.exportForSave().boardItems.any((i) => i.itemId == 'item_a'),
          isFalse);
      // Card NOT deleted
      expect(vm.exportForSave().cards.length, equals(cardCount));
    });

    testWidgets('undo restores deleted BoardItem', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      await tester.tap(find.text('Card A'));
      await tester.pumpAndSettle();
      await _openCanvasTools(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      final vm = _getVm(tester);
      expect(vm.exportForSave().boardItems.any((i) => i.itemId == 'item_a'),
          isFalse);

      // Undo
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();

      expect(vm.exportForSave().boardItems.any((i) => i.itemId == 'item_a'),
          isTrue);
    });

    testWidgets('scroll wheel zooms viewport', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());
      final vm = _getVm(tester);
      final beforeZoom = vm.viewport.zoom;

      // Simulate scroll up (zoom in)
      await tester.sendEventToBinding(
        const gestures.PointerScrollEvent(
          position: Offset(400, 300),
          scrollDelta: Offset(0, -100),
          kind: ui.PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();

      expect(vm.viewport.zoom, greaterThan(beforeZoom));
    });

    testWidgets('bring to front raises zIndex', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      await tester.tap(find.text('Card A'));
      await tester.pumpAndSettle();
      await _openCanvasTools(tester);
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();

      final vm = _getVm(tester);
      final itemA =
          vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a');
      final itemB =
          vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_b');
      expect(itemA.zIndex, greaterThan(itemB.zIndex));
    });

    testWidgets('group from selection creates a group', (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      // Select both via marquee spanning both cards
      final a = tester.getRect(find.text('Card A'));
      final b = tester.getRect(find.text('Card B'));
      final gesture =
          await tester.startGesture(a.topLeft - const Offset(20, 20));
      await gesture.moveTo(b.bottomRight + const Offset(20, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await _openCanvasTools(tester);
      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();

      final vm = _getVm(tester);
      expect(vm.exportForSave().groups.length, equals(1));
      expect(vm.exportForSave().groupMembers.length, equals(2));
    });

    testWidgets('full-screen canvas has no persistent top bar by default',
        (tester) async {
      await _pumpCanvas(tester, _singleCardSnapshot());

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byKey(const Key('wb_navigation_group')), findsNothing);
      expect(find.byKey(const Key('wb_action_tools')), findsNothing);
      expect(find.byKey(const Key('wb_view_tools')), findsNothing);
      expect(find.byKey(const Key('wb_card_library_panel')), findsNothing);
      expect(
          find.byKey(const Key('wb_canvas_chrome_launcher')), findsOneWidget);
    });
  });

  group('WhiteboardSnapshotStore widget-level restore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('w1_widget_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('save then restore preserves moved positions', (tester) async {
      final store = WhiteboardSnapshotStore(tempDir.path);
      const boardId = 'board_widget';

      // Save original
      store.save(boardId, _singleCardSnapshot());

      // Restore into ViewModel
      final restored = store.load(boardId);
      expect(restored.isSuccess, isTrue);

      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: restored.snapshot!,
        boardId: boardId,
      );

      // Verify a round-trip keeps the item positions
      final item =
          vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a');
      expect(item.x, equals(100));
      expect(item.y, equals(100));

      // Move, then save, then restore again — new position preserved
      vm.moveItems({
        'item_a': const math.Point(40.0, 25.0),
      });
      store.save(boardId, vm.exportForSave());

      final restored2 = store.load(boardId);
      expect(restored2.isSuccess, isTrue);
      final itemAfter = restored2.snapshot!.boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(itemAfter.x, equals(140));
      expect(itemAfter.y, equals(125));
    });

    testWidgets('corrupted snapshot load reports failure without crash',
        (tester) async {
      final file = File('${tempDir.path}/whiteboard_corrupt_board.json');
      file.writeAsStringSync('{{{ not json');

      final store = WhiteboardSnapshotStore(tempDir.path);
      final result = store.load('corrupt_board');
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });
  });
}

WhiteboardCanvasViewModel _getVm(WidgetTester tester) {
  final screen = tester.widget<WhiteboardCanvasScreen>(
    find.byType(WhiteboardCanvasScreen),
  );
  return screen.viewModel;
}
