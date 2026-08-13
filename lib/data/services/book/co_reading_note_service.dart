import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/models/topic_thread_intent.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/data/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:uuid/uuid.dart';

import 'co_reading_continuity_prompt.dart';

typedef CoReadingRecordWriter = Future<RecordResult> Function(
  CoReadingRecordInput input,
);

typedef CoReadingIntentAnalyzer = Future<CoReadingIntentAnalysis> Function(
  CoReadingIntentAnalysisInput input,
);

class CoReadingRecordInput {
  const CoReadingRecordInput({
    required this.session,
    required this.transcript,
    required this.messageIds,
  });

  final CoReadingSession session;
  final String transcript;
  final List<int> messageIds;
}

class CoReadingIntentAnalysisInput {
  const CoReadingIntentAnalysisInput({
    required this.session,
    required this.intent,
    required this.transcript,
    required this.existingContext,
  });

  final CoReadingSession session;
  final TopicThreadIntentItem intent;
  final String transcript;
  final TopicThreadContext? existingContext;
}

class CoReadingIntentAnalysis {
  const CoReadingIntentAnalysis({
    required this.relevant,
    this.summary = '',
    this.currentStage = '',
    this.openQuestions = const [],
  });

  final bool relevant;
  final String summary;
  final String currentStage;
  final List<String> openQuestions;

  static CoReadingIntentAnalysis parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('共读话题分析不是 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);
    final questions = (map['open_questions'] as List?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .take(3)
            .toList(growable: false) ??
        const <String>[];
    return CoReadingIntentAnalysis(
      relevant: map['relevant'] == true,
      summary: map['summary']?.toString().trim() ?? '',
      currentStage: map['current_stage']?.toString().trim() ?? '',
      openQuestions: questions,
    );
  }
}

class CoReadingSessionHandle {
  const CoReadingSessionHandle({
    required this.id,
    required this.continuityContext,
  });

  final String id;
  final String continuityContext;
}

class CoReadingProcessResult {
  const CoReadingProcessResult({
    required this.messageCount,
    required this.cardIds,
    required this.threadSessionIds,
  });

  final int messageCount;
  final List<String> cardIds;
  final List<String> threadSessionIds;
}

/// Owns the durable continuity loop between a reading session, Memory Cards,
/// and user-selected Topic Threads.
///
/// Unlike the old character-wide watermark, every persisted chat message is
/// explicitly linked to the exact work/chapter that produced it. This keeps
/// ordinary companion chat out of co-reading cleanup and gives every generated
/// Thread Session auditable source message ids.
class CoReadingNoteService {
  CoReadingNoteService(
    this._db, {
    CoReadingRecordWriter? recordWriter,
    CoReadingIntentAnalyzer? intentAnalyzer,
  })  : _recordWriter = recordWriter,
        _intentAnalyzer = intentAnalyzer;

  final AppDatabase _db;
  final CoReadingRecordWriter? _recordWriter;
  final CoReadingIntentAnalyzer? _intentAnalyzer;
  final _uuid = const Uuid();

