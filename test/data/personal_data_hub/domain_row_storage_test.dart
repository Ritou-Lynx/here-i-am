import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/domain_row_storage.dart';
import 'crash_worker.dart' show CrashDatabase, fixtureBinding;
import 'domain_sync_test.dart'
    show record, fields, runCrashProcess, deleteCrashFixture;

Json oldState() => {
      'domains': {
        'example': {
          'route': 'core',
          'binding': fixtureBinding.forDomain('example'),
          'cursor': 'original-cursor',
          'records': {
            'a': record('a', 2),
            'deleted': record('deleted', 3, deleted: true)
          },
          'phone_records': {
            'local': {
              'id': 'local',
              'data': {'title': 'local'},
              'revision': 0
            }
          },
          'hidden_ids': {'hidden': 5},
          'corrections': [
            {
              'op_id': 'sealed-op',
              'id': 'a',
              'field': 'title',
              'actor': 'user_direct',
              'value': 'new',
              'state': 'pending'
            }
          ],
        }
      },
      'outbox': [
        {
          'op_id': 'accepted-op',
          'id': 'a',
          'domain': 'example',
          'state': 'accepted',
          'result': {
            'receipt': {'receipt_id': 'original-receipt'}
          }
        },
        {
          'op_id': 'sealed-op',
          'id': 'a',
          'domain': 'example',
          'state': 'submitting',
          'sealed': true,
          'intent': {
            'op_id': 'sealed-op',
            'kind': 'patch',
            'patch': {'title': 'new'}
          }
        },
      ],
    };

Future<void> legacy(CrashDatabase db, Json state) => db.customStatement(
        'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?)', [
      'personal_data_hub.v1.${fixtureBinding.installationId}',
      jsonEncode(state),
      'personal_data_hub',
      1
    ]);

