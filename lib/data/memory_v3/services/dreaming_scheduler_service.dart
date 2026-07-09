/// Auto-scheduler for the Dreaming pipeline.
///
/// Provides two trigger paths:
/// - **Lightweight Tick** (non-LLM): foreground timer + post-message hook.
///   Entity promotion, stale-fragment resolution, fragment-count sync.
/// - **Daily Dreaming** (LLM): Workmanager background task. Fragment extraction
///   + episode consolidation, gated by device state and activity detection.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('memory_v3.DreamingSchedulerService');

class DreamingSchedulerService {
  DreamingSchedulerService({required AppDatabase db})
      : _orchestrator = DreamingOrchestratorServiceV3.instance;

  final DreamingOrchestratorServiceV3 _orchestrator;

  Timer? _foregroundTickTimer;

  static const _foregroundTickInterval = Duration(minutes: 5);
  static const _userActiveThreshold = Duration(minutes: 2);

  // Workmanager task name registered in health_service.dart.
  static const dailyBatchTaskName = 'dreaming_daily_batch';

  // ---------------------------------------------------------------------------
  // Foreground lifecycle
  // ---------------------------------------------------------------------------

  /// Run a one-off lightweight tick using only the database (no timer needed).
  /// Safe to call from any context — fire-and-forget by default.
  static Future<void> triggerLightweightTickStatic(AppDatabase db) async {
    try {
      final orchestrator = DreamingOrchestratorServiceV3.instance;
      await orchestrator.resolveStaleFragments('i');
    } catch (e, stack) {
      _logger.warning(
          'Lightweight tick: resolveStaleFragments failed', e, stack);
    }
    try {
      final orchestrator = DreamingOrchestratorServiceV3.instance;
      await orchestrator.syncEntityFragmentCounts();
    } catch (e, stack) {
      _logger.warning(
          'Lightweight tick: syncEntityFragmentCounts failed', e, stack);
    }
  }

  /// Start the periodic lightweight tick while the app is visible.
  void startForegroundTick() {
    stopForegroundTick();
    _foregroundTickTimer = Timer.periodic(_foregroundTickInterval, (_) {
      _doLightweightTick();
    });
    _logger.info(
        'Foreground tick started (${_foregroundTickInterval.inMinutes}min)');
  }

  /// Stop the periodic lightweight tick (e.g. app backgrounded).
  void stopForegroundTick() {
    _foregroundTickTimer?.cancel();
    _foregroundTickTimer = null;
  }

