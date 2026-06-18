import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('PersonaChatService', () {
    late AppDatabase db;
    late PersonaChatService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
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
      expect(messages.single.messageType, 'chat');
      expect(
        messages.single.content,
        '*\u5979\u8f7b\u8f7b\u504f\u8fc7\u5934,'
        '\u770b\u7740\u4f60\u3002* \u6211\u5728\u5462\u3002',
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
  });
}
