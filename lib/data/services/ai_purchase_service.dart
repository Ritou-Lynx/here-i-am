import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/ai_purchase_dao.dart';

class BudgetExceededError implements Exception {
  final String message;
  BudgetExceededError(this.message);
  @override
  String toString() => message;
}

class WhitelistViolationError implements Exception {
  final String message;
  WhitelistViolationError(this.message);
  @override
  String toString() => message;
}

/// Manages autonomous shopping budget limits and purchase logs.
///
/// Budget config is persisted in KvStore under the `shopping.*` bucket.
/// The user sets limits via settings; the companion reads them via tools
/// but cannot modify them — safety is enforced here, not by the LLM.
class AiPurchaseService {
  final AppDatabase _db;
  late final AiPurchaseDao _dao = AiPurchaseDao(_db);
  static const _uuid = Uuid();

  /// Platforms the companion is allowed to shop on.
  static const _allowedPlatforms = {'taobao'};

  /// Keywords that indicate a non-physical or prohibited purchase category.
  static const _blockedKeywords = {
    '转账', '提现', '充值', '虚拟货币', '订阅', '理财', '保险',
    'transfer', 'withdraw', 'recharge', 'crypto', 'subscription',
  };

  AiPurchaseService({required AppDatabase db}) : _db = db;

  // ── KvStore keys ──────────────────────────────────────────────────────────
  static const _kEnabled = 'shopping.enabled';
  static const _kPaymentMode = 'shopping.payment_mode';
  static const _kPerTxLimit = 'shopping.per_tx_limit_cny';
  static const _kCumulativeLimit = 'shopping.cumulative_limit_cny';
  static const _kCumulativeSpent = 'shopping.cumulative_spent_cny';

  static const double _defaultPerTxLimit = 50.0;
  static const double _defaultCumulativeLimit = 200.0;

