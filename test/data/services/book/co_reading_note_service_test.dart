import 'dart:convert';
import 'dart:io' show stderr;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/topic_thread_intent.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/data/services/book/co_reading_note_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fts5Available = _checkFts5();

  late AppDatabase db;
  late List<CoReadingRecordInput> recordInputs;
  late List<CoReadingIntentAnalysisInput> analysisInputs;
  late CoReadingNoteService service;

  setUp(() {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    recordInputs = [];
    analysisInputs = [];
    service = CoReadingNoteService(
      db,
      recordWriter: (input) async {
        recordInputs.add(input);
        return RecordPersistResult(
          cardIds: const ['card-reading-1'],
          entityIds: const [],
          assetIds: const [],
          isEmpty: false,
        );
      },
      intentAnalyzer: (input) async {
        analysisInputs.add(input);
        return const CoReadingIntentAnalysis(
          relevant: true,
          summary: '这次更在意角色获得主动选择，而不是被剧情推着走。',
          currentStage: '开始区分被拯救与主动选择的叙事张力',
          openQuestions: ['这种偏好在不同类型作品里是否一致？'],
        );
      },
    );
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('only linked reading messages become cards and a Topic Thread session',
      () async {
    if (!fts5Available) return;
    final threadId = await TopicThreadService(db: db).createThread(
      title: '角色主动性',
      openQuestions: ['旧问题仍需保留'],
    );
    await _insertBook(db, threadId: threadId);

    final handle = await service.startBookSession(
      bookId: 'book-1',
      bookTitle: '测试小说',
      characterId: 'i',
      chapterNumber: 3,
      chapterTitle: '第三章 选择',
    );
    final userMessageId = await _insertMessage(
      db,
      content: '我喜欢她这次自己做决定，不是等别人来救。',
      isFromCharacter: false,
    );
    final characterMessageId = await _insertMessage(
      db,
      content: '你在意的是她重新拿回主动权。',
      isFromCharacter: true,
    );
    final unrelatedMessageId = await _insertMessage(
      db,
      content: '晚上记得拿快递。',
      isFromCharacter: false,
    );
    await service.recordMessages(
      sessionId: handle.id,
      messageIds: [userMessageId, characterMessageId],
    );
    await service.finishSession(handle.id, processNow: false);

    final result = await service.processSession(handle.id);

    expect(result.cardIds, ['card-reading-1']);
    expect(result.threadSessionIds, hasLength(1));
    expect(recordInputs, hasLength(1));
    expect(recordInputs.single.messageIds, [userMessageId, characterMessageId]);
    expect(recordInputs.single.transcript, contains('自己做决定'));
    expect(recordInputs.single.transcript, isNot(contains('拿快递')));
    expect(recordInputs.single.messageIds, isNot(contains(unrelatedMessageId)));
    expect(analysisInputs.single.intent.threadId, threadId);

    final topicSession = (await db.select(db.topicThreadSessions).get()).single;
    expect(topicSession.summary, contains('主动选择'));
    expect(topicSession.linkedCardIds, contains('card-reading-1'));
    expect(topicSession.sourceRefJson, contains(handle.id));
    final sourceRef =
        Map<String, dynamic>.from(jsonDecode(topicSession.sourceRefJson));
    expect(sourceRef['messageIds'], [userMessageId, characterMessageId]);
    expect(sourceRef['messageIds'], isNot(contains(unrelatedMessageId)));

    final thread = await TopicThreadService(db: db).getThread(threadId);
    expect(thread!.currentStage, contains('主动选择'));
    final questions =
        TopicThreadService.decodeListPublic(thread.openQuestionsJson);
    expect(questions, contains('旧问题仍需保留'));
    expect(questions, contains('这种偏好在不同类型作品里是否一致？'));

    final continuity = await service.buildContinuityContext(
      workType: 'book',
      workId: 'book-1',
    );
    expect(continuity, contains('角色主动性'));
    expect(continuity, contains('这次更在意角色获得主动选择'));
  });

  test('a session without linked user messages is closed without writing',
      () async {
    if (!fts5Available) return;
    final threadId =
        await TopicThreadService(db: db).createThread(title: '叙事节奏');
    await _insertBook(db, threadId: threadId);
    final handle = await service.startBookSession(
      bookId: 'book-1',
      bookTitle: '测试小说',
      characterId: 'i',
      chapterNumber: 1,
      chapterTitle: '第一章',
    );

    await service.finishSession(handle.id, processNow: false);
    final result = await service.processSession(handle.id);

    expect(result.messageCount, 0);
    expect(recordInputs, isEmpty);
    expect(analysisInputs, isEmpty);
    expect(await db.select(db.topicThreadSessions).get(), isEmpty);
    final row = await (db.select(db.coReadingSessions)
          ..where((session) => session.id.equals(handle.id)))
        .getSingle();
    expect(row.status, 'processed');
  });

  test('intent analysis accepts fenced JSON and limits open questions', () {
    final analysis = CoReadingIntentAnalysis.parse('''```json
{"relevant":true,"summary":"有推进","current_stage":"新阶段","open_questions":["一","二","三","四"]}
```''');
    expect(analysis.relevant, isTrue);
    expect(analysis.summary, '有推进');
    expect(analysis.openQuestions, ['一', '二', '三']);
  });
}

Future<void> _insertBook(AppDatabase db, {required String threadId}) async {
  final intents = TopicThreadIntentItem.encodeList([
    TopicThreadIntentItem(threadId: threadId, threadTitle: '角色主动性'),
  ]);
  await db.into(db.books).insert(
        BooksCompanion.insert(
          id: 'book-1',
          characterId: 'i',
          title: '测试小说',
          createdAt: 1,
          updatedAt: 1,
          intentsJson: Value(intents),
        ),
      );
}

Future<int> _insertMessage(
  AppDatabase db, {
  required String content,
  required bool isFromCharacter,
}) {
  return db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: 'i',
          isFromCharacter: isFromCharacter,
          content: content,
          timestamp: DateTime(2026, 8, 10, 12),
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
    stderr.writeln('FTS5 unavailable; co-reading continuity tests skipped.');
    return false;
  }
}
