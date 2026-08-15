/// W1 interaction completion tests — keyboard shortcuts, card-library
/// drag & drop, BoardTargetPicker, group collapse, edge endpoint editing,
/// rotation handle, and Huabu-style single-undo-step logical actions.
library;

import 'dart:math' as math;
import 'dart:ui' as ui show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/interactions/ui_intent.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

WhiteboardSnapshot _snapshot({
  bool withEdge = false,
  bool withGroup = false,
  bool withExtraCard = false,
  bool withOtherBoard = false,
}) {
  final now = DateTime(2026, 8, 15);
  return WhiteboardSnapshot(
    boards: [
      Board(
        boardId: 'board_widget',
        name: 'Widget Test Board',
        createdAt: now,
      ),
      if (withOtherBoard)
        Board(
          boardId: 'board_other',
          name: 'Other Board',
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
      if (withEdge || withExtraCard)
        CardContract(
          cardId: 'card_c',
          cardKind: CardKind.note,
          title: 'Card C',
          body: 'Body of card C.',
          createdAt: now,
        ),
    ],
    boardItems: [
      const BoardItem(
        itemId: 'item_a',
        boardId: 'board_widget',
        cardId: 'card_a',
        x: 0,
        y: 0,
        width: 140,
        height: 120,
        zIndex: 1,
      ),
      const BoardItem(
        itemId: 'item_b',
        boardId: 'board_widget',
        cardId: 'card_b',
        x: 160,
        y: 0,
        width: 140,
        height: 120,
        zIndex: 2,
      ),
      if (withEdge)
        const BoardItem(
          itemId: 'item_c',
          boardId: 'board_widget',
          cardId: 'card_c',
          x: 320,
          y: 0,
          width: 140,
          height: 120,
          zIndex: 3,
        ),
    ],
    groups: [
      if (withGroup)
        const BoardGroup(
          groupId: 'group_g1',
          boardId: 'board_widget',
          name: '测试分组',
        ),
    ],
    groupMembers: [
      if (withGroup) ...[
        const GroupMember(groupId: 'group_g1', itemId: 'item_a', order: 0),
        const GroupMember(groupId: 'group_g1', itemId: 'item_b', order: 1),
      ],
    ],
    edges: [
      if (withEdge)
        BoardEdge(
          edgeId: 'edge_e1',
          boardId: 'board_widget',
          fromItemId: 'item_a',
          toItemId: 'item_b',
          createdAt: now,
        ),
    ],
  );
}

Future<WhiteboardCanvasViewModel> _pumpCanvas(
  WidgetTester tester,
  WhiteboardSnapshot snapshot, {
  VoidCallback? onExit,
}) async {
  final vm = WhiteboardCanvasViewModel(
    initialSnapshot: snapshot,
    boardId: snapshot.boards.isNotEmpty ? snapshot.boards.first.boardId : 'b',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WhiteboardCanvasScreen(
          viewModel: vm,
          onExit: onExit,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return vm;
}

Future<void> _sendShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (control) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pumpAndSettle();
}

void main() {
  group('keyboard shortcuts', () {
    testWidgets('Ctrl+Z undoes and Ctrl+Y redoes a move', (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot());
      vm.moveItems({'item_a': const math.Point(50, 0)});
      await tester.pumpAndSettle();
      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(50),
      );

      await _sendShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(0),
      );

      await _sendShortcut(tester, LogicalKeyboardKey.keyY, control: true);
      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(50),
      );
    });

    testWidgets('Ctrl+Shift+Z also redoes', (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot());
      vm.moveItems({'item_a': const math.Point(50, 0)});
      await tester.pumpAndSettle();

      await _sendShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
      await _sendShortcut(tester,
          LogicalKeyboardKey.keyZ, control: true, shift: true);
      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(50),
      );
    });

    testWidgets('Ctrl+A selects all and Del deletes BoardItems only',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot());
      expect(find.textContaining('已选'), findsNothing);

      await _sendShortcut(tester, LogicalKeyboardKey.keyA, control: true);
      expect(find.textContaining('已选 2'), findsOneWidget);

      final cardCount = vm.exportForSave().cards.length;
      await _sendShortcut(tester, LogicalKeyboardKey.delete);
      expect(vm.exportForSave().boardItems, isEmpty);
      expect(vm.exportForSave().cards.length, equals(cardCount));
    });

    testWidgets('arrow keys nudge the selection by 8 canvas px, one undo step',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot());
      await tester.tap(find.text('Card A'));
      await tester.pumpAndSettle();

      await _sendShortcut(tester, LogicalKeyboardKey.arrowRight);
      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(8),
      );

      // The nudge is exactly one undo step.
      await _sendShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(0),
      );
    });

    testWidgets('Esc exits the board', (tester) async {
      var exited = false;
      await _pumpCanvas(
        tester,
        _snapshot(),
        onExit: () => exited = true,
      );
      await _sendShortcut(tester, LogicalKeyboardKey.escape);
      expect(exited, isTrue);
    });
  });

  group('card-library drag & drop', () {
    testWidgets('dragging a library card onto the canvas places it there',
        (tester) async {
      // card_c exists in the library but is NOT placed on the board.
      final vm = await _pumpCanvas(tester, _snapshot(withExtraCard: true));
      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Card C'), findsOneWidget);
      final rowRect =
          tester.getRect(find.byKey(const Key('wb_lib_row_card_c')));

      // Mouse drag (Draggable uses an immediate recognizer for mouse).
      await tester.drag(
        find.text('Card C'),
        const Offset(450, 250),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final item = vm.exportForSave().boardItems
          .firstWhere((i) => i.cardId == 'card_c');
      expect(item.boardId, equals('board_widget'));
      // dropX - screenCenterX - grabOffsetX = 450 - 400 + rowRect.left
      expect(item.x, closeTo(rowRect.left + 50, 10));
      expect(item.y, closeTo(rowRect.top - 50, 10));
      expect(vm.selection.isSelected(item.itemId), isTrue);
    });
  });

  group('BoardTargetPicker', () {
    testWidgets('opens from the library row and places into another board',
        (tester) async {
      final vm =
          await _pumpCanvas(tester, _snapshot(withExtraCard: true, withOtherBoard: true));
      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();

      final rowButton = find.descendant(
        of: find.byKey(const Key('wb_lib_row_card_c')),
        matching: find.byIcon(Icons.space_dashboard_outlined),
      );
      await tester.tap(rowButton);
      await tester.pumpAndSettle();

      expect(find.text('放入白板'), findsOneWidget);
      expect(find.text('Other Board'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);

      await tester.tap(find.text('Other Board'));
      await tester.pumpAndSettle();

      final item = vm.exportForSave().boardItems
          .firstWhere((i) => i.cardId == 'card_c');
      expect(item.boardId, equals('board_other'));
      expect(find.textContaining('已放入白板「Other Board」'), findsOneWidget);
    });

    testWidgets('search filters boards and empty result is honest',
        (tester) async {
      await _pumpCanvas(tester, _snapshot(withExtraCard: true, withOtherBoard: true));
      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byKey(const Key('wb_lib_row_card_c')),
        matching: find.byIcon(Icons.space_dashboard_outlined),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的白板，新建一个吧'), findsOneWidget);
      expect(find.text('Other Board'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'other');
      await tester.pumpAndSettle();
      expect(find.text('Other Board'), findsOneWidget);
      expect(find.text('当前'), findsNothing,
          reason: 'the current board row is filtered out by the search');
    });

    testWidgets('新建白板 creates the board and places the card into it',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot(withExtraCard: true));
      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byKey(const Key('wb_lib_row_card_c')),
        matching: find.byIcon(Icons.space_dashboard_outlined),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('新建白板'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '新板');
      await tester.tap(find.text('创建并放入'));
      await tester.pumpAndSettle();

      final snapshot = vm.exportForSave();
      final board = snapshot.boards.firstWhere((b) => b.name == '新板');
      final item =
          snapshot.boardItems.firstWhere((i) => i.cardId == 'card_c');
      expect(item.boardId, equals(board.boardId));
    });
  });

  group('group collapse / expand', () {
    testWidgets('tap toggles collapse, hides members, survives in snapshot',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot(withGroup: true));
      expect(find.text('Card A'), findsOneWidget);
      expect(find.text('Card B'), findsOneWidget);

      // The group title chip sits above the member cards; tapping it toggles.
      await tester.tap(find.text('测试分组'));
      await tester.pumpAndSettle();

      expect(vm.exportForSave().groups.first.collapsed, isTrue);
      expect(find.text('Card A'), findsNothing,
          reason: 'collapsed group hides its member cards');
      expect(find.text('Card B'), findsNothing);
      expect(find.text('2 张卡片'), findsOneWidget);

      await tester.tap(find.text('测试分组'));
      await tester.pumpAndSettle();

      expect(vm.exportForSave().groups.first.collapsed, isFalse);
      expect(find.text('Card A'), findsOneWidget);
      expect(find.text('Card B'), findsOneWidget);
    });

    testWidgets('collapsing clears selection of hidden members',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot(withGroup: true));
      // Select both cards via marquee over their area.
      final a = tester.getRect(find.text('Card A'));
      final b = tester.getRect(find.text('Card B'));
      final gesture =
          await tester.startGesture(a.topLeft - const Offset(20, 20));
      await gesture.moveTo(b.bottomRight + const Offset(20, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(vm.selection.length, equals(2));

      await tester.tap(find.text('测试分组'));
      await tester.pumpAndSettle();
      expect(vm.selection.isEmpty, isTrue);
    });
  });

  group('edge endpoint editing', () {
    testWidgets('click near an edge selects it, drag endpoint retargets it',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot(withEdge: true));

      // Screen-space (window 800×600, screenCenter 400,300, zoom 1):
      // card A rect (400,300)-(540,420) center (470,360); card B (540,300)-
      // (680,420) center (630,360); edge midpoint (550,360) — in the 20px
      // gap between the cards.
      await tester.tapAt(const Offset(550, 360));
      await tester.pumpAndSettle();
      expect(vm.selectedEdgeId, equals('edge_e1'));

      // Drag the "to" handle (630,360) onto card C's center (790,360).
      await tester.drag(
        find.byKey(const Key('wb_edge_edge_e1_to')),
        const Offset(160, 0),
      );
      await tester.pumpAndSettle();

      expect(vm.exportForSave().edges.first.toItemId, equals('item_c'));
      expect(vm.exportForSave().edges.first.fromItemId, equals('item_a'));
    });

    testWidgets('dropping an endpoint on empty canvas leaves the edge intact',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot(withEdge: true));
      await tester.tapAt(const Offset(550, 360));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('wb_edge_edge_e1_from')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      expect(vm.exportForSave().edges.first.fromItemId, equals('item_a'));
      expect(vm.exportForSave().edges.first.toItemId, equals('item_b'));
    });

    testWidgets('Del removes the selected edge', (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot(withEdge: true));
      await tester.tapAt(const Offset(550, 360));
      await tester.pumpAndSettle();

      await _sendShortcut(tester, LogicalKeyboardKey.delete);
      expect(vm.exportForSave().edges, isEmpty);
    });
  });

  group('rotation handle', () {
    testWidgets('dragging the handle rotates the card; undo restores it',
        (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot());
      await tester.tap(find.text('Card A'));
      await tester.pumpAndSettle();

      final handle = find.byKey(const Key('wb_rotate_item_a'));
      expect(handle, findsOneWidget);
      // Handle sits above the card; dragging straight down yields ~90°.
      await tester.drag(handle, const Offset(0, 80));
      await tester.pumpAndSettle();

      final rotated = vm.exportForSave().boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(rotated.rotation, closeTo(90, 8));

      await _sendShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
      final restored = vm.exportForSave().boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(restored.rotation, equals(0));
    });
  });

  group('single undo step per logical action', () {
    testWidgets('one card drag = one undo step', (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot());
      await tester.drag(find.text('Card A'), const Offset(120, 40));
      await tester.pumpAndSettle();

      final moved = vm.exportForSave().boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(moved.x, greaterThan(90));

      await _sendShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
      final restored = vm.exportForSave().boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(restored.x, equals(0),
          reason: 'a whole drag gesture must be exactly one undo step');
    });

    testWidgets('one resize drag = one undo step', (tester) async {
      final vm = await _pumpCanvas(tester, _snapshot());
      await tester.tap(find.text('Card A'));
      await tester.pumpAndSettle();

      // Drag the resize handle (SE corner) out by (60, 40).
      await tester.drag(
        find.byKey(const Key('wb_resize_item_a')),
        const Offset(60, 40),
      );
      await tester.pumpAndSettle();

      final resized = vm.exportForSave().boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(resized.width, greaterThan(190));

      await _sendShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
      final restored = vm.exportForSave().boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(restored.width, equals(140),
          reason: 'a whole resize drag must be exactly one undo step');
    });
  });

  group('ViewModel logical actions and intents', () {
    test('logical action merges many operations into one undo step', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_widget',
      );
      vm.beginLogicalAction();
      for (var i = 0; i < 5; i++) {
        vm.moveItems({'item_a': const math.Point(10, 0)});
      }
      vm.endLogicalAction();

      expect(vm.operationLog.length, equals(5),
          reason: 'every adapter operation is still audited');
      expect(vm.canUndo, isTrue);
      vm.undo();
      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(0),
        reason: 'one logical action → one undo step returns to baseline',
      );
      expect(vm.canUndo, isFalse);
    });

    test('cancelLogicalAction restores baseline with no side effects', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_widget',
      );
      vm.beginLogicalAction();
      vm.moveItems({'item_a': const math.Point(10, 0)});
      vm.cancelLogicalAction();

      expect(
        vm.exportForSave().boardItems.firstWhere((i) => i.itemId == 'item_a').x,
        equals(0),
      );
      expect(vm.canUndo, isFalse);
      expect(vm.operationLog, isEmpty);
    });

    test('retargetEdge intent rejects self-loops and unknown items', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(withEdge: true),
        boardId: 'board_widget',
      );
      final selfLoop = vm.handleIntent(const RetargetEdgeIntent(
        edgeId: 'edge_e1',
        fromItemId: 'item_a',
        toItemId: 'item_a',
      ));
      expect(selfLoop, isFalse);
      expect(vm.exportForSave().edges.first.toItemId, equals('item_b'));

      final unknown = vm.handleIntent(const RetargetEdgeIntent(
        edgeId: 'edge_e1',
        fromItemId: 'item_zz',
      ));
      expect(unknown, isFalse);
      expect(vm.exportForSave().edges.first.fromItemId, equals('item_a'));
    });

    test('createBoard + placeCardOnBoard write through the same path', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_widget',
      );
      final board = vm.createBoard('新板');
      expect(
        vm.snapshot.boards.any((b) => b.boardId == board.boardId),
        isTrue,
      );

      final item = vm.placeCardOnBoard(
        cardId: 'card_a',
        boardId: board.boardId,
        x: 10,
        y: 20,
      );
      expect(item, isNotNull);
      expect(
        vm.snapshot.boardItems
            .any((i) => i.boardId == board.boardId && i.cardId == 'card_a'),
        isTrue,
      );
      // Placing on the current board selects the new item; on another
      // board it must not steal the selection.
      expect(vm.selection.isEmpty, isTrue);
    });

    test('DeleteSelectionIntent removes the selected edge first', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(withEdge: true, withGroup: true),
        boardId: 'board_widget',
      );
      vm.handleIntent(const SelectEdgeIntent(edgeId: 'edge_e1'));
      expect(vm.selectedEdgeId, equals('edge_e1'));

      expect(vm.handleIntent(const DeleteSelectionIntent()), isTrue);
      expect(vm.exportForSave().edges, isEmpty);
      expect(vm.selectedEdgeId, isNull);
    });

    test('selectAll with exclude skips collapsed group members', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(withGroup: true),
        boardId: 'board_widget',
      );
      vm.setGroupCollapsed('group_g1', true);
      vm.handleIntent(const SelectAllIntent(exclude: {'item_b'}));
      expect(vm.selection.selectedItemIds, equals({'item_a'}));
    });

    test('readonly rejects write intents', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_widget',
      );
      vm.setReadonly(true);
      expect(
        vm.handleIntent(const NudgeSelectionIntent(dx: 10, dy: 0)),
        isFalse,
      );
      expect(
        vm.handleIntent(const DeleteSelectionIntent()),
        isFalse,
      );
    });
  });
}
