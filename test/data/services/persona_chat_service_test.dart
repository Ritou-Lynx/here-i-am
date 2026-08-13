import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('PersonaChatService', () {
    late AppDatabase db;
    late PersonaChatService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DeviceIdentityService.resetForTesting();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
      service = PersonaChatService.instance;
    });

    tearDown(() async {
      await db.close();
    });

    test('searchMessages filters by character and content', () async {
      final base = DateTime(2026, 6, 14, 9);
      await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'luna',
              isFromCharacter: false,
              content: 'coffee after lunch',
              timestamp: base,
            ),
          );
      await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'luna',
              isFromCharacter: true,
              content: 'tea before dinner',
              timestamp: base.add(const Duration(minutes: 1)),
            ),
          );
      await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'other',
              isFromCharacter: false,
              content: 'coffee elsewhere',
              timestamp: base.add(const Duration(minutes: 2)),
            ),
          );

      final results = await service.searchMessages('luna', 'coffee');

      expect(results, hasLength(1));
      expect(results.single.characterId, 'luna');
      expect(results.single.content, 'coffee after lunch');
    });

    test('countMessagesNewerThan follows chat ordering', () async {
      final base = DateTime(2026, 6, 14, 9);
      final oldId = await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'luna',
              isFromCharacter: false,
              content: 'old',
              timestamp: base,
            ),
          );
      await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'luna',
              isFromCharacter: true,
              content: 'newer',
              timestamp: base.add(const Duration(minutes: 1)),
            ),
          );
      await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'other',
              isFromCharacter: true,
              content: 'not counted',
              timestamp: base.add(const Duration(minutes: 2)),
            ),
          );
      final oldMessage = await (db.select(db.personaChatMessages)
            ..where((t) => t.id.equals(oldId)))
          .getSingle();

      final newer = await service.countMessagesNewerThan('luna', oldMessage);

      expect(newer, 1);
    });

    test('retractUserMessage deletes only user messages for the character',
        () async {
      final base = DateTime(2026, 6, 14, 9);
      final userId = await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'luna',
              isFromCharacter: false,
              content: 'mistyped',
              timestamp: base,
            ),
          );
      final characterId = await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'luna',
              isFromCharacter: true,
              content: 'reply',
              timestamp: base.add(const Duration(minutes: 1)),
            ),
          );
      final otherUserId = await db.into(db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              characterId: 'other',
              isFromCharacter: false,
              content: 'other',
              timestamp: base.add(const Duration(minutes: 2)),
            ),
          );

      expect(await service.retractUserMessage('luna', characterId), 0);
      expect(await service.retractUserMessage('luna', otherUserId), 0);
      expect(await service.retractUserMessage('luna', userId), 1);

      final messages = await db.select(db.personaChatMessages).get();
      expect(messages.map((m) => m.id),
          unorderedEquals([characterId, otherUserId]));
    });

    test('addCharacterMessage keeps inline roleplay text as one chat message',
        () async {
      final base = DateTime(2026, 6, 14, 9);

      final id = await service.addCharacterMessage(
        'luna',
        '*\u5979\u8f7b\u8f7b\u504f\u8fc7\u5934,'
            '\u770b\u7740\u4f60\u3002* \u6211\u5728\u5462\u3002',
        timestamp: base,
        isRead: true,
      );

      final messages = await service.getMessages('luna', limit: 10);

      expect(messages, hasLength(1));
      expect(messages.single.id, id);
      expect(messages.single.syncId, isNotNull);
      expect(messages.single.syncId, isNotEmpty);
      expect(messages.single.originDeviceId, isNotNull);
      expect(
        await service.getMessageBySyncId(messages.single.syncId!),
        isNotNull,
      );
      expect(messages.single.messageType, 'chat');
      expect(
        messages.single.content,
        '*\u5979\u8f7b\u8f7b\u504f\u8fc7\u5934,'
        '\u770b\u7740\u4f60\u3002* \u6211\u5728\u5462\u3002',
      );
    });

    test('new messages share one installation identity and unique sync ids',
        () async {
      await service.addUserMessage('luna', 'first');
      await service.addCharacterMessage('luna', 'second');

      final messages = await service.getMessages('luna', limit: 10);

      expect(messages, hasLength(2));
      expect(messages.map((m) => m.syncId).toSet(), hasLength(2));
      expect(messages.map((m) => m.originDeviceId).toSet(), hasLength(1));
      expect(
        messages.singleWhere((m) => m.content == 'first').originDeviceId,
        messages.singleWhere((m) => m.content == 'second').originDeviceId,
      );
    });

    test('addActionMessage still creates an explicit action message', () async {
      final base = DateTime(2026, 6, 14, 9);

      await service.addActionMessage(
        'luna',
        '*\u5979\u628a\u676f\u5b50\u5f80\u4f60\u624b\u8fb9\u63a8\u4e86\u63a8*',
        timestamp: base,
        isRead: true,
      );

      final messages = await service.getMessages('luna', limit: 10);

      expect(messages, hasLength(1));
      expect(messages.single.messageType, 'action');
      expect(
        messages.single.content,
        '*\u5979\u628a\u676f\u5b50\u5f80\u4f60\u624b\u8fb9\u63a8\u4e86\u63a8*',
      );
    });

    test('addUserMessage enqueues a pending outbox copy atomically', () async {
      final base = DateTime(2026, 6, 14, 9);
      final deviceId = await DeviceIdentityService.getOrCreate();

      final id = await service.addUserMessage('luna', 'first', timestamp: base);
      await service.addUserMessage('luna', 'second', timestamp: base);

      final chat = await service.getMessageById(id);
      final pending = await service.pendingOutboxMessages(deviceId);

      expect(pending, hasLength(2));
      expect(pending.map((m) => m.syncId), contains(chat!.syncId));
      // Strictly increasing per-device origin sequence.
      expect(pending[0].originSequence, lessThan(pending[1].originSequence));
      expect(pending.map((m) => m.originSequence).toSet(), hasLength(2));
      // Only user messages are outboxed; content and character preserved.
      expect(pending.every((m) => m.characterId == 'luna'), isTrue);
      expect(pending.map((m) => m.content), containsAll(['first', 'second']));
      expect(pending.every((m) => m.messageType == 'chat'), isTrue);
    });

    test('character messages are not enqueued to the sync outbox', () async {
      final base = DateTime(2026, 6, 14, 9);
      final deviceId = await DeviceIdentityService.getOrCreate();

      await service.addCharacterMessage('luna', 'reply from i',
          timestamp: base);
      await service.addActionMessage('luna', '*nods*', timestamp: base);

      final pending = await service.pendingOutboxMessages(deviceId);
      expect(pending, isEmpty);
    });

    test('markOutboxAccepted removes only the accepted sync_id', () async {
      final base = DateTime(2026, 6, 14, 9);
      final deviceId = await DeviceIdentityService.getOrCreate();

      await service.addUserMessage('luna', 'keep', timestamp: base);
      await service.addUserMessage('luna', 'drop', timestamp: base);

      final pending = await service.pendingOutboxMessages(deviceId);
      final drop = pending.singleWhere((m) => m.content == 'drop');
      await service.markOutboxAccepted(drop.syncId);

      final remaining = await service.pendingOutboxMessages(deviceId);
      expect(remaining, hasLength(1));
      expect(remaining.single.content, 'keep');
    });

    test('retracting a pending user message also drops its outbox copy',
        () async {
      final base = DateTime(2026, 6, 14, 9);
      final deviceId = await DeviceIdentityService.getOrCreate();

      final id = await service.addUserMessage('luna', 'oops', timestamp: base);
      await service.retractUserMessage('luna', id);

      final pending = await service.pendingOutboxMessages(deviceId);
      expect(pending, isEmpty);
    });
  });
}
