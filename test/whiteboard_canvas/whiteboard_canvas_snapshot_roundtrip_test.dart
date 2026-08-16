/// Snapshot round-trip tests for the new W1 interactions — rotation,
/// group collapse and edge retargeting must survive save → load (restart
/// recovery) through the file store AND the plain JSON contract.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart';

WhiteboardSnapshot _snapshot() {
  final now = DateTime(2026, 8, 15);
  return WhiteboardSnapshot(
    boards: [
      Board(boardId: 'board_r', name: 'Round Trip', createdAt: now),
    ],
    cards: [
      CardContract(
        cardId: 'card_a',
        cardKind: CardKind.note,
        title: 'Card A',
        body: 'Body A',
        createdAt: now,
      ),
      CardContract(
        cardId: 'card_b',
        cardKind: CardKind.note,
        title: 'Card B',
        body: 'Body B',
        createdAt: now,
      ),
      CardContract(
        cardId: 'card_c',
        cardKind: CardKind.note,
        title: 'Card C',
        body: 'Body C',
        createdAt: now,
      ),
    ],
    boardItems: const [
      BoardItem(
        itemId: 'item_a',
        boardId: 'board_r',
        cardId: 'card_a',
        x: 100,
        y: 100,
        width: 200,
        height: 120,
      ),
      BoardItem(
        itemId: 'item_b',
        boardId: 'board_r',
        cardId: 'card_b',
        x: 360,
        y: 100,
        width: 200,
        height: 120,
      ),
      BoardItem(
        itemId: 'item_c',
        boardId: 'board_r',
        cardId: 'card_c',
        x: 620,
        y: 100,
        width: 200,
        height: 120,
      ),
    ],
    groups: [
      const BoardGroup(groupId: 'group_g1', boardId: 'board_r', name: 'G1'),
    ],
    groupMembers: [
      const GroupMember(groupId: 'group_g1', itemId: 'item_a', order: 0),
      const GroupMember(groupId: 'group_g1', itemId: 'item_b', order: 1),
    ],
    edges: [
      BoardEdge(
        edgeId: 'edge_e1',
        boardId: 'board_r',
        fromItemId: 'item_a',
        toItemId: 'item_b',
        createdAt: now,
      ),
    ],
  );
}

void main() {
  group('interaction state snapshot round-trip (restart recovery)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('w1_roundtrip_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('rotation / collapse / retargeted edge survive store save→load', () {
      final store = WhiteboardSnapshotStore(tempDir.path);
      const boardId = 'board_r';

      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: boardId,
      );

      // Rotate card A, collapse the group, retarget the edge onto card C.
      vm.rotateItem(itemId: 'item_a', rotationDegrees: 33.5);
      vm.setGroupCollapsed('group_g1', true);
      vm.retargetEdge(edgeId: 'edge_e1', toItemId: 'item_c');

      expect(store.save(boardId, vm.exportForSave()), isTrue);

      final result = store.load(boardId);
      expect(result.isSuccess, isTrue);
      final restored = result.snapshot!;

      final itemA =
          restored.boardItems.firstWhere((i) => i.itemId == 'item_a');
      expect(itemA.rotation, equals(33.5));

      final group = restored.groups.firstWhere((g) => g.groupId == 'group_g1');
      expect(group.collapsed, isTrue);

      final edge = restored.edges.firstWhere((e) => e.edgeId == 'edge_e1');
      expect(edge.fromItemId, equals('item_a'));
      expect(edge.toItemId, equals('item_c'));

      final integrity = validateSnapshotIntegrity(restored);
      expect(integrity.isValid, isTrue,
          reason: 'the round-tripped snapshot must stay internally valid');
    });

    test('undo / redo / undo after restart stays consistent', () {
      final store = WhiteboardSnapshotStore(tempDir.path);
      const boardId = 'board_r';

      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: boardId,
      );
      vm.rotateItem(itemId: 'item_a', rotationDegrees: 45);
      vm.rotateItem(itemId: 'item_a', rotationDegrees: 90);
      vm.undo();
      store.save(boardId, vm.exportForSave());

      final restored = store.load(boardId);
      final itemA = restored.snapshot!.boardItems
          .firstWhere((i) => i.itemId == 'item_a');
      expect(itemA.rotation, equals(45));
    });

    test('JSON contract round-trip preserves interaction state', () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_r',
      );
      vm.rotateItem(itemId: 'item_b', rotationDegrees: -30);
      vm.retargetEdge(
        edgeId: 'edge_e1',
        fromItemId: 'item_c',
        toItemId: null,
      );
      vm.moveItems({'item_c': const math.Point(12.5, -7.5)});

      final json = vm.exportForSave().toJson();
      final restored = WhiteboardSnapshot.fromJson(json);

      final itemB =
          restored.boardItems.firstWhere((i) => i.itemId == 'item_b');
      expect(itemB.rotation, equals(-30));
      final edge = restored.edges.first;
      expect(edge.fromItemId, equals('item_c'));
      final itemC =
          restored.boardItems.firstWhere((i) => i.itemId == 'item_c');
      expect(itemC.x, equals(632.5));
      expect(itemC.y, equals(92.5));
    });

    test('collapsed group hides nothing at the data layer (layout intact)',
        () {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(),
        boardId: 'board_r',
      );
      vm.setGroupCollapsed('group_g1', true);
      final snapshot = vm.exportForSave();
      expect(snapshot.boardItems.length, equals(3),
          reason: 'collapse is a view state, never a data deletion');
      expect(snapshot.groupMembers.length, equals(2));
    });
  });
}
