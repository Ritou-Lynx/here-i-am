/// LOD (semantic zoom) tests — tier logic, hysteresis, 500-card render
/// behavior and full-vs-minimal build cost comparison.
///
/// Design reference: `docs/development/WHITEBOARD_EXTERNAL_REFERENCE_HUABU.md`
/// §5 — card screen width (width × zoom) switches full ↔ minimal with a
/// 10px hysteresis band (140 / 150). LOD is render-side only: it never
/// touches the snapshot.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/interactions/lod.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

WhiteboardSnapshot _singleCard() {
  final now = DateTime(2026, 8, 15);
  return WhiteboardSnapshot(
    cards: [
      CardContract(
        cardId: 'card_a',
        cardKind: CardKind.note,
        title: 'Card A',
        body: 'Body of card A for LOD testing.',
        tags: const ['perf'],
        createdAt: now,
      ),
    ],
    boards: [
      Board(boardId: 'board_0', name: 'LOD', createdAt: now),
    ],
    boardItems: const [
      BoardItem(
        itemId: 'item_a',
        boardId: 'board_0',
        cardId: 'card_a',
        x: 100,
        y: 100,
        width: 140,
        height: 110,
      ),
    ],
  );
}

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

Future<WhiteboardCanvasViewModel> _pump(
  WidgetTester tester,
  WhiteboardSnapshot snapshot,
) async {
  final vm = WhiteboardCanvasViewModel(
    initialSnapshot: snapshot,
    boardId: snapshot.boards.isNotEmpty ? snapshot.boards.first.boardId : 'b',
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

int _tierCount(WidgetTester tester, String tierName) {
  return find
      .byWidgetPredicate(
        (w) =>
            w.key != null &&
            w.key.toString().contains('wb_card_content_') &&
            w.key.toString().contains('_$tierName'),
      )
      .evaluate()
      .length;
}

int _renderedCardCount(WidgetTester tester) {
  return find
      .byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.startsWith('Card '),
      )
      .evaluate()
      .length;
}

void main() {
  group('LodTier pure logic', () {
    test('full collapses to minimal below 140px screen width', () {
      expect(
        nextLodTier(current: LodTier.full, screenWidth: 139.9),
        LodTier.minimal,
      );
      expect(
        nextLodTier(current: LodTier.full, screenWidth: 140),
        LodTier.full,
      );
    });

    test('minimal expands to full above 150px screen width', () {
      expect(
        nextLodTier(current: LodTier.minimal, screenWidth: 150.1),
        LodTier.full,
      );
      expect(
        nextLodTier(current: LodTier.minimal, screenWidth: 150),
        LodTier.minimal,
      );
    });

    test('10px hysteresis band keeps the current tier stable', () {
      expect(
        nextLodTier(current: LodTier.full, screenWidth: 145),
        LodTier.full,
      );
      expect(
        nextLodTier(current: LodTier.minimal, screenWidth: 145),
        LodTier.minimal,
      );
      // Round trip: full → minimal → full across the band.
      var tier = LodTier.full;
      tier = nextLodTier(current: tier, screenWidth: 130);
      expect(tier, LodTier.minimal);
      tier = nextLodTier(current: tier, screenWidth: 145);
      expect(tier, LodTier.minimal, reason: 'still inside the hysteresis band');
      tier = nextLodTier(current: tier, screenWidth: 170);
      expect(tier, LodTier.full);
    });
  });

  group('LOD widget rendering', () {
    testWidgets('hysteresis survives zoom jitter per card', (tester) async {
      final vm = await _pump(tester, _singleCard());
      // width 140 × zoom 1.0 = 140 → full tier.
      expect(_tierCount(tester, 'full'), equals(1));
      expect(_tierCount(tester, 'minimal'), equals(0));

      // zoom 0.95 → 133px → minimal.
      vm.zoomViewport(0.95, const math.Point(0, 0));
      await tester.pumpAndSettle();
      expect(_tierCount(tester, 'minimal'), equals(1));

      // zoom back to 1.0 → 140px, still inside hysteresis (≤150) → minimal.
      vm.zoomViewport(1.0 / 0.95, const math.Point(0, 0));
      await tester.pumpAndSettle();
      expect(_tierCount(tester, 'minimal'), equals(1),
          reason: 'hysteresis must prevent flicker on zoom jitter');

      // zoom 1.2 → 168px > 150 → full again.
      vm.zoomViewport(1.2, const math.Point(0, 0));
      await tester.pumpAndSettle();
      expect(_tierCount(tester, 'full'), equals(1));
    });

    testWidgets('minimal tier renders no body or tags', (tester) async {
      final vm = await _pump(tester, _singleCard());
      vm.zoomViewport(0.5, const math.Point(0, 0));
      await tester.pumpAndSettle();

      expect(_tierCount(tester, 'minimal'), equals(1));
      expect(find.textContaining('Body of card'), findsNothing);
      expect(find.text('perf'), findsNothing);
      expect(find.text('Card A'), findsOneWidget,
          reason: 'title stays the minimal tier anchor');
    });

    testWidgets('LOD never changes the snapshot', (tester) async {
      final vm = await _pump(tester, _singleCard());
      final before = vm.exportForSave().toJson().toString();
      vm.zoomViewport(0.3, const math.Point(0, 0));
      await tester.pumpAndSettle();
      expect(_tierCount(tester, 'minimal'), equals(1));
      expect(vm.exportForSave().toJson().toString(), equals(before));
    });
  });

  group('500-card LOD render', () {
    testWidgets('low zoom renders visible cards in minimal tier only',
        (tester) async {
      final vm = await _pump(tester, _generate500());
      vm.zoomViewport(0.25, const math.Point(0, 0));
      await tester.pumpAndSettle();

      final rendered = _renderedCardCount(tester);
      expect(rendered, greaterThan(0));
      expect(rendered, lessThan(500),
          reason: 'viewport culling must hold at low zoom too');
      expect(_tierCount(tester, 'minimal'), greaterThan(0));
      expect(_tierCount(tester, 'full'), equals(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('high zoom returns to full tier and repaints cleanly',
        (tester) async {
      final vm = await _pump(tester, _generate500());
      vm.zoomViewport(0.25, const math.Point(0, 0));
      await tester.pumpAndSettle();
      expect(_tierCount(tester, 'minimal'), greaterThan(0));

      vm.zoomViewport(6.0, const math.Point(0, 0));
      await tester.pumpAndSettle();
      expect(_tierCount(tester, 'full'), greaterThan(0));
      expect(_tierCount(tester, 'minimal'), equals(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('full vs minimal build cost on 500 visible cards',
        (tester) async {
      // Widen the test viewport so all 500 cards (grid spans ~3100×3350
      // canvas px) are inside the culling window at zoom 1.0 → a
      // like-for-like build-cost comparison.
      tester.view.physicalSize = const Size(6800, 7200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final vm = await _pump(tester, _generate500());
      expect(_tierCount(tester, 'full'), greaterThan(400),
          reason: 'all cards visible and in full tier at zoom 1.0');

      final swFull = Stopwatch()..start();
      vm.panViewport(0, 1);
      await tester.pump();
      final fullMs = swFull.elapsedMicroseconds / 1000;

      vm.zoomViewport(0.25, const math.Point(0, 0));
      await tester.pumpAndSettle();
      expect(_tierCount(tester, 'minimal'), greaterThan(400));

      final swMin = Stopwatch()..start();
      vm.panViewport(0, 1);
      await tester.pump();
      final minimalMs = swMin.elapsedMicroseconds / 1000;

      debugPrint('LOD_BENCH fullMs=$fullMs minimalMs=$minimalMs');
      expect(minimalMs, lessThanOrEqualTo(fullMs + 10),
          reason: 'minimal tier must not be slower than full tier');
      expect(tester.takeException(), isNull);
    });
  });
}
