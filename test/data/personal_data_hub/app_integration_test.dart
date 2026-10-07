import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/capture_consumer.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_engine.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crash_worker.dart' show fixtureBinding;

OrganizedCard card(String type) => OrganizedCard(
    type: type,
    title: 'Synthetic $type',
    dropletLabel: '合成',
    presentationModule: {'blocks': <dynamic>[]},
    retrievalText: 'synthetic life record',
    valence: 0,
    arousal: 0);

class ChatClient extends CoreSyncClient {
  ChatClient() : this._(Dio());
  ChatClient._(Dio dio)
      : super(
            baseUrl: 'http://localhost',
            deviceId: 'fixture',
            deviceToken: 'unused',
            dio: dio) {
    // Exercise the real capabilities GET and JSON parser. PR10 mode is routing
    // information; neither legacy enabled nor an owner/server grant is implied.
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capabilityRequests++;
      expect(options.method, 'GET');
      expect(options.uri.path,
          '${CoreSyncProtocol.basePath}/chat/transcript-capabilities');
      handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {'enabled': false, 'companion_upload_mode': 'pr10'}));
    }));
  }
  int capabilityRequests = 0;
  CoreChatSubmitRequest? sent;
  @override
  Future<CoreChatSubmitResponse> submitTranscripts(
          CoreChatSubmitRequest request) async =>
      throw StateError('PR10 must never use the legacy transcript uploader');
  bool forbidden = true;
  @override
  Future<CoreChatSubmitResponse> submitMessages(CoreChatSubmitRequest r) async {
    sent = r;
    if (forbidden) {
      throw const CoreSyncException(
          code: 'sender_not_allowed',
          message: 'companion permission required',
          retryable: false);
    }
    return CoreChatSubmitResponse(results: [
      for (final m in r.messages)
        CoreChatSubmitResult(
            syncId: m.syncId,
            status: CoreSubmitStatus.accepted,
            serverSequence: m.originSequence)
    ]);
  }

  @override
  Future<CoreChangePage> fetchChanges(
          {required String cursor, int limit = 100}) async =>
      const CoreChangePage(events: [], nextCursor: 'empty', hasMore: false);
  @override
  Future<void> acknowledgeCursor({required String cursor}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late RecordOrganizerServiceV3 organizer;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    SharedPreferences.setMockInitialValues({});
    DeviceIdentityService.resetForTesting();
    organizer = RecordOrganizerServiceV3(db);
  });
  tearDown(() async {
    await db.close();
  });

  test(
      'companion actual service: default off, one owner character, same queue, server refusal preserves',
      () async {
    final service = PersonaChatService.instance;
    final device = await DeviceIdentityService.getOrCreate();
    await service.addCharacterMessage('primary', 'before opt in');
    expect(await service.pendingOutboxMessages(device), isEmpty);
    final client = ChatClient();
    final engine = CoreSyncEngine(db: db, client: client, deviceId: device);
    expect(await engine.syncOnce(), 0);
    expect(client.capabilityRequests, 1);
    expect(client.sent, isNull);
    expect(await service.pendingOutboxMessages(device), isEmpty);
    await service.configureCompanionOutbox(
        deviceId: device, characterId: 'primary', enabled: true);
    await service.addCharacterMessage('other', 'must stay local');
    await service.addCharacterMessage('primary', 'synthetic reply');
    final pending = await service.pendingOutboxMessages(device);
    expect(pending, hasLength(1));
    expect(pending.single.content, 'synthetic reply');
    await expectLater(
        engine.syncOnce(),
        throwsA(isA<CoreSyncException>().having(
            (error) => error.code, 'code', 'sender_not_allowed')));
    expect(client.capabilityRequests, 2);
    expect(client.sent, isNotNull);
    expect(client.sent!.messages.single.sender, CoreMessageSender.companion);
    expect(client.sent!.toJson().containsKey('request_companion_reply'), false);
    expect(await service.pendingOutboxMessages(device), hasLength(1));
    expect((await service.pendingOutboxMessages(device)).single, pending.single);
    final refusedPayload = client.sent!.toJson();
    client.forbidden = false;
    await engine.syncOnce();
    expect(client.capabilityRequests, 3);
    expect(client.sent!.toJson(), refusedPayload);
    expect(await service.pendingOutboxMessages(device), isEmpty);
    expect((await service.getMessages('primary')), hasLength(2));
  });

  test('chat row cannot commit when companion outbox insertion fails',
      () async {
    final service = PersonaChatService.instance;
    final device = await DeviceIdentityService.getOrCreate();
    await service.configureCompanionOutbox(
        deviceId: device, characterId: 'primary', enabled: true);
    await db.customStatement(
        "CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_outbox_messages BEGIN SELECT RAISE(ABORT,'synthetic fault'); END");
    await expectLater(service.addCharacterMessage('primary', 'must rollback'),
        throwsA(anything));
    expect(await service.getMessages('primary'), isEmpty);
    expect(await service.pendingOutboxMessages(device), isEmpty);
  });

  test(
      'actual Organizer writes per-field user actor and rejects agent overwrite at latest state',
      () async {
    final saved = await organizer.persist(
        organized: OrganizedRecord(cards: [card('fact')]),
        source:
            RecordSource(sourceKind: 'record_button', rawInput: 'synthetic'));
    final id = saved.cardIds.single;
    await organizer.updateCard(id,
        title: 'user title',
        structuredFields: {'amount': 7, 'currency': 'X'},
        structuredFieldsType: 'synthetic',
        actor: 'user_direct');
    final corrections = await db.select(db.userCorrections).get();
    expect(
        corrections.map((c) => c.field),
        containsAll(
            ['title', 'structuredFields.amount', 'structuredFields.currency']));
    for (final c in corrections) {
      final row = await (db.select(db.kvStore)
            ..where((t) => t.key.equals('user_correction_actor.${c.id}')))
          .getSingle();
      expect(row.value, 'user_direct');
    }
    await expectLater(organizer.updateCard(id, title: 'automatic overwrite'),
        throwsStateError);
    expect(
        (await (db.select(db.memoryCards)..where((t) => t.id.equals(id)))
                .getSingle())
            .title,
        'user title');
    await organizer.updateCard(id, dropletLabel: '自动', actor: 'agent_inferred');
    expect(await db.select(db.userCorrections).get(),
        hasLength(corrections.length));
    await expectLater(
        organizer.updateCard(id, title: 'forged', actor: 'user_via_agent'),
        throwsArgumentError);
  });

  Future<DomainStore> seedCapture({bool version = true}) async {
    final store = DomainStore(db, binding: fixtureBinding);
    await store.configureRoute('captures', DomainRoute.core);
    await store.applyPage('captures', {
      'next_cursor': 'captures-c1',
      'policy_version': DomainPolicy.version,
      'records': [
        {
          'id': 'capture-a',
          'domain': 'captures',
          'revision': 3,
          'core_instance_id': 'core-test',
          'data': {'text': 'synthetic capture'},
          'provenance': {'source': 'claude_web'},
          'field_meta': version
              ? {
                  'text': {'rev': 2}
                }
              : <String, dynamic>{}
        }
      ]
    });
    return store;
  }

  CaptureConsumer consumer(DomainStore store,
          Future<OrganizedRecord> Function(String) extract) =>
      CaptureConsumer(
          db: db,
          store: store,
          organizer: organizer,
          extract: extract,
          decodeText: (data) => data['text'] as String,
          inputVersion: (r) => r['field_meta']?['text']?['rev'] as int?);

  test(
      'captures accepted feed -> actual Organizer -> durable IDs + bounded input version ack, exactly once',
      () async {
    final store = await seedCapture();
    var calls = 0;
    final c = consumer(store, (text) async {
      calls++;
      return OrganizedRecord(cards: [card('fact'), card('task')]);
    });
    expect(await c.consume(), 1);
    expect(await c.consume(), 0);
    expect(calls, 1);
    final cards = await db.select(db.memoryCards).get();
    expect(cards, hasLength(1));
    expect(cards.single.type, 'fact');
    final op = (await store.read())['outbox'][0];
    expect(op['intent']['base_revision'], 3);
    expect(op['intent']['disposition']['organizer']['input_revision'], 2);
    expect(
        op['intent']['disposition']['organizer']['outputs'], [cards.single.id]);
    final source = await db.select(db.memoryCardSources).getSingle();
    expect(source.sourceRef, 'captures:capture-a');
  });

  test(
      'captures missing raw-input field version cannot complete or invoke extractor',
      () async {
    final store = await seedCapture(version: false);
    var calls = 0;
    expect(
        await consumer(store, (text) async {
          calls++;
          return OrganizedRecord(cards: [card('fact')]);
        }).consume(),
        0);
    expect(calls, 0);
    expect(await db.select(db.memoryCards).get(), isEmpty);
  });

  test(
      'capture tombstone or changed input during extraction cannot persist stale outputs',
      () async {
    final store = await seedCapture();
    final c = consumer(store, (text) async {
      await store.applyPage('captures', {
        'next_cursor': 'captures-c2',
        'policy_version': DomainPolicy.version,
        'records': [
          {
            'id': 'capture-a',
            'domain': 'captures',
            'revision': 4,
            'core_instance_id': 'core-test',
            'deleted_at': '2026-10-05T00:00:00.000Z',
            'body_state': 'purged'
          }
        ]
      });
      return OrganizedRecord(cards: [card('fact')]);
    });
    expect(await c.consume(), 0);
    expect(await db.select(db.memoryCards).get(), isEmpty);
    expect((await store.read())['outbox'], isEmpty);
  });

  test(
      'capture outbox failure rolls back actual Organizer cards and dedup receipt together',
      () async {
    final seed = await seedCapture();
    final failed = DomainStore(db, binding: fixtureBinding, testFault: (p) {
      if (p == 'enqueue_before_commit') throw StateError('synthetic crash');
    });
    await expectLater(
        consumer(failed, (text) async => OrganizedRecord(cards: [card('fact')]))
            .consume(),
        throwsStateError);
    expect(await db.select(db.memoryCards).get(), isEmpty);
    final receipts = await db
        .customSelect(
            "SELECT key FROM kv_store WHERE bucket='capture_consumer'")
        .get();
    expect(receipts, isEmpty);
    expect((await seed.read())['outbox'], isEmpty);
  });
}
