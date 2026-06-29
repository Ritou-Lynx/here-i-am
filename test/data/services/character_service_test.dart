import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
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
      AppFlavor.init('global');
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

    test('create and update return display-ready media paths', () async {
      const userId = 'display-ready-media';
      final mediaDir = p.join(
        FileSystemService.instance.getWorkspacePath(userId),
        '_System',
        'media',
      );
      await Directory(mediaDir).create(recursive: true);
      final avatar = File(p.join(mediaDir, 'avatar.png'));
      final background = File(p.join(mediaDir, 'background.jpg'));
      await avatar.writeAsBytes([1]);
      await background.writeAsBytes([2]);

      final avatarRelative =
          FileSystemService.instance.toRelativePath(avatar.path);
      final backgroundRelative =
          FileSystemService.instance.toRelativePath(background.path);

      final created = await CharacterService.instance.createCharacter(
        userId: userId,
        characterData: {
          'name': 'I',
          'tags': <String>[],
          'persona': '',
          'avatar': avatarRelative,
          'chat_background': backgroundRelative,
        },
      );

      expect(p.isAbsolute(created.avatar!), isTrue);
      expect(p.isAbsolute(created.chatBackground!), isTrue);
      expect(p.normalize(created.avatar!), p.normalize(avatar.path));
      expect(
        p.normalize(created.chatBackground!),
        p.normalize(background.path),
      );

      final updated = await CharacterService.instance.updateCharacter(
        userId: userId,
        characterId: created.id,
        updates: {
          'avatar': avatarRelative,
          'chat_background': backgroundRelative,
        },
      );

      expect(updated, isNotNull);
      expect(p.isAbsolute(updated!.avatar!), isTrue);
      expect(p.isAbsolute(updated.chatBackground!), isTrue);
      expect(p.normalize(updated.avatar!), p.normalize(avatar.path));
      expect(
        p.normalize(updated.chatBackground!),
        p.normalize(background.path),
      );
    });

    test('hereIAmV3 seeds only singleton I as primary companion', () async {
      AppFlavor.init('hereIAmV3');

      final characters =
          await CharacterService.instance.getAllCharacters('new-v3-user');

      expect(characters, hasLength(1));
      expect(characters.single.id, 'i');
      expect(characters.single.name, 'I');
      expect(characters.single.persona, isEmpty);
      expect(characters.single.enabled, isTrue);
      expect(characters.single.isPrimaryCompanion, isTrue);
    });

    test('hereIAmV3 ignores stale legacy characters and keeps I enabled',
        () async {
      AppFlavor.init('hereIAmV3');
      const userId = 'stale-v3-user';
      final charactersPath =
          CharacterService.instance.getCharactersPath(userId);
      await Directory(charactersPath).create(recursive: true);
      await File(p.join(charactersPath, '2.yaml')).writeAsString('''
name: Legacy
tags: []
persona: old default
avatar: "2"
enabled: true
is_primary_companion: true
''');
      await File(p.join(charactersPath, 'i.yaml')).writeAsString('''
name: Old I
tags: []
persona: ""
avatar: custom/avatar.png
enabled: false
chat_background: custom/background.jpg
''');

      final characters = await CharacterService.instance.getAllCharacters(
        userId,
      );
      final primary = await CharacterService.instance.getPrimaryCompanion(
        userId,
      );

      expect(characters.map((character) => character.id), ['i']);
      expect(primary, isNotNull);
      expect(primary!.id, 'i');
      expect(primary.enabled, isTrue);
      expect(primary.isPrimaryCompanion, isTrue);
      expect(p.normalize(primary.avatar!),
          endsWith(p.join('custom', 'avatar.png')));
      expect(
        p.normalize(primary.chatBackground!),
        endsWith(p.join('custom', 'background.jpg')),
      );
    });
  });
}
