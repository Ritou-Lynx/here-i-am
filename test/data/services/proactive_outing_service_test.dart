import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/proactive_outing_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProactiveOutingService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    service = ProactiveOutingService(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('schedules one checkpoint for an explicit outing and deduplicates it',
      () async {
    final now = DateTime(2026, 7, 13, 8);
    final eventAt = DateTime(2026, 7, 13, 10);
    await CheckinService.instance.setEnabled(true);
    await _insertTimedCard(
      db,
      id: 'outing-1',
      type: 'schedule',
      title: '去医院复诊',
      retrievalText: '上午十点去医院复诊',
      rawInput: '记一下，上午十点去医院复诊',
      fields: {
        'startAt': eventAt.toIso8601String(),
        'location': '北京市朝阳区',
        'walkingMinutes': 20,
      },
    );

    final alarms = <DateTime>[];
    final first = await service.refreshSchedule(
      now: now,
      alarmScheduler: (_, dueAt) async => alarms.add(dueAt),
    );
    final second = await service.refreshSchedule(
      now: now,
      alarmScheduler: (_, dueAt) async => alarms.add(dueAt),
    );

    expect(first, 1);
    expect(second, 0);
    expect(alarms, [DateTime(2026, 7, 13, 9, 15)]);

    final queue = await db.select(db.systemMessageQueue).get();
    expect(queue, hasLength(1));
    expect(queue.single.scheduledFor,
        DateTime(2026, 7, 13, 9, 15).millisecondsSinceEpoch ~/ 1000);
    final context = jsonDecode(queue.single.context!) as Map<String, dynamic>;
    expect(context['kind'], ProactiveOutingService.contextKind);
    expect(context['place_hint'], '北京市朝阳区');
    expect(context['walking_minutes'], 20);
  });

  test('ignores a generic deadline with no place or outing language', () async {
    final now = DateTime(2026, 7, 13, 8);
    await CheckinService.instance.setEnabled(true);
    await _insertTimedCard(
      db,
      id: 'task-1',
      type: 'task',
      title: '交报告',
      retrievalText: '今天十点前交报告',
      rawInput: '记一下，今天十点前交报告',
      fields: {'dueAt': DateTime(2026, 7, 13, 10).toIso8601String()},
    );

    final count = await service.refreshSchedule(
      now: now,
      alarmScheduler: (_, __) async {},
    );

    expect(count, 0);
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
  });

  test('disabling proactive pushes cancels only outing checkpoints', () async {
    final now = DateTime(2026, 7, 13, 8).millisecondsSinceEpoch ~/ 1000;
    await db.into(db.systemMessageQueue).insert(
          SystemMessageQueueCompanion.insert(
            id: 'outing-reminder',
            triggerType: 'reminder',
            body: 'outing',
            createdAt: now,
            scheduledFor: Value(now + 3600),
            context: Value(jsonEncode({
              'kind': ProactiveOutingService.contextKind,
              'card_id': 'outing-1',
            })),
          ),
        );
    await db.into(db.systemMessageQueue).insert(
          SystemMessageQueueCompanion.insert(
            id: 'user-reminder',
            triggerType: 'reminder',
            body: 'call mum',
            createdAt: now,
            scheduledFor: Value(now + 3600),
          ),
        );

    final cancelled = await service.cancelPendingCheckpoints();
    final rows = await db.select(db.systemMessageQueue).get();
    final byId = {for (final row in rows) row.id: row};

    expect(cancelled, 1);
    expect(byId['outing-reminder']?.status, 'failed');
    expect(byId['user-reminder']?.status, 'pending');
  });
}

Future<void> _insertTimedCard(
  AppDatabase db, {
  required String id,
  required String type,
  required String title,
  required String retrievalText,
  required String rawInput,
  required Map<String, dynamic> fields,
}) async {
  final now = DateTime(2026, 7, 13, 8).millisecondsSinceEpoch;
  await db.into(db.memoryCards).insert(
        MemoryCardsCompanion.insert(
          id: id,
          type: type,
          title: title,
          dropletLabel: title.substring(0, 2),
          presentationModule: '[]',
          retrievalText: retrievalText,
          valence: 0,
          arousal: 0.2,
          status: const Value('active'),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db.into(db.memoryCardSources).insert(
        MemoryCardSourcesCompanion.insert(
          cardId: id,
          rawInput: rawInput,
          recordedAt: now,
          sourceKind: 'record_button',
        ),
      );
  await db.into(db.memoryCardStructuredFields).insert(
        MemoryCardStructuredFieldsCompanion.insert(
          cardId: id,
          structuredFieldsType: 'general',
          fieldsJson: jsonEncode(fields),
          createdAt: now,
          updatedAt: now,
        ),
      );
}
