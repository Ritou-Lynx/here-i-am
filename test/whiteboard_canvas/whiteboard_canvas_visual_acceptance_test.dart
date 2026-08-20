/// M3 desktop visual-contract acceptance for the full-screen canvas shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

WhiteboardSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 20);
  return WhiteboardSnapshot(
    boards: [
      Board(boardId: 'board_m3', name: 'M3 全屏画布', createdAt: now),
    ],
    cards: [
      CardContract(
        cardId: 'card_m3',
        cardKind: CardKind.note,
        title: '视觉验收卡',
        body: 'Card 内容仍来自统一卡片仓库契约。',
        createdAt: now,
      ),
    ],
    boardItems: const [
      BoardItem(
        itemId: 'item_m3',
        boardId: 'board_m3',
        cardId: 'card_m3',
        x: -120,
        y: -80,
        width: 240,
        height: 160,
      ),
    ],
  );
}

Future<WhiteboardCanvasViewModel> _pump(
  WidgetTester tester, {
  DesktopWorkspaceTokens tokens = DesktopWorkspaceTokens.lieflatPalm,
}) async {
  final vm = WhiteboardCanvasViewModel(
    initialSnapshot: _snapshot(),
    boardId: 'board_m3',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: DesktopWorkspaceTheme(
        tokens: tokens,
        child: WhiteboardCanvasScreen(viewModel: vm),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return vm;
}

void main() {
  test('selected-face ARGB is opaque #E3E5C9', () {
    expect(WhiteboardCanvasTokens.cardSurfaceSelectedArgb, 0xFFE3E5C9);
    expect(WhiteboardCanvasTokens.cardSurfaceSelected.a, 1);
    expect(WhiteboardCanvasTokens.cardSurfaceSelected.r,
        closeTo(0xE3 / 255, 0.001));
    expect(WhiteboardCanvasTokens.cardSurfaceSelected.g,
        closeTo(0xE5 / 255, 0.001));
    expect(WhiteboardCanvasTokens.cardSurfaceSelected.b,
        closeTo(0xC9 / 255, 0.001));
  });

  for (final size in <Size>[const Size(1280, 720), const Size(1440, 900)]) {
    testWidgets('canvas fills ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      await _pump(tester);

      final canvas = find.byKey(const Key('wb_fullscreen_canvas'));
      expect(tester.getTopLeft(canvas), Offset.zero);
      expect(tester.getSize(canvas), size);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      expect(find.byKey(const Key('wb_navigation_group')), findsNothing);
      expect(find.byKey(const Key('wb_action_tools')), findsNothing);
      expect(find.byKey(const Key('wb_view_tools')), findsNothing);
      expect(find.byKey(const Key('wb_card_library_panel')), findsNothing);
    });
  }

  testWidgets('navigation, tools, and card library retreat completely',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('wb_canvas_chrome_launcher')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wb_navigation_group')), findsOneWidget);
    expect(find.byKey(const Key('wb_canvas_chrome_launcher')), findsNothing);

    await tester.tap(find.byTooltip('画布工具'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wb_action_tools')), findsOneWidget);
    expect(find.byKey(const Key('wb_view_tools')), findsOneWidget);

    await tester.tap(find.byTooltip('卡片库'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wb_card_library_panel')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('wb_card_library_panel')),
        matching: find.byTooltip('关闭'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wb_card_library_panel')), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('wb_action_tools')),
        matching: find.byTooltip('关闭画布工具'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wb_action_tools')), findsNothing);
    expect(find.byKey(const Key('wb_view_tools')), findsNothing);

    await tester.tap(find.byTooltip('收起画布控件'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wb_navigation_group')), findsNothing);
    expect(find.byKey(const Key('wb_canvas_chrome_launcher')), findsOneWidget);
  });

  testWidgets('M0 desktop semantic theme drives the canvas surface',
      (tester) async {
    const customCanvas = Color(0xFFEEE8DC);
    final tokens = DesktopWorkspaceTokens.lieflatPalm.copyWith(
      canvas: customCanvas,
      action: const Color(0xFF314B2C),
    );

    final vm = await _pump(tester, tokens: tokens);
    final scaffold = tester.widget<Scaffold>(
      find.byKey(const Key('wb_fullscreen_canvas_shell')),
    );
    expect(scaffold.backgroundColor, customCanvas);

    expect(vm.selection, isEmpty);
    await tester.tap(find.text('视觉验收卡'));
    await tester.pumpAndSettle();
    expect(vm.selection.selectedItemIds, {'item_m3'});
    expect(vm.exportForSave().boardItems.single.itemId, 'item_m3');
  });
}
