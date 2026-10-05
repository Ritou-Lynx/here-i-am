import 'dart:convert';
import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/db/app_database.dart';
import 'domain_protocol.dart';
import 'planning_models.dart';

abstract interface class PlanningAlarmScheduler {
  Future<void> schedule(String reminderId, DateTime dueAt);
  Future<void> cancel(String reminderId);
}

/// Uses the existing reminder wake-up callback and ID namespace. Permission
/// and OS delivery remain device gates; CheckinService has a DB fallback.
class CheckinPlanningAlarmScheduler implements PlanningAlarmScheduler {
  const CheckinPlanningAlarmScheduler();
  @override
  Future<void> schedule(String reminderId, DateTime dueAt) =>
      CheckinService.instance
          .scheduleReminderAlarm(reminderId: reminderId, dueAt: dueAt);
  @override
  Future<void> cancel(String reminderId) async {
    if (Platform.isAndroid) {
      final removed = await AndroidAlarmManager.cancel(
          CheckinService.instance.alarmIdForReminder(reminderId));
      if (!removed) throw const DomainFailure('planning_alarm_cancel_failed');
    }
  }
}

abstract interface class PlanningReminderSink {
  Future<void> reconcile(Iterable<PlanningItem> items);
}

/// Only derived reminders/registration metadata are persisted. The input is
/// always the current W7 visible replica, including local pending statuses.
class PlanningReminders implements PlanningReminderSink {
  PlanningReminders(
      {required this.db,
      required this.alarms,
      required this.binding,
      DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final AppDatabase db;
  final PlanningAlarmScheduler alarms;
  final DomainBinding binding;
  final DateTime Function() clock;
  final _registered = <String, String>{};
  Future<void> _tail = Future.value();
  String get _ownerPrefix =>
      'planning-reminder:${domainDigest(binding.installationId)}:';
  String get _prefix =>
      '$_ownerPrefix${domainDigest(binding.forDomain('plan_items'))}:';
  static const _bucket = 'planning_reminder';

  @override
  Future<void> reconcile(Iterable<PlanningItem> items) {
    final snapshot = items.toList();
    final next = _tail.then((_) => _reconcile(snapshot));
    // Keep later updates usable after a failed OS registration/cancellation.
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _reconcile(List<PlanningItem> items) async {
    final desired = <String, PlanningItem>{};
    for (final item in items) {
      if (!item.terminal && item.remindAt?.isAfter(clock()) == true) {
        desired['$_prefix${domainDigest(item.id)}'] = item;
      }
    }
    final saved = await (db.select(db.kvStore)
          ..where(
              (t) => t.bucket.equals(_bucket) & t.key.like('$_ownerPrefix%')))
        .get();
    final previous = {for (final row in saved) row.key: row.value};
    for (final id in previous.keys.where((id) => !desired.containsKey(id))) {
      // Remove the deliverable first. Failed OS cancellation may still wake
      // the existing checkin callback, but cannot deliver this stale body.
      // Keep cancellation metadata for retry.
      await _markCancellation(id, previous[id]);
      await alarms.cancel(id);
      await (db.delete(db.kvStore)
            ..where((t) => t.key.equals(id) & t.bucket.equals(_bucket)))
          .go();
      _registered.remove(id);
    }
    for (final entry in desired.entries) {
      final id = entry.key, item = entry.value, dueAt = item.remindAt!;
      final signature =
          domainDigest([dueAt.toUtc().toIso8601String(), item.title]);
      final existing = await (db.select(db.systemMessageQueue)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (previous[id] != signature) {
        if (previous.containsKey(id)) {
          await _markCancellation(id, previous[id]);
          await alarms.cancel(id);
        }
        final now = clock().millisecondsSinceEpoch ~/ 1000;
        await db.transaction(() async {
          await db
              .into(db.systemMessageQueue)
              .insertOnConflictUpdate(SystemMessageQueueCompanion.insert(
                id: id,
                triggerType: 'reminder',
                body: item.title,
                createdAt: now,
                status: const Value('pending'),
                processedAt: const Value(null),
                scheduledFor: Value(dueAt.millisecondsSinceEpoch ~/ 1000),
                context: Value(jsonEncode({
                  'kind': 'planning_reminder',
                  'plan_item_id': item.id,
                  'core_instance_id': binding.coreInstanceId
                })),
              ));
          await db.into(db.kvStore).insertOnConflictUpdate(
              KvStoreCompanion.insert(
                  key: id,
                  bucket: const Value(_bucket),
                  value: Value(signature),
                  updatedAt: Value(now)));
        });
      } else if (existing == null || existing.status != 'pending') {
        // A reminder that was already consumed must not be delivered twice.
        continue;
      }
      if (_registered[id] != signature) {
        await alarms.schedule(id, dueAt);
        _registered[id] = signature;
      }
    }
  }

  Future<void> _markCancellation(String id, String? prior) async {
    _registered.remove(id);
    await db.transaction(() async {
      if (prior != 'cancel_pending') {
        await (db.update(db.kvStore)
              ..where((t) => t.key.equals(id) & t.bucket.equals(_bucket)))
            .write(const KvStoreCompanion(value: Value('cancel_pending')));
      }
      await (db.delete(db.systemMessageQueue)..where((t) => t.id.equals(id)))
          .go();
    });
  }
}
