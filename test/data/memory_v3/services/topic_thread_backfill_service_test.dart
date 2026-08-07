import 'dart:io' show stderr;

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/topic_thread_backfill_service.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fts5Available = _checkFts5();

  late AppDatabase db;
  late TopicThreadBackfillService service;

  setUp(() {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TopicThreadBackfillService(db: db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test(
      'summarizeAndAppend writes a user_confirmed session dated to the '
      'last chat message', () async {
    if (!fts5Available) return;
    await _insertMessage(
      db,
      content: '我在想换个工作方向',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 30, 9, 34),
    );
    await _insertMessage(
      db,
      content: '你现在主要纠结哪些点？',
      isFromCharacter: true,
      timestamp: DateTime(2026, 7, 30, 9, 35),
    );
    await _insertMessage(
      db,
      content: '薪资和成长路径吧',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 30, 9, 36),
    );
    await _insertMessage(
      db,
      content: '已读回执',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 30, 9, 37),
      messageType: 'action',
    );
    await _insertMessage(
      db,
      content: '   ',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 30, 9, 38),
    );

    final threadId = await TopicThreadService(db: db).createThread(title: '求职');
    final messages = await db.select(db.personaChatMessages).get();

    final result = await service.summarizeAndAppend(
      threadId: threadId,
      messages: messages,
      characterName: '林埃',
      client: _FakeLLMClient(
        '求职讨论摘要：在考虑换工作方向，纠结薪资与成长路径，尚未得出结论。',
      ),
      modelConfig: ModelConfig(model: 'fake'),
    );

    expect(result.messageCount, 3);
    expect(result.summary, contains('求职'));

    final session = (await db.select(db.topicThreadSessions).get()).single;
    expect(session.threadId, threadId);
    expect(session.summary, contains('薪资'));
    expect(session.authority, 'user_confirmed');
    expect(session.sourceType, 'chat');
    // occurredAt = last extractable chat message (id 3, 09:36) — the action
    // (id 4) and the blank message (id 5) must NOT date the session.
    expect(
      session.occurredAt,
      DateTime(2026, 7, 30, 9, 36).millisecondsSinceEpoch,
    );
    // sourceRef lists only the included chat ids.
    expect(session.sourceRefJson, contains('[1, 2, 3]'));
    expect(session.sourceRefJson, isNot(contains('4')));

    // Thread lastDiscussedAt follows the backfilled session.
    final thread = (await db.select(db.topicThreads).get()).single;
    expect(thread.lastDiscussedAt, session.occurredAt);
  });

  test('rejects when no chat messages remain after filtering', () async {
    if (!fts5Available) return;
    final threadId = await TopicThreadService(db: db).createThread(title: '求职');
    await _insertMessage(
      db,
      content: '系统动作消息',
      isFromCharacter: true,
      timestamp: DateTime(2026, 7, 30, 10),
      messageType: 'action',
    );
    final messages = await db.select(db.personaChatMessages).get();

    await expectLater(
      service.summarizeAndAppend(
        threadId: threadId,
        messages: messages,
        characterName: '林埃',
        client: _FakeLLMClient('不会用到'),
        modelConfig: ModelConfig(model: 'fake'),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('empty LLM summary surfaces as StateError, nothing is persisted',
      () async {
    if (!fts5Available) return;
    final threadId = await TopicThreadService(db: db).createThread(title: '求职');
    await _insertMessage(
      db,
      content: '一句话',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 30, 10),
    );
    final messages = await db.select(db.personaChatMessages).get();

    await expectLater(
      service.summarizeAndAppend(
        threadId: threadId,
        messages: messages,
        characterName: '林埃',
        client: _FakeLLMClient(''),
        modelConfig: ModelConfig(model: 'fake'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.select(db.topicThreadSessions).get(), isEmpty);
  });
}

Future<void> _insertMessage(
  AppDatabase db, {
  required String content,
  required bool isFromCharacter,
  required DateTime timestamp,
  String messageType = 'chat',
}) async {
  await db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: 'i',
          isFromCharacter: isFromCharacter,
          content: content,
          timestamp: timestamp,
          messageType: Value(messageType),
        ),
      );
}

bool _checkFts5() {
  try {
    final db = sqlite3.sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; TopicThreadBackfill tests skipped.');
    return false;
  }
}

class _FakeLLMClient extends LLMClient {
  _FakeLLMClient(this._text);

  final String _text;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    dynamic cancelToken,
  }) async {
    return ModelMessage(model: modelConfig.model, textOutput: _text);
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
