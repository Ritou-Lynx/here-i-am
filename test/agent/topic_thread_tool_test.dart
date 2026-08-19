import 'dart:convert';
import 'dart:io' show stderr;

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/topic_thread_tool.dart';
import 'package:memex/data/memory_v3/services/topic_thread_chat_context_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fts5Available = _checkFts5();
  late AppDatabase db;

  setUp(() {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('recall anchors and append writes back without creating a duplicate',
      () async {
    if (!fts5Available) return;
    final create = buildTopicThreadCreateTool();
    final created = await _run(create, {'title': '秋招'});
    final duplicate = await _run(create, {'title': ' 秋 招 '});
    expect(created['success'], isTrue);
    expect(duplicate['reason'], 'existing_thread');
    expect(await db.select(db.topicThreads).get(), hasLength(1));

    await _insertMessage(db, '接着聊秋招', false);
    final recall = buildTopicThreadRecallTool(
      characterId: 'i',
      currentUserMessageId: 1,
    );
    final recalled = await _run(recall, {'query': '秋招'});
    expect(recalled['found'], isTrue);
    expect(
      (await TopicThreadChatContextService(db: db).load('i'))?.threadId,
      created['thread_id'],
    );

    await _insertMessage(db, '我们接着上次的选择聊。', true);
    await _insertMessage(db, '我更倾向成长空间大的岗位。', false);
    await _insertMessage(db, '那就把成长空间放在筛选条件前面。', true);
    await _insertMessage(db, '整理到这个话题里', false);

    final append = buildTopicThreadAppendSessionTool(
      characterId: 'i',
      characterName: '林埃',
      currentUserMessageId: 5,
      client: _FakeLLMClient('秋招筛选更看重成长空间。'),
      modelConfig: ModelConfig(model: 'fake'),
    );
    final appended = await _run(append, {'close_after_save': true});

    expect(appended['success'], isTrue);
    expect(appended['thread_id'], created['thread_id']);
    expect(appended['message_count'], 3);
    expect(await db.select(db.topicThreads).get(), hasLength(1));
    expect(await db.select(db.topicThreadSessions).get(), hasLength(1));
    expect(await TopicThreadChatContextService(db: db).load('i'), isNull);
  });

  test('append without an active thread never creates one', () async {
    if (!fts5Available) return;
    await _insertMessage(db, '整理到这个话题里', false);
    final append = buildTopicThreadAppendSessionTool(
      characterId: 'i',
      characterName: '林埃',
      currentUserMessageId: 1,
      client: _FakeLLMClient('不会调用'),
      modelConfig: ModelConfig(model: 'fake'),
    );

    final result = await _run(append, const {});
    expect(result['success'], isFalse);
    expect(result['reason'], 'no_active_thread');
    expect(await db.select(db.topicThreads).get(), isEmpty);
  });
}

Future<void> _insertMessage(
  AppDatabase db,
  String content,
  bool isFromCharacter,
) async {
  await db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: 'i',
          isFromCharacter: isFromCharacter,
          content: content,
          timestamp: DateTime(2026, 8, 18, 20),
          messageType: const Value('chat'),
        ),
      );
}

Future<Map<String, dynamic>> _run(
  Tool tool,
  Map<String, dynamic> args,
) async {
  final output = await tool.executable!(args) as String;
  return Map<String, dynamic>.from(jsonDecode(output) as Map);
}

bool _checkFts5() {
  try {
    final db = sqlite3.sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; TopicThread tool tests skipped.');
    return false;
  }
}

class _FakeLLMClient extends LLMClient {
  _FakeLLMClient(this.text);

  final String text;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    dynamic cancelToken,
  }) async {
    return ModelMessage(model: modelConfig.model, textOutput: text);
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    dynamic cancelToken,
  }) async {
    return const Stream.empty();
  }
}
