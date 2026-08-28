import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_executor.dart';
import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_facade.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/domain_command.dart';
import 'package:memex/domain/whiteboard/domain_command_receipt.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
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
      equals(null),
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

  test(
      'terminal update rollback leaves no board action or undo and same batch retries after reopen',
      () async {
    final persistence = _ActionPersistence(db, now)..failAfterUpdate = true;
    final fixture = _fixture(store, persistence, now);
    const batch = WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_atomic_retry',
      boardId: 'board_1',
      commands: [
        MovePlacementCommand(
          commandId: 'cmd_atomic_move',
          itemId: 'item_1',
          x: 777,
          y: 333,
        ),
      ],
    );
    final beforeHash = WhiteboardDomainCommandExecutor.snapshotHash(
      (await store.load('board_1')).snapshot!,
    );

    await expectLater(
      fixture.facade.executeUser(
        characterId: 'i',
        batch: batch,
        userAuthorizationMessageId: 'message_atomic',
      ),
      throwsStateError,
    );
    expect(
      WhiteboardDomainCommandExecutor.snapshotHash(
        (await store.load('board_1')).snapshot!,
      ),
      beforeHash,
    );
    expect(await readPersistedWorkbenchActions(db, 'i'), isEmpty);
    expect(fixture.facade.canUndo(batch.operationBatchId), isFalse);

    await db.close();
    databaseOpen = false;
    await openDatabase();
    final retryPersistence = _ActionPersistence(db, now);
    final retry = _fixture(store, retryPersistence, now);
    final applied = await retry.facade.executeUser(
      characterId: 'i',
      batch: batch,
      userAuthorizationMessageId: 'message_atomic',
    );
    expect(applied.status, WhiteboardDomainCommandStatus.applied);
    expect((await store.load('board_1')).snapshot!.boardItems.first.x, 777);
    expect(await readPersistedWorkbenchActions(db, 'i'), hasLength(1));
  });

  test(
      'undo terminal update rollback preserves applied action and retryable undo after reopen',
      () async {
    final persistence = _ActionPersistence(db, now);
    final fixture = _fixture(store, persistence, now);
    const batch = WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_undo_atomic',
      boardId: 'board_1',
      commands: [
        MovePlacementCommand(
          commandId: 'cmd_undo_atomic',
          itemId: 'item_1',
          x: 888,
          y: 444,
        ),
      ],
    );
    expect(
      (await fixture.facade.executeUser(
        characterId: 'i',
        batch: batch,
        userAuthorizationMessageId: 'message_undo_atomic',
      ))
          .status,
      WhiteboardDomainCommandStatus.applied,
    );
    persistence.failAfterUpdate = true;
    await expectLater(
      fixture.facade.undo(characterId: 'i', actionId: batch.operationBatchId),
      throwsStateError,
    );
    expect((await store.load('board_1')).snapshot!.boardItems.first.x, 888);
    final action = (await readPersistedWorkbenchActions(db, 'i')).single;
    expect(action.projection.status.name, 'completed');

    await db.close();
    databaseOpen = false;
    await openDatabase();
    final reopened = _fixture(store, _ActionPersistence(db, now), now);
    await reopened.facade.restore('i');
    expect(reopened.facade.canUndo(batch.operationBatchId), isTrue);
    final undone = await reopened.facade.undo(
      characterId: 'i',
      actionId: batch.operationBatchId,
    );
    expect(undone?.status, WhiteboardDomainCommandStatus.undone);
    expect((await store.load('board_1')).snapshot!.boardItems.first.x, 10);
  });

  test('same-database manual/runtime race applies at most one stale baseline',
      () async {
    final persistence = _ActionPersistence(db, now);
    final fixture = _fixture(store, persistence, now);
    final baseline = WhiteboardDomainCommandExecutor.snapshotHash(
      (await store.load('board_1')).snapshot!,
    );
    const userBatch = WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_race_user',
      boardId: 'board_1',
      expectedSnapshotHash: null,
      commands: [
        MovePlacementCommand(
          commandId: 'cmd_race_user',
          itemId: 'item_1',
          x: 111,
          y: 111,
        ),
      ],
    );
    final runtimeBatch = WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_race_runtime',
      boardId: 'board_1',
      expectedSnapshotHash: baseline,
      commands: const [
        MovePlacementCommand(
          commandId: 'cmd_race_runtime',
          itemId: 'item_1',
          x: 222,
          y: 222,
        ),
      ],
    );
    final userWithBaseline = WhiteboardDomainCommandBatch(
      operationBatchId: userBatch.operationBatchId,
      boardId: userBatch.boardId,
      expectedSnapshotHash: baseline,
      commands: userBatch.commands,
    );
    final grant = _grant(fixture.broker, runtimeBatch, 'turn_race');
    final receipts = await Future.wait([
      fixture.facade.executeUser(
        characterId: 'i',
        batch: userWithBaseline,
        userAuthorizationMessageId: 'message_race_user',
      ),
      fixture.facade.executeRuntime(
        characterId: 'i',
        batch: runtimeBatch,
        authorizationId: grant.authorizationId,
        runtimeTurnId: 'turn_race',
        userAuthorizationMessageId: 'message_race_runtime',
      ),
    ]);
    expect(
      receipts.where(
        (receipt) => receipt.status == WhiteboardDomainCommandStatus.applied,
      ),
      hasLength(1),
    );
    expect(
      receipts.where(
        (receipt) => receipt.status == WhiteboardDomainCommandStatus.conflict,
      ),
      hasLength(1),
    );
    expect(
      (await store.load('board_1')).snapshot!.boardItems.first.x,
      anyOf(111, 222),
    );
  });

  test(
      'pre-update zero-row permission-commit and transaction-end faults fully rollback',
      () async {
    final beforeHash = WhiteboardDomainCommandExecutor.snapshotHash(
      (await store.load('board_1')).snapshot!,
    );

    Future<void> expectFaultRollback(
      String suffix,
      _Fixture fixture,
    ) async {
      await expectLater(
        fixture.facade.executeUser(
          characterId: 'i',
          batch: WhiteboardDomainCommandBatch(
            operationBatchId: 'batch_fault_$suffix',
            boardId: 'board_1',
            commands: [
              MovePlacementCommand(
                commandId: 'cmd_fault_$suffix',
                itemId: 'item_1',
                x: 500,
                y: 500,
              ),
            ],
          ),
          userAuthorizationMessageId: 'message_fault_$suffix',
        ),
        throwsA(isA<Object>()),
      );
      expect(
        WhiteboardDomainCommandExecutor.snapshotHash(
          (await store.load('board_1')).snapshot!,
        ),
        beforeHash,
      );
      expect(await readPersistedWorkbenchActions(db, 'i'), isEmpty);
    }

    final beforeUpdate = _ActionPersistence(db, now)..failBeforeUpdate = true;
    await expectFaultRollback(
      'before_update',
      _fixture(store, beforeUpdate, now),
    );

    final zeroRow = _ActionPersistence(db, now)..deleteBeforeUpdate = true;
    await expectFaultRollback('zero_row', _fixture(store, zeroRow, now));

    final throwingBroker = _CommitThrowingBroker(now);
    await expectFaultRollback(
      'permission_commit',
      _fixture(
        store,
        _ActionPersistence(db, now),
        now,
        permissionBroker: throwingBroker,
      ),
    );

    final transaction = _TransactionHarness(db)..crashAtEnd = true;
    final transactionFixture = _fixture(
      store,
      _ActionPersistence(db, now),
      now,
      runTransaction: transaction.run,
    );
    await expectFaultRollback(
      'transaction_end',
      transactionFixture,
    );
    final retried = await transactionFixture.facade.executeUser(
      characterId: 'i',
      batch: const WhiteboardDomainCommandBatch(
        operationBatchId: 'batch_fault_transaction_end',
        boardId: 'board_1',
        commands: [
          MovePlacementCommand(
            commandId: 'cmd_fault_transaction_end',
            itemId: 'item_1',
            x: 500,
            y: 500,
          ),
        ],
      ),
      userAuthorizationMessageId: 'message_fault_transaction_end',
    );
    expect(retried.status, WhiteboardDomainCommandStatus.applied);
    expect(await readPersistedWorkbenchActions(db, 'i'), hasLength(1));
  });

  test(
      'manual title command round-trips and Undo restores title after real reopen',
      () async {
    const command = EditCardTitleCommand(
      commandId: 'cmd_title',
      cardId: 'card_1',
      title: '新的标题',
    );
    final decoded = WhiteboardDomainCommand.fromJson(command.toJson());
    expect(decoded, isA<EditCardTitleCommand>());
    expect((decoded as EditCardTitleCommand).title, '新的标题');

    final fixture = _fixture(store, _ActionPersistence(db, now), now);
    const batch = WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_title',
      boardId: 'board_1',
      commands: [command],
    );
    final applied = await fixture.facade.executeUser(
      characterId: 'i',
      batch: batch,
      userAuthorizationMessageId: 'ui-title-edit',
    );
    expect(applied.status, WhiteboardDomainCommandStatus.applied);
    expect(
      (await store.load('board_1'))
          .snapshot!
          .cards
          .singleWhere((card) => card.cardId == 'card_1')
          .title,
      '新的标题',
    );

    await db.close();
    databaseOpen = false;
    await openDatabase();
    final reopened = _fixture(store, _ActionPersistence(db, now), now);
    await reopened.facade.restore('i');
    expect(reopened.facade.canUndo(batch.operationBatchId), isTrue);
    final undone = await reopened.facade.undo(
      characterId: 'i',
      actionId: batch.operationBatchId,
    );
    expect(undone?.status, WhiteboardDomainCommandStatus.undone);
    expect(
      (await store.load('board_1'))
          .snapshot!
          .cards
          .singleWhere((card) => card.cardId == 'card_1')
          .title,
      'Card 1',
    );
  });

  test(
      'title and canonical body share one receipt while rich document survives restart Undo',
      () async {
    var repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    final objectStore = RichTextObjectStore(repository.richTextStorage.baseDir);
    final asset = await objectStore.importBytes(
      Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'image/png',
      extension: 'png',
      alt: '',
    );
    final rich = RichTextDocument(
      blocks: [
        const RichTextBlock(
          type: BlockType.paragraph,
          text: 'original body',
          marks: [
            RichTextMark(type: MarkType.bold, start: 0, end: 8),
          ],
        ),
        RichTextBlock(
          type: BlockType.image,
          attrs: {'asset_ref_id': asset.refId},
        ),
      ],
      assetRefs: [asset],
    );
    await repository.saveRichText('card_1', rich, title: 'Card 1');
    final richFile = File(
      '${repository.richTextStorage.baseDir.path}${Platform.pathSeparator}'
      'card_card_1${Platform.pathSeparator}rich_text.json',
    );
    final richBytes = await richFile.readAsBytes();
    final assetFile = objectStore.resolveFile(asset)!;

    final fixture = _fixture(store, _ActionPersistence(db, now), now);
    const batch = WhiteboardDomainCommandBatch(
      operationBatchId: 'batch_title_body',
      boardId: 'board_1',
      commands: [
        EditCardTitleCommand(
          commandId: 'cmd_title_body_title',
          cardId: 'card_1',
          title: 'B title',
        ),
        EditCardBodyCommand(
          commandId: 'cmd_title_body_body',
          cardId: 'card_1',
          body: 'B body',
        ),
      ],
    );
    final applied = await fixture.facade.executeUser(
      characterId: 'i',
      batch: batch,
      userAuthorizationMessageId: 'ui-title-body-edit',
    );
    expect(applied.status, WhiteboardDomainCommandStatus.applied);
    expect(applied.commandIds, hasLength(2));
    expect(await richFile.readAsBytes(), richBytes);
    expect(await assetFile.exists(), isTrue);

    await db.close();
    databaseOpen = false;
    await openDatabase();
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    final stale = await repository.getCard('card_1');
    expect(stale!.card.title, 'B title');
    expect(stale.card.body, 'B body');
    expect(stale.documentState, CardDocumentState.stale);
    expect(stale.document, isNull);

    final reopened = _fixture(store, _ActionPersistence(db, now), now);
    await reopened.facade.restore('i');
    expect(reopened.facade.canUndo(batch.operationBatchId), isTrue);
    expect(
      (await reopened.facade.undo(
        characterId: 'i',
        actionId: batch.operationBatchId,
      ))
          ?.status,
      WhiteboardDomainCommandStatus.undone,
    );

    await db.close();
    databaseOpen = false;
    await openDatabase();
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    final restored = await repository.getCard('card_1');
    expect(restored!.card.title, 'Card 1');
    expect(restored.card.body, 'original body');
    expect(restored.documentState, CardDocumentState.available);
    expect(restored.document!.toJson(), rich.toJson());
    expect(await richFile.readAsBytes(), richBytes);
    expect(await assetFile.exists(), isTrue);
  });

  test('title command is validated and cannot be authorized for Runtime',
      () async {
    final fixture = _fixture(store, _ActionPersistence(db, now), now);
    final before = (await store.load('board_1')).snapshot!;
    final oversized = await fixture.facade.executeUser(
      characterId: 'i',
      batch: WhiteboardDomainCommandBatch(
        operationBatchId: 'batch_title_too_large',
        boardId: 'board_1',
        commands: [
          EditCardTitleCommand(
            commandId: 'cmd_title_too_large',
            cardId: 'card_1',
            title: List.filled(501, '字').join(),
          ),
        ],
      ),
      userAuthorizationMessageId: 'ui-title-edit',
    );
    expect(oversized.status, WhiteboardDomainCommandStatus.invalidRequest);
    expect(oversized.issues.single.code, 'title_too_large');
    expect(
      WhiteboardDomainCommandExecutor.snapshotHash(
        (await store.load('board_1')).snapshot!,
      ),
      WhiteboardDomainCommandExecutor.snapshotHash(before),
    );

    expect(
      () => fixture.facade.authorizeRuntime(
        batch: const WhiteboardDomainCommandBatch(
          operationBatchId: 'batch_runtime_title',
          boardId: 'board_1',
          commands: [
            EditCardTitleCommand(
              commandId: 'cmd_runtime_title',
              cardId: 'card_1',
              title: 'forbidden',
            ),
          ],
        ),
        runtimeTurnId: 'turn_runtime_title',
        userAuthorizationMessageId: 'chat-message-1',
      ),
      throwsArgumentError,
    );
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
  DateTime now, {
  WhiteboardPermissionBroker? permissionBroker,
  DomainDatabaseTransaction? runTransaction,
}) {
  final broker = permissionBroker ?? _broker(now);
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
      runTransaction: runTransaction ?? store.db.transaction,
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
                EditCardTitleCommand() =>
                  WhiteboardWriteCapability.editCardTitle,
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
  bool failBeforeUpdate = false;
  bool failAfterUpdate = false;
  bool deleteBeforeUpdate = false;

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
    if (failBeforeUpdate) {
      failBeforeUpdate = false;
      throw StateError('injected pre-update failure');
    }
    if (deleteBeforeUpdate) {
      deleteBeforeUpdate = false;
      await (db.delete(db.personaChatMessages)
            ..where((row) => row.id.equals(messageId)))
          .go();
    }
    final affected = await (db.update(db.personaChatMessages)
          ..where((row) => row.id.equals(messageId)))
        .write(PersonaChatMessagesCompanion(
      content: Value(content),
      attachmentsJson: Value(jsonEncode([
        {'type': 'workbench_action', 'action': projection},
      ])),
    ));
    if (affected != 1) throw StateError('expected exactly one action row');
    if (failAfterUpdate) {
      failAfterUpdate = false;
      throw StateError('injected terminal update failure');
    }
  }

  Future<List<PersistedWorkbenchAction>> read(String characterId) =>
      readPersistedWorkbenchActions(db, characterId);
}

class _CommitThrowingBroker extends WhiteboardPermissionBroker {
  _CommitThrowingBroker(DateTime now)
      : super(
          clock: () => now,
          authorizationIdFactory: () => 'auth_throwing_commit',
        );

  @override
  bool commit({
    required String authorizationId,
    required String operationBatchId,
  }) {
    throw StateError('injected permission commit failure');
  }
}

class _TransactionHarness {
  _TransactionHarness(this.db);

  final AppDatabase db;
  bool crashAtEnd = false;

  Future<T> run<T>(Future<T> Function() body) => db.transaction(() async {
        final result = await body();
        if (crashAtEnd) {
          crashAtEnd = false;
          throw StateError('injected transaction-end failure');
        }
        return result;
      });
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
