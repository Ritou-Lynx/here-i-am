import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_access.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/data/personal_data_hub/planning_models.dart';
import 'package:memex/data/personal_data_hub/planning_reminders.dart';
import 'package:memex/data/personal_data_hub/planning_service.dart';

class FakeAlarms implements PlanningAlarmScheduler {
  final events = <String>[];
  Completer<void>? block;
  int active = 0, maximum = 0;
  bool failSchedule = false;
  @override
  Future<void> schedule(String id, DateTime due) async {
    if (failSchedule) throw StateError('synthetic alarm unavailable');
    active++;
    if (active > maximum) maximum = active;
    events.add('schedule:$id');
    await block?.future;
    active--;
  }

  @override
  Future<void> cancel(String id) async {
    events.add('cancel:$id');
  }
}

class NoNetwork implements DomainTransport {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('network forbidden in fixture');
  }
}

final now = DateTime.utc(2026, 10, 5, 8);
Json item(String id, {String status = '待办'}) => {
      'id': id,
      'domain': 'plan_items',
      'core_instance_id': 'core-$id',
      'revision': 1,
      'data': {
        'title': 'synthetic $id',
        'area': '未归类',
        'status': status,
        'remind_at': '2026-10-05T09:00:00Z'
      },
    };
Json page(List<Json> records) => {
      'records': records,
      'next_cursor': 'cursor',
      'policy_version': DomainPolicy.version,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late PersonalDataHub hub;
  late FakeAlarms alarms;
  late NoNetwork transport;
  PersonalDataHubRuntime? runtime;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('hub-runtime-synthetic-');
    db = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/app.sqlite')));
    hub = PersonalDataHub.forDatabase(db);
    alarms = FakeAlarms();
    transport = NoNetwork();
    SharedPreferences.setMockInitialValues(
        {DeviceIdentityService.preferenceKey: 'runtime-install'});
    DeviceIdentityService.resetForTesting();
  });
  tearDown(() async {
    await runtime?.dispose();
    runtime = null;
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<PersonalDataHubRuntime> start({
    Future<OrganizedRecord> Function(String)? extract,
    PlanningAuthorize? authorize,
  }) async =>
      runtime = await PersonalDataHubRuntime.create(
        db: db,
        hub: hub,
        alarms: alarms,
        clock: () => now,
        extract: extract,
        planningAuthorize: authorize,
      );
  Future<DomainStore> attach(String suffix,
      {String domain = 'plan_items',
      List<Json>? records,
      String? installationId}) async {
    final store = DomainStore(db,
        binding: DomainBinding(
            coreInstanceId: 'core-$suffix',
            principalId: 'principal-$suffix',
            generation: 1,
            installationId: installationId ?? 'install-$suffix'),
        clock: () => now);
    await store.configureRoute(domain, DomainRoute.core);
    await store.applyPage(domain, page(records ?? [item(suffix)]));
    hub.attach(domain, store, transport, allowLocalRecall: false);
    return store;
  }

  test(
      'empty hub is readonly and local capture survives database reopen without a model',
      () async {
    final r = await start();
    expect((await r.read(now)).statusWritable, false);
    await expectLater(r.setStatus('x', PlanningStatusAction.complete),
        throwsA(isA<DomainFailure>()));
    await r.synchronize();
    final draft = r.quickCaptureService.newDraft('synthetic capture');
    final result = await r.quickCaptureService.send(draft);
    expect(result.deliveryMessage, contains('本机'));
    expect(result.organizerMessage, contains('待处理'));
    expect((await r.phoneStore.read())['outbox'], isEmpty);
    expect(r.phoneStore.binding.installationId, 'runtime-install');
    expect(transport.calls, 0);
    await r.dispose();
    runtime = null;
    await db.close();
    DeviceIdentityService.resetForTesting();
    db = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/app.sqlite')));
    hub = PersonalDataHub.forDatabase(db);
    final reopened = await start();
    expect((await reopened.recent()).single.captureId, draft.captureId);
    expect((await reopened.recent()).single.text, 'synthetic capture');
  });

  test('optional secure connection read failure keeps phone-local startup',
      () async {
    final errors = <String>[];
    final access = await loadOptionalDomainAccess(
      hub: hub,
      readConnection: () async => throw StateError('synthetic keystore error'),
      readInstallationId: () async => 'runtime-install',
      reportError: errors.add,
    );
    expect(access, isNull);
    expect(errors, ['hub_domain_access_unavailable']);

    final r = await start();
    final draft = r.quickCaptureService.newDraft('凭据不可用仍保存在本机');
    final result = await r.quickCaptureService.send(draft);
    expect(result.deliveryMessage, contains('本机'));
    expect((await r.phoneStore.visible('captures')).single['data']['text'],
        '凭据不可用仍保存在本机');
  });

  test(
      'runtime discovers all domains attached after creation and missing issuer fails closed',
      () async {
    final r = await start();
    final store = await attach('first');
    for (final domain in ['plan_days', 'plan_weeks']) {
      await store.configureRoute(domain, DomainRoute.core);
      await store.applyPage(domain, page([]));
      hub.attach(domain, store, transport, allowLocalRecall: false);
    }
    await r.ownerConnectionsChanged();
    final snapshot = await r.read(now);
    expect(snapshot.items.keys, ['first']);
    expect(snapshot.domainErrors, isEmpty);
    expect(snapshot.statusWritable, false);
    await expectLater(r.setStatus('first', PlanningStatusAction.complete),
        throwsA(isA<DomainFailure>()));
    expect((await store.read())['outbox'], isEmpty);
    expect(transport.calls, 0);
  });

  test(
      'status uses existing evidence transaction and clears reminder without an open page',
      () async {
    final store = await attach('status');
    final actions = <PlanningUiAuthorization>[];
    final r = await start(authorize: (_, action) async {
      actions.add(action);
      return 'runtime-planning:${action.actionId}';
    });
    expect(alarms.events, hasLength(1));
    final op = await r.setStatus('status', PlanningStatusAction.complete);
    expect(actions.single.intent['op_id'], op);
    expect(actions.single.status, '完成');
    expect((await store.read())['outbox'].single['intent']['authorization_ref'],
        'runtime-planning:${actions.single.actionId}');
    expect(alarms.events.last, startsWith('cancel:'));
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
  });

  test(
      'owner binding replacement cancels old reminders before registering current ones',
      () async {
    await attach('old');
    final r = await start();
    await attach('new');
    await r.ownerConnectionsChanged();
    expect((await r.read(now)).items.keys, ['new']);
    expect(alarms.events.map((e) => e.split(':').first),
        ['schedule', 'cancel', 'schedule']);
    final queued = await db.select(db.systemMessageQueue).get();
    expect(queued.single.body, 'synthetic new');
  });

  test(
      'kv_store committed notifications reconcile reminders and publish changes',
      () async {
    final store = await attach('event');
    final r = await start();
    final changed = r.changes.first;
    await store.applyPage(
        'plan_items',
        page([
          {...item('event', status: '完成'), 'revision': 2}
        ]));
    await changed.timeout(const Duration(seconds: 5));
    await r.refresh(consume: false);
    expect(alarms.events.last, startsWith('cancel:'));
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
  });

  test('overlapping refresh requests coalesce while alarms remain serial',
      () async {
    final r = await start();
    alarms.block = Completer<void>();
    await attach('serial');
    final first = r.ownerConnectionsChanged();
    final second = r.refresh();
    final third = r.refresh();
    expect(identical(first, second), true);
    expect(identical(second, third), true);
    alarms.block!.complete();
    await Future.wait([first, second, third]);
    expect(alarms.maximum, 1);
    expect(alarms.events.where((e) => e.startsWith('schedule:')), hasLength(1));
  });

  test(
      'configured extraction consumes saved phone capture once and filters planning cards',
      () async {
    var calls = 0;
    final r = await start(extract: (_) async {
      calls++;
      OrganizedCard card(String type) => OrganizedCard(
          type: type,
          title: 'synthetic $type',
          dropletLabel: 'fixture',
          presentationModule: {'blocks': <dynamic>[]},
          retrievalText: 'fixture',
          valence: 0,
          arousal: 0);
      return OrganizedRecord(cards: [card('fact'), card('task')]);
    });
    final result = await r.quickCaptureService
        .send(r.quickCaptureService.newDraft('synthetic input'));
    await r.refresh();
    expect(calls, 1);
    expect(result.text, 'synthetic input');
    expect((await r.recent()).single.organizerMessage, contains('已处理'));
    expect((await db.select(db.memoryCards).get()).single.type, 'fact');
    expect(result.plannerMessage, contains('待处理'));
  });

  test(
      'failed extraction retains durable pending capture and refresh retries it',
      () async {
    var fail = true;
    final r = await start(extract: (_) async {
      if (fail) throw StateError('synthetic model offline');
      return OrganizedRecord(cards: []);
    });
    final result = await r.quickCaptureService
        .send(r.quickCaptureService.newDraft('pending input'));
    expect(result.organizerMessage, contains('待处理'));
    await expectLater(r.refresh(), throwsStateError);
    expect((await r.recent()).single.text, 'pending input');
    fail = false;
    await r.refresh();
    expect((await r.recent()).single.organizerMessage, contains('无需处理'));
  });

  test('configured Core captures never fall back or fabricate authorization',
      () async {
    final r = await start();
    final store = await attach('capture', domain: 'captures', records: []);
    await r.ownerConnectionsChanged();
    await expectLater(
        r.quickCaptureService
            .send(r.quickCaptureService.newDraft('must reject')),
        throwsA(isA<DomainFailure>().having(
            (e) => e.code, 'code', 'capture_authorization_not_configured')));
    expect((await store.read())['outbox'], isEmpty);
    expect(await r.recent(), isEmpty);
    expect(transport.calls, 0);
  });
  test('startup and send return while existing capture extraction is blocked',
      () async {
    final initial = await start();
    await initial.quickCaptureService
        .send(initial.quickCaptureService.newDraft('existing pending'));
    await initial.dispose();
    runtime = null;
    final gate = Completer<void>(), entered = Completer<void>();
    var calls = 0;
    final r = await start(extract: (_) async {
      calls++;
      if (!entered.isCompleted) entered.complete();
      await gate.future;
      return OrganizedRecord(cards: []);
    }).timeout(const Duration(seconds: 5));
    await entered.future.timeout(const Duration(seconds: 5));
    final saved = await r.quickCaptureService
        .send(r.quickCaptureService.newDraft('second pending'))
        .timeout(const Duration(seconds: 5));
    expect(saved.organizerMessage, contains('待处理'));
    expect(gate.isCompleted, false);
    gate.complete();
    await r.refresh();
    expect(calls, 2);
    expect(
        (await r.recent()).every((r) => r.organizerMessage!.contains('无需处理')),
        true);
  });

  test('hub attachment refreshes reminders without an explicit owner hook',
      () async {
    final r = await start();
    final event = r.changes.first;
    await attach('auto');
    await event.timeout(const Duration(seconds: 5));
    await r.refresh(consume: false);
    expect(alarms.events.single, startsWith('schedule:'));
    expect((await r.read(now)).items.keys, ['auto']);
  });
  test('alarm failure does not block processing of a durably saved capture',
      () async {
    await attach('alarm');
    alarms.failSchedule = true;
    var calls = 0;
    final r = await start(extract: (_) async {
      calls++;
      return OrganizedRecord(cards: []);
    });
    await r.quickCaptureService
        .send(r.quickCaptureService.newDraft('safe pending'));
    await expectLater(r.refresh(), throwsStateError);
    expect(calls, 1);
    expect((await r.recent()).single.organizerMessage, contains('无需处理'));
    expect(r.lastRefreshError, isA<StateError>());
    alarms.failSchedule = false;
    await r.refresh();
    expect(calls, 1);
  });
  Future<List<Map<String, Object?>>> reminderRows(AppDatabase database) async =>
      (await database
              .customSelect(
                  "SELECT key,value FROM kv_store WHERE bucket='planning_reminder' ORDER BY key")
              .get())
          .map((row) => row.data)
          .toList();

  test(
      'second empty-hub engine with same installation preserves owner reminders during capture',
      () async {
    await attach('shared', installationId: 'runtime-install');
    final owner = await start();
    await owner.refresh(consume: false);
    final beforeQueue = await db.select(db.systemMessageQueue).get();
    final beforeRows = await reminderRows(db);
    expect(beforeQueue, hasLength(1));
    expect(beforeRows, hasLength(1));
    final secondDb = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/app.sqlite')));
    final secondAlarms = FakeAlarms();
    PersonalDataHubRuntime? second;
    try {
      DeviceIdentityService.resetForTesting();
      second = await PersonalDataHubRuntime.create(
          db: secondDb, alarms: secondAlarms, clock: () => now);
      expect(second.phoneStore.binding.installationId,
          owner.phoneStore.binding.installationId);
      await second.refresh();
      await second.quickCaptureService
          .send(second.quickCaptureService.newDraft('other engine capture'));
      await second.refresh();
      await second.ownerConnectionsChanged();
      await owner.refresh(consume: false);
      expect(secondAlarms.events, isEmpty);
      expect(alarms.events.where((e) => e.startsWith('cancel:')), isEmpty);
      expect(await secondDb.select(secondDb.systemMessageQueue).get(),
          beforeQueue);
      expect(await reminderRows(secondDb), beforeRows);
      expect((await second.recent()).single.text, 'other engine capture');
    } finally {
      await second?.dispose();
      await secondDb.close();
    }
  });

  test(
      'capture-only flag prevents takeover even with a configured planning owner on another engine',
      () async {
    final ownerStore = await attach('flag', installationId: 'runtime-install');
    final owner = await start();
    await owner.refresh(consume: false);
    final beforeQueue = await db.select(db.systemMessageQueue).get();
    final beforeRows = await reminderRows(db);
    final secondDb = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/app.sqlite')));
    final secondHub = PersonalDataHub.forDatabase(secondDb);
    final secondAlarms = FakeAlarms();
    PersonalDataHubRuntime? second;
    try {
      final secondStore =
          DomainStore(secondDb, binding: ownerStore.binding, clock: () => now);
      secondHub.attach('plan_items', secondStore, transport,
          allowLocalRecall: false);
      second = await PersonalDataHubRuntime.create(
          db: secondDb,
          hub: secondHub,
          alarms: secondAlarms,
          enablePlanningReminders: false,
          clock: () => now,
          extract: (_) async => OrganizedRecord(cards: []));
      expect((await second.read(now)).items.keys, ['flag']);
      await second.quickCaptureService
          .send(second.quickCaptureService.newDraft('capture only engine'));
      await second.ownerConnectionsChanged();
      await second.refresh();
      expect((await second.recent()).single.organizerMessage, contains('无需处理'));
      expect(secondAlarms.events, isEmpty);
      expect(await secondDb.select(secondDb.systemMessageQueue).get(),
          beforeQueue);
      expect(await reminderRows(secondDb), beforeRows);
    } finally {
      await second?.dispose();
      await secondDb.close();
    }
  });

  test(
      'an acquired owner clears its own reminders when its replica is invalidated',
      () async {
    final store = await attach('invalidated');
    final r = await start();
    await r.refresh(consume: false);
    expect(alarms.events.single, startsWith('schedule:'));
    await store.invalidateReplica('plan_items');
    await r.refresh(consume: false);
    expect(alarms.events.last, startsWith('cancel:'));
    expect(await db.select(db.systemMessageQueue).get(), isEmpty);
    expect(await reminderRows(db), isEmpty);
  });
}
