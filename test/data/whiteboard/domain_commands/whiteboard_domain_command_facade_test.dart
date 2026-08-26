import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_executor.dart';
import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_facade.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/domain_command.dart';
import 'package:memex/domain/whiteboard/domain_command_receipt.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/domain/workbench_ai/permissions/whiteboard_permission_broker.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 10);
  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;
  late WhiteboardDriftStore store;
  var databaseOpen = false;

  Future<void> openDatabase() async {
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    store = WhiteboardDriftStore(db);
    databaseOpen = true;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('domain_commands_');
    dbFile = File('${tempDir.path}/whiteboard.sqlite');
    await openDatabase();
    expect(await store.save('board_1', _initialSnapshot(now)), isTrue);
  });

  tearDown(() async {
    if (databaseOpen) await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
      'user facade executes six commands and real Drift reader restores receipt and undo after reopen',
      () async {
    final persistence = _ActionPersistence(db, now);
    final fixture = _fixture(store, persistence, now);
    final batch = _sixCommandBatch();

    final receipt = await fixture.facade.executeUser(
      characterId: 'i',
      batch: batch,
      userAuthorizationMessageId: 'message_1',
    );

    expect(receipt.status, WhiteboardDomainCommandStatus.applied);
    expect(receipt.commandIds, hasLength(6));
    expect(receipt.undoReceipt, isNotNull);
    final undoJson = receipt.undoReceipt!.toJson();
    expect(undoJson, isNot(contains('before_snapshot')));
    expect(
      utf8.encode(jsonEncode(undoJson)).length,
      lessThanOrEqualTo(WhiteboardDomainCommandExecutor.hardMaxUndoUtf8Bytes),
    );
    final changed = (await store.load('board_1')).snapshot!;
    final card = changed.cards.singleWhere((value) => value.cardId == 'card_1');
    final item =
        changed.boardItems.singleWhere((value) => value.itemId == 'item_1');
    expect(card.body, 'edited body');
    expect(card.tags, ['alpha', 'beta']);
    expect(item.x, 420);
    expect(item.y, 240);
    expect(item.width, 640);
    expect(item.height, 360);
    expect(changed.cards.any((value) => value.cardId == 'card_new'), isTrue);
    expect(
        changed.boardItems.any((value) => value.itemId == 'item_new'), isTrue);
    expect(changed.boardItems.any((value) => value.itemId == 'item_remove'),
        isFalse);

    final persistedBeforeRestart = await readPersistedWorkbenchActions(db, 'i');
    expect(persistedBeforeRestart, hasLength(1));
    expect(
      WhiteboardDomainCommandBatch.fromJson(
        persistedBeforeRestart.single.projection.domainCommandBatch!,
      ).commands,
      hasLength(6),
    );
    expect(
      WhiteboardDomainCommandReceipt.fromJson(
        persistedBeforeRestart.single.projection.domainCommandReceipt!,
      ).status,
      WhiteboardDomainCommandStatus.applied,
    );

    await db.close();
    databaseOpen = false;
    await openDatabase();
    final reopenedPersistence = _ActionPersistence(db, now);
    final reopened = _fixture(store, reopenedPersistence, now);
    await reopened.facade.restore('i');
    expect(reopened.facade.canUndo(batch.operationBatchId), isTrue);
    final undone = await reopened.facade.undo(
      characterId: 'i',
      actionId: batch.operationBatchId,
    );

    expect(undone?.status, WhiteboardDomainCommandStatus.undone);
    expect(reopened.facade.canUndo(batch.operationBatchId), isFalse);
    expect(
      await reopened.facade.undo(
        characterId: 'i',
        actionId: batch.operationBatchId,
      ),
      isNull,
      reason: 'a repeated undo must not report a second success',
    );
    final restored = (await store.load('board_1')).snapshot!;
    final restoredCard =
        restored.cards.singleWhere((value) => value.cardId == 'card_1');
    final restoredItem =
        restored.boardItems.singleWhere((value) => value.itemId == 'item_1');
    expect(restoredCard.body, 'original body');
    expect(restoredCard.tags, ['original']);
    expect(restoredItem.x, 10);
    expect(restoredItem.y, 20);
    expect(restoredItem.width, 260);
    expect(restoredItem.height, 200);
    expect(
      restored.boardItems.any((value) => value.itemId == 'item_remove'),
      isTrue,
    );
    expect(
      restored.cards
          .singleWhere((value) => value.cardId == 'card_new')
          .deletedAt,
      isNotNull,
      reason: 'undo of creation uses a recoverable soft delete',
    );
  });

  test(
      'runtime and user paths share permission and rejection leaves no residue',
      () async {
    final persistence = _ActionPersistence(db, now);
    final fixture = _fixture(store, persistence, now);
    final before = (await store.load('board_1')).snapshot!;
    final grant = fixture.broker.issueSelectionAuthorization(
      runtimeTurnId: 'turn_1',
      userAuthorizationMessageId: 'message_1',
      boardId: 'board_1',
      selectedItemIds: const {'item_1'},
      capabilities: const {WhiteboardWriteCapability.movePlacement},
    );
    final denied = await fixture.facade.executeRuntime(
      characterId: 'i',
      batch: const WhiteboardDomainCommandBatch(
        operationBatchId: 'batch_denied',
        boardId: 'board_1',
        commands: [
          RemovePlacementCommand(commandId: 'cmd_1', itemId: 'item_1'),
        ],
      ),
      authorizationId: grant.authorizationId,
      runtimeTurnId: 'turn_1',
      userAuthorizationMessageId: 'message_1',
    );
    expect(denied.status, WhiteboardDomainCommandStatus.denied);
    expect(
      WhiteboardDomainCommandExecutor.snapshotHash(
        (await store.load('board_1')).snapshot!,
      ),
      WhiteboardDomainCommandExecutor.snapshotHash(before),
    );
  });

  test('save failure is zero-residue and the same request retries honestly',
      () async {
    var snapshot = (await store.load('board_1')).snapshot!;
    var saves = 0;
    var allowSave = false;
    final broker = _broker(now);
    final executor = WhiteboardDomainCommandExecutor(
      permissionBroker: broker,
      loadSnapshot: (_) async => snapshot,
      saveSnapshot: (_, value) async {
        saves++;
        if (!allowSave) return false;
        snapshot = value;
        return true;
      },
      clock: () => now,
      idFactory: (prefix) => '${prefix}_1',
    );
    const batch = WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_retry',
      boardId: 'board_1',
      commands: [
        MovePlacementCommand(
            commandId: 'cmd_move', itemId: 'item_1', x: 9, y: 8),
      ],
    );
    final grant = _grant(broker, batch, 'turn_1');
    final request = WhiteboardDomainExecutionRequest(
      batch: batch,
      authorizationId: grant.authorizationId,
      actorTurnId: 'turn_1',
      actor: WhiteboardDomainCommandActor.i,
    );
    final beforeHash = WhiteboardDomainCommandExecutor.snapshotHash(snapshot);
    final failed = await executor.execute(request);
    expect(failed.status, WhiteboardDomainCommandStatus.unavailable);
    expect(WhiteboardDomainCommandExecutor.snapshotHash(snapshot), beforeHash);

    allowSave = true;
    final applied = await executor.execute(request);
    expect(applied.status, WhiteboardDomainCommandStatus.applied);
    final repeated = await executor.execute(request);
    expect(identical(repeated, applied), isTrue);
    expect(saves, 2,
        reason: 'failure writes nothing; idempotent repeat writes nothing');
  });

  test('expected hash conflict and oversized inverse are rejected before save',
      () async {
    final persistence = _ActionPersistence(db, now);
    final fixture = _fixture(store, persistence, now);
    final conflict = await fixture.facade.executeUser(
      characterId: 'i',
      batch: const WhiteboardDomainCommandBatch(
        operationBatchId: 'batch_conflict',
        boardId: 'board_1',
        expectedSnapshotHash: 'stale',
        commands: [
          MovePlacementCommand(
              commandId: 'cmd_move', itemId: 'item_1', x: 1, y: 2),
        ],
      ),
      userAuthorizationMessageId: 'message_1',
    );
    expect(conflict.status, WhiteboardDomainCommandStatus.conflict);
    expect(conflict.issues.single.code, 'snapshot_conflict');

    final loaded = (await store.load('board_1')).snapshot!;
    final huge = WhiteboardSnapshot(
      schemaVersion: loaded.schemaVersion,
      sources: loaded.sources,
      sourceVersions: loaded.sourceVersions,
      cards: [
        for (final card in loaded.cards)
          card.cardId == 'card_1'
              ? CardContract(
                  cardId: card.cardId,
                  cardKind: card.cardKind,
                  title: card.title,
                  body: List.filled(40000, 'x').join(),
                  tags: card.tags,
                  createdAt: card.createdAt,
                  updatedAt: card.updatedAt,
                )
              : card,
      ],
      boards: loaded.boards,
      boardItems: loaded.boardItems,
      groups: loaded.groups,
      groupMembers: loaded.groupMembers,
      edges: loaded.edges,
      viewport: loaded.viewport,
      updatedAt: loaded.updatedAt,
    );
    expect(await store.save('board_1', huge), isTrue);
    final beforeHugeHash = WhiteboardDomainCommandExecutor.snapshotHash(
      (await store.load('board_1')).snapshot!,
    );
    final oversized = await fixture.facade.executeUser(
      characterId: 'i',
      batch: const WhiteboardDomainCommandBatch(
        operationBatchId: 'batch_oversized',
        boardId: 'board_1',
        commands: [
          EditCardBodyCommand(
              commandId: 'cmd_edit', cardId: 'card_1', body: 'small'),
        ],
      ),
      userAuthorizationMessageId: 'message_2',
    );
    expect(oversized.status, WhiteboardDomainCommandStatus.invalidRequest);
    expect(oversized.issues.single.code, 'undo_payload_too_large');
    expect(
      WhiteboardDomainCommandExecutor.snapshotHash(
        (await store.load('board_1')).snapshot!,
      ),
      beforeHugeHash,
    );
  });

  test('malformed and oversized persisted undo records fail closed', () async {
    final persistence = _ActionPersistence(db, now);
    final fixture = _fixture(store, persistence, now);
    final batch = _sixCommandBatch();
    final receipt = await fixture.facade.executeUser(
      characterId: 'i',
      batch: batch,
      userAuthorizationMessageId: 'message_1',
    );
    expect(receipt.status, WhiteboardDomainCommandStatus.applied);

    final persisted =
        (await readPersistedWorkbenchActions(db, 'i')).single.projection;
    final oversizedUndo = <String, dynamic>{
      ...persisted.undoReceipt!,
      'inverse_steps': [
        {
          'kind': 'oversized_untrusted_inverse',
          'payload': List.filled(
            WhiteboardDomainCommandExecutor.hardMaxUndoUtf8Bytes + 1,
            'x',
          ).join(),
        },
      ],
    };
    final oversizedReceipt = <String, dynamic>{
      ...persisted.domainCommandReceipt!,
      'undo_receipt': oversizedUndo,
    };
    await persistence.update(
      (await readPersistedWorkbenchActions(db, 'i')).single.messageId,
      persisted.summary,
      persisted
          .copyWith(
            undoReceipt: oversizedUndo,
            domainCommandReceipt: oversizedReceipt,
          )
          .toJson(),
    );
    await persistence.add(
      'i',
      'malformed',
      {
        ...persisted.toJson(),
        'action_id': 'batch_malformed',
        'operation_batch_id': 'batch_malformed',
        'domain_command_batch': {'bad': true},
      },
    );

    final reopened = _fixture(store, _ActionPersistence(db, now), now);
    await reopened.facade.restore('i');
    expect(reopened.facade.canUndo(batch.operationBatchId), isFalse);
    expect(reopened.facade.canUndo('batch_malformed'), isFalse);
  });
}

