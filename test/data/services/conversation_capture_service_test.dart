import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/conversation_capture_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late List<Map<String, dynamic>> enqueued;
  late ConversationCaptureService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    enqueued = [];
    service = ConversationCaptureService(
      db,
      minimumMessageCount: 2,
      minimumCharacterCount: 1000,
      idleDelay: const Duration(hours: 1),
      enqueueTask: ({
        required userId,
        required taskType,
        required payload,
        priority = 0,
        maxRetries = 5,
        bizId,
      }) async {
        final taskId = 'task-${enqueued.length + 1}';
        enqueued.add({
          'user_id': userId,
          'task_type': taskType,
          'payload': payload,
          'priority': priority,
          'max_retries': maxRetries,
          'biz_id': bizId,
        });
        await db.into(db.tasks).insert(
              TasksCompanion.insert(
                id: taskId,
                type: taskType,
                payload: Value(payload.toString()),
                status: 'pending',
                priority: Value(priority),
                maxRetries: Value(maxRetries),
                bizId: Value(bizId),
              ),
            );
        return taskId;
      },
    );
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  test('default thresholds capture after one completed chat turn', () {
    final defaultService = ConversationCaptureService(db);
    addTearDown(defaultService.dispose);

    expect(defaultService.minimumMessageCount, 2);
    expect(defaultService.minimumCharacterCount, 240);
    expect(defaultService.idleDelay, const Duration(minutes: 2));
  });

  test('queues a slice only after deterministic threshold is reached',
      () async {
    await _insertMessage(db, characterId: 'char-a', content: 'first');

    expect(
      await service.scheduleIfNeeded(
        userId: 'user-a',
        characterId: 'char-a',
      ),
      isFalse,
    );
    expect(enqueued, isEmpty);

    await _insertMessage(db, characterId: 'char-a', content: 'second');

    expect(
      await service.scheduleIfNeeded(
        userId: 'user-a',
        characterId: 'char-a',
      ),
      isTrue,
    );
    expect(enqueued, hasLength(1));
    expect(enqueued.single['task_type'], ConversationCaptureService.taskType);
    expect(
      enqueued.single['payload'],
      containsPair('through_message_id', 2),
    );

    expect(
      await service.scheduleIfNeeded(
        userId: 'user-a',
        characterId: 'char-a',
      ),
      isFalse,
    );
    expect(enqueued, hasLength(1));
  });

  test('successful cursor advance schedules a later backlog slice', () async {
    await _insertMessage(db, characterId: 'char-a', content: 'one');
    await _insertMessage(db, characterId: 'char-a', content: 'two');
    await service.scheduleIfNeeded(
      userId: 'user-a',
      characterId: 'char-a',
    );

    await _insertMessage(db, characterId: 'char-a', content: 'three');
    await _insertMessage(db, characterId: 'char-a', content: 'four');
    await service.markSliceExtracted(
      userId: 'user-a',
      characterId: 'char-a',
      throughMessageId: 2,
    );

    expect(enqueued, hasLength(2));
    expect(
      enqueued.last['payload'],
      containsPair('after_message_id', 2),
    );
    expect(
      enqueued.last['payload'],
      containsPair('through_message_id', 4),
    );
  });

  test('releases stale queued slice when its task is no longer active',
      () async {
    await _insertMessage(db, characterId: 'char-a', content: 'one');
    await _insertMessage(db, characterId: 'char-a', content: 'two');
    await service.scheduleIfNeeded(
      userId: 'user-a',
      characterId: 'char-a',
    );

    await (db.update(db.tasks)..where((t) => t.id.equals('task-1'))).write(
      const TasksCompanion(status: Value('failed')),
    );
    await _insertMessage(db, characterId: 'char-a', content: 'three');

    expect(
      await service.scheduleIfNeeded(
        userId: 'user-a',
        characterId: 'char-a',
      ),
      isTrue,
    );
    expect(enqueued, hasLength(2));
    expect(enqueued.last['payload'], containsPair('after_message_id', 0));
    expect(enqueued.last['payload'], containsPair('through_message_id', 3));
  });

  test('startup repair releases stale queued cursors only', () async {
    await _insertMessage(db, characterId: 'char-a', content: 'one');
    await _insertMessage(db, characterId: 'char-a', content: 'two');
    await service.scheduleIfNeeded(
      userId: 'user-a',
      characterId: 'char-a',
    );
    await (db.update(db.tasks)..where((t) => t.id.equals('task-1'))).write(
      const TasksCompanion(status: Value('failed')),
    );

    await _insertMessage(db, characterId: 'char-b', content: 'one');
    await _insertMessage(db, characterId: 'char-b', content: 'two');
    await service.scheduleIfNeeded(
      userId: 'user-a',
      characterId: 'char-b',
    );

    expect(await service.releaseStaleQueuedSlices(), 1);

    final cursors = {
      for (final cursor in await db.select(db.conversationCaptureCursors).get())
        cursor.characterId: cursor,
    };
    expect(cursors['char-a']!.lastQueuedMessageId, 0);
    expect(cursors['char-b']!.lastQueuedMessageId, 4);
  });

  test('forced scheduling queues a short explicit-memory slice', () async {
    await _insertMessage(db, characterId: 'char-a', content: 'remember this');

    expect(
      await service.scheduleIfNeeded(
        userId: 'user-a',
        characterId: 'char-a',
        force: true,
        trigger: 'explicit_memory',
      ),
      isTrue,
    );
    expect(enqueued, hasLength(1));
  });

  test('capture slices expose only user messages as record evidence', () async {
    await _insertMessage(db, characterId: 'char-a', content: 'user fact');
    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'char-a',
            isFromCharacter: true,
            content: 'character suggestion',
            timestamp: DateTime.now(),
            isRead: const Value(true),
          ),
        );

    final slice = await service.loadSlice(
      characterId: 'char-a',
      afterMessageId: 0,
      throughMessageId: 2,
    );

    expect(slice!.userMessageIds, {1});
  });

  test('background filter rejects character suggestions and sleep todos',
      () async {
    await _insertMessage(db, characterId: 'char-a', content: '现在睡');
    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'char-a',
            isFromCharacter: true,
            content: 'Complete back stretches before bed.',
            timestamp: DateTime.now(),
            isRead: const Value(true),
          ),
        );
    await _insertMessage(
      db,
      characterId: 'char-a',
      content: 'Remember I need to buy train tickets.',
    );
    await _insertMessage(
      db,
      characterId: 'char-a',
      content: 'Call me in two minutes.',
    );
    final slice = (await service.loadSlice(
      characterId: 'char-a',
      afterMessageId: 0,
      throughMessageId: 4,
    ))!;

    final filtered = service.filterBackgroundOperations(
      slice: slice,
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: 'Complete back stretches',
          patch: {},
          sourceMessageIds: [2],
        ),
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: '现在睡',
          patch: {},
          sourceMessageIds: [1],
        ),
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: 'Buy train tickets',
          patch: {},
          sourceMessageIds: [3],
        ),
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: 'Call user in 2 minutes',
          patch: {},
          sourceMessageIds: [4],
        ),
      ],
    );

    expect(filtered.map((operation) => operation.title), ['Buy train tickets']);
  });

  test('startup repair removes old short-lived background reminders', () async {
    final created = await service.sharedLifeMemory.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-old',
      allowedSourceMessageIds: {1},
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: '两分钟后打电话',
          patch: {},
          sourceMessageIds: [1],
        ),
      ],
    );

    expect(created.operationIds, hasLength(1));
    expect(await service.repairEphemeralBackgroundRecords(), 1);
    expect(await service.sharedLifeMemory.listEntities(), isEmpty);
  });

  test('initial baseline skips old chats and captures only later messages',
      () async {
    await _insertMessage(db, characterId: 'char-a', content: 'old history');

    expect(await service.initializeCaptureBaselines(), 1);

    await _insertMessage(db, characterId: 'char-a', content: 'new message');
    expect(
      await service.scheduleIfNeeded(
        userId: 'user-a',
        characterId: 'char-a',
        force: true,
      ),
      isTrue,
    );
    expect(
      enqueued.single['payload'],
      containsPair('after_message_id', 1),
    );
    expect(
      enqueued.single['payload'],
      containsPair('through_message_id', 2),
    );
  });

  test('historical backfill reset removes background artifacts only', () async {
    await _insertMessage(db, characterId: 'char-a', content: 'old history');
    final background = await service.sharedLifeMemory.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-old',
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'event',
          title: 'Old extracted history',
          patch: {},
          sourceMessageIds: [1],
        ),
      ],
      allowedSourceMessageIds: {1},
    );
    final manual = await service.sharedLifeMemory.applyManualOperation(
      sourceCharacterId: 'char-a',
      sourceMessageId: 1,
      operation: const SharedLifeOperationDraft(
        operationType: 'create',
        entityType: 'fact',
        title: 'Explicitly remembered fact',
        patch: {},
        sourceMessageIds: [1],
      ),
    );
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: 'queued-old-capture',
            type: ConversationCaptureService.taskType,
            status: 'pending',
          ),
        );
    await db.into(db.kvStore).insert(
          KvStoreCompanion.insert(
            key: 'conversation_capture_baseline_reset_v1',
            value: const Value('pending'),
          ),
        );

    expect(await service.needsHistoricalBackfillReset(), isTrue);
    final reset = await service.resetHistoricalBackfill();

    expect(reset.characterCount, 1);
    expect(reset.discardedTaskCount, 1);
    expect(reset.undoneOperationCount, 1);
    expect(background.operationIds, hasLength(1));
    expect(manual.operationIds, hasLength(1));
    expect(
      (await service.sharedLifeMemory.listEntities())
          .map((entity) => entity.title),
      ['Explicitly remembered fact'],
    );
    expect((await db.select(db.tasks).get()).single.status, 'completed');
    expect(await service.needsHistoricalBackfillReset(), isFalse);

    await _insertMessage(db, characterId: 'char-a', content: 'after reset');
    expect(
      await service.scheduleIfNeeded(
        userId: 'user-a',
        characterId: 'char-a',
        force: true,
      ),
      isTrue,
    );
    expect(
      enqueued.single['payload'],
      containsPair('after_message_id', 1),
    );
  });
}

Future<void> _insertMessage(
  AppDatabase db, {
  required String characterId,
  required String content,
}) {
  return db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: characterId,
          isFromCharacter: false,
          content: content,
          timestamp: DateTime.now(),
          isRead: const Value(true),
        ),
      );
}
