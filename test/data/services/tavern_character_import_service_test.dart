import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:memex/agent/memory/character_memory_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/tavern_character_import_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('TavernCharacterImportService', () {
    late Directory tempRoot;
    late String userId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      userId = 'tavern_import_${DateTime.now().microsecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_tavern_import_');
      await FileSystemService.init(tempRoot.path);
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('previews and imports JSON and PNG cards with world entries',
        () async {
      final fixtures = await _writeTavernFixtures(tempRoot);
      final service = TavernCharacterImportService.instance;

      final jsonPreview = await service.previewFromFile(
        filePath: fixtures.jsonPath,
      );
      final pngPreview = await service.previewFromFile(
        filePath: fixtures.pngPath,
      );
      expect(jsonPreview['name'], 'Fixture Companion');
      expect(pngPreview['name'], 'Fixture Companion');
      expect(jsonPreview['world_entries_count'], 1);

      final jsonCharacter = await service.importFromFile(
        userId: userId,
        filePath: fixtures.jsonPath,
      );
      final pngCharacter = await service.importFromFile(
        userId: userId,
        filePath: fixtures.pngPath,
      );
      expect(jsonCharacter.persona, contains('A steady test companion.'));
      expect(pngCharacter.avatar, isNotNull);

      final conflict = await service.detectConflicts(
        userId: userId,
        filePath: fixtures.jsonPath,
      );
      expect(conflict['has_conflict'], isTrue);

      final jsonWorldEntries = await CharacterMemoryService.instance
          .loadWorldEntries(userId, jsonCharacter.id);
      final pngWorldEntries = await CharacterMemoryService.instance
          .loadWorldEntries(userId, pngCharacter.id);
      expect(jsonWorldEntries.single['content'], 'Fixture world entry.');
      expect(pngWorldEntries.single['content'], 'Fixture world entry.');
    });

    test('rejects unsupported card formats', () async {
      final invalid = File('${tempRoot.path}/not_a_card.txt');
      await invalid.writeAsString('not a card');

      expect(
        () => TavernCharacterImportService.instance.previewFromFile(
          filePath: invalid.path,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

Future<({String jsonPath, String pngPath})> _writeTavernFixtures(
  Directory root,
) async {
  final card = {
    'spec': 'chara_card_v2',
    'data': {
      'name': 'Fixture Companion',
      'description': 'A steady test companion.',
      'personality': 'Warm and concise.',
      'scenario': 'A quiet test room.',
      'first_mes': 'I am here.',
      'mes_example': 'User: Hello\\nFixture Companion: Hey.',
      'character_book': {
        'entries': [
          {
            'keys': ['test'],
            'content': 'Fixture world entry.',
            'enabled': true,
          },
        ],
      },
    },
  };
  final jsonText = jsonEncode(card);
  final jsonFile = File('${root.path}/fixture_character.json');
  final pngFile = File('${root.path}/fixture_character.png');
  await jsonFile.writeAsString(jsonText);
  await pngFile.writeAsBytes(
    _pngWithTextChunk('chara', base64Encode(utf8.encode(jsonText))),
  );
  return (jsonPath: jsonFile.path, pngPath: pngFile.path);
}

List<int> _pngWithTextChunk(String key, String value) {
  final bytes = BytesBuilder();
  bytes.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  _addPngChunk(
    bytes,
    'tEXt',
    [...latin1.encode(key), 0, ...latin1.encode(value)],
  );
  _addPngChunk(bytes, 'IEND', const []);
  return bytes.takeBytes();
}

void _addPngChunk(BytesBuilder bytes, String type, List<int> data) {
  final length = ByteData(4)..setUint32(0, data.length);
  bytes.add(length.buffer.asUint8List());
  bytes.add(ascii.encode(type));
  bytes.add(data);
  bytes.add(const [0, 0, 0, 0]);
}
