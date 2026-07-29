/// Auto-scheduler for the Dreaming pipeline.
///
/// Provides two trigger paths:
/// - **Lightweight Tick** (non-LLM): foreground timer + post-message hook.
///   Entity promotion, stale-fragment resolution, fragment-count sync.
/// - **Daily Dreaming** (LLM): Workmanager background task. Fragment extraction
///   + episode consolidation, gated by device state and activity detection.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:workmanager/workmanager.dart';

final _logger = getLogger('memory_v3.DreamingSchedulerService');

class DreamingSchedulerService {
  DreamingSchedulerService({required AppDatabase db})
      : _orchestrator = DreamingOrchestratorServiceV3.instance;

  final DreamingOrchestratorServiceV3 _orchestrator;

  Timer? _foregroundTickTimer;

  static const _foregroundTickInterval = Duration(minutes: 5);
  static const _userActiveThreshold = Duration(minutes: 2);
  static const eventDrivenIdleDelay = Duration(minutes: 30);
  static const eventDrivenInitialChatThreshold = 20;
  static const eventDrivenChatThreshold = 100;
  static const minBatchInterval = Duration(minutes: 60);

  // Workmanager task name registered in health_service.dart.
  static const dailyBatchTaskName = 'dreaming_daily_batch';
  static const eventDrivenTaskUniqueName = 'dreaming_event_driven_batch';

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

