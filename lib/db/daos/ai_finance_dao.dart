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

  /// Overwrite the matching ledger row with the supplied companion values.
  /// Caller is responsible for only setting the fields that should change.
  Future<void> updateEntry(
    String id,
    AiFinanceLedgerCompanion companion,
  ) async {
    await (update(aiFinanceLedger)..where((t) => t.id.equals(id)))
        .write(companion);
  }

  /// Hard-delete a single ledger row by id. Used for correcting wrong/duplicate
  /// entries — there is no soft-delete convention on this table (it is a
  /// derived view, not User-truth).
  Future<void> deleteEntry(String id) async {
    await (delete(aiFinanceLedger)..where((t) => t.id.equals(id))).go();
  }

  /// Fetch a single row by id, or null if missing/deleted.
  Future<AiFinanceLedgerData?> getEntryById(String id) async {
    return (select(aiFinanceLedger)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
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
