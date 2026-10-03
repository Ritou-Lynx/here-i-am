import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_engine.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const cutoff = 1700000000000;
const enabled = CoreChatTranscriptCapabilities.enabled(
  fromCreatedAtMs: cutoff,
  characterId: 'i',
);
const transportFailure = CoreSyncException(
  code: 'transport_error',
  message: 'synthetic transport failure',
  retryable: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('local companion transcript', () {
    late AppDatabase db;
    late String deviceId;
    late _TranscriptClient client;
    final service = PersonaChatService.instance;
    DateTime time(int delta) =>
        DateTime.fromMillisecondsSinceEpoch(cutoff + delta);
    CoreSyncEngine engine() => CoreSyncEngine(
          db: db,
          client: client,
          deviceId: deviceId,
          scheduleImportedChat: (_, __) async {},
        );
    Future<void> seed(String id,
        {String? origin,
        String character = 'i',
        int delta = 0,
        int? serverSequence,
        String? attachments,
        bool companion = true,
        String type = 'chat'}) async {
      await db
          .into(db.personaChatMessages)
          .insert(PersonaChatMessagesCompanion.insert(
            syncId: Value(id),
            originDeviceId: Value(origin ?? deviceId),
            characterId: character,
            isFromCharacter: companion,
            content: 'synthetic $id',
            timestamp: time(delta),
            createdAtMs: Value(cutoff + delta),
            serverSequence: Value(serverSequence),
            attachmentsJson: Value(attachments),
            messageType: Value(type),
          ));
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DeviceIdentityService.resetForTesting();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
      deviceId = await DeviceIdentityService.getOrCreate();
      client = _TranscriptClient(deviceId);
    });
    tearDown(() async {
      await db.close();
    });

    for (final target in ['queue', 'marker']) {
      test('reply, queue, sequence and marker rollback on $target failure',
          () async {
        final table = target == 'queue' ? 'sync_outbox_messages' : 'kv_store';
        final condition = target == 'queue'
            ? "NEW.sender = 'companion'"
            : "NEW.key LIKE 'companion.enqueued.%'";
        await db.customStatement(
            "CREATE TEMP TRIGGER fail_enqueue BEFORE INSERT ON $table "
            "WHEN $condition BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END");
        await expectLater(
            service.addCharacterMessage('i', 'synthetic reply',
                timestamp: time(1)),
            throwsA(anything));
        expect(await db.select(db.personaChatMessages).get(), isEmpty);
        expect(await db.select(db.syncOutboxMessages).get(), isEmpty);
        expect(await db.select(db.kvStore).get(), isEmpty);
        await db.customStatement('DROP TRIGGER fail_enqueue');
        await service.addCharacterMessage('i', 'synthetic reply',
            timestamp: time(1));
        final pending = await service.pendingOutboxMessages(deviceId);
        expect(pending.single.originSequence, 1);
        expect(pending.single.sender, 'companion');
      });
    }

    test(
        'plain replies enqueue; rich addenda, actions and empty replies stay local',
        () async {
      await service
          .addCharacterMessage('i', 'plain', timestamp: time(0), addenda: []);
      await service
          .addCharacterMessage('i', 'rich', timestamp: time(1), addenda: [
        {'kind': 'synthetic'}
      ]);
      await service.addCharacterMessage('i', '', timestamp: time(2));
      await service.addActionMessage('i', 'action', timestamp: time(3));
      expect(await db.select(db.personaChatMessages).get(), hasLength(4));
      expect(
          (await service.pendingOutboxMessages(deviceId)).map((r) => r.content),
          ['plain']);
      client.capability = enabled;
      await engine().syncOnce();
      expect(client.transcripts.single.messages.single.content, 'plain');
      expect(await service.pendingOutboxMessages(deviceId), isEmpty);
    });

    test(
        'addenda patched after enqueue stay local without starving user or feed',
        () async {
      final richId = await service.addCharacterMessage('i', 'patched rich',
          timestamp: time(0));
      final rich = (await service.pendingOutboxMessages(deviceId)).single;
      await service.updateMessageAddenda(richId, addenda: [
        {'kind': 'synthetic'}
      ]);
      await service.addUserMessage('i', 'user', timestamp: time(1));
      await service.addCharacterMessage('i', 'plain', timestamp: time(2));
      client.capability = enabled;
      client.events = [_event('web-user', 'frontend:claude_web', 'user')];
      expect(await engine().syncOnce(submitLimit: 1), 2);
      expect(client.users.single.messages.single.content, 'user');
      expect(client.transcripts.single.messages.single.content, 'plain');
      expect(await service.getMessageBySyncId('web-user'), isNotNull);
      final pending = await service.pendingOutboxMessages(deviceId);
      expect(pending.single.syncId, rich.syncId);
      expect(pending.single.originSequence, rich.originSequence);
      expect(
          await (db.select(db.kvStore)
                ..where(
                    (t) => t.key.equals('companion.enqueued.${rich.syncId}')))
              .get(),
          hasLength(1));
      await engine().syncOnce();
      expect(client.transcripts, hasLength(1));
    });

    test('user route precedes filtered eligible companions without starvation',
        () async {
      for (var i = 0; i < 4; i++) {
        await service.addCharacterMessage('i', 'old $i',
            timestamp: time(-100 + i));
      }
      await service.addCharacterMessage('other', 'other character',
          timestamp: time(0));
      await service.addUserMessage('i', 'current user', timestamp: time(1));
      await service.addCharacterMessage('i', 'current companion',
          timestamp: time(2));
      client.capability = enabled;
      expect(await engine().syncOnce(submitLimit: 1), 2);
      expect(client.calls, ['user', 'capability', 'transcript', 'feed', 'ack']);
      expect(
          client.users.single.messages.single.sender, CoreMessageSender.user);
      final reply = client.transcripts.single.messages.single;
      expect(reply.sender, CoreMessageSender.companion);
      expect(reply.originDeviceId, deviceId);
      expect(reply.content, 'current companion');
      expect(reply.assetRefs, isEmpty);
      expect(reply.addenda, isEmpty);
      expect(
          client.transcripts.single
              .toJson()
              .containsKey('request_companion_reply'),
          isFalse);
      expect(await service.pendingOutboxMessages(deviceId), hasLength(5));
    });

    for (final status in [null, 403, 404]) {
      test('disabled or HTTP $status capability preserves replies and old feed',
          () async {
        await service.addUserMessage('i', 'user', timestamp: time(1));
        await service.addCharacterMessage('i', 'reply', timestamp: time(2));
        if (status != null) {
          client.capabilityError = CoreSyncException(
              code: 'not_enabled',
              message: 'synthetic',
              retryable: false,
              statusCode: status);
        }
        client.events = [_event('web-user', 'frontend:claude_web', 'user')];
        expect(await engine().syncOnce(), 1);
        expect(client.transcripts, isEmpty);
        expect(client.calls, ['user', 'capability', 'feed', 'ack']);
        final pending = await service.pendingOutboxMessages(deviceId);
        expect(pending.single.sender, 'companion');
        expect(await service.getMessageBySyncId('web-user'), isNotNull);
      });
    }

    for (final status in [403, 404]) {
      test(
          'POST HTTP $status after enabled capability retains reply and continues feed',
          () async {
        await service.addUserMessage('i', 'user', timestamp: time(1));
        await service.addCharacterMessage('i', 'reply', timestamp: time(2));
        client.capability = enabled;
        client.transcriptError = CoreSyncException(
            code: 'not_enabled',
            message: 'synthetic',
            retryable: false,
            statusCode: status);
        client.events = [_event('web-user', 'frontend:claude_web', 'user')];
        expect(await engine().syncOnce(), 1);
        expect(
            client.calls, ['user', 'capability', 'transcript', 'feed', 'ack']);
        expect((await service.pendingOutboxMessages(deviceId)).single.sender,
            'companion');
        expect(await service.getMessageBySyncId('web-user'), isNotNull);
      });
    }

    for (final failure in [
      transportFailure,
      const CoreSyncException(
          code: 'unauthorized',
          message: 'synthetic',
          retryable: false,
          statusCode: 401),
      const CoreSyncException(
          code: 'immutable_message_conflict',
          message: 'synthetic',
          retryable: false,
          statusCode: 409)
    ]) {
      test('capability ${failure.code} fails and keeps companion queue',
          () async {
        await service.addUserMessage('i', 'user', timestamp: time(1));
        await service.addCharacterMessage('i', 'reply', timestamp: time(2));
        client.capabilityError = failure;
        await expectLater(engine().syncOnce(), throwsA(same(failure)));
        expect(client.calls, ['user', 'capability']);
        expect((await service.pendingOutboxMessages(deviceId)).single.sender,
            'companion');
      });
      test('transcript ${failure.code} fails without losing queue', () async {
        await service.addCharacterMessage('i', 'reply', timestamp: time(2));
        client.capability = enabled;
        client.transcriptError = failure;
        await expectLater(engine().syncOnce(), throwsA(same(failure)));
        expect(await service.pendingOutboxMessages(deviceId), hasLength(1));
        expect(client.calls, ['capability', 'transcript']);
      });
    }

    test('lost response retries identical immutable reply and clears duplicate',
        () async {
      await service.addCharacterMessage('i', 'reply', timestamp: time(1));
      client.capability = enabled;
      client.loseNextTranscriptResponse = true;
      await expectLater(engine().syncOnce(), throwsA(same(transportFailure)));
      final before = jsonEncode(client.transcripts.single.toJson());
      expect(await service.pendingOutboxMessages(deviceId), hasLength(1));
      await engine().syncOnce();
      expect(jsonEncode(client.transcripts.last.toJson()), before);
      expect(client.accepted, hasLength(1));
      expect(await service.pendingOutboxMessages(deviceId), isEmpty);
      await engine().syncOnce();
      expect(client.transcripts, hasLength(2));
    });

    test('accepted reply is not re-enqueued when feed fails or has not echoed',
        () async {
      await seed('local-before-upgrade');
      client.capability = enabled;
      client.feedError = transportFailure;
      await expectLater(engine().syncOnce(), throwsA(same(transportFailure)));
      expect(await service.pendingOutboxMessages(deviceId), isEmpty);
      final original = client.transcripts.single.messages.single;
      expect(original.syncId, 'local-before-upgrade');
      expect(
          (await service.getMessageBySyncId(original.syncId))!.serverSequence,
          isNull);
      client.feedError = null;
      // A fresh engine represents a later runtime pass; durable KV, not memory, owns idempotency.
      await engine().syncOnce();
      expect(client.transcripts, hasLength(1));
      expect(await service.pendingOutboxMessages(deviceId), isEmpty);
      final markers = await (db.select(db.kvStore)
            ..where(
                (t) => t.key.equals('companion.enqueued.local-before-upgrade')))
          .get();
      expect(markers, hasLength(1));
    });

    test(
        'backfill filters origin, character, cutoff, role, type and attachments',
        () async {
      await seed('eligible');
      await seed('frontend', origin: 'frontend:claude_web');
      await seed('other-device', origin: 'other-device');
      await seed('core', origin: 'core-companion:i');
      await seed('history', origin: 'v3-history-synthetic');
      await seed('old', delta: -1);
      await seed('other-character', character: 'other');
      await seed('already-on-core', serverSequence: 10);
      await seed('rich', attachments: '[{"kind":"synthetic"}]');
      await seed('user', companion: false);
      await seed('action', type: 'action');
      client.capability = enabled;
      await engine().syncOnce();
      expect(client.transcripts.single.messages.map((m) => m.syncId),
          ['eligible']);
      await engine().syncOnce();
      expect(client.transcripts, hasLength(1));
    });

    test(
        'existing companion queue backfill retains its sequence and durable marker',
        () async {
      await seed('queued');
      await db
          .into(db.syncOutboxMessages)
          .insert(SyncOutboxMessagesCompanion.insert(
            syncId: 'queued',
            originDeviceId: deviceId,
            originSequence: 42,
            characterId: 'i',
            content: 'synthetic queued',
            createdAtMs: cutoff,
            sender: const Value('companion'),
          ));
      client.capability = enabled;
      await engine().syncOnce();
      expect(client.transcripts.single.messages.single.originSequence, 42);
      await engine().syncOnce();
      expect(client.transcripts, hasLength(1));
    });

    test('feed imports never create a companion outbox even with own origin',
        () async {
      client.capability = enabled;
      client.events = [
        _event('web', 'frontend:claude_web', 'companion'),
        _event('own-echo', deviceId, 'companion'),
        _event('worker', 'core-companion:i', 'companion'),
      ];
      await engine().syncOnce();
      await engine().syncOnce();
      expect(await db.select(db.personaChatMessages).get(), hasLength(3));
      expect(await service.pendingOutboxMessages(deviceId), isEmpty);
      expect(client.users, isEmpty);
      expect(client.transcripts, isEmpty);
    });
  });

  group('transcript capability wire and transport', () {
    test('disabled needs no grant fields; enabled requires exact fields', () {
      expect(
          CoreChatTranscriptCapabilities.fromJson({'enabled': false}).enabled,
          isFalse);
      final value = CoreChatTranscriptCapabilities.fromJson(
          {'enabled': true, 'from_created_at_ms': cutoff, 'character_id': 'i'});
      expect(value.fromCreatedAtMs, cutoff);
      expect(value.characterId, 'i');
      for (final data in [
        <String, dynamic>{},
        {'enabled': true},
        {'enabled': true, 'from_created_at_ms': -1, 'character_id': 'i'},
        {'enabled': true, 'from_created_at_ms': 0, 'character_id': 'i'},
        {'enabled': true, 'from_created_at_ms': cutoff, 'character_id': ''},
      ]) {
        expect(() => CoreChatTranscriptCapabilities.fromJson(data),
            throwsFormatException);
      }
    });

    test('GET capability uses the independent authenticated route', () async {
      final adapter = _Adapter((_, __) => _json({
            'enabled': true,
            'from_created_at_ms': cutoff,
            'character_id': 'i'
          }));
      final client = _transport(adapter);
      expect((await client.getTranscriptCapabilities()).enabled, isTrue);
      expect(adapter.requests.single.path,
          endsWith('/v1/core/chat/transcript-capabilities'));
      expect(adapter.requests.single.method, 'GET');
      expect(
          adapter.requests.single.headers['Authorization'], 'Bearer synthetic');
    });

    test('POST transcript connection retry retains sender and identical body',
        () async {
      final adapter = _Adapter((options, attempt) {
        if (attempt == 1) {
          throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout);
        }
        return _json({
          'results': [
            {'sync_id': 'reply', 'status': 'duplicate', 'server_sequence': 9}
          ]
        });
      });
      final request = CoreChatSubmitRequest(deviceId: 'phone', messages: [
        const CoreChatMessageWire(
            syncId: 'reply',
            originDeviceId: 'phone',
            originSequence: 1,
            characterId: 'i',
            sender: CoreMessageSender.companion,
            content: 'synthetic',
            createdAtMs: cutoff),
      ]);
      final result = await _transport(adapter).submitTranscripts(request);
      expect(result.results.single.status, CoreSubmitStatus.duplicate);
      expect(adapter.requests, hasLength(2));
      expect(
          adapter.requests.every((r) =>
              r.method == 'POST' && r.path.endsWith('/chat/transcripts')),
          isTrue);
      expect(adapter.bodies[0], adapter.bodies[1]);
      expect(jsonDecode(adapter.bodies[0]), request.toJson());
    });
  });
}

