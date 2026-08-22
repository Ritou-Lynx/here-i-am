import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';

void main() {
  testWidgets(
      'real Repository Card → board → consumer → save → reconnect → remove',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('f1_product_loop_');
    final dbFile = File('${root.path}${Platform.pathSeparator}canvas.sqlite');
    var db = AppDatabase.forTesting(NativeDatabase(dbFile));
    var repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    var store = WhiteboardDriftStore(db);
    var dbOpen = true;
    addTearDown(() async {
      if (dbOpen) await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    const cardId = 'card_f1_real_note';
    await tester.runAsync(() => repository.createTextCard(
          cardId: cardId,
          title: '真实文字卡',
          body: '来自 UnifiedCardRepository 的正文',
        ));
    final boardId =
        (await tester.runAsync(() => store.createBoard(name: 'F1 产品闭环')))!;

    WhiteboardSnapshot? pendingSave;
    var router = _router(
      boardId: boardId,
      store: store,
      repository: repository,
      saveSnapshot: (_, snapshot) async {
        pendingSave = snapshot;
        return true;
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);
    await _openCanvasNavigation(tester);
    expect(find.text('F1 产品闭环'), findsOneWidget);
    expect(find.text('真实文字卡'), findsNothing,
        reason: 'an empty board must not invent fixture cards');

    await tester.tap(find.byTooltip('卡片库'));
    await _settle(tester);
    expect(
        find.byKey(const Key('wb_lib_row_card_f1_real_note')), findsOneWidget);
    await tester.tap(find.text('真实文字卡'));
    await _settle(tester);
    await tester.tap(find.byTooltip('关闭'));
    await _settle(tester);
    expect(find.text('真实文字卡'), findsOneWidget);

    await _doubleTap(tester, find.text('真实文字卡'));
    await _waitForWidget(
        tester, find.byKey(const Key('wb_compact_editor_expand')));
    final embeddedEditor = find.byKey(const Key('wb_compact_card_editor'));
    expect(embeddedEditor, findsOneWidget);
    expect(
      find.ancestor(
        of: embeddedEditor,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget.key is Key &&
              widget.key.toString().contains('wb_card_item_'),
        ),
      ),
      findsWidgets,
    );
    expect(find.byKey(const Key('wb_compact_editor_position')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byKey(const Key('wb_compact_editor_expand')));
    await _waitForWidget(tester, find.text('文字卡消费页'));
    expect(find.text('文字卡消费页'), findsOneWidget);
    expect(pendingSave, isNotNull);
    expect(
      await tester.runAsync(() => store.save(boardId, pendingSave!)),
      isTrue,
    );

    await tester.tap(find.text('返回白板'));
    await _settle(tester);
    expect(find.text('真实文字卡'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    router.dispose();
    await db.close();
    dbOpen = false;

    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    dbOpen = true;
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    store = WhiteboardDriftStore(db);
    pendingSave = null;
    router = _router(
      boardId: boardId,
      store: store,
      repository: repository,
      saveSnapshot: (_, snapshot) async {
        pendingSave = snapshot;
        return true;
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);
    expect(find.text('真实文字卡'), findsOneWidget,
        reason: 'a new SQLite connection must restore the placement');

    await tester.tap(find.text('真实文字卡'));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await _settle(tester);
    await _openCanvasTools(tester);
    await tester.tap(find.byTooltip('保存快照 (Ctrl+S)'));
    await _settle(tester);
    expect(pendingSave, isNotNull);
    expect(
      await tester.runAsync(() => store.save(boardId, pendingSave!)),
      isTrue,
    );
    expect(find.text('真实文字卡'), findsNothing);
    expect(await tester.runAsync(() => repository.getCard(cardId)), isNotNull,
        reason: 'removing a BoardItem must preserve the same Repository Card');
    expect(await tester.runAsync(repository.listCards), hasLength(1));
    router.dispose();
  });

  testWidgets('product routing follows CardKind before optional sourceId',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('f1_route_matrix_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final store = WhiteboardDriftStore(db);
    addTearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final committed = (await tester
        .runAsync(() => repository.commitIngestion(_sourceIngestion())))!;
    await tester.runAsync(() async {
      await repository.createTextCard(
        cardId: 'card_annotation_source',
        title: '带来源批注卡',
      );
      await repository.updateCardMetadata(
        'card_annotation_source',
        cardKind: CardKind.annotation,
      );
      await repository.linkSourceToCard(
        'card_annotation_source',
        committed.source.sourceId,
      );
      await repository.createTextCard(
        cardId: 'card_source_missing',
        title: '缺少来源的来源卡',
      );
      await repository.updateCardMetadata(
        'card_source_missing',
        cardKind: CardKind.source,
      );
      await repository.createTextCard(
        cardId: 'card_plain_note',
        title: '普通文字卡',
      );
    });
    final boardId =
        (await tester.runAsync(() => store.createBoard(name: '来源路由')))!;
    expect(
      await tester.runAsync(() => store.save(
            boardId,
            _routingLayout(
              boardId,
              [
                committed.card.cardId,
                'card_annotation_source',
                'card_source_missing',
                'card_plain_note',
              ],
            ),
          )),
      isTrue,
    );
    final router = _router(
      boardId: boardId,
      store: store,
      repository: repository,
      saveSnapshot: (_, __) async => true,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);

    final cases = [
      (
        title: 'F1 来源卡',
        page: '来源消费页',
        marker: 'source:${committed.source.sourceId}',
        compact: false,
      ),
      (
        title: '带来源批注卡',
        page: '文字卡消费页',
        marker: 'card:card_annotation_source',
        compact: true,
      ),
      (
        title: '缺少来源的来源卡',
        page: '文字卡消费页',
        marker: 'card:card_source_missing',
        compact: false,
      ),
      (
        title: '普通文字卡',
        page: '文字卡消费页',
        marker: 'card:card_plain_note',
        compact: true,
      ),
    ];
    for (final routeCase in cases) {
      await _doubleTap(tester, find.text(routeCase.title));
      if (routeCase.compact) {
        await _waitForWidget(
            tester, find.byKey(const Key('wb_compact_editor_expand')));
        await tester.tap(find.byKey(const Key('wb_compact_editor_expand')));
      } else {
        expect(find.byKey(const Key('wb_compact_card_editor')), findsNothing);
      }
      await _waitForWidget(tester, find.text(routeCase.page));
      expect(find.text(routeCase.marker), findsOneWidget);
      router.pop();
      await _settle(tester);
    }
    router.dispose();
  });

  testWidgets(
      'invalid Card reference stays honest and repository failure retries',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('f1_failures_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final store = WhiteboardDriftStore(db);
    addTearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final boardId =
        (await tester.runAsync(() => store.createBoard(name: '失效引用')))!;
    expect(
      await tester.runAsync(() => store.save(
            boardId,
            _layout(
              boardId,
              cardId: 'card_missing',
              itemId: 'item_missing',
            ),
          )),
      isTrue,
    );
    var router = _router(
      boardId: boardId,
      store: store,
      repository: repository,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);
    expect(find.text('失效卡片引用'), findsOneWidget);
    await _doubleTap(tester, find.text('失效卡片引用'));
    await _settle(tester);
    expect(router.routeInformationProvider.value.uri.path,
        AppRoutes.whiteboardCanvasPath(boardId));

    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    router = _router(
      boardId: boardId,
      store: store,
      repositoryLoader: () async => throw StateError('repository offline'),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);
    expect(find.textContaining('加载白板失败'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('whiteboard_canvas_retry')), findsOneWidget);
    router.dispose();
  });

  testWidgets(
      'save failure is visible, retryable, and keeps content out of save',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('f1_save_failure_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final store = WhiteboardDriftStore(db);
    addTearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    const cardId = 'card_save_failure';
    await tester.runAsync(() => repository.createTextCard(
          cardId: cardId,
          title: '保存失败卡',
        ));
    final boardId =
        (await tester.runAsync(() => store.createBoard(name: '保存失败')))!;
    expect(
      await tester.runAsync(() => store.save(
            boardId,
            _layout(boardId, cardId: cardId, itemId: 'item_save_failure'),
          )),
      isTrue,
    );
    WhiteboardSnapshot? attempted;
    final router = _router(
      boardId: boardId,
      store: store,
      repository: repository,
      saveSnapshot: (_, snapshot) async {
        attempted = snapshot;
        return false;
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester);
    await _openCanvasTools(tester);
    await tester.tap(find.byTooltip('保存快照 (Ctrl+S)'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('whiteboard_save_error')), findsOneWidget);
    expect(find.text('白板没有保存成功，请重试。'), findsWidgets);
    expect(attempted, isNotNull);
    expect(attempted!.cards, isEmpty,
        reason: 'canvas persistence must write layout only');
    expect(attempted!.sources, isEmpty);
    expect(attempted!.sourceVersions, isEmpty);
    expect(await tester.runAsync(() => repository.getCard(cardId)), isNotNull);
    router.dispose();
  });

  test('500 real Repository cards hydrate without material regression',
      () async {
    final root = Directory.systemTemp.createTempSync('f1_repository_500_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    addTearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    for (var i = 0; i < 500; i++) {
      await repository.createTextCard(
        cardId: 'f1_perf_card_$i',
        title: 'F1 Card $i',
        body: 'Repository hydration body $i',
      );
    }
    final stopwatch = Stopwatch()..start();
    final records = await repository.listCards();
    stopwatch.stop();

    debugPrint('F1_REPOSITORY_500 list_ms=${stopwatch.elapsedMilliseconds}');
    expect(records, hasLength(500));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openCanvasNavigation(WidgetTester tester) async {
  if (find.byKey(const Key('wb_navigation_group')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('wb_canvas_chrome_launcher')));
    await _settle(tester);
  }
}

Future<void> _openCanvasTools(WidgetTester tester) async {
  await _openCanvasNavigation(tester);
  if (find.byKey(const Key('wb_action_tools')).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('画布工具'));
    await _settle(tester);
  }
}

Future<void> _waitForWidget(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _settle(tester);
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, kind: ui.PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder, kind: ui.PointerDeviceKind.mouse);
}

GoRouter _router({
  required String boardId,
  required WhiteboardDriftStore store,
  UnifiedCardRepository? repository,
  Future<UnifiedCardRepository> Function()? repositoryLoader,
  Future<bool> Function(String, WhiteboardSnapshot)? saveSnapshot,
}) {
  return GoRouter(
    initialLocation: AppRoutes.whiteboardCanvasPath(boardId),
    routes: [
      GoRoute(
        path: AppRoutes.whiteboard,
        builder: (_, __) => const Scaffold(body: Text('白板索引')),
      ),
      GoRoute(
        path: AppRoutes.whiteboardCanvas,
        builder: (_, state) => WhiteboardCanvasRouteScreen(
          boardId: state.pathParameters['boardId']!,
          store: store,
          cardRepository: repository,
          repositoryLoader: repositoryLoader,
          saveSnapshot: saveSnapshot,
        ),
      ),
      GoRoute(
        path: AppRoutes.cardEdit,
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const Text('文字卡消费页'),
              Text('card:${state.pathParameters['cardId']}'),
              TextButton(
                onPressed: context.pop,
                child: const Text('返回白板'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.sourceStudy,
        builder: (_, state) => Scaffold(
          body: Column(
            children: [
              const Text('来源消费页'),
              Text('source:${state.pathParameters['sourceId']}'),
            ],
          ),
        ),
      ),
    ],
  );
}

WhiteboardSnapshot _layout(
  String boardId, {
  required String cardId,
  required String itemId,
}) {
  final now = DateTime.utc(2026, 8, 19);
  return WhiteboardSnapshot(
    boards: [Board(boardId: boardId, name: '测试白板', createdAt: now)],
    boardItems: [
      BoardItem(
        itemId: itemId,
        boardId: boardId,
        cardId: cardId,
        x: -120,
        y: -80,
        width: 240,
        height: 160,
      ),
    ],
  );
}

WhiteboardSnapshot _routingLayout(String boardId, List<String> cardIds) {
  final now = DateTime.utc(2026, 8, 19);
  const positions = [
    (-260.0, -160.0),
    (20.0, -160.0),
    (-260.0, 20.0),
    (20.0, 20.0),
  ];
  return WhiteboardSnapshot(
    boards: [Board(boardId: boardId, name: '来源路由', createdAt: now)],
    boardItems: [
      for (var i = 0; i < cardIds.length; i++)
        BoardItem(
          itemId: 'item_route_$i',
          boardId: boardId,
          cardId: cardIds[i],
          x: positions[i].$1,
          y: positions[i].$2,
          width: 220,
          height: 120,
        ),
    ],
  );
}

IngestionResult _sourceIngestion() {
  final now = DateTime.utc(2026, 8, 19);
  const sourceId = 'src_f1_source';
  const versionId = 'ver_f1_source_v1';
  const hash = 'f1-source-hash';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.web,
    title: 'F1 来源卡',
    origin: SourceOrigin.externalLink,
    provider: 'web',
    currentVersionId: versionId,
    contentHash: hash,
    objectRef: 'objects/sources/$sourceId/$versionId.json',
    createdAt: now,
  );
  final version = SourceVersion(
    versionId: versionId,
    sourceId: sourceId,
    contentHash: hash,
    objectRef: source.objectRef!,
    createdAt: now,
  );
  return IngestionResult(
    canonicalUrl: 'https://example.com/f1',
    provider: 'web',
    status: IngestionStatus.ok,
    source: source,
    sourceVersion: version.toJson(),
    hasBody: true,
    metadata: const {'body_text': 'F1 来源正文'},
    resolvedAt: now,
  );
}
