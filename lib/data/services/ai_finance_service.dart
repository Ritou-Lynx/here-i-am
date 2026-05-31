import 'package:uuid/uuid.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/ai_finance_dao.dart';
import 'package:drift/drift.dart';

class AiFinanceService {
  final AppDatabase _db;
  late final AiFinanceDao _dao = AiFinanceDao(_db);

  AiFinanceService({required AppDatabase db}) : _db = db;

  static const _uuid = Uuid();

  Future<String> recordEntry({
    required String characterId,
    required String entryType,
    required double totalAmount,
    required double aiAmount,
    double? contributionRatio,
    String? myContributionDesc,
    String? aiContributionDesc,
    String? purpose,
    String? linkedFactId,
    String? notes,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _dao.insertEntry(AiFinanceLedgerCompanion.insert(
      id: id,
      characterId: characterId,
      entryType: entryType,
      totalAmount: totalAmount,
      aiAmount: aiAmount,
      contributionRatio: Value(contributionRatio),
      myContributionDesc: Value(myContributionDesc),
      aiContributionDesc: Value(aiContributionDesc),
      purpose: Value(purpose),
      linkedFactId: Value(linkedFactId),
      recordedAt: now,
      notes: Value(notes),
    ));
    return id;
  }

  /// Returns a structured summary for the companion to reason about.
  Future<Map<String, dynamic>> getSummary({
    required String characterId,
    String? month, // 'YYYY-MM', if null returns all-time
  }) async {
    int? sinceEpoch;
    int? untilEpoch;
    if (month != null) {
      final parts = month.split('-');
      final year = int.parse(parts[0]);
      final mon = int.parse(parts[1]);
      final start = DateTime(year, mon);
      final end = DateTime(year, mon + 1);
      sinceEpoch = start.millisecondsSinceEpoch ~/ 1000;
      untilEpoch = end.millisecondsSinceEpoch ~/ 1000 - 1;
    }

    final sums = await _dao.getSumsByType(
      characterId: characterId,
      sinceEpoch: sinceEpoch,
      untilEpoch: untilEpoch,
    );

    final income = sums['income'] ?? 0.0;
    final cost = sums['cost'] ?? 0.0;
    final loan = sums['loan'] ?? 0.0;
    final repayment = sums['repayment'] ?? 0.0;

    // balance = income + repayment - cost - loan
    final balance = income + repayment - cost - loan;

    // all-time totals for debt calculation
    final allSums = month != null
        ? await _dao.getSumsByType(characterId: characterId)
        : sums;
    final allIncome = allSums['income'] ?? 0.0;
    final allCost = allSums['cost'] ?? 0.0;
    final allLoan = allSums['loan'] ?? 0.0;
    final allRepayment = allSums['repayment'] ?? 0.0;
    final allBalance = allIncome + allRepayment - allCost - allLoan;

    return {
      'period': month ?? 'all_time',
      'income': income,
      'cost': cost,
      'loan': loan,
      'repayment': repayment,
      'period_net': balance,
      'all_time_balance': allBalance,
      // Positive all_time_balance = savings; negative = still owes user
      'savings': allBalance > 0 ? allBalance : 0.0,
      'owes_user': allBalance < 0 ? -allBalance : 0.0,
    };
  }

  Future<List<Map<String, dynamic>>> getRecentEntries({
    required String characterId,
    int limit = 10,
  }) async {
    final rows = await _dao.getEntriesForCharacter(
      characterId: characterId,
      limit: limit,
    );
    return rows.map((r) => {
          'id': r.id,
          'type': r.entryType,
          'total_amount': r.totalAmount,
          'ai_amount': r.aiAmount,
          'contribution_ratio': r.contributionRatio,
          'my_contribution': r.myContributionDesc,
          'ai_contribution': r.aiContributionDesc,
          'purpose': r.purpose,
          'linked_fact_id': r.linkedFactId,
          'recorded_at': r.recordedAt,
          'notes': r.notes,
        }).toList();
  }
}
