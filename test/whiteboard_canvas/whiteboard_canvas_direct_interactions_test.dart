import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/interactions/ui_intent.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

WhiteboardSnapshot _snapshot({List<CardContract>? cards}) {
  final now = DateTime.utc(2026, 8, 22);
  final values = cards ??
      [
        CardContract(
          cardId: 'card_a',
          cardKind: CardKind.note,
          title: 'Card A',
          body: 'A body',
          createdAt: now,
        ),
        CardContract(
          cardId: 'card_b',
          cardKind: CardKind.note,
          title: 'Card B',
          body: 'B body',
          createdAt: now,
        ),
      ];
  return WhiteboardSnapshot(
    boards: [Board(boardId: 'board_direct', name: '直接交互', createdAt: now)],
    cards: values,
    boardItems: [
      for (var i = 0; i < values.length; i++)
        BoardItem(
          itemId: 'item_${values[i].cardId}',
          boardId: 'board_direct',
          cardId: values[i].cardId,
          x: -230 + i * 300,
          y: -80,
          width: 160,
          height: 120,
          zIndex: i,
        ),
    ],
  );
}

WhiteboardSnapshot _emptySnapshot() => WhiteboardSnapshot(
      boards: [
        Board(
          boardId: 'board_direct',
          name: '空白板',
          createdAt: DateTime.utc(2026, 8, 22),
        ),
      ],
      viewport: const BoardViewport(centerX: -1000),
    );

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

Future<void> _doubleTapAt(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 70));
  await tester.tapAt(point);
  await tester.pump();
}

class _RepoHarness {
  _RepoHarness(this.root, this.db, this.repository);

  final Directory root;
  final AppDatabase db;
  final _TrackingRepository repository;

  static _RepoHarness create() {
    final root = Directory.systemTemp.createTempSync('w1_direct_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    return _RepoHarness(
      root,
      db,
      _TrackingRepository(db: db, whiteboardRoot: root),
    );
  }

  Future<void> dispose() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

class _TrackingRepository extends UnifiedCardRepository {
  _TrackingRepository({required super.db, required super.whiteboardRoot});

  Completer<void>? _nextSave;
  CardContract? _nextSaveResult;
  RichTextDocument? capturedDocument;

  Future<void> expectNextSave(CardContract result) {
    _nextSave = Completer<void>();
    _nextSaveResult = result;
    return _nextSave!.future;
  }

  @override
  Future<CardContract> saveRichText(
    String cardId,
    RichTextDocument document, {
    String? title,
  }) async {
    final expected = _nextSaveResult;
    if (expected != null) {
      capturedDocument = document;
      _nextSaveResult = null;
      _nextSave?.complete();
      _nextSave = null;
      return expected;
    }
    final saved = await super.saveRichText(cardId, document, title: title);
    _nextSave?.complete();
    _nextSave = null;
    return saved;
  }
}

void main() {
  // Tests are intentionally product-facing: they exercise pointer gestures
  // and Repository persistence, not private canvas implementation details.
  testWidgets('偏移容器内四向锚点拖线，自环与空白落点取消', (tester) async {
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 80,
            top: 50,
            width: 600,
            height: 500,
            child: WhiteboardCanvasArea(viewModel: vm),
          ),
        ]),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Card A'));
    await tester.pump();
    final handle = find.byKey(const Key('wb_connect_item_card_a_right'));
    expect(handle, findsOneWidget);
    final create = await tester.startGesture(tester.getCenter(handle));
    await create.moveTo(tester.getCenter(find.text('Card B')));
    await create.up();
    await tester.pump();
    expect(vm.exportForSave().edges, hasLength(1));
    expect(vm.exportForSave().edges.single.direction, EdgeDirection.undirected);
    expect(vm.exportForSave().edges.single.label, isNull);

