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
  static const _keySleepConfirmedDate = 'sleep_push_confirmed_date';
  // Epoch-seconds timestamp of when user announced sleep but hasn't been verified yet.
  static const _keySleepClaimedTs = 'sleep_push_claimed_ts';
  // Epoch-seconds timestamp when the verification push was sent.
  static const _keySleepVerifyTs = 'sleep_push_verify_ts';

  // Sleep push window: 23:40–02:00 (high-frequency mode to nudge user to sleep)
  static const int _sleepPushMinMin = 1;
  static const int _sleepPushMaxMin = 2;
  // Minutes after claim before we send the "are you really asleep?" verification push.
  static const int _sleepClaimVerifyMinutes = 15;
  // Minutes after sending the verification push before we check for a response.
  static const int _sleepVerifyResponseMinutes = 10;
  static const int sleepClaimVerifySeconds = _sleepClaimVerifyMinutes * 60;

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

  // ---------------------------------------------------------------------------
  // Sleep push
  // ---------------------------------------------------------------------------

  /// Returns true when the current local time is in the sleep push window
  /// (23:40–02:00). No DB access needed.
  bool isSleepPushWindow() {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute;
    return (h == 23 && m >= 40) || h == 0 || h == 1;
  }

  /// Maps post-midnight hours back to the previous calendar date so that
  /// the whole "tonight" session (23:40 → 02:00) shares the same key.
  String _sleepNightKey() {
    final now = DateTime.now();
    final d = now.hour < 4 ? now.subtract(const Duration(days: 1)) : now;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Whether the user has already confirmed sleep for tonight.
  Future<bool> isSleepConfirmedTonight() async {
    if (!AppDatabase.isInitialized) return false;
    final row =
        await _db.kvStoreLookup(key: _keySleepConfirmedDate, bucket: _bucket);
    return row?.value == _sleepNightKey();
  }

  /// Mark that the user has confirmed sleep for tonight.
  /// Called only after inactivity has been verified. Stops all sleep push.
  Future<void> markSleepConfirmedTonight() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
      KvStoreCompanion.insert(
        key: _keySleepConfirmedDate,
        bucket: const Value(_bucket),
        value: Value(_sleepNightKey()),
        updatedAt: Value(now),
      ),
    );
    _logger.info('Sleep confirmed tonight (${_sleepNightKey()})');
  }

  /// User announced they are going to sleep, but we have not yet verified
  /// inactivity. Alarm will reschedule at [_sleepClaimVerifyMinutes] to check.
  Future<void> markSleepClaimed() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
      KvStoreCompanion.insert(
        key: _keySleepClaimedTs,
        bucket: const Value(_bucket),
        value: Value(now.toString()),
        updatedAt: Value(now),
      ),
    );
    _logger.info('Sleep claimed at epoch $now');
  }

  /// Returns the epoch-seconds timestamp when the user claimed sleep,
  /// or null if no pending claim exists.
  Future<int?> getSleepClaimedTs() async {
    if (!AppDatabase.isInitialized) return null;
    final row =
        await _db.kvStoreLookup(key: _keySleepClaimedTs, bucket: _bucket);
    return int.tryParse(row?.value ?? '');
  }

  /// Clear the sleep-claimed state (user was caught still awake).
  Future<void> clearSleepClaimed() async {
    if (!AppDatabase.isInitialized) return;
    await (_db.delete(_db.kvStore)
          ..where((t) =>
              t.key.equals(_keySleepClaimedTs) &
              t.bucket.equalsNullable(_bucket)))
        .go();
    _logger.info('Sleep claim cleared — user still awake');
  }

  /// Record that the verification push ("你真的睡了吗？") has been sent.
  Future<void> markSleepVerifySent() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
      KvStoreCompanion.insert(
        key: _keySleepVerifyTs,
        bucket: const Value(_bucket),
        value: Value(now.toString()),
        updatedAt: Value(now),
      ),
    );
    _logger.info('Sleep verify push sent at epoch $now');
  }

  /// Returns the epoch-seconds timestamp when the verification push was sent,
  /// or null if it hasn't been sent yet.
  Future<int?> getSleepVerifyTs() async {
    if (!AppDatabase.isInitialized) return null;
    final row =
        await _db.kvStoreLookup(key: _keySleepVerifyTs, bucket: _bucket);
    return int.tryParse(row?.value ?? '');
  }

  /// Clear both claimed and verify states together (resume push or confirm sleep).
  Future<void> clearSleepClaimAndVerify() async {
    if (!AppDatabase.isInitialized) return;
    await (_db.delete(_db.kvStore)
          ..where((t) =>
              (t.key.equals(_keySleepClaimedTs) |
                  t.key.equals(_keySleepVerifyTs)) &
              t.bucket.equalsNullable(_bucket)))
        .go();
    _logger.info('Sleep claim + verify state cleared');
  }

  /// Returns true if the user sent any chat message after [sinceEpochSec].
  /// Used by the sleep push state machine to verify inactivity.
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
    final int minMin, maxMin;
    if (isSleepPushWindow() && !await isSleepConfirmedTonight()) {
      final claimedTs = await getSleepClaimedTs();
      if (claimedTs != null) {
        final verifyTs = await getSleepVerifyTs();
        if (verifyTs == null) {
          // Claimed but verification push not yet sent — fire after the claim window.
          minMin = _sleepClaimVerifyMinutes;
          maxMin = _sleepClaimVerifyMinutes;
          _logger.info('Sleep claimed — sending verify push in ${_sleepClaimVerifyMinutes}min');
        } else {
          // Verification push sent — wait for the user's response window.
          minMin = _sleepVerifyResponseMinutes;
          maxMin = _sleepVerifyResponseMinutes;
          _logger.info('Sleep verify sent — checking response in ${_sleepVerifyResponseMinutes}min');
        }
      } else {
        // Active sleep push: fire every 1–2 min.
        minMin = _sleepPushMinMin;
        maxMin = _sleepPushMaxMin;
        _logger.info('Sleep push active — using $minMin–${maxMin}min interval');
      }
    } else {
      minMin = await getMinIntervalMinutes();
      maxMin = await getMaxIntervalMinutes();
    }
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

  /// How long after the last foreground heartbeat we still consider the app
  /// "in use". Must exceed the UI heartbeat interval (60s) with margin.
  static const int _foregroundGraceSeconds = 90;

  /// Called by the UI isolate while the app is foregrounded. Writes a heartbeat
  /// timestamp so background checkins know to stay silent.
  Future<void> markForeground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _keyForegroundHeartbeat, DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }

  /// Called when the app is backgrounded — expires the heartbeat immediately so
  /// background checkins can resume without waiting out the grace window.
  Future<void> markBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyForegroundHeartbeat, 0);
  }

  /// Whether the app appears to be in the foreground right now, based on the
  /// heartbeat timestamp. Survives app kills (a stale timestamp simply expires).
  Future<bool> isAppInForeground() async {
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
    _logger.info('Checkin pulse: next natural delay would be ~${delayMinutes}m');

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
  /// elapsed since the last checkin — a random interval within [min, max], or
  /// the high-frequency window during sleep push. Reschedules the next target
  /// each time it fires, so checkin cadence stays random/natural rather than
  /// firing on every tick.
  Future<bool> dueForCheckin() async {
    if (!AppDatabase.isInitialized) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final row = await _db.kvStoreLookup(key: _keyNextCheckinTs, bucket: _bucket);
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
    final int minMin, maxMin;
    if (isSleepPushWindow() && !await isSleepConfirmedTonight()) {
      minMin = _sleepPushMinMin;
      maxMin = _sleepPushMaxMin;
    } else {
      minMin = await getMinIntervalMinutes();
      maxMin = await getMaxIntervalMinutes();
    }
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
    if (isSleepPushWindow()) {
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      return '[SLEEP PUSH] Current time: $hh:$mm — '
          'It is bedtime. Nudge the user to sleep. '
          'Check recent chat: if user confirmed sleep, call sleep_confirmed. '
          'Otherwise always call notify with a sleep-push message. '
          'Never call silent during sleep push.';
    }

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

  /// Marks system messages currently being handled by an agent turn as done.
  ///
  /// Draining a checkin marks it as `processing` before the LLM sees it, so the
  /// completion tool must finish `processing` rows rather than querying pending
  /// rows again.
  Future<int> markProcessingDone() async {
    if (!AppDatabase.isInitialized) return 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (_db.update(_db.systemMessageQueue)
          ..where((t) => t.status.equals('processing')))
        .write(SystemMessageQueueCompanion(
      status: const Value('done'),
      processedAt: Value(now),
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

    // Skip checkin if the app is currently in the foreground — the user is
    // actively using the app and doesn't need a background push.
    // (This catches the hasPendingWork path that bypasses maybeEnqueueCheckin's
    // own foreground gate.)
    if (await CheckinService.instance.isAppInForeground()) {
      debugPrint('AlarmCheckin: app is in foreground, skipping checkin');
      return;
    }

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
  } finally {
    // Always reschedule the next alarm so the chain continues even when the
    // app is never opened again. This is the self-sustaining production alarm.
    try {
      await CheckinService.instance.scheduleProductionAlarm();
      debugPrint('AlarmCheckin: next alarm scheduled');
    } catch (e) {
      debugPrint('AlarmCheckin: failed to reschedule alarm: $e');
    }
  }
}