  static CoReadingNoteService? _instance;
  static bool get isInitialized => _instance != null;
  static CoReadingNoteService get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('CoReadingNoteService not initialized');
    }
    return value;
  }

  static void init(AppDatabase db) {
    _instance = CoReadingNoteService(db);
  }

  static final _logger = getLogger('CoReadingNoteService');
  static const _maxMessages = 200;

  Future<CoReadingSessionHandle> startBookSession({
    required String bookId,
    required String bookTitle,
    required String characterId,
    required int chapterNumber,
    required String chapterTitle,
  }) {
    return _startSession(
      workType: 'book',
      workId: bookId,
      workTitle: bookTitle,
      characterId: characterId,
      chapterRef: '$chapterNumber',
      chapterTitle: chapterTitle,
    );
  }

  Future<CoReadingSessionHandle> startMangaSession({
    required String mangaId,
    required String mangaTitle,
    required String characterId,
    required String chapterId,
    required String chapterTitle,
  }) {
    return _startSession(
      workType: 'comic',
      workId: mangaId,
      workTitle: mangaTitle,
      characterId: characterId,
      chapterRef: chapterId,
      chapterTitle: chapterTitle,
    );
  }

  Future<CoReadingSessionHandle> _startSession({
    required String workType,
    required String workId,
    required String workTitle,
    required String characterId,
    required String chapterRef,
    required String chapterTitle,
  }) async {
    await _closeAbandonedActiveSessions(workType: workType, workId: workId);
    unawaited(processPendingForWork(workType: workType, workId: workId));

    final id = _uuid.v4();
    await _db.into(_db.coReadingSessions).insert(
          CoReadingSessionsCompanion.insert(
            id: id,
            workType: workType,
            workId: workId,
            workTitle: workTitle,
            characterId: characterId,
            chapterRef: chapterRef,
            chapterTitle: Value(chapterTitle),
            startedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

    return CoReadingSessionHandle(
      id: id,
      continuityContext: await buildContinuityContext(
        workType: workType,
        workId: workId,
      ),
    );
  }

  Future<void> recordMessages({
    required String sessionId,
    required Iterable<int> messageIds,
  }) async {
    final uniqueIds = messageIds.where((id) => id > 0).toSet();
    if (uniqueIds.isEmpty) return;
    // Resolve stable sync_ids for dual-write so co-reading membership survives
    // cross-device replication (where the local int id differs).
    final syncById = await _resolveMessageSyncIds(uniqueIds);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.batch((batch) {
      for (final messageId in uniqueIds) {
        batch.insert(
          _db.coReadingSessionMessages,
          CoReadingSessionMessagesCompanion.insert(
            sessionId: sessionId,
            messageId: messageId,
            messageSyncId: Value(syncById[messageId]),
            addedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  Future<Map<int, String>> _resolveMessageSyncIds(Iterable<int> ids) async {
    final rows = await (_db.select(_db.personaChatMessages)
          ..where((t) => t.id.isIn(ids.toSet())))
        .get();
    return {
      for (final row in rows)
        if (row.syncId != null && row.syncId!.isNotEmpty) row.id: row.syncId!,
    };
  }

  Future<CoReadingProcessResult?> finishSession(
    String sessionId, {
    bool processNow = true,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.coReadingSessions)
          ..where(
              (row) => row.id.equals(sessionId) & row.status.equals('active')))
        .write(CoReadingSessionsCompanion(
      status: const Value('ready'),
      endedAt: Value(now),
    ));
    if (!processNow) return null;
    try {
      return await processSession(sessionId);
    } catch (error, stackTrace) {
      _logger.warning(
          'Co-reading cleanup failed for $sessionId: $error', stackTrace);
      return null;
    }
  }

  Future<void> processPendingForWork({
    required String workType,
    required String workId,
  }) async {
    final pending = await (_db.select(_db.coReadingSessions)
          ..where((row) =>
              row.workType.equals(workType) &
              row.workId.equals(workId) &
              row.status.equals('ready'))
          ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]))
        .get();
    for (final session in pending) {
      try {
        await processSession(session.id);
      } catch (error, stackTrace) {
        _logger.warning(
          'Pending co-reading cleanup failed for ${session.id}: $error',
          stackTrace,
        );
      }
    }
  }

  Future<CoReadingProcessResult> processSession(String sessionId) async {
    final session = await (_db.select(_db.coReadingSessions)
          ..where((row) => row.id.equals(sessionId)))
        .getSingleOrNull();
    if (session == null) {
      throw StateError('共读会话不存在: $sessionId');
    }
    if (session.status == 'processed') {
      return const CoReadingProcessResult(
        messageCount: 0,
        cardIds: [],
        threadSessionIds: [],
      );
    }
    if (session.status != 'ready' && session.status != 'failed') {
      throw StateError('共读会话尚未结束: ${session.status}');
    }

    await (_db.update(_db.coReadingSessions)
          ..where((row) => row.id.equals(sessionId)))
        .write(const CoReadingSessionsCompanion(
      status: Value('processing'),
      error: Value(null),
    ));

    try {
      final messages = await _messagesForSession(session);
      final userMessages =
          messages.where((message) => !message.isFromCharacter);
      if (userMessages.isEmpty) {
        await _markProcessed(sessionId);
        return const CoReadingProcessResult(
          messageCount: 0,
          cardIds: [],
          threadSessionIds: [],
        );
      }

      final messageIds =
          messages.map((message) => message.id).toList(growable: false);
      final transcript = _formatTranscript(session, messages);
      final recordResult = await (_recordWriter ?? _recordWithOrganizer)(
        CoReadingRecordInput(
          session: session,
          transcript: transcript,
          messageIds: messageIds,
        ),
      );

      final intents = await _intentsFor(session);
      final threadService = TopicThreadService(db: _db);
      final threadSessionIds = <String>[];
      for (final intent in intents) {
        final context = await threadService.buildContext(intent.threadId);
        if (context == null) continue;
        final analysis = await (_intentAnalyzer ?? _analyzeIntent)(
          CoReadingIntentAnalysisInput(
            session: session,
            intent: intent,
            transcript: transcript,
            existingContext: context,
          ),
        );
        if (!analysis.relevant || analysis.summary.isEmpty) continue;
        if (await _threadAlreadyContainsSession(
          threadId: intent.threadId,
          coReadingSessionId: session.id,
        )) {
          continue;
        }

        final topicSessionId = await threadService.appendSession(
          threadId: intent.threadId,
          summary: analysis.summary,
          sourceType:
              session.workType == 'book' ? 'book_reading' : 'comic_reading',
          sourceRef: {
            'coReadingSessionId': session.id,
            'workType': session.workType,
            'workId': session.workId,
            'workTitle': session.workTitle,
            'chapterRef': session.chapterRef,
            'chapterTitle': session.chapterTitle,
            'messageIds': messageIds,
          },
          linkedCardIds: recordResult.entityIds,
          authority: 'agent_inferred',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            session.endedAt ?? session.startedAt,
          ),
        );
        threadSessionIds.add(topicSessionId);

        if (analysis.currentStage.isNotEmpty ||
            analysis.openQuestions.isNotEmpty) {
          final mergedQuestions = <String>{
            ...context.openQuestions,
            ...analysis.openQuestions,
          }.take(6).toList(growable: false);
          await threadService.updateStage(
            threadId: intent.threadId,
            currentStage:
                analysis.currentStage.isEmpty ? null : analysis.currentStage,
            openQuestions:
                analysis.openQuestions.isEmpty ? null : mergedQuestions,
          );
        }
      }

      await _markProcessed(sessionId);
      return CoReadingProcessResult(
        messageCount: messages.length,
        cardIds: recordResult.entityIds,
        threadSessionIds: threadSessionIds,
      );
    } catch (error) {
      await (_db.update(_db.coReadingSessions)
            ..where((row) => row.id.equals(sessionId)))
          .write(CoReadingSessionsCompanion(
        status: const Value('failed'),
        error: Value(error.toString()),
      ));
      rethrow;
    }
  }

  Future<String> buildContinuityContext({
    required String workType,
    required String workId,
  }) async {
    final intents = await _intentsForWork(workType: workType, workId: workId);
    if (intents.isEmpty) return '';
    final threadService = TopicThreadService(db: _db);
    final blocks = <String>[];
    for (final intent in intents) {
      final context = await threadService.buildContext(
        intent.threadId,
        recentSessions: 3,
      );
      if (context != null) blocks.add(context.toPromptBlock().trim());
    }
    if (blocks.isEmpty) return '';
    return '## 本次共读关联的长期话题\n'
        '这些话题由用户主动关联。自然接续相关的旧讨论，不要机械复述；'
        '若本轮无关则不要强行提起。\n\n${blocks.join('\n\n')}';
  }

  Future<void> _closeAbandonedActiveSessions({
    required String workType,
    required String workId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.coReadingSessions)
          ..where((row) =>
              row.workType.equals(workType) &
              row.workId.equals(workId) &
              row.status.equals('active')))
        .write(CoReadingSessionsCompanion(
      status: const Value('ready'),
      endedAt: Value(now),
    ));
  }

  Future<List<PersonaChatMessage>> _messagesForSession(
    CoReadingSession session,
  ) async {
    final links = await (_db.select(_db.coReadingSessionMessages)
          ..where((row) => row.sessionId.equals(session.id))
          ..orderBy([(row) => OrderingTerm.asc(row.messageId)]))
        .get();
    final ids = links.map((link) => link.messageId).take(_maxMessages).toList();
    if (ids.isEmpty) return const [];
    // Prefer stable sync_ids when present; fall back to legacy int ids for
    // rows written before dual-write or still awaiting backfill.
    final syncIds = links
        .map((link) => link.messageSyncId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    return (_db.select(_db.personaChatMessages)
          ..where((message) => message.characterId.equals(session.characterId) &
              message.messageType.equals('chat') &
              (syncIds.isEmpty
                  ? message.id.isIn(ids)
                  : message.syncId.isIn(syncIds)))
          ..orderBy([(message) => OrderingTerm.asc(message.id)]))
        .get();
  }

  Future<List<TopicThreadIntentItem>> _intentsFor(CoReadingSession session) {
    return _intentsForWork(
      workType: session.workType,
      workId: session.workId,
    );
  }

  Future<List<TopicThreadIntentItem>> _intentsForWork({
    required String workType,
    required String workId,
  }) async {
    if (workType == 'book') {
      final row = await (_db.select(_db.books)
            ..where((book) => book.id.equals(workId)))
          .getSingleOrNull();
      return TopicThreadIntentItem.parseList(row?.intentsJson ?? '[]');
    }
    final row = await (_db.select(_db.comicMangas)
          ..where((manga) => manga.id.equals(workId)))
        .getSingleOrNull();
    return TopicThreadIntentItem.parseList(row?.intentsJson ?? '[]');
  }

  Future<RecordResult> _recordWithOrganizer(CoReadingRecordInput input) async {
    if (!RecordOrganizerService.isInitialized) {
      return const RecordResult(entityIds: [], entityTitles: [], isEmpty: true);
    }
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      return const RecordResult(entityIds: [], entityTitles: [], isEmpty: true);
    }
    return RecordOrganizerService.instance.recordFromText(
      userId: userId,
      sourceCharacterId: input.session.characterId,
      text: input.transcript,
      sourceKind: 'co_reading',
      sourceRef: jsonEncode({
        'coReadingSessionId': input.session.id,
        'workType': input.session.workType,
        'workId': input.session.workId,
        'chapterRef': input.session.chapterRef,
      }),
      sourceMessageIds: input.messageIds,
    );
  }

  Future<CoReadingIntentAnalysis> _analyzeIntent(
    CoReadingIntentAnalysisInput input,
  ) async {
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.recordOrganizerAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    final payload = jsonEncode({
      'topic_title': input.intent.threadTitle,
      'existing_context': input.existingContext?.toPromptBlock() ?? '',
      'work': {
        'type': input.session.workType,
        'title': input.session.workTitle,
        'chapter': input.session.chapterTitle,
      },
      'transcript': input.transcript,
    });
    final response = await resources.client.generate(
      [
        SystemMessage(coReadingIntentAnalysisSystemPrompt),
        UserMessage([TextPart(payload)]),
      ],
      modelConfig: ModelConfig(
        model: resources.modelConfig.model,
        maxTokens: 768,
        extra: {
          ...?resources.modelConfig.extra,
          'thinking': {'type': 'disabled'},
        },
      ),
    );
    return CoReadingIntentAnalysis.parse(response.textOutput ?? '');
  }

  Future<bool> _threadAlreadyContainsSession({
    required String threadId,
    required String coReadingSessionId,
  }) async {
    final row = await (_db.select(_db.topicThreadSessions)
          ..where((session) =>
              session.threadId.equals(threadId) &
              session.sourceRefJson.contains(coReadingSessionId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> _markProcessed(String sessionId) {
    return (_db.update(_db.coReadingSessions)
          ..where((row) => row.id.equals(sessionId)))
        .write(CoReadingSessionsCompanion(
      status: const Value('processed'),
      processedAt: Value(DateTime.now().millisecondsSinceEpoch),
      error: const Value(null),
    ));
  }

  String _formatTranscript(
    CoReadingSession session,
    List<PersonaChatMessage> messages,
  ) {
    final buffer = StringBuffer()
      ..writeln('[共读讨论] 《${session.workTitle}》')
      ..writeln(
          '章节：${session.chapterTitle.isEmpty ? session.chapterRef : session.chapterTitle}')
      ..writeln()
      ..writeln('只整理下面这次共读会话中用户明确表达的感受、偏好、观点和问题。')
      ..writeln('---');
    for (final message in messages) {
      final role = message.isFromCharacter ? '林埃' : '用户';
      final text = message.content.trim();
      if (text.isEmpty) continue;
      final clipped = text.length > 600 ? '${text.substring(0, 600)}…' : text;
      buffer.writeln('$role: $clipped');
    }
    buffer.writeln('---');
    return buffer.toString();
  }
}
