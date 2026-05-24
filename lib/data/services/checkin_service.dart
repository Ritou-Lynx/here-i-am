import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Stochastic checkin pulse generator.
///
/// Registers a WorkManager periodic task that randomly enqueues checkin triggers
/// into [SystemMessageQueue]. The AI agent processes them in foreground turns.
class CheckinService {
  CheckinService._();
  static final CheckinService instance = CheckinService._();

  final _logger = getLogger('CheckinService');
  final _uuid = const Uuid();
  final _rand = Random();

  // KvStore bucket for config
  static const _bucket = 'checkin';
  static const _keyEnabled = 'enabled';
  static const _keyMinMin = 'min_interval_minutes';
  static const _keyMaxMin = 'max_interval_minutes';

  static const int defaultMinIntervalMinutes = 3;
  static const int defaultMaxIntervalMinutes = 60;

  /// WorkManager task name — public so [callbackDispatcher] can route.
  static const String checkinTaskName = 'stochasticCheckinPulse';

  AppDatabase get _db => AppDatabase.instance;

  // ---------------------------------------------------------------------------
  // Config (backed by KvStore)
  // ---------------------------------------------------------------------------

  Future<bool> isEnabled() async {
    if (!AppDatabase.isInitialized) return false;
    final row = await _db.kvStoreLookup(key: _keyEnabled, bucket: _bucket);
    if (row == null) return true; // Default: enabled unless explicitly turned off
    return row.value == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
      KvStoreCompanion.insert(
        key: _keyEnabled,
        bucket: const Value(_bucket),
        value: Value(enabled.toString()),
        updatedAt: Value(now),
      ),
    );
  }

  Future<int> getMinIntervalMinutes() async {
    final row = await _db.kvStoreLookup(key: _keyMinMin, bucket: _bucket);
    final v = int.tryParse(row?.value ?? '');
    return (v != null && v > 0) ? v : defaultMinIntervalMinutes;
  }

  Future<int> getMaxIntervalMinutes() async {
    final row = await _db.kvStoreLookup(key: _keyMaxMin, bucket: _bucket);
    final v = int.tryParse(row?.value ?? '');
    return (v != null && v > 0) ? v : defaultMaxIntervalMinutes;
  }

  Future<void> setInterval(int min, int max) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final entry in [
      (_keyMinMin, min.toString()),
      (_keyMaxMin, max.toString()),
    ]) {
      await _db.into(_db.kvStore).insertOnConflictUpdate(
        KvStoreCompanion.insert(
          key: entry.$1,
          bucket: const Value(_bucket),
          value: Value(entry.$2),
          updatedAt: Value(now),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // WorkManager
  // ---------------------------------------------------------------------------

  Future<void> ensureCheckinTaskRegistered() async {
    try {
      await Workmanager().registerPeriodicTask(
        checkinTaskName,
        checkinTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
      _logger.info('Checkin pulse task registered');
    } catch (e) {
      _logger.severe('Failed to register checkin task: $e');
    }
  }

  /// Schedules a one-off WorkManager task for testing.
  /// Fires after [delay] (default 1 min) in a real background isolate,
  /// runs the same callbackDispatcher path as the periodic pulse.
  Future<void> scheduleTestRun({
    Duration delay = const Duration(minutes: 1),
  }) async {
    final uniqueName = 'testCheckin_${DateTime.now().millisecondsSinceEpoch}';
    await Workmanager().registerOneOffTask(
      uniqueName,
      checkinTaskName, // same task name → same callbackDispatcher branch
      initialDelay: delay,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    _logger.info('Test checkin scheduled in ${delay.inSeconds}s ($uniqueName)');
  }

  /// Schedules a one-off AlarmManager wake-up that bypasses Doze.
  /// Uses [setExactAndAllowWhileIdle] under the hood (via allowWhileIdle=true),
  /// so the alarm fires at the requested time even when the device is dozing.
  /// Only meaningful on Android.
  Future<void> scheduleAlarmTestRun({
    Duration delay = const Duration(minutes: 1),
  }) async {
    if (!Platform.isAndroid) {
      _logger.warning('AlarmManager only available on Android');
      return;
    }
    final fireAt = DateTime.now().add(delay);
    // Use seconds-since-epoch as alarm id (truncated to int32 range)
    final alarmId = (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0x7fffffff;
    await AndroidAlarmManager.oneShotAt(
      fireAt,
      alarmId,
      alarmCheckinCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: false,
    );
    _logger.info(
        'Alarm checkin scheduled at $fireAt (alarmId=$alarmId, in ${delay.inSeconds}s)');
  }

  /// Cancels the checkin WorkManager task.
  Future<void> cancelCheckinTask() async {
    try {
      await Workmanager().cancelByUniqueName(checkinTaskName);
      _logger.info('Checkin pulse task cancelled');
    } catch (e) {
      _logger.warning('Failed to cancel checkin task: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Pulse logic (called from WorkManager callback or direct trigger)
  // ---------------------------------------------------------------------------

  /// Decides whether to enqueue a checkin trigger.
  /// Returns true if a new checkin was enqueued.
  Future<bool> maybeEnqueueCheckin() async {
    if (!AppDatabase.isInitialized) {
      _logger.warning('Database not initialized, skipping pulse');
      return false;
    }

    // Turn gate: skip if a pending system message already exists
    final pendingCount = await (_db.selectOnly(_db.systemMessageQueue)
          ..addColumns([_db.systemMessageQueue.id.count()])
          ..where(_db.systemMessageQueue.status.equals('pending')))
        .map((r) => r.read<int>(_db.systemMessageQueue.id.count()))
        .getSingleOrNull();

    if (pendingCount != null && pendingCount > 0) {
      _logger.info('Turn gate: pending=$pendingCount, skipping pulse');
      return false;
    }

    final minMin = await getMinIntervalMinutes();
    final maxMin = await getMaxIntervalMinutes();
    final delayMinutes = minMin + _rand.nextInt(maxMin - minMin + 1);
    _logger.info('Checkin pulse: next natural delay would be ~${delayMinutes}m');

    final now = DateTime.now();
    await _db.into(_db.systemMessageQueue).insert(
      SystemMessageQueueCompanion.insert(
        id: _uuid.v4(),
        triggerType: 'checkin',
        body: _buildCheckinText(),
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
        scheduledFor: const Value(null),
        context: const Value(null),
        processedAt: const Value(null),
      ),
    );

    _logger.info('Checkin trigger enqueued');
    return true;
  }

  String _buildCheckinText() {
    final hour = DateTime.now().hour;
    final timeOfDay = hour < 6
        ? 'late night'
        : hour < 12
            ? 'morning'
            : hour < 14
                ? 'noon'
                : hour < 18
                    ? 'afternoon'
                    : hour < 22
                        ? 'evening'
                        : 'night';

    return 'Memex agent wakes up — $timeOfDay check-in. '
        'Review recent context and decide: speak, act, or stay silent.';
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns true if there is any pending work — an unprocessed checkin trigger
  /// OR a reminder that is due. Used by the background callback to decide
  /// whether to run the agent even when no new checkin was enqueued.
  Future<bool> hasPendingWork() async {
    if (!AppDatabase.isInitialized) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = await (_db.select(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              (t.triggerType.equals('checkin') |
                  (t.triggerType.equals('reminder') &
                      t.scheduledFor.isSmallerOrEqualValue(now)))))
        .get();
    _logger.info('hasPendingWork: ${rows.length} row(s)');
    return rows.isNotEmpty;
  }

  /// Returns true if there are reminders that are due right now.
  Future<bool> hasDueReminders() async {
    if (!AppDatabase.isInitialized) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final due = await (_db.select(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.triggerType.equals('reminder') &
              t.scheduledFor.isSmallerOrEqualValue(now)))
        .get();
    return due.isNotEmpty;
  }

  /// Drain all pending system messages (checkins and due reminders).
  Future<List<SystemMessageQueueData>> drainPending() async {
    if (!AppDatabase.isInitialized) {
      _logger.warning('drainPending: DB not initialized');
      return [];
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _logger.info('drainPending: now=$now, querying...');

    // Expire stale checkin triggers (older than 1 hour) before draining.
    // These are triggers that were never successfully processed and keep
    // recycling through loopDetection → recoverStuckProcessing → pending.
    final expireBefore = now - 3600; // 1 hour
    final expiredCount = await (_db.update(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.triggerType.equals('checkin') &
              t.createdAt.isSmallerOrEqualValue(expireBefore)))
        .write(const SystemMessageQueueCompanion(status: Value('failed')));
    if (expiredCount > 0) {
      _logger.warning('drainPending: expired $expiredCount stale checkin trigger(s)');
    }

    final query = _db.select(_db.systemMessageQueue)
      ..where((t) => t.status.equals('pending') &
          (t.triggerType.equals('checkin') |
              (t.triggerType.equals('reminder') &
                  t.scheduledFor.isSmallerOrEqualValue(now))));
    final results = await query.get();
    _logger.info('drainPending: ${results.length} results');
    for (final r in results) {
      _logger.info('drainPending: row id=${r.id} type=${r.triggerType} status=${r.status}');
    }
    return results;
  }

  /// Mark a system message with a new status.
  Future<void> markStatus(String id, String status) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final processedAt = status == 'done' ? now : null;
    await (_db.update(_db.systemMessageQueue)
          ..where((t) => t.id.equals(id)))
        .write(SystemMessageQueueCompanion(
      status: Value(status),
      processedAt: Value(processedAt),
    ));
  }

  /// Reset stuck 'processing' triggers back to 'pending', or expire them if
  /// they are too old to be worth retrying.
  ///
  /// Triggers older than 30 minutes are marked 'failed' to prevent stale
  /// checkin triggers from looping indefinitely through loopDetection.
  Future<void> recoverStuckProcessing() async {
    if (!AppDatabase.isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expireBefore = now - 1800; // 30 minutes

    final stuck = await (_db.select(_db.systemMessageQueue)
          ..where((t) => t.status.equals('processing')))
        .get();
    for (final row in stuck) {
      final isOld = row.createdAt < expireBefore;
      final newStatus = isOld ? 'failed' : 'pending';
      await markStatus(row.id, newStatus);
      if (isOld) {
        _logger.warning(
            'Expired stale trigger ${row.id} (age: ${(now - row.createdAt) ~/ 60}min)');
      } else {
        _logger.info('Recovered stuck trigger: ${row.id}');
      }
    }
  }
}

/// Convenience lookup helper for KvStore.
extension KvLookup on AppDatabase {
  Future<KvStoreData?> kvStoreLookup({
    required String key,
    String? bucket,
  }) async {
    var query = select(kvStore)..where((kv) => kv.key.equals(key));
    if (bucket != null) {
      query = query..where((kv) => kv.bucket.equals(bucket));
    }
    return query.getSingleOrNull();
  }
}

/// Top-level callback fired by AndroidAlarmManager.
/// Runs in a separate isolate. Mirrors the checkin branch of
/// `callbackDispatcher` (health_service.dart) but is triggered by exact-time
/// AlarmManager wakeups that bypass Doze mode.
@pragma('vm:entry-point')
Future<void> alarmCheckinCallback(int alarmId) async {
  debugPrint('AlarmCheckin: fired alarmId=$alarmId (Isolate=${Isolate.current.debugName})');
  try {
    await setupLogger();
  } catch (_) {}

  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('current_user_id');
    if (userId == null) {
      debugPrint('AlarmCheckin: no userId, skipping');
      return;
    }
    if (!AppDatabase.isInitialized) {
      await AppDatabase.init(userId);
    }
    await UserStorage.initL10n();

    final enqueued = await CheckinService.instance.maybeEnqueueCheckin();
    final hasPendingWork = await CheckinService.instance.hasPendingWork();
    debugPrint(
        'AlarmCheckin: enqueued=$enqueued hasPendingWork=$hasPendingWork');
    if (!enqueued && !hasPendingWork) return;

    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    await NotificationService.instance.initialize();

    final character =
        await CharacterService.instance.getPrimaryCompanion(userId);
    if (character == null) {
      debugPrint('AlarmCheckin: no character, skipping');
      return;
    }
    debugPrint('AlarmCheckin: running agent as "${character.name}"');

    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.checkinAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    await CompanionAgent.runBackgroundCheckin(
      client: resources.client,
      modelConfig: resources.modelConfig,
      userId: userId,
      characterId: character.id,
    );
    debugPrint('AlarmCheckin: agent run complete');
  } catch (e, st) {
    debugPrint('AlarmCheckin: error: $e\n$st');
  }
}
