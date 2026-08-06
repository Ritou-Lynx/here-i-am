import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/reminder_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

/// Schedules a single morning weather/clothing checkpoint keyed to the user's
/// wake-up time derived from their `sleep_pattern` rhythm.
///
/// Unlike [ProactiveOutingService], this does not require an explicit saved
/// plan — it uses the user's inferred daily rhythm. The checkpoint fires at
/// `wakeTime - leadTime` so the companion can give a clothing/umbrella heads-up
/// before the user heads out.
class MorningWeatherService {
  MorningWeatherService._();
  static final MorningWeatherService instance = MorningWeatherService._();

  static const Duration defaultLeadTime = Duration(minutes: 15);
  static const String contextKind = 'morning_weather';
  static const String _kvBucket = 'morning_weather';

  final _logger = getLogger('MorningWeatherService');

  AppDatabase get _db => AppDatabase.instance;

  /// Reconciles the next morning weather checkpoint.
  ///
  /// Idempotent per wake-up date: the dedupe key is
  /// `morning_weather_<yyyy-MM-dd>`, so calling this multiple times in one day
  /// does not create duplicate reminders. [alarmScheduler] is injectable for
  /// tests.
  Future<int> refreshSchedule({
    DateTime? now,
    Duration leadTime = defaultLeadTime,
    Future<void> Function(String reminderId, DateTime dueAt)? alarmScheduler,
  }) async {
    if (!AppDatabase.isInitialized) return 0;
    if (!UserRhythmService.isInitialized) return 0;
    if (!await CheckinService.instance.isEnabled()) return 0;

    final effectiveNow = now ?? DateTime.now();

    final wakeTime = await _inferWakeTime(effectiveNow);
    if (wakeTime == null) return 0;

    final dueAt = wakeTime.subtract(leadTime);
    final earliest = effectiveNow.add(const Duration(minutes: 1));
    if (dueAt.isBefore(earliest)) {
      // Wake time already passed today; skip — next call will pick up tomorrow
      // when the rhythm snapshot is refreshed.
      return 0;
    }

    final dedupeKey = _dedupeKey(dueAt);
    final existing = await _db.kvStoreLookup(
      key: dedupeKey,
      bucket: _kvBucket,
    );
    if (existing != null) return 0;

    final context = jsonEncode({
      'kind': contextKind,
      'wake_time': wakeTime.toIso8601String(),
      'due_at': dueAt.toIso8601String(),
    });
    final reminderId = await ReminderService.instance.createReminder(
      text: '起床前天气与穿衣检查（预计 ${_fmtHhMm(wakeTime)} 起床）',
      dueAt: dueAt,
      contextJson: context,
    );
    await (alarmScheduler ?? _scheduleAlarm)(reminderId, dueAt);

    final nowSec = effectiveNow.millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: dedupeKey,
            bucket: const Value(_kvBucket),
            value: Value(reminderId),
            updatedAt: Value(nowSec),
          ),
        );
    _logger.info(
      'Scheduled morning weather checkpoint at $dueAt '
      '(wakeTime=$wakeTime, reminderId=$reminderId)',
    );
    return 1;
  }

  /// Stops automatically-created morning weather checkpoints.
  Future<int> cancelPendingCheckpoints() async {
    if (!AppDatabase.isInitialized) return 0;
    final count = await (_db.update(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.context.like('%"kind":"$contextKind"%')))
        .write(const SystemMessageQueueCompanion(status: Value('failed')));
    await (_db.delete(_db.kvStore)..where((t) => t.bucket.equals(_kvBucket)))
        .go();
    return count;
  }

  /// Infers today's wake-up time from the active `sleep_pattern` rhythm.
  ///
  /// Sleep rrule format: `FREQ=DAILY;HH:MM-HH:MM`, where the second time is the
  /// wake-up time. For cross-midnight slots (e.g. `02:00-09:00`), the wake time
  /// is 09:00 of the same calendar day. For normal evening slots (e.g.
  /// `23:30-07:00`), the end time (07:00) belongs to the next calendar day, so
  /// we interpret the wake time as that morning of the current day.
  Future<DateTime?> _inferWakeTime(DateTime now) async {
    final service = UserRhythmService.instance;
    final rhythms = await service.getActiveRhythmsByKind('sleep_pattern');
    if (rhythms.isEmpty) return null;

    for (final rhythm in rhythms) {
      final slots = UserRhythmService.parseRrule(rhythm.rrule);
      for (final slot in slots) {
        final endTime = slot.endTime;
        if (endTime.isEmpty) continue;
        final parts = endTime.split(':');
        if (parts.length != 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) continue;

        final todayWake = DateTime(
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );
        // If wake time is in the morning (00:00–11:59), it belongs to today.
        // If it is in the afternoon/evening (12:00–23:59), the user likely
        // works night shifts — treat it as today as well, since the rhythm is
        // DAILY.
        return todayWake;
      }
    }
    return null;
  }

  Future<void> _scheduleAlarm(String reminderId, DateTime dueAt) {
    return CheckinService.instance.scheduleReminderAlarm(
      reminderId: reminderId,
      dueAt: dueAt,
    );
  }

  static String _dedupeKey(DateTime dueAt) {
    final d = dueAt;
    return 'morning_weather_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _fmtHhMm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}