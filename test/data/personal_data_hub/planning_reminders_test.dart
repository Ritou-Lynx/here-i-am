import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/planning_models.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/planning_reminders.dart';
import 'package:memex/db/app_database.dart';
import 'planning_fixtures.dart';

class TestPlanningAlarms implements PlanningAlarmScheduler {
  final scheduled = <String, DateTime>{};
  int schedules = 0, cancels = 0;
  bool failCancel = false, failSchedule = false;
  @override
  Future<void> schedule(String id, DateTime dueAt) async {
    if (failSchedule) throw StateError('no OS permission');
    schedules++;
    scheduled[id] = dueAt;
  }

  @override
  Future<void> cancel(String id) async {
    if (failCancel) throw StateError('OS unavailable');
    cancels++;
    scheduled.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late TestPlanningAlarms alarms;
  late PlanningReminders reminders;
  PlanningItem item(
          {String status = '待办', String? at = '2026-10-05T09:00:00.000Z'}) =>
      PlanningItem(planningItem('a', remindAt: at, status: status));
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    alarms = TestPlanningAlarms();
    reminders = PlanningReminders(
        db: db,
        alarms: alarms,
        binding: planningTestBinding,
        clock: () => planningTestNow);
  });
  tearDown(() async {
    await db.close();
  });

  test(
      'remind_at creates one existing queue reminder and stable alarm only once',
      () async {
    await reminders.reconcile([item()]);
    await reminders.reconcile([item()]);
    expect(alarms.schedules, 1);
    final row = await db.select(db.systemMessageQueue).getSingle();
    expect(row.triggerType, 'reminder');
    expect(row.status, 'pending');
    expect(row.scheduledFor,
        DateTime.utc(2026, 10, 5, 9).millisecondsSinceEpoch ~/ 1000);
    expect(alarms.scheduled.keys, [row.id]);
    expect(await db.select(db.memoryCards).get(), isEmpty);
  });

  test('reschedule keeps ID, removes old alarm, terminal/no remind cancels',
      () async {
    await reminders.reconcile([item()]);
    final id = alarms.scheduled.keys.single;
    await reminders.reconcile([item(at: '2026-10-05T10:00:00.000Z')]);
    expect(alarms.scheduled.keys, [id]);
    expect(alarms.cancels, 1);
    expect(alarms.schedules, 2);
    await reminders.reconcile([item(status: '完成')]);
    expect(alarms.scheduled, isEmpty);
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
    await reminders.reconcile([item(at: null)]);
    expect(alarms.schedules, 2);
  });

  test(
      'removing replica cancels and scrubs body; cancel failure retries safely',
      () async {
    await reminders.reconcile([item()]);
    alarms.failCancel = true;
    await expectLater(reminders.reconcile([]), throwsStateError);
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
    alarms.failCancel = false;
    await reminders.reconcile([]);
    expect(alarms.scheduled, isEmpty);
    expect(await db.select(db.kvStore).get(), isEmpty);
  });

  test('registration failure and restart recover without duplicate queue rows',
      () async {
    alarms.failSchedule = true;
    await expectLater(reminders.reconcile([item()]), throwsStateError);
    expect(await db.select(db.systemMessageQueue).get(), hasLength(1));
    alarms.failSchedule = false;
    await reminders.reconcile([item()]);
    final restarted = PlanningReminders(
        db: db,
        alarms: alarms,
        binding: planningTestBinding,
        clock: () => planningTestNow);
    await restarted.reconcile([item()]);
    expect(await db.select(db.systemMessageQueue).get(), hasLength(1));
    expect(alarms.scheduled, hasLength(1));
    expect(alarms.schedules, 2);
  });

  test('past due and abandoned items never create stale reminders', () async {
    await reminders.reconcile([item(at: '2026-10-05T07:59:00.000Z')]);
    await reminders.reconcile([item(status: '放弃')]);
    expect(alarms.schedules, 0);
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
  });

  test('rejected pending completion restores reminder after failed OS cancel',
      () async {
    await reminders.reconcile([item()]);
    alarms.failCancel = true;
    await expectLater(
        reminders.reconcile([item(status: '完成')]), throwsStateError);
    alarms.failCancel = false;
    await reminders.reconcile([item()]);
    expect(await db.select(db.systemMessageQueue).get(), hasLength(1));
    expect(alarms.schedules, 2);
    expect(alarms.scheduled, hasLength(1));
  });

  test(
      'credential rotation clears old binding alarms before registering new ones',
      () async {
    await reminders.reconcile([item()]);
    final oldId = alarms.scheduled.keys.single;
    final rotated = PlanningReminders(
        db: db,
        alarms: alarms,
        binding: const DomainBinding(
            coreInstanceId: 'planning-core',
            principalId: 'planning-phone',
            generation: 2,
            installationId: 'planning-install'),
        clock: () => planningTestNow);
    await rotated.reconcile([item()]);
    expect(alarms.scheduled, hasLength(1));
    expect(alarms.scheduled.containsKey(oldId), false);
    expect(await db.select(db.systemMessageQueue).get(), hasLength(1));
  });
}
