import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/ai_write_tools/whiteboard_ai_write_models.dart';
import 'package:memex/data/whiteboard/ai_write_tools/whiteboard_ai_write_tool_host.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/domain/workbench_ai/permissions/whiteboard_permission_broker.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21, 13);

  test('applies one authorized group-and-connect batch and is idempotent',
      () async {
    var snapshot = _snapshot();
    var saves = 0;
    final fixture = _fixture(
      now: now,
      load: (_) async => snapshot,
      save: (_, value) async {
        saves++;
        snapshot = value;
        return true;
      },
    );

    final receipt = await fixture.host.groupAndConnect(fixture.request);
    expect(receipt.status, WhiteboardAiWriteStatus.applied);
    expect(receipt.userAuthorizationMessageId, 'message_1');
    expect(receipt.operations, hasLength(4));
    expect(
        receipt.operations.every((operation) =>
            operation.actor == OperationActor.i &&
            operation.authorizationId == fixture.authorizationId),
        isTrue);
    expect(receipt.undoToken, isNotNull);
    expect(receipt.beforeSnapshotHash, isNot(receipt.afterSnapshotHash));
    expect(snapshot.groups, hasLength(2));
    expect(snapshot.groupMembers, hasLength(3));
    expect(snapshot.edges, hasLength(2));
    expect(snapshot.cards, hasLength(3), reason: 'Card identity is untouched');
    expect(saves, 1);

    final repeated = await fixture.host.groupAndConnect(fixture.request);
    expect(identical(repeated, receipt), isTrue);
    expect(saves, 1, reason: 'same batch must not write twice');

    final reusedId = await fixture.host.groupAndConnect(
      WhiteboardAiGroupAndConnectRequest(
        operationBatchId: fixture.request.operationBatchId,
        authorizationId: fixture.authorizationId,
        runtimeTurnId: 'turn_1',
        boardId: 'board_1',
        groups: const [
          WhiteboardAiGroupPlan(name: 'Different', itemIds: ['item_1']),
        ],
      ),
    );
    expect(reusedId.status, WhiteboardAiWriteStatus.conflict);
    expect(reusedId.issues.single.code, 'batch_id_reused');
  });

  test('undo restores the exact snapshot and is itself idempotent', () async {
    var snapshot = _snapshot();
    final original = jsonEncode(snapshot.toJson());
    final fixture = _fixture(
      now: now,
      load: (_) async => snapshot,
      save: (_, value) async {
        snapshot = value;
        return true;
      },
    );
    final applied = await fixture.host.groupAndConnect(fixture.request);

    final undone = await fixture.host.undo(
      WhiteboardAiUndoRequest(
        undoToken: applied.undoToken!,
        runtimeTurnId: 'turn_1',
      ),
    );
    expect(undone.status, WhiteboardAiWriteStatus.undone);
    expect(undone.operations.single.operationKind, OperationKind.undo);
    expect(undone.operations.single.undoOf, 'batch_1');
    expect(jsonEncode(snapshot.toJson()), original);

    final repeated = await fixture.host.undo(
      WhiteboardAiUndoRequest(
        undoToken: applied.undoToken!,
        runtimeTurnId: 'turn_1',
      ),
    );
    expect(identical(repeated, undone), isTrue);
  });

  test('undo tolerates timestamp-only refresh after reopening a board',
      () async {
    var snapshot = _snapshot();
    final fixture = _fixture(
      now: now,
      load: (_) async => snapshot,
      save: (_, value) async {
        snapshot = value;
        return true;
      },
    );
    final applied = await fixture.host.groupAndConnect(fixture.request);
    final refreshedAt = now.add(const Duration(minutes: 1));
    snapshot = _copySnapshot(
      snapshot,
      boards: [
        for (final board in snapshot.boards)
          Board(
            boardId: board.boardId,
            name: board.name,
            ownerSpace: board.ownerSpace,
            createdBy: board.createdBy,
            createdAt: board.createdAt,
            updatedAt: refreshedAt,
            deletedAt: board.deletedAt,
          ),
      ],
      updatedAt: refreshedAt,
    );

    final undone = await fixture.host.undo(
      WhiteboardAiUndoRequest(
        undoToken: applied.undoToken!,
        runtimeTurnId: 'turn_1',
      ),
    );

    expect(undone.status, WhiteboardAiWriteStatus.undone);
    expect(snapshot.groups, isEmpty);
    expect(snapshot.edges, isEmpty);
  });

  test('undo tolerates entity list reordering after reopening a board',
      () async {
    var snapshot = _snapshot();
    final fixture = _fixture(
      now: now,
      load: (_) async => snapshot,
      save: (_, value) async {
        snapshot = value;
        return true;
      },
    );
    final applied = await fixture.host.groupAndConnect(fixture.request);
    snapshot = _copySnapshot(
      snapshot,
      boards: snapshot.boards.reversed.toList(),
      boardItems: snapshot.boardItems.reversed.toList(),
      groups: snapshot.groups.reversed.toList(),
      groupMembers: snapshot.groupMembers.reversed.toList(),
      edges: snapshot.edges.reversed.toList(),
      updatedAt: now.add(const Duration(minutes: 1)),
    );

    final undone = await fixture.host.undo(
      WhiteboardAiUndoRequest(
        undoToken: applied.undoToken!,
        runtimeTurnId: 'turn_1',
      ),
    );

    expect(undone.status, WhiteboardAiWriteStatus.undone);
    expect(snapshot.groups, isEmpty);
    expect(snapshot.edges, isEmpty);
  });

  test('undo refuses to overwrite a later user snapshot change', () async {
    var snapshot = _snapshot();
    var saves = 0;
    final fixture = _fixture(
      now: now,
      load: (_) async => snapshot,
      save: (_, value) async {
        saves++;
        snapshot = value;
        return true;
      },
    );
    final applied = await fixture.host.groupAndConnect(fixture.request);
    snapshot = _copySnapshot(
      snapshot,
      boardItems: [
        const BoardItem(
          itemId: 'item_1',
          boardId: 'board_1',
          cardId: 'card_1',
          x: 999,
        ),
        ...snapshot.boardItems.where((item) => item.itemId != 'item_1'),
      ],
      updatedAt: now.add(const Duration(minutes: 1)),
    );

    final undo = await fixture.host.undo(
      WhiteboardAiUndoRequest(
        undoToken: applied.undoToken!,
        runtimeTurnId: 'turn_1',
      ),
    );
    expect(undo.status, WhiteboardAiWriteStatus.conflict);
    expect(undo.issues.single.code, 'snapshot_changed_after_batch');
    expect(snapshot.boardItems.first.x, 999);
    expect(saves, 1, reason: 'conflicting undo must not save');
  });

  test('permission denial happens before load and save', () async {
    var loads = 0;
    var saves = 0;
    final fixture = _fixture(
      now: now,
      selectedItemIds: {'item_1', 'item_2'},
      load: (_) async {
        loads++;
        return _snapshot();
      },
      save: (_, __) async {
        saves++;
        return true;
      },
    );
    final denied = await fixture.host.groupAndConnect(fixture.request);
    expect(denied.status, WhiteboardAiWriteStatus.denied);
    expect(denied.issues.single.code, contains('targetOutsideSelection'));
    expect(loads, 0);
    expect(saves, 0);
  });

  test('failed save releases authorization for an honest retry', () async {
    var snapshot = _snapshot();
    var shouldSave = false;
    final fixture = _fixture(
      now: now,
      load: (_) async => snapshot,
      save: (_, value) async {
        if (!shouldSave) return false;
        snapshot = value;
        return true;
      },
    );
    final failed = await fixture.host.groupAndConnect(fixture.request);
    expect(failed.status, WhiteboardAiWriteStatus.unavailable);
    expect(snapshot.groups, isEmpty);

    shouldSave = true;
    final retried = await fixture.host.groupAndConnect(fixture.request);
    expect(retried.status, WhiteboardAiWriteStatus.applied);
    expect(snapshot.groups, hasLength(2));
  });

  test('invalid, duplicate, and pre-grouped plans fail without mutation',
      () async {
    var snapshot = _snapshot();
    var saves = 0;
    final fixture = _fixture(
      now: now,
      load: (_) async => snapshot,
      save: (_, value) async {
        saves++;
        snapshot = value;
        return true;
      },
    );
    final duplicateMember = await fixture.host.groupAndConnect(
      WhiteboardAiGroupAndConnectRequest(
        operationBatchId: 'batch_invalid',
        authorizationId: fixture.authorizationId,
        runtimeTurnId: 'turn_1',
        boardId: 'board_1',
        groups: const [
          WhiteboardAiGroupPlan(name: 'A', itemIds: ['item_1', 'item_2']),
          WhiteboardAiGroupPlan(name: 'B', itemIds: ['item_2', 'item_3']),
        ],
      ),
    );
    expect(duplicateMember.status, WhiteboardAiWriteStatus.invalidRequest);

    snapshot = _copySnapshot(
      snapshot,
      groups: const [
        BoardGroup(groupId: 'group_existing', boardId: 'board_1'),
      ],
      groupMembers: const [
        GroupMember(groupId: 'group_existing', itemId: 'item_1'),
      ],
    );
    final grouped = await fixture.host.groupAndConnect(fixture.request);
    expect(grouped.status, WhiteboardAiWriteStatus.conflict);
    expect(grouped.issues.single.code, 'target_already_grouped');
    expect(saves, 0);
  });

  test('Drift apply, whole-batch undo, and process-style reopen restore state',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai_write_host_test_');
    final dbFile = File('${tempDir.path}/whiteboard.db');
    var db = AppDatabase.forTesting(NativeDatabase(dbFile));
    var store = WhiteboardDriftStore(db);
    try {
      final original = _snapshot();
      expect(await store.save('board_1', original), isTrue);
      final fixture = _fixture(
        now: now,
        driftStore: store,
      );
      final applied = await fixture.host.groupAndConnect(fixture.request);
      expect(applied.status, WhiteboardAiWriteStatus.applied);
      final persisted = await store.load('board_1');
      expect(persisted.snapshot!.groups, hasLength(2));
      expect(persisted.snapshot!.edges, hasLength(2));

      final undone = await fixture.host.undo(
        WhiteboardAiUndoRequest(
          undoToken: applied.undoToken!,
          runtimeTurnId: 'turn_1',
        ),
      );
      expect(undone.status, WhiteboardAiWriteStatus.undone);
      await db.close();

      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      store = WhiteboardDriftStore(db);
      final reopened = await store.load('board_1');
      expect(reopened.isSuccess, isTrue);
      expect(reopened.snapshot!.groups, isEmpty);
      expect(reopened.snapshot!.groupMembers, isEmpty);
      expect(reopened.snapshot!.edges, isEmpty);
      expect(reopened.snapshot!.boardItems, hasLength(3));
      expect(reopened.snapshot!.cards, hasLength(3));
    } finally {
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('Drift undo survives database millisecond timestamp precision',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai_write_precision_');
    final dbFile = File('${tempDir.path}/whiteboard.db');
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final store = WhiteboardDriftStore(db);
    try {
      expect(await store.save('board_1', _snapshot()), isTrue);
      final preciseNow = DateTime.utc(2026, 8, 21, 10, 0, 0, 123, 456);
      final fixture = _fixture(now: preciseNow, driftStore: store);
      final applied = await fixture.host.groupAndConnect(fixture.request);
      expect(applied.status, WhiteboardAiWriteStatus.applied);

      final undone = await fixture.host.undo(
        WhiteboardAiUndoRequest(
          undoToken: applied.undoToken!,
          runtimeTurnId: 'turn_1',
        ),
      );

      expect(undone.status, WhiteboardAiWriteStatus.undone);
      expect((await store.load('board_1')).snapshot!.groups, isEmpty);
    } finally {
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}

class _HostFixture {
  const _HostFixture({
    required this.host,
    required this.request,
    required this.authorizationId,
  });

  final WhiteboardAiWriteToolHost host;
  final WhiteboardAiGroupAndConnectRequest request;
  final String authorizationId;
}

_HostFixture _fixture({
  required DateTime now,
  Set<String> selectedItemIds = const {'item_1', 'item_2', 'item_3'},
  WhiteboardSnapshotLoader? load,
  WhiteboardSnapshotSaver? save,
  WhiteboardDriftStore? driftStore,
}) {
  var next = 0;
  final broker = WhiteboardPermissionBroker(
    clock: () => now,
    authorizationIdFactory: () => 'auth_${++next}',
  );
  final authorization = broker.issueSelectionAuthorization(
    runtimeTurnId: 'turn_1',
    userAuthorizationMessageId: 'message_1',
    boardId: 'board_1',
    selectedItemIds: selectedItemIds,
    capabilities: {
      WhiteboardWriteCapability.groupSelection,
      WhiteboardWriteCapability.connectSelection,
    },
  );
  String idFactory(String prefix) => '${prefix}_${++next}';
  final host = driftStore != null
      ? WhiteboardAiWriteToolHost.forDriftStore(
          permissionBroker: broker,
          store: driftStore,
          clock: () => now,
          idFactory: idFactory,
        )
      : WhiteboardAiWriteToolHost(
          permissionBroker: broker,
          loadSnapshot: load!,
          saveSnapshot: save!,
          clock: () => now,
          idFactory: idFactory,
        );
  return _HostFixture(
    host: host,
    authorizationId: authorization.authorizationId,
    request: WhiteboardAiGroupAndConnectRequest(
      operationBatchId: 'batch_1',
      authorizationId: authorization.authorizationId,
      runtimeTurnId: 'turn_1',
      boardId: 'board_1',
      groups: const [
        WhiteboardAiGroupPlan(
          name: 'Research',
          itemIds: ['item_1', 'item_2'],
        ),
        WhiteboardAiGroupPlan(
          name: 'Actions',
          itemIds: ['item_3'],
        ),
      ],
      edges: const [
        WhiteboardAiEdgePlan(
          fromItemId: 'item_1',
          toItemId: 'item_2',
          semanticType: 'supports',
        ),
        WhiteboardAiEdgePlan(
          fromItemId: 'item_2',
          toItemId: 'item_3',
          direction: EdgeDirection.directed,
          label: 'next',
        ),
      ],
    ),
  );
}

WhiteboardSnapshot _snapshot() {
  final createdAt = DateTime.utc(2026, 8, 20);
  return WhiteboardSnapshot(
    cards: [
      for (var index = 1; index <= 3; index++)
        CardContract(
          cardId: 'card_$index',
          cardKind: CardKind.note,
          title: 'Card $index',
          body: 'Body $index',
          createdAt: createdAt,
        ),
    ],
    boards: [
      Board(
        boardId: 'board_1',
        name: 'Board',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
    boardItems: [
      for (var index = 1; index <= 3; index++)
        BoardItem(
          itemId: 'item_$index',
          boardId: 'board_1',
          cardId: 'card_$index',
          x: index * 100,
        ),
    ],
    viewport: const BoardViewport(),
    updatedAt: createdAt,
  );
}

WhiteboardSnapshot _copySnapshot(
  WhiteboardSnapshot source, {
  List<Board>? boards,
  List<BoardItem>? boardItems,
  List<BoardGroup>? groups,
  List<GroupMember>? groupMembers,
  List<BoardEdge>? edges,
  DateTime? updatedAt,
}) {
  return WhiteboardSnapshot(
    schemaVersion: source.schemaVersion,
    sources: source.sources,
    sourceVersions: source.sourceVersions,
    cards: source.cards,
    boards: boards ?? source.boards,
    boardItems: boardItems ?? source.boardItems,
    groups: groups ?? source.groups,
    groupMembers: groupMembers ?? source.groupMembers,
    edges: edges ?? source.edges,
    viewport: source.viewport,
    updatedAt: updatedAt ?? source.updatedAt,
  );
}
