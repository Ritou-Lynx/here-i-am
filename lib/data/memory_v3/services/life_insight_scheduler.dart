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
  ///
  /// Also drives rhythm signal extraction (conversation → user_rhythms).
  /// This is the ONLY production trigger path for rhythm extraction —
  /// startup, event-driven (card recorded / COROS sync) and manual refresh
  /// all funnel through here, so routines like "我7点下班"/"周二有课" get
  /// picked up on every route. The extractor has its own 6h rate limit.
  Future<void> runWeeklyAnalysis() async {
    await _runAnalysis(LifeInsightPeriod.weekly);
    await _extractRhythmSignals();
  }

  /// Force a weekly analysis, bypassing the rate limit. Used by the manual
  /// refresh button in the observation panels so the user can pull fresh
  /// insights on demand. Rhythm extraction is forced too, so a user who
  /// just corrected the companion ("我说了我 7 点下班！") can trigger an
  /// immediate re-extraction from the panel.
  Future<void> forceRunWeeklyAnalysis() async {
    await _runAnalysis(LifeInsightPeriod.weekly, force: true);
    await _extractRhythmSignals(force: true);
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

    // Extract rhythm signals from recent chat → user_rhythms.
    // NOTE: runFullAnalysis has no periodic caller today; the production
    // trigger path is runWeeklyAnalysis(), which runs extraction itself.
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
    // Store MILLISECONDS — _shouldRun compares against
    // DateTime.now().millisecondsSinceEpoch. (Previously stored seconds,
    // which made the 30-min rate limit a no-op.)
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: key,
            bucket: const Value('life_insight'),
            value: Value(now.toString()),
            updatedAt: Value(now ~/ 1000),
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

  Future<void> _extractRhythmSignals({bool force = false}) async {
    if (!UserRhythmService.isInitialized) return;

    // Rate-limit: rhythm extraction runs at most once per 6 hours.
    // Values are MILLISECONDS since epoch (legacy devices may hold a
    // seconds value from a previous build — that parses as a tiny
    // millisecond timestamp, elapsed is huge, we just run once more).
    const rhythmKey = 'life_insight_last_rhythm_extraction';
    final row = await (_db.select(_db.kvStore)
          ..where((t) => t.key.equals(rhythmKey)))
        .getSingleOrNull();
    if (!force && row?.value != null) {
      final lastRun = int.tryParse(row!.value!);
      if (lastRun != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastRun;
        if (elapsed < const Duration(hours: 6).inMilliseconds) {
          _logger.info('LifeInsight: rhythm extraction rate-limited, skipping');
          return;
        }
      }
    }

    // First-ever run (no kv marker): read a much larger chat window so
    // routines stated weeks ago ("我每天7点下班", "周二五日晚上网课") are
    // backfilled, not just the last 100 messages.
    final isFirstRun = row?.value == null;
    final messageLimit = isFirstRun ? 500 : 100;

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
        messageLimit: messageLimit,
      );

      if (created > 0) {
        _logger.info('LifeInsight: extracted $created new rhythm(s) from chat');
      }

      // Mark completion (MILLISECONDS — see rate-limit check above).
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.into(_db.kvStore).insertOnConflictUpdate(
            KvStoreCompanion.insert(
              key: rhythmKey,
              bucket: const Value('life_insight'),
              value: Value(now.toString()),
              updatedAt: Value(now ~/ 1000),
            ),
          );
    } catch (e, stack) {
      _logger.warning('LifeInsight: rhythm extraction failed', e, stack);
    }
  }
}