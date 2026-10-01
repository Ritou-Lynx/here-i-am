import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/checkin_tool.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/data/services/checkin_service.dart';
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

  tearDown(() => db.close());

  test('disabled switch neither enqueues nor considers a checkin due',
      () async {
    await CheckinService.instance.setEnabled(false);
    await CheckinService.instance.forceCheckinDueNow();

    expect(await CheckinService.instance.dueForCheckin(), isFalse);
    expect(await CheckinService.instance.maybeEnqueueCheckin(), isFalse);
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
  });

  test('re-enabling allows a new checkin without reviving old work', () async {
    final old =
        await _insert(db, id: 'old', triggerType: 'checkin', createdAt: _now());
    await CheckinService.instance.setEnabled(false);
    expect(await CheckinService.instance.hasPendingWork(), isFalse);
    expect(await CheckinService.instance.drainPending(), isEmpty);

    await CheckinService.instance.setEnabled(true);
    expect(await CheckinService.instance.maybeEnqueueCheckin(), isTrue);
    expect(await CheckinService.instance.canDeliverTrigger(old), isFalse);
    expect(await CheckinService.instance.drainPending(), hasLength(1));
  });

  test('disabling fails every active automatic trigger, including spaced JSON',
      () async {
    final now = _now();
    await _insert(
      db,
      id: 'checkin-pending',
      triggerType: 'checkin',
      status: 'pending',
      createdAt: now,
    );
    await _insert(
      db,
      id: 'weather-processing',
      triggerType: 'reminder',
      status: 'processing',
      createdAt: now,
      context: '{ "kind" : "morning_weather" }',
    );
    await _insert(
      db,
      id: 'outing-pending',
      triggerType: 'reminder',
      status: 'pending',
      createdAt: now,
      context: jsonEncode({'kind': 'proactive_outing'}),
    );
    await _insert(
      db,
      id: 'followup-pending',
      triggerType: 'reminder',
      status: 'pending',
      createdAt: now,
      context: jsonEncode({'kind': 'checkin_followup'}),
    );
    await _insert(
      db,
      id: 'user-reminder',
      triggerType: 'reminder',
      status: 'pending',
      createdAt: now,
      context: jsonEncode({'action': 'call'}),
    );

    await CheckinService.instance.setEnabled(false);

    final rows = await db.select(db.systemMessageQueue).get();
    final status = {for (final row in rows) row.id: row.status};
    expect(status['checkin-pending'], 'failed');
    expect(status['weather-processing'], 'failed');
    expect(status['outing-pending'], 'failed');
    expect(status['followup-pending'], 'failed');
    expect(status['user-reminder'], 'pending');
  });

  test(
      'disabled service does not drain residual automatic work but keeps user work',
      () async {
    await CheckinService.instance.setEnabled(false);
    final now = _now();
    // Simulate rows left by an old app version after the durable switch was off.
    await _insert(
      db,
      id: 'legacy-checkin',
      triggerType: 'checkin',
      createdAt: now,
    );
    await _insert(
      db,
      id: 'user-reminder',
      triggerType: 'reminder',
      createdAt: now,
    );

    expect(await CheckinService.instance.hasPendingWork(), isTrue,
        reason: 'the explicit user reminder remains actionable');
    final drained = await CheckinService.instance.drainPending();

    expect(drained.map((row) => row.id), ['user-reminder']);
    final legacy = await _row(db, 'legacy-checkin');
    expect(legacy.status, 'failed');
  });

  test(
      'a claimed automatic trigger stays cancelled after disable and re-enable',
      () async {
    final trigger = await _insert(
      db,
      id: 'claimed-checkin',
      triggerType: 'checkin',
      status: 'processing',
      createdAt: _now(),
    );

    await CheckinService.instance.setEnabled(false);
    // A different isolate can finish an old drain or recovery after disable.
    await CheckinService.instance.markStatus(trigger.id, 'pending');
    await CheckinService.instance.markStatus(trigger.id, 'processing');
    await CheckinService.instance.setEnabled(true);

    expect(await CheckinService.instance.canDeliverTrigger(trigger), isFalse);
    expect((await _row(db, trigger.id)).status, 'failed');
  });

  test('a disabled claimed trigger cannot notify, remind, or queue a call',
      () async {
    final trigger = await _insert(
      db,
      id: 'inflight-checkin',
      triggerType: 'checkin',
      status: 'processing',
      createdAt: _now(),
    );
    final checkinTool = buildSystemCheckinTool(
      characterId: 'i',
      triggerProvider: () => trigger,
    );
    final callTool = buildInitiateCallTool(
      characterId: 'i',
      triggerProvider: () => trigger,
    );

    await CheckinService.instance.setEnabled(false);

    final notify = await Function.apply(
      checkinTool.executable!,
      ['notify', 'i', 'This must not send.', null, null],
    ) as String;
    final remind = await Function.apply(
      checkinTool.executable!,
      ['remind', null, null, 5, 'This must not be scheduled.'],
    ) as String;
    final call = await Function.apply(
      callTool.executable!,
      ['This must not call.'],
    ) as String;

    expect(notify, contains('cancelled'));
    expect(remind, contains('cancelled'));
    expect(call, contains('blocked'));
    expect(await db.select(db.personaChatMessages).get(), isEmpty,
        reason: 'blocked notification must not persist a chat message');
    expect(await db.select(db.systemMessageQueue).get(), hasLength(1),
        reason: 'blocked remind must not create a follow-up');
    expect(await readPendingCall(), isNull,
        reason: 'blocked call must not create pending call state');
  });

  test(
      'automatic pending call is cleared on disable while explicit call survives',
      () async {
    await CheckinService.instance.setEnabled(true);
    expect(
      await queuePendingCall(
        characterId: 'i',
        openingMessage: 'automatic',
        proactive: true,
      ),
      isTrue,
    );

    await CheckinService.instance.setEnabled(false);
    expect(await readPendingCall(), isNull);

    expect(
      await queuePendingCall(
        characterId: 'i',
        openingMessage: 'explicit',
        proactive: false,
      ),
      isTrue,
    );
    await CheckinService.instance.setEnabled(false);

    expect((await readPendingCall())?.opening, 'explicit');
  });

  test('system checkin follow-up inherits automatic versus user provenance',
      () async {
    final automatic = await _insert(
      db,
      id: 'automatic',
      triggerType: 'checkin',
      createdAt: _now(),
    );
    final autoTool = buildSystemCheckinTool(triggerProvider: () => automatic);
    await Function.apply(
      autoTool.executable!,
      ['remind', null, null, 5, 'automatic follow-up'],
    );
    final automaticFollowup = (await db.select(db.systemMessageQueue).get())
        .singleWhere((row) => row.body == 'automatic follow-up');
    expect(jsonDecode(automaticFollowup.context!), {
      'kind': 'checkin_followup',
    });

    final userTrigger = await _insert(
      db,
      id: 'user',
      triggerType: 'reminder',
      createdAt: _now(),
    );
    final userTool = buildSystemCheckinTool(triggerProvider: () => userTrigger);
    await CheckinService.instance.setEnabled(false);
    expect(
        await CheckinService.instance.canDeliverTrigger(userTrigger), isTrue);
    await Function.apply(
      userTool.executable!,
      ['remind', null, null, 5, 'user follow-up'],
    );
    final userFollowup = (await db.select(db.systemMessageQueue).get())
        .singleWhere((row) => row.body == 'user follow-up');
    expect(userFollowup.context, isNull);
  });
}

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Future<SystemMessageQueueData> _insert(
  AppDatabase db, {
  required String id,
  required String triggerType,
  required int createdAt,
  String status = 'pending',
  String? context,
}) async {
  await db.into(db.systemMessageQueue).insert(
        SystemMessageQueueCompanion.insert(
          id: id,
          triggerType: triggerType,
          body: id,
          status: Value(status),
          createdAt: createdAt,
          scheduledFor: triggerType == 'reminder'
              ? Value(createdAt - 1)
              : const Value(null),
          context: Value(context),
        ),
      );
  return _row(db, id);
}

Future<SystemMessageQueueData> _row(AppDatabase db, String id) =>
    (db.select(db.systemMessageQueue)..where((t) => t.id.equals(id)))
        .getSingle();
