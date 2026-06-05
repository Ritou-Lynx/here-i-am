import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

/// Manages AI-created reminders — the agent leaves breadcrumbs for its future
/// self. Reminders are stored as rows in [SystemMessageQueue] with
/// `triggerType = 'reminder'` and a `scheduledFor` timestamp.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final _logger = getLogger('ReminderService');
  final _uuid = const Uuid();
  static const int _callDedupeWindowSeconds = 120;

  AppDatabase get _db => AppDatabase.instance;

  /// Create a reminder that will be processed at [dueAt].
  Future<String> createReminder({
    required String text,
    required DateTime dueAt,
    String? contextJson,
  }) async {
    final isCallReminder = _isCallReminder(contextJson);
    final id = _uuid.v4();
    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final dueAtSec = dueAt.millisecondsSinceEpoch ~/ 1000;
    await _db.transaction(() async {
      if (isCallReminder) {
        final minDueAt = dueAtSec - _callDedupeWindowSeconds;
        final maxDueAt = dueAtSec + _callDedupeWindowSeconds;
        final superseded = await (_db.update(_db.systemMessageQueue)
              ..where((t) =>
                  t.triggerType.equals('reminder') &
                  t.status.equals('pending') &
                  t.context.like('%"action":"call"%') &
                  t.scheduledFor.isBiggerOrEqualValue(minDueAt) &
                  t.scheduledFor.isSmallerOrEqualValue(maxDueAt)))
            .write(SystemMessageQueueCompanion(
          status: const Value('failed'),
          processedAt: Value(nowSec),
        ));
        if (superseded > 0) {
          _logger.info(
            'Superseded $superseded duplicate call reminder(s) near $dueAt',
          );
        }
      }
      await _db.into(_db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: id,
              triggerType: 'reminder',
              body: text,
              createdAt: nowSec,
              scheduledFor: Value(dueAtSec),
              context: Value(contextJson),
              processedAt: const Value(null),
            ),
          );
    });
    _logger.info('Reminder created: $id — $text (due: $dueAt)');
    return id;
  }

  bool _isCallReminder(String? contextJson) {
    if (contextJson == null) return false;
    try {
      final decoded = jsonDecode(contextJson);
      return decoded is Map && decoded['action'] == 'call';
    } catch (_) {
      return contextJson.contains('"action":"call"');
    }
  }

  /// Get all pending reminders that are due now.
  Future<List<SystemMessageQueueData>> getDueReminders() async {
    if (!AppDatabase.isInitialized) return [];

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final query = _db.select(_db.systemMessageQueue)
      ..where((t) =>
          t.triggerType.equals('reminder') &
          t.status.equals('pending') &
          t.scheduledFor.isSmallerOrEqualValue(now));
    return query.get();
  }

  /// Delete a reminder by id.
  Future<void> deleteReminder(String id) async {
    await (_db.delete(_db.systemMessageQueue)..where((t) => t.id.equals(id)))
        .go();
    _logger.info('Reminder deleted: $id');
  }
}
