import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/shared_life_memory_tools.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late SharedLifeMemoryService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SharedLifeMemoryService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('background companions receive query only', () {
    final tools = buildSharedLifeMemoryTools(
      service: service,
      sourceCharacterId: 'char-a',
    );

    expect(tools.map((tool) => tool.name), ['LifeMemoryQuery']);
  });

  test('foreground tools create, query, complete, and undo shared records',
      () async {
    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'char-a',
            isFromCharacter: false,
            content: 'Remember that I need to buy train tickets.',
            timestamp: DateTime(2026, 6, 2, 12),
          ),
        );
    final tools = buildSharedLifeMemoryTools(
      service: service,
      sourceCharacterId: 'char-a',
      sourceMessageId: 1,
      knownTags: const ['travel', 'Shanghai'],
    );

    final create = await _runTool(tools, 'LifeMemoryCreate', {
      'entity_type': 'task',
      'title': 'Buy train tickets',
      'patch': {'summary': 'Buy tickets before Friday'},
      'tags': ['travel', 'Shanghai'],
    });
    expect(create['success'], isTrue);
    final entityId = (create['entity_ids'] as List).single as String;

    final query = await _runTool(tools, 'LifeMemoryQuery', {
      'query': 'train tickets',
    });
    final queriedEntity = (query['entities'] as List).single as Map;
    expect(queriedEntity['id'], entityId);
    expect(queriedEntity['tags'], ['travel', 'Shanghai']);

    final completed = await _runTool(tools, 'LifeMemoryComplete', {
      'entity_id': entityId,
      'patch': {'note': 'Purchased in the app'},
    });
    expect(completed['success'], isTrue);
    expect((await service.listEntities()).single.status, 'completed');

    final undone = await _runTool(tools, 'LifeMemoryUndo', {
      'entity_id': entityId,
    });
    expect(undone['success'], isTrue);
    final entity = (await service.listEntities()).single;
    expect(entity.status, 'active');
    expect(entity.state.containsKey('note'), isFalse);
  });

  test('foreground tools keep only tags from the shared tag list', () async {
    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'char-a',
            isFromCharacter: false,
            content: 'Remember that I got an offer.',
            timestamp: DateTime(2026, 6, 2, 12),
          ),
        );
    final tools = buildSharedLifeMemoryTools(
      service: service,
      sourceCharacterId: 'char-a',
      sourceMessageId: 1,
      knownTags: const ['Work', 'Emotion'],
    );

    await _runTool(tools, 'LifeMemoryCreate', {
      'entity_type': 'event',
      'title': 'Got an offer',
      'patch': {'summary': 'User got an offer'},
      'tags': ['工作', 'work', 'career', 'Emotion'],
    });

    final entity = (await service.listEntities()).single;
    expect(entity.tags, ['Work', 'Emotion']);
  });
}

Future<Map<String, dynamic>> _runTool(
  List<Tool> tools,
  String name,
  Map<String, dynamic> args,
) async {
  final tool = tools.singleWhere((candidate) => candidate.name == name);
  final output = await tool.executable!(args) as String;
  return Map<String, dynamic>.from(jsonDecode(output) as Map);
}
