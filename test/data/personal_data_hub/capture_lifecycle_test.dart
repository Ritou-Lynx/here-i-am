import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/capture_consumer.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/db/app_database.dart';
import 'crash_worker.dart' show fixtureBinding;

OrganizedCard output(String title,
        {String? text,
        String type = 'fact',
        Map<String, dynamic>? fields,
        List<OrganizedEntityLink> links = const []}) =>
    OrganizedCard(
        type: type,
        title: title,
        dropletLabel: '测试',
        presentationModule: {'blocks': []},
        retrievalText: text ?? title,
        valence: 0,
        arousal: 0,
        structuredFieldsType: fields == null ? null : 'synthetic',
        structuredFields: fields,
        entityLinks: links);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late DomainStore store;
  late RecordOrganizerServiceV3 organizer;
  Directory? diskFixture;
  var revision = 0;
  var calls = 0;
  var cards = <OrganizedCard>[];
  Future<void> feed(int version,
      {bool deleted = false, Json? disposition}) async {
    revision++;
    await store.applyPage('captures', {
      'next_cursor': 'c$revision',
      'policy_version': DomainPolicy.version,
      'records': [
        {
          'id': 'capture-a',
          'domain': 'captures',
          'core_instance_id': 'core-test',
          'revision': revision,
          if (deleted) ...{
            'deleted_at': '2026-10-05T00:00:00.000Z',
            'body_state': 'purged'
          } else ...{
            'data': {
              'text': 'synthetic input $version',
              if (disposition != null) 'organizer': disposition
            },
            'provenance': {'source': 'claude_web'},
            'field_meta': {
              'text': {'rev': version}
            }
          }
        }
      ]
    });
  }

  CaptureConsumer consumer(
          {Future<OrganizedRecord> Function(String)? extract,
          DomainStore? using}) =>
      CaptureConsumer(
          db: db,
          store: using ?? store,
          organizer: organizer,
          extract: extract ??
              (_) async {
                calls++;
                return OrganizedRecord(cards: cards);
              },
          decodeText: (d) => d['text'] as String,
          inputVersion: (r) => r['field_meta']?['text']?['rev'] as int?);
  Future<List<MemoryCard>> saved() => db.select(db.memoryCards).get();
  Future<Json> ledger() async => jsonObject(jsonDecode((await db
          .customSelect(
              "SELECT value FROM kv_store WHERE key='capture_lifecycle.core-test.capture-a'")
          .getSingle())
      .read<String>('value')));
  setUp(() async {
    diskFixture = null;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    organizer = RecordOrganizerServiceV3(db);
    store = DomainStore(db, binding: fixtureBinding);
    revision = 0;
    calls = 0;
    cards = [output('A')];
    await store.configureRoute('captures', DomainRoute.core);
    await feed(1);
  });
  tearDown(() async {
    await db.close();
    if (diskFixture != null) await diskFixture!.delete(recursive: true);
  });

  test(
      'same capture changes version in place including type; revision only does not rerun',
      () async {
    expect(await consumer().consume(), 1);
    final original = (await saved()).single;
    await feed(1);
    expect(await consumer().consume(), 0);
    cards = [
      output('Changed', type: 'event', fields: {'amount': 12})
    ];
    await feed(2);
    expect(await consumer().consume(), 1);
    final changed = (await saved()).single;
    expect(changed.id, original.id);
    expect(changed.title, 'Changed');
    expect(changed.type, 'event');
    expect(changed.createdAt, original.createdAt);
    expect(changed.updatedAt, greaterThanOrEqualTo(original.updatedAt));
    expect(calls, 2);
    expect((await db.select(db.memoryCardSources).getSingle()).rawInput,
        'synthetic input 2');
    expect((await ledger())['input_version'], 2);
    expect(await consumer().consume(), 0); // recreated consumer, durable ledger
    expect((await store.read())['outbox'], hasLength(2));
  });

  test(
      'reorder plus pure slot additions/removals retain IDs and remove obsolete fields',
      () async {
    cards = [output('A'), output('B')];
    await consumer().consume();
    final ids = {for (final c in await saved()) c.title: c.id};
    cards = [output('B', text: 'B revised'), output('A'), output('C')];
    await feed(2);
    await consumer().consume();
    expect(await saved(), hasLength(3));
    for (final c in await saved()) {
      if (ids.containsKey(c.title)) expect(c.id, ids[c.title]);
    }
  });

  test(
      'stable titles with two cards update fields then pure remove/add without duplication',
      () async {
    cards = [
      output('A', fields: {'old': true}),
      output('B')
    ];
    await consumer().consume();
    final ids = {for (final c in await saved()) c.title: c.id};
    cards = [
      output('B', text: 'revised'),
      output('A', fields: {'new': true}),
      output('C')
    ];
    await feed(2);
    await consumer().consume();
    expect(await saved(), hasLength(3));
    final fields = await (db.select(db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(ids['A']!)))
        .getSingle();
    expect(jsonDecode(fields.fieldsJson), {'new': true});
    cards = [
      output('C'),
      output('A', fields: {'new': true})
    ];
    await feed(3);
    await consumer().consume();
    expect((await saved()).map((c) => c.title).toSet(), {'A', 'C'});
    expect((await saved()).firstWhere((c) => c.title == 'A').id, ids['A']);
    expect((await ledger())['removed_ids'], [ids['B']]);
  });

  test(
      'equal-content groups preserve both IDs and ambiguous replacement stays pending',
      () async {
    cards = [output('A'), output('A')];
    await consumer().consume();
    final ids = (await saved()).map((c) => c.id).toSet();
    await feed(2);
    await consumer().consume();
    expect((await saved()).map((c) => c.id).toSet(), ids);
    expect(await consumer().pendingIssues(), isEmpty);
    cards = [output('X'), output('Y')];
    await feed(3);
    await consumer().consume();
    expect((await saved()).map((c) => c.id).toSet(), ids);
    expect((await consumer().pendingIssues()).single['reason'],
        'output_identity_ambiguous');
    expect(await consumer().consume(), 0);
    expect((await store.read())['outbox'], hasLength(3));
  });

  test(
      'source tomb removes untouched cards and FTS; no tomb ack and no digest history',
      () async {
    await consumer().consume();
    final id = (await saved()).single.id;
    await feed(2, deleted: true);
    expect(await consumer().consume(), 1);
    expect(await saved(), isEmpty);
    expect(await db.select(db.memoryCardSources).get(), isEmpty);
    expect(
        await db.customSelect('SELECT * FROM memory_v3_fts WHERE card_id = ?',
            variables: [Variable(id)]).get(),
        isEmpty);
    final l = await ledger();
    expect(l['slots'], isEmpty);
    expect(l['removed_ids'], [id]);
    expect(jsonEncode(l), isNot(contains('snapshot')));
    expect(jsonEncode(l), isNot(contains('synthetic input')));
    expect(await consumer().consume(), 0);
    expect((await store.read())['outbox'], hasLength(1));
  });

  test(
      'user edits during extraction are preserved and tomb issues remain queryable',
      () async {
    await consumer().consume();
    final id = (await saved()).single.id;
    await feed(2);
    await consumer(extract: (_) async {
      await organizer.updateCard(id, title: 'My title', actor: 'user_direct');
      return OrganizedRecord(cards: [output('Replacement')]);
    }).consume();
    expect((await saved()).single.title, 'My title');
    expect(
        (await consumer().pendingIssues()).single['reason'], 'user_modified');
    await feed(3, deleted: true);
    await consumer().consume();
    expect((await saved()).single.title, 'My title');
    final issue = (await consumer().pendingIssues()).single;
    expect(issue['message'], contains('来源已删除'));
    expect(issue['message'], contains('你修改过'));
    expect((await ledger())['slots'], [
      {'id': id}
    ]);
    // Source quotation on a protected card is deliberately retained: clearing
    // it was not authorized by the current review scope.
    expect((await db.select(db.memoryCardSources).getSingle()).rawInput,
        'synthetic input 1');
  });

  test(
      'structured userCorrected and unexplained projection change both protect without false attribution',
      () async {
    cards = [
      output('A', fields: {'x': 1}),
      output('B')
    ];
    await consumer().consume();
    final ids = {for (final c in await saved()) c.title: c.id};
    await (db.update(db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(ids['A']!)))
        .write(const MemoryCardStructuredFieldsCompanion(
            userCorrected: Value(true)));
    await (db.update(db.memoryCards)..where((t) => t.id.equals(ids['B']!)))
        .write(const MemoryCardsCompanion(title: Value('Other change')));
    await feed(2, deleted: true);
    await consumer().consume();
    expect(await saved(), hasLength(2));
    final issues = await consumer().pendingIssues();
    expect(issues.map((i) => i['reason']).toSet(),
        {'user_modified', 'output_changed'});
    expect(issues.firstWhere((i) => i['reason'] == 'output_changed')['message'],
        contains('另有变动'));
  });

  test(
      'explicit user_via_agent edit is protected through source update and delete',
      () async {
    await consumer().consume();
    final id = (await saved()).single.id;
    await organizer.updateCard(id,
        retrievalText: 'Explicit user correction',
        actor: 'user_via_agent',
        authorizationRef: 'synthetic-user-message-sync-id');
    cards = [output('New capture')];
    await feed(2);
    await consumer().consume();
    expect((await saved()).single.retrievalText, 'Explicit user correction');
    await feed(3, deleted: true);
    await consumer().consume();
    expect((await saved()).single.id, id);
    expect(
        (await consumer().pendingIssues()).single['reason'], 'user_modified');
    final operations = await db.select(db.memoryCardOperations).get();
    expect(
        operations
            .map((o) => jsonDecode(o.payload))
            .where((p) => p['_actor'] == 'user_via_agent')
            .single['_authorization_ref'],
        'synthetic-user-message-sync-id');
  });

  test('SQLite reopen retains source identity and prevents another extraction',
      () async {
    await db.close();
    final directory =
        await Directory.systemTemp.createTemp('capture-lifecycle-');
    diskFixture = directory;
    final file = File('${directory.path}/synthetic.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(file));
    organizer = RecordOrganizerServiceV3(db);
    store = DomainStore(db, binding: fixtureBinding);
    await store.configureRoute('captures', DomainRoute.core);
    await feed(1);
    await consumer().consume();
    final id = (await saved()).single.id;
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    organizer = RecordOrganizerServiceV3(db);
    store = DomainStore(db, binding: fixtureBinding);
    expect(await consumer().consume(), 0);
    expect(calls, 1);
    await feed(2);
    cards = [output('Reopened update')];
    await consumer().consume();
    expect((await saved()).single.id, id);
  });

  for (final race in ['version', 'deleted', 'remote_done']) {
    test('extract race $race cannot persist stale or duplicate output',
        () async {
      expect(
          await consumer(extract: (_) async {
            await feed(race == 'version' ? 2 : 1,
                deleted: race == 'deleted',
                disposition: race == 'remote_done'
                    ? {
                        'status': 'done',
                        'outputs': ['remote-card'],
                        'input_revision': 1
                      }
                    : null);
            return OrganizedRecord(cards: [output('Stale')]);
          }).consume(),
          0);
      expect(await saved(), isEmpty);
      expect((await store.read())['outbox'], isEmpty);
    });
  }

  test(
      'only whole revision changes during extract still commits current input version',
      () async {
    expect(
        await consumer(extract: (_) async {
          await feed(1);
          return OrganizedRecord(cards: cards);
        }).consume(),
        1);
    expect(
        ((await store.read())['outbox'] as List).single['intent']
            ['base_revision'],
        2);
  });

  test(
      'ack fault rolls back replacement deletion creation ledger and source together',
      () async {
    cards = [output('A'), output('B')];
    await consumer().consume();
    final original = (await saved()).map((c) => c.toJson()).toList();
    final previous = await ledger();
    await feed(2);
    cards = [output('A', text: 'revised')];
    final failing = DomainStore(db, binding: fixtureBinding, testFault: (p) {
      if (p == 'enqueue_before_commit') throw StateError('fault');
    });
    await expectLater(consumer(using: failing).consume(), throwsStateError);
    expect((await saved()).map((c) => c.toJson()).toList(), original);
    expect(await ledger(), previous);
    expect((await store.read())['outbox'], hasLength(1));
    expect(await consumer().consume(), 1);
    expect(await saved(), hasLength(1));
  });

  test('deletion fault rolls back cards and retired ledger', () async {
    await consumer().consume();
    await feed(2, deleted: true);
    final failing = DomainStore(db, binding: fixtureBinding, testFault: (p) {
      if (p == 'capture_before_commit') throw StateError('fault');
    });
    await expectLater(consumer(using: failing).consume(), throwsStateError);
    expect(await saved(), hasLength(1));
    expect((await ledger())['deleted'], false);
    expect(await consumer().consume(), 1);
    expect(await saved(), isEmpty);
  });

  test(
      'cache/snapshot/permission absence and merge hiding are never deletion proof',
      () async {
    await consumer().consume();
    await store.transaction((s) async {
      final d = store.domain(s, 'captures');
      d['records'] = <String, dynamic>{};
      d['cursor'] = null;
      d['hidden_ids'] = {'capture-a': 4};
    });
    expect(await consumer().consume(), 0);
    expect(await saved(), hasLength(1));
    await store.replaceSnapshot(
        'captures', [], {'base_cursor': 'new', 'snapshot_id': 'empty'});
    expect(await consumer().consume(), 0);
    expect(await saved(), hasLength(1));
  });

  test(
      'validated GET deleted target on an ack receipt reconciles despite missing body',
      () async {
    await consumer().consume();
    final op = ((await store.read())['outbox'] as List).single['op_id'];
    await store.complete(
        op,
        {
          'domain': 'captures',
          'op_id': op,
          'outcome': 'accepted',
          'receipt': {
            'receipt_id': 'receipt-a',
            'accepted_op_id': op,
            'principal_id': 'phone-test',
            'accepted_at': '2026-10-05T00:00:00.000Z',
            'policy_version': DomainPolicy.version,
            'core_instance_id': 'core-test',
            'domain': 'captures',
            'authority_mode': 'single_host',
            'epoch': null,
            'targets': [
              {'id': 'capture-a', 'revision': 2}
            ],
            'change_sequences': [2],
            'receipt_auth': '0' * 64,
          }
        },
        targetState: 'deleted');
    expect(await consumer().consume(), 1);
    expect(await saved(), isEmpty);
    expect((await store.read())['outbox'], hasLength(1));
  });

  test(
      'old per-version ledgers collapse without copying sensitive input or duplicating outputs',
      () async {
    final old = await organizer.persist(
        organized: OrganizedRecord(cards: cards),
        source: RecordSource(
            sourceKind: 'import',
            rawInput: 'legacy source',
            sourceRef: 'captures:capture-a'));
    for (final v in [1, 2]) {
      await db.customStatement(
          'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?)', [
        'capture_consumed.core-test.capture-a.$v',
        jsonEncode({
          'capture_id': 'capture-a',
          'raw_input': 'must not copy this',
          'disposition': {'input_revision': v, 'outputs': old.cardIds}
        }),
        'capture_consumer',
        0
      ]);
    }
    await feed(2);
    expect(await consumer().consume(), 0);
    expect(await saved(), hasLength(1));
    expect((await ledger())['slots'], [
      {'id': old.cardIds.single, 'legacy': true}
    ]);
    expect(jsonEncode(await ledger()), isNot(contains('must not copy')));
    expect(
        await db
            .customSelect(
                "SELECT key FROM kv_store WHERE key LIKE 'capture_consumed.%'")
            .get(),
        isEmpty);
    await feed(3);
    await consumer().consume();
    expect((await saved()).single.id, old.cardIds.single);
    expect((await consumer().pendingIssues()).single['reason'],
        'legacy_generation_unverified');
  });

  test(
      'user-deleted output does not silently reappear and entity mention count does not grow on update',
      () async {
    final link = OrganizedEntityLink(
        name: 'Synthetic Person', category: 'person', relation: 'with');
    cards = [
      output('A', links: [link])
    ];
    await consumer().consume();
    final id = (await saved()).single.id;
    final count =
        (await db.select(db.memoryEntities).getSingle()).fragmentCount;
    await feed(2);
    cards = [
      output('A', text: 'revised', links: [link])
    ];
    await consumer().consume();
    expect(
        (await db.select(db.memoryEntities).getSingle()).fragmentCount, count);
    await organizer.deleteCard(id);
    await feed(3);
    await consumer().consume();
    expect(await saved(), isEmpty);
    expect(
        (await consumer().pendingIssues()).single['reason'], 'output_missing');
  });
}
