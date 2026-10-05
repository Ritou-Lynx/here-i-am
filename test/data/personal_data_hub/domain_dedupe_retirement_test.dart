import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/db/app_database.dart';
import 'crash_worker.dart' show fixtureBinding;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;
  late AppDatabase db;
  late DomainStore store;
  late RecordOrganizerServiceV3 organizer;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hub-dedupe-synthetic-');
    file = File('${directory.path}/app.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(file));
    store = DomainStore(db, binding: fixtureBinding);
    organizer = RecordOrganizerServiceV3(db);
  });
  tearDown(() async {
    RecordOrganizerServiceV3.reset();
    await db.close();
    final temp = Directory.systemTemp.absolute.path.toLowerCase() +
        Platform.pathSeparator;
    if (!directory.absolute.path.toLowerCase().startsWith(temp)) {
      throw StateError('Unsafe fixture cleanup');
    }
    await directory.delete(recursive: true);
  });
  Future<void> seed(String type) async {
    for (var i = 0; i < 2; i++) {
      final money = type == 'event';
      final id = '$type-$i';
      await db.into(db.memoryCards).insert(MemoryCardsCompanion.insert(
          id: id,
          memoryScope: const Value('user_truth'),
          type: type,
          title: money ? 'Synthetic expense' : 'Synthetic appointment',
          dropletLabel: 'fixture',
          presentationModule: '{"blocks":[]}',
          retrievalText: 'synthetic',
          valence: 0,
          arousal: 0,
          status: const Value('active'),
          createdAt: 100 + i,
          updatedAt: 100 + i));
      await db.into(db.memoryCardStructuredFields).insert(
          MemoryCardStructuredFieldsCompanion.insert(
              cardId: id,
              structuredFieldsType: money ? 'expense_entry' : 'general',
              fieldsJson: jsonEncode(money
                  ? {'amount_cny': 33, 'paidAt': '2026-10-05T10:00:00'}
                  : {'startAt': '2026-10-05T10:00:00'}),
              createdAt: 100 + i,
              updatedAt: 100 + i));
    }
  }

  Future<void> coldStartup() async {
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    store = DomainStore(db, binding: fixtureBinding);
    organizer = RecordOrganizerServiceV3(db);
    await RecordOrganizerServiceV3.init(db);
  }

  Future<int> count(String type) async =>
      (await db.select(db.memoryCards).get())
          .where((r) => r.type == type)
          .length;

  test(
      'cold startup keeps switched planning duplicates but still cleans local money',
      () async {
    await seed('schedule');
    await seed('event');
    await store.disableLocalDedupe('plan_items');
    await coldStartup();
    expect(await count('schedule'), 2);
    expect(await count('event'), 1);
  });
  test(
      'cold startup keeps switched money duplicates but still cleans local planning',
      () async {
    await seed('schedule');
    await seed('event');
    await store.disableLocalDedupe('ledger');
    await coldStartup();
    expect(await count('event'), 2);
    expect(await count('schedule'), 1);
  });
  test(
      'route transition suppresses before startup, independent of attached owner services',
      () async {
    await seed('schedule');
    await store.configureRoute('plan_items', DomainRoute.core);
    await coldStartup();
    expect(await count('schedule'), 2);
    expect(
        (await store.read())['domains']['plan_items']['local_dedupe_disabled'],
        true);
    await RecordOrganizerServiceV3.init(db);
    expect(await count('schedule'), 2);
  });
  test(
      'suppressed planning does not reuse an existing card during local persistence',
      () async {
    await seed('schedule');
    await store.disableLocalDedupe('plan_items');
    final result = await organizer.persist(
        organized: OrganizedRecord(cards: [
          OrganizedCard(
              type: 'schedule',
              title: 'Synthetic appointment',
              dropletLabel: 'fixture',
              presentationModule: {'blocks': []},
              retrievalText: 'synthetic',
              valence: 0,
              arousal: 0,
              structuredFieldsType: 'general',
              structuredFields: {'startAt': '2026-10-05T10:00:00'})
        ]),
        source: RecordSource(
            sourceKind: 'record_button', rawInput: 'synthetic explicit input'));
    expect(result.cardIds.single, isNot('schedule-0'));
    expect(result.cardIds.single, isNot('schedule-1'));
    expect(await count('schedule'), 3);
  });
  test(
      'ordinary local finance still reuses duplicates, retired local dedupe does not',
      () async {
    final finance = AiFinanceService(db: db);
    Future<AiFinanceRecordResult> add() => finance.recordEntryWithResult(
        characterId: 'synthetic-character',
        entryType: 'expense',
        totalAmount: 33,
        aiAmount: 0,
        purpose: 'synthetic expense',
        occurredAt: DateTime.utc(2026, 10, 5, 10));
    final first = await add(), second = await add();
    expect(second.id, first.id);
    expect(second.created, false);
    await store.disableLocalDedupe('ledger');
    await coldStartup();
    final after = await AiFinanceService(db: db).recordEntryWithResult(
        characterId: 'synthetic-character',
        entryType: 'expense',
        totalAmount: 33,
        aiAmount: 0,
        purpose: 'synthetic expense',
        occurredAt: DateTime.utc(2026, 10, 5, 10));
    expect(after.created, true);
    expect(after.id, isNot(first.id));
  });
}
