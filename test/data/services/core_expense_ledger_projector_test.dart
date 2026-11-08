import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/data/services/core_expense_ledger_projector.dart';
import 'package:memex/db/app_database.dart';

Map<String, dynamic> _record(
  String id, {
  int revision = 1,
  double amount = 25.5,
  double aiAmount = 0,
  String item = '午饭 黄焖鸡',
  String note = '',
  String frontend = 'claude_web',
  String spentAt = '2026-11-07T12:30:00+08:00',
  bool voided = false,
}) =>
    {
      'id': id,
      'revision': revision,
      'data': {
        'spent_at': spentAt,
        'local_date': spentAt.substring(0, 10),
        'amount_cny': amount,
        'ai_amount_cny': aiAmount,
        'item': item,
        'category': 'food',
        'note': note,
        'source_frontend': frontend,
        'voided': voided,
      },
    };

void main() {
  late AppDatabase db;
  late CoreExpenseLedgerProjector projector;
  late AiFinanceService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    projector = CoreExpenseLedgerProjector(db: db);
    service = AiFinanceService(db: db);
  });

  tearDown(() => db.close());

  Future<List<AiFinanceLedgerData>> rows() =>
      db.select(db.aiFinanceLedger).get();

  test('projects Core expenses as owned expense rows with stable IDs',
      () async {
    expect(
        await projector.project([
          _record('a'),
          _record('b', frontend: 'chatgpt_web', note: '林埃请客', aiAmount: 10),
        ]),
        2);
    final all = await rows();
    expect(all, hasLength(2));
    final a = all.singleWhere(
        (r) => r.id == CoreExpenseLedgerProjector.entryIdFor('a'));
    expect(a.entryType, 'expense');
    expect(a.totalAmount, 25.5);
    expect(a.aiAmount, 0);
    expect(a.purpose, '午饭 黄焖鸡');
    expect(a.notes, '经 Claude 记账');
    expect(a.characterId, '${AiFinanceService.coreExpenseOwnerPrefix}claude_web');
    expect(a.recordedAt,
        DateTime.parse('2026-11-07T12:30:00+08:00').millisecondsSinceEpoch ~/ 1000);
    final b = all.singleWhere(
        (r) => r.id == CoreExpenseLedgerProjector.entryIdFor('b'));
    expect(b.notes, '林埃请客（经 ChatGPT 记账）');
    expect(b.aiAmount, 10);

    // Same revisions again: nothing to write.
    expect(await projector.project([_record('a'), _record('b')]), 0);
  });

  test('same amount and item from two records are both counted', () async {
    await projector.project([_record('a'), _record('b')]);
    final entries = await service.getRecentEntries(limit: 10);
    expect(entries, hasLength(2));
  });

  test('a manual entry of the same spending is not swallowed by dedupe',
      () async {
    await projector.project([_record('a')]);
    final result = await service.recordEntryWithResult(
      characterId: 'char-a',
      entryType: 'expense',
      totalAmount: 25.5,
      aiAmount: 0,
      purpose: '午饭 黄焖鸡',
      occurredAt: DateTime.parse('2026-11-07T12:40:00+08:00'),
    );
    expect(result.created, isTrue);
  });

  test('new revision updates, void and disappearance remove the row',
      () async {
    await projector.project([_record('a'), _record('b')]);
    await projector.project([
      _record('a', revision: 2, amount: 30, item: '午饭 加饭'),
      _record('b'),
    ]);
    var a = await (db.select(db.aiFinanceLedger)
          ..where((t) => t.id.equals(CoreExpenseLedgerProjector.entryIdFor('a'))))
        .getSingle();
    expect(a.totalAmount, 30);
    expect(a.purpose, '午饭 加饭');

    await projector.project([_record('a', revision: 3, voided: true), _record('b')]);
    expect((await rows()).map((r) => r.id),
        [CoreExpenseLedgerProjector.entryIdFor('b')]);

    await projector.project([]);
    expect(await rows(), isEmpty);
  });

  test('user edits and deletes stick until the AI changes the record',
      () async {
    await projector.project([_record('a'), _record('b')]);
    final aId = CoreExpenseLedgerProjector.entryIdFor('a');
    final bId = CoreExpenseLedgerProjector.entryIdFor('b');
    await service.updateEntry(entryId: aId, totalAmount: 20);
    await service.deleteEntry(bId);

    await projector.project([_record('a'), _record('b')]);
    final kept = await rows();
    expect(kept, hasLength(1));
    expect(kept.single.totalAmount, 20);

    await projector.project([_record('a', revision: 2, amount: 40), _record('b')]);
    final a = await (db.select(db.aiFinanceLedger)..where((t) => t.id.equals(aId)))
        .getSingle();
    expect(a.totalAmount, 40);
  });

  test('never overwrites a row owned by another writer and skips bad data',
      () async {
    final id = CoreExpenseLedgerProjector.entryIdFor('a');
    await db.into(db.aiFinanceLedger).insert(AiFinanceLedgerCompanion.insert(
          id: id,
          characterId: AiFinanceService.manualUserCharacterId,
          entryType: 'income',
          totalAmount: 100,
          aiAmount: 30,
          recordedAt: 1,
        ));
    final bad = _record('c');
    (bad['data'] as Map)['amount_cny'] = -1;
    expect(await projector.project([_record('a'), bad]), 0);
    final row = await (db.select(db.aiFinanceLedger)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.entryType, 'income');
    expect(await rows(), hasLength(1));
  });
}