class _Fixture {
  const _Fixture(this.facade, this.broker);
  final WhiteboardDomainCommandFacade facade;
  final WhiteboardPermissionBroker broker;
}

_Fixture _fixture(
  WhiteboardDriftStore store,
  _ActionPersistence persistence,
  DateTime now,
) {
  final broker = _broker(now);
  var nextId = 0;
  final executor = WhiteboardDomainCommandExecutor.forDriftStore(
    permissionBroker: broker,
    store: store,
    clock: () => now,
    idFactory: (prefix) => '${prefix}_${++nextId}',
  );
  return _Fixture(
    WhiteboardDomainCommandFacade(
      executor: executor,
      permissionBroker: broker,
      addAction: persistence.add,
      updateAction: persistence.update,
      readActions: persistence.read,
      clock: () => now,
    ),
    broker,
  );
}

WhiteboardPermissionBroker _broker(DateTime now) {
  var next = 0;
  return WhiteboardPermissionBroker(
    clock: () => now,
    authorizationIdFactory: () => 'auth_${++next}',
  );
}

WhiteboardAuthorizationGrant _grant(
  WhiteboardPermissionBroker broker,
  WhiteboardDomainCommandBatch batch,
  String turnId,
) =>
    broker.issueSelectionAuthorization(
      runtimeTurnId: turnId,
      userAuthorizationMessageId: 'message_1',
      boardId: batch.boardId,
      selectedItemIds:
          batch.commands.expand((command) => command.targetItemIds).toSet(),
      selectedCardIds:
          batch.commands.expand((command) => command.targetCardIds).toSet(),
      capabilities: batch.commands
          .map((command) => switch (command) {
                CreateCardCommand() => WhiteboardWriteCapability.createCard,
                EditCardBodyCommand() => WhiteboardWriteCapability.editCardBody,
                SetCardLabelsCommand() =>
                  WhiteboardWriteCapability.setCardLabels,
                MovePlacementCommand() =>
                  WhiteboardWriteCapability.movePlacement,
                ResizePlacementCommand() =>
                  WhiteboardWriteCapability.resizePlacement,
                RemovePlacementCommand() =>
                  WhiteboardWriteCapability.removePlacement,
              })
          .toSet(),
      maxOperationCount: batch.commands.length,
    );

