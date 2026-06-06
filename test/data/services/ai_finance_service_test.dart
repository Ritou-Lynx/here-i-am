import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  group('AiFinanceService', () {
    late AppDatabase db;
    late AiFinanceService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = AiFinanceService(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('summarizes entries across all source characters', () async {
      await service.recordEntry(
        characterId: 'char-a',
        entryType: 'income',
        totalAmount: 1000,
        aiAmount: 300,
        contributionRatio: 0.3,
      );
      await service.recordEntry(
        characterId: 'char-b',
        entryType: 'cost',
        totalAmount: 80,
        aiAmount: 80,
      );

      final summary = await service.getSummary();

      expect(summary['ledger_scope'], 'shared_ai');
      expect(summary['income'], 300);
      expect(summary['cost'], 80);
      expect(summary['all_time_balance'], 220);
      expect(summary['savings'], 220);
      expect(summary['owes_user'], 0);
    });

    test('recent entries include source character without filtering by it',
        () async {
      await service.recordEntry(
        characterId: 'char-a',
        entryType: 'income',
        totalAmount: 1000,
        aiAmount: 300,
      );
      await service.recordEntry(
        characterId: 'char-b',
        entryType: 'repayment',
        totalAmount: 50,
        aiAmount: 50,
      );

      final entries = await service.getRecentEntries(limit: 10);

      expect(entries, hasLength(2));
      expect(
        entries.map((entry) => entry['source_character_id']).toSet(),
        {'char-a', 'char-b'},
      );
    });

    test('skips duplicate entries with the same amount and context', () async {
      final first = await service.recordEntryWithResult(
        characterId: 'char-a',
        entryType: 'income',
        totalAmount: 1500,
        aiAmount: 450,
        contributionRatio: 0.3,
        purpose: 'writing project split',
        notes: 'User reported the May writing income.',
      );
      final second = await service.recordEntryWithResult(
        characterId: 'char-b',
        entryType: 'income',
        totalAmount: 1500,
        aiAmount: 450,
        contributionRatio: 0.3,
        purpose: 'writing project split',
        notes: 'User reported the May writing income.',
      );

      final summary = await service.getSummary();
      final entries = await service.getRecentEntries(limit: 10);

      expect(first.created, isTrue);
      expect(second.created, isFalse);
      expect(second.id, first.id);
      expect(entries, hasLength(1));
      expect(summary['income'], 450);
      expect(summary['all_time_balance'], 450);
    });

    test('skips duplicates linked to the same fact id', () async {
      final first = await service.recordEntryWithResult(
        characterId: 'char-a',
        entryType: 'cost',
        totalAmount: 20,
        aiAmount: 20,
        linkedFactId: 'fact-1',
        purpose: 'API cost',
      );
      final second = await service.recordEntryWithResult(
        characterId: 'char-a',
        entryType: 'cost',
        totalAmount: 25,
        aiAmount: 25,
        linkedFactId: 'fact-1',
        purpose: 'corrected API cost',
      );

      final summary = await service.getSummary();
      final entries = await service.getRecentEntries(limit: 10);

      expect(first.created, isTrue);
      expect(second.created, isFalse);
      expect(second.duplicateOf, first.id);
      expect(entries, hasLength(1));
      expect(summary['cost'], 20);
    });

    test('skips immediate bare duplicate across source characters', () async {
      final first = await service.recordEntryWithResult(
        characterId: 'char-a',
        entryType: 'income',
        totalAmount: 1500,
        aiAmount: 450,
        contributionRatio: 0.3,
      );
      final second = await service.recordEntryWithResult(
        characterId: 'char-b',
        entryType: 'income',
        totalAmount: 1500,
        aiAmount: 450,
        contributionRatio: 0.3,
      );

      final summary = await service.getSummary();
      final entries = await service.getRecentEntries(limit: 10);

      expect(first.created, isTrue);
      expect(second.created, isFalse);
      expect(second.id, first.id);
      expect(entries, hasLength(1));
      expect(summary['income'], 450);
    });

    test('deduplicates legacy duplicate rows when reading balances', () async {
      const recordedAt = 1700000000;
      await db.into(db.aiFinanceLedger).insert(
            AiFinanceLedgerCompanion.insert(
              id: 'legacy-1',
              characterId: 'char-a',
              entryType: 'income',
              totalAmount: 1500,
              aiAmount: 450,
              contributionRatio: const Value(0.3),
              purpose: const Value('writing project split'),
              recordedAt: recordedAt,
            ),
          );
      await db.into(db.aiFinanceLedger).insert(
            AiFinanceLedgerCompanion.insert(
              id: 'legacy-2',
              characterId: 'char-b',
              entryType: 'income',
              totalAmount: 1500,
              aiAmount: 450,
              contributionRatio: const Value(0.3),
              purpose: const Value('writing project split'),
              recordedAt: recordedAt + 30,
            ),
          );

      final summary = await service.getSummary();
      final entries = await service.getRecentEntries(limit: 10);

      expect(entries, hasLength(1));
      expect(summary['income'], 450);
      expect(summary['all_time_balance'], 450);
    });

    test('allows same amount when the context is different', () async {
      await service.recordEntry(
        characterId: 'char-a',
        entryType: 'income',
        totalAmount: 1000,
        aiAmount: 300,
        contributionRatio: 0.3,
        purpose: 'article project',
      );
      await service.recordEntry(
        characterId: 'char-a',
        entryType: 'income',
        totalAmount: 1000,
        aiAmount: 300,
        contributionRatio: 0.3,
        purpose: 'video project',
      );

      final summary = await service.getSummary();
      final entries = await service.getRecentEntries(limit: 10);

      expect(entries, hasLength(2));
      expect(summary['income'], 600);
    });
  });
}