  // ── KvStore helpers ───────────────────────────────────────────────────────
  Future<String?> _kvGet(String key) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _kvSet(String key, String value) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: key,
            value: Value(value),
            updatedAt: Value(now),
          ),
        );
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getBudgetStatus() async {
    final enabled = (await _kvGet(_kEnabled)) == 'true';
    final paymentMode = (await _kvGet(_kPaymentMode)) ?? 'manual_approval';
    final perTxLimit =
        double.tryParse((await _kvGet(_kPerTxLimit)) ?? '') ??
            _defaultPerTxLimit;
    final cumulativeLimit =
        double.tryParse((await _kvGet(_kCumulativeLimit)) ?? '') ??
            _defaultCumulativeLimit;
    final cumulativeSpent =
        double.tryParse((await _kvGet(_kCumulativeSpent)) ?? '') ?? 0.0;

    return {
      'enabled': enabled,
      'payment_mode': paymentMode,
      'per_tx_limit_cny': perTxLimit,
      'cumulative_limit_cny': cumulativeLimit,
      'cumulative_spent_cny': cumulativeSpent,
      'cumulative_remaining_cny': cumulativeLimit - cumulativeSpent,
    };
  }

  /// Configure budget from the settings page. Not callable by the AI.
  Future<void> configureBudget({
    bool? enabled,
    double? perTxLimitCny,
    double? cumulativeLimitCny,
    String? paymentMode,
  }) async {
    if (enabled != null) await _kvSet(_kEnabled, enabled.toString());
    if (perTxLimitCny != null) {
      await _kvSet(_kPerTxLimit, perTxLimitCny.toString());
    }
    if (cumulativeLimitCny != null) {
      await _kvSet(_kCumulativeLimit, cumulativeLimitCny.toString());
    }
    if (paymentMode != null) await _kvSet(_kPaymentMode, paymentMode);
  }

  Future<void> resetCumulativeSpent() =>
      _kvSet(_kCumulativeSpent, '0.0');

  /// Hard budget and whitelist check. Throws [BudgetExceededError] or
  /// [WhitelistViolationError] on violation — never returns silently unsafe.
  Future<void> checkBudget({
    required double amountCny,
    required String platform,
    String? productTitle,
  }) async {
    final status = await getBudgetStatus();

    if (!(status['enabled'] as bool)) {
      throw BudgetExceededError(
          '购物功能未开启。请在设置 → 购物助手中开启并配置预算后再试。');
    }

    if (!_allowedPlatforms.contains(platform.toLowerCase())) {
      throw WhitelistViolationError(
          'Platform "$platform" is not in the allowed list: $_allowedPlatforms');
    }

    if (productTitle != null) {
      for (final kw in _blockedKeywords) {
        if (productTitle.toLowerCase().contains(kw.toLowerCase())) {
          throw WhitelistViolationError(
              '商品「$productTitle」包含禁止关键词「$kw」。仅允许购买实物商品，禁止转账/充值/虚拟货币/订阅等。');
        }
      }
    }

    final perTxLimit = status['per_tx_limit_cny'] as double;
    final remaining = status['cumulative_remaining_cny'] as double;

    if (amountCny > perTxLimit) {
      throw BudgetExceededError(
          '¥${amountCny.toStringAsFixed(2)} 超出单笔上限 ¥${perTxLimit.toStringAsFixed(2)}，已中止。');
    }
    if (amountCny > remaining) {
      throw BudgetExceededError(
          '¥${amountCny.toStringAsFixed(2)} 超出剩余累计额度 ¥${remaining.toStringAsFixed(2)}，已中止。需要你手动补充额度才能继续。');
    }
  }

  /// Create a new purchase log. Returns the log ID.
  Future<String> createPurchaseLog({
    required String characterId,
    required String userInstruction,
    required String paymentMode,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _dao.insertEntry(AiPurchaseLogCompanion.insert(
      id: id,
      characterId: characterId,
      paymentMode: paymentMode,
      status: 'searching',
      userInstruction: userInstruction,
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  }

  Future<void> updatePurchaseStatus({
    required String id,
    required String status,
    String? productId,
    String? productTitle,
    String? productUrl,
    double? priceCny,
    String? cashierUrl,
    String? failureReason,
    String? linkedLedgerId,
  }) =>
      _dao.updateFields(
        id: id,
        status: status,
        productId: productId,
        productTitle: productTitle,
        productUrl: productUrl,
        priceCny: priceCny,
        cashierUrl: cashierUrl,
        failureReason: failureReason,
        linkedLedgerId: linkedLedgerId,
      );

  /// Deduct [amountCny] from the cumulative remaining budget after payment.
  Future<void> recordSpend(double amountCny) async {
    final current =
        double.tryParse((await _kvGet(_kCumulativeSpent)) ?? '') ?? 0.0;
    await _kvSet(_kCumulativeSpent, (current + amountCny).toString());
  }

  /// IDs of purchases still in-flight — used to build the Supabase query.
  Future<List<String>> getPendingPurchaseIds({
    required String characterId,
  }) async {
    final rows =
        await _dao.getPendingForCharacter(characterId: characterId);
    return rows.map((r) => r.id).toList();
  }

  /// Apply status updates received from Supabase remote tasks to the local log.
  ///
  /// Returns a summary of what changed (id + new_status) so the tool can
  /// report it to the LLM / user.
  Future<List<Map<String, dynamic>>> syncFromRemoteTasks(
      List<Map<String, dynamic>> remoteTasks) async {
    final updates = <Map<String, dynamic>>[];
    for (final remote in remoteTasks) {
      final id = remote['id'] as String?;
      final remoteStatus = remote['status'] as String?;
      if (id == null || remoteStatus == null) continue;

      final local = await _dao.getById(id);
      if (local == null || local.status == remoteStatus) continue;

      await updatePurchaseStatus(
        id: id,
        status: remoteStatus,
        cashierUrl: remote['cashier_url'] as String?,
        priceCny: (remote['actual_price_cny'] as num?)?.toDouble(),
        failureReason: remote['error'] as String?,
      );

      // Record spend when Hermes marks the payment as confirmed.
      if (remoteStatus == 'done') {
        final price = (remote['actual_price_cny'] as num?)?.toDouble();
        if (price != null && price > 0) await recordSpend(price);
      }

      updates.add({
        'id': id,
        'new_status': remoteStatus,
        'product': remote['product_hint'] ?? local.productTitle,
        'cashier_url': remote['cashier_url'],
        'error': remote['error'],
      });
    }
    return updates;
  }

  Future<List<Map<String, dynamic>>> getRecentPurchases({
    required String characterId,
    int limit = 5,
  }) async {
    final rows = await _dao.getRecentForCharacter(
        characterId: characterId, limit: limit);
    return rows
        .map((r) => {
              'id': r.id,
              'status': r.status,
              'instruction': r.userInstruction,
              'product': r.productTitle,
              'price_cny': r.priceCny,
              'platform': r.productPlatform,
              'payment_mode': r.paymentMode,
              'cashier_url': r.cashierUrl,
              'failure': r.failureReason,
              'created_at': r.createdAt,
            })
        .toList();
  }
}
