import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/checkin_tool.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/reminder_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CheckinService', () {
    test('markProcessingDone completes active system triggers', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'active-checkin',
              triggerType: 'checkin',
              body: 'Review recent context.',
              status: const Value('processing'),
              createdAt: now,
            ),
          );
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'future-checkin',
              triggerType: 'checkin',
              body: 'Leave this one alone.',
              status: const Value('pending'),
              createdAt: now,
            ),
          );

      final updated = await CheckinService.instance.markProcessingDone();

      expect(updated, 1);
      final active = await (db.select(db.systemMessageQueue)
            ..where((t) => t.id.equals('active-checkin')))
          .getSingle();
      final future = await (db.select(db.systemMessageQueue)
            ..where((t) => t.id.equals('future-checkin')))
          .getSingle();
      expect(active.status, 'done');
      expect(active.processedAt, isNotNull);
      expect(future.status, 'pending');
      expect(future.processedAt, isNull);
    });

    test('recoverStuckProcessing does not reopen completed triggers', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'completed-checkin',
              triggerType: 'checkin',
              body: 'Already processed.',
              status: const Value('processing'),
              createdAt: now,
            ),
          );

      await CheckinService.instance.markProcessingDone();
      await CheckinService.instance.recoverStuckProcessing();

      final row = await (db.select(db.systemMessageQueue)
            ..where((t) => t.id.equals('completed-checkin')))
          .getSingle();
      expect(row.status, 'done');
    });

    test('future reminders do not block new checkin pulses', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'future-reminder',
              triggerType: 'reminder',
              body: 'Check back later.',
              status: const Value('pending'),
              createdAt: now,
              scheduledFor: Value(now + 3600),
            ),
          );

      final enqueued = await CheckinService.instance.maybeEnqueueCheckin();

      expect(enqueued, isTrue);
      final checkins = await (db.select(db.systemMessageQueue)
            ..where((t) => t.triggerType.equals('checkin')))
          .get();
      expect(checkins, hasLength(1));
    });

    test('due reminders still block a second immediate checkin pulse',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'due-reminder',
              triggerType: 'reminder',
              body: 'This should be handled now.',
              status: const Value('pending'),
              createdAt: now - 3600,
              scheduledFor: Value(now - 60),
            ),
          );

      final enqueued = await CheckinService.instance.maybeEnqueueCheckin();

      expect(enqueued, isFalse);
      final checkins = await (db.select(db.systemMessageQueue)
            ..where((t) => t.triggerType.equals('checkin')))
          .get();
      expect(checkins, isEmpty);
    });

    test('hasDueReminders ignores future reminders', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'future-reminder',
              triggerType: 'reminder',
              body: 'Later.',
              status: const Value('pending'),
              createdAt: now,
              scheduledFor: Value(now + 3600),
            ),
          );

      expect(await CheckinService.instance.hasDueReminders(), isFalse);

      await (db.update(db.systemMessageQueue)
            ..where((t) => t.id.equals('future-reminder')))
          .write(SystemMessageQueueCompanion(
        scheduledFor: Value(now - 1),
      ));

      expect(await CheckinService.instance.hasDueReminders(), isTrue);
    });

    test('reminder_create persists explicit scheduled call action', () async {
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final tool = buildReminderTool();

      await Function.apply(
        tool.executable!,
        [30, 'Call the user now.', null, 'call', null],
      );

      final row = await db.select(db.systemMessageQueue).getSingle();
      expect(row.triggerType, 'reminder');
      expect(row.body, 'Call the user now.');
      expect(jsonDecode(row.context!), {'action': 'call'});
      expect(row.scheduledFor, greaterThanOrEqualTo(before + 30 * 60));
    });

    test('stale checkins and reminders are failed before draining', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final row in [
        SystemMessageQueueCompanion.insert(
          id: 'stale-checkin',
          triggerType: 'checkin',
          body: 'This checkin is no longer timely.',
          createdAt: now - 61 * 60,
        ),
        SystemMessageQueueCompanion.insert(
          id: 'stale-reminder',
          triggerType: 'reminder',
          body: 'This is no longer timely.',
          createdAt: now - 60 * 60,
          scheduledFor: Value(now - 16 * 60),
        ),
      ]) {
        await db.into(db.systemMessageQueue).insert(row);
      }

      expect(await CheckinService.instance.drainPending(), isEmpty);
      final rows = await db.select(db.systemMessageQueue).get();
      expect(rows.map((row) => row.status), everyElement('failed'));
    });

    test('due reminders are drained before fresh stochastic checkins',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'fresh-checkin',
              triggerType: 'checkin',
              body: 'Natural pulse.',
              createdAt: now,
            ),
          );
      await db.into(db.systemMessageQueue).insert(
            SystemMessageQueueCompanion.insert(
              id: 'due-reminder',
              triggerType: 'reminder',
              body: 'Handle this first.',
              createdAt: now - 60,
              scheduledFor: Value(now - 1),
            ),
          );

      final rows = await CheckinService.instance.drainPending();

      expect(rows.map((row) => row.id), ['due-reminder', 'fresh-checkin']);
    });

    test('reminder_create accepts an explicit ISO due_at', () async {
      final dueAt = DateTime.now().add(const Duration(hours: 2));
      final tool = buildReminderTool();

      await Function.apply(
        tool.executable!,
        [
          null,
          'Call at the exact time.',
          dueAt.toIso8601String(),
          'call',
          null
        ],
      );

      final row = await db.select(db.systemMessageQueue).getSingle();
      expect(row.scheduledFor, dueAt.millisecondsSinceEpoch ~/ 1000);
    });

    test('nearby call reminders supersede older pending call reminders',
        () async {
      final dueAt = DateTime.now().add(const Duration(minutes: 5));
      final context = jsonEncode({'action': 'call'});

      await ReminderService.instance.createReminder(
        text: 'First call.',
        dueAt: dueAt,
        contextJson: context,
      );
      await ReminderService.instance.createReminder(
        text: 'Second call.',
        dueAt: dueAt.add(const Duration(seconds: 30)),
        contextJson: context,
      );

      final rows = await db.select(db.systemMessageQueue).get();
      final first = rows.singleWhere((row) => row.body == 'First call.');
      final second = rows.singleWhere((row) => row.body == 'Second call.');
      expect(first.status, 'failed');
      expect(first.processedAt, isNotNull);
      expect(second.status, 'pending');
      expect(second.processedAt, isNull);
    });

    test('claimDueCallReminders batches duplicate due call reminders',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final context = jsonEncode({'action': 'call'});
      for (final row in [
        SystemMessageQueueCompanion.insert(
          id: 'call-one',
          triggerType: 'reminder',
          body: 'Call once.',
          createdAt: now - 60,
          scheduledFor: Value(now - 1),
          context: Value(context),
        ),
        SystemMessageQueueCompanion.insert(
          id: 'call-two',
          triggerType: 'reminder',
          body: 'Call twice.',
          createdAt: now - 30,
          scheduledFor: Value(now),
          context: Value(context),
        ),
        SystemMessageQueueCompanion.insert(
          id: 'text-reminder',
          triggerType: 'reminder',
          body: 'Do not call.',
          createdAt: now - 30,
          scheduledFor: Value(now),
        ),
        SystemMessageQueueCompanion.insert(
          id: 'future-call',
          triggerType: 'reminder',
          body: 'Call later.',
          createdAt: now,
          scheduledFor: Value(now + 60),
          context: Value(context),
        ),
      ]) {
        await db.into(db.systemMessageQueue).insert(row);
      }

      final claimed = await CheckinService.instance.claimDueCallReminders();

      expect(claimed.map((row) => row.id), ['call-one', 'call-two']);
      final rows = await db.select(db.systemMessageQueue).get();
      expect(
          rows.singleWhere((row) => row.id == 'call-one').status, 'processing');
      expect(
          rows.singleWhere((row) => row.id == 'call-two').status, 'processing');
      expect(rows.singleWhere((row) => row.id == 'text-reminder').status,
          'pending');
      expect(
          rows.singleWhere((row) => row.id == 'future-call').status, 'pending');
    });
  });
}
