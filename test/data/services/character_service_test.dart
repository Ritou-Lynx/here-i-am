import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterService default character refresh', () {
    late Directory tempRoot;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'language': 'zh'});
      await UserStorage.initL10n();
      tempRoot = await Directory.systemTemp.createTemp('memex_characters_');
      await FileSystemService.init(tempRoot.path);
    });

    tearDown(() async {
      await LocalAssetServer.stopServer();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('new defaults keep voice, routing, greeting, and examples separated',
        () async {
      final characters =
          await CharacterService.instance.getAllCharacters('new-defaults');
      final mentor = characters.firstWhere((character) => character.id == '2');

      expect(mentor.persona, contains('## Voice'));
      expect(mentor.persona, isNot(contains('## Example Dialogue')));
      expect(mentor.persona, isNot(contains('## PKM Interest Filter')));
      expect(mentor.interestFilter, isNotEmpty);
      expect(mentor.firstMessage, isNotEmpty);
      expect(mentor.postHistoryInstructions, isNotEmpty);
      expect(mentor.mesExample, isNotEmpty);
    });

    test('migration refreshes legacy defaults without overwriting user edits',
        () async {
      const userId = 'existing-defaults';
      final charactersPath =
          CharacterService.instance.getCharactersPath(userId);
      await Directory(charactersPath).create(recursive: true);
      await File(p.join(charactersPath, '.characters_seed_version'))
          .writeAsString('1');
      await File(p.join(charactersPath, '2.yaml')).writeAsString('''
name: 我的老领导
tags: [智慧, 认可, 宏观]
persona: 这是旧版智慧认可者模板。
avatar: custom/avatar.png
enabled: false
is_primary_companion: true
chat_background: custom/background.jpg
tts_voice_id: voice-custom
''');
      await File(p.join(charactersPath, '3.yaml')).writeAsString('''
name: 我自己改过的角色
tags: [自定义]
persona: 这是用户自己写的人设，不应被升级覆盖。
avatar: "18"
enabled: true
''');

      final characters =
          await CharacterService.instance.getAllCharacters(userId);
      final mentor = characters.firstWhere((character) => character.id == '2');
      final customized =
          characters.firstWhere((character) => character.id == '3');

      expect(mentor.persona, contains('偶尔深夜聊两句的老朋友'));
      expect(mentor.name, '我的老领导');
      expect(mentor.enabled, isFalse);
      expect(mentor.isPrimaryCompanion, isTrue);
      expect(
        p.normalize(mentor.avatar!),
        endsWith(p.join('custom', 'avatar.png')),
      );
      expect(
        p.normalize(mentor.chatBackground!),
        endsWith(p.join('custom', 'background.jpg')),
      );
      expect(mentor.ttsVoiceId, 'voice-custom');
      expect(mentor.interestFilter, isNotEmpty);
      expect(mentor.firstMessage, isNotEmpty);

      expect(customized.name, '我自己改过的角色');
      expect(customized.persona, '这是用户自己写的人设，不应被升级覆盖。');
      expect(
        await File(p.join(charactersPath, '.characters_seed_version'))
            .readAsString(),
        '2',
      );
    });
  });
}
