import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/food_models.dart';
import 'package:memex/data/personal_data_hub/food_service.dart';
import 'package:memex/db/app_database.dart';

const _binding = DomainBinding(
  coreInstanceId: 'food-core',
  principalId: 'food-phone',
  generation: 1,
  installationId: 'food-install',
);
final _now = DateTime.utc(2026, 10, 24, 5);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late DomainStore store;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = DomainStore(db, binding: _binding, clock: () => _now);
  });

  tearDown(() => db.close());

  test('reads selected day in time order and excludes voided records', () async {
    await store.configureRoute(foodDomain, DomainRoute.core);
    await store.applyPage(
      foodDomain,
      _page([
        _record('later', eatenAt: '2026-10-24T13:00:00+08:00'),
        _record('earlier', eatenAt: '2026-10-24T08:00:00+08:00'),
        _record('voided', voided: true),
        _record('tomorrow', localDate: '2026-10-25'),
      ]),
    );

    final snapshot = await FoodService(store: store).read(_now);
    expect(snapshot.entries.map((entry) => entry.id), ['earlier', 'later']);
    expect(snapshot.totals.kcal, 400);
    expect(snapshot.totals.kcalLow, 360);
    expect(snapshot.totals.kcalHigh, 440);
    expect(snapshot.invalidRecords, 0);
    expect(snapshot.error, isNull);
  });

  test('strict parser skips and counts corrupt records without losing valid data',
      () async {
    await store.configureRoute(foodDomain, DomainRoute.core);
    final bad = _record('bad');
    (bad['data'] as Map<String, dynamic>)['unexpected'] = true;
    await store.applyPage(foodDomain, _page([_record('good'), bad]));

    final snapshot = await FoodService(store: store).read(_now);
    expect(snapshot.entries.map((entry) => entry.id), ['good']);
    expect(snapshot.invalidRecords, 1);
    expect(snapshot.error, '已跳过 1 条无法读取的记录');
  });

  test('totals mismatch is corrupt and does not enter the day aggregate',
      () async {
    await store.configureRoute(foodDomain, DomainRoute.core);
    final bad = _record('bad-total');
    ((bad['data'] as Map<String, dynamic>)['totals']
        as Map<String, dynamic>)['kcal'] = 200.1;
    await store.applyPage(foodDomain, _page([bad]));

    final snapshot = await FoodService(store: store).read(_now);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.totals.kcal, 0);
    expect(snapshot.invalidRecords, 1);
  });

  test('rollover, incomplete and out-of-range business times are skipped',
      () async {
    await store.configureRoute(foodDomain, DomainRoute.core);
    const invalidTimes = [
      '2026-02-30T12:00:00Z',
      '2026-10-24T24:00:00Z',
      '2026-10-24T12:00Z',
      '2026-10-24T12:00:00.12Z',
      '2026-10-24T12:00:00+14:01',
      '2026-10-24T12:00:00+08:60',
    ];
    await store.applyPage(
      foodDomain,
      _page([
        for (var index = 0; index < invalidTimes.length; index++)
          _record('bad-time-$index', eatenAt: invalidTimes[index]),
      ]),
    );

    final snapshot = await FoodService(store: store).read(_now);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.invalidRecords, invalidTimes.length);
  });

  test('blank title is skipped even when its raw length is valid', () async {
    await store.configureRoute(foodDomain, DomainRoute.core);
    final bad = _record('blank-title');
    (bad['data'] as Map<String, dynamic>)['title'] = ' \t ';
    await store.applyPage(foodDomain, _page([bad]));

    final snapshot = await FoodService(store: store).read(_now);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.invalidRecords, 1);
  });

  test('unconfigured, disabled, unsynced and stale replicas return states',
      () async {
    expect((await FoodService().read(_now)).error, '尚未配置');
    expect((await FoodService(store: store).read(_now)).error, '尚未启用');

    await store.configureRoute(foodDomain, DomainRoute.core);
    expect((await FoodService(store: store).read(_now)).error, '等待首次同步');
    await store.invalidateReplica(foodDomain);
    expect((await FoodService(store: store).read(_now)).error, '等待首次同步');

    await store.applyPage(foodDomain, _page([_record('stale')]));
    expect((await FoodService(store: store).read(_now)).error, isNull);
    final op = await store.enqueue(
      foodDomain,
      id: 'stale',
      kind: 'patch',
      actor: 'agent_inferred',
      baseRevision: 1,
      fields: {
        'patch': {'title': '合成午餐修正'},
      },
    );
    // Operation lookup reports a deleted target after the patch was accepted.
    await store.complete(
      op,
      {
        'domain': foodDomain,
        'op_id': op,
        'outcome': 'accepted',
        'receipt': {
          'receipt_id': 'receipt-$op',
          'accepted_op_id': op,
          'principal_id': _binding.principalId,
          'accepted_at': _now.toIso8601String(),
          'policy_version': DomainPolicy.version,
          'core_instance_id': _binding.coreInstanceId,
          'domain': foodDomain,
          'authority_mode': 'single_host',
          'epoch': null,
          'targets': [
            {'id': 'stale', 'revision': 2},
          ],
          'change_sequences': [1],
          'receipt_auth': List.filled(64, 'a').join(),
        },
      },
      targetState: 'deleted',
    );
    expect((await store.read())['domains'][foodDomain]['replica_requires_resync'],
        isTrue);
    expect((await FoodService(store: store).read(_now)).error, '副本需要重新同步');
  });

  test('date filtering uses local_date rather than eaten_at UTC date', () async {
    await store.configureRoute(foodDomain, DomainRoute.core);
    await store.applyPage(
      foodDomain,
      _page([
        _record(
          'boundary',
          eatenAt: '2026-10-23T20:30:00Z',
          localDate: '2026-10-24',
        ),
      ]),
    );

    final today = await FoodService(store: store).read(_now);
    final yesterday =
        await FoodService(store: store).read(DateTime.utc(2026, 10, 23));
    expect(today.entries.single.id, 'boundary');
    expect(yesterday.entries, isEmpty);
  });
}