CoreChangeEvent _event(String id, String origin, String sender) =>
    CoreChangeEvent(
      eventId: 'event-$id',
      serverSequence: 1,
      kind: 'chat.message.upsert',
      entityId: id,
      occurredAtMs: cutoff,
      payload: {
        'sync_id': id,
        'origin_device_id': origin,
        'character_id': 'i',
        'sender': sender,
        'content': 'synthetic $id',
        'created_at_ms': cutoff,
        'message_type': 'chat'
      },
    );

class _TranscriptClient extends CoreSyncClient {
  _TranscriptClient(String deviceId)
      : super(
            baseUrl: 'https://unused.invalid',
            deviceId: deviceId,
            deviceToken: 'synthetic');
  CoreChatTranscriptCapabilities capability =
      const CoreChatTranscriptCapabilities.disabled();
  CoreSyncException? capabilityError;
  CoreSyncException? transcriptError;
  CoreSyncException? feedError;
  bool loseNextTranscriptResponse = false;
  final calls = <String>[];
  final users = <CoreChatSubmitRequest>[];
  final transcripts = <CoreChatSubmitRequest>[];
  final accepted = <String, String>{};
  List<CoreChangeEvent> events = [];
  @override
  Future<CoreChatTranscriptCapabilities> getTranscriptCapabilities() async {
    calls.add('capability');
    if (capabilityError != null) throw capabilityError!;
    return capability;
  }

