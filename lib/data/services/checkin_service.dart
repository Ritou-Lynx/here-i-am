import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/callkit_service.dart';
import 'package:memex/data/services/companion_foreground_task.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/morning_weather_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/data/services/sqlite_retry.dart';
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
  static const int _staleCheckinSeconds = 60 * 60;
  /// Non-call reminders expire after 15 minutes — a late "remember to X" is
  /// worse than silence.
  static const int _staleReminderSeconds = 15 * 60;
  /// Call reminders get a 2-hour window: the foreground service may be
  /// temporarily dead (Samsung battery management), and a scheduled call
  /// arriving 30 min late is still useful.
  static const int _staleCallReminderSeconds = 2 * 60 * 60;

  /// WorkManager task name — public so [callbackDispatcher] can route.
  static const String checkinTaskName = 'stochasticCheckinPulse';

  AppDatabase get _db => AppDatabase.instance;

  // ---------------------------------------------------------------------------
  // Config (backed by KvStore)
  // ---------------------------------------------------------------------------

  Future<bool> isEnabled() async {
    if (!AppDatabase.isInitialized) return false;
    final row = await _db.kvStoreLookup(key: _keyEnabled, bucket: _bucket);
    if (row == null) {
      return true; // Default: enabled unless explicitly turned off
    }
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
    if (!AppDatabase.isInitialized) return defaultMinIntervalMinutes;
    final row = await _db.kvStoreLookup(key: _keyMinMin, bucket: _bucket);
    final v = int.tryParse(row?.value ?? '');
    return (v != null && v > 0) ? v : defaultMinIntervalMinutes;
  }

  Future<int> getMaxIntervalMinutes() async {
    if (!AppDatabase.isInitialized) return defaultMaxIntervalMinutes;
    final row = await _db.kvStoreLookup(key: _keyMaxMin, bucket: _bucket);
    final v = int.tryParse(row?.value ?? '');
    return (v != null && v > 0) ? v : defaultMaxIntervalMinutes;
  }

  /// Returns true if the user sent any chat message after [sinceEpochSec].
  Future<bool> hasUserChatActivitySince(
      String characterId, int sinceEpochSec) async {
    if (!AppDatabase.isInitialized) return false;
    final since = DateTime.fromMillisecondsSinceEpoch(sinceEpochSec * 1000);
    final row = await (_db.select(_db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.isFromCharacter.equals(false) &
              t.timestamp.isBiggerThanValue(since))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
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
        // keep (not update): re-registering on every app launch with `update`
        // resets the period and forces an immediate run, which is what caused a
        // checkin to fire every time the app was opened.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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
    final alarmId =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0x7fffffff;
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

  /// Schedule an exact wake-up for a persisted reminder.
  ///
  /// The foreground service remains a fallback, but a user-requested future
  /// action should not wait for the next stochastic production alarm.
  Future<void> scheduleReminderAlarm({
    required String reminderId,
    required DateTime dueAt,
  }) async {
    if (!Platform.isAndroid) return;
    final alarmId = alarmIdForReminder(reminderId);
    try {
      await AndroidAlarmManager.oneShotAt(
        dueAt,
        alarmId,
        alarmCheckinCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        alarmClock: true,
        rescheduleOnReboot: true,
      );
      _logger.info(
        'Reminder alarm scheduled at $dueAt '
        '(reminderId=$reminderId, alarmId=$alarmId)',
      );
    } catch (e) {
      // Keep the DB reminder: the persistent foreground loop can still pick it
      // up within its next tick if exact-alarm registration is unavailable.
      _logger.warning(
        'Failed to schedule exact reminder alarm for $reminderId: $e',
      );
    }
  }

  int alarmIdForReminder(String reminderId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in reminderId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 0x40000000 | (hash & 0x3fffffff);
  }

  /// Stable alarm ID for the production recurring checkin alarm.
  static const int _productionAlarmId = 0xC4EC1;

  /// Schedule the next production checkin alarm using AndroidAlarmManager.
  ///
  /// Uses a random delay within the configured [min, max] interval window so the
  /// alarm fires even when the device is in Doze mode (allowWhileIdle=true).
  /// The alarm reschedules itself after each fire via [alarmCheckinCallback],
  /// creating a self-sustaining wake-up chain that does not rely on WorkManager.
  Future<void> scheduleProductionAlarm() async {
    if (!Platform.isAndroid) return;
    final minMin = await getMinIntervalMinutes();
    final maxMin = await getMaxIntervalMinutes();
    final delayMin = minMin + _rand.nextInt(maxMin - minMin + 1);
    final fireAt = DateTime.now().add(Duration(minutes: delayMin));
    await AndroidAlarmManager.oneShotAt(
      fireAt,
      _productionAlarmId,
      alarmCheckinCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
    _logger.info('Production alarm scheduled at $fireAt (in ${delayMin}m)');
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
  /// SharedPreferences key for the foreground heartbeat timestamp (epoch sec).
  /// The UI isolate refreshes this while the app is visible; background checkin
  /// isolates read it to detect that the user is actively using the app.
  static const String _keyForegroundHeartbeat =
      'checkin_foreground_heartbeat_ts';

  /// KvStore key for the foreground heartbeat — cross-isolate safe alternative
  /// to SharedPreferences. Background isolates (foreground service, alarm
  /// callback) read this because SharedPreferences cache is unreliable across
  /// isolates.
  static const String _keyFgHeartbeatKv = 'fg_heartbeat_ts';

  /// How long after the last foreground heartbeat we still consider the app
  /// "in use". Must exceed the UI heartbeat interval (60s) with margin.
  static const int _foregroundGraceSeconds = 90;

  /// Called by the UI isolate while the app is foregrounded. Writes a heartbeat
  /// timestamp so background checkins know to stay silent.
  ///
  /// Writes to BOTH SharedPreferences and KvStore so the heartbeat is visible
  /// from background isolates where SharedPreferences cache may be stale.
  Future<void> markForeground() async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // SharedPreferences (fast path for main-isolate reads)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyForegroundHeartbeat, ts);
    // KvStore (cross-isolate safe — background isolates read this)
    if (AppDatabase.isInitialized) {
      try {
        await _db.into(_db.kvStore).insertOnConflictUpdate(
              KvStoreCompanion.insert(
                key: _keyFgHeartbeatKv,
                bucket: const Value(_bucket),
                value: Value(ts.toString()),
                updatedAt: Value(ts),
              ),
            );
        // Also write a dreaming-level active-user heartbeat so the
        // Dreaming daily batch can skip when the user is actively chatting.
        await _db.into(_db.kvStore).insertOnConflictUpdate(
              KvStoreCompanion.insert(
                key: 'last_user_active',
                bucket: const Value('memory_v3.dreaming'),
                value: Value(DateTime.now().millisecondsSinceEpoch.toString()),
                updatedAt: Value(ts),
              ),
            );
      } catch (_) {
        // Never throw from a heartbeat — it's best-effort.
      }
    }
  }

  /// Called when the app is backgrounded — expires the heartbeat immediately so
  /// background checkins can resume without waiting out the grace window.
  Future<void> markBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyForegroundHeartbeat, 0);
    if (AppDatabase.isInitialized) {
      try {
        await _db.into(_db.kvStore).insertOnConflictUpdate(
              KvStoreCompanion.insert(
                key: _keyFgHeartbeatKv,
                bucket: const Value(_bucket),
                value: const Value('0'),
                updatedAt:
                    Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
              ),
            );
      } catch (_) {
        // Best-effort.
      }
    }
  }

  /// Whether the app appears to be in the foreground right now, based on the
  /// heartbeat timestamp. Survives app kills (a stale timestamp simply expires).
  ///
  /// Reads from KvStore (SQLite) first so background isolates get the true
  /// value. Falls back to SharedPreferences for compatibility.
  Future<bool> isAppInForeground() async {
    // Primary path: read from DB (cross-isolate safe).
    if (AppDatabase.isInitialized) {
      try {
        final row = await _db.kvStoreLookup(
            key: _keyFgHeartbeatKv, bucket: _bucket);
        final dbTs = int.tryParse(row?.value ?? '');
        if (dbTs != null) {
          if (dbTs <= 0) return false;
          final ageSec =
              (DateTime.now().millisecondsSinceEpoch ~/ 1000) - dbTs;
          return ageSec >= 0 && ageSec < _foregroundGraceSeconds;
        }
      } catch (_) {
        // Fall through to SharedPreferences.
      }
    }
    // Fallback: SharedPreferences (only reliable in the main isolate).
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_keyForegroundHeartbeat) ?? 0;
    if (ts <= 0) return false;
    final ageSec = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - ts;
    return ageSec >= 0 && ageSec < _foregroundGraceSeconds;
  }

  Future<bool> maybeEnqueueCheckin() async {
    if (!AppDatabase.isInitialized) {
      _logger.warning('Database not initialized, skipping pulse');
      return false;
    }

    // Clear any stale 'processing' rows before the turn gate so a crashed/killed
    // agent run can't permanently block future checkins.
    await recoverStuckProcessing();
    await expireStalePendingTriggers();

    // Foreground gate: never proactively interrupt while the user is actively
    // using the app — the whole point of a proactive push is to reach them when
    // they're away. (Stuck-row recovery above still runs, which is desirable.)
    if (await isAppInForeground()) {
      _logger.info('App in foreground, skipping proactive checkin');
      return false;
    }

    // Turn gate: skip only when there is work that should be handled now.
    // Future reminders must not block ordinary check-in pulses for hours/days.
    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final activeCount = await (_db.selectOnly(_db.systemMessageQueue)
          ..addColumns([_db.systemMessageQueue.id.count()])
          ..where(
            _db.systemMessageQueue.status.equals('processing') |
                (_db.systemMessageQueue.status.equals('pending') &
                    (_db.systemMessageQueue.triggerType.equals('checkin') |
                        (_db.systemMessageQueue.triggerType.equals('reminder') &
                            _db.systemMessageQueue.scheduledFor
                                .isSmallerOrEqualValue(nowSec)))),
          ))
        .map((r) => r.read<int>(_db.systemMessageQueue.id.count()))
        .getSingleOrNull();

    if (activeCount != null && activeCount > 0) {
      _logger.info('Turn gate: active=$activeCount, skipping pulse');
      return false;
    }

    final minMin = await getMinIntervalMinutes();
    final maxMin = await getMaxIntervalMinutes();
    final delayMinutes = minMin + _rand.nextInt(maxMin - minMin + 1);
    _logger
        .info('Checkin pulse: next natural delay would be ~${delayMinutes}m');

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

  // KV key for the foreground-service heartbeat interval gate.
  static const _keyNextCheckinTs = 'next_checkin_ts';

  /// Foreground-service heartbeat gate. The persistent foreground service ticks
  /// frequently (e.g. every 60s); this returns true only when enough time has
  /// elapsed since the last checkin — a random interval within [min, max].
  /// Reschedules the next target each time it fires, so checkin cadence stays
  /// random/natural rather than firing on every tick.
  Future<bool> dueForCheckin() async {
    if (!AppDatabase.isInitialized) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final row =
        await _db.kvStoreLookup(key: _keyNextCheckinTs, bucket: _bucket);
    final next = int.tryParse(row?.value ?? '');
    if (next == null) {
      // First tick after install/launch — arm the next target, don't fire now.
      await _scheduleNextCheckinTs(nowSec);
      return false;
    }
    if (nowSec >= next) {
      await _scheduleNextCheckinTs(nowSec);
      return true;
    }
    return false;
  }

  /// Test helper: force the next foreground-service tick to be "due" so a
  /// checkin runs within one tick interval (instead of waiting the random gap).
  Future<void> forceCheckinDueNow() async {
    if (!AppDatabase.isInitialized) return;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _keyNextCheckinTs,
            bucket: const Value(_bucket),
            value: const Value('0'), // 0 ≤ now → due on next tick
            updatedAt: Value(nowSec),
          ),
        );
  }

  Future<void> _scheduleNextCheckinTs(int nowSec) async {
    final minMin = await getMinIntervalMinutes();
    final maxMin = await getMaxIntervalMinutes();
    final span = (maxMin - minMin) < 0 ? 0 : (maxMin - minMin);
    final delayMin = minMin + (span == 0 ? 0 : _rand.nextInt(span + 1));
    final next = nowSec + delayMin * 60;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _keyNextCheckinTs,
            bucket: const Value(_bucket),
            value: Value(next.toString()),
            updatedAt: Value(nowSec),
          ),
        );
    _logger.info('Next checkin target in ${delayMin}m');
  }

  String _buildCheckinText() {
    final now = DateTime.now();
    final hour = now.hour;
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

  /// Fail pending work that is too late to send naturally.
  ///
  /// A missed reminder must not surface many hours later with stale wording
  /// such as "Current time: 23:40". Explicit commitments are still handled
  /// promptly by the foreground-service fallback, but after the grace window
  /// silence is safer than a misleading late interruption.
  Future<int> expireStalePendingTriggers({int? nowEpochSec}) async {
    if (!AppDatabase.isInitialized) return 0;
    final now = nowEpochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var expired = 0;

    expired += await (_db.update(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.triggerType.equals('checkin') &
              t.createdAt.isSmallerOrEqualValue(now - _staleCheckinSeconds)))
        .write(const SystemMessageQueueCompanion(status: Value('failed')));

    // Reminders: call reminders get a 2-hour window (the foreground service
    // may be temporarily dead); non-call reminders expire after 15 minutes.
    // Drift has no NOT LIKE, so we first collect call-reminder IDs.
    final callReminderIds = (await (_db.select(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.triggerType.equals('reminder') &
              t.context.like('%"action":"call"%')))
        .get())
        .map((r) => r.id)
        .toList();

    // Non-call reminders: short expiry (15 min).
    expired += await (_db.update(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.triggerType.equals('reminder') &
              t.scheduledFor
                  .isSmallerOrEqualValue(now - _staleReminderSeconds) &
              (callReminderIds.isEmpty
                  ? const Constant(true)
                  : t.id.isNotIn(callReminderIds))))
        .write(const SystemMessageQueueCompanion(status: Value('failed')));

    // Call reminders: longer expiry (2 h).
    if (callReminderIds.isNotEmpty) {
      expired += await (_db.update(_db.systemMessageQueue)
            ..where((t) =>
                t.status.equals('pending') &
                t.triggerType.equals('reminder') &
                t.scheduledFor.isSmallerOrEqualValue(
                    now - _staleCallReminderSeconds) &
                t.id.isIn(callReminderIds)))
          .write(const SystemMessageQueueCompanion(status: Value('failed')));
    }

    if (expired > 0) {
      _logger.warning('Expired $expired stale pending system trigger(s)');
    }
    return expired;
  }

  /// Returns true if there is any pending work — an unprocessed checkin trigger
  /// OR a reminder that is due. Used by the background callback to decide
  /// whether to run the agent even when no new checkin was enqueued.
  Future<bool> hasPendingWork() async {
    return retryOnSqliteLocked(() async {
      if (!AppDatabase.isInitialized) return false;
      await recoverStuckProcessing();
      await expireStalePendingTriggers();
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
    });
  }

  /// Returns true if there are reminders that are due right now.
  Future<bool> hasDueReminders() async {
    return retryOnSqliteLocked(() async {
      if (!AppDatabase.isInitialized) return false;
      await recoverStuckProcessing();
      await expireStalePendingTriggers();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final due = await (_db.select(_db.systemMessageQueue)
            ..where((t) =>
                t.status.equals('pending') &
                t.triggerType.equals('reminder') &
                t.scheduledFor.isSmallerOrEqualValue(now)))
          .get();
      return due.isNotEmpty;
    });
  }

  Future<List<SystemMessageQueueData>> claimDueCallReminders() async {
    return retryOnSqliteLocked(() async {
      if (!AppDatabase.isInitialized) return [];
      await recoverStuckProcessing();
      await expireStalePendingTriggers();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return _db.transaction(() async {
        final rows = await (_db.select(_db.systemMessageQueue)
              ..where((t) =>
                  t.status.equals('pending') &
                  t.triggerType.equals('reminder') &
                  t.scheduledFor.isSmallerOrEqualValue(now) &
                  t.context.like('%"action":"call"%'))
              ..orderBy([(t) => OrderingTerm.asc(t.scheduledFor)]))
            .get();
        if (rows.isEmpty) return rows;
        final ids = rows.map((row) => row.id).toList(growable: false);
        await (_db.update(_db.systemMessageQueue)..where((t) => t.id.isIn(ids)))
            .write(const SystemMessageQueueCompanion(
          status: Value('processing'),
        ));
        return rows;
      });
    });
  }

  /// Drain all pending system messages (checkins and due reminders).
  Future<List<SystemMessageQueueData>> drainPending() async {
    if (!AppDatabase.isInitialized) {
      _logger.warning('drainPending: DB not initialized');
      return [];
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _logger.info('drainPending: now=$now, querying...');
    await recoverStuckProcessing();
    await expireStalePendingTriggers(nowEpochSec: now);

    final query = _db.select(_db.systemMessageQueue)
      ..where((t) =>
          t.status.equals('pending') &
          (t.triggerType.equals('checkin') |
              (t.triggerType.equals('reminder') &
                  t.scheduledFor.isSmallerOrEqualValue(now))));
    final results = await query.get();
    results.sort((a, b) {
      final aPriority = a.triggerType == 'reminder' ? 0 : 1;
      final bPriority = b.triggerType == 'reminder' ? 0 : 1;
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      return (a.scheduledFor ?? a.createdAt)
          .compareTo(b.scheduledFor ?? b.createdAt);
    });
    _logger.info('drainPending: ${results.length} results');
    for (final r in results) {
      _logger.info(
          'drainPending: row id=${r.id} type=${r.triggerType} status=${r.status}');
    }
    return results;
  }

  /// Mark a system message with a new status.
  Future<void> markStatus(String id, String status) async {
    await retryOnSqliteLocked(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final processedAt = status == 'done' ? now : null;
      await (_db.update(_db.systemMessageQueue)..where((t) => t.id.equals(id)))
          .write(SystemMessageQueueCompanion(
        status: Value(status),
        processedAt: Value(processedAt),
      ));
    });
  }

  /// Marks system messages currently being handled by an agent turn as done.
  ///
  /// Draining a checkin marks it as `processing` before the LLM sees it, so the
  /// completion tool must finish `processing` rows rather than querying pending
  /// rows again.
  Future<int> markProcessingDone() async {
    return retryOnSqliteLocked(() async {
      if (!AppDatabase.isInitialized) return 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return (_db.update(_db.systemMessageQueue)
            ..where((t) => t.status.equals('processing')))
          .write(SystemMessageQueueCompanion(
        status: const Value('done'),
        processedAt: Value(now),
      ));
    });
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
      final referenceTs = row.triggerType == 'reminder'
          ? row.scheduledFor ?? row.createdAt
          : row.createdAt;
      final isOld = referenceTs < expireBefore;
      final newStatus = isOld ? 'failed' : 'pending';
      await markStatus(row.id, newStatus);
      if (isOld) {
        _logger.warning(
            'Expired stale trigger ${row.id} (age: ${(now - referenceTs) ~/ 60}min)');
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
///
/// KEY FIX (2026-07): due call reminders are now handled DIRECTLY — the call
/// is queued and a notification fallback fires without waiting for the LLM
/// agent. CallKit display is attempted but degrades gracefully: this
/// background isolate has no Flutter engine, so CallKit usually fails;
/// the persistent foreground service (15 s tick) shows it instead, and a
/// full-screen notification is the last-resort fallback.
@pragma('vm:entry-point')
Future<void> alarmCheckinCallback(int alarmId) async {
  debugPrint(
      'AlarmCheckin: fired alarmId=$alarmId (Isolate=${Isolate.current.debugName})');
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

    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    await NotificationService.instance.initialize();

    // ── Priority 1: due call reminders — deliver directly, no LLM needed ──
    // The old path ran the full agent first, which was slow and could fail.
    // A user-requested call ("1分钟后打给我") must not depend on an LLM round-
    // trip; we queue the call immediately and let the foreground service
    // (or the notification fallback below) deliver it.
    final dueCalls =
        await CheckinService.instance.claimDueCallReminders();
    if (dueCalls.isNotEmpty) {
      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (character != null) {
        await queuePendingCall(
          characterId: character.id,
          openingMessage: alarmOpeningForDueCall(dueCalls.first.body),
        );
        debugPrint('AlarmCheckin: call queued directly for '
            '"${character.name}" (${dueCalls.length} reminder(s))');
        // Try CallKit (usually fails in background isolate — no Flutter
        // engine). The foreground service picks it up within 15 s.
        var callDelivered = false;
        try {
          callDelivered =
              await CallkitService.instance.showPendingIncomingCall(
            characterId: character.id,
            nameCaller: character.name,
            avatarUrl: character.avatar,
          );
        } catch (e) {
          debugPrint('AlarmCheckin: CallKit failed (expected in '
              'background isolate): $e');
        }
        if (!callDelivered) {
          await _showAlarmCallFallbackNotification(character);
        }
      } else {
        debugPrint('AlarmCheckin: due call but no character found');
      }
      for (final c in dueCalls) {
        await CheckinService.instance.markStatus(c.id, 'done');
      }
    }

    // ── Priority 2: regular checkin / non-call reminders ──
    final hasDueReminder = await CheckinService.instance.hasDueReminders();
    if (await CheckinService.instance.isAppInForeground() &&
        !hasDueReminder) {
      debugPrint('AlarmCheckin: app is in foreground, skipping checkin');
      return;
    }

    // Best-effort: ensure the persistent foreground service is running so
    // it can display CallKit for the pending call on its next tick.
    try {
      await CompanionForegroundService.startPersistent();
      debugPrint('AlarmCheckin: foreground service ensured');
    } catch (e) {
      debugPrint('AlarmCheckin: could not start foreground service: $e');
    }

    final enqueued = await CheckinService.instance.maybeEnqueueCheckin();
    final hasPendingWork = await CheckinService.instance.hasPendingWork();
    debugPrint(
        'AlarmCheckin: enqueued=$enqueued hasPendingWork=$hasPendingWork');
    if (!enqueued && !hasPendingWork) return;

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

    // If the agent queued a voice call during a spontaneous checkin,
    // try CallKit (usually fails here) then fall back to notification.
    try {
      final showed = await CallkitService.instance.showPendingIncomingCall(
        characterId: character.id,
        nameCaller: character.name,
        avatarUrl: character.avatar,
      );
      if (!showed) {
        final pending = await readPendingCall();
        if (pending != null) {
          await _showAlarmCallFallbackNotification(character);
        }
      }
    } catch (e) {
      debugPrint('AlarmCheckin: post-agent call delivery failed: $e');
    }
  } catch (e, st) {
    debugPrint('AlarmCheckin: error: $e\n$st');
  } finally {
    // Always reschedule the next alarm so the chain continues even when the
    // app is never opened again. This is the self-sustaining production alarm.
    try {
      await CheckinService.instance.scheduleProductionAlarm();
      debugPrint('AlarmCheckin: next alarm scheduled');
    } catch (e) {
      debugPrint('AlarmCheckin: failed to reschedule alarm: $e');
    }
    // Reconcile the morning weather checkpoint so tomorrow's wake-up trigger
    // is armed even if the app is never reopened. Cheap when already scheduled.
    try {
      await MorningWeatherService.instance.refreshSchedule();
    } catch (e) {
      debugPrint('AlarmCheckin: failed to refresh morning weather: $e');
    }
  }
}

/// Opening message for a due call reminder (alarm callback path).
String alarmOpeningForDueCall(String reminderBody) {
  final body = reminderBody.trim();
  if (body.startsWith('宝，') || body.startsWith('宝。')) return body;
  return '宝，到时间了，我打过来了。现在方便说话吗？';
}

/// Fallback: show a full-screen notification when CallKit cannot display
/// from a background isolate. Tapping it opens the app in voice mode.
Future<void> _showAlarmCallFallbackNotification(
    CharacterModel character) async {
  try {
    await NotificationService.instance.showCallNotification(
      title: character.name,
      body: '想给你打个电话 ☎️',
      payload: 'call:${character.id}',
    );
    debugPrint('AlarmCheckin: fallback call notification shown');
  } catch (e) {
    debugPrint('AlarmCheckin: fallback notification failed: $e');
  }
}
