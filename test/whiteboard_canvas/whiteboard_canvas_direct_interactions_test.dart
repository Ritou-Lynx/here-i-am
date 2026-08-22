import 'dart:async';
import 'dart:io';
import 'dart:math' show Point;
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
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/interactions/ui_intent.dart';
import 'package:memex/ui/whiteboard_canvas/engine/flutter_canvas_adapter.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

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
  Completer<void>? createRelease;
  Completer<CardContract>? created;
  int softDeleteFailures = 0;
  int softDeleteCalls = 0;

  @override
  Future<CardContract> createTextCard({
    String? cardId,
    String title = '',
    String body = '',
    List<String> tags = const [],
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
    DateTime? createdAt,
  }) async {
    final card = await super.createTextCard(
      cardId: cardId,
      title: title,
      body: body,
      tags: tags,
      ownerSpace: ownerSpace,
      createdBy: createdBy,
      createdAt: createdAt,
    );
    created?.complete(card);
    await createRelease?.future;
    return card;
  }

  @override
  Future<bool> softDeleteCard(String cardId, {DateTime? at}) async {
    softDeleteCalls++;
    if (softDeleteFailures > 0) {
      softDeleteFailures--;
      throw StateError('scripted compensation failure');
    }
    return super.softDeleteCard(cardId, at: at);
  }

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
    expect(
      vm.exportForSave().edges.single.style['from_anchor_side'],
      'right',
    );
    expect(
      vm.exportForSave().edges.single.style['to_anchor_side'],
      isIn(<String>['top', 'right', 'bottom', 'left']),
    );

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

  testWidgets('连线更新与删除持久化失败均回滚且不污染后续快照', (tester) async {
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    expect(
      vm.createEdge(
        fromItemId: 'item_card_a',
        toItemId: 'item_card_b',
      ),
      isTrue,
    );
    final original = vm.exportForSave().edges.single;
    final logLength = vm.operationLog.length;
    var persistCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        onPersistSnapshot: () async {
          persistCalls++;
          return false;
        },
      ),
    ));
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('wb_edge_quick_label')), '失败标签');
    await tester.tap(find.byKey(const Key('wb_edge_quick_save')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(vm.exportForSave().edges.single.toJson(), original.toJson());
    expect(vm.operationLog, hasLength(logLength));
    expect(find.text('连线没有保存成功'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wb_edge_quick_delete')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(vm.exportForSave().edges.single.toJson(), original.toJson());
    expect(vm.operationLog, hasLength(logLength));
    expect(vm.selectedEdge?.edgeId, original.edgeId);
    expect(find.byKey(const Key('wb_edge_quick_editor')), findsOneWidget);
    expect(persistCalls, 2);

    final laterSave = vm.exportForSave();
    expect(laterSave.edges.single.direction, EdgeDirection.undirected);
    expect(laterSave.edges.single.label, isNull);
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
      find.byKey(const Key('rich_text_continuous_document')),
    );

    final createdItemId = vm.exportForSave().boardItems.single.itemId;
    expect(
      find.descendant(
        of: find.byKey(Key('wb_card_$createdItemId')),
        matching: find.byKey(const Key('wb_compact_card_editor')),
      ),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('wb_compact_editor_close')), findsNothing);
    expect(find.byKey(const Key('wb_compact_editor_expand')), findsNothing);
    expect(find.byKey(const Key('wb_compact_editor_save')), findsNothing);

    final records = await tester.runAsync(harness.repository.listCards);
    expect(records, hasLength(1));
    expect(vm.exportForSave().boardItems, hasLength(1));
    expect(persisted?.boardItems, hasLength(1));
    expect(vm.exportForSave().boardItems.single.x, closeTo(-880, 0.01));
    expect(vm.exportForSave().boardItems.single.y, closeTo(70, 0.01));
    await tester.tapAt(const Offset(30, 560));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wb_compact_card_editor')), findsNothing);
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

  testWidgets('普通卡双击把编辑 surface 嵌入 BoardItem 且隔离拖动', (tester) async {
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardEditSurfaceBuilder: (context, request) => ColoredBox(
          key: const ValueKey('test_embedded_edit_surface'),
          color: Colors.amber,
          child: Text('editing ${request.cardId}'),
        ),
      ),
    ));
    await tester.pump();

    final card = find.byKey(const Key('wb_card_item_card_a'));
    final beforeRect = tester.getRect(card);
    final before = vm
        .exportForSave()
        .boardItems
        .firstWhere((item) => item.itemId == 'item_card_a');
    await _doubleTapAt(tester, tester.getCenter(find.text('Card A')));
    await tester.pump();

    final surface = find.byKey(const ValueKey('test_embedded_edit_surface'));
    expect(surface, findsOneWidget);
    expect(find.descendant(of: card, matching: surface), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.getRect(card), beforeRect);
    expect(tester.getRect(surface), beforeRect);
    for (final side in ['top', 'right', 'bottom', 'left']) {
      expect(find.byKey(Key('wb_connect_item_card_a_$side')), findsNothing);
    }
    expect(find.byKey(const Key('wb_resize_item_card_a')), findsNothing);
    expect(find.byKey(const Key('wb_rotate_item_card_a')), findsNothing);

    await tester.drag(surface, const Offset(90, 60));
    await tester.pump();
    final after = vm
        .exportForSave()
        .boardItems
        .firstWhere((item) => item.itemId == 'item_card_a');
    expect(after.x, before.x);
    expect(after.y, before.y);
    expect(after.width, before.width);
    expect(after.height, before.height);
  });

  testWidgets('原位编辑 Esc 保存退出且不改变 BoardItem 几何', (tester) async {
    final harness = _RepoHarness.create();
    addTearDown(harness.dispose);
    final original = (await tester.runAsync(
      () => harness.repository.createTextCard(
        cardId: 'card_escape_inline',
        title: '原位卡片',
        body: '编辑前',
      ),
    ))!;
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(cards: [original]),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardRepository: harness.repository,
      ),
    ));
    await tester.pump();
    final itemBefore = vm.exportForSave().boardItems.single;

    await _doubleTapAt(tester, tester.getCenter(find.text('原位卡片')));
    final field = find.byKey(const Key('rich_text_continuous_document'));
    await _pumpUntil(tester, field);
    await tester.tap(field);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '编辑后正文',
      selection: TextSelection.collapsed(offset: 5),
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wb_compact_card_editor')), findsNothing);
    final itemAfter = vm.exportForSave().boardItems.single;
    expect(itemAfter.x, itemBefore.x);
    expect(itemAfter.y, itemBefore.y);
    expect(itemAfter.width, itemBefore.width);
    expect(itemAfter.height, itemBefore.height);
    final stored = (await tester.runAsync(
      () => harness.repository.getCard('card_escape_inline'),
    ))!;
    expect(stored.card.body, '编辑后正文');
  });

  testWidgets('同一 Card 的两个 BoardItem 只编辑被双击的摆放', (tester) async {
    final now = DateTime.utc(2026, 8, 22);
    final sharedCard = CardContract(
      cardId: 'card_shared',
      cardKind: CardKind.note,
      title: '共享内容',
      body: '同一张 Card',
      createdAt: now,
    );
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: WhiteboardSnapshot(
        boards: [
          Board(boardId: 'board_direct', name: '双摆放', createdAt: now),
        ],
        cards: [sharedCard],
        boardItems: const [
          BoardItem(
            itemId: 'item_shared_left',
            boardId: 'board_direct',
            cardId: 'card_shared',
            x: -260,
            y: -80,
            width: 180,
            height: 140,
          ),
          BoardItem(
            itemId: 'item_shared_right',
            boardId: 'board_direct',
            cardId: 'card_shared',
            x: 80,
            y: -80,
            width: 180,
            height: 140,
          ),
        ],
      ),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardEditSurfaceBuilder: (context, request) => ColoredBox(
          key: const ValueKey('test_shared_card_edit_surface'),
          color: Colors.amber,
          child: Text('editing ${request.cardId}'),
        ),
      ),
    ));
    await tester.pump();

    final left = find.byKey(const Key('wb_card_item_shared_left'));
    final right = find.byKey(const Key('wb_card_item_shared_right'));
    await _doubleTapAt(
      tester,
      tester.getCenter(
        find.descendant(of: right, matching: find.text('共享内容')),
      ),
    );
    await tester.pump();

    final surface = find.byKey(const ValueKey('test_shared_card_edit_surface'));
    expect(surface, findsOneWidget);
    expect(find.descendant(of: right, matching: surface), findsOneWidget);
    expect(find.descendant(of: left, matching: surface), findsNothing);
    expect(
      find.descendant(of: left, matching: find.text('共享内容')),
      findsOneWidget,
    );
  });

  testWidgets('白板卡片标题和正文复用全局混排字体 Token', (tester) async {
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(viewModel: vm),
    ));
    await tester.pump();

    final title = tester.widget<Text>(find.text('Card A'));
    final body = tester.widget<Text>(find.text('A body'));
    for (final text in [title, body]) {
      expect(text.style?.fontFamily, richTextCodeFamily);
      expect(text.style?.fontFamilyFallback, contains(richTextCjkFamily));
    }
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

  testWidgets('建卡保存失败只局部回滚，保留既有 undo/redo 和操作日志', (tester) async {
    final harness = _RepoHarness.create();
    addTearDown(harness.dispose);
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(),
      boardId: 'board_direct',
    );
    vm.selectItem('item_card_a');
    vm.moveSelectedItems(24, 0);
    vm.undo();
    final before = vm.exportForSave();
    final logLength = vm.operationLog.length;
    expect(vm.canRedo, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardRepository: harness.repository,
        onPersistSnapshot: () async => false,
      ),
    ));
    await _doubleTapAt(tester, const Offset(650, 470));
    await tester.pump(const Duration(milliseconds: 800));

    expect(vm.exportForSave().boardItems.map((item) => item.toJson()),
        before.boardItems.map((item) => item.toJson()));
    expect(vm.operationLog, hasLength(logLength));
    expect(vm.canRedo, isTrue);
    vm.redo();
    expect(vm.exportForSave().boardItems.first.x, -206);
  });

  testWidgets('软删补偿失败可见且可重试，不留下 BoardItem', (tester) async {
    final harness = _RepoHarness.create();
    addTearDown(harness.dispose);
    harness.repository.softDeleteFailures = 1;
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
    await _doubleTapAt(tester, const Offset(650, 470));
    await _pumpUntil(
      tester,
      find.byKey(const Key('wb_pending_card_compensation')),
    );
    expect(vm.exportForSave().boardItems, isEmpty);
    expect(await tester.runAsync(harness.repository.listCards), hasLength(1));

    await tester.tap(find.byKey(const Key('wb_retry_card_compensation')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('wb_pending_card_compensation')), findsNothing);
    expect(await tester.runAsync(harness.repository.listCards), isEmpty);
    expect(harness.repository.softDeleteCalls, 2);
  });

  testWidgets('createTextCard 返回时页面已销毁则补偿 Card 且不操作旧 VM', (tester) async {
    final harness = _RepoHarness.create();
    addTearDown(harness.dispose);
    final release = Completer<void>();
    final created = Completer<CardContract>();
    harness.repository
      ..createRelease = release
      ..created = created;
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _emptySnapshot(),
      boardId: 'board_direct',
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        cardRepository: harness.repository,
      ),
    ));
    await _doubleTapAt(tester, const Offset(650, 470));
    await tester
        .runAsync(() => created.future.timeout(const Duration(seconds: 3)));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    release.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(vm.exportForSave().boardItems, isEmpty);
    expect(vm.operationLog, isEmpty);
    expect(await tester.runAsync(harness.repository.listCards), isEmpty);
    expect(harness.repository.softDeleteCalls, 1);
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
    final savedProjection = CardContract(
      cardId: updated.cardId,
      cardKind: updated.cardKind,
      title: updated.title,
      body: '你好世界',
      createdAt: updated.createdAt,
      updatedAt: DateTime.utc(2026, 8, 22, 1),
    );
    final saveDone = harness.repository.expectNextSave(savedProjection);
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
    expect(vm.exportForSave().cards.single.body, '你好世界');

    vm.selectItem('item_card_complex');
    vm.moveSelectedItems(40, 0);
    vm.undo();
    expect(vm.exportForSave().cards.single.body, '你好世界');
    vm.redo();
    expect(vm.exportForSave().cards.single.body, '你好世界');
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

  testWidgets('readonly UI 与 VM/adapter 双层拒绝编辑、放置及撤销重做', (tester) async {
    final snapshot = _snapshot();
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: snapshot,
      boardId: 'board_direct',
    );
    vm.selectItem('item_card_a');
    vm.moveSelectedItems(20, 0);
    vm.undo();
    vm.setReadonly(true);
    final before = vm.exportForSave().toJson();
    final logLength = vm.operationLog.length;

    vm.placeCard(cardId: 'card_a');
    vm.placeCardOnBoard(
      cardId: 'card_a',
      boardId: 'board_direct',
      x: 0,
      y: 0,
    );
    vm.moveItems({'item_card_a': const Point(20, 20)});
    vm.resizeItem(itemId: 'item_card_a', width: 500, height: 500);
    vm.removeItems(['item_card_a']);
    vm.createEdge(fromItemId: 'item_card_a', toItemId: 'item_card_b');
    vm.undo();
    vm.redo();
    expect(vm.exportForSave().toJson(), before);
    expect(vm.operationLog, hasLength(logLength));

    final adapter = FlutterCanvasAdapter(snapshot)..setReadonly(true);
    final adapterBefore = adapter.exportSnapshot().toJson();
    adapter.placeCard(boardId: 'board_direct', cardId: 'card_a');
    adapter.moveItems(
      boardId: 'board_direct',
      deltas: {'item_card_a': const Point(5, 5)},
    );
    adapter.removeItems(
      boardId: 'board_direct',
      itemIds: ['item_card_a'],
    );
    expect(adapter.exportSnapshot().toJson(), adapterBefore);

    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasScreen(
        viewModel: vm,
        onOpenCard: (_) => opened++,
      ),
    ));
    await tester.pump();
    await _doubleTapAt(tester, tester.getCenter(find.text('Card A')));
    expect(opened, 1);
    expect(find.byKey(const Key('wb_compact_card_editor')), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(vm.exportForSave().toJson(), before);
  });
}
