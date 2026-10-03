import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/fragment_extractor.dart';
import 'package:memex/data/memory_v3/models/dreaming_fragment.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_engine.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _FeedClient client;
  final scheduled = <String>[];
  final notifications = <String>[];
  void onMessage(EventBusMessage event) {
    notifications.add((event as PersonaChatMessageAddedMessage).characterId);
  }

  CoreSyncEngine engine() => CoreSyncEngine(
        db: db,
        client: client,
        deviceId: 'synthetic-phone',
        scheduleImportedChat: (database, characterId) async {
          expect(identical(database, db), isTrue);
          scheduled.add(characterId);
        },
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    client = _FeedClient();
    scheduled.clear();
    notifications.clear();
    await EventBusService.instance.connect();
    EventBusService.instance
        .addHandler(EventBusMessageType.personaChatMessageAdded, onMessage);
  });
  tearDown(() async {
    EventBusService.instance
        .removeHandler(EventBusMessageType.personaChatMessageAdded, onMessage);
    await EventBusService.instance.disconnect();
    await db.close();
  });

  test('frontend history refreshes once, enters Daily Dreaming, never submits',
      () async {
    client.events = [
      for (var n = 1; n <= 20; n++) _event(n, 1700000000000 + n)
    ];
    expect(await engine().syncOnce(), 0);
    await Future<void>.delayed(Duration.zero);
    final messages = await db.select(db.personaChatMessages).get();
    expect(messages, hasLength(20));
    expect(messages.where((row) => row.isFromCharacter), hasLength(10));
    expect(messages.every((row) => row.originDeviceId == 'frontend:claude_web'),
        isTrue);
    expect(messages.every((row) => row.messageType == 'chat' && row.isRead),
        isTrue);
    expect(scheduled, ['i']);
    expect(notifications, ['i']);
    expect(
        await DreamingSchedulerService.shouldScheduleEventDrivenBatch(
            db: db, characterId: 'i'),
        isTrue);
    final extractor = _RecordingExtractor();
    final result =
        await DreamingOrchestratorServiceV3(db).runDailyFragmentBatch(
      characterId: 'i',
      client: _NoLLM(),
      modelConfig: ModelConfig(model: 'synthetic'),
      agent: extractor,
    );
    expect(result.processedMessageCount, 20);
    expect(extractor.messages.map((row) => row.content),
        messages.map((row) => row.content));
    expect(
        extractor.messages.where((row) => row.isFromCharacter), hasLength(10));
    expect(await db.select(db.memoryCards).get(), isEmpty);
    expect(await db.select(db.syncOutboxMessages).get(), isEmpty);
    expect(client.submissions, 0);

    // A persisted-cursor restart still tolerates a server replay without side effects.
    await engine().syncOnce();
    await Future<void>.delayed(Duration.zero);
    expect(await db.select(db.personaChatMessages).get(), hasLength(20));
    expect(scheduled, ['i']);
    expect(notifications, ['i']);
    expect(client.submissions, 0);
    expect(await engine().loadCursor(), 'synthetic-cursor');
  });

  test(
      'millisecond then core sequence order survives reverse arrival and pagination',
      () async {
    client.events = [
      _event(1, 1700000000901),
      _event(3, 1700000000900),
      _event(2, 1700000000900)
    ];
    await engine().syncOnce();
    final service = PersonaChatService.instance;
    final all = await service.getMessages('i');
    expect(all.map((row) => row.serverSequence), [1, 3, 2]);
    expect(all.map((row) => row.createdAtMs),
        [1700000000901, 1700000000900, 1700000000900]);
    expect(
        (await service.getMessages('i', limit: 1, offset: 1))
            .single
            .serverSequence,
        3);
    expect(
        (await service.searchMessages('i', 'synthetic'))
            .map((row) => row.serverSequence),
        [1, 3, 2]);
    expect((await service.getLastMessage('i'))!.serverSequence, 1);
    expect(await service.countMessagesNewerThan('i', all.last), 2);
    expect(await service.countMessagesNewerThan('i', all.first), 0);
    await engine().syncOnce();
    expect((await service.getMessages('i')).map((row) => row.serverSequence),
        [1, 3, 2]);
  });

  test(
      'existing own message receives ordering metadata without duplicate or outbox',
      () async {
    final id = await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            syncId: const Value('synthetic-1'),
            originDeviceId: const Value('synthetic-phone'),
            characterId: 'i',
            isFromCharacter: false,
            content: 'synthetic original',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000123),
          ),
        );
    client.events = [_event(1, 1700000000123)];
    await engine().syncOnce();
    final row = (await db.select(db.personaChatMessages).get()).single;
    expect(row.id, id);
    expect(row.content, 'synthetic original');
    expect(row.originDeviceId, 'synthetic-phone');
    expect(row.createdAtMs, 1700000000123);
    expect(row.serverSequence, 1);
    expect(scheduled, isEmpty);
    expect(await db.select(db.syncOutboxMessages).get(), isEmpty);
    expect(client.submissions, 0);
  });
}

CoreChangeEvent _event(int sequence, int createdAtMs) => CoreChangeEvent(
      eventId: 'event-$sequence',
      serverSequence: sequence,
      kind: 'chat.message.upsert',
      entityId: 'synthetic-$sequence',
      occurredAtMs: createdAtMs,
      payload: {
        'sender': sequence.isEven ? 'companion' : 'user',
        'content': 'synthetic message $sequence',
        'character_id': 'i',
        'created_at_ms': createdAtMs,
        'origin_device_id': 'frontend:claude_web',
        'message_type': 'chat'
      },
    );

class _FeedClient extends CoreSyncClient {
  _FeedClient()
      : super(
            baseUrl: 'http://unused.invalid',
            deviceId: 'synthetic-phone',
            deviceToken: 'synthetic');
  @override
  Future<CoreChatTranscriptCapabilities> getTranscriptCapabilities() async =>
      const CoreChatTranscriptCapabilities.disabled();
  List<CoreChangeEvent> events = [];
  int submissions = 0;
  @override
  Future<CoreChangePage> fetchChanges(
          {required String cursor, int limit = 100}) async =>
      CoreChangePage(
          events: events, nextCursor: 'synthetic-cursor', hasMore: false);
  @override
  Future<void> acknowledgeCursor({required String cursor}) async {}
  @override
  Future<CoreChatSubmitResponse> submitMessages(
      CoreChatSubmitRequest request) async {
    submissions++;
    throw StateError('History import must never submit or request a reply');
  }
}

class _RecordingExtractor extends DreamingFragmentExtractorV3 {
  List<DreamingChatMessageInput> messages = [];
  @override
  Future<DreamingFragmentExtraction> extract(
      {required LLMClient client,
      required ModelConfig modelConfig,
      required List<DreamingChatMessageInput> messages,
      required DateTime now,
      List<String> existingFragmentSummaries = const []}) async {
    this.messages = messages;
    return DreamingFragmentExtraction(fragments: const []);
  }
}

class _NoLLM implements LLMClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No model calls in synthetic test');
}
