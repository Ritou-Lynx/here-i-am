import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/character_tools_factory.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Companion tool permissions', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('singleton I can delegate agent work and start Dev Room sessions', () {
      final toolNames = CharacterToolsFactory.buildCompanionTools(
        userId: 'user',
        characterId: 'i',
        characterName: 'I',
      ).map((tool) => tool.name);

      expect(toolNames, contains('delegate_task'));
      expect(toolNames, contains('dev_session_start_or_continue'));
    });
  });
}
