/// Growth Pact Service — 成长契约（教练模式的目标/习惯/约定追踪）。
///
/// 这是"用户对未来的自己有期待"的结构化载体。和 Topic Thread 一样是活文档
/// + append-only 执行日志的模式，但面向"目标/习惯/约定"。
///
/// 核心设计：target 是 agent_inferred 且可变的。林埃基于 Life Insights
/// 推断的 baseline + dailyAdjust 形成当前生效目标，用户可以微调但不需要
/// 主动设定。
///
/// 生命周期：emerging → active → calibrating(持续) → achieved/faded
/// authority 分层：target/baseline = agent_inferred 或 user_adjusted
///                stakes（罚款/奖励）= user_confirmed（严格）
///                check 记录 = agent_inferred 或 user_confirmed
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';
import 'life_insight_service.dart';

final _log = Logger('GrowthPactService');
const _uuid = Uuid();

class GrowthPactService {
  final AppDatabase _db;

  GrowthPactService({required AppDatabase db}) : _db = db;

  static bool _initialized = false;
  static GrowthPactService? _instance;

  static bool get isInitialized => _initialized;

  static void init(AppDatabase db) {
    _instance = GrowthPactService(db: db);
    _initialized = true;
  }

  static GrowthPactService get instance {
    if (!_initialized || _instance == null) {
      throw StateError('GrowthPactService not initialized. Call init() first.');
    }
    return _instance!;
  }

  // ──────────────────────────────────────────────────────────────────────
  // CRUD — GrowthPacts
  // ──────────────────────────────────────────────────────────────────────

  Future<String> createPact({
    required String kind,
    required String domain,
    required String description,
    Map<String, dynamic>? target,
    Map<String, dynamic>? stakes,
    String status = 'emerging',
    String authority = 'agent_inferred',
    String origin = 'conversation',
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.growthPacts).insert(
          GrowthPactsCompanion.insert(
            id: id,
            kind: kind,
            domain: domain,
            description: description,
            targetJson: Value(target != null ? jsonEncode(target) : '{}'),
            stakesJson: Value(stakes != null ? jsonEncode(stakes) : null),
            status: Value(status),
            authority: Value(authority),
            origin: Value(origin),
            lastCalibratedAt: Value(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
    _log.info('Pact created: $id kind=$kind domain=$domain "$description"');
    return id;
  }

  Future<void> updateTarget(String id, Map<String, dynamic> target) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.growthPacts)
          ..where((t) => t.id.equals(id)))
        .write(GrowthPactsCompanion(
      targetJson: Value(jsonEncode(target)),
      lastCalibratedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateStakes(
      String id, Map<String, dynamic> stakes) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // stakes 始终用 user_confirmed authority
    await (_db.update(_db.growthPacts)
          ..where((t) => t.id.equals(id)))
        .write(GrowthPactsCompanion(
      stakesJson: Value(jsonEncode(stakes)),
      authority: const Value('user_confirmed'),
      updatedAt: Value(now),
    ));
  }

  Future<void> setStatus(String id, String status) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.growthPacts)
          ..where((t) => t.id.equals(id)))
        .write(GrowthPactsCompanion(
      status: Value(status),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateDescription(String id, String description) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.growthPacts)
          ..where((t) => t.id.equals(id)))
        .write(GrowthPactsCompanion(
      description: Value(description),
      updatedAt: Value(now),
    ));
  }

  // ──────────────────────────────────────────────────────────────────────
  // Query
  // ──────────────────────────────────────────────────────────────────────

  /// 所有 active 状态的 pact（check-in 会注入这些）。
  Future<List<GrowthPact>> getActivePacts() async {
    final query = _db.select(_db.growthPacts)
      ..where((t) => t.status.equals('active'))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  /// active + emerging 状态的 pact（emerging 是还没正式督促但已注意到的）。
  Future<List<GrowthPact>> getActiveAndEmergingPacts() async {
    final query = _db.select(_db.growthPacts)
      ..where((t) =>
          t.status.equals('active') | t.status.equals('emerging'))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  Future<List<GrowthPact>> getPactsByDomain(String domain) async {
    final query = _db.select(_db.growthPacts)
      ..where((t) =>
          t.domain.equals(domain) &
          (t.status.equals('active') | t.status.equals('emerging')))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  Future<GrowthPact?> getPact(String id) async {
    final query = _db.select(_db.growthPacts)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    return query.getSingleOrNull();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Check logs — append-only
  // ──────────────────────────────────────────────────────────────────────

  Future<String> recordCheck({
    required String pactId,
    required String result,
    String? actualValue,
    String? targetValue,
    List<Map<String, dynamic>> evidence = const [],
    String? penaltyLedgerId,
    String? rewardLedgerId,
    String sourceType = 'checkin',
    String authority = 'agent_inferred',
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.growthPactChecks).insert(
          GrowthPactChecksCompanion.insert(
            id: id,
            pactId: pactId,
            checkedAt: now,
            result: result,
            actualValue: Value(actualValue),
            targetValue: Value(targetValue),
            evidenceJson: Value(jsonEncode(evidence)),
            penaltyLedgerId: Value(penaltyLedgerId),
            rewardLedgerId: Value(rewardLedgerId),
            sourceType: Value(sourceType),
            authority: Value(authority),
            createdAt: now,
          ),
        );
    _log.info('Pact check recorded: pact=$pactId result=$result');
    return id;
  }

  /// 某个 pact 最近的 N 条 check 记录。
  Future<List<GrowthPactCheck>> getRecentChecks(String pactId,
      {int limit = 7}) async {
    final query = _db.select(_db.growthPactChecks)
      ..where((t) => t.pactId.equals(pactId))
      ..orderBy([(t) => OrderingTerm.desc(t.checkedAt)])
      ..limit(limit);
    return query.get();
  }

  /// 某个 pact 在某时间区间内的 miss 次数（用于罚款判断）。
  Future<int> countMissesInRange(String pactId,
      {required int fromMs, required int toMs}) async {
    final count = _db.selectOnly(_db.growthPactChecks)
      ..addColumns([_db.growthPactChecks.id.count()])
      ..where((_db.growthPactChecks.pactId.equals(pactId)) &
          (_db.growthPactChecks.result.equals('miss')) &
          (_db.growthPactChecks.checkedAt
              .isBiggerOrEqualValue(fromMs)) &
          (_db.growthPactChecks.checkedAt.isSmallerOrEqualValue(toMs)));
    final result = await count.getSingle();
    return result.read(_db.growthPactChecks.id.count()) ?? 0;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Calibrate — 基于 Life Insights 重新推断 target
  // ──────────────────────────────────────────────────────────────────────

  /// 基于 Life Insights 的 baseline/trend 重新推断 pact target。
  /// 由 Dreaming/Insights 周期调用，不是每次 check-in 都跑。
  Future<void> calibrateFromInsights(String pactId) async {
    final pact = await getPact(pactId);
    if (pact == null) return;

    final target = _decodeTarget(pact.targetJson);
    final domain = pact.domain;

    // 读 Life Insights 的 baseline
    final baselineInsight =
        await LifeInsightService.instance.getLatest(domain, 'baseline');
    final trendInsight =
        await LifeInsightService.instance.getLatest(domain, 'trend');

    final newTarget = Map<String, dynamic>.from(target);

    if (baselineInsight != null) {
      // 从 baseline insight 的 dataPoints 提取 range
      final dp = _decodeDataPoints(baselineInsight.dataPointsJson);
      if (dp.isNotEmpty) {
        newTarget['baseline'] = {
          'narrative': baselineInsight.narrative,
          'confidence': baselineInsight.confidence,
          'source': 'life_insight_${baselineInsight.id.substring(0, 8)}',
        };
      }
    }

    if (trendInsight != null) {
      newTarget['trendDirection'] = _inferTrendDirection(trendInsight);
    }

    // 根据 trend 方向微调 current target
    newTarget['current'] = _adjustCurrentTarget(newTarget);

    await updateTarget(pactId, newTarget);
    _log.info('Pact calibrated: $pactId domain=$domain');
  }

  // ──────────────────────────────────────────────────────────────────────
  // Snapshot text — 给 check-in snapshot 用
  // ──────────────────────────────────────────────────────────────────────

  /// 构建 check-in snapshot 用的 "Active Pacts" 文本段。
  /// 只包含 active 状态的 pact，emerging 不注入（还没正式督促）。
  Future<String> buildSnapshotSection({DateTime? now}) async {
    final pacts = await getActivePacts();
    if (pacts.isEmpty) return '';

    final moment = now ?? DateTime.now();
    final lines = <String>['## Active Growth Pacts'];

    for (final pact in pacts) {
      final target = _decodeTarget(pact.targetJson);
      final stakes = _decodeStakes(pact.stakesJson);

      final kindEmoji = _kindEmoji(pact.kind);
      final current = target['current'] as Map<String, dynamic>?;
      final currentRange = current?['range'] ?? target['baseline']?['range'] ?? '?';

      // 读最近 7 天的 check 记录
      final weekAgo = moment.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final recentChecks = await getRecentChecks(pact.id, limit: 7);
      final recentMisses =
          await countMissesInRange(pact.id, fromMs: weekAgo, toMs: moment.millisecondsSinceEpoch);

      final statusParts = <String>[];
      if (recentChecks.isNotEmpty) {
        final lastCheck = recentChecks.first;
        final resultEmoji = _resultEmoji(lastCheck.result);
        statusParts.add('last: $resultEmoji ${lastCheck.result}');
        if (lastCheck.actualValue != null) {
          statusParts.add('actual=${lastCheck.actualValue}');
        }
      }
      if (recentMisses > 0) {
        statusParts.add('misses this week: $recentMisses');
        if (stakes != null) {
          final penaltyPerMiss = stakes['penaltyPerMiss'];
          if (penaltyPerMiss != null && penaltyPerMiss > 0) {
            statusParts.add('⚠️ penalty due: $recentMisses × $penaltyPerMiss CNY');
          }
        }
      }

      lines.add('- $kindEmoji ${pact.kind}/${pact.domain}: '
          '${pact.description}');
      lines.add('    target: $currentRange');
      if (statusParts.isNotEmpty) {
        lines.add('    ${statusParts.join(' | ')}');
      }
    }

    return lines.join('\n');
  }

  // ──────────────────────────────────────────────────────────────────────
  // Pact signal consumption — 从 Life Insights 创建 emerging pact
  // ──────────────────────────────────────────────────────────────────────

  /// 扫描 Life Insights 的 pactSignal，为有信号但还没 pact 的洞察创建
  /// emerging 状态的 pact。由 Dreaming/Insights 周期调用。
  Future<List<String>> createEmergingPactsFromSignals() async {
    final insights =
        await LifeInsightService.instance.getInsightsWithPactSignal();
    if (insights.isEmpty) return [];

    final activePacts = await getActiveAndEmergingPacts();
    final existingDomains = activePacts.map((p) => p.domain).toSet();

    final created = <String>[];
    for (final ins in insights) {
      if (ins.pactSignalJson == null) continue;
      final signal = jsonDecode(ins.pactSignalJson!) as Map<String, dynamic>;
      final suggestedDomain = signal['suggestedDomain'] as String? ?? ins.domain;
      if (existingDomains.contains(suggestedDomain)) continue;

      final suggestedKind = signal['suggestedKind'] as String? ?? 'habit';
      final suggestedMetric = signal['suggestedMetric'] as String?;

      final pactId = await createPact(
        kind: suggestedKind,
        domain: suggestedDomain,
        description: suggestedMetric != null
            ? '从数据模式中发现：$suggestedMetric'
            : '从数据模式中发现',
        target: {
          'baseline': {
            'narrative': ins.narrative,
            'confidence': ins.confidence,
          },
          'current': {
            'range': 'TBD — emerging, not yet enforcing',
          },
          'confidence': ins.confidence * 0.7, // 降一级，因为是 inferred
        },
        status: 'emerging',
        origin: 'data_pattern',
      );
      created.add(pactId);
      _log.info('Emerging pact created from signal: $pactId '
          'domain=$suggestedDomain kind=$suggestedKind');
    }
    return created;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _decodeTarget(String json) {
    if (json.isEmpty) return {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic>? _decodeStakes(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _decodeDataPoints(String json) {
    if (json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  String _inferTrendDirection(LifeInsight insight) {
    final narrative = insight.narrative.toLowerCase();
    if (narrative.contains('变好') ||
        narrative.contains('变早') ||
        narrative.contains('减少') ||
        narrative.contains('下降') ||
        narrative.contains('improving') ||
        narrative.contains('better')) {
      return 'improving';
    }
    if (narrative.contains('变差') ||
        narrative.contains('变晚') ||
        narrative.contains('增加') ||
        narrative.contains('上升') ||
        narrative.contains('worse') ||
        narrative.contains('deteriorating')) {
      return 'deteriorating';
    }
    return 'stable';
  }

  Map<String, dynamic> _adjustCurrentTarget(
      Map<String, dynamic> target) {
    final trend = target['trendDirection'] as String? ?? 'stable';
    final baseline = target['baseline'] as Map<String, dynamic>?;
    if (baseline == null) return target;

    // 如果趋势在变好，不收紧目标（让用户保持当前节奏）
    // 如果趋势在变差，不放宽目标（但也不收紧，先稳住）
    // 这个逻辑很保守，后续可以更精细
    final current = Map<String, dynamic>.from(target['current'] as Map? ?? {});
    current['adjustmentReason'] =
        'trend=$trend, maintaining baseline target';
    target['current'] = current;
    return target;
  }

  String _kindEmoji(String kind) {
    switch (kind) {
      case 'goal':
        return '🎯';
      case 'habit':
        return '🌙';
      case 'agreement':
        return '🤝';
      default:
        return '📌';
    }
  }

  String _resultEmoji(String result) {
    switch (result) {
      case 'hit':
        return '✅';
      case 'miss':
        return '❌';
      case 'partial':
        return '🟡';
      case 'skipped':
        return '⏭️';
      default:
        return '❓';
    }
  }
}