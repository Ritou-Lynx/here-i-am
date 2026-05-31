import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'ai_purchase_dao.g.dart';

@DriftAccessor(tables: [AiPurchaseLog])
class AiPurchaseDao extends DatabaseAccessor<AppDatabase>
    with _$AiPurchaseDaoMixin {
  AiPurchaseDao(super.db);

  Future<void> insertEntry(AiPurchaseLogCompanion entry) =>
      into(aiPurchaseLog).insert(entry);

  Future<void> updateFields({
    required String id,
    required String status,
    String? productId,
    String? productTitle,
    String? productUrl,
    double? priceCny,
    String? cashierUrl,
    String? failureReason,
    String? linkedLedgerId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (update(aiPurchaseLog)..where((t) => t.id.equals(id))).write(
      AiPurchaseLogCompanion(
        status: Value(status),
        updatedAt: Value(now),
        productId:
            productId != null ? Value(productId) : const Value.absent(),
        productTitle:
            productTitle != null ? Value(productTitle) : const Value.absent(),
        productUrl:
            productUrl != null ? Value(productUrl) : const Value.absent(),
        priceCny: priceCny != null ? Value(priceCny) : const Value.absent(),
        cashierUrl:
            cashierUrl != null ? Value(cashierUrl) : const Value.absent(),
        failureReason: failureReason != null
            ? Value(failureReason)
            : const Value.absent(),
        linkedLedgerId: linkedLedgerId != null
            ? Value(linkedLedgerId)
            : const Value.absent(),
      ),
    );
  }

  Future<AiPurchaseLogData?> getById(String id) =>
      (select(aiPurchaseLog)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<AiPurchaseLogData>> getRecentForCharacter({
    required String characterId,
    int limit = 10,
  }) =>
      (select(aiPurchaseLog)
            ..where((t) => t.characterId.equals(characterId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .get();

  /// Returns purchases that are still in-flight and eligible for remote sync.
  Future<List<AiPurchaseLogData>> getPendingForCharacter({
    required String characterId,
    int limit = 20,
  }) =>
      (select(aiPurchaseLog)
            ..where((t) =>
                t.characterId.equals(characterId) &
                t.status.isNotIn(const ['done', 'failed', 'aborted']))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .get();
}
