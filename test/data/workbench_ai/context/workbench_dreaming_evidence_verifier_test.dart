import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/context/workbench_relationship_context.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late WorkbenchDreamingEvidenceVerifier verifier;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    verifier = WorkbenchDreamingEvidenceVerifier(db);
  });

  tearDown(() => db.close());

  test('rejects i sync subset when local evidence includes a TaskRoom source',
      () async {
    final iMessageId = await _insertMessage(
      db,
      characterId: 'i',
      syncId: 'i-sync',
    );
    final taskRoomMessageId = await _insertMessage(
      db,
      characterId: 'i',
      taskRoomId: 'task-room-1',
    );
    final fragment = await _insertFragment(
      db,
      id: 'mixed-evidence',
      sourceSyncIds: jsonEncode(['i-sync']),
      sourceMessageIds: jsonEncode([iMessageId, taskRoomMessageId]),
    );

    expect(
      await verifier.fragmentBelongsToCharacter(fragment, 'i'),
      isFalse,
    );
  });

  test('rejects i sync subset when local evidence crosses character or type',
      () async {
    final iMessageId = await _insertMessage(
      db,
      characterId: 'i',
      syncId: 'i-sync',
    );
    final otherMessageId = await _insertMessage(
      db,
      characterId: 'other',
    );
    final nonChatMessageId = await _insertMessage(
      db,
      characterId: 'i',
      messageType: 'system',
    );
    final crossCharacter = await _insertFragment(
      db,
      id: 'cross-character',
      sourceSyncIds: jsonEncode(['i-sync']),
      sourceMessageIds: jsonEncode([iMessageId, otherMessageId]),
    );
    final crossType = await _insertFragment(
      db,
      id: 'cross-type',
      sourceSyncIds: jsonEncode(['i-sync']),
      sourceMessageIds: jsonEncode([iMessageId, nonChatMessageId]),
    );

    expect(
      await verifier.fragmentBelongsToCharacter(crossCharacter, 'i'),
      isFalse,
    );
    expect(
      await verifier.fragmentBelongsToCharacter(crossType, 'i'),
      isFalse,
    );
  });

  test('accepts complete evidence and fails closed for invalid present sets',
      () async {
    final messageId = await _insertMessage(
      db,
      characterId: 'i',
      syncId: 'i-sync',
    );
    final valid = await _insertFragment(
      db,
      id: 'valid',
      sourceSyncIds: jsonEncode(['i-sync']),
      sourceMessageIds: jsonEncode([messageId]),
    );
    final malformed = await _insertFragment(
      db,
      id: 'malformed',
      sourceSyncIds: '{not-json',
      sourceMessageIds: jsonEncode([messageId]),
    );
    final empty = await _insertFragment(
      db,
      id: 'empty',
      sourceMessageIds: '[]',
    );
    final oversized = await _insertFragment(
      db,
      id: 'oversized',
      sourceMessageIds: jsonEncode(List.generate(17, (index) => index + 1)),
    );
    final emptySyncWithValidLocal = await _insertFragment(
      db,
      id: 'empty-sync-valid-local',
      sourceSyncIds: '',
      sourceMessageIds: jsonEncode([messageId]),
    );
    final blankLocalWithValidSync = await _insertFragment(
      db,
      id: 'blank-local-valid-sync',
      sourceSyncIds: jsonEncode(['i-sync']),
      sourceMessageIds: '   ',
    );

    expect(await verifier.fragmentBelongsToCharacter(valid, 'i'), isTrue);
    expect(await verifier.fragmentBelongsToCharacter(malformed, 'i'), isFalse);
    expect(await verifier.fragmentBelongsToCharacter(empty, 'i'), isFalse);
    expect(await verifier.fragmentBelongsToCharacter(oversized, 'i'), isFalse);
    expect(
      await verifier.fragmentBelongsToCharacter(emptySyncWithValidLocal, 'i'),
      isFalse,
    );
    expect(
      await verifier.fragmentBelongsToCharacter(blankLocalWithValidSync, 'i'),
      isFalse,
    );
  });
}

Future<int> _insertMessage(
  AppDatabase db, {
  required String characterId,
  String? syncId,
  String? taskRoomId,
  String messageType = 'chat',
}) =>
    db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            syncId: Value(syncId),
            characterId: characterId,
            isFromCharacter: false,
            content: 'source',
            timestamp: DateTime.utc(2026, 8, 26),
            messageType: Value(messageType),
            taskRoomId: Value(taskRoomId),
          ),
        );

Future<MemoryFragment> _insertFragment(
  AppDatabase db, {
  required String id,
  String? sourceMessageIds,
  String? sourceSyncIds,
}) async {
  await db.into(db.memoryFragments).insert(
        MemoryFragmentsCompanion.insert(
          id: id,
          content: 'relationship evidence',
          sourceMessageIds: Value(sourceMessageIds),
          sourceSyncIds: Value(sourceSyncIds),
          createdAt: DateTime.utc(2026, 8, 26).millisecondsSinceEpoch,
        ),
      );
  return (db.select(db.memoryFragments)..where((row) => row.id.equals(id)))
      .getSingle();
}
