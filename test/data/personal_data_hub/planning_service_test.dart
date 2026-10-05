import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/planning_models.dart';
import 'package:memex/data/personal_data_hub/planning_service.dart';
import 'package:memex/db/app_database.dart';
import 'planning_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late DomainStore store;
  late PlanningService service;
  final evidence = <PlanningUiAuthorization>[];
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = DomainStore(db,
        binding: planningTestBinding, clock: () => planningTestNow);
    for (final name in planningDomains) {
      await store.configureRoute(name, DomainRoute.core);
    }
    await store.applyPage(
        'plan_items',
        planningPage([
          planningItem('a', title: '事项甲'),
          planningItem('b', title: '事项乙', area: '学习')
        ]));
    await store.applyPage('plan_days', planningPage([planningDay()]));
    await store.applyPage('plan_weeks', planningPage([planningWeek()]));
    evidence.clear();
    service = PlanningService(
        stores: {for (final name in planningDomains) name: store},
        connection: () => PlanningConnection.offline,
        clock: () => planningTestNow,
        authorize: (database, action) async {
          evidence.add(action);
          await database.customStatement(
              'INSERT INTO kv_store(key,value,bucket) VALUES(?,?,?)', [
            action.reference,
            jsonEncode(action.toJson()),
            'planning_test_authorization'
          ]);
        });
  });
  tearDown(() async {
    await db.close();
  });

  test('reads queue order, week capacities and unclassified without guessing',
      () async {
    final s = await service.read(planningTestNow);
    expect(s.day!.queue('deep'), ['b', 'a']);
    expect(s.day!.version, 1);
    expect(s.day!.capacity['long'], isNull);
    expect(s.items['a']!.area, '未归类');
    expect(s.week!.quotas.single['completed'], 1);
    expect(s.week!.debt.single['amount'], 1);
    expect(s.connection, PlanningConnection.offline);
    expect(s.statusWritable, true);
  });

  test('UI status and exact authorization commit atomically in shared outbox',
      () async {
    final op = await service.setStatus('a', PlanningStatusAction.complete);
    final raw = (await store.read())['outbox'].single;
    expect(raw['intent']['patch'], {'status': '完成'});
    expect(raw['intent']['kind'], 'status');
    expect(raw['intent']['actor'], 'user_direct');
    expect(raw['intent']['base_revision'], 1);
    expect(raw['intent']['authorization_ref'], evidence.single.reference);
    expect(evidence.single.opId, op);
    expect(evidence.single.toJson()['principal_id'], 'planning-phone');
    expect(evidence.single.toJson()['installation_id'], 'planning-install');
    expect(evidence.single.toJson()['patch'], {'status': '完成'});
    final s = await service.read(planningTestNow);
    expect(s.items['a']!.status, '完成');
    expect(s.items['a']!.pending, true);
    expect(s.operations['a']!.label, '待同步');
    await expectLater(service.setStatus('a', PlanningStatusAction.abandon),
        throwsA(isA<DomainFailure>()));
    expect((await store.read())['outbox'], hasLength(1));
  });

  test('failed authorization rolls back queue, overlay and field correction',
      () async {
    final failing = PlanningService(
        stores: {'plan_items': store},
        authorize: (_, __) async {
          throw StateError('evidence unavailable');
        });
    await expectLater(failing.setStatus('a', PlanningStatusAction.complete),
        throwsStateError);
    final state = await store.read();
    expect(state['outbox'], isEmpty);
    expect(state['domains']['plan_items']['corrections'], isEmpty);
    expect((await service.read(planningTestNow)).items['a']!.status, '待办');
  });

  test('unconfigured, phone and shadow cannot write or synchronize online',
      () async {
    var calls = 0;
    final empty = PlanningService(syncDomain: (_) async {
      calls++;
    });
    expect((await empty.read(planningTestNow)).statusWritable, false);
    await expectLater(empty.setStatus('a', PlanningStatusAction.complete),
        throwsA(isA<DomainFailure>()));
    await empty.synchronize();
    final second = DomainStore(db,
        binding: const DomainBinding(
            coreInstanceId: 'x',
            principalId: 'x',
            generation: 1,
            installationId: 'other'));
    final inactive = PlanningService(
        stores: {'plan_items': second},
        authorize: (_, __) async {},
        syncDomain: (_) async {
          calls++;
        });
    for (final route in [DomainRoute.phone, DomainRoute.shadow]) {
      await second.configureRoute('plan_items', route);
      await expectLater(inactive.setStatus('a', PlanningStatusAction.complete),
          throwsA(isA<DomainFailure>()));
      await inactive.synchronize();
    }
    expect(calls, 0);
  });

  test('request feedback distinguishes accepted, rejected and needs resolution',
      () async {
    final op = await service.setStatus('a', PlanningStatusAction.complete);
    final accepted = planningReceipt(op, 'a');
    accepted['record'] = {...planningItem('a', status: '完成'), 'revision': 2};
    await store.complete(op, accepted);
    var snapshot = await service.read(planningTestNow);
    expect(snapshot.operations['a']!.label, '已接受');
    expect(snapshot.items['a']!.pending, false);
    final second = await service.setStatus('b', PlanningStatusAction.abandon);
    await store.complete(second, {
      'domain': 'plan_items',
      'op_id': second,
      'outcome': 'needs_resolution',
      'reason': 'user_conflict',
      'problem': {'code': 'user_conflict'}
    });
    snapshot = await service.read(planningTestNow);
    expect(snapshot.items['b']!.status, '待办');
    expect(snapshot.operations['b']!.state, 'needs_resolution');
    expect(snapshot.operations['b']!.blocksAction, true);
  });

  test('rejected status never remains an accepted or pending card overlay',
      () async {
    final op = await service.setStatus('a', PlanningStatusAction.abandon);
    await store.complete(op, {
      'domain': 'plan_items',
      'op_id': op,
      'outcome': 'rejected',
      'reason': 'actor_not_authorized'
    });
    final s = await service.read(planningTestNow);
    expect(s.items['a']!.status, '待办');
    expect(s.items['a']!.pending, false);
    expect(s.operations['a']!.state, 'rejected');
  });

  test('tombstone, stale replica and replaced item fail without new evidence',
      () async {
    await store.applyPage(
        'plan_items',
        planningPage([
          {
            'id': 'a',
            'domain': 'plan_items',
            'revision': 2,
            'core_instance_id': 'planning-core',
            'deleted_at': '2026-10-05T08:00:00Z'
          },
          {
            ...planningItem('b'),
            'revision': 2,
            'data': {
              ...planningItem('b')['data'],
              'status': '被替代',
              'replaced_by': 'other'
            }
          },
        ], 'c2'));
    for (final id in ['a', 'b']) {
      await expectLater(service.setStatus(id, PlanningStatusAction.complete),
          throwsA(isA<DomainFailure>()));
    }
    expect(evidence, isEmpty);
    await store.invalidateReplica('plan_items');
    expect((await service.read(planningTestNow)).items, isEmpty);
  });

  test(
      'sync attempts all three domains when one fails and recovers by callback',
      () async {
    final calls = <String>[];
    final sync = PlanningService(
        stores: {for (final d in planningDomains) d: store},
        syncDomain: (name) async {
          calls.add(name);
          if (name == 'plan_days') throw const DomainFailure('offline');
        });
    await expectLater(sync.synchronize(), throwsA(isA<DomainFailure>()));
    expect(calls, planningDomains);
  });

  test('same database events and external connection stream are forwarded',
      () async {
    final external = StreamController<void>();
    final observing = PlanningService(
        stores: {'plan_items': store}, changes: external.stream);
    var count = 0;
    final sub = observing.changes.listen((_) {
      count++;
    });
    external.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(count, 1);
    await db.into(db.kvStore).insert(KvStoreCompanion.insert(
        key: 'planning-synthetic-notify', value: const Value('1')));
    await Future<void>.delayed(Duration.zero);
    expect(count, 2);
    await sub.cancel();
    await external.close();
  });

  test('cached prior day is explicit and ISO week handles year boundaries',
      () async {
    final s = await service.read(DateTime.utc(2026, 10, 6));
    expect(s.day!.date, '2026-10-05');
    expect(planningWeekKey(DateTime(2021, 1, 1)), '2020-W53');
    expect(planningWeekKey(DateTime(2024, 12, 30)), '2025-W01');
  });

  test('cross-owner domains cannot be joined into a misleading plan', () {
    final other = DomainStore(db,
        binding: const DomainBinding(
            coreInstanceId: 'another-core',
            principalId: 'phone',
            generation: 1,
            installationId: 'planning-install'));
    expect(
        () =>
            PlanningService(stores: {'plan_days': other, 'plan_items': store}),
        throwsA(isA<DomainFailure>()));
  });
}
