import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/readonly/phone_dreaming_read_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late PhoneDreamingReadService service;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = PhoneDreamingReadService(db);
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());

  test('real FTS and source closure work with database query_only enabled',
      () async {
    await _seed(db);
    await db.customStatement('PRAGMA query_only = ON');
    final result = await service.read('orchard');
    expect((result['episodes'] as List).single['id'], 'e');
    expect((result['fragments'] as List).single['id'], 'f');
    expect((result['sagas'] as List).single['id'], 's');
    expect(
        (await service.read('unmatchedzz'))
            .values
            .every((v) => (v as List).isEmpty),
        isTrue);
  });

  test(
      'hidden expanded episode blocks saga; deleted expanded fragment blocks both',
      () async {
    await _seed(db);
    // Keep a saga-only FTS hit, so evidence is reached exclusively by expansion.
    await db.customStatement('DELETE FROM memory_episodes_fts');
    await db.customStatement('DELETE FROM memory_fragments_fts');
    await (db.update(db.memoryEpisodes)..where((t) => t.id.equals('e')))
        .write(const MemoryEpisodesCompanion(status: Value('hidden')));
    expect((await service.read('orchard'))['sagas'], isEmpty);
    await (db.update(db.memoryEpisodes)..where((t) => t.id.equals('e')))
        .write(const MemoryEpisodesCompanion(status: Value('active')));
    await (db.update(db.memoryFragments)..where((t) => t.id.equals('f')))
        .write(const MemoryFragmentsCompanion(status: Value('deleted')));
    final result = await service.read('orchard');
    expect(result.values.every((v) => (v as List).isEmpty), isTrue);
  });

  test(
      'strict dual-source evidence rejects other character, TaskRoom and malformed refs',
      () async {
    await _seed(db);
    final other = await db
        .into(db.personaChatMessages)
        .insert(PersonaChatMessagesCompanion.insert(
          characterId: 'other',
          isFromCharacter: false,
          content: 'source',
          timestamp: DateTime.utc(2026),
        ));
    for (final ids in ['[1,$other]', '[1,1]', '[]', '["1"]', '{bad']) {
      await (db.update(db.memoryFragments)..where((t) => t.id.equals('f')))
          .write(MemoryFragmentsCompanion(sourceMessageIds: Value(ids)));
      expect(
          (await service.read('orchard'))
              .values
              .every((v) => (v as List).isEmpty),
          isTrue);
    }
    await (db.update(db.memoryFragments)..where((t) => t.id.equals('f')))
        .write(const MemoryFragmentsCompanion(sourceMessageIds: Value('[1]')));
    await (db.update(db.personaChatMessages)..where((t) => t.id.equals(1)))
        .write(const PersonaChatMessagesCompanion(taskRoomId: Value('room')));
    expect(
        (await service.read('orchard'))
            .values
            .every((v) => (v as List).isEmpty),
        isTrue);
  });

  test(
      'deleted source message and invalid episode/saga evidence cannot return old prose',
      () async {
    await _seed(db);
    await (db.update(db.memoryEpisodes)..where((t) => t.id.equals('e'))).write(
        const MemoryEpisodesCompanion(sourceFragmentIds: Value('["f","f"]')));
    expect((await service.read('orchard'))['episodes'], isEmpty);
    expect((await service.read('orchard'))['sagas'], isEmpty);
    await (db.delete(db.personaChatMessages)..where((t) => t.id.equals(1)))
        .go();
    expect(
        (await service.read('orchard'))
            .values
            .every((v) => (v as List).isEmpty),
        isTrue);
  });

  test('missing FTS is unavailable through failure, never successful empty',
      () async {
    await db.customStatement('DROP TABLE memory_fragments_fts');
    await expectLater(service.read('orchard'), throwsA(anything));
  });

  test(
      'concurrent delete and read produce a complete snapshot; next read excludes it',
      () async {
    await _seed(db);
    final reading = service.read('orchard');
    final deleting =
        (db.delete(db.memoryFragments)..where((t) => t.id.equals('f'))).go();
    final snapshot = await reading;
    await deleting;
    final counts = snapshot.values.map((v) => (v as List).length).toSet();
    expect(counts.length, 1);
    expect(
        (await service.read('orchard'))
            .values
            .every((v) => (v as List).isEmpty),
        isTrue);
  });

  test('UTF-16 field limits retain valid emoji and fixed fragment count',
      () async {
    await _seed(db);
    for (var i = 0; i < 9; i++) {
      await db.into(db.memoryFragments).insert(MemoryFragmentsCompanion.insert(
            id: 'extra-$i',
            content: 'orchard ${'😀' * 200}',
            sourceMessageIds: const Value('[1]'),
            createdAt: 1,
          ));
      await db.searchDao
          .upsertMemoryFragmentFts(fragmentId: 'extra-$i', content: 'orchard');
    }
    final fragments = (await service.read('orchard'))['fragments'] as List;
    expect(fragments.length, 6);
    for (final fragment in fragments) {
      final content = fragment['content'] as String;
      expect(content.length, lessThanOrEqualTo(300));
      expect(utf8.decode(utf8.encode(content)), content);
    }
  });
}

Future<void> _seed(AppDatabase db) async {
  final message = await db
      .into(db.personaChatMessages)
      .insert(PersonaChatMessagesCompanion.insert(
        characterId: 'i',
        syncId: const Value('sync-i'),
        isFromCharacter: false,
        content: 'source',
        timestamp: DateTime.utc(2026),
      ));
  await db.into(db.memoryFragments).insert(MemoryFragmentsCompanion.insert(
        id: 'f',
        content: 'orchard fragment',
        sourceMessageIds: Value(jsonEncode([message])),
        sourceSyncIds: const Value('["sync-i"]'),
        createdAt: 1,
      ));
  await db.into(db.memoryEpisodes).insert(MemoryEpisodesCompanion.insert(
        id: 'e',
        primaryEntityId: 'entity',
        narrative: 'orchard episode',
        sourceFragmentIds: '["f"]',
        significance: 5,
        confidence: 'high',
        valence: 0,
        arousal: 0,
        createdAt: 1,
        updatedAt: 1,
      ));
  await db.into(db.memorySagas).insert(MemorySagasCompanion.insert(
        id: 's',
        title: 'orchard',
        description: 'orchard saga',
        episodeIds: '["e"]',
        emotionalAxis: '{}',
        createdAt: 1,
        updatedAt: 1,
      ));
  await db.searchDao
      .upsertMemoryFragmentFts(fragmentId: 'f', content: 'orchard fragment');
  await db.searchDao.upsertMemoryEpisodeFts(
      episodeId: 'e', narrative: 'orchard episode', topicId: 'orchard');
  await db.searchDao.upsertMemorySagaFts(
      sagaId: 's', title: 'orchard', description: 'orchard saga');
}
