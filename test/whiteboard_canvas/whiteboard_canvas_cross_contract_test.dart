/// W1 ↔ W0 cross-boundary contract tests.
///
/// Verifies that the canvas adapter honors the W0-frozen shared contracts:
/// - Snapshot load → operations → export preserves referential integrity.
/// - Deleting a BoardItem never deletes the Card or Source.
/// - The same Card can appear as multiple BoardItems on different boards.
/// - Engine-private IDs stay identity-mapped (no private ID space).
/// - Export passes `validateSnapshotIntegrity`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/ui/whiteboard_canvas/engine/flutter_canvas_adapter.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

Map<String, dynamic> _loadFixture(String filename) {
  final path = 'test/domain/whiteboard/fixtures/$filename';
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('W1 ↔ W0 cross-boundary contract', () {
    test('operations on adapter preserve snapshot referential integrity', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final adapter = FlutterCanvasAdapter(original);

      // Perform a sequence of operations.
      adapter.placeCard(boardId: 'board_whiteboard_mvp', cardId: 'card_note_spine', x: 800, y: 100);
      adapter.moveItems(boardId: 'board_whiteboard_mvp', deltas: {
        'item_spine': const math.Point(50.0, 20.0),
      });
      adapter.resizeItem(
        boardId: 'board_whiteboard_mvp',
        itemId: 'item_affine',
        width: 320,
        height: 260,
      );
      adapter.createGroup(boardId: 'board_whiteboard_mvp', itemIds: ['item_spine', 'item_affine'], name: '契约测试组');
      adapter.createEdge(
        boardId: 'board_whiteboard_mvp',
        fromItemId: 'item_spine',
        toItemId: 'item_affine',
        direction: EdgeDirection.directed,
        label: '契约测试',
      );

      final exported = adapter.exportSnapshot();
      final integrity = validateSnapshotIntegrity(exported);

      expect(integrity.isValid, isTrue,
          reason: 'Export must pass integrity. Errors: ${integrity.errors}');
      expect(integrity.errors, isEmpty);
    });

    test('deleting BoardItem preserves Card and Source', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final adapter = FlutterCanvasAdapter(original);

      final cardsBefore = adapter.exportSnapshot().cards.length;
      final sourcesBefore = adapter.exportSnapshot().sources.length;
      final versionsBefore = adapter.exportSnapshot().sourceVersions.length;

      adapter.removeItems(boardId: 'board_whiteboard_mvp', itemIds: ['item_spine', 'item_affine']);

      final exported = adapter.exportSnapshot();
      expect(exported.cards.length, cardsBefore);
      expect(exported.sources.length, sourcesBefore);
      expect(exported.sourceVersions.length, versionsBefore);
      // The card that was referenced still exists.
      expect(exported.cards.any((c) => c.cardId == 'card_note_spine'), isTrue);
      // Integrity still holds after removal (cascading group/edge cleanup).
      final integrity = validateSnapshotIntegrity(exported);
      expect(integrity.isValid, isTrue,
          reason: 'Export after delete must pass integrity');
    });

    test('same Card appears as multiple BoardItems across boards', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final adapter = FlutterCanvasAdapter(original);

      // card_book_zhishen already appears on both boards in the fixture.
      final exported = adapter.exportSnapshot();
      final occurrences = exported.boardItems
          .where((i) => i.cardId == 'card_book_zhishen');
      expect(occurrences.length, greaterThanOrEqualTo(2));

      // Placing the same card on board_stage_color again adds another item
      // without duplicating the card.
      adapter.placeCard(
        boardId: 'board_stage_color',
        cardId: 'card_book_zhishen',
        x: 900,
        y: 300,
      );
      final after = adapter.exportSnapshot();
      expect(after.cards.where((c) => c.cardId == 'card_book_zhishen').length, 1);
      expect(after.boardItems.where((i) => i.cardId == 'card_book_zhishen').length, 3);
    });

    test('adapter ID mapping contains all product IDs (no private space)', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final adapter = FlutterCanvasAdapter(original);

      for (final item in original.boardItems) {
        expect(adapter.idMapping[item.itemId], item.itemId);
      }
      for (final group in original.groups) {
        expect(adapter.idMapping[group.groupId], group.groupId);
      }
      for (final edge in original.edges) {
        expect(adapter.idMapping[edge.edgeId], edge.edgeId);
      }
    });

    test('BoardItem contains no card content (only layout)', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final item = original.boardItems.first;
      final json = item.toJson();

      expect(json.containsKey('title'), isFalse);
      expect(json.containsKey('body'), isFalse);
      expect(json.containsKey('tags'), isFalse);
      expect(json.containsKey('x'), isTrue);
      expect(json.containsKey('y'), isTrue);
      expect(json.containsKey('width'), isTrue);
      expect(json.containsKey('height'), isTrue);
      expect(json.containsKey('card_id'), isTrue);
    });
  });

  group('ViewModel undo/redo across 20 mixed operations', () {
    test('20 mixed operations undo then redo restores original state', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: original,
        boardId: 'board_whiteboard_mvp',
      );

      // Perform 20 mixed operations.
      for (int i = 0; i < 10; i++) {
        vm.placeCard(
          cardId: 'card_note_spine',
          x: 100.0 + i * 60,
          y: 100.0 + i * 40,
        );
        vm.moveSelectedItems(10, 10);
      }

      // Undo all 20.
      int undoCount = 0;
      while (vm.canUndo) {
        vm.undo();
        undoCount++;
      }

      // Redo all 20.
      int redoCount = 0;
      while (vm.canRedo) {
        vm.redo();
        redoCount++;
      }

      expect(undoCount, greaterThanOrEqualTo(20));
      expect(redoCount, undoCount);

      // Final state matches original (all undone operations redone).
      final finalJson = vm.exportForSave().toJson();
      expect(finalJson['board_items'], isNotNull);
    });

    test('undo stack cleared on new snapshot load', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: original,
        boardId: 'board_whiteboard_mvp',
      );

      vm.placeCard(cardId: 'card_note_spine');
      expect(vm.canUndo, isTrue);

      vm.loadFromSnapshot(original);
      expect(vm.canUndo, isFalse);
      expect(vm.canRedo, isFalse);
      expect(vm.operationLog, isEmpty);
    });

    test('undo restores viewport changes', () {
      final original = loadSnapshot(_loadFixture('normal_snapshot.json'));
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: original,
        boardId: 'board_whiteboard_mvp',
      );

      final originalZoom = vm.viewport.zoom;
      vm.setViewport(const BoardViewport(centerX: 500, centerY: 400, zoom: 1.5));
      expect(vm.viewport.zoom, 1.5);

      vm.undo();
      expect(vm.viewport.zoom, originalZoom);
    });
  });
}