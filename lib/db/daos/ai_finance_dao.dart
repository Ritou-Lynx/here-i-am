import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'ai_finance_dao.g.dart';

@DriftAccessor(tables: [AiFinanceLedger])
class AiFinanceDao extends DatabaseAccessor<AppDatabase>
    with _$AiFinanceDaoMixin {
  AiFinanceDao(super.db);

  Future<void> insertEntry(AiFinanceLedgerCompanion entry) async {
    await into(aiFinanceLedger).insert(entry);
  }

  Future<List<AiFinanceLedgerData>> getSharedEntries({
    String? entryType,
    int? sinceEpoch,
    int? untilEpoch,
    int limit = 50,
  }) async {
    final query = select(aiFinanceLedger);
    if (entryType != null) {
      query.where((t) => t.entryType.equals(entryType));
    }
    if (sinceEpoch != null) {
      query.where((t) => t.recordedAt.isBiggerOrEqualValue(sinceEpoch));
    }
    if (untilEpoch != null) {
      query.where((t) => t.recordedAt.isSmallerOrEqualValue(untilEpoch));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.recordedAt)]);
    query.limit(limit);
    return query.get();
  }

  Future<List<AiFinanceLedgerData>> getSharedEntriesForPeriod({
    int? sinceEpoch,
    int? untilEpoch,
  }) async {
    final query = select(aiFinanceLedger);
    if (sinceEpoch != null) {
      query.where((t) => t.recordedAt.isBiggerOrEqualValue(sinceEpoch));
    }
    if (untilEpoch != null) {
      query.where((t) => t.recordedAt.isSmallerOrEqualValue(untilEpoch));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.recordedAt)]);
    return query.get();
  }

  /// Returns sum of aiAmount grouped by entryType for the shared AI ledger.
  Future<Map<String, double>> getSumsByType({
    int? sinceEpoch,
    int? untilEpoch,
  }) async {
    final query = select(aiFinanceLedger);
    if (sinceEpoch != null) {
      query.where((t) => t.recordedAt.isBiggerOrEqualValue(sinceEpoch));
    }
    if (untilEpoch != null) {
      query.where((t) => t.recordedAt.isSmallerOrEqualValue(untilEpoch));
    }
    final rows = await query.get();

    final sums = <String, double>{};
    for (final row in rows) {
      sums[row.entryType] = (sums[row.entryType] ?? 0.0) + row.aiAmount;
    }
    return sums;
  }
}