void main() {
  late Directory directory;
  late File file;
  late CrashDatabase db;
  late DomainStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hub-row-synthetic-');
    file = File('${directory.path}/state.sqlite');
    db = CrashDatabase(file);
    store = DomainStore(db, binding: fixtureBinding);
  });
  tearDown(() async {
    await db.close();
    final tempRoot = Directory.systemTemp.absolute.path.toLowerCase() +
        Platform.pathSeparator;
    if (!directory.absolute.path.toLowerCase().startsWith(tempRoot)) {
      throw StateError('Unsafe synthetic cleanup path');
    }
    await deleteCrashFixture(directory);
  });
  Future<List<Json>> physical() async => (await db
          .customSelect(
              "SELECT value FROM kv_store WHERE bucket='personal_data_hub'")
          .get())
      .map((r) => jsonObject(jsonDecode(r.read<String>('value'))))
      .toList();

  test(
      'legacy migration preserves record/tomb/op/correction/receipt identities',
      () async {
    final before = oldState();
    await legacy(db, before);
    expect(await store.read(), before);
    final rows = await physical();
    expect(rows.where((r) => r['kind'] == 'record'), hasLength(2));
    expect(rows.where((r) => r['kind'] == 'operation'), hasLength(2));
    expect(rows.where((r) => r['kind'] == 'correction'), hasLength(1));
    expect(rows.where((r) => r['kind'] == 'tomb'), hasLength(1));
    expect(
        rows.every((r) =>
            r['value'] is! Map || !(r['value'] as Map).containsKey('domains')),
        true);
    expect(
        await db.customSelect("SELECT key FROM kv_store WHERE key = ?",
            variables: [
              Variable('personal_data_hub.v1.${fixtureBinding.installationId}')
            ]).get(),
        isEmpty);
    await db.close();
    db = CrashDatabase(file);
    store = DomainStore(db, binding: fixtureBinding);
    expect(await store.read(), before);
  });

  for (final point in [
    'storage_row_before_commit',
    'legacy_migration_before_commit'
  ]) {
    test(
        'migration rollback at $point keeps original row with no partial new state',
        () async {
      final before = oldState();
      await legacy(db, before);
      final broken = DomainStore(db, binding: fixtureBinding, testFault: (p) {
        if (p == point) throw StateError('synthetic interruption');
      });
      await expectLater(broken.read(), throwsStateError);
      final rows = await physical();
      expect(rows, [before]);
      expect(await store.read(), before);
    });
  }

  test('corrupt legacy and mixed formats fail closed without discarding either',
      () async {
    await legacy(db, oldState());
    final raw = DomainRowStorage(db,
        installationId: fixtureBinding.installationId, clock: DateTime.now);
    await db.customStatement(
        'INSERT INTO kv_store(key,value,bucket) VALUES(?,?,?)', [
      '${raw.prefix}root',
      '{"kind":"root","version":2,"value":{}}',
      'personal_data_hub'
    ]);
    await expectLater(
        store.read(),
        throwsA(isA<DomainFailure>()
            .having((e) => e.code, 'code', 'storage_format_conflict')));
    expect(await physical(), hasLength(2));
  });

  test(
      'same installation reads coherent rows; other installation remains isolated',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.applyPage('example', {
      'records': [record('a', 1)],
      'next_cursor': 'c1',
      'policy_version': DomainPolicy.version
    });
    final other = DomainStore(db,
        binding: const DomainBinding(
            coreInstanceId: 'core-test',
            principalId: 'phone-test',
            generation: 1,
            installationId: 'other.installation_%'));
    expect((await other.read())['domains'], isEmpty);
    await other.configureRoute('example', DomainRoute.phone);
    expect((await store.read())['domains']['example']['cursor'], 'c1');
  });

  test('one record update writes only that record and its domain metadata',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.applyPage('example', {
      'records': [record('a', 1), record('b', 1)],
      'next_cursor': 'c1',
      'policy_version': DomainPolicy.version
    });
    await db.customStatement('CREATE TABLE write_audit(key TEXT, kind TEXT)');
    for (final action in ['INSERT', 'UPDATE']) {
      await db.customStatement('CREATE TRIGGER audit_$action AFTER $action '
          " ON kv_store WHEN NEW.bucket='personal_data_hub' "
          "BEGIN INSERT INTO write_audit VALUES(NEW.key,json_extract(NEW.value,'"
          r"$.kind"
          "')); END");
    }
    await store.applyPage('example', {
      'records': [record('a', 2)],
      'next_cursor': 'c2',
      'policy_version': DomainPolicy.version
    });
    final writes = await db.customSelect('SELECT kind FROM write_audit').get();
    expect(writes.map((r) => r.read<String>('kind')),
        unorderedEquals(['domain', 'record']));
    final current = (await store.read())['domains']['example'];
    expect(current['records']['b']['revision'], 1);
    expect(current['cursor'], 'c2');
    await db.customStatement('DELETE FROM write_audit');
    await store.transaction((_) async {});
    expect(await db.customSelect('SELECT * FROM write_audit').get(), isEmpty);
  });

  test(
      'corrections and pending operations occupy independent rows in durable order',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'user_direct',
        authorizationRef: 'synthetic-ui-evidence',
        fields: fields('one'));
    final rows = await physical();
    expect(rows.where((r) => r['kind'] == 'operation').single['value']['op_id'],
        op);
    expect(
        rows.where((r) => r['kind'] == 'correction').single['value']['op_id'],
        op);
    await store.prepare('example');
    await db.close();
    db = CrashDatabase(file);
    store = DomainStore(db, binding: fixtureBinding);
    final saved = (await store.read())['outbox'].single;
    expect(saved['op_id'], op);
    expect(saved['state'], 'submitting');
    expect(saved['sealed'], true);
  });

  test('feed and cursor rollback together when a row write is interrupted',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.applyPage('example', {
      'records': [record('a', 1)],
      'next_cursor': 'c1',
      'policy_version': DomainPolicy.version
    });
    final before = await store.read();
    final broken = DomainStore(db, binding: fixtureBinding, testFault: (p) {
      if (p == 'storage_row_before_commit') {
        throw StateError('synthetic interruption');
      }
    });
    await expectLater(
        broken.applyPage('example', {
          'records': [record('a', 2)],
          'next_cursor': 'c2',
          'policy_version': DomainPolicy.version
        }),
        throwsStateError);
    expect(await store.read(), before);
  });

  test(
      'phone capture keeps source/version and positive bodyless deletion evidence',
      () async {
    await store.enqueue('captures',
        id: 'local',
        kind: 'create',
        actor: 'user_direct',
        authorizationRef: 'local-ui',
        fields: {
          'data': {'text': 'private-local-original', 'source': 'phone_quick'},
          'provenance': {
            'source': 'phone_quick',
            'source_refs': [],
            'import_batch_id': null
          }
        });
    await store.enqueue('captures',
        id: 'local',
        kind: 'patch',
        actor: 'user_direct',
        authorizationRef: 'edit-ui',
        fields: {
          'patch': {'text': 'private-local-edit'}
        });
    final local =
        (await store.read())['domains']['captures']['phone_records']['local'];
    expect(local['provenance']['source'], 'phone_quick');
    expect(local['local_input_version'], 2);
    await store.enqueue('captures',
        id: 'other',
        kind: 'create',
        actor: 'user_direct',
        authorizationRef: 'other-ui',
        fields: {
          'data': {'text': 'other-kept', 'source': 'phone_quick'},
          'provenance': {
            'source': 'phone_quick',
            'source_refs': [],
            'import_batch_id': null
          }
        });
    final deletion = await store.enqueue('captures',
        id: 'local',
        kind: 'delete',
        actor: 'user_direct',
        authorizationRef: 'delete-ui',
        fields: {'permanent': true});
    final tomb =
        (await store.read())['domains']['captures']['phone_records']['local'];
    expect(tomb['local_delete_action'], deletion);
    expect(tomb['deleted_at'], isNotNull);
    expect(tomb.containsKey('data'), false);
    expect(
        (await store.visible('captures')).map((row) => row['id']), ['other']);
    await db.close();
    db = CrashDatabase(file);
    store = DomainStore(db, binding: fixtureBinding);
    final serialized = jsonEncode(await physical());
    expect(serialized.contains('private-local-original'), false);
    expect(serialized.contains('private-local-edit'), false);
    expect(serialized.contains('other-kept'), true);
    final reopened = await store.read();
    expect(
        reopened['domains']['captures']['corrections']
            .where(
                (dynamic row) => row['id'] == 'other' && row['field'] == 'text')
            .single['value'],
        'other-kept');

    await expectLater(
        store.enqueue('captures',
            id: 'local',
            kind: 'create',
            actor: 'agent_inferred',
            fields: fields('resurrection')),
        throwsA(isA<DomainFailure>()
            .having((e) => e.code, 'code', 'deleted_target')));
  });

  test(
      'dedupe suppression survives reopening and does not affect untouched domains',
      () async {
    await store.disableLocalDedupe('ledger');
    expect(await DomainRowStorage.suppressedDedupeDomains(db), {'ledger'});
    await store.configureRoute('plan_items', DomainRoute.core);
    await db.close();
    db = CrashDatabase(file);
    expect(await DomainRowStorage.suppressedDedupeDomains(db),
        {'ledger', 'plan_items'});
    expect(
        (await DomainRowStorage.suppressedDedupeDomains(db)).contains('cycle'),
        false);
  });

  for (final point in [
    'legacy_migration_before_commit',
    'legacy_migration_after_commit',
    'feed_before_commit',
    'feed_after_commit'
  ]) {
    test('real process kill at $point preserves atomic migration/feed',
        () async {
      final migrating = point.startsWith('legacy_');
      if (migrating) {
        await legacy(db, oldState());
      } else {
        await store.configureRoute('example', DomainRoute.core);
        await store.applyPage('example', {
          'records': [record('original', 1)],
          'next_cursor': 'original-cursor',
          'policy_version': DomainPolicy.version
        });
      }
      final before = migrating ? oldState() : await store.read();
      await db.close();
      await runCrashProcess(file, point, migrating ? 'migration' : 'feed');
      db = CrashDatabase(file);
      store = DomainStore(db, binding: fixtureBinding);
      final after = await store.read();
      if (point == 'feed_after_commit') {
        expect(after['domains']['example']['cursor'], 'cursor-feed-new');
        expect(after['domains']['example']['records'].containsKey('feed-new'),
            true);
      } else {
        expect(after, before);
      }
      expect((await physical()).every((r) => r['kind'] != null), true);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