    await tester.tap(find.text('Card A'));
    await tester.pump();
    final self = await tester.startGesture(tester.getCenter(handle));
    await self.moveTo(tester.getCenter(find.text('Card A')));
    await self.up();
    final empty = await tester.startGesture(tester.getCenter(handle));
    await empty.moveTo(const Offset(100, 100));
    await empty.up();
    await tester.pump();
    expect(vm.exportForSave().edges, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('连线创建后轻量修改方向标签并从快照恢复', (tester) async {
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    WhiteboardSnapshot? persisted;
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        onPersistSnapshot: () async {
          persisted = vm.exportForSave();
          return true;
        },
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Card A'));
    await tester.pump();
    final handle = find.byKey(const Key('wb_connect_item_card_a_right'));
    final create = await tester.startGesture(tester.getCenter(handle));
    await create.moveTo(tester.getCenter(find.text('Card B')));
    await create.up();
    await tester.pump();

    final editor = find.byKey(const Key('wb_edge_quick_editor'));
    expect(editor, findsOneWidget);
    await tester.enterText(find.byKey(const Key('wb_edge_quick_label')), '支持');
    await tester.tap(find.descendant(
      of: editor,
      matching: find.byIcon(Icons.arrow_forward_rounded),
    ));
    await tester.tap(find.byKey(const Key('wb_edge_quick_save')));
    await tester.pump(const Duration(milliseconds: 100));

    final edge = persisted!.edges.single;
    expect(edge.direction, EdgeDirection.directed);
    expect(edge.label, '支持');
    final restarted = WhiteboardCanvasViewModel(
      initialSnapshot: persisted!,
      boardId: 'board_direct',
    );
    expect(restarted.exportForSave().edges.single.toJson(), edge.toJson());
  });

  testWidgets('空白双击建真实 Card，移除 BoardItem 不删 Card', (tester) async {
    final harness = _RepoHarness.create();
    addTearDown(harness.dispose);
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _emptySnapshot(),
      boardId: 'board_direct',
    );
    WhiteboardSnapshot? persisted;
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardRepository: harness.repository,
        onPersistSnapshot: () async {
          persisted = vm.exportForSave();
          return true;
        },
      ),
    ));
    await tester.pump();
    await _doubleTapAt(tester, const Offset(650, 470));
    await _pumpUntil(
      tester,
      find.byKey(const Key('wb_compact_editor_close')),
    );

    final records = await tester.runAsync(harness.repository.listCards);
    expect(records, hasLength(1));
    expect(vm.exportForSave().boardItems, hasLength(1));
    expect(persisted?.boardItems, hasLength(1));
    expect(vm.exportForSave().boardItems.single.x, closeTo(-880, 0.01));
    expect(vm.exportForSave().boardItems.single.y, closeTo(70, 0.01));
    await tester.tap(find.byKey(const Key('wb_compact_editor_close')));
    await tester.pump();
    vm.handleIntent(
      SelectItemIntent(itemId: vm.exportForSave().boardItems.single.itemId),
    );
    vm.removeSelectedItems();
    expect(vm.exportForSave().boardItems, isEmpty);
    expect(
      await tester.runAsync(
          () => harness.repository.getCard(records!.single.card.cardId)),
      isNotNull,
    );
    final restarted = WhiteboardCanvasViewModel(
      initialSnapshot: persisted!,
      boardId: 'board_direct',
    );
    expect(restarted.exportForSave().boardItems, hasLength(1));
  });

  testWidgets('布局保存失败回滚 BoardItem 并软删新 Card', (tester) async {
    final harness = _RepoHarness.create();
    addTearDown(harness.dispose);
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _emptySnapshot(),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardRepository: harness.repository,
        onPersistSnapshot: () async => false,
      ),
    ));
    await tester.pump();
    await _doubleTapAt(tester, const Offset(650, 470));
    await tester.pump(const Duration(milliseconds: 800));
    expect(vm.exportForSave().boardItems, isEmpty);
    expect(await tester.runAsync(harness.repository.listCards), isEmpty);
    expect(find.byKey(const Key('wb_compact_card_editor')), findsNothing);
  });

  testWidgets('compact editor 保留复杂文档且 Ctrl+S 保存中文 IME', (tester) async {
    final harness = _RepoHarness.create();
    addTearDown(harness.dispose);
    final card = (await tester.runAsync(
      () => harness.repository.createTextCard(
        cardId: 'card_complex',
        title: '复杂卡片',
      ),
    ))!;
    const original = RichTextDocument(
      blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '原文'),
        RichTextBlock(
          type: BlockType.heading,
          text: '保留标题',
          marks: [RichTextMark(type: MarkType.bold, start: 0, end: 4)],
          attrs: {'level': 2},
        ),
        RichTextBlock(
          type: BlockType.image,
          attrs: {'asset_ref_id': 'asset_keep', 'alt': '保留图片'},
        ),
      ],
      assetRefs: [
        RichTextAssetRef(
          refId: 'asset_keep',
          objectRef: 'objects/sha256-keep',
          mimeType: 'image/png',
        ),
      ],
    );
    final updated = (await tester.runAsync(
      () => harness.repository.saveRichText(
        card.cardId,
        original,
        title: card.title,
      ),
    ))!;
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(cards: [updated]),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardRepository: harness.repository,
      ),
    ));
    await tester.pump();
    await _doubleTapAt(tester, tester.getCenter(find.text('复杂卡片')));
    final field = find.byKey(const Key('rich_text_block_0_root'));
    await _pumpUntil(tester, field);
    await tester.tap(field);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '你好',
      composing: TextRange(start: 0, end: 2),
    ));
    await tester.pump();
    expect(
      tester.widget<TextField>(field).controller!.value.composing,
      const TextRange(start: 0, end: 2),
    );
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '你好世界',
      selection: TextSelection.collapsed(offset: 4),
    ));
    await tester.pump();
    final saveDone = harness.repository.expectNextSave(updated);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.runAsync(
      () => saveDone.timeout(const Duration(seconds: 3)),
    );
    await tester.pump();
    final saved = harness.repository.capturedDocument;
    expect(saved?.blocks.first.text, '你好世界');
    expect(saved?.blocks[1].type, BlockType.heading);
    expect(saved?.blocks[1].marks.single.type, MarkType.bold);
    expect(saved?.blocks[2].type, BlockType.image);
    expect(saved?.assetRefs.single.objectRef, 'objects/sha256-keep');
  });

  testWidgets('右键短按开菜单，超过阈值拖动只平移', (tester) async {
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WhiteboardCanvasArea(viewModel: vm)),
    ));
    await tester.pump();
    final click = await tester.startGesture(
      tester.getCenter(find.text('Card A')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await click.up();
    await tester.pump();
    expect(find.text('快捷编辑'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final before = vm.viewport;
    final drag = await tester.startGesture(
      const Offset(80, 90),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await drag.moveBy(const Offset(36, 24));
    await drag.up();
    await tester.pump();
    expect(vm.viewport.centerX, isNot(before.centerX));
    expect(vm.viewport.centerY, isNot(before.centerY));
    expect(find.text('新建文字卡片'), findsNothing);
    expect(find.text('快捷编辑'), findsNothing);
  });

  testWidgets('Source Card 双击和右键主动作直接打开来源', (tester) async {
    final source = CardContract(
      cardId: 'card_source',
      cardKind: CardKind.source,
      sourceId: 'src_source',
      title: '来源卡',
      body: '来源摘要不允许在画布冒充备注编辑',
      createdAt: DateTime.utc(2026, 8, 22),
    );
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(cards: [source]),
      boardId: 'board_direct',
    );
    var openCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        onOpenCard: (_) => openCount++,
      ),
    ));
    await tester.pump();

    await _doubleTapAt(tester, tester.getCenter(find.text('来源卡')));
    expect(openCount, 1);
    expect(find.byKey(const Key('wb_compact_card_editor')), findsNothing);

    final rightClick = await tester.startGesture(
      tester.getCenter(find.text('来源卡')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await rightClick.up();
    await tester.pumpAndSettle();
    expect(find.text('打开来源'), findsOneWidget);
    expect(find.text('快捷编辑'), findsNothing);
    await tester.tap(find.text('打开来源'));
    await tester.pump();
    expect(openCount, 2);
    expect(find.byKey(const Key('wb_compact_card_editor')), findsNothing);
  });

  test('createEdge 拒绝自环和未知端点', () {
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    expect(
      vm.createEdge(fromItemId: 'item_card_a', toItemId: 'item_card_a'),
      isFalse,
    );
    expect(
      vm.createEdge(fromItemId: 'item_card_a', toItemId: 'item_missing'),
      isFalse,
    );
    expect(vm.exportForSave().edges, isEmpty);
  });
}
