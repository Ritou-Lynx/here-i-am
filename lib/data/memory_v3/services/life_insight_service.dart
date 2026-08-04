/// Life Insight Service — 跨 User-truth 聚合分析层。
///
/// 读已有的 Memory Cards / COROS / Ledger 等原始数据，产出结构化洞察
/// （趋势/模式/基线/异常/预测），喂给三个消费者：
///   1. 观察面板 Insight Strip（展示）
///   2. Growth Pacts calibrate（推断合理目标）
///   3. Check-in snapshot（"该不该介入"信号）
///
/// 写入方式：按 (domain, insightType, period, periodStart) 做 upsert，
/// 同一周期同一类型重算时 overwrite，不 append。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';

final _log = Logger('LifeInsightService');
const _uuid = Uuid();

class LifeInsightService {
  final AppDatabase _db;

  LifeInsightService({required AppDatabase db}) : _db = db;

  static bool _initialized = false;
  static LifeInsightService? _instance;

  static bool get isInitialized => _initialized;

  static void init(AppDatabase db) {
    _instance = LifeInsightService(db: db);
    _initialized = true;
  }

  static LifeInsightService get instance {
    if (!_initialized || _instance == null) {
      throw StateError('LifeInsightService not initialized. Call init() first.');
    }
    return _instance!;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Write — upsert by (domain, insightType, period, periodStart)
  // ──────────────────────────────────────────────────────────────────────

  /// 写入或覆盖一条洞察。同一周期同一类型重算时 overwrite。
  ///
  /// 查重粒度为 (domain, insightType, period)——忽略 periodStart，因为
  /// weekly/monthly 的 periodStart 随 now 漂移，按精确 periodStart 匹配会
  /// 导致每次重算都 INSERT 新行、旧行永久累积。先删除同三元组的旧行，
  /// 再插入新行，保证新 insight 取代旧的。
  Future<String> upsertInsight({
    required String domain,
    required String insightType,
    required String period,
    required int periodStart,
    required int periodEnd,
    required String narrative,
    List<Map<String, dynamic>> dataPoints = const [],
    double confidence = 0.5,
    Map<String, dynamic>? pactSignal,
    String authority = 'agent_inferred',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dataPointsJson = jsonEncode(dataPoints);
    final pactSignalJson = pactSignal != null ? jsonEncode(pactSignal) : null;

    // 删除同 (domain, insightType, period) 的旧行（忽略 periodStart 漂移）。
    await (_db.delete(_db.lifeInsights)
          ..where((t) =>
              t.domain.equals(domain) &
              t.insightType.equals(insightType) &
              t.period.equals(period)))
        .go();

    final id = _uuid.v4();
    await _db.into(_db.lifeInsights).insert(
          LifeInsightsCompanion.insert(
            id: id,
            domain: domain,
            insightType: insightType,
            period: period,
            periodStart: periodStart,
            periodEnd: periodEnd,
            narrative: narrative,
            dataPointsJson: Value(dataPointsJson),
            confidence: Value(confidence),
            pactSignalJson: Value(pactSignalJson),
            authority: Value(authority),
            createdAt: now,
            updatedAt: now,
          ),
        );
    _log.info('Insight created: $id $domain/$insightType/$period');
    return id;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Query
  // ──────────────────────────────────────────────────────────────────────

  /// 一次性清理：保留每个 (domain, insightType, period) 最新的一行，
  /// 删除因 periodStart 漂移导致的历史累积旧行。幂等，重复调用安全。
  /// 在 app 启动时执行一次，回收旧版本遗留的重复行。
  Future<int> deduplicateLegacyRows() async {
    // 取所有行，按 (domain, insightType, period) 分组，每组保留 updatedAt 最大的一行。
    final all = await (_db.select(_db.lifeInsights)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    final keepIds = <String>{};
    final seenKeys = <String>{};
    for (final row in all) {
      final key = '${row.domain}|${row.insightType}|${row.period}';
      if (seenKeys.add(key)) {
        keepIds.add(row.id);
      }
    }
    if (all.length <= keepIds.length) return 0;
    final deleteCount = all.length - keepIds.length;
    await (_db.delete(_db.lifeInsights)
          ..where((t) => t.id.isNotIn(keepIds.toList())))
        .go();
    _log.info('Insight dedup: removed $deleteCount legacy rows, '
        'kept ${keepIds.length}');
    return deleteCount;
  }

  /// 某个 domain 的最新洞察（所有 insightType）。
  Future<List<LifeInsight>> getLatestByDomain(String domain,
      {int limit = 5}) async {
    final query = _db.select(_db.lifeInsights)
      ..where((t) => t.domain.equals(domain))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    return query.get();
  }

  /// 某个 domain + insightType 的最新洞察。
  Future<LifeInsight?> getLatest(String domain, String insightType) async {
    final query = _db.select(_db.lifeInsights)
      ..where((t) =>
          t.domain.equals(domain) & t.insightType.equals(insightType))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// 所有带有 pactSignal 的洞察（供 GrowthPactService 消费）。
  Future<List<LifeInsight>> getInsightsWithPactSignal(
      {int sinceHours = 24}) async {
    final cutoff = DateTime.now()
            .subtract(Duration(hours: sinceHours))
            .millisecondsSinceEpoch;
    final query = _db.select(_db.lifeInsights)
      ..where((t) =>
          t.pactSignalJson.isNotNull() &
          t.updatedAt.isBiggerThanValue(cutoff))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  /// 某时间区间内的所有洞察（面板展示用）。
  Future<List<LifeInsight>> getInsightsInRange(
      {required int fromMs, required int toMs}) async {
    final query = _db.select(_db.lifeInsights)
      ..where((t) =>
          t.updatedAt.isBiggerOrEqualValue(fromMs) &
          t.updatedAt.isSmallerOrEqualValue(toMs))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Snapshot text — 给 check-in snapshot 用
  // ──────────────────────────────────────────────────────────────────────

  /// 构建 check-in snapshot 用的 "Recent Insights" 文本段。
  /// 只取最近 24h 更新的洞察，每个 domain 最多 2 条。
  Future<String> buildSnapshotSection({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final cutoff = moment.subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

    final insights = await getInsightsInRange(
        fromMs: cutoff, toMs: moment.millisecondsSinceEpoch);

    if (insights.isEmpty) return '';

    // 按 domain 分组，每个 domain 最多 2 条
    final byDomain = <String, List<LifeInsight>>{};
    for (final ins in insights) {
      byDomain.putIfAbsent(ins.domain, () => []).add(ins);
    }

    final lines = <String>['## Recent Life Insights (last 24h)'];
    for (final entry in byDomain.entries) {
      final domainInsights = entry.value.take(2);
      for (final ins in domainInsights) {
        final typeTag = _typeEmoji(ins.insightType);
        lines.add('- $typeTag ${ins.domain}/${ins.insightType}: '
            '${ins.narrative}');
      }
    }
    return lines.join('\n');
  }

  /// 构建观察面板用的 insight strip 文本（单 domain）。
  Future<String> buildPanelInsightStrip(String domain,
      {int limit = 3}) async {
    final insights = await getLatestByDomain(domain, limit: limit);
    if (insights.isEmpty) return '';

    final lines = <String>[];
    for (final ins in insights) {
      final typeTag = _typeEmoji(ins.insightType);
      lines.add('$typeTag ${ins.narrative}');
    }
    return lines.join('\n');
  }

  String _typeEmoji(String insightType) {
    switch (insightType) {
      case 'trend':
        return '📈';
      case 'pattern':
        return '🔁';
      case 'streak':
        return '🔥';
      case 'baseline':
        return '📊';
      case 'anomaly':
        return '⚠️';
      case 'projection':
        return '🔮';
      default:
        return '💡';
    }
  }
}