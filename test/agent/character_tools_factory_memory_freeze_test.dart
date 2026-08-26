import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/agent/skills/character_tools_factory.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('CharacterToolsFactory legacy memory freeze', () {
    late Directory tempRoot;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      tempRoot = await Directory.systemTemp.createTemp('memex_tools_freeze_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('companion tools do not expose legacy character memory tools', () {
      final names = CharacterToolsFactory.buildCompanionTools(
        userId: 'user-a',
        characterId: 'char-a',
        characterName: 'Companion',
      ).map((tool) => tool.name);

      expect(names, isNot(contains('MemoryRead')));
      expect(names, isNot(contains('MemoryWrite')));
      expect(names, isNot(contains('MemoryEdit')));
      expect(names, isNot(contains('MemoryRemove')));
      expect(names, isNot(contains('HistorySearch')));
      expect(names, isNot(contains('UserKnowledgeQuery')));
    });
  });
}
