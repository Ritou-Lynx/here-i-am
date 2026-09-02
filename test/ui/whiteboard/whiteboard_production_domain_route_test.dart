import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_manual_domain_command_host.dart';
import 'package:memex/data/workbench_ai/whiteboard_runtime_domain_tool.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_coordinator.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/domain_command.dart';
import 'package:memex/domain/whiteboard/domain_command_receipt.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/desktop/widgets/desktop_persona_chat_view.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor_screen.dart'
    as rich_editor;
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/interactions/ui_intent.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart'
    show SnapshotLoadResult;

void main() {
  testWidgets(
    'production mouse inline editor owns text keys until Escape then selection Delete removes placement',
    (tester) async {
      final composerFocusNode = FocusNode(debugLabel: 'test-desktop-composer');
      final composerController = TextEditingController();
      final composerScrollController = ScrollController();
      addTearDown(composerFocusNode.dispose);
      addTearDown(composerController.dispose);
      addTearDown(composerScrollController.dispose);
      final root = Directory.systemTemp.createTempSync('p4_inline_route_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      CardRichTextEditorScreen.setRepositoryForTesting(repository);
      addTearDown(
        () => CardRichTextEditorScreen.setRepositoryForTesting(null),
      );
      final store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 28, 8);
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                viewport: const BoardViewport(
                  centerX: 380,
                  centerY: -220,
                  zoom: 1.4,
                ),
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      final coordinator = WhiteboardWorkbenchCoordinator(
        runtime: _UnusedRuntime(),
        store: store,
        repositoryLoader: () async => repository,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        addAction: (characterId, content, projection) =>
            _addAction(db, characterId, content, projection),
        updateAction: (messageId, content, projection) =>
            _updateAction(db, messageId, content, projection),
        readActions: (characterId) =>
            readPersistedWorkbenchActions(db, characterId),
        clock: () => now,
      );
      final host = _RecordingManualHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );
      final router = GoRouter(
        initialLocation: AppRoutes.whiteboardCanvasPath('board_route'),
        routes: [
          GoRoute(
            path: AppRoutes.whiteboardCanvas,
            builder: (_, state) => WhiteboardCanvasRouteScreen(
              boardId: state.pathParameters['boardId']!,
              store: store,
              cardRepository: repository,
              manualCommandHost: host,
            ),
          ),
          GoRoute(
            path: AppRoutes.cardEdit,
            builder: (_, state) => CardRichTextEditorScreen(
              cardId: state.pathParameters['cardId']!,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Stack(
                children: [
                  child!,
                  Positioned(
                    left: 8,
                    bottom: 8,
                    width: 280,
                    height: 160,
                    child: DesktopPersonaChatView(
                      loading: false,
                      messagesNewestFirst: const [],
                      isStreaming: false,
                      streamingText: '',
                      controller: composerController,
                      composerFocusNode: composerFocusNode,
                      scrollController: composerScrollController,
                      onSend: () async {},
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ));
      await _pumpUntil(tester, find.byType(WhiteboardCanvasArea));
      final area = tester.widget<WhiteboardCanvasArea>(
        find.byType(WhiteboardCanvasArea),
      );
      await _pumpUntilCondition(
        tester,
        () =>
            WhiteboardWorkbenchSurfaceController.instance.current?.boardId ==
            'board_route',
      );
      final viewportBefore = area.viewModel.viewport;
      expect(area.viewModel.isReadonly, isFalse);
      store.saveCalls = 0;

      await _doubleClickMouseAt(tester, const Offset(700, 450));
      List<PersistedWorkbenchAction>? createActions;
      for (var index = 0; index < 80; index++) {
        createActions = await tester.runAsync(
          () => readPersistedWorkbenchActions(db, 'i'),
        );
        if (createActions?.isNotEmpty ?? false) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(createActions, isNotNull);
      expect(host.receipts, isNotEmpty);
      expect(host.receipts.single.status.name, 'applied',
          reason: host.receipts.single.summary);
      expect(createActions, hasLength(1));
      expect(createActions!.single.projection.status.name, 'completed');
      SnapshotLoadResult? persistedAfterCreate;
      for (var index = 0; index < 80; index++) {
        persistedAfterCreate = await tester.runAsync(
          () => store.loadPersisted('board_route'),
        );
        if (persistedAfterCreate?.snapshot?.boardItems.isNotEmpty ?? false) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(persistedAfterCreate, isNotNull);
      final persistedSnapshot = persistedAfterCreate!.snapshot!;
      expect(persistedSnapshot.boardItems, hasLength(1));
      expect(await tester.runAsync(repository.listCards), hasLength(1));
      await _pumpUntilCondition(
        tester,
        () => area.viewModel.exportForSave().boardItems.isNotEmpty,
      );
      final createdItem = area.viewModel.exportForSave().boardItems.single;
      expect(area.viewModel.exportForSave().cards, hasLength(1));
      expect(find.byKey(Key('wb_card_${createdItem.itemId}')), findsOneWidget);
      await _pumpUntil(
        tester,
        find.byKey(const Key('rich_text_continuous_document')),
      );
      final item = area.viewModel.exportForSave().boardItems.single;
      final itemFinder = find.byKey(Key('wb_card_${item.itemId}'));
      final editor = find.byKey(const Key('wb_compact_card_editor'));
      final field = find.byKey(const Key('rich_text_continuous_document'));
      expect(find.byKey(const Key('wb_domain_card_editor')), findsNothing);
      expect(find.descendant(of: itemFinder, matching: editor), findsOneWidget);
      expect(find.descendant(of: editor, matching: find.byType(TextField)),
          findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.widget<Material>(editor).type, MaterialType.transparency);
      final itemRect = tester.getRect(itemFinder);
      final geometryBefore = item.toJson();
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      final canvasFocusNode = tester
          .widget<Focus>(find.byKey(const ValueKey('wb_canvas_focus')))
          .focusNode!;
      expect(FocusManager.instance.primaryFocus, isNot(same(canvasFocusNode)));

      await tester.enterText(field, 'ABC');
      final textController = tester.widget<TextField>(field).controller!;
      textController.selection = const TextSelection.collapsed(offset: 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(textController.text, 'AB');
      textController.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(textController.text, 'B');
      expect(
          area.viewModel.exportForSave().boardItems.single.itemId, item.itemId);
      expect(host.receipts, hasLength(1),
          reason: 'editing Delete/Backspace must not reach the remove port');

      await tester.enterText(field, '选择测试\n正文');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        {
          textController.selection.baseOffset,
          textController.selection.extentOffset,
        },
        {0, textController.text.length},
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(textController.selection.isCollapsed, isFalse);
      expect(area.viewModel.exportForSave().boardItems.single.toJson(),
          geometryBefore);
      expect(host.receipts, hasLength(1),
          reason: 'editing selection/arrows must not select or nudge canvas');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
          area.viewModel.exportForSave().boardItems.single.itemId, item.itemId);
      expect(host.receipts, hasLength(1),
          reason: 'editing Ctrl+Z/Y must remain inside the text editor');

      await tester.enterText(field, '真人标题\n真人正文\n第二行');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _pumpUntilCondition(tester, () => store.saveCalls >= 2);
      await _pumpUntilCondition(
        tester,
        () =>
            find.byKey(const Key('wb_compact_card_editor')).evaluate().isEmpty,
      );
      final stored = (await tester.runAsync(
        () => repository.getCard(item.cardId, loadDocument: false),
      ))!;
      expect(stored.card.title, '真人标题');
      expect(stored.card.body, '真人正文\n第二行');
      expect(area.viewModel.viewport.centerX, viewportBefore.centerX);
      expect(area.viewModel.viewport.centerY, viewportBefore.centerY);
      expect(area.viewModel.viewport.zoom, viewportBefore.zoom);
      expect(area.viewModel.exportForSave().boardItems.single.toJson(),
          geometryBefore);
      expect(
          tester.getRect(find.byKey(Key('wb_card_${item.itemId}'))), itemRect);

      final actions = await _waitForActionCount(tester, db, 2);
      expect(actions, hasLength(2));
      final editBatch = actions
          .map((action) => WhiteboardDomainCommandBatch.fromJson(
                action.projection.domainCommandBatch!,
              ))
          .singleWhere(
            (batch) => batch.commands.first.kind == 'edit_card_title',
          );
      expect(editBatch.commands.map((command) => command.kind), [
        'edit_card_title',
        'edit_card_body',
      ]);

      final labelClick = await tester.startGesture(
        tester.getCenter(find.byKey(Key('wb_card_${item.itemId}'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await labelClick.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑标签'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('wb_card_labels_field')),
        'alpha, beta',
      );
      await tester.tap(find.byKey(const ValueKey('wb_card_labels_save')));
      await _pumpUntilCondition(tester, () => store.saveCalls >= 3);
      final actionsAfterLabels = await _waitForActionCount(tester, db, 3);
      expect(actionsAfterLabels, hasLength(3));
      final labelBatch = actionsAfterLabels
          .map((action) => WhiteboardDomainCommandBatch.fromJson(
                action.projection.domainCommandBatch!,
              ))
          .singleWhere(
            (batch) => batch.commands.first.kind == 'set_card_labels',
          );
      expect(labelBatch.commands.map((command) => command.kind), [
        'set_card_labels',
      ]);
      expect(
        (await tester.runAsync(
          () => repository.getCard(item.cardId, loadDocument: false),
        ))!
            .card
            .tags,
        ['alpha', 'beta'],
      );

      final openClick = await tester.startGesture(
        tester.getCenter(find.byKey(Key('wb_card_${item.itemId}'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await openClick.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开查看'));
      await _pumpUntil(
        tester,
        find.byType(rich_editor.CardRichTextEditorScreen),
      );
      final fullDocument = tester.widget<TextField>(
        find.byKey(const ValueKey('rich_text_continuous_document')),
      );
      expect(fullDocument.controller!.text, '真人正文\n第二行');
      expect(
        find.byKey(const ValueKey('rich_text_degraded_notice')),
        findsNothing,
      );
      expect(find.textContaining('当前没有可用的富文本版本'), findsNothing);
      expect(find.textContaining('富文本文件缺失'), findsNothing);
      expect(find.textContaining('正文投影恢复'), findsNothing);
      expect(repository.richTextStorage.exists(item.cardId), isFalse);

      await tester.tap(find.byKey(const ValueKey('desktop_page_back')));
      await _pumpUntil(
        tester,
        find.byKey(Key('wb_card_${item.itemId}')),
      );
      final returnedCard = find.byKey(Key('wb_card_${item.itemId}'));
      await _pumpUntilCondition(tester, () {
        final elements = returnedCard.evaluate();
        return elements.length == 1 &&
            (ModalRoute.of(elements.single)?.isCurrent ?? false);
      });
      await tester.pumpAndSettle();
      area.viewModel.handleIntent(const ClearSelectionIntent());
      await tester.pump();
      expect(area.viewModel.selection.selectedItemIds, isEmpty);
      await tester.tap(find.byKey(const ValueKey('desktop_chat_input')));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(composerFocusNode));
      final interactiveCard = find.descendant(
        of: returnedCard,
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onTap != null,
          description: 'interactive card GestureDetector',
        ),
      );
      expect(interactiveCard, findsOneWidget);
      final interactiveCenter = tester.getCenter(interactiveCard);
      expect(interactiveCard.hitTestable(at: Alignment.center), findsOneWidget);
      await tester.tapAt(
        interactiveCenter,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await tester.pump();
      expect(area.viewModel.selection.selectedItemIds, {item.itemId});
      expect(FocusManager.instance.primaryFocus, same(canvasFocusNode));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await _pumpUntilCondition(
        tester,
        () => find.byKey(Key('wb_card_${item.itemId}')).evaluate().isEmpty,
      );
      expect(
        area.viewModel.selection.selectedItemIds,
        isEmpty,
        reason:
            'an applied remove must not restore an item absent after reload',
      );
      expect(await tester.runAsync(() => repository.getCard(item.cardId)),
          isNotNull,
          reason: 'post-edit Delete removes only the BoardItem');
      final removeActions = await _waitForActionCount(tester, db, 4);
      expect(
        removeActions
            .map((action) => WhiteboardDomainCommandBatch.fromJson(
                  action.projection.domainCommandBatch!,
                ))
            .expand((batch) => batch.commands)
            .where((command) => command.kind == 'remove_placement'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'production route Card Library click and drag persist through SQLite reload',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('p4_library_route_');
      final databaseFile = File('${root.path}/whiteboard.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(databaseFile));
      var databaseOpen = true;
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        if (databaseOpen) await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      var repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      var store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 29, 8);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_library_route',
            title: 'Library route card',
            body: 'Persistent body',
            createdAt: now,
          ));
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      var coordinator = _testCoordinator(
        db: db,
        store: store,
        repository: repository,
        now: now,
      );
      var host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );

      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: 'board_route',
          store: store,
          cardRepository: repository,
          manualCommandHost: host,
        ),
      ));
      await _pumpUntil(tester, find.byType(WhiteboardCanvasArea));
      final area = tester.widget<WhiteboardCanvasArea>(
        find.byType(WhiteboardCanvasArea),
      );
      final canvasFocusNode = tester
          .widget<Focus>(find.byKey(const ValueKey('wb_canvas_focus')))
          .focusNode!;
      await tester.tap(find.byKey(const Key('wb_open_card_library_tool')));
      final row = find.byKey(const Key('wb_lib_row_card_library_route'));
      await _pumpUntil(tester, row);

      await tester.tap(row);
      await _pumpUntilCondition(
        tester,
        () => area.viewModel.exportForSave().boardItems.length == 1,
      );
      final clickedItem = area.viewModel.exportForSave().boardItems.single;
      expect(clickedItem.cardId, 'card_library_route');
      expect(area.viewModel.selection.selectedItemIds, {clickedItem.itemId});
      expect(FocusManager.instance.primaryFocus, same(canvasFocusNode));
      expect(find.byKey(Key('wb_card_${clickedItem.itemId}')), findsOneWidget);
      var actions = await _waitForActionCount(tester, db, 1);
      expect(
        WhiteboardDomainCommandBatch.fromJson(
          actions.single.projection.domainCommandBatch!,
        ).commands.single.kind,
        'place_existing_card',
      );

      final beforeMove = clickedItem;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      actions = await _waitForActionCount(tester, db, 2);
      await _pumpUntilCondition(tester, () {
        final items = area.viewModel.exportForSave().boardItems;
        return items
                .singleWhere((item) => item.itemId == clickedItem.itemId)
                .x ==
            beforeMove.x + 8;
      });
      expect(area.viewModel.selection.selectedItemIds, {clickedItem.itemId});
      expect(FocusManager.instance.primaryFocus, same(canvasFocusNode));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      actions = await _waitForActionCount(tester, db, 3);
      await _pumpUntilCondition(tester, () {
        final items = area.viewModel.exportForSave().boardItems;
        return items
                .singleWhere((item) => item.itemId == clickedItem.itemId)
                .x ==
            beforeMove.x + 16;
      });
      expect(area.viewModel.selection.selectedItemIds, {clickedItem.itemId});
      expect(FocusManager.instance.primaryFocus, same(canvasFocusNode));

      await tester.drag(
        find.byKey(Key('wb_resize_${clickedItem.itemId}')),
        const Offset(40, 30),
      );
      actions = await _waitForActionCount(tester, db, 4);
      await _pumpUntilCondition(tester, () {
        final item = area.viewModel.exportForSave().boardItems.singleWhere(
              (value) => value.itemId == clickedItem.itemId,
            );
        return item.width > beforeMove.width && item.height > beforeMove.height;
      });
      expect(area.viewModel.selection.selectedItemIds, {clickedItem.itemId});
      expect(FocusManager.instance.primaryFocus, same(canvasFocusNode));

      await tester.dragFrom(
        tester.getCenter(row),
        const Offset(420, 260),
      );
      actions = await _waitForActionCount(tester, db, 5);
      await _pumpUntilCondition(
        tester,
        () => area.viewModel.exportForSave().boardItems.length == 2,
      );
      final draggedItem = area.viewModel.exportForSave().boardItems.singleWhere(
            (item) => item.itemId != clickedItem.itemId,
          );
      expect(area.viewModel.selection.selectedItemIds, {draggedItem.itemId});
      expect(FocusManager.instance.primaryFocus, same(canvasFocusNode));
      final actionKinds = actions
          .map((action) => WhiteboardDomainCommandBatch.fromJson(
                action.projection.domainCommandBatch!,
              ).commands.single.kind)
          .toList();
      expect(
        actionKinds.where((kind) => kind == 'place_existing_card'),
        hasLength(2),
      );
      expect(
        actionKinds.where((kind) => kind == 'move_placement'),
        hasLength(2),
      );
      expect(
        actionKinds.where((kind) => kind == 'resize_placement'),
        hasLength(1),
      );
      expect(
        actions.every(
          (action) =>
              action.projection.status.name == 'completed' &&
              (action.projection.undoToken?.isNotEmpty ?? false),
        ),
        isTrue,
      );
      expect(
        actionKinds.reversed.take(3),
        ['place_existing_card', 'move_placement', 'move_placement'],
      );
      final beforeReopen = area.viewModel.exportForSave().boardItems;
      expect(
        beforeReopen.where((item) => item.cardId == 'card_library_route'),
        hasLength(2),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
      databaseOpen = false;

      db = AppDatabase.forTesting(NativeDatabase(databaseFile));
      databaseOpen = true;
      repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      store = _GatedStore(db);
      coordinator = _testCoordinator(
        db: db,
        store: store,
        repository: repository,
        now: now,
      );
      host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: 'board_route',
          store: store,
          cardRepository: repository,
          manualCommandHost: host,
        ),
      ));
      await _pumpUntil(tester, find.byType(WhiteboardCanvasArea));
      final reopenedArea = tester.widget<WhiteboardCanvasArea>(
        find.byType(WhiteboardCanvasArea),
      );
      final reopenedItems = reopenedArea.viewModel.exportForSave().boardItems;
      expect(reopenedItems, hasLength(2));
      for (final expected in beforeReopen) {
        final actual = reopenedItems.singleWhere(
          (item) => item.itemId == expected.itemId,
        );
        expect(
          [actual.cardId, actual.x, actual.y, actual.width, actual.height],
          [
            expected.cardId,
            expected.x,
            expected.y,
            expected.width,
            expected.height,
          ],
        );
        expect(find.byKey(Key('wb_card_${actual.itemId}')), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'production route Card Library surface change leaves no placement or ghost',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('p4_library_failure_');
      final databaseFile = File('${root.path}/whiteboard.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(databaseFile));
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      final store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 29, 9);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_library_failure',
            title: 'Failure card',
            createdAt: now,
          ));
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      final coordinator = _testCoordinator(
        db: db,
        store: store,
        repository: repository,
        now: now,
      );
      final host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: 'board_route',
          store: store,
          cardRepository: repository,
          manualCommandHost: host,
        ),
      ));
      await _pumpUntil(tester, find.byType(WhiteboardCanvasArea));
      final area = tester.widget<WhiteboardCanvasArea>(
        find.byType(WhiteboardCanvasArea),
      );
      await tester.tap(find.byKey(const Key('wb_open_card_library_tool')));
      final row = find.byKey(const Key('wb_lib_row_card_library_failure'));
      await _pumpUntil(tester, row);

      final switchedOwner = Object();
      WhiteboardWorkbenchSurfaceController.instance.attach(
        owner: switchedOwner,
        boardId: 'board_switched',
        selectedItemIds: const {},
        flush: () async => true,
        reload: () async => true,
        setInteractionLocked: (_) {},
      );
      await tester.tap(row);
      await _pumpUntil(
        tester,
        find.text('白板操作未完成；正在核对持久状态。'),
      );

      expect(area.viewModel.exportForSave().boardItems, isEmpty);
      expect(area.viewModel.selection.selectedItemIds, isEmpty);
      expect(
        (await tester.runAsync(() => store.loadPersisted('board_route')))
            ?.snapshot
            ?.boardItems,
        isEmpty,
      );
      expect(
        await tester.runAsync(() => readPersistedWorkbenchActions(db, 'i')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'applied manual command does not restore captured selection after surface switch',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('p4_selection_switch_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      final store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 29, 10);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_surface_selection',
            title: 'Surface selection',
            createdAt: now,
          ));
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                boardItems: const [
                  BoardItem(
                    itemId: 'item_surface_selection',
                    boardId: 'board_route',
                    cardId: 'card_surface_selection',
                    x: -90,
                    y: -70,
                    width: 180,
                    height: 140,
                  ),
                ],
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      final coordinator = _testCoordinator(
        db: db,
        store: store,
        repository: repository,
        now: now,
      );
      final host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: 'board_route',
          store: store,
          cardRepository: repository,
          manualCommandHost: host,
        ),
      ));
      await _pumpUntil(
        tester,
        find.byKey(const Key('wb_card_item_surface_selection')),
      );
      final area = tester.widget<WhiteboardCanvasArea>(
        find.byType(WhiteboardCanvasArea),
      );
      await tester.tap(
        find.byKey(const Key('wb_card_item_surface_selection')),
      );
      await tester.pump();
      expect(
        area.viewModel.selection.selectedItemIds,
        {'item_surface_selection'},
      );

      store.gateNextSave();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.runAsync(
        () => store.saveEntered.future.timeout(const Duration(seconds: 3)),
      );
      expect(area.viewModel.isReadonly, isTrue);
      expect(
        area.viewModel.selection.selectedItemIds,
        isEmpty,
        reason:
            'the production lock clears selection after the port captures it',
      );

      final switchedOwner = Object();
      WhiteboardWorkbenchSurfaceController.instance.attach(
        owner: switchedOwner,
        boardId: 'board_switched',
        selectedItemIds: const {},
        flush: () async => true,
        reload: () async => true,
        setInteractionLocked: (_) {},
      );
      await tester.pump();
      expect(area.viewModel.selection.selectedItemIds, isEmpty);

      store.releaseSave();
      await _pumpUntilCondition(tester, () => !area.viewModel.isReadonly);
      final actions = await _waitForActionCount(tester, db, 1);
      expect(
        WhiteboardWorkbenchSurfaceController.instance.current?.boardId,
        'board_switched',
      );
      expect(
        area.viewModel.selection.selectedItemIds,
        isEmpty,
        reason: 'the old route must not restore selection for a stale surface',
      );
      final persisted =
          (await tester.runAsync(() => store.loadPersisted('board_route')))!
              .snapshot!;
      expect(persisted.boardItems.single.x, -82);
      expect(actions.single.projection.status.name, 'completed');
      expect(
        WhiteboardDomainCommandBatch.fromJson(
          actions.single.projection.domainCommandBatch!,
        ).commands.single.kind,
        'move_placement',
      );
    },
  );

  testWidgets(
    'runtime resize survives production route lock clearing selection',
    (tester) async {
      final root =
          Directory.systemTemp.createTempSync('p4_runtime_lock_route_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      final store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 28, 10);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_runtime_resize',
            title: 'Runtime 创建验收 R14',
            body: 'R15 Runtime 正文编辑通过',
            tags: const ['runtime验收'],
            createdAt: now,
          ));
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                boardItems: const [
                  BoardItem(
                    itemId: 'item_runtime_resize',
                    boardId: 'board_route',
                    cardId: 'card_runtime_resize',
                    x: 1039.862130884688,
                    y: 1045.1693417620572,
                    width: 887.5555555555558,
                    height: 740.4444444444441,
                  ),
                ],
                viewport: const BoardViewport(
                  centerX: 1039.862130884688,
                  centerY: 1045.1693417620572,
                ),
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      final coordinator = _testCoordinator(
        db: db,
        store: store,
        repository: repository,
        now: now,
      );
      final host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );
      final tool = WorkbenchRuntimeWhiteboardDomainTool(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        clock: () => now,
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: 'board_route',
          store: store,
          cardRepository: repository,
          manualCommandHost: host,
        ),
      ));
      await _pumpUntil(
        tester,
        find.byKey(const Key('wb_card_item_runtime_resize')),
      );
      final area = tester.widget<WhiteboardCanvasArea>(
        find.byType(WhiteboardCanvasArea),
      );
      await tester.tapAt(const Offset(450, 350));
      await tester.pump();
      expect(
        area.viewModel.selection.selectedItemIds,
        {'item_runtime_resize'},
      );
      final authorization = await tester.runAsync(
        () => tool.prepareAuthorization(
          conversationId: 'persona-runtime-route',
          characterId: 'i',
          userText: '把选中卡片卡片宽度增加 120 像素',
          userAuthorizationMessageId: 'chat-message-runtime-route',
        ),
      );
      expect(authorization?.available, isTrue);
      expect(authorization?.selectedItemIds, {'item_runtime_resize'});

      final result = await tester.runAsync(
        () => tool.invoke(
          const {
            'commands': [
              {
                'kind': 'resize_placement',
                'item_id': 'item_runtime_resize',
                'width': 1007.5555555555558,
                'height': 740.4444444444441,
              },
            ],
          },
          authorization: authorization!,
          runtimeTurnId: 'turn-runtime-route-lock',
          isCancelled: () => false,
        ),
      );
      await tester.pump();

      expect(result?.success, isTrue, reason: result?.text);
      expect(jsonDecode(result!.text)['status'], 'applied');
      expect(area.viewModel.isReadonly, isFalse);
      expect(area.viewModel.selection.selectedItemIds, isEmpty,
          reason: 'the production lock intentionally clears selection');
      final visibleItem = area.viewModel.exportForSave().boardItems.single;
      expect(visibleItem.width, 1007.5555555555558);
      expect(visibleItem.height, 740.4444444444441);
      expect(visibleItem.x, 1039.862130884688);
      expect(visibleItem.y, 1045.1693417620572);
      final persisted =
          (await tester.runAsync(() => store.loadPersisted('board_route')))!
              .snapshot!;
      final persistedItem = persisted.boardItems.single;
      expect(persistedItem.width, 1007.5555555555558);
      expect(persistedItem.height, 740.4444444444441);
      expect(persistedItem.x, 1039.862130884688);
      expect(persistedItem.y, 1045.1693417620572);
      final card = (await tester.runAsync(() => repository.getCard(
                'card_runtime_resize',
                loadDocument: false,
              )))!
          .card;
      expect(card.title, 'Runtime 创建验收 R14');
      expect(card.body, 'R15 Runtime 正文编辑通过');
      expect(card.tags, ['runtime验收']);
      final actions = await _waitForActionCount(tester, db, 1);
      expect(actions.single.projection.status.name, 'completed');
      expect(
          actions.single.projection.domainCommandReceipt?['status'], 'applied');
    },
  );

  testWidgets(
    'manual receipt reload preserves active viewport and committed geometry',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('p4_viewport_route_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      final store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 28, 9);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_a',
            title: 'Card A',
            body: 'Body A',
            createdAt: now,
          ));
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                boardItems: const [
                  BoardItem(
                    itemId: 'item_a',
                    boardId: 'board_route',
                    cardId: 'card_a',
                    x: -90,
                    y: -70,
                    width: 180,
                    height: 140,
                  ),
                ],
                viewport: const BoardViewport(
                  centerX: -250,
                  centerY: 175,
                  zoom: 0.8,
                ),
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      final coordinator = WhiteboardWorkbenchCoordinator(
        runtime: _UnusedRuntime(),
        store: store,
        repositoryLoader: () async => repository,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        addAction: (characterId, content, projection) =>
            _addAction(db, characterId, content, projection),
        updateAction: (messageId, content, projection) =>
            _updateAction(db, messageId, content, projection),
        readActions: (characterId) =>
            readPersistedWorkbenchActions(db, characterId),
        clock: () => now,
      );
      final host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );
      await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: 'board_route',
          store: store,
          cardRepository: repository,
          manualCommandHost: host,
        ),
      ));
      await _pumpUntil(tester, find.text('Card A'));

      final area = tester.widget<WhiteboardCanvasArea>(
        find.byType(WhiteboardCanvasArea),
      );
      const activeViewport = BoardViewport(
        centerX: 640,
        centerY: -360,
        zoom: 1.75,
      );
      await tester.tap(find.byKey(const Key('wb_card_item_a')));
      area.viewModel.setViewport(activeViewport);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpUntilCondition(tester, () => store.saveCalls >= 1);

      expect(area.viewModel.viewport.centerX, activeViewport.centerX);
      expect(area.viewModel.viewport.centerY, activeViewport.centerY);
      expect(area.viewModel.viewport.zoom, activeViewport.zoom);
      expect(area.viewModel.exportForSave().boardItems.single.x, -82);
      expect(area.viewModel.exportForSave().boardItems.single.y, -70);
    },
  );

  testWidgets(
    'desktop route holds save and second nudge behind the Domain commit',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('p4_domain_route_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      final store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 28, 10);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_a',
            title: 'Card A',
            body: 'Body A',
            createdAt: now,
          ));
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                boardItems: const [
                  BoardItem(
                    itemId: 'item_a',
                    boardId: 'board_route',
                    cardId: 'card_a',
                    x: -90,
                    y: -70,
                    width: 180,
                    height: 140,
                  ),
                ],
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      final coordinator = WhiteboardWorkbenchCoordinator(
        runtime: _UnusedRuntime(),
        store: store,
        repositoryLoader: () async => repository,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        addAction: (characterId, content, projection) =>
            _addAction(db, characterId, content, projection),
        updateAction: (messageId, content, projection) =>
            _updateAction(db, messageId, content, projection),
        readActions: (characterId) =>
            readPersistedWorkbenchActions(db, characterId),
        clock: () => now,
      );
      final host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );

      final router = GoRouter(
        initialLocation: AppRoutes.whiteboardCanvasPath('board_route'),
        routes: [
          GoRoute(
            path: AppRoutes.whiteboard,
            builder: (_, __) => const Scaffold(body: Text('Board index')),
          ),
          GoRoute(
            path: AppRoutes.whiteboardCanvas,
            builder: (_, __) => WhiteboardCanvasRouteScreen(
              boardId: 'board_route',
              store: store,
              cardRepository: repository,
              manualCommandHost: host,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
      ));
      await _pumpUntil(tester, find.text('Card A'));
      await tester.tap(find.byKey(const Key('wb_card_item_a')));
      await tester.pump();

      store.gateNextSave();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.runAsync(
        () => store.saveEntered.future.timeout(const Duration(seconds: 3)),
      );
      expect(store.saveCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byTooltip('退出白板 (Esc)'));
      await tester.pump();
      expect(
        store.saveCalls,
        1,
        reason: 'explicit save must wait; the readonly second nudge is ignored',
      );

      store.releaseSave();
      await _pumpUntilCondition(tester, () => store.saveCalls == 2);
      await _pumpUntil(tester, find.text('Board index'));
      final persisted =
          (await tester.runAsync(() => store.load('board_route')))!.snapshot!;
      expect(
        persisted.boardItems.single.x,
        -82,
        reason: 'the waiting save must export the reloaded Domain result',
      );
      final actions = (await tester
          .runAsync(() => readPersistedWorkbenchActions(db, 'i')))!;
      expect(actions, hasLength(1));
      expect(
          actions.single.projection.actionType, 'whiteboard_domain_commands');
      expect(actions.single.projection.status.name, 'completed');
      expect(actions.single.projection.undoToken, isNotEmpty);
    },
  );

  testWidgets(
    'failed Domain commit plus reload failure locks stale preview out of save and exit',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('p4_reconcile_route_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        final owner =
            WhiteboardWorkbenchSurfaceController.instance.current?.owner;
        if (owner != null) {
          WhiteboardWorkbenchSurfaceController.instance.detach(owner);
        }
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
      final store = _GatedStore(db);
      final now = DateTime.utc(2026, 8, 28, 11);
      await tester.runAsync(() => repository.createTextCard(
            cardId: 'card_a',
            title: 'Card A',
            body: 'Body A',
            createdAt: now,
          ));
      expect(
        await tester.runAsync(() => store.seed(
              'board_route',
              WhiteboardSnapshot(
                boards: [
                  Board(boardId: 'board_route', name: 'Route', createdAt: now),
                ],
                boardItems: const [
                  BoardItem(
                    itemId: 'item_a',
                    boardId: 'board_route',
                    cardId: 'card_a',
                    x: -90,
                    y: -70,
                    width: 180,
                    height: 140,
                  ),
                ],
                updatedAt: now,
              ),
            )),
        isTrue,
      );
      final coordinator = WhiteboardWorkbenchCoordinator(
        runtime: _UnusedRuntime(),
        store: store,
        repositoryLoader: () async => repository,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        addAction: (characterId, content, projection) =>
            _addAction(db, characterId, content, projection),
        updateAction: (messageId, content, projection) =>
            _updateAction(db, messageId, content, projection),
        readActions: (characterId) =>
            readPersistedWorkbenchActions(db, characterId),
        clock: () => now,
      );
      final host = WhiteboardManualDomainCommandHost(
        store: store,
        coordinator: coordinator,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async => 'i',
        clock: () => now,
      );
      final router = GoRouter(
        initialLocation: AppRoutes.whiteboardCanvasPath('board_route'),
        routes: [
          GoRoute(
            path: AppRoutes.whiteboard,
            builder: (_, __) => const Scaffold(body: Text('Board index')),
          ),
          GoRoute(
            path: AppRoutes.whiteboardCanvas,
            builder: (_, __) => WhiteboardCanvasRouteScreen(
              boardId: 'board_route',
              store: store,
              cardRepository: repository,
              manualCommandHost: host,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpUntil(tester, find.text('Card A'));
      await tester.tap(find.byKey(const Key('wb_card_item_a')));
      await tester.pump();

      store.failNextSaveAndReload = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpUntil(
        tester,
        find.textContaining('持久状态核对失败'),
      );
      expect(store.saveCalls, 1);
      expect(
        tester
            .widget<WhiteboardCanvasArea>(find.byType(WhiteboardCanvasArea))
            .viewModel
            .selection
            .selectedItemIds,
        isEmpty,
        reason: 'a failed commit must not restore the pre-lock selection',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byTooltip('退出白板 (Esc)'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.saveCalls, 1,
          reason: 'stale preview must never reach the ordinary save path');
      expect(find.text('Board index'), findsNothing,
          reason: 'exit is refused while reconciliation cannot reload');
      final persisted = (await store.loadPersisted('board_route')).snapshot!;
      expect(persisted.boardItems.single.x, -90);
    },
  );
}

Future<void> _doubleClickMouseAt(WidgetTester tester, Offset point) async {
  final first = await tester.startGesture(
    point,
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryMouseButton,
  );
  await first.up();
  await tester.pump(const Duration(milliseconds: 70));
  final second = await tester.startGesture(
    point,
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryMouseButton,
  );
  await second.up();
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  await _pumpUntilCondition(tester, () => finder.evaluate().isNotEmpty);
  expect(finder, findsOneWidget);
}

Future<List<PersistedWorkbenchAction>> _waitForActionCount(
  WidgetTester tester,
  AppDatabase db,
  int count,
) async {
  var actions = <PersistedWorkbenchAction>[];
  for (var index = 0; index < 80 && actions.length < count; index++) {
    actions = (await tester.runAsync(
      () => readPersistedWorkbenchActions(db, 'i'),
    ))!;
    if (actions.length >= count) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(actions, hasLength(count));
  return actions;
}

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var index = 0; index < 80 && !condition(); index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}

Future<int> _addAction(
  AppDatabase db,
  String characterId,
  String content,
  Map<String, dynamic> projection,
) =>
    db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: characterId,
            isFromCharacter: true,
            content: content,
            timestamp: DateTime.utc(2026, 8, 28, 10),
            messageType: const Value('action'),
            attachmentsJson: Value(jsonEncode([
              {'type': 'workbench_action', 'action': projection},
            ])),
          ),
        );

Future<void> _updateAction(
  AppDatabase db,
  int messageId,
  String content,
  Map<String, dynamic> projection,
) async {
  await (db.update(db.personaChatMessages)
        ..where((row) => row.id.equals(messageId)))
      .write(PersonaChatMessagesCompanion(
    content: Value(content),
    attachmentsJson: Value(jsonEncode([
      {'type': 'workbench_action', 'action': projection},
    ])),
  ));
}

WhiteboardWorkbenchCoordinator _testCoordinator({
  required AppDatabase db,
  required WhiteboardDriftStore store,
  required UnifiedCardRepository repository,
  required DateTime now,
}) =>
    WhiteboardWorkbenchCoordinator(
      runtime: _UnusedRuntime(),
      store: store,
      repositoryLoader: () async => repository,
      surfaceController: WhiteboardWorkbenchSurfaceController.instance,
      addAction: (characterId, content, projection) =>
          _addAction(db, characterId, content, projection),
      updateAction: (messageId, content, projection) =>
          _updateAction(db, messageId, content, projection),
      readActions: (characterId) =>
          readPersistedWorkbenchActions(db, characterId),
      clock: () => now,
    );

class _GatedStore extends WhiteboardDriftStore {
  _GatedStore(super.db);

  Completer<void> saveEntered = Completer<void>();
  Completer<void>? _release;
  int saveCalls = 0;
  bool failNextSaveAndReload = false;
  bool _failLoads = false;

  Future<bool> seed(String boardId, WhiteboardSnapshot snapshot) =>
      super.save(boardId, snapshot);

  Future<SnapshotLoadResult> loadPersisted(String boardId) =>
      super.load(boardId);

  @override
  Future<SnapshotLoadResult> load(String boardId) {
    if (_failLoads) throw StateError('injected reload failure');
    return super.load(boardId);
  }

  void gateNextSave() {
    saveEntered = Completer<void>();
    _release = Completer<void>();
  }

  void releaseSave() => _release?.complete();

  @override
  Future<bool> save(String boardId, WhiteboardSnapshot snapshot) async {
    saveCalls += 1;
    if (failNextSaveAndReload) {
      failNextSaveAndReload = false;
      _failLoads = true;
      return false;
    }
    final release = _release;
    if (release != null) {
      saveEntered.complete();
      await release.future;
      _release = null;
    }
    return super.save(boardId, snapshot);
  }
}

class _RecordingManualHost extends WhiteboardManualDomainCommandHost {
  _RecordingManualHost({
    required super.store,
    required super.coordinator,
    required super.surfaceController,
    required super.resolveCharacterId,
    required super.clock,
  });

  final receipts = <WhiteboardDomainCommandReceipt>[];

  @override
  Future<WhiteboardDomainCommandReceipt> execute({
    required Object surfaceOwner,
    required String boardId,
    required String operationBatchId,
    required List<WhiteboardDomainCommand> commands,
  }) async {
    final receipt = await super.execute(
      surfaceOwner: surfaceOwner,
      boardId: boardId,
      operationBatchId: operationBatchId,
      commands: commands,
    );
    receipts.add(receipt);
    return receipt;
  }
}

class _UnusedRuntime implements WorkbenchRuntimeGateway {
  Never _unused() => throw StateError('legacy workbench runtime is unused');

  @override
  Future<void> closeSession(String sessionId) async => _unused();

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async =>
      _unused();

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async =>
      _unused();

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async =>
      _unused();

  @override
  Future<WorkbenchRuntimeTurn> startTurn(
    String sessionId,
    String input,
  ) async =>
      _unused();
}