Json _record(
  String id, {
  String eatenAt = '2026-10-24T12:00:00+08:00',
  String localDate = '2026-10-24',
  bool voided = false,
}) =>
    {
      'id': id,
      'domain': foodDomain,
      'revision': 1,
      'core_instance_id': 'food-core',
      'origin': {'device_id': 'frontend:chatgpt_web'},
      'data': {
        'eaten_at': eatenAt,
        'local_date': localDate,
        'meal': 'lunch',
        'title': '合成午餐',
        'note': '虚构样例',
        'input_kind': 'text',
        'items': [
          {
            'name': '合成米饭',
            'food_ref': {'source': 'model', 'id': null},
            'grams': 100,
            'grams_low': 90,
            'grams_high': 110,
            'kcal': 130,
            'protein_g': 2.7,
            'fat_g': 0.3,
            'carb_g': 28,
            'basis': 'model_guess',
            'confidence': 'medium',
          },
          {
            'name': '合成鸡蛋',
            'food_ref': {'source': 'label', 'id': 'synthetic-label'},
            'grams': 50,
            'grams_low': 45,
            'grams_high': 55,
            'kcal': 70,
            'protein_g': 6,
            'fat_g': 5,
            'carb_g': 0.5,
            'basis': 'label',
            'confidence': 'high',
          },
        ],
        'totals': {
          'kcal': 200,
          'kcal_low': 180,
          'kcal_high': 220,
          'protein_g': 8.7,
          'fat_g': 5.3,
          'carb_g': 28.5,
        },
        'user_corrected': false,
        'voided': voided,
      },
    };

Json _page(List<Json> records) => {
      'records': records,
      'next_cursor': 'food-cursor',
      'policy_version': DomainPolicy.version,
    };
