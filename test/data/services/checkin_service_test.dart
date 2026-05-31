import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
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

    test('due reminders still block a second immediate checkin pulse', () async {
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
  });
}
