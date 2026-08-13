import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_engine.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(String, Process)> _startCore({bool seedCompanionHistory = false}) async {
  final process = await Process.start(
    'node',
    [
      'test/data/services/sync/_core_server_harness.mjs',
      '654321',
      '654322',
      if (seedCompanionHistory) 'seed-companion-history',
    ],
  );
  final url = await process.stdout
      .transform(utf8.decoder)
      .firstWhere((line) => line.trim().startsWith('http://'));
  return (url.trim(), process);
}

void main() {
  group('CoreSyncEngine', () {
    late AppDatabase db;
    late Process core;
    late String baseUrl;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DeviceIdentityService.resetForTesting();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
      final started = await _startCore();
      baseUrl = started.$1;
      core = started.$2;
    });

    tearDown(() async {
      core.kill();
      await db.close();
    });

    test(
        'submit outbox, then a second device pulls the same message via '
        'change feed', () async {
      final deviceA = await DeviceIdentityService.getOrCreate();

      // Device A pairs and writes a user message -> lands in chat + outbox.
      final pairA = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: CoreDevicePairRequest(
          deviceId: deviceA,
          displayName: 'device-a',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
        ),
      );
      final clientA = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pairA.deviceId,
        deviceToken: pairA.deviceToken,
      );
      final engineA = CoreSyncEngine(
        db: db,
        client: clientA,
        deviceId: pairA.deviceId,
        initialCursor: pairA.initialCursor,
      );
      await PersonaChatService.instance.addUserMessage('lin-ai', '我到家了');

      // Before sync, the message exists locally and in the outbox.
      var pending =
          await PersonaChatService.instance.pendingOutboxMessages(deviceA);
      expect(pending, hasLength(1));
      expect(pending.single.content, '我到家了');

      // syncOnce submits the outbox and advances the cursor.
      final submitted = await engineA.syncOnce();
      expect(submitted, 1);
      pending =
          await PersonaChatService.instance.pendingOutboxMessages(deviceA);
      expect(pending, isEmpty);

      // Device B (a second logical device) syncs from the same core with its
      // own local database copy -> receives device A's message.
      final dbB = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(dbB);
      final pairB = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: const CoreDevicePairRequest(
          deviceId: 'device-b',
          displayName: 'device-b',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654322',
        ),
      );
      final clientB = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pairB.deviceId,
        deviceToken: pairB.deviceToken,
      );
      final engineB = CoreSyncEngine(
        db: dbB,
        client: clientB,
        deviceId: pairB.deviceId,
        initialCursor: pairB.initialCursor,
      );
      await engineB.syncOnce();

      final messagesB = await dbB.select(dbB.personaChatMessages).get();
      expect(messagesB, hasLength(1));
      expect(messagesB.single.content, '我到家了');
      expect(messagesB.single.syncId, isNotNull);
      expect(messagesB.single.syncId, isNotEmpty);
      await dbB.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('cursor persists across engine rebuilds (restart recovery)', () async {
      final deviceId = await DeviceIdentityService.getOrCreate();
      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: CoreDevicePairRequest(
          deviceId: deviceId,
          displayName: 'device-a',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
        ),
      );
      final engine = CoreSyncEngine(
        db: db,
        client: CoreSyncClient(
          baseUrl: baseUrl,
          deviceId: pair.deviceId,
          deviceToken: pair.deviceToken,
        ),
        deviceId: pair.deviceId,
        initialCursor: pair.initialCursor,
      );

      await PersonaChatService.instance.addUserMessage('lin-ai', '重启前');
      await engine.syncOnce();

      // Simulate app restart: new engine instance, same database.
      final engine2 = CoreSyncEngine(
        db: db,
        client: CoreSyncClient(
          baseUrl: baseUrl,
          deviceId: pair.deviceId,
          deviceToken: pair.deviceToken,
        ),
        deviceId: pair.deviceId,
      );
      // A new message submitted after "restart" must still sync; the cursor
      // persisted by the first engine ensures no duplicate replay.
      await PersonaChatService.instance.addUserMessage('lin-ai', '重启后');
      await engine2.syncOnce();

      final messages = await db.select(db.personaChatMessages).get();
      expect(messages, hasLength(2));
      expect(messages.map((m) => m.content), containsAll(['重启前', '重启后']));
      // No duplicates from replaying the feed.
      expect(messages.map((m) => m.syncId).toSet(), hasLength(2));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('cursor state is isolated by authority core node id', () async {
      final deviceId = await DeviceIdentityService.getOrCreate();
      final client = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: deviceId,
        deviceToken: 'unused-for-cursor-storage',
      );
      final coreA = CoreSyncEngine(
        db: db,
        client: client,
        deviceId: deviceId,
        coreNodeId: 'core-a',
        initialCursor: 'initial-a',
      );
      final coreB = CoreSyncEngine(
        db: db,
        client: client,
        deviceId: deviceId,
        coreNodeId: 'core-b',
        initialCursor: 'initial-b',
      );

      await coreA.saveCursor('cursor-a-7');

      expect(await coreA.loadCursor(), 'cursor-a-7');
      expect(await coreB.loadCursor(), 'initial-b');
      await coreB.saveCursor('cursor-b-3');
      expect(await coreA.loadCursor(), 'cursor-a-7');
      expect(await coreB.loadCursor(), 'cursor-b-3');
    });

    test('pulls companion history as character messages', () async {
      core.kill();
      final seeded = await _startCore(seedCompanionHistory: true);
      baseUrl = seeded.$1;
      core = seeded.$2;

      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: const CoreDevicePairRequest(
          deviceId: 'history-reader',
          displayName: 'history-reader',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
        ),
      );
      final engine = CoreSyncEngine(
        db: db,
        client: CoreSyncClient(
          baseUrl: baseUrl,
          deviceId: pair.deviceId,
          deviceToken: pair.deviceToken,
        ),
        deviceId: pair.deviceId,
        initialCursor: pair.initialCursor,
      );

      await engine.syncOnce();

      final messages = await db.select(db.personaChatMessages).get();
      expect(messages, hasLength(1));
      expect(messages.single.syncId, 'historical-companion-1');
      expect(messages.single.isFromCharacter, isTrue);
      expect(messages.single.content, '欢迎回来。');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('syncOnce is idempotent: re-running does not duplicate messages',
        () async {
      final deviceId = await DeviceIdentityService.getOrCreate();
      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: CoreDevicePairRequest(
          deviceId: deviceId,
          displayName: 'device-a',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
        ),
      );
      final engine = CoreSyncEngine(
        db: db,
        client: CoreSyncClient(
          baseUrl: baseUrl,
          deviceId: pair.deviceId,
          deviceToken: pair.deviceToken,
        ),
        deviceId: pair.deviceId,
        initialCursor: pair.initialCursor,
      );

      await PersonaChatService.instance.addUserMessage('lin-ai', '第一条');
      await engine.syncOnce();

      // Nothing new to submit, but a second pass must not create bubbles.
      await engine.syncOnce();
      await engine.syncOnce();
      final messages = await db.select(db.personaChatMessages).get();
      expect(messages, hasLength(1));
      expect(messages.single.content, '第一条');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('duplicate response clears outbox after a lost first response',
        () async {
      final deviceId = await DeviceIdentityService.getOrCreate();
      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: CoreDevicePairRequest(
          deviceId: deviceId,
          displayName: 'device-a',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
        ),
      );
      final client = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pair.deviceId,
        deviceToken: pair.deviceToken,
      );
      final engine = CoreSyncEngine(
        db: db,
        client: client,
        deviceId: pair.deviceId,
        initialCursor: pair.initialCursor,
      );

      await PersonaChatService.instance
          .addUserMessage('lin-ai', '核心已经收到，但客户端丢了响应');
      final pending =
          await PersonaChatService.instance.pendingOutboxMessages(deviceId);
      expect(pending, hasLength(1));
      final row = pending.single;

      // Simulate the authority commit succeeding while the HTTP response is
      // lost: submit directly, but deliberately leave the local outbox row.
      final first = await client.submitMessages(CoreChatSubmitRequest(
        deviceId: deviceId,
        messages: [
          CoreChatMessageWire(
            syncId: row.syncId,
            originDeviceId: row.originDeviceId,
            originSequence: row.originSequence,
            characterId: row.characterId,
            sender: CoreMessageSender.user,
            content: row.content,
            createdAtMs: row.createdAtMs,
            messageType: row.messageType,
          ),
        ],
      ));
      expect(first.results.single.status, CoreSubmitStatus.accepted);

      // The engine retries the same immutable message, receives duplicate,
      // and must treat that as durable success instead of retrying forever.
      expect(await engine.syncOnce(), 1);
      expect(
        await PersonaChatService.instance.pendingOutboxMessages(deviceId),
        isEmpty,
      );
      expect(await db.select(db.personaChatMessages).get(), hasLength(1));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
