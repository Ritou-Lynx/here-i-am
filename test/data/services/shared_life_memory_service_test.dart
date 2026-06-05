import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late SharedLifeMemoryService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SharedLifeMemoryService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('stores validated evidence and rebuilds the current projection',
      () async {
    final created = await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-1',
      allowedSourceMessageIds: {10},
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: 'Buy train tickets',
          patch: {
            'summary': 'Buy tickets before Friday',
            'tags': ['travel', 'Shanghai'],
          },
          sourceMessageIds: [10, 999],
        ),
      ],
    );

    expect(created.operationIds, hasLength(1));
    final entities = await service.listEntities();
    expect(entities, hasLength(1));
    expect(entities.single.title, 'Buy train tickets');
    expect(entities.single.state['summary'], 'Buy tickets before Friday');
    expect(entities.single.tags, ['travel', 'Shanghai']);

    final log = await db.select(db.sharedLifeEventOperations).get();
    expect(log.single.sourceMessageIds, '[10]');
  });

  test('detail exposes exact source chat messages and operation history',
      () async {
    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'char-a',
            isFromCharacter: false,
            content: 'Please remember that I need to buy train tickets.',
            timestamp: DateTime(2026, 6, 2, 10),
          ),
        );
    final created = await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-1',
      allowedSourceMessageIds: {1},
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: 'Buy train tickets',
          patch: {
            'tags': ['travel']
          },
          sourceMessageIds: [1],
        ),
      ],
    );

    final entities = await service.listEntities();
    final detail = await service.getEntityDetail(entities.single.id);

    expect(created.operationIds, hasLength(1));
    expect(detail, isNotNull);
    expect(detail!.operations, hasLength(1));
    expect(detail.sourceMessages, hasLength(1));
    expect(
      detail.sourceMessages.single.content,
      'Please remember that I need to buy train tickets.',
    );
  });

  test('undo appends a compensating operation and removes projection',
      () async {
    final created = await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-1',
      allowedSourceMessageIds: {10},
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'event',
          title: 'Dinner with Lin',
          patch: {'time': 'Friday 19:00'},
          sourceMessageIds: [10],
        ),
      ],
    );

    await service.undoOperations(created.operationIds);

    expect(await service.listEntities(), isEmpty);
    final log = await db.select(db.sharedLifeEventOperations).get();
    expect(log, hasLength(2));
    expect(log.last.operationType, 'undo');
    expect(log.last.revertsOperationId, created.operationIds.single);
  });

  test('undoing the origin removes a projection even if completion remains',
      () async {
    final created = await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-a',
      allowedSourceMessageIds: {1},
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: 'Go to sleep',
          patch: {},
          sourceMessageIds: [1],
        ),
      ],
    );
    await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: null,
      allowedSourceMessageIds: {2},
      operations: [
        SharedLifeOperationDraft(
          operationType: 'complete',
          entityId: created.entityIds.single,
          entityType: 'task',
          title: 'Go to sleep',
          patch: const {},
          sourceMessageIds: const [2],
        ),
      ],
    );

    await service.undoOperations([created.operationIds.single]);

    expect(await service.listEntities(), isEmpty);
  });

  test('repairs orphaned projections left by older builds', () async {
    final created = await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-a',
      allowedSourceMessageIds: {1},
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'task',
          title: 'Complete back stretches',
          patch: {},
          sourceMessageIds: [1],
        ),
      ],
    );
    final completed = await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: null,
      allowedSourceMessageIds: {2},
      operations: [
        SharedLifeOperationDraft(
          operationType: 'complete',
          entityId: created.entityIds.single,
          entityType: 'task',
          title: 'Complete back stretches',
          patch: const {},
          sourceMessageIds: const [2],
        ),
      ],
    );
    await service.undoOperations([created.operationIds.single]);
    await db.into(db.sharedLifeEntities).insert(
          SharedLifeEntitiesCompanion.insert(
            id: created.entityIds.single,
            entityType: 'task',
            title: 'Complete back stretches',
            stateJson: '{}',
            sourceCharacterId: 'char-a',
            lastOperationId: completed.operationIds.single,
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    expect(await service.repairOrphanedEntities(), 1);
    expect(await service.listEntities(), isEmpty);
  });

  test('repairs tags that are not in the shared tags file vocabulary',
      () async {
    await service.applyOperations(
      sourceCharacterId: 'char-a',
      captureTaskId: 'capture-a',
      allowedSourceMessageIds: {1},
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'event',
          title: 'Got an offer',
          patch: {
            'summary': 'User got an offer',
            'tags': ['工作', 'work', 'career', 'Emotion'],
          },
          sourceMessageIds: [1],
        ),
      ],
    );

    expect(await service.repairTagsAgainstKnownTags(['Work', 'Emotion']), 1);

    final entity = (await service.listEntities()).single;
    expect(entity.tags, ['Work', 'Emotion']);
    final operations = await db.select(db.sharedLifeEventOperations).get();
    expect(operations, hasLength(2));
    expect(operations.last.operationType, 'correct');
    expect(operations.last.sourceMessageIds, '[]');
  });

  test('manual changes preserve the current chat message as evidence',
      () async {
    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'char-a',
            isFromCharacter: false,
            content: 'Please mark the train tickets as done.',
            timestamp: DateTime(2026, 6, 2, 11),
          ),
        );
    final created = await service.applyManualOperation(
      sourceCharacterId: 'char-a',
      sourceMessageId: 1,
      operation: const SharedLifeOperationDraft(
        operationType: 'create',
        entityType: 'task',
        title: 'Buy train tickets',
        patch: {
          'tags': ['travel']
        },
        sourceMessageIds: [1],
      ),
    );

    expect(created.entityIds, hasLength(1));
    expect(created.entityTitles, ['Buy train tickets']);
    final entity = (await service.listEntities()).single;
    expect(entity.tags, ['travel']);

    final undone = await service.undoLatestEntityOperation(
      entityId: entity.id,
      sourceCharacterId: 'char-a',
      sourceMessageId: 1,
    );

    expect(undone, isTrue);
    expect(await service.listEntities(), isEmpty);
    final log = await db.select(db.sharedLifeEventOperations).get();
    expect(log.last.operationType, 'undo');
    expect(log.last.sourceMessageIds, '[1]');
  });
}