  @override
  Future<CoreChatSubmitResponse> submitMessages(
      CoreChatSubmitRequest request) async {
    calls.add('user');
    users.add(request);
    expect(request.messages.every((m) => m.sender == CoreMessageSender.user),
        isTrue);
    return _accept(request);
  }

  @override
  Future<CoreChatSubmitResponse> submitTranscripts(
      CoreChatSubmitRequest request) async {
    calls.add('transcript');
    transcripts.add(request);
    if (transcriptError != null) throw transcriptError!;
    final response = _accept(request);
    if (loseNextTranscriptResponse) {
      loseNextTranscriptResponse = false;
      throw transportFailure;
    }
    return response;
  }

  CoreChatSubmitResponse _accept(CoreChatSubmitRequest request) {
    return CoreChatSubmitResponse(
        results: [for (final m in request.messages) _acceptOne(m)]);
  }

  CoreChatSubmitResult _acceptOne(CoreChatMessageWire message) {
    final previous = accepted[message.syncId];
    final serialized = jsonEncode(message.toJson());
    if (previous != null) expect(serialized, previous);
    accepted[message.syncId] = serialized;
    return CoreChatSubmitResult(
        syncId: message.syncId,
        status: previous == null
            ? CoreSubmitStatus.accepted
            : CoreSubmitStatus.duplicate,
        serverSequence: accepted.length);
  }

  @override
  Future<CoreChangePage> fetchChanges(
      {required String cursor, int limit = 100}) async {
    calls.add('feed');
    if (feedError != null) throw feedError!;
    return CoreChangePage(
        events: events, nextCursor: 'synthetic-cursor', hasMore: false);
  }

  @override
  Future<void> acknowledgeCursor({required String cursor}) async {
    calls.add('ack');
  }
}

CoreSyncClient _transport(_Adapter adapter) => CoreSyncClient(
      baseUrl: 'https://synthetic.invalid',
      deviceId: 'phone',
      deviceToken: 'synthetic',
      connectionTimeoutRetryDelay: Duration.zero,
      dio: Dio(BaseOptions(headers: {'Authorization': 'Bearer synthetic'}))
        ..httpClientAdapter = adapter,
    );
ResponseBody _json(Map<String, dynamic> body) =>
    ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions, int) respond;
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    bodies.add(utf8.decode(bytes));
    return respond(options, requests.length);
  }
}
