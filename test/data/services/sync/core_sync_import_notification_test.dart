import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_engine.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

CoreChangeEvent event(String id, int sequence,
        {String character = 'i',
        String sender = 'companion',
        String type = 'chat'}) =>
    CoreChangeEvent(
      eventId: 'event-$id',
      serverSequence: sequence,
      kind: 'chat.message.upsert',
      entityId: id,
      occurredAtMs: 1700000000000 + sequence,
      payload: {
        'sync_id': id,
        'origin_device_id': 'frontend:synthetic',
        'character_id': character,
        'sender': sender,
        'content': 'synthetic $id',
        'created_at_ms': 1700000000000 + sequence,
        'message_type': type
      },
    );

class FeedClient extends CoreSyncClient {
  FeedClient(this.pages)
      : super(
            baseUrl: 'https://unused.invalid',
            deviceId: 'phone',
            deviceToken: 'synthetic');
  final List<List<CoreChangeEvent>> pages;
  var index = 0;
  final cursors = <String>[];
  final acks = <String>[];
  @override
  Future<CoreChatTranscriptCapabilities> getTranscriptCapabilities() async =>
      const CoreChatTranscriptCapabilities.disabled();
  @override
  Future<CoreChatSubmitResponse> submitMessages(
          CoreChatSubmitRequest request) async =>
      throw StateError('Feed must not submit messages');
  @override
  Future<CoreChatSubmitResponse> submitTranscripts(
          CoreChatSubmitRequest request) async =>
      throw StateError('Feed must not submit transcripts');
  @override
  Future<CoreChangePage> fetchChanges(
      {required String cursor, int limit = 100}) async {
    cursors.add(cursor);
    final current = index++;
    if (current >= pages.length) {
      return CoreChangePage(
          events: const [], nextCursor: cursor, hasMore: false);
    }
    return CoreChangePage(
        events: pages[current],
        nextCursor: 'cursor-${current + 1}',
        hasMore: current + 1 < pages.length);
  }

  @override
  Future<void> acknowledgeCursor({required String cursor}) async {
    acks.add(cursor);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late List<String> notifications;
  late List<String> scheduled;
  late EventBusMessageHandler handler;
  CoreSyncEngine engine(FeedClient client) => CoreSyncEngine(
        db: db,
        client: client,
        deviceId: 'phone',
        initialCursor: 'initial',
        scheduleImportedChat: (database, character) async {
          expect(database, same(db));
          // Scheduler only runs after its page's newly imported rows are visible.
          expect(
              await (db.select(db.personaChatMessages)
                    ..where((t) => t.characterId.equals(character)))
                  .get(),
              isNotEmpty);
          scheduled.add(character);
        },
      );
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    notifications = [];
    scheduled = [];
    await EventBusService.instance.connect();
    handler = (message) {
      notifications
          .add((message as PersonaChatMessageAddedMessage).characterId);
    };
    EventBusService.instance
        .addHandler(EventBusMessageType.personaChatMessageAdded, handler);
  });
  tearDown(() async {
    EventBusService.instance
        .removeHandler(EventBusMessageType.personaChatMessageAdded, handler);
    await EventBusService.instance.disconnect();
    await db.close();
  });

  test(
      'new imported chat notifies and schedules once; identical feed replay does neither',
      () async {
    final client = FeedClient([
      [event('new', 1)]
    ]);
    final sync = engine(client);
    expect(await sync.syncOnce(), 0);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, ['i']);
    expect(scheduled, ['i']);
    client.index = 0;
    await sync.syncOnce();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, ['i']);
    expect(scheduled, ['i']);
    expect(await db.select(db.personaChatMessages).get(), hasLength(1));
    expect(await db.select(db.syncOutboxMessages).get(), isEmpty);
    expect(client.acks, ['cursor-1', 'cursor-1']);
  });

  test(
      'new chats coalesce by character within each page, then notify again for a new page',
      () async {
    final client = FeedClient([
      [
        event('one', 1),
        event('two', 2, sender: 'user'),
        event('other', 3, character: 'other')
      ],
      [
        event('one', 1),
        event('three', 4),
        event('four', 5),
        event('action', 6, character: 'action-only', type: 'action')
      ],
    ]);
    final sync = engine(client);
    await sync.syncOnce();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, ['i', 'other', 'i']);
    expect(scheduled, ['i', 'other', 'i']);
    expect(client.cursors, ['initial', 'cursor-1']);
    expect(await sync.loadCursor(), 'cursor-2');
    expect(client.acks, ['cursor-2']);
    expect(await db.select(db.personaChatMessages).get(), hasLength(6));
    expect(await db.select(db.syncOutboxMessages).get(), isEmpty);
    client.index = 0;
    await sync.syncOnce();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, hasLength(3));
    expect(scheduled, hasLength(3));
  });

  test(
      'own feed echo only archives server sequence and never emits an import notification',
      () async {
    await db
        .into(db.personaChatMessages)
        .insert(PersonaChatMessagesCompanion.insert(
          syncId: const Value('own'),
          originDeviceId: const Value('phone'),
          characterId: 'i',
          isFromCharacter: true,
          content: 'local body',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ));
    final client = FeedClient([
      [event('own', 9)]
    ]);
    await engine(client).syncOnce();
    await Future<void>.delayed(Duration.zero);
    final row = (await db.select(db.personaChatMessages).get()).single;
    expect(row.serverSequence, 9);
    expect(row.content, 'local body');
    expect(notifications, isEmpty);
    expect(scheduled, isEmpty);
    expect(await db.select(db.syncOutboxMessages).get(), isEmpty);
  });
}
