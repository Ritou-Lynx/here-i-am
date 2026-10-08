import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/capture_consumer.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/quick_capture_domain_adapter.dart';
import 'package:memex/data/personal_data_hub/quick_capture_service.dart';
import 'crash_worker.dart' show fixtureBinding;
import 'capture_lifecycle_test.dart' show output;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late DomainStore store;
  late CaptureConsumer consumer;
  late QuickCaptureDomainAdapter adapter;
  var extractions = 0;
  void connect() {
    db = AppDatabase.forTesting(
      NativeDatabase(File('${dir.path}/capture.sqlite')),
    );
    store = DomainStore(db, binding: fixtureBinding);
    consumer = CaptureConsumer(
      db: db,
      store: store,
      organizer: RecordOrganizerServiceV3(db),
      extract: (text) async {
        extractions++;
        return OrganizedRecord(
          cards: [
            output('午饭', text: text),
            output('买牛奶', type: 'task'),
          ],
        );
      },
      decodeText: (data) => data['text'] as String,
      inputVersion: (row) => row['field_meta']?['text']?['rev'] as int?,
    );
    adapter = QuickCaptureDomainAdapter(store: store, consumer: consumer);
  }

  setUp(() {
    extractions = 0;
    dir = Directory.systemTemp.createTempSync('w4-synthetic-');
    connect();
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
      'core offline processes one signed record and blocks dependent re-signing',
      () async {
    await store.configureRoute('captures', DomainRoute.core);
    adapter = QuickCaptureDomainAdapter(
        store: store,
        consumer: consumer,
        issueAuthorization: (_) async => 'synthetic-evidence');
    final draft = QuickCaptureService(submit: adapter.submit).newDraft('午饭30元');
    await adapter.submit(draft);
    expect(await consumer.consume(), 1);
    expect(await consumer.consume(), 0);
    expect(await db.select(db.memoryCards).get(), hasLength(1));
    expect(((await store.read())['outbox'] as List).single['intent']['kind'],
        'create');
    await expectLater(
      adapter.submit(draft.copyWith(text: '午饭35元')),
      throwsA(
        isA<DomainFailure>().having(
          (failure) => failure.code,
          'code',
          'causal_predecessor_unresolved',
        ),
      ),
    );
    expect(await consumer.consume(), 0);
    expect(extractions, 1);
    expect(await db.select(db.memoryCards).get(), hasLength(1));
    expect((await store.read())['outbox'], hasLength(1));
  });

  test('local deletion protects user edited card and reports issue', () async {
    final draft = QuickCaptureService(submit: adapter.submit).newDraft('午饭30元');
    await adapter.submit(draft);
    await consumer.consume();
    final card = await db.select(db.memoryCards).getSingle();
    await (db.update(db.memoryCards)..where((t) => t.id.equals(card.id)))
        .write(const MemoryCardsCompanion(title: Value('用户改过标题')));
    await store.enqueue('captures',
        id: draft.captureId!,
        kind: 'delete',
        fields: {},
        actor: 'user_direct',
        authorizationRef: 'synthetic-delete-click');
    expect(await consumer.consume(), 1);
    expect(await consumer.consume(), 0);
    expect((await db.select(db.memoryCards).getSingle()).title, '用户改过标题');
    expect(await consumer.pendingIssues(), isNotEmpty);
    await expectLater(adapter.submit(draft), throwsA(isA<DomainFailure>()));
  });

  test('positive local delete removes untouched output without tombstone ack',
      () async {
    final draft = QuickCaptureService(submit: adapter.submit).newDraft('午饭30元');
    await adapter.submit(draft);
    await consumer.consume();
    await store.enqueue('captures',
        id: draft.captureId!,
        kind: 'delete',
        fields: {},
        actor: 'user_direct',
        authorizationRef: 'synthetic-delete-click');
    expect(await consumer.consume(), 1);
    expect(await db.select(db.memoryCards).get(), isEmpty);
    expect((await store.read())['outbox'], isEmpty);
  });

  test('stale core input cannot revert a newer offline card', () async {
    final draft = QuickCaptureService(submit: adapter.submit).newDraft('午饭30元');
    await adapter.submit(draft);
    await consumer.consume();
    await adapter.submit(draft.copyWith(text: '午饭35元'));
    await consumer.consume();
    await store.configureRoute('captures', DomainRoute.core);
    await store.applyPage('captures', {
      'next_cursor': 'c1',
      'policy_version': DomainPolicy.version,
      'records': [
        {
          'id': draft.captureId,
          'domain': 'captures',
          'core_instance_id': 'core-test',
          'revision': 1,
          'provenance': {'source': 'phone_quick'},
          'data': {'text': draft.text, 'source': 'phone_quick'},
          'field_meta': {
            'text': {'rev': 1}
          }
        }
      ]
    });
    expect(await consumer.consume(), 0);
    expect(extractions, 2);
    expect(
        (await db.select(db.memoryCards).getSingle()).retrievalText, '午饭35元');
  });

  test('disk transaction fault rolls back UI evidence and capture together',
      () async {
    final broken = DomainStore(db, binding: fixtureBinding, testFault: (point) {
      if (point == 'enqueue_before_commit') {
        throw StateError('synthetic disk fault');
      }
    });
    adapter = QuickCaptureDomainAdapter(store: broken);
    final draft = QuickCaptureService(submit: adapter.submit).newDraft('合成输入');
    await expectLater(adapter.submit(draft), throwsStateError);
    expect(await store.visible('captures'), isEmpty);
    expect(
        await db
            .customSelect(
                "SELECT value FROM kv_store WHERE bucket='quick_capture_authorization'")
            .get(),
        isEmpty);
  });

  test(
    'real SQLite offline save/reopen/retry/edit reconciles one life card and leaves task to planner',
    () async {
      final service = QuickCaptureService(submit: adapter.submit);
      final draft = service.newDraft('午饭30元，明天买牛奶');
      final result = await service.send(draft);
      expect(result.deliveryMessage, contains('尚未启用同步'));
      expect(await consumer.consume(), 1);
      final cardId = (await db.select(db.memoryCards).getSingle()).id;
      await db.close();
      connect();
      await adapter.submit(draft);
      expect(await consumer.consume(), 0);
      expect(extractions, 1);
      await adapter.submit(draft.copyWith(text: '午饭35元，明天买牛奶'));
      expect(await consumer.consume(), 1);
      expect((await db.select(db.memoryCards).getSingle()).id, cardId);
      expect((await store.read())['outbox'], isEmpty);
      final auth = await db
          .customSelect(
            "SELECT value FROM kv_store WHERE bucket='quick_capture_authorization'",
          )
          .get();
      expect(auth, hasLength(2));
      expect(auth.first.read<String>('value'), isNot(contains('午饭')));
      final shown = await adapter.readResult(draft.captureId!);
      expect(shown.organizerOutputs, [cardId]);
      expect(shown.plannerOutputs, isEmpty);
    },
  );
  test(
    'core missing issuer fails closed; trusted issuer queues a single stable operation',
    () async {
      await store.configureRoute('captures', DomainRoute.core);
      final draft = QuickCaptureService(
        submit: adapter.submit,
      ).newDraft('合成记录');
      await expectLater(adapter.submit(draft), throwsA(isA<DomainFailure>()));
      expect((await store.read())['outbox'], isEmpty);
      Json? evidence;
      adapter = QuickCaptureDomainAdapter(
        store: store,
        issueAuthorization: (e) async {
          evidence = e;
          return 'fixture-verified-action';
        },
      );
      await adapter.submit(draft);
      await adapter.submit(draft);
      final pending = ((await store.read())['outbox'] as List).single;
      expect(pending['intent']['actor'], 'user_direct');
      expect(pending['intent']['data']['source'], 'phone_quick');
      expect(evidence!['surface'], 'quick_capture_send');
      final unsignedIntent = evidence!['intent'] as Map<String, dynamic>;
      expect(unsignedIntent['op_id'], pending['op_id']);
      expect(unsignedIntent['base_revision'], 0);
      expect(unsignedIntent['created_at'], isNotEmpty);
      expect(unsignedIntent['expires_at'], isNotEmpty);
      expect(unsignedIntent.containsKey('authorization_ref'), isFalse);
      expect(
        (await adapter.authorizationEvidence(
          'fixture-verified-action',
        )),
        allOf(
          containsPair('op_id', pending['op_id']),
          containsPair('intent_sha256', domainDigest(unsignedIntent)),
        ),
      );
    },
  );
  test('signed final intent survives reopen and prepare without base rewrite',
      () async {
    await store.configureRoute('captures', DomainRoute.core);
    var issued = 0;
    adapter = QuickCaptureDomainAdapter(
      store: store,
      issueAuthorization: (_) async {
        issued++;
        return 'fixture-sealed-action';
      },
    );
    final draft =
        QuickCaptureService(submit: adapter.submit).newDraft('不可自动重签的合成记录');
    await adapter.submit(draft);
    final before = ((await store.read())['outbox'] as List).single;
    final immutableIntent = copyJson(before['intent'] as Json);
    expect(before['authorization_sealed'], isTrue);

    await db.close();
    connect();
    adapter = QuickCaptureDomainAdapter(
      store: store,
      issueAuthorization: (_) async {
        issued++;
        return 'unexpected-second-signature';
      },
    );
    final reopened = ((await store.read())['outbox'] as List).single;
    expect(reopened['authorization_sealed'], isTrue);
    final prepared = await store.prepare('captures');
    expect(prepared!['query_first'], isFalse);
    expect(prepared['intent'], immutableIntent);
    await expectLater(
      adapter.submit(draft.copyWith(text: '不允许变更 base 后重签')),
      throwsA(
        isA<DomainFailure>().having(
          (failure) => failure.code,
          'code',
          'causal_predecessor_unresolved',
        ),
      ),
    );
    expect(issued, 1);
  });
  test(
    'local output promoted to core acks existing card without extraction',
    () async {
      final draft = QuickCaptureService(
        submit: adapter.submit,
      ).newDraft('午饭30元');
      await adapter.submit(draft);
      await consumer.consume();
      final cardId = (await db.select(db.memoryCards).getSingle()).id;
      await store.configureRoute('captures', DomainRoute.core);
      await store.applyPage('captures', {
        'next_cursor': 'c1',
        'policy_version': DomainPolicy.version,
        'records': [
          {
            'id': draft.captureId,
            'domain': 'captures',
            'core_instance_id': 'core-test',
            'revision': 1,
            'provenance': {'source': 'phone_quick'},
            'data': {'text': draft.text, 'source': 'phone_quick'},
            'field_meta': {
              'text': {'rev': 1},
            },
          },
        ],
      });
      expect(await consumer.consume(), 1);
      expect(extractions, 1);
      expect((await db.select(db.memoryCards).getSingle()).id, cardId);
      final ack = ((await store.read())['outbox'] as List).single;
      expect(ack['intent']['disposition']['organizer']['outputs'], [cardId]);
      expect(await consumer.consume(), 0);
    },
  );
}
