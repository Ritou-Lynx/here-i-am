import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_manual_command_port.dart';

void main() {
  testWidgets(
    'production canvas semantic commits route keyboard drag resize and compact edit',
    (tester) async {
      final port = _RecordingPort();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_port',
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          manualCommandPort: port,
        ),
      ));
      await tester.pump();

      final card = find.byKey(const Key('wb_card_item_a'));
      await tester.tap(card);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(port.moves, hasLength(1));
      expect(port.moves.single['item_a']?.x, -82);

      await tester.drag(card, const Offset(48, 24));
      await tester.pump();
      expect(port.moves, hasLength(2));
      expect(port.moves.last['item_a']?.x, greaterThan(-82));

      await tester.pump(const Duration(milliseconds: 500));
      vm.selectItem('item_a');
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('wb_resize_item_a')),
        const Offset(40, 30),
      );
      await tester.pump();
      expect(port.resizes, hasLength(1));
      expect(port.resizes.single.width, greaterThan(180));

      await _doubleTapAt(tester, tester.getCenter(card));
      await tester.pump();
      expect(find.byKey(const Key('wb_domain_card_editor')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('wb_domain_card_body')),
        'domain body',
      );
      await tester.tap(find.byKey(const Key('wb_domain_card_save')));
      await tester.pump();
      expect(port.edits, hasLength(1));
      expect(port.edits.single.body, 'domain body');
      expect(port.edits.single.labels, ['existing-label']);
    },
  );

  testWidgets(
    'right click create/remove and floating/keyboard delete route the port',
    (tester) async {
      final port = _RecordingPort();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_port',
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          manualCommandPort: port,
        ),
      ));
      await tester.pump();

      final createClick = await tester.startGesture(
        const Offset(740, 540),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await createClick.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建文字卡片'));
      await tester.pump();
      expect(port.creates, hasLength(1));

      await _doubleTapAt(tester, const Offset(700, 450));
      await tester.pump();
      expect(port.creates, hasLength(2));

      final card = find.byKey(const Key('wb_card_item_a'));
      final removeClick = await tester.startGesture(
        tester.getCenter(card),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await removeClick.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('从白板移除'));
      await tester.pump();
      expect(port.removals, [
        ['item_a'],
      ]);

      await tester.tap(card);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(port.removals, hasLength(2));

      expect(find.byKey(const Key('wb_action_tools')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wb_delete_selection_tool')));
      await tester.pump();
      expect(port.removals, hasLength(3));
      expect(port.removals.every((ids) => ids.single == 'item_a'), isTrue);
    },
  );
}

WhiteboardSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 28);
  return WhiteboardSnapshot(
    boards: [Board(boardId: 'board_port', name: 'Port', createdAt: now)],
    cards: [
      CardContract(
        cardId: 'card_a',
        cardKind: CardKind.note,
        title: 'Card A',
        body: 'old body',
        tags: const ['existing-label'],
        createdAt: now,
      ),
    ],
    boardItems: const [
      BoardItem(
        itemId: 'item_a',
        boardId: 'board_port',
        cardId: 'card_a',
        x: -90,
        y: -70,
        width: 180,
        height: 140,
      ),
    ],
    updatedAt: now,
  );
}

Future<void> _doubleTapAt(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 70));
  await tester.tapAt(point);
  await tester.pump();
}

class _RecordingPort implements WhiteboardManualCommandPort {
  final creates = <math.Point<double>>[];
  final edits = <({String cardId, String body, List<String> labels})>[];
  final moves = <Map<String, math.Point<double>>>[];
  final resizes = <({String itemId, double width, double height})>[];
  final removals = <List<String>>[];

  @override
  Future<WhiteboardManualCreateResult?> createNote({
    required double x,
    required double y,
    double width = 260,
    double height = 200,
  }) async {
    creates.add(math.Point(x, y));
    return const WhiteboardManualCreateResult(
      cardId: 'new_card',
      itemId: 'new_item',
    );
  }

  @override
  Future<bool> editCard({
    required String cardId,
    required String body,
    required List<String> labels,
  }) async {
    edits.add((cardId: cardId, body: body, labels: List.of(labels)));
    return true;
  }

  @override
  Future<bool> movePlacements(
    Map<String, math.Point<double>> positions,
  ) async {
    moves.add(Map.of(positions));
    return true;
  }

  @override
  Future<bool> removePlacements(List<String> itemIds) async {
    removals.add(List.of(itemIds));
    return true;
  }

  @override
  Future<bool> resizePlacement({
    required String itemId,
    required double width,
    required double height,
  }) async {
    resizes.add((itemId: itemId, width: width, height: height));
    return true;
  }
}
