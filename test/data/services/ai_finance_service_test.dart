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

    test('builds a real cash overview and derived user/AI split', () async {
      await service.recordEntry(
        characterId: 'manual:user',
        entryType: 'income',
        totalAmount: 1000,
        aiAmount: 300,
        purpose: '制作收入',
      );
      await service.recordEntry(
        characterId: 'manual:user',
        entryType: 'cost',
        totalAmount: 100,
        aiAmount: 80,
        purpose: 'API 套餐',
      );
      await service.recordEntry(
        characterId: 'char-a',
        entryType: 'reward',
        totalAmount: 20,
        aiAmount: 20,
        purpose: '奖励',
      );
      await service.recordEntry(
        characterId: 'char-a',
        entryType: 'penalty',
        totalAmount: 10,
        aiAmount: 10,
        purpose: '罚款',
      );

      final overview = await service.getLedgerOverview();

      expect(overview['external_income'], 1000);
      expect(overview['external_expense'], 100);
      expect(overview['cash_net'], 900);
      expect(overview['my_income_share'], 700);
      expect(overview['my_expense_share'], 20);
      expect(overview['my_allocated_net'], 690);
      expect(overview['ai_income_share'], 300);
      expect(overview['ai_expense_share'], 80);
      expect(overview['ai_all_time_balance'], 210);
      expect(overview['entry_count'], 4);
    });

    test('stores a manually selected occurrence date', () async {
      final occurredAt = DateTime(2025, 12, 31);
      await service.recordEntry(
        characterId: 'manual:user',
        entryType: 'income',
        totalAmount: 200,
        aiAmount: 50,
        purpose: '旧收入',
        occurredAt: occurredAt,
      );

      final entries = await service.getRecentEntries();
      expect(
        entries.single['recorded_at'],
        occurredAt.millisecondsSinceEpoch ~/ 1000,
      );
    });

    // Regression: 2026-08-04 real-device bug - the same 西塔老太太 dinner was
    // written once via card bridge (linked_fact_id set, purpose "西塔老太太
    // 烤肉 335元AA") and once via agent AiFinanceRecord (linked_fact_id null,
    // purpose "西塔老太太烤肉 AA"). Context-based dedupe missed them because
    // purpose text differed; result was 3 ledger rows for one dinner. expense
    // now dedupes by amount within 36h regardless of purpose/linked_fact_id.
    test('expense dedupes by amount within 36h even when purpose differs', () async {
      await service.recordEntry(
        characterId: 'system:card_bridge',
        entryType: 'expense',
        totalAmount: 167.5,
        aiAmount: 0,
        purpose: '西塔老太太烤肉 335元AA',
        linkedFactId: 'card-1',
      );
      await service.recordEntry(
        characterId: 'i',
        entryType: 'expense',
        totalAmount: 167.5,
        aiAmount: 0,
        purpose: '西塔老太太烤肉 AA',
      );

      final entries = await service.getRecentEntries(limit: 10);
      expect(entries, hasLength(1));
      expect(entries.single['total_amount'], 167.5);
    });

    // Companion guard: income must NOT amount-dedupe - two 1000-元 income
    // events for different projects within 36h are real and distinct.
    test('income does NOT dedupe by amount when purpose differs', () async {
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

      final entries = await service.getRecentEntries(limit: 10);
      expect(entries, hasLength(2));
    });

    // Regression: 2026-08-14 real-device bug - three identical 30 CNY penalties
    // were recorded in ~10 min because the companion agent re-fired the penalty
    // on each checkin tick. The primary fix is Growth Pact settlement, but the
    // ledger must also dedupe same-amount penalties within a short window.
    test('penalty dedupes by amount within 30min when purpose differs', () async {
      await service.recordEntry(
        characterId: 'i',
        entryType: 'penalty',
        totalAmount: 30,
        aiAmount: 30,
        purpose: '⚠️ 惩罚: 又没早睡',
      );
      await service.recordEntry(
        characterId: 'i',
        entryType: 'penalty',
        totalAmount: 30,
        aiAmount: 30,
        purpose: '⚠️ 惩罚: 说了要早睡的',
      );

      final entries = await service.getRecentEntries(limit: 10);
      expect(entries, hasLength(1));
      expect(entries.single['total_amount'], 30);
    });

    // Guard: two penalties for the same amount but hours apart are real and
    // distinct - must NOT dedupe.
    test('penalty does NOT dedupe when outside the 30min window', () async {
      final oldTime = DateTime.now().subtract(const Duration(hours: 2));
      await service.recordEntry(
        characterId: 'i',
        entryType: 'penalty',
        totalAmount: 30,
        aiAmount: 30,
        purpose: '⚠️ 惩罚: 没早睡',
        occurredAt: oldTime,
      );
      await service.recordEntry(
        characterId: 'i',
        entryType: 'penalty',
        totalAmount: 30,
        aiAmount: 30,
        purpose: '⚠️ 惩罚: 又没早睡',
      );

      final entries = await service.getRecentEntries(limit: 10);
      expect(entries, hasLength(2));
    });
  });
}
