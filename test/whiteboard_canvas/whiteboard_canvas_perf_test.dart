/// W1 performance benchmark for the canvas adapter.
///
/// Measures load time, round-trip serialization, batch move, and culling
/// math for a 500-card board. Results are printed to stdout for recording
/// in W1_CANVAS.md; assertions use generous upper bounds to catch
/// pathological regressions without flaking on slow CI machines.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/engine/flutter_canvas_adapter.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

/// Generates a 500-card snapshot: 500 cards, 1 board, 500 board items.
WhiteboardSnapshot _generate500() {
  final now = DateTime(2026, 8, 15);
  final cards = <CardContract>[];
  final items = <BoardItem>[];
  for (int i = 0; i < 500; i++) {
    final row = i ~/ 20;
    final col = i % 20;
    cards.add(CardContract(
      cardId: 'card_$i',
      cardKind: CardKind.note,
      title: 'Card $i',
      body: 'Performance test card $i body text.',
      tags: const ['perf'],
      createdAt: now,
    ));
    items.add(BoardItem(
      itemId: 'item_$i',
      boardId: 'board_0',
      cardId: 'card_$i',
      x: 100.0 + col * 150,
      y: 100.0 + row * 130,
      width: 140,
      height: 110,
      zIndex: i,
    ));
  }
  return WhiteboardSnapshot(
    cards: cards,
    boards: [
      Board(boardId: 'board_0', name: 'Perf', createdAt: now),
    ],
    boardItems: items,
  );
}

void main() {
  final result = <String>[];
  void record(String key, double value) =>
      result.add('$key=${value.toStringAsFixed(1)}');

  group('500-card canvas performance', () {
    test('cold load and getBoardState', () {
      final snapshot = _generate500();
      final sw = Stopwatch()..start();
      final adapter = FlutterCanvasAdapter(snapshot);
      final state = adapter.getBoardState('board_0');
      sw.stop();
      record('cold_load_ms', sw.elapsedMicroseconds / 1000.0);
      expect(state.nodes.length, 500);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('snapshot toJson round-trip', () {
      final snapshot = _generate500();
      final sw = Stopwatch()..start();
      final json = snapshot.toJson();
      final restored = WhiteboardSnapshot.fromJson(json);
      sw.stop();
      record('serialize_roundtrip_ms', sw.elapsedMicroseconds / 1000.0);
      expect(restored.cards.length, 500);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('batch move 100 items', () {
      final snapshot = _generate500();
      final adapter = FlutterCanvasAdapter(snapshot);
      final deltas = <String, math.Point<double>>{};
      for (int i = 0; i < 100; i++) {
        deltas['item_$i'] = const math.Point(10.0, 10.0);
      }
      final sw = Stopwatch()..start();
      adapter.moveItems(boardId: 'board_0', deltas: deltas);
      sw.stop();
      record('batch_move_100_ms', sw.elapsedMicroseconds / 1000.0);
      final moved = adapter.exportSnapshot().boardItems
          .firstWhere((i) => i.itemId == 'item_0');
      expect(moved.x, 110.0);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('marquee culling over 500 items', () {
      final snapshot = _generate500();
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: 'board_0',
      );
      final sw = Stopwatch()..start();
      // Select a rect covering first 2 cards in a row.
      vm.selectInRect(const math.Rectangle(50.0, 50.0, 400.0, 200.0));
      sw.stop();
      record('marquee_select_ms', sw.elapsedMicroseconds / 1000.0);
      // 3 cards at x=100,250,400 with width 140 → 3 selected.
      expect(vm.selection.length, greaterThanOrEqualTo(2));
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('1000-card stress load (degradation check only)', () {
      final now = DateTime(2026, 8, 15);
      final cards = <CardContract>[];
      final items = <BoardItem>[];
      for (int i = 0; i < 1000; i++) {
        cards.add(CardContract(
          cardId: 'c$i',
          cardKind: CardKind.note,
          title: 'C$i',
          createdAt: now,
        ));
        items.add(BoardItem(
          itemId: 'i$i',
          boardId: 'b',
          cardId: 'c$i',
          x: (i % 40) * 150.0,
          y: (i ~/ 40) * 130.0,
        ));
      }
      final snapshot = WhiteboardSnapshot(
        cards: cards,
        boards: [Board(boardId: 'b', name: 'B', createdAt: now)],
        boardItems: items,
      );
      final sw = Stopwatch()..start();
      final adapter = FlutterCanvasAdapter(snapshot);
      final state = adapter.getBoardState('b');
      sw.stop();
      record('load_1000_ms', sw.elapsedMicroseconds / 1000.0);
      expect(state.nodes.length, 1000);
      // 1000-card load should degrade gracefully (well under a second of CPU
      // for pure Dart), but we allow generous headroom on slow CI.
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    tearDownAll(() {
      // ignore: avoid_print
      print('PERF_RESULTS ${result.join(' | ')}');
    });
  });
}