  /// Run a lightweight tick immediately. Fire-and-forget safe —
  /// all work is idempotent SQL, no LLM calls.
  Future<void> triggerLightweightTick() async {
    try {
      await _doLightweightTick();
    } catch (e, stack) {
      _logger.warning('triggerLightweightTick failed', e, stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Background entry point (called from Workmanager callbackDispatcher)
  // ---------------------------------------------------------------------------

  /// Run the daily dreaming batch from a background isolate.
  ///
  /// Returns true if work was performed, false if skipped (user active,
  /// already ran today, conditions not met, or LLM error).
  static Future<bool> runDailyDreamingFromBackground({
    required AppDatabase db,
    required String characterId,
    bool forceRun = false,
  }) async {
    final orchestrator = DreamingOrchestratorServiceV3.instance;

    // 1. Already ran today?
    if (!forceRun && await orchestrator.hasDailyBatchRunToday(characterId)) {
      _logger.info('Daily batch: already ran today, skipping');
      return false;
    }

    // 2. Is user actively chatting?
    if (!forceRun && await _isUserActive(db)) {
      _logger.info('Daily batch: user active, deferring');
      return false;
    }

    // 3. Device-state gate (best-effort; Workmanager constraints are the
    //    primary gate, this is the secondary code-level check).
    //    We skip the full charging/wifi check in the background isolate
    //    because we don't have battery_plus or connectivity_plus. Instead
    //    we rely on Workmanager's constraint system + the idle-duration
    //    check via KvStore heartbeat.
    if (!forceRun && !await _hasSufficientIdleTime(db)) {
      _logger.info('Daily batch: insufficient idle time, deferring');
      return false;
    }

    // 4. Load LLM resources (same pattern as the Lab screen).
    final fragResources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.recordOrganizerAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    final epResources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.companionAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );

    // 5. Run fragment extraction.
    try {
      final fragResult = await orchestrator.runDailyFragmentBatch(
        characterId: characterId,
        client: fragResources.client,
        modelConfig: fragResources.modelConfig,
      );

      if (fragResult.isEmpty && fragResult.processedMessageCount == 0) {
        _logger.info('Daily batch: no new messages to process');
        await orchestrator.markDailyBatchComplete(characterId);
        return true;
      }

      _logger.info(
        'Daily batch: extracted ${fragResult.fragmentIds.length} fragments '
        'from ${fragResult.processedMessageCount} messages',
      );
    } catch (e, stack) {
      _logger.warning('Daily batch: fragment extraction failed', e, stack);
      return false; // will retry on next Workmanager tick
    }

    // 6. Run episode consolidation.
    try {
      final epResult = await orchestrator.runEpisodeConsolidation(
        client: epResources.client,
        modelConfig: epResources.modelConfig,
      );

      _logger.info(
        'Daily batch: consolidated ${epResult.episodeIds.length} episodes '
        'for ${epResult.consolidatedEntities.length} entities',
      );
    } catch (e, stack) {
      _logger.warning(
        'Daily batch: episode consolidation failed (fragments already '
        'extracted, will retry consolidation next time)',
        e,
        stack,
      );
    }

    // 7. Post-batch lightweight tick for cleanup.
    try {
      await orchestrator.resolveStaleFragments(characterId);
      await orchestrator.syncEntityFragmentCounts();
    } catch (e, stack) {
      _logger.warning('Daily batch: post-batch cleanup failed', e, stack);
    }

    await orchestrator.markDailyBatchComplete(characterId);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _doLightweightTick() async {
    try {
      await _orchestrator.resolveStaleFragments('i');
    } catch (e, stack) {
      _logger.warning(
          'Lightweight tick: resolveStaleFragments failed', e, stack);
    }

    try {
      await _orchestrator.syncEntityFragmentCounts();
    } catch (e, stack) {
      _logger.warning(
          'Lightweight tick: syncEntityFragmentCounts failed', e, stack);
    }
  }

  /// Check KvStore for a recent foreground heartbeat.
  static Future<bool> _isUserActive(AppDatabase db) async {
    try {
      final row = await (db.select(db.kvStore)
            ..where((t) =>
                t.bucket.equals('memory_v3.dreaming') &
                t.key.equals('last_user_active')))
          .getSingleOrNull();
      if (row == null || row.value == null) return false;

      final lastActive = int.tryParse(row.value!);
      if (lastActive == null) return false;

      final elapsed = DateTime.now().millisecondsSinceEpoch - lastActive;
      return elapsed < _userActiveThreshold.inMilliseconds;
    } catch (e) {
      _logger.warning('_isUserActive check failed', e);
      return false; // safe default: don't skip on error
    }
  }

  /// Best-effort idle check via the last_user_active KvStore key.
  static Future<bool> _hasSufficientIdleTime(AppDatabase db) async {
    try {
      final row = await (db.select(db.kvStore)
            ..where((t) =>
                t.bucket.equals('memory_v3.dreaming') &
                t.key.equals('last_user_active')))
          .getSingleOrNull();
      if (row == null || row.value == null) {
        // No heartbeat recorded — first run, consider idle enough.
        return true;
      }

      final lastActive = int.tryParse(row.value!);
      if (lastActive == null) return true;

      final idleMinutes =
          (DateTime.now().millisecondsSinceEpoch - lastActive) / (60 * 1000);
      // Gate: idle > 30 min OR in preferred night window with idle > 2 hours.
      if (idleMinutes >= 30) return true;

      final hour = DateTime.now().hour;
      if (hour >= 22 || hour < 6) {
        return idleMinutes >= 120;
      }

      return false;
    } catch (e) {
      _logger.warning('_hasSufficientIdleTime check failed', e);
      return true; // allow on error
    }
  }
}
