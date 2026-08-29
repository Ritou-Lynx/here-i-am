import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
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
      final root = Directory.systemTemp.createTempSync('manual_port_card_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_a',
            title: 'Card A',
            body: 'old body',
            tags: const ['existing-label'],
            createdAt: DateTime.utc(2026, 8, 28),
          ));
      final port = _RecordingPort();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_port',
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          manualCommandPort: port,
          cardRepository: repository,
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
      for (var index = 0;
          index < 50 &&
              find
                  .byKey(const Key('rich_text_continuous_document'))
                  .evaluate()
                  .isEmpty;
          index++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.byKey(const Key('wb_domain_card_editor')), findsNothing);
      expect(find.byKey(const Key('wb_compact_card_editor')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('rich_text_continuous_document')),
        'Domain title\ndomain body',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      for (var index = 0; index < 50 && port.edits.isEmpty; index++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(port.edits, hasLength(1));
      expect(port.edits.single.title, 'Domain title');
      expect(port.edits.single.body, 'domain body');
    },
  );

  testWidgets(
    'right click create/remove and floating delete route the port',
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
      vm.selectItem('item_a');
      await tester.pump();
      final removeClick = await tester.startGesture(
        tester.getCenter(card),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await removeClick.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('从白板移除'));
      await tester.pumpAndSettle();
      expect(port.removals, hasLength(1));

      expect(find.byKey(const Key('wb_action_tools')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wb_delete_selection_tool')));
      await tester.pump();
      expect(port.removals, hasLength(2));
      expect(port.removals.every((ids) => ids.single == 'item_a'), isTrue);
    },
  );

  testWidgets('keyboard delete routes the port on a fresh focused canvas',
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
    expect(vm.selection.selectedItemIds, contains('item_a'));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(port.removals, [
      ['item_a'],
    ]);
  });

  testWidgets('card library click and drag route place-existing port',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('manual_port_library_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    await tester.runAsync(() => repository.createTextCard(
          cardId: 'card_library',
          title: 'Library card',
          createdAt: DateTime.utc(2026, 8, 28),
        ));
    final port = _RecordingPort();
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_port',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        manualCommandPort: port,
        cardRepository: repository,
      ),
    ));
    await tester.tap(find.byKey(const Key('wb_open_card_library_tool')));
    for (var index = 0;
        index < 50 &&
            find.byKey(const Key('wb_lib_row_card_library')).evaluate().isEmpty;
        index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    final row = find.byKey(const Key('wb_lib_row_card_library'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    expect(port.placements, hasLength(1));
    expect(
      vm.exportForSave().boardItems.any((item) => item.cardId == 'card_library'),
      isFalse,
      reason: 'UI must wait for host reload rather than create a ghost',
    );

    await tester.dragFrom(tester.getCenter(row), const Offset(420, 260));
    await tester.pump();
    expect(port.placements, hasLength(2));

    port.placementSucceeds = false;
    await tester.tap(row);
    await tester.pump();
    expect(port.placements, hasLength(3));
    expect(
      vm.exportForSave().boardItems.any((item) => item.cardId == 'card_library'),
      isFalse,
    );
  });
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
  bool placementSucceeds = true;
  final creates = <math.Point<double>>[];
  final edits = <({String cardId, String title, String body})>[];
  final labels = <({String cardId, List<String> labels})>[];
  final moves = <Map<String, math.Point<double>>>[];
  final resizes = <({String itemId, double width, double height})>[];
  final removals = <List<String>>[];
  final placements = <({String cardId, double x, double y})>[];

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
  Future<WhiteboardManualPlacementResult?> placeExistingCard({
    required String cardId,
    required double x,
    required double y,
    double width = 260,
    double height = 200,
  }) async {
    placements.add((cardId: cardId, x: x, y: y));
    if (!placementSucceeds) return null;
    return WhiteboardManualPlacementResult(
      cardId: cardId,
      itemId: 'placed_${placements.length}',
    );
  }

  @override
  Future<bool> editCard({
    required String cardId,
    required String title,
    required String body,
  }) async {
    edits.add((cardId: cardId, title: title, body: body));
    return true;
  }

  @override
  Future<bool> setCardLabels({
    required String cardId,
    required List<String> labels,
  }) async {
    this.labels.add((cardId: cardId, labels: List.of(labels)));
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
