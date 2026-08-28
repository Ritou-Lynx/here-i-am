import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_manual_domain_command_host.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_coordinator.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart'
    show SnapshotLoadResult;

void main() {
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

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  await _pumpUntilCondition(tester, () => finder.evaluate().isNotEmpty);
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var index = 0; index < 80 && !condition(); index++) {
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