class _ActionPersistence {
  _ActionPersistence(this.db, this.now);
  final AppDatabase db;
  final DateTime now;

  Future<int> add(
    String characterId,
    String content,
    Map<String, dynamic> projection,
  ) =>
      db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: characterId,
              isFromCharacter: true,
              content: content,
              timestamp: now,
              messageType: const Value('action'),
              attachmentsJson: Value(jsonEncode([
                {'type': 'workbench_action', 'action': projection},
              ])),
            ),
          );

  Future<void> update(
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

  Future<List<PersistedWorkbenchAction>> read(String characterId) =>
      readPersistedWorkbenchActions(db, characterId);
}

WhiteboardDomainCommandBatch _sixCommandBatch() =>
    const WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_six',
      boardId: 'board_1',
      commands: [
        CreateCardCommand(
          commandId: 'cmd_create',
          cardId: 'card_new',
          itemId: 'item_new',
          title: 'new',
          body: 'new body',
          x: 100,
          y: 100,
        ),
        EditCardBodyCommand(
          commandId: 'cmd_edit',
          cardId: 'card_1',
          body: 'edited body',
        ),
        SetCardLabelsCommand(
          commandId: 'cmd_labels',
          cardId: 'card_1',
          labels: ['alpha', 'beta'],
        ),
        MovePlacementCommand(
          commandId: 'cmd_move',
          itemId: 'item_1',
          x: 420,
          y: 240,
        ),
        ResizePlacementCommand(
          commandId: 'cmd_resize',
          itemId: 'item_1',
          width: 640,
          height: 360,
        ),
        RemovePlacementCommand(
          commandId: 'cmd_remove',
          itemId: 'item_remove',
        ),
      ],
    );

WhiteboardSnapshot _initialSnapshot(DateTime now) => WhiteboardSnapshot(
      cards: [
        CardContract(
          cardId: 'card_1',
          cardKind: CardKind.note,
          title: 'Card 1',
          body: 'original body',
          tags: const ['original'],
          createdAt: now,
          updatedAt: now,
        ),
        CardContract(
          cardId: 'card_remove',
          cardKind: CardKind.note,
          title: 'Remove me from board',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      boards: [
        Board(
            boardId: 'board_1', name: 'Board', createdAt: now, updatedAt: now),
      ],
      boardItems: const [
        BoardItem(
          itemId: 'item_1',
          boardId: 'board_1',
          cardId: 'card_1',
          x: 10,
          y: 20,
        ),
        BoardItem(
          itemId: 'item_remove',
          boardId: 'board_1',
          cardId: 'card_remove',
        ),
      ],
      updatedAt: now,
    );
