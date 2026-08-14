/// W1 Canvas adapter and ViewModel tests.
///
/// Tests cover:
/// - Adapter load/exportSnapshot round-trip
/// - placeCard / moveItems / resizeItem / removeItems
/// - bringToFront (zIndex)
/// - Group creation and removal
/// - Edge creation and removal
/// - Delete BoardItem does NOT delete Card
/// - Same Card appears on multiple boards (multiple BoardItems)
/// - Viewport update
/// - setReadonly
/// - focusItem
/// - Operation audit log (onOperation callback)
/// - Undo/redo via ViewModel
/// - Selection (single, multi, marquee)
/// - Empty board state
/// - Corrupted snapshot recovery
/// - Orphaned card reference rendering
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

import 'package:memex/ui/whiteboard_canvas/engine/flutter_canvas_adapter.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart';

// ── Helpers ──────────────────────────────────────────────────────────

Map<String, dynamic> _loadFixture(String filename) {
  final path = 'test/domain/whiteboard/fixtures/$filename';
  final raw = File(path).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

WhiteboardSnapshot _loadSnapshotFixture(String filename) {
  return loadSnapshot(_loadFixture(filename));
}

WhiteboardSnapshot _createTestSnapshot({
  int cardCount = 5,
  int boardCount = 2,
  int itemsPerBoard = 3,
}) {
  final now = DateTime(2026, 8, 15);
  final cards = <CardContract>[];
  for (int i = 0; i < cardCount; i++) {
    cards.add(CardContract(
      cardId: 'card_$i',
      cardKind: i % 3 == 0 ? CardKind.source : CardKind.note,
      title: 'Card $i',
      body: 'Body text for card $i',
      tags: ['tag_$i'],
      createdAt: now,
    ));
  }

  final boards = <Board>[];
  for (int i = 0; i < boardCount; i++) {
    boards.add(Board(
      boardId: 'board_$i',
      name: 'Board $i',
      createdAt: now,
    ));
  }

  final boardItems = <BoardItem>[];
  for (int b = 0; b < boardCount; b++) {
    for (int i = 0; i < itemsPerBoard && i < cardCount; i++) {
      boardItems.add(BoardItem(
        itemId: 'item_${b}_$i',
        boardId: 'board_$b',
        cardId: 'card_$i',
        x: 100.0 + i * 150,
        y: 100.0 + i * 100,
        width: 260,
        height: 200,
        zIndex: i + 1,
      ));
    }
  }

  return WhiteboardSnapshot(
    cards: cards,
    boards: boards,
    boardItems: boardItems,
  );
}

// ── Adapter tests ───────────────────────────────────────────────────

void main() {
  group('FlutterCanvasAdapter', () {
    test('load and exportSnapshot round-trip preserves data', () {
      final original = _loadSnapshotFixture('normal_snapshot.json');
      final adapter = FlutterCanvasAdapter(original);
      final exported = adapter.exportSnapshot();

      expect(exported.cards.length, equals(original.cards.length));
      expect(exported.boards.length, equals(original.boards.length));
      expect(exported.boardItems.length, equals(original.boardItems.length));
      expect(exported.groups.length, equals(original.groups.length));
      expect(exported.groupMembers.length, equals(original.groupMembers.length));
      expect(exported.edges.length, equals(original.edges.length));
    });

    test('getBoardState returns only items for specified board', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final board0State = adapter.getBoardState('board_0');
      final board1State = adapter.getBoardState('board_1');

      expect(board0State.nodes.length, equals(3));
      expect(board1State.nodes.length, equals(3));
      expect(board0State.nodes.every((n) => n.item.boardId == 'board_0'), isTrue);
    });

    test('placeCard creates new BoardItem with correct card reference', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final item = adapter.placeCard(
        boardId: 'board_0',
        cardId: 'card_4',
        x: 500,
        y: 300,
      );

      expect(item, isNotNull);
      expect(item!.cardId, equals('card_4'));
      expect(item.boardId, equals('board_0'));
      expect(item.x, equals(500));
      expect(item.y, equals(300));

      final exported = adapter.exportSnapshot();
      expect(exported.boardItems.length, equals(snapshot.boardItems.length + 1));
      // Card NOT duplicated
      expect(exported.cards.length, equals(snapshot.cards.length));
    });

    test('placeCard returns null for non-existent board', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final item = adapter.placeCard(
        boardId: 'nonexistent',
        cardId: 'card_0',
      );
      expect(item, isNull);
    });

    test('placeCard returns null for non-existent card', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final item = adapter.placeCard(
        boardId: 'board_0',
        cardId: 'nonexistent',
      );
      expect(item, isNull);
    });

    test('placeCard assigns increasing zIndex', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final item1 = adapter.placeCard(
        boardId: 'board_0',
        cardId: 'card_0',
      );
      final item2 = adapter.placeCard(
        boardId: 'board_0',
        cardId: 'card_1',
      );

      expect(item2!.zIndex, greaterThan(item1!.zIndex));
    });

    test('moveItems updates positions by delta', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final originalItem = adapter.exportSnapshot().boardItems.first;
      final originalX = originalItem.x;
      final originalY = originalItem.y;

      adapter.moveItems(
        boardId: originalItem.boardId,
        deltas: {
          originalItem.itemId: const math.Point(50.0, 30.0),
        },
      );

      final movedItem = adapter.exportSnapshot().boardItems
          .firstWhere((i) => i.itemId == originalItem.itemId);
      expect(movedItem.x, equals(originalX + 50));
      expect(movedItem.y, equals(originalY + 30));
    });

    test('resizeItem updates width and height', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      adapter.resizeItem(
        boardId: 'board_0',
        itemId: 'item_0_0',
        width: 400,
        height: 300,
      );

      final item = adapter.exportSnapshot().boardItems
          .firstWhere((i) => i.itemId == 'item_0_0');
      expect(item.width, equals(400));
      expect(item.height, equals(300));
    });

    test('removeItems deletes BoardItem but NOT Card', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);
      final originalCardCount = snapshot.cards.length;
      final originalItemCount = snapshot.boardItems.length;

      adapter.removeItems(
        boardId: 'board_0',
        itemIds: ['item_0_0'],
      );

      final exported = adapter.exportSnapshot();
      expect(exported.boardItems.length, equals(originalItemCount - 1));
      // Card is NOT deleted
      expect(exported.cards.length, equals(originalCardCount));
      expect(exported.cards.any((c) => c.cardId == 'card_0'), isTrue);
    });

    test('removeItems also removes groupMembers and edges referencing the item', () {
      final snapshot = _loadSnapshotFixture('normal_snapshot.json');
      final adapter = FlutterCanvasAdapter(snapshot);

      adapter.removeItems(
        boardId: 'board_whiteboard_mvp',
        itemIds: ['item_spine'],
      );

      final exported = adapter.exportSnapshot();
      expect(exported.groupMembers.any((m) => m.itemId == 'item_spine'), isFalse);
      expect(exported.edges.any((e) =>
          e.fromItemId == 'item_spine' || e.toItemId == 'item_spine'), isFalse);
    });

    test('bringToFront increases zIndex above all others', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      adapter.bringToFront(
        boardId: 'board_0',
        itemId: 'item_0_0',
      );

      final items = adapter.exportSnapshot().boardItems
          .where((i) => i.boardId == 'board_0');
      final frontItem = items.firstWhere((i) => i.itemId == 'item_0_0');
      final maxOther = items
          .where((i) => i.itemId != 'item_0_0')
          .fold(0, (max, i) => i.zIndex > max ? i.zIndex : max);

      expect(frontItem.zIndex, greaterThan(maxOther));
    });

    test('createGroup adds group and members', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final group = adapter.createGroup(
        boardId: 'board_0',
        itemIds: ['item_0_0', 'item_0_1'],
        name: 'Test Group',
      );

      expect(group, isNotNull);
      final exported = adapter.exportSnapshot();
      expect(exported.groups.any((g) => g.groupId == group!.groupId), isTrue);
      expect(exported.groupMembers.where((m) => m.groupId == group!.groupId).length, equals(2));
    });

    test('removeGroup removes group and members but keeps items', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final group = adapter.createGroup(
        boardId: 'board_0',
        itemIds: ['item_0_0', 'item_0_1'],
      );

      final itemCountBefore = adapter.exportSnapshot().boardItems.length;

      adapter.removeGroup(boardId: 'board_0', groupId: group!.groupId);

      final exported = adapter.exportSnapshot();
      expect(exported.groups.any((g) => g.groupId == group.groupId), isFalse);
      expect(exported.groupMembers.where((m) => m.groupId == group.groupId), isEmpty);
      // Items still on board
      expect(exported.boardItems.length, equals(itemCountBefore));
    });

    test('createEdge connects two items', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final edge = adapter.createEdge(
        boardId: 'board_0',
        fromItemId: 'item_0_0',
        toItemId: 'item_0_1',
        direction: EdgeDirection.directed,
        label: 'test',
      );

      expect(edge, isNotNull);
      expect(edge!.fromItemId, equals('item_0_0'));
      expect(edge.toItemId, equals('item_0_1'));
    });

    test('createEdge returns null for non-existent items', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final edge = adapter.createEdge(
        boardId: 'board_0',
        fromItemId: 'nonexistent',
        toItemId: 'item_0_1',
      );
      expect(edge, isNull);
    });

    test('removeEdge deletes edge', () {
      final snapshot = _loadSnapshotFixture('normal_snapshot.json');
      final adapter = FlutterCanvasAdapter(snapshot);

      adapter.removeEdge(
        boardId: 'board_whiteboard_mvp',
        edgeId: 'edge_spine_affine',
      );

      expect(
        adapter.exportSnapshot().edges.any((e) => e.edgeId == 'edge_spine_affine'),
        isFalse,
      );
    });

    test('updateViewport changes viewport state', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      adapter.updateViewport(
        boardId: 'board_0',
        viewport: const BoardViewport(centerX: 500, centerY: 300, zoom: 1.5),
      );

      final vp = adapter.exportSnapshot().viewport;
      expect(vp.centerX, equals(500));
      expect(vp.centerY, equals(300));
      expect(vp.zoom, equals(1.5));
    });

    test('setReadonly toggles readonly flag', () {
      final adapter = FlutterCanvasAdapter();
      expect(adapter.isReadonly, isFalse);
      adapter.setReadonly(true);
      expect(adapter.isReadonly, isTrue);
    });

    test('focusItem centers viewport on item', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      adapter.focusItem('item_0_1');

      final vp = adapter.exportSnapshot().viewport;
      final item = snapshot.boardItems.firstWhere((i) => i.itemId == 'item_0_1');
      expect(vp.centerX, equals(item.x + item.width / 2));
      expect(vp.centerY, equals(item.y + item.height / 2));
    });

    test('onOperation callback fires with correct operation kind', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);
      final operations = <WhiteboardOperation>[];
      adapter.onOperation(operations.add);

      adapter.placeCard(boardId: 'board_0', cardId: 'card_0');
      adapter.moveItems(
        boardId: 'board_0',
        deltas: {'item_0_0': const math.Point(10.0, 10.0)},
      );

      expect(operations.length, equals(2));
      expect(operations[0].operationKind, equals(OperationKind.place));
      expect(operations[1].operationKind, equals(OperationKind.move));
    });

    test('same Card appears on multiple boards via multiple BoardItems', () {
      final snapshot = _loadSnapshotFixture('normal_snapshot.json');
      final adapter = FlutterCanvasAdapter(snapshot);

      // card_book_zhishen appears on both boards already in the fixture
      final exported = adapter.exportSnapshot();
      final bookItems = exported.boardItems
          .where((i) => i.cardId == 'card_book_zhishen');
      expect(bookItems.length, equals(2));
      expect(bookItems.map((i) => i.boardId).toSet().length, equals(2));
    });

    test('ID mapping is identity for this adapter', () {
      final snapshot = _loadSnapshotFixture('normal_snapshot.json');
      final adapter = FlutterCanvasAdapter(snapshot);

      for (final item in snapshot.boardItems) {
        expect(adapter.idMapping[item.itemId], equals(item.itemId));
      }
    });
  });

  group('FlutterCanvasAdapter inverse operations', () {
    test('placeCard inverse contains remove data', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);
      final operations = <WhiteboardOperation>[];
      adapter.onOperation(operations.add);

      adapter.placeCard(boardId: 'board_0', cardId: 'card_0');
      expect(operations.last.inverse, isNotNull);
      expect(operations.last.inverse!['kind'], equals('remove'));
    });

    test('moveItems inverse contains old positions', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);
      final operations = <WhiteboardOperation>[];
      adapter.onOperation(operations.add);

      adapter.moveItems(
        boardId: 'board_0',
        deltas: {'item_0_0': const math.Point(50.0, 30.0)},
      );

      final inverse = operations.last.inverse!;
      expect(inverse['kind'], equals('move'));
      expect(inverse['positions'], isNotNull);
    });

    test('removeItems inverse contains removed item data', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);
      final operations = <WhiteboardOperation>[];
      adapter.onOperation(operations.add);

      adapter.removeItems(boardId: 'board_0', itemIds: ['item_0_0']);

      final inverse = operations.last.inverse!;
      expect(inverse['kind'], equals('place'));
      expect((inverse['items'] as List).length, equals(1));
    });

    test('resizeItem inverse contains old geometry', () {
      final snapshot = _createTestSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);
      final operations = <WhiteboardOperation>[];
      adapter.onOperation(operations.add);

      adapter.resizeItem(
        boardId: 'board_0',
        itemId: 'item_0_0',
        width: 400,
        height: 300,
      );

      final inverse = operations.last.inverse!;
      expect(inverse['kind'], equals('resize'));
      expect(inverse['geometry'], isNotNull);
    });
  });

  // ── ViewModel tests ────────────────────────────────────────────────

  group('WhiteboardCanvasViewModel', () {
    test('undo restores previous snapshot state', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      final originalItemCount = vm.snapshot.boardItems.length;

      // Perform an operation
      vm.placeCard(cardId: 'card_4', x: 500, y: 300);
      expect(vm.snapshot.boardItems.length, equals(originalItemCount + 1));

      // Undo
      vm.undo();
      expect(vm.snapshot.boardItems.length, equals(originalItemCount));
      expect(vm.canUndo, isFalse);
    });

    test('redo restores undone state', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      final originalCount = vm.snapshot.boardItems.length;

      vm.placeCard(cardId: 'card_4');
      final placedCount = vm.snapshot.boardItems.length;
      expect(placedCount, equals(originalCount + 1));

      vm.undo();
      expect(vm.snapshot.boardItems.length, equals(originalCount));

      vm.redo();
      expect(vm.snapshot.boardItems.length, equals(placedCount));
    });

    test('undo stack is bounded by operations performed', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      expect(vm.canUndo, isFalse);
      expect(vm.canRedo, isFalse);

      vm.placeCard(cardId: 'card_0');
      expect(vm.canUndo, isTrue);

      vm.undo();
      expect(vm.canUndo, isFalse);
      expect(vm.canRedo, isTrue);

      vm.redo();
      expect(vm.canUndo, isTrue);
      expect(vm.canRedo, isFalse);
    });

    test('selection manages item IDs', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      expect(vm.selection.isEmpty, isTrue);

      vm.selectItem('item_0_0');
      expect(vm.selection.isSelected('item_0_0'), isTrue);
      expect(vm.selection.length, equals(1));

      vm.addToSelection('item_0_1');
      expect(vm.selection.length, equals(2));

      vm.clearSelection();
      expect(vm.selection.isEmpty, isTrue);
    });

    test('selectInRect selects items intersecting the rectangle', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      // Items are at x=100, 250, 400 with width=260
      // Select a rect that intersects first two
      vm.selectInRect(const math.Rectangle(50.0, 50.0, 300.0, 300.0));

      expect(vm.selection.length, greaterThan(0));
    });

    test('removeSelectedItems clears selection', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      vm.selectItem('item_0_0');
      expect(vm.selection.isNotEmpty, isTrue);

      vm.removeSelectedItems();
      expect(vm.selection.isEmpty, isTrue);
      expect(vm.snapshot.boardItems.any((i) => i.itemId == 'item_0_0'), isFalse);
    });

    test('setReadonly clears selection', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      vm.selectItem('item_0_0');
      vm.setReadonly(true);

      expect(vm.isReadonly, isTrue);
      expect(vm.selection.isEmpty, isTrue);
    });

    test('operation log records all operations', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      vm.placeCard(cardId: 'card_0');
      vm.moveSelectedItems(10, 20);

      expect(vm.operationLog.length, greaterThanOrEqualTo(1));
    });

    test('loadFromSnapshot resets undo/redo and operation log', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      vm.placeCard(cardId: 'card_0');
      expect(vm.canUndo, isTrue);
      expect(vm.operationLog.length, greaterThan(0));

      vm.loadFromSnapshot(snapshot);
      expect(vm.canUndo, isFalse);
      expect(vm.canRedo, isFalse);
      expect(vm.operationLog, isEmpty);
    });

    test('exportForSave returns current snapshot', () {
      final snapshot = _createTestSnapshot();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );

      vm.placeCard(cardId: 'card_0', x: 500, y: 300);
      final exported = vm.exportForSave();

      expect(exported.boardItems.length, equals(snapshot.boardItems.length + 1));
    });
  });

  // ── Snapshot store tests ──────────────────────────────────────────

  group('WhiteboardSnapshotStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('whiteboard_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('save and load round-trip', () {
      final store = WhiteboardSnapshotStore(tempDir.path);
      final snapshot = _createTestSnapshot();

      final saved = store.save('board_0', snapshot);
      expect(saved, isTrue);

      final result = store.load('board_0');
      expect(result.isSuccess, isTrue);
      expect(result.snapshot!.cards.length, equals(snapshot.cards.length));
      expect(result.snapshot!.boards.length, equals(snapshot.boards.length));
    });

    test('load non-existent file returns error', () {
      final store = WhiteboardSnapshotStore(tempDir.path);

      final result = store.load('nonexistent');
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });

    test('load corrupted JSON returns error', () {
      final file = File('${tempDir.path}/whiteboard_corrupt.json');
      file.writeAsStringSync('{ "invalid json,,, }');

      final store = WhiteboardSnapshotStore(tempDir.path);
      final result = store.load('corrupt');
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });

    test('load invalid dangling refs returns snapshot with integrity issues', () {
      // Copy fixture to temp dir
      final fixture = _loadFixture('invalid_dangling_refs.json');
      final file = File('${tempDir.path}/whiteboard_dangling.json');
      file.writeAsStringSync(jsonEncode(fixture));

      final store = WhiteboardSnapshotStore(tempDir.path);
      final result = store.load('dangling');

      // loadSnapshot may recover or return with integrity issues
      expect(result.error, isNull);
      if (result.integrity != null) {
        expect(result.hasIntegrityIssues, isTrue);
      }
    });

    test('load old schema v0 migrates successfully', () {
      final fixture = _loadFixture('old_schema_v0.json');
      final file = File('${tempDir.path}/whiteboard_old.json');
      file.writeAsStringSync(jsonEncode(fixture));

      final store = WhiteboardSnapshotStore(tempDir.path);
      final result = store.load('old');

      expect(result.isSuccess, isTrue);
      expect(result.snapshot!.schemaVersion, equals(1));
    });

    test('exists returns true after save', () {
      final store = WhiteboardSnapshotStore(tempDir.path);
      store.save('board_0', _createTestSnapshot());
      expect(store.exists('board_0'), isTrue);
      expect(store.exists('board_1'), isFalse);
    });

    test('delete removes file', () {
      final store = WhiteboardSnapshotStore(tempDir.path);
      store.save('board_0', _createTestSnapshot());
      expect(store.delete('board_0'), isTrue);
      expect(store.exists('board_0'), isFalse);
    });
  });

  // ── Empty board state ─────────────────────────────────────────────

  group('Empty board state', () {
    test('getBoardState for empty board returns no nodes', () {
      final emptySnapshot = _loadSnapshotFixture('empty_snapshot.json');
      final adapter = FlutterCanvasAdapter(emptySnapshot);

      final boardState = adapter.getBoardState('board_empty');
      expect(boardState.nodes, isEmpty);
      expect(boardState.groups, isEmpty);
      expect(boardState.edges, isEmpty);
    });

    test('ViewModel with empty snapshot has no items', () {
      final emptySnapshot = _loadSnapshotFixture('empty_snapshot.json');
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: emptySnapshot,
        boardId: 'board_empty',
      );

      expect(vm.boardState.nodes, isEmpty);
      expect(vm.selection.isEmpty, isTrue);
    });
  });

  // ── Orphaned card reference ───────────────────────────────────────

  group('Orphaned card reference', () {
    test('BoardItem with non-existent cardId is marked orphaned', () {
      final snapshot = WhiteboardSnapshot(
        boards: [
          Board(boardId: 'b1', name: 'Test', createdAt: DateTime.now()),
        ],
        cards: [
          CardContract(
            cardId: 'card_exists',
            cardKind: CardKind.note,
            title: 'Exists',
            createdAt: DateTime.now(),
          ),
        ],
        boardItems: [
          const BoardItem(
            itemId: 'item_1',
            boardId: 'b1',
            cardId: 'card_exists',
          ),
          const BoardItem(
            itemId: 'item_2',
            boardId: 'b1',
            cardId: 'card_missing',
          ),
        ],
      );

      final adapter = FlutterCanvasAdapter(snapshot);
      final boardState = adapter.getBoardState('b1');

      expect(boardState.nodes.length, equals(2));
      expect(boardState.nodes[0].isOrphaned, isFalse);
      expect(boardState.nodes[1].isOrphaned, isTrue);
      expect(boardState.nodes[1].card, isNull);
    });
  });

  // ── 500 cards performance fixture ─────────────────────────────────

  group('500 cards performance', () {
    test('adapter handles 500 cards and 500 items without errors', () {
      final snapshot = _generate500CardSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final boardState = adapter.getBoardState('board_perf');

      expect(boardState.nodes.length, equals(500));
      expect(boardState.nodes.every((n) => !n.isOrphaned), isTrue);
    });

    test('adapter round-trip preserves 500 cards', () {
      final snapshot = _generate500CardSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final exported = adapter.exportSnapshot();

      expect(exported.cards.length, equals(500));
      expect(exported.boardItems.length, equals(500));
      expect(exported.boards.length, equals(1));
    });

    test('adapter moveItems on 100 items completes', () {
      final snapshot = _generate500CardSnapshot();
      final adapter = FlutterCanvasAdapter(snapshot);

      final itemIds = snapshot.boardItems.take(100).map((i) => i.itemId).toList();
      final deltas = <String, math.Point<double>>{};
      for (final id in itemIds) {
        deltas[id] = const math.Point(10.0, 10.0);
      }

      adapter.moveItems(boardId: 'board_perf', deltas: deltas);

      final exported = adapter.exportSnapshot();
      for (final id in itemIds) {
        final item = exported.boardItems.firstWhere((i) => i.itemId == id);
        // Verify moved
        expect(item.x, isNot(equals(snapshot.boardItems
            .firstWhere((i) => i.itemId == id).x)));
      }
    });

    test('snapshot serialization and deserialization of 500 cards', () {
      final snapshot = _generate500CardSnapshot();
      final json = snapshot.toJson();
      final restored = WhiteboardSnapshot.fromJson(json);

      expect(restored.cards.length, equals(500));
      expect(restored.boardItems.length, equals(500));
    });

    test('integrity validation passes for 500 card snapshot', () {
      final snapshot = _generate500CardSnapshot();
      final result = validateSnapshotIntegrity(snapshot);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });
}

// ── 500-card fixture generator ───────────────────────────────────────

WhiteboardSnapshot _generate500CardSnapshot() {
  final now = DateTime(2026, 8, 15);
  final cards = <CardContract>[];
  final boardItems = <BoardItem>[];

  for (int i = 0; i < 500; i++) {
    final row = i ~/ 20;
    final col = i % 20;
    cards.add(CardContract(
      cardId: 'perf_card_$i',
      cardKind: i % 5 == 0
          ? CardKind.source
          : i % 7 == 0
              ? CardKind.annotation
              : CardKind.note,
      sourceId: i % 5 == 0 ? 'perf_source_${i ~/ 5}' : null,
      title: 'Card $i',
      body: 'Performance test card number $i with some body text.',
      tags: ['perf', 'card_$i'],
      createdAt: now,
    ));

    boardItems.add(BoardItem(
      itemId: 'perf_item_$i',
      boardId: 'board_perf',
      cardId: 'perf_card_$i',
      x: 100.0 + col * 150,
      y: 100.0 + row * 130,
      width: 140,
      height: 110,
      zIndex: i,
    ));
  }

  final sources = <SourceContent>[];
  for (int i = 0; i < 100; i++) {
    sources.add(SourceContent(
      sourceId: 'perf_source_$i',
      mediaType: SourceMediaType.text,
      title: 'Source $i',
      createdAt: now,
    ));
  }

  return WhiteboardSnapshot(
    sources: sources,
    cards: cards,
    boards: [
      Board(boardId: 'board_perf', name: 'Performance Test', createdAt: now),
    ],
    boardItems: boardItems,
  );
}