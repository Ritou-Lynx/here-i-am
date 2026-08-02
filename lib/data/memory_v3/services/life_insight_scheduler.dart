/// Life Insight Scheduler — orchestrates the LifeInsightAgent.
///
/// Two trigger paths (mirrors DreamingSchedulerService pattern):
/// - **Event-driven**: after new data is recorded (Memory Card written, COROS
///   synced), schedule a one-off analysis with a debounce delay.
/// - **Periodic fallback**: daily weekly analysis + monthly analysis.
///
/// The scheduler calls LifeInsightAgent.analyze(), then persists results via
/// LifeInsightService.upsertInsight(), and feeds pact signals to
/// GrowthPactService.createEmergingPactsFromSignals().
library;

import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/agents/life_insight_agent/agent.dart';
import 'package:memex/data/memory_v3/agents/life_insight_agent/rhythm_signal_extractor.dart';
import 'package:memex/data/memory_v3/services/growth_pact_service.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('memory_v3.LifeInsightScheduler');

class LifeInsightScheduler {
  LifeInsightScheduler({required AppDatabase db}) : _db = db;

  final AppDatabase _db;
  Timer? _debounceTimer;

  static const _debounceDelay = Duration(minutes: 10);
  static const _minInterval = Duration(minutes: 30);

  // ──────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────

  /// Debounced trigger — called after new data is recorded (Memory Card,
  /// COROS sync, ledger entry). Runs analysis after a short idle period.
  void scheduleEventDriven() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      runWeeklyAnalysis().catchError((e) {
        _logger.warning('LifeInsight event-driven analysis failed: $e');
      });
    });
    _logger.info('LifeInsight: event-driven analysis scheduled in '
        '${_debounceDelay.inMinutes} min');
  }

  /// Run weekly analysis (last 7 days). This is the primary analysis —
  /// produces trends, patterns, streaks, baselines.
  Future<void> runWeeklyAnalysis() async {
    await _runAnalysis(LifeInsightPeriod.weekly);
  }

  /// Force a weekly analysis, bypassing the rate limit. Used by the manual
  /// refresh button in the observation panels so the user can pull fresh
  /// insights on demand.
  Future<void> forceRunWeeklyAnalysis() async {
    await _runAnalysis(LifeInsightPeriod.weekly, force: true);
  }

  /// Run daily analysis (today). Produces baseline and anomaly insights.
  Future<void> runDailyAnalysis() async {
    await _runAnalysis(LifeInsightPeriod.daily);
  }

  /// Run monthly analysis (last 30 days). Produces projections and
  /// long-term patterns.
  Future<void> runMonthlyAnalysis() async {
    await _runAnalysis(LifeInsightPeriod.monthly);
  }

  /// Run all three analysis periods. Called by the periodic scheduler.
  Future<void> runFullAnalysis() async {
    await runDailyAnalysis();
    await runWeeklyAnalysis();
    await runMonthlyAnalysis();

    // After analysis, check for pact signals
    try {
      if (GrowthPactService.isInitialized) {
        final created =
            await GrowthPactService.instance.createEmergingPactsFromSignals();
        if (created.isNotEmpty) {
          _logger.info('LifeInsight: created ${created.length} emerging pacts');
        }
      }
    } catch (e) {
      _logger.warning('LifeInsight: pact signal consumption failed: $e');
    }

    // Extract rhythm signals from recent chat → user_rhythms
    await _extractRhythmSignals();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Internal
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _runAnalysis(LifeInsightPeriod period,
      {bool force = false}) async {
    if (!LifeInsightService.isInitialized) {
      _logger.warning('LifeInsight: service not initialized, skipping');
      return;
    }

    // Rate-limit: don't run the same period more than once per _minInterval
    if (!force && !await _shouldRun(period)) {
      _logger.info('LifeInsight: $period analysis rate-limited, skipping');
      return;
    }

    final now = DateTime.now();

    // Load LLM resources — uses lifeInsightAgent config ("记忆整理" category).
    // Falls back to recordOrganizerAgent config if lifeInsightAgent is not
    // configured (shares the same "记忆整理" model category).
    ({LLMClient client, ModelConfig modelConfig}) resources;
    try {
      resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.lifeInsightAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
    } catch (_) {
      resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
    }

    _logger.info('LifeInsight: starting $period analysis');

    try {
      const agent = LifeInsightAgent();
      final batch = await agent.analyze(
        client: resources.client,
        modelConfig: resources.modelConfig,
        db: _db,
        userId: await UserStorage.getUserId() ?? '',
        now: now,
        period: period,
      );

      _logger.info('LifeInsight: $period analysis produced '
          '${batch.insights.length} insights');

      // Persist each insight
      final service = LifeInsightService.instance;
      for (final insight in batch.insights) {
        // Calculate period boundaries if LLM didn't provide them
        final (periodStart, periodEnd) = _periodBounds(period, now);

        await service.upsertInsight(
          domain: insight.domain,
          insightType: insight.insightType,
          period: insight.period,
          periodStart: insight.periodStart > 0
              ? insight.periodStart
              : periodStart,
          periodEnd: insight.periodEnd > 0 ? insight.periodEnd : periodEnd,
          narrative: insight.narrative,
          dataPoints: insight.dataPoints,
          confidence: insight.confidence,
          pactSignal: insight.pactSignal,
        );
      }

      await _markRunComplete(period);
    } catch (e, stack) {
      _logger.warning('LifeInsight: $period analysis failed', e, stack);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Rate limiting via KvStore
  // ──────────────────────────────────────────────────────────────────────

  Future<bool> _shouldRun(LifeInsightPeriod period) async {
    final key = 'life_insight_last_run_${period.name}';
    final row = await (_db.select(_db.kvStore)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (row == null || row.value == null) return true;
    final lastRun = int.tryParse(row.value!);
    if (lastRun == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastRun;
    return elapsed >= _minInterval.inMilliseconds;
  }

  Future<void> _markRunComplete(LifeInsightPeriod period) async {
    final key = 'life_insight_last_run_${period.name}';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: key,
            bucket: const Value('life_insight'),
            value: Value(now.toString()),
            updatedAt: Value(now),
          ),
        );
  }

  (int, int) _periodBounds(LifeInsightPeriod period, DateTime now) {
    switch (period) {
      case LifeInsightPeriod.daily:
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
      case LifeInsightPeriod.weekly:
        final end = now;
        final start = now.subtract(const Duration(days: 7));
        return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
      case LifeInsightPeriod.monthly:
        final end = now;
        final start = now.subtract(const Duration(days: 30));
        return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Rhythm signal extraction
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _extractRhythmSignals() async {
    if (!UserRhythmService.isInitialized) return;

    // Rate-limit: rhythm extraction runs at most once per 6 hours
    const rhythmKey = 'life_insight_last_rhythm_extraction';
    final row = await (_db.select(_db.kvStore)
          ..where((t) => t.key.equals(rhythmKey)))
        .getSingleOrNull();
    if (row?.value != null) {
      final lastRun = int.tryParse(row!.value!);
      if (lastRun != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastRun;
        if (elapsed < const Duration(hours: 6).inMilliseconds) {
          _logger.info('LifeInsight: rhythm extraction rate-limited, skipping');
          return;
        }
      }
    }

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;

      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (character == null) return;

      ({LLMClient client, ModelConfig modelConfig}) resources;
      try {
        resources = await UserStorage.getAgentLLMResources(
          AgentDefinitions.lifeInsightAgent,
          defaultClientKey: LLMConfig.defaultClientKey,
        );
      } catch (_) {
        resources = await UserStorage.getAgentLLMResources(
          AgentDefinitions.recordOrganizerAgent,
          defaultClientKey: LLMConfig.defaultClientKey,
        );
      }

      const extractor = RhythmSignalExtractor();
      final created = await extractor.extractAndPersist(
        client: resources.client,
        modelConfig: resources.modelConfig,
        db: _db,
        characterId: character.id,
      );

      if (created > 0) {
        _logger.info('LifeInsight: extracted $created new rhythm(s) from chat');
      }

      // Mark completion
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _db.into(_db.kvStore).insertOnConflictUpdate(
            KvStoreCompanion.insert(
              key: rhythmKey,
              bucket: const Value('life_insight'),
              value: Value(now.toString()),
              updatedAt: Value(now),
            ),
          );
    } catch (e, stack) {
      _logger.warning('LifeInsight: rhythm extraction failed', e, stack);
    }
  }
}