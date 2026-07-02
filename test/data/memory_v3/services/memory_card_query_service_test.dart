import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/retrieval/query_expander.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MemoryCardQueryService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.searchDao.createFtsTables();
    service = MemoryCardQueryService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('expanded query recalls semantically adjacent beverage card', () async {
    await _insertCard(
      db,
      id: 'coffee-card',
      type: 'event',
      label: '拿铁',
      text: '今天下午在店里喝了一杯拿铁，感觉精神好多了。',
    );

    final hits = await service.searchCards('咖啡');

    expect(hits.map((h) => h['card_id']), contains('coffee-card'));
    expect(
      hits.firstWhere((h) => h['card_id'] == 'coffee-card')['query_strategy'],
      QueryExpansionStrategy.expanded.name,
    );
  });

  test('expanded query recalls finance card with different wording', () async {
    await _insertCard(
      db,
      id: 'finance-card',
      type: 'fact',
      label: '书店',
      text: '在书店消费 38 元，买了一本旅行随笔。',
    );

    final hits = await service.searchCards('花钱');

    expect(hits.map((h) => h['card_id']), contains('finance-card'));
  });
}

Future<void> _insertCard(
  AppDatabase db, {
  required String id,
  required String type,
  required String label,
  required String text,
}) async {
  final now = DateTime(2026, 7, 3, 12).millisecondsSinceEpoch;
  await db.into(db.memoryCards).insert(
        MemoryCardsCompanion.insert(
          id: id,
          type: type,
          title: label,
          dropletLabel: label,
          presentationModule: '[]',
          retrievalText: text,
          valence: 0,
          arousal: 0.2,
          createdAt: now,
          updatedAt: now,
          status: const Value.absent(),
          needsFollowUp: const Value.absent(),
        ),
      );
  await db.searchDao.upsertMemoryV3Fts(
    cardId: id,
    dropletLabel: label,
    title: label,
    retrievalText: text,
  );
}