  /// Debounce a real Dreaming batch after enough chat data has accumulated.
  ///
  /// Re-registering with [ExistingWorkPolicy.replace] moves the task to
  /// [eventDrivenIdleDelay] after the latest chat message. The periodic
  /// four-hour task remains only as a fallback if Android drops this work.
  static Future<void> scheduleEventDrivenBatchIfNeeded({
    required AppDatabase db,
    required String characterId,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      final initialDelay = await eventDrivenScheduleDelay(
        db: db,
        characterId: characterId,
      );
      if (initialDelay == null) return;

      await Workmanager().registerOneOffTask(
        eventDrivenTaskUniqueName,
        dailyBatchTaskName,
        initialDelay: initialDelay,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: true,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 15),
      );
      _logger.info(
        'Scheduled event-driven Dreaming batch in '
        '${initialDelay.inMinutes} minute(s) ($characterId)',
      );
    } catch (e, stack) {
      _logger.warning(
          'Failed to schedule event-driven Dreaming batch', e, stack);
    }
  }

  /// Schedule existing backlog on startup, without requiring another message.
  static Future<void> scheduleExistingBacklog(AppDatabase db) async {
    final latest = await (db.select(db.personaChatMessages)
          ..where((t) => t.messageType.equals('chat'))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timestamp),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (latest == null) return;
    await scheduleEventDrivenBatchIfNeeded(
      db: db,
      characterId: latest.characterId,
    );
  }

  /// Exposed for regression tests and Lab diagnostics. This decides whether
  /// chat activity should create a one-off task; it does not contact Android.
  static Future<bool> shouldScheduleEventDrivenBatch({
    required AppDatabase db,
    required String characterId,
    DateTime? now,
  }) async {
    return await eventDrivenScheduleDelay(
          db: db,
          characterId: characterId,
          now: now,
        ) !=
        null;
  }

  /// Return the delay for a one-off batch, or null when there is not yet enough
  /// first-run data. Sparse post-batch messages are scheduled for the future so
  /// they cannot fall through to the four-hour fallback merely because the
  /// 60-minute interval had not elapsed at insert time.
  static Future<Duration?> eventDrivenScheduleDelay({
    required AppDatabase db,
    required String characterId,
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final snapshot = await _loadBatchTriggerSnapshot(
      db,
      characterId,
      now: currentTime,
    );
    if (snapshot.pendingChatCount == 0) return null;
    if (snapshot.lastRunTime == null) {
      if (snapshot.pendingChatCount < eventDrivenInitialChatThreshold) {
        return null;
      }
    }

    final chatAge = snapshot.latestChatTime == null
        ? Duration.zero
        : currentTime.difference(snapshot.latestChatTime!);
    final idleRemaining = _remaining(eventDrivenIdleDelay, chatAge);
    final intervalRemaining = snapshot.lastRunTime != null &&
            snapshot.pendingChatCount < eventDrivenChatThreshold
        ? _remaining(minBatchInterval, snapshot.elapsedSinceLastRun)
        : Duration.zero;
    return idleRemaining >= intervalRemaining
        ? idleRemaining
        : intervalRemaining;
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

    // 1. Data-driven check: enough time passed + sufficient new messages?
    if (!forceRun && !await _shouldRunBatch(db, characterId)) {
      _logger.info(
          'Daily batch: insufficient time or messages since last batch, deferring');
      return false;
    }

    // 2. Is user actively chatting?
    if (!forceRun && await _isUserActive(db, characterId)) {
      _logger.info('Daily batch: user active, deferring');
      return false;
    }

    // 3. Device-state gate (best-effort; Workmanager constraints are the
    //    primary gate, this is the secondary code-level check).
    //    We skip the full charging/wifi check in the background isolate
    //    because we don't have battery_plus or connectivity_plus. Instead
    //    we rely on Workmanager's constraint system + the idle-duration
    //    check based on the latest real chat message.
    if (!forceRun && !await _hasSufficientIdleTime(db, characterId)) {
      _logger.info('Daily batch: insufficient idle time, deferring');
      return false;
    }

    // 4. Load LLM resources. Both fragment extraction and episode
    //    consolidation are memory-organization tasks and share the same
    //    record_organizer_agent model config. Episode consolidation used to
    //    piggyback on companionAgent for historical reasons, but that model
    //    is tuned for chat (with NSFW/TTS context) and may enforce different
    //    content policies when run under the cold episode-consolidator prompt,
    //    causing refusals on intimate relationship memories. Keeping both
    //    stages under the same agent also means the user only has to verify
    //    one model accepts sensitive content, not two.
    final fragResources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.recordOrganizerAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    final epResources = fragResources;

    // 5. Run fragment extraction.
    try {
      final fragResult = await orchestrator.runDailyFragmentBatch(
        characterId: characterId,
        client: fragResources.client,
        modelConfig: fragResources.modelConfig,
      );

      if (fragResult.isEmpty && fragResult.processedMessageCount == 0) {
        // No new messages — but there may still be active fragments waiting
        // to be consolidated (e.g. after clearAllEpisodes). Check before
        // skipping episode consolidation.
        final activeFragmentCount = await (db.select(db.memoryFragments)
              ..where((t) => t.status.equals('active')))
            .get()
            .then((rows) => rows.length);
        if (activeFragmentCount == 0) {
          _logger.info('Daily batch: no new messages and no active fragments');
          await orchestrator.markDailyBatchComplete(characterId);
          return true;
        }
        _logger.info(
          'Daily batch: no new messages but $activeFragmentCount active '
          'fragment(s) pending consolidation — continuing to episode step',
        );
      }

      _logger.info(
        'Daily batch: extracted ${fragResult.fragmentIds.length} fragments '
        'from ${fragResult.processedMessageCount} messages',
      );
    } catch (e, stack) {
      // Fragment extraction failed, but runDailyFragmentBatch already advanced
      // the watermark past this batch (see method doc). Mark the batch as
      // complete so the next trigger respects the 60-min interval instead of
      // immediately re-firing. Episode consolidation still runs, because
      // previously-extracted active fragments may be waiting.
      _logger.warning('Daily batch: fragment extraction failed', e, stack);
      await orchestrator.markDailyBatchComplete(characterId);
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

    // 8. Deep Dreaming: saga weaving (threshold-gated, runs at most weekly).
    try {
      if (await orchestrator.shouldRunSagaWeaving()) {
        _logger.info('Daily batch: saga threshold met, running Deep Dreaming');
        final sagaResult = await orchestrator.runSagaWeaving(
          client: epResources.client,
          modelConfig: epResources.modelConfig,
          forceRun: true, // threshold already checked
        );
        _logger.info(
          'Daily batch: saga weaving done — '
          '${sagaResult.sagaIds.length} new, '
          '${sagaResult.updatedSagaIds.length} updated',
        );
      }
    } catch (e, stack) {
      _logger.warning('Daily batch: saga weaving failed', e, stack);
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

  /// A visible app is not necessarily an active conversation. Use the latest
  /// real chat message rather than the foreground heartbeat shared by check-in.
  static Future<bool> _isUserActive(
    AppDatabase db,
    String characterId,
  ) async {
    try {
      final age = await _latestChatAge(db, characterId);
      return age != null && age < _userActiveThreshold;
    } catch (e) {
      _logger.warning('_isUserActive check failed', e);
      return false; // safe default: don't skip on error
    }
  }

  /// Data-driven batch trigger: check if enough time has passed and new messages
  /// have accumulated since the last batch.
  /// Returns true if: (time since last batch >= 1 hour) OR (new messages >= 100)
  static Future<bool> _shouldRunBatch(
      AppDatabase db, String characterId) async {
    try {
      final snapshot = await _loadBatchTriggerSnapshot(db, characterId);

      // First run or no prior batch — always allow
      if (snapshot.lastRunTime == null) return true;

      // Check time since last batch
      if (snapshot.elapsedSinceLastRun >= minBatchInterval) return true;

      return snapshot.pendingChatCount >= eventDrivenChatThreshold;
    } catch (e) {
      _logger.warning('_shouldRunBatch check failed', e);
      return true; // allow on error
    }
  }

  static Future<bool> _hasSufficientIdleTime(
    AppDatabase db,
    String characterId,
  ) async {
    try {
      final age = await _latestChatAge(db, characterId);
      if (age == null) return true;
      return age >= eventDrivenIdleDelay;
    } catch (e) {
      _logger.warning('_hasSufficientIdleTime check failed', e);
      return true; // allow on error
    }
  }

  static Future<Duration?> _latestChatAge(
    AppDatabase db,
    String characterId,
  ) async {
    final latest = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) & t.messageType.equals('chat'))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timestamp),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (latest == null) return null;
    final age = DateTime.now().difference(latest.timestamp);
    return age.isNegative ? Duration.zero : age;
  }

  static Future<_BatchTriggerSnapshot> _loadBatchTriggerSnapshot(
    AppDatabase db,
    String characterId, {
    DateTime? now,
  }) async {
    final timeRow = await (db.select(db.kvStore)
          ..where((t) =>
              t.bucket.equals('memory_v3.dreaming') &
              t.key.equals('dreaming.batch.last_run_time.$characterId')))
        .getSingleOrNull();
    final watermarkRow = await (db.select(db.kvStore)
          ..where((t) =>
              t.bucket.equals('memory_v3.dreaming') &
              t.key.equals('dreaming.batch.last_watermark.$characterId')))
        .getSingleOrNull();

    final lastRunMillis = int.tryParse(timeRow?.value ?? '');
    final lastRunTime = lastRunMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastRunMillis);
    final lastWatermark = int.tryParse(watermarkRow?.value ?? '') ?? 0;
    final countExpression = db.personaChatMessages.id.count();
    final countRow = await (db.selectOnly(db.personaChatMessages)
          ..addColumns([countExpression])
          ..where(
            db.personaChatMessages.characterId.equals(characterId) &
                db.personaChatMessages.messageType.equals('chat') &
                db.personaChatMessages.id.isBiggerThanValue(lastWatermark),
          ))
        .getSingle();
    final pendingChatCount = countRow.read(countExpression) ?? 0;
    final latestChat = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) & t.messageType.equals('chat'))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timestamp),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    final currentTime = now ?? DateTime.now();

    return _BatchTriggerSnapshot(
      lastRunTime: lastRunTime,
      latestChatTime: latestChat?.timestamp,
      pendingChatCount: pendingChatCount,
      elapsedSinceLastRun: lastRunTime == null
          ? Duration.zero
          : currentTime.difference(lastRunTime),
    );
  }

  static Duration _remaining(Duration required, Duration elapsed) {
    if (elapsed >= required) return Duration.zero;
    if (elapsed.isNegative) return required;
    return required - elapsed;
  }
}

class _BatchTriggerSnapshot {
  const _BatchTriggerSnapshot({
    required this.lastRunTime,
    required this.latestChatTime,
    required this.pendingChatCount,
    required this.elapsedSinceLastRun,
  });

  final DateTime? lastRunTime;
  final DateTime? latestChatTime;
  final int pendingChatCount;
  final Duration elapsedSinceLastRun;
}
