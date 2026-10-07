import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/capture_consumer.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/db/app_database.dart';
import 'crash_worker.dart' show fixtureBinding;

OrganizedCard financeCard(
        {String title = 'Synthetic lunch',
        String fieldType = 'expense_entry',
        double amount = 30}) =>
    OrganizedCard(
      type: 'event',
      title: title,
      dropletLabel: 'synthetic',
      presentationModule: {'blocks': []},
      retrievalText: '$title $amount',
      valence: 0,
      arousal: 0,
      structuredFieldsType: fieldType,
      structuredFields: {
        'amount_cny': amount,
        'paidAt': '2026-10-06T12:00:00',
        if (fieldType == 'income_entry') 'ai_share_ratio': 0.25
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final route in [DomainRoute.phone, DomainRoute.core]) {
    group(route.name, () {
      late AppDatabase db;
      late DomainStore store;
      late RecordOrganizerServiceV3 organizer;
      late AiFinanceService finance;
      var revision = 0;
      var calls = 0;
      var cards = <OrganizedCard>[];
      Future<void> feed(int version,
          {String id = 'capture-finance', bool deleted = false}) async {
        revision++;
        if (route == DomainRoute.phone) {
          await store.enqueue(
            'captures',
            id: id,
            kind: deleted
                ? 'delete'
                : version == 1
                    ? 'create'
                    : 'patch',
            actor: 'user_direct',
            authorizationRef: 'synthetic-action-$revision',
            fields: deleted
                ? {}
                : version == 1
                    ? {
                        'data': {
                          'text': 'synthetic input $version',
                          'source': 'phone_quick'
                        },
                        'provenance': {
                          'source': 'phone_quick',
                          'source_refs': [],
                          'import_batch_id': null
                        },
                      }
                    : {
                        'patch': {'text': 'synthetic input $version'}
                      },
          );
        } else {
          await store.applyPage('captures', {
            'next_cursor': 'cursor-$revision',
            'policy_version': DomainPolicy.version,
            'records': [
              {
                'id': id,
                'domain': 'captures',
                'core_instance_id': 'core-test',
                'revision': revision,
                if (deleted) ...{
                  'deleted_at': '2026-10-06T00:00:00Z',
                  'body_state': 'purged'
                } else ...{
                  'data': {'text': 'synthetic input $version'},
                  'provenance': {'source': 'claude_web'},
                  'field_meta': {
                    'text': {'rev': version}
                  },
                },
              }
            ],
          });
        }
      }

      CaptureConsumer consumer(
              {DomainStore? using,
              Future<OrganizedRecord> Function(String)? extract}) =>
          CaptureConsumer(
            db: db,
            store: using ?? store,
            organizer: organizer,
            decodeText: (data) => data['text'] as String,
            inputVersion: (record) =>
                record['field_meta']?['text']?['rev'] as int?,
            extract: extract ??
                (_) async {
                  calls++;
                  return OrganizedRecord(cards: cards);
                },
          );
      // These are precisely the reads used by LedgerViewModel.load, not raw
      // SQL-only evidence that bypasses the panel's deduplication and sums.
      Future<List<Map<String, dynamic>>> panel() =>
          finance.getRecentEntries(month: '2026-10');
      Future<List<String>> receipts() async => (await db
              .customSelect(
                  "SELECT value FROM kv_store WHERE bucket='capture_consumer' ORDER BY key")
              .get())
          .map((r) => r.read<String>('value'))
          .toList();
      setUp(() async {
        db = AppDatabase.forTesting(NativeDatabase.memory());
        store = DomainStore(db, binding: fixtureBinding);
        organizer = RecordOrganizerServiceV3(db);
        finance = AiFinanceService(db: db);
        revision = 0;
        calls = 0;
        cards = [financeCard()];
        if (route == DomainRoute.core) {
          await store.configureRoute('captures', route);
        }
        await feed(1);
      });
      tearDown(() => db.close());

      test(
          'panel reads one stable row across revisions and duplicate consumption',
          () async {
        expect(await consumer().consume(), 1);
        final original = (await panel()).single;
        final cardId = (await db.select(db.memoryCards).getSingle()).id;
        expect(original['linked_fact_id'], cardId);
        expect(original['total_amount'], 30);
        expect(
            (await finance.getLedgerOverview(
                month: '2026-10'))['external_expense'],
            30);
        expect(await consumer().consume(), 0);
        if (route == DomainRoute.core) {
          await feed(1); // duplicate source page, changed whole-record revision
          expect(await consumer().consume(), 0);
        }
        cards = [financeCard(fieldType: 'income_entry', amount: 80)];
        await feed(2);
        expect(await consumer().consume(), 1);
        final revised = (await panel()).single;
        expect(revised['id'], original['id']);
        expect(revised['linked_fact_id'], cardId);
        expect(revised['type'], 'income');
        expect(revised['total_amount'], 80);
        expect(revised['ai_amount'], 20);
        expect(
            (await finance.getLedgerOverview(
                month: '2026-10'))['external_income'],
            80);
        expect(await consumer().consume(), 0);
        expect(calls, 2);
        expect(await db.select(db.aiFinanceLedger).get(), hasLength(1));
      });

      test(
          'same-money distinct captures remain visible; exact source delete preserves others',
          () async {
        await consumer().consume();
        final first = (await panel()).single;
        await feed(1, id: 'other-capture');
        await consumer().consume();
        // Even an unrelated generic row linked to the card is not owned by the
        // capture. It must survive deletion and not steal its generated row.
        final unrelated = await finance.recordEntry(
            characterId: 'synthetic-manual',
            entryType: 'expense',
            totalAmount: 30,
            aiAmount: 0,
            purpose: 'Synthetic lunch',
            linkedFactId: first['linked_fact_id'] as String,
            occurredAt: DateTime(2026, 10, 6, 12));
        expect(unrelated, isNot(first['id']));
        expect(await panel(), hasLength(3));
        expect(
            (await finance.getLedgerOverview(
                month: '2026-10'))['external_expense'],
            90);
        await feed(2, deleted: true);
        expect(await consumer().consume(), 1);
        expect(await panel(), hasLength(2));
        expect((await panel()).map((r) => r['id']), contains(unrelated));
        expect(
            (await panel()).map((r) => r['id']), isNot(contains(first['id'])));
        expect(await consumer().consume(), 0);
      });

      test(
          'user modified card stays protected while its owned ledger row is deleted',
          () async {
        await consumer().consume();
        final id = (await db.select(db.memoryCards).getSingle()).id;
        await organizer.updateCard(id,
            title: 'My corrected title', actor: 'user_direct');
        cards = [financeCard(amount: 45)];
        await feed(2);
        await consumer().consume();
        expect((await panel()).single['total_amount'], 30);
        expect((await consumer().pendingIssues()).single['reason'],
            'user_modified');
        // The public ledger editor may clear its mutable linked_fact_id. The
        // immutable generated identity must still drive exact source cleanup.
        await finance.updateEntry(
            entryId: (await panel()).single['id'] as String,
            totalAmount: 32,
            notes: 'User edited ledger');
        expect((await panel()).single['linked_fact_id'], isNull);
        await feed(3, deleted: true);
        await consumer().consume();
        expect(await panel(), isEmpty);
        expect((await db.select(db.memoryCards).getSingle()).title,
            'My corrected title');
        expect((await consumer().pendingIssues()).single['message'],
            contains('你修改过'));
      });

      test(
          'reclassification and slot removal clear only obsolete finance projections',
          () async {
        cards = [financeCard(), financeCard(title: 'Second', amount: 12)];
        await consumer().consume();
        expect(await panel(), hasLength(2));
        cards = [financeCard()];
        await feed(2);
        await consumer().consume();
        expect(await panel(), hasLength(1));
        cards = [financeCard(fieldType: 'synthetic_non_finance')];
        await feed(3);
        await consumer().consume();
        expect(await panel(), isEmpty);
        expect(await db.select(db.memoryCards).get(), hasLength(1));
      });

      test('model failure and invalid finance output never partially commit',
          () async {
        await expectLater(
            consumer(extract: (_) async => throw StateError('model failed'))
                .consume(),
            throwsStateError);
        expect(await panel(), isEmpty);
        expect(await db.select(db.memoryCards).get(), isEmpty);
        expect(await receipts(), isEmpty);
        cards = [financeCard(), financeCard(title: 'Invalid', amount: 0)];
        await expectLater(consumer().consume(), throwsStateError);
        expect(await panel(), isEmpty);
        expect(await db.select(db.memoryCards).get(), isEmpty);
        expect(await receipts(), isEmpty);
      });

      test(
          'ACK or commit fault rolls back create and replacement; retry is unique',
          () async {
        final failing =
            DomainStore(db, binding: fixtureBinding, testFault: (point) {
          if (point ==
              (route == DomainRoute.core
                  ? 'enqueue_before_commit'
                  : 'capture_before_commit')) {
            throw StateError('synthetic transaction fault');
          }
        });
        await expectLater(consumer(using: failing).consume(), throwsStateError);
        expect(await panel(), isEmpty);
        expect(await db.select(db.memoryCards).get(), isEmpty);
        expect(await receipts(), isEmpty);
        await consumer().consume();
        final beforeRows = await panel(), beforeReceipts = await receipts();
        final beforeCards = (await db.select(db.memoryCards).get())
            .map((c) => c.toJson())
            .toList();
        final beforeOutbox = jsonEncode((await store.read())['outbox']);
        cards = [financeCard(amount: 40)];
        await feed(2);
        await expectLater(consumer(using: failing).consume(), throwsStateError);
        expect(await panel(), beforeRows);
        expect(await receipts(), beforeReceipts);
        expect(
            (await db.select(db.memoryCards).get())
                .map((c) => c.toJson())
                .toList(),
            beforeCards);
        expect(jsonEncode((await store.read())['outbox']), beforeOutbox);
        await consumer().consume();
        expect((await panel()).single['id'], beforeRows.single['id']);
        expect((await panel()).single['total_amount'], 40);
      });

      test(
          'delete fault restores ledger, card and receipt before a successful retry',
          () async {
        await consumer().consume();
        final before = await panel(), beforeReceipts = await receipts();
        await feed(2, deleted: true);
        final failing =
            DomainStore(db, binding: fixtureBinding, testFault: (point) {
          if (point == 'capture_before_commit') {
            throw StateError('synthetic delete fault');
          }
        });
        await expectLater(consumer(using: failing).consume(), throwsStateError);
        expect(await panel(), before);
        expect(await receipts(), beforeReceipts);
        expect(await db.select(db.memoryCards).get(), hasLength(1));
        await consumer().consume();
        expect(await panel(), isEmpty);
        expect(await db.select(db.memoryCards).get(), isEmpty);
      });
    });
  }
}
