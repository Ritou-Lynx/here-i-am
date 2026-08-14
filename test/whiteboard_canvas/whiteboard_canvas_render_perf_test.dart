/// W1 500-card widget-level render tests.
///
/// Verifies real widget-tree behavior under the 500-card performance board:
/// - Initial pump materializes only the cards visible in the viewport
///   (viewport culling keeps the widget count far below 500).
/// - Panning / zooming changes which cards are visible and repaints without
///   error.
/// - Culled cards are not in the widget tree at all.
///
/// NOTE: The test harness (flutter test) cannot produce a trustworthy FPS
/// number — it runs headless with an unbounded frame budget. Frame-rate
/// profiling must happen on a real desktop window (see W1 handoff). Here we
/// only assert widget-count bounds and error-free repaints, not frame times.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

/// Generates a 500-card snapshot laid out on a 20-col grid.
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

/// Counts the card title texts currently materialized in the widget tree.
int _renderedCardCount(WidgetTester tester) {
  return find
      .byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.startsWith('Card '),
      )
      .evaluate()
      .length;
}

Future<WhiteboardCanvasViewModel> _pump500(WidgetTester tester) async {
  final vm = WhiteboardCanvasViewModel(
    initialSnapshot: _generate500(),
    boardId: 'board_0',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WhiteboardCanvasScreen(viewModel: vm),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return vm;
}

void main() {
  group('500-card widget render', () {
    testWidgets('initial pump materializes only viewport-visible cards',
        (tester) async {
      await _pump500(tester);

      // 500 cards exist in data, but the widget tree must NOT contain all of
      // them — viewport culling should keep rendered count well below 500.
      final rendered = _renderedCardCount(tester);
      expect(rendered, greaterThan(0));
      expect(rendered, lessThan(500),
          reason: 'viewport culling must not materialize all 500 card widgets');

      // The first card (grid origin) is visible; a far card is not.
      expect(find.text('Card 0'), findsOneWidget);
    });

    testWidgets('pan changes the culled visible set and repaints cleanly',
        (tester) async {
      final vm = await _pump500(tester);
      final before = _renderedCardCount(tester);

      // Pan down to a later card row: panViewport(dx, dy) moves the content,
      // so a negative dy (canvas dragged up) reveals lower rows. centerY goes
      // from 0 to +1300, revealing rows ~7-11; row 0 (Card 0) leaves view.
      vm.panViewport(0, -130 * 10);
      await tester.pumpAndSettle();

      final after = _renderedCardCount(tester);
      expect(after, greaterThan(0));
      // The visible set changed (origin card left the viewport).
      expect(find.text('Card 0'), findsNothing);
      expect(after, lessThan(500));
      expect(tester.takeException(), isNull,
          reason: 'pan must not throw during repaint');
      expect(before, isNot(equals(after)));
    });

    testWidgets('zoom changes the culled visible set and repaints cleanly',
        (tester) async {
      final vm = await _pump500(tester);
      final before = _renderedCardCount(tester);

      // Zoom in — fewer cards fit on screen.
      vm.zoomViewport(2.0, const math.Point(0, 0));
      await tester.pumpAndSettle();

      final after = _renderedCardCount(tester);
      expect(after, greaterThan(0));
      expect(after, lessThan(500));
      expect(tester.takeException(), isNull,
          reason: 'zoom must not throw during repaint');
      expect(after, isNot(equals(before)));
    });

    testWidgets('selected card stays materialized when dragged off-viewport',
        (tester) async {
      final vm = await _pump500(tester);

      // Select card 0, then pan it out of view (down to later rows).
      vm.selectItem('item_0');
      vm.panViewport(0, -130 * 10);
      await tester.pumpAndSettle();

      // Selected items are force-rendered regardless of culling.
      expect(find.text('Card 0'), findsOneWidget,
          reason: 'selected item must survive culling');
    });
  });
}
