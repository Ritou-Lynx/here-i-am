import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('first run schedules after 20 real chat messages', () async {
    await _insertChatMessages(db, count: 19);
    await _insertActionMessage(db);

    expect(
      await DreamingSchedulerService.shouldScheduleEventDrivenBatch(
        db: db,
        characterId: 'i',
      ),
      isFalse,
    );

    await _insertChatMessages(db, count: 1, start: 20);

    expect(
      await DreamingSchedulerService.shouldScheduleEventDrivenBatch(
        db: db,
        characterId: 'i',
      ),
      isTrue,
    );
  });

  test('after a recent batch 100 new chat messages schedule immediately',
      () async {
    final now = DateTime(2026, 7, 13, 20);
    await _writeBatchState(db, lastRun: now, watermark: 0);
    await _insertChatMessages(db, count: 99);
    await _insertActionMessage(db);

    expect(
      await DreamingSchedulerService.shouldScheduleEventDrivenBatch(
        db: db,
        characterId: 'i',
        now: now.add(const Duration(minutes: 10)),
      ),
      isFalse,
    );

    await _insertChatMessages(db, count: 1, start: 100);

    expect(
      await DreamingSchedulerService.shouldScheduleEventDrivenBatch(
        db: db,
        characterId: 'i',
        now: now.add(const Duration(minutes: 10)),
      ),
      isTrue,
    );
  });

  test('one new chat schedules when the previous batch is over an hour old',
      () async {
    final lastRun = DateTime(2026, 7, 13, 18);
    await _writeBatchState(db, lastRun: lastRun, watermark: 0);
    await _insertChatMessages(db, count: 1);

    expect(
      await DreamingSchedulerService.shouldScheduleEventDrivenBatch(
        db: db,
        characterId: 'i',
        now: lastRun.add(const Duration(minutes: 61)),
      ),
      isTrue,
    );
  });
}

Future<void> _insertChatMessages(
  AppDatabase db, {
  required int count,
  int start = 1,
}) async {
  for (var i = 0; i < count; i++) {
    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'i',
            isFromCharacter: (start + i).isEven,
            content: 'chat ${start + i}',
            timestamp: DateTime(2026, 7, 13, 12).add(Duration(minutes: i)),
          ),
        );
  }
}

Future<void> _insertActionMessage(AppDatabase db) async {
  await db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: 'i',
          isFromCharacter: true,
          content: '*action*',
          messageType: const Value('action'),
          timestamp: DateTime(2026, 7, 13, 13),
        ),
      );
}

Future<void> _writeBatchState(
  AppDatabase db, {
  required DateTime lastRun,
  required int watermark,
}) async {
  await db.into(db.kvStore).insert(
        KvStoreCompanion.insert(
          key: 'dreaming.batch.last_run_time.i',
          bucket: const Value('memory_v3.dreaming'),
          value: Value(lastRun.millisecondsSinceEpoch.toString()),
        ),
      );
  await db.into(db.kvStore).insert(
        KvStoreCompanion.insert(
          key: 'dreaming.batch.last_watermark.i',
          bucket: const Value('memory_v3.dreaming'),
          value: Value(watermark.toString()),
        ),
      );
}
