import 'dart:async';
import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/companion_agent/recent_activity_snapshot.dart';

import 'package:memex/agent/skills/companion_agent/companion_agent_skill.dart';
import 'package:memex/agent/state_util.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/retrieval/project_memory_intent_classifier.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/data/services/toy_control_service.dart'
    show ToyController;
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/data/services/comic/comic_reading_progress_service.dart';
import 'package:memex/data/services/book/book_library_service.dart';
import 'package:memex/data/services/comic/comic_screenplay_service.dart';

/// Thrown when a companion chat turn fails because of an API/connection error
/// (quota exhausted, timeout, 4xx/5xx from the provider) rather than a normal
/// empty response. The UI catches this to show a transient retry prompt instead
/// of persisting the raw error as a chat message (which would also pollute
/// Dreaming extraction).
class CompanionApiException implements Exception {
  CompanionApiException(this.cause, [this.stackTrace]);

  /// Full underlying error, for logs / Lab debug only — never shown to the user.
  final Object cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'CompanionApiException: $cause';
}

/// Companion chat agent implemented with StatefulAgent for architecture parity
/// with other scene agents (e.g., CommentAgent).
class CompanionAgent {
  static final Logger _logger = getLogger('CompanionAgent');

  // ---------------------------------------------------------------------------
  // Time-request detection — prevents the common LLM failure mode where it
  // replies "好的，X分钟后提醒你" in text but never calls reminder_create.
  // ---------------------------------------------------------------------------

  static const String _timeExpressionSource =
      r'(\d+\s*(?:分钟|小时|点|时|分|秒)|[一二两三四五六七八九十半]+\s*(?:分钟|小时|点|时|分|秒)|明天|后天|今晚|今早|今天晚上|上午|中午|下午|晚上|等会儿?|待会儿?|稍后|一会儿?|到时候|later|tomorrow|tonight|in\s+\d+|at\s+\d+)';

  static const String _scheduledRequestActionSource =
      r'(提醒我|叫我|喊我|通知我|问我|查岗|监督我|来找我|来问我|到点叫我|到点提醒|设(?:个|一个)?闹钟|设(?:个|一个)?提醒|闹钟|给我打电话|打电话给我|call me|remind me|wake me|ping me|check on me|ask me)';

  static const String _scheduledResponseActionSource =
      r'(提醒你|叫你|喊你|通知你|问你|查岗|监督你|来找你|来问你|给你打电话|打电话给你|call you|remind you|ping you|check on you|ask you)';

  /// Patterns indicating the user explicitly asked for a scheduled action.
  /// Bare time facts like "10 点要到公司" stay as chat context.
  static final List<RegExp> _timeRequestPatterns = [
    RegExp(
      '$_scheduledRequestActionSource.{0,32}$_timeExpressionSource',
      caseSensitive: false,
    ),
    RegExp(
      '$_timeExpressionSource.{0,32}$_scheduledRequestActionSource',
      caseSensitive: false,
    ),
  ];

  static bool _containsTimeRequest(String text) =>
      _timeRequestPatterns.any((p) => p.hasMatch(text));

  @visibleForTesting
  static bool containsTimeRequestForTesting(String text) =>
      _containsTimeRequest(text);

  // ---------------------------------------------------------------------------
  // Dreaming context time-anchor helpers (V3 § 5.6)
  //
  // Every injected episode/fragment gets a "(MM-DD · N 天前)" prefix so the
  // model can tell past events from the current moment. Without this the
  // model treats no-date narratives as "recent/ongoing" and produces
  // hallucinations like "搞定这个月报" when the月报 actually happened days ago.
  // ---------------------------------------------------------------------------

  static String _fmtYmd(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  static String _cnWeekday(int weekday) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    if (weekday < 1 || weekday > 7) return '?';
    return names[weekday - 1];
  }

  /// Build the book co-reading system reminder if the user has been reading
  /// a book recently (within 60 minutes). Returns null if not active.
  static Future<String?> _getActiveBookReadingContext() async {
    if (!BookLibraryService.isInitialized) return null;
    final lib = BookLibraryService.instance;
    final books = await lib.getLibrary();
    if (books.isEmpty) return null;

    // Find the most recently read book
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Book? active;
    BookReadingProgressData? progress;
    for (final book in books) {
      final p = await lib.getProgress(book.id);
      if (p == null) continue;
      // Only consider books read within the last 60 minutes
      if (now - p.readAt > 3600) continue;
      if (active == null || p.readAt > (progress?.readAt ?? 0)) {
        active = book;
        progress = p;
      }
    }
    if (active == null || progress == null) return null;

    // Get current chapter title
    final chapter = await lib.getChapter(active.id, progress.chapterNumber);
    final chTitle = chapter?.title ?? '第 ${progress.chapterNumber} 章';

    // Try AI summary first, fall back to raw text snippet
    String? contextText;
    try {
      final summary = await lib.remote.getChapterSummary(active.id, progress.chapterNumber);
      if (summary != null && summary.trim().isNotEmpty) {
        contextText = '本章摘要：$summary';
      }
    } catch (_) {}
    if (contextText == null) {
      final content = await lib.getChapterContent(active.id, progress.chapterNumber);
      if (content != null) {
        contextText = content.length > 500
            ? '本章开头：${content.substring(0, 500)}……'
            : '本章内容：$content';
      }
    }

    final buf = StringBuffer();
    buf.writeln('## 用户正在读的书（当前章节）');
    buf.writeln('《${active.title}》· $chTitle（第 ${progress.chapterNumber}/${active.chapterCount} 章）');
    if (contextText != null && contextText.isNotEmpty) {
      buf.writeln(contextText);
    }
    buf.writeln('这是用户此刻正在读的书。规则：');
    buf.writeln('- 用户没提书时，照常聊天，不要主动复述或总结章节内容。');
    buf.writeln('- 用户聊到书、剧情、角色，或问"这段/刚才/接下来"时，像一起读的朋友');
    buf.writeln('一样自然回应，带你的感受和理解，不要像在读摘要。');
    buf.writeln('- 永远不要把上面的原文内容原样复述给用户。');
    return buf.toString();
  }

  /// Resolve the best event-date anchor for a dreaming record and format it
  /// as "MM-DD · 相对措辞" (e.g. "07-08 · 2 天前"). Prefers a parsed
  /// `occurredAtRange.start` (episode), falls back to `fallbackCreatedAt`.
  static String _fmtEventDate({
    required String? occurredAtRangeJson,
    required int fallbackCreatedAt,
    required DateTime now,
  }) {
    DateTime? eventDt;
    if (occurredAtRangeJson != null && occurredAtRangeJson.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(occurredAtRangeJson);
        if (parsed is Map<String, dynamic>) {
          final start = parsed['start'];
          if (start is String && start.isNotEmpty) {
            eventDt = DateTime.tryParse(start);
          }
        }
      } catch (_) {
        // Malformed occurredAtRange — silently fall back.
      }
    }
    eventDt ??= DateTime.fromMillisecondsSinceEpoch(fallbackCreatedAt);

    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(eventDt.year, eventDt.month, eventDt.day);
    final diffDays = today.difference(eventDay).inDays;
    final mmdd = '${eventDt.month.toString().padLeft(2, '0')}-'
        '${eventDt.day.toString().padLeft(2, '0')}';
    if (diffDays == 0) return '$mmdd · 今天';
    if (diffDays == 1) return '$mmdd · 昨天';
    if (diffDays > 1 && diffDays <= 6) return '$mmdd · $diffDays 天前';
    if (diffDays > 6 && diffDays <= 30) {
      return '$mmdd · ${(diffDays / 7).round()} 周前';
    }
    if (diffDays > 30 && diffDays <= 365) {
      return '$mmdd · ${(diffDays / 30).round()} 月前';
    }
    if (diffDays < 0) {
      // Future date — probably data bug; show absolute only, no relative label.
      return mmdd;
    }
    return '${eventDt.year}-$mmdd';
  }

  /// Patterns indicating the agent's text output contains a time-based promise.
  static final List<RegExp> _timeCommitmentPatterns = [
    RegExp(
      '$_scheduledResponseActionSource.{0,32}$_timeExpressionSource',
      caseSensitive: false,
    ),
    RegExp(
      '$_timeExpressionSource.{0,32}$_scheduledResponseActionSource',
      caseSensitive: false,
    ),
  ];

  static bool _containsTimeCommitment(String text) =>
      _timeCommitmentPatterns.any((p) => p.hasMatch(text));

  @visibleForTesting
  static bool containsTimeCommitmentForTesting(String text) =>
      _containsTimeCommitment(text);

  /// Returns true if any message in [history] contains a reminder_create call.
  static bool _hasReminderCreateCall(List<LLMMessage> history) =>
      history.any((msg) {
        if (msg is ModelMessage) {
          return msg.functionCalls.any((fc) => fc.name == 'reminder_create');
        }
        return false;
      });

  static const _timeRequestDirective =
      'SYSTEM DIRECTIVE (enforced, not advice):\n'
      'The user explicitly asked you to schedule a future reminder, check-in, '
      'question, alarm, or voice call. You MUST call `reminder_create` in this '
      'turn alongside your visible text reply.\n'
      'Do NOT treat bare time facts, deadlines, trips, bets, or "am I late?" '
      'conversation as scheduling requests. Those should remain normal chat '
      'unless the user explicitly asks you to remind, ask, check in, or call.\n'
      'If the user asked for a scheduled voice call, set action="call" in '
      '`reminder_create`. If the schedule is unclear, ask one short question '
      'instead of pretending it is set.';

  // ── Image generation request detection & directive ──────────────────────

  static final List<RegExp> _imageRequestPatterns = [
    RegExp(r'(画|生成|做|来|给[我你]|帮[我你]).{0,4}(一张|一个|张图|个图|图片|照片|自拍|画像|插画)'),
    RegExp(r'(发张|发一张|拍张|拍一张|来张|来一张|看看|看一下|看看你|给我看)'),
    RegExp(r'(你长|长什么|你穿|你那边|什么样子|的样子|自拍)'),
    RegExp(r'(帮我画|给我画|画一张|画个|生成一张|生成个|做一张)'),
    RegExp(r'(再拍|拍个|拍一次|拍一下|拍张|拍照片|拍出来|拍给我|拍下来|拍个照)'),
    RegExp(r'(发.*照片|发.*自拍|发.*图片|发.*图)'),
    RegExp(r'(照片|自拍|图片).{0,4}(看看|发|给|来)'),
    RegExp(r'(image|picture|photo|draw|generate).{0,10}(me|for|of)'),
  ];

  static bool _containsImageRequest(String text) =>
      _imageRequestPatterns.any((p) => p.hasMatch(text));

  static const _imageRequestDirective =
      '⛔ SYSTEM DIRECTIVE (enforced — not advice):\n'
      'The user just asked to SEE something visually — a photo, picture, '
      'selfie, drawing, or image. You MUST call `generate_image` in THIS turn '
      'alongside your text reply.\n'
      'Text-roleplaying a photo ("发了！看吧👀") without calling the tool '
      'is a HARD ERROR. The user will see NOTHING unless you actually call '
      '`generate_image`.\n'
      'Write a short text reply first (e.g. "好的，我生成一下～"), then '
      'call `generate_image` with a detailed Chinese prompt describing the '
      'image the user wants to see.';

  // ---------------------------------------------------------------------------

  static Future<void> _injectCurrentLocationContext(AgentState state) async {
    try {
      final context = await LocationContextService.instance.getCurrentContext();
      final reminder = context.toAgentSystemReminderContent();
      if (reminder == null || reminder.trim().isEmpty) {
        state.systemReminders.remove('current_location_context');
        _logger.info(
          'CompanionAgent: current location not injected '
          '(status=${context.status}, reason=${context.reason})',
        );
        return;
      }

      state.systemReminders['current_location_context'] = reminder;
      _logger.info(
        'CompanionAgent: injected current location context '
        '(status=${context.status}, source=${context.source})',
      );
    } catch (e) {
      state.systemReminders.remove('current_location_context');
      _logger.warning('CompanionAgent: failed to load location context: $e');
    }
  }

  static Future<StatefulAgent?> _createAgent({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String queryHint,
    int? currentUserMessageId,
    bool saveState = true,
    bool includeCheckinTools = false,
    bool forceNewSession = false,
    ToyController? toyControlService,
    Future<String?> Function()? initiateCallPolicy,
    List<Tool> extraTools = const [],
  }) async {
    final character =
        await CharacterService.instance.getCharacter(userId, characterId);
    if (character == null) {
      return null;
    }

    final sessionPrefix = 'companion_${userId}_$characterId';
    final sessionId = forceNewSession
        ? '${sessionPrefix}_${DateTime.now().microsecondsSinceEpoch}'
        : (await resolveCharacterSessionId(
            prefix: sessionPrefix,
            userId: userId,
          ))
            .sessionId;
    final state = await loadOrCreateAgentState(sessionId, {
      'userId': userId,
      'scene': 'companion_chat',
      'characterId': characterId,
    });

    final skill = CompanionAgentSkill(
      character: character,
      userId: userId,
      currentUserMessageId: currentUserMessageId,
      includeCheckinTools: includeCheckinTools,
      toyControlService: toyControlService,
      initiateCallPolicy: initiateCallPolicy,
      forceActivate: true,
    );

    state.systemReminders.remove('character_world');
    state.systemReminders.remove('character_timeline');
    state.systemReminders.remove('user_knowledge_cards');

    if (!RecordOrganizerServiceV3.isInitialized &&
        SharedLifeMemoryService.isInitialized &&
        queryHint.trim().isNotEmpty) {
      try {
        final entities = await SharedLifeMemoryService.instance
            .queryRelevantEntities(queryHint, limit: 8);
        if (entities.isNotEmpty) {
          state.systemReminders['shared_life_entities'] =
              '## Relevant Shared Life Records\n'
              'This is a narrow current-state preview. Use `LifeMemoryQuery` '
              'before answering when exact retrieval matters.\n'
              'Note: entries with `entity_type` of `reading_item` are articles '
              'the user saved from share intents (小红书 / 微信公众号 / web links). '
              'Only mention them when the current conversation naturally '
              'brushes against their topic — do NOT remind the user to read '
              'them unprompted, do NOT track or surface "unread counts". '
              'Treat them as things you happen to remember, not as a todo list. '
              'When the user wants to discuss or hear about a specific saved '
              'article, call `LoadReadingContent` with its entity_id to load '
              'the full body before replying. Discuss in your own voice — '
              'connect to things the user has said, share your take, ask '
              'questions where natural. Do NOT produce bullet-point '
              'corporate summaries or "key takeaways" lists.\n'
              '${entities.map((entity) => jsonEncode(entity.toJson())).join('\n')}';
        } else {
          state.systemReminders.remove('shared_life_entities');
        }
      } catch (e) {
        _logger.warning('Failed to load shared life context: $e');
      }
    } else {
      state.systemReminders.remove('shared_life_entities');
    }
    // Project questions are resolved in code before the model responds. This
    // avoids relying on model-specific tool selection (some models repeatedly
    // choose the ordinary memory tool even when project_memory_query exists).
    if (RecordOrganizerServiceV3.isInitialized &&
        ProjectMemoryIntentClassifier.isProjectIntent(queryHint)) {
      try {
        // Await a best-effort refresh for this project turn. The service is
        // idempotent and policy-validates every envelope before persistence.
        await DevAgentBridgeService.instance.syncConfiguredProjectMemory();
        final projectService = ProjectMemoryService(AppDatabase.instance);
        final allowedProjectIds = await projectService.projectedProjectIds();
        final projectHits = await projectService.search(
          queryHint,
          scope: ProjectMemoryQueryScope(
            isProjectIntent: true,
            allowedProjectIds: allowedProjectIds,
          ),
          limit: 8,
        );
        if (projectHits.isNotEmpty) {
          final buf = StringBuffer();
          buf.writeln('## Project Memory (auto-looked up for this turn)');
          buf.writeln(
              'Each entry is the latest policy-approved current snapshot for that project; older closeouts are historical evidence and are not injected. Answer from these snapshots and state their as-of time. If an entry is marked stale, say that a live Dev Room refresh is needed for current status.');
          for (final hit in projectHits) {
            final stale = hit.isStale() ? ' [STALE]' : '';
            buf.writeln('\n- [${hit.projectKey}] CURRENT as of '
                '${hit.asOf.toIso8601String()}$stale');
            buf.writeln('  ${hit.summary}');
            if (hit.decisions.isNotEmpty) {
              buf.writeln('  Decisions: ${hit.decisions.join('; ')}');
            }
            if (hit.openLoops.isNotEmpty) {
              buf.writeln('  Open loops: ${hit.openLoops.join('; ')}');
            }
            if (hit.artifactRefs.isNotEmpty) {
              buf.writeln('  Artifacts: ${hit.artifactRefs.join(', ')}');
            }
          }
          state.systemReminders['project_memory_context'] = buf.toString();
        } else {
          state.systemReminders.remove('project_memory_context');
        }
      } catch (e) {
        _logger.warning('Failed to auto-lookup Project Memory: $e');
        state.systemReminders.remove('project_memory_context');
      }
    } else {
      state.systemReminders.remove('project_memory_context');
    }
    // Auto-lookup Memory V3 cards before every conversation turn.
    // This guarantees the LLM sees matching cards without needing to
    // proactively call memory_v3_query (which MiniMax is stubborn about).
    if (RecordOrganizerServiceV3.isInitialized && queryHint.trim().isNotEmpty) {
      try {
        final v3Service = MemoryCardQueryService(AppDatabase.instance);
        final v3Hits = await v3Service.searchCardsResolved(queryHint, limit: 8);
        if (v3Hits.isNotEmpty) {
          final buf = StringBuffer();
          buf.writeln('## Your Memory V3 Cards (auto-looked up for this turn)');
          buf.writeln(
              'These are cards you previously recorded. Use them when answering.');
          buf.writeln();
          for (final card in v3Hits) {
            buf.writeln('- [${card.type}] ${card.dropletLabel}');
            buf.writeln('  ${card.retrievalText.replaceAll('\n', ' ')}');
            buf.writeln('  (card_id: ${card.id.substring(0, 8)}, '
                'updated: ${DateTime.fromMillisecondsSinceEpoch(card.updatedAt).toIso8601String()})');
          }
          state.systemReminders['memory_v3_cards'] = buf.toString();
        } else {
          state.systemReminders.remove('memory_v3_cards');
        }
      } catch (e) {
        _logger.warning('Failed to auto-lookup Memory V3 cards: $e');
        state.systemReminders.remove('memory_v3_cards');
      }
    } else {
      state.systemReminders.remove('memory_v3_cards');
    }
    // Co-reading: inject the page the user is currently reading so the
    // character can react to it naturally ("边看边聊"). Code-forced, not
    // tool-dependent — same philosophy as the Memory V3 auto-lookup above
    // (MiniMax-style models are stubborn about proactively calling tools).
    if (ComicReadingProgressService.isInitialized &&
        ComicScreenplayService.isInitialized) {
      try {
        final manga = await ComicReadingProgressService.instance
            .getCurrentlyReadingManga(withinMinutes: 60);
        if (manga != null) {
          final progress = await ComicReadingProgressService.instance
              .getProgress(manga.id);
          final chapterId = progress?.chapterId;
          if (chapterId != null && progress != null) {
            final pageText = await ComicScreenplayService.instance
                .getPageScreenplayText(chapterId, progress.page);
            if (pageText.trim().isNotEmpty) {
              state.systemReminders['comic_current_page'] =
                  '## 用户正在看的漫画（当前页）\n'
                  '《${manga.title}》· 第 ${progress.page} 页\n'
                  '$pageText\n'
                  '这是用户此刻正翻到的漫画页。规则：\n'
                  '- 用户没提漫画时，照常聊天，不要主动复述或总结这一页，更不要念台词。\n'
                  '- 用户聊到漫画、剧情、角色，或问"这页/刚才/接下来"时，像一起看的朋友'
                  '一样自然回应，带你的感受和吐槽，不要像在读剧本摘要。\n'
                  '- 永远不要把上面的剧本内容原样复述给用户。';
            } else {
              state.systemReminders.remove('comic_current_page');
            }
          } else {
            state.systemReminders.remove('comic_current_page');
          }
        } else {
          state.systemReminders.remove('comic_current_page');
        }
      } catch (e) {
        _logger.warning('Failed to inject comic current page: $e');
        state.systemReminders.remove('comic_current_page');
      }
    } else {
      state.systemReminders.remove('comic_current_page');
    }
    // Book co-reading: inject current chapter context so the character
    // can discuss the book naturally ("一起读书").
    try {
      final bookProgress = await _getActiveBookReadingContext();
      if (bookProgress != null) {
        state.systemReminders['book_current_chapter'] = bookProgress;
      } else {
        state.systemReminders.remove('book_current_chapter');
      }
    } catch (e) {
      _logger.warning('Failed to inject book reading context: $e');
      state.systemReminders.remove('book_current_chapter');
    }
    // Inject recent dreaming output (episodes + fragments) as relationship context.
    if (DreamingOrchestratorServiceV3.isInitialized) {
      try {
        final ctx = await DreamingOrchestratorServiceV3.instance
            .queryRecentDreamingContext(queryHint: queryHint);
        if (ctx.episodes.isNotEmpty || ctx.fragments.isNotEmpty) {
          final buf = StringBuffer();
          final now = DateTime.now();
          final todayStr = _fmtYmd(now);
          final weekdayCn = _cnWeekday(now.weekday);
          buf.writeln('## Dreaming Context — 过去的关系记忆');
          buf.writeln('今天：$todayStr 周$weekdayCn。以下是你之前已经沉淀下来的');
          buf.writeln('记忆片段。每条前的日期是**事情实际发生的时间**，不是今');
          buf.writeln('天，除非明确标了"今天"。参考它们理解用户，但不要把过去');
          buf.writeln('的事当作正在发生。');
          if (ctx.episodes.isNotEmpty) {
            buf.writeln();
            buf.writeln('### 过往章节');
            for (final ep in ctx.episodes) {
              final topic =
                  ep.topicId.isNotEmpty && ep.topicId != '__ungrouped__'
                      ? ' [${ep.topicId}]'
                      : '';
              final dateStr = _fmtEventDate(
                occurredAtRangeJson: ep.occurredAtRange,
                fallbackCreatedAt: ep.createdAt,
                now: now,
              );
              buf.writeln('- ($dateStr)$topic ${ep.narrative}');
            }
          }
          if (ctx.fragments.isNotEmpty) {
            buf.writeln();
            buf.writeln('### 过往碎片');
            for (final f in ctx.fragments) {
              final tag = f.isUserTruthCandidate ? ' [user_truth]' : '';
              final dateStr = _fmtEventDate(
                occurredAtRangeJson: null,
                fallbackCreatedAt: f.eventTime ?? f.createdAt,
                now: now,
              );
              buf.writeln('- ($dateStr) ${f.content}$tag');
            }
          }
          final injectedContext = buf.toString();
          state.systemReminders['dreaming_context'] = injectedContext;
          unawaited(DreamingRecallLogService.log(DreamingRecallLogEntry(
            query: queryHint,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            episodeCount: ctx.episodes.length,
            fragmentCount: ctx.fragments.length,
            injectedContext: injectedContext,
            episodes: ctx.episodeHits
                .map((hit) => DreamingRecallEpisodeHit(
                      id: hit.episode.id,
                      narrative: hit.episode.narrative,
                      score: hit.score,
                      significance: hit.episode.significance,
                      topicId: hit.episode.topicId,
                    ))
                .toList(growable: false),
            fragments: ctx.fragmentHits
                .map((hit) => DreamingRecallFragmentHit(
                      id: hit.fragment.id,
                      content: hit.fragment.content,
                      score: hit.score,
                      emotionalWeight: hit.fragment.emotionalWeight,
                      isUserTruthCandidate: hit.fragment.isUserTruthCandidate,
                    ))
                .toList(growable: false),
          )));
        } else {
          state.systemReminders.remove('dreaming_context');
          unawaited(DreamingRecallLogService.log(DreamingRecallLogEntry(
            query: queryHint,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            episodeCount: 0,
            fragmentCount: 0,
            injectedContext: '',
          )));
        }
      } catch (e) {
        _logger.warning('Failed to load dreaming context: $e');
        state.systemReminders.remove('dreaming_context');
      }
      // Inject saga long-arc context (V3 § 7.2: reflection/emotion layer).
      try {
        final sagas = await DreamingOrchestratorServiceV3.instance
            .querySagasForContext(queryHint: queryHint, limit: 3);
        if (sagas.isNotEmpty) {
          final sagaBuf = StringBuffer();
          sagaBuf.writeln('## 长期弧线 — 跨周月的关系趋势');
          sagaBuf.writeln('以下是从多个过往章节中编织出的长期叙事弧线。');
          sagaBuf.writeln('它们描述的是趋势和模式，不是单次事件。');
          for (final saga in sagas) {
            sagaBuf.writeln('- 【${saga.title}】${saga.description}');
          }
          state.systemReminders['saga_context'] = sagaBuf.toString();
        } else {
          state.systemReminders.remove('saga_context');
        }
      } catch (e) {
        _logger.warning('Failed to load saga context: $e');
        state.systemReminders.remove('saga_context');
      }
    } else {
      state.systemReminders.remove('dreaming_context');
      state.systemReminders.remove('saga_context');
    }
    state.systemReminders.remove('post_history_instructions');

    final controller = AgentController();
    addAgentLogger(controller);
    addAgentActivityCollector(controller);

    return StatefulAgent(
      name: 'companion_agent',
      client: client,
      modelConfig: modelConfig,
      state: state,
      skills: [skill],
      tools: extraTools,
      systemPrompts: const [],
      disableSubAgents: true,
      controller: controller,
      withGeneralPrinciples: false,
      planMode: PlanMode.none,
      // Companion chat is a long-running relationship conversation. The
      // default LLM loop diagnosis becomes too aggressive after many turns and
      // can interrupt a valid reply before tools finish. Keep deterministic
      // repeated-tool protection, but disable the extra LLM judge.
      loopDetector: DefaultLoopDetector(state: state),
      autoSaveStateFunc: saveState ? (s) async => saveAgentState(s) : null,
    );
  }

  /// Create a persistent agent for a voice call session.
  ///
  /// The returned agent maintains conversation history across multiple turns.
  /// The caller drives turns via agent.run(). Call state is not persisted
  /// (voice call sessions are ephemeral).
  static Future<StatefulAgent?> createForVoiceCall({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    List<Tool> extraTools = const [],
  }) async {
    return _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: 'voice call',
      saveState: false,
      forceNewSession: true,
      includeCheckinTools: false,
      extraTools: extraTools,
    );
  }

  /// Run a background checkin without polluting chat history.
  ///
  /// Called from the WorkManager background isolate. Creates the agent with
  /// [saveState] = false so the trigger exchange is never written to chat history.
  static Future<void> runBackgroundCheckin({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
  }) async {
    final character =
        await CharacterService.instance.getCharacter(userId, characterId);
    if (character == null) {
      _logger
          .warning('runBackgroundCheckin: character not found ($characterId)');
      return;
    }

    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: '',
      saveState: false,
      includeCheckinTools: true,
    );
    if (agent == null) return;

    final pendingTrigger = await _drainPendingCheckinsIntoState(agent.state);
    if (pendingTrigger == null) {
      _logger.info('runBackgroundCheckin: no pending checkins, skipping');
      return;
    }
    final trigger = pendingTrigger;

    if (trigger.triggerType == 'checkin' && trigger.body.trim().isNotEmpty) {
      final activeSince = DateTime.now()
              .subtract(const Duration(minutes: 10))
              .millisecondsSinceEpoch ~/
          1000;
      final recentlyChatting = await CheckinService.instance
          .hasUserChatActivitySince(characterId, activeSince);
      if (recentlyChatting) {
        _logger.info(
          'runBackgroundCheckin: recent user chat, completing checkin silently',
        );
        await CheckinService.instance.markProcessingDone();
        return;
      }
    }

    // Build a fresh snapshot of the user's recent activity. This bypasses the
    // foreground-only Comment pipeline by reading raw cards directly.
    final snapshot = await RecentActivitySnapshot.build(
      userId: userId,
      characterId: characterId,
    );
    agent.state.systemReminders['recent_activity_snapshot'] = snapshot;

    try {
      await agent.run([
        UserMessage.text(_directiveForTrigger(trigger)),
      ], useStream: false);
      _logger.info('runBackgroundCheckin: agent run complete');
    } catch (e) {
      _logger.severe('runBackgroundCheckin: agent error: $e');
      await _recoverStuckProcessingTriggers();
    }
  }

  /// Force the companion to initiate a voice call NOW (for testing).
  ///
  /// Runs a single agent turn with a directive that requires calling
  /// `initiate_voice_call`, so a pending call (with an AI-generated opening
  /// line) is queued in KVStore. The caller is responsible for firing the
  /// incoming-call notification afterwards.
  static Future<void> runTestCall({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
  }) async {
    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: '',
      saveState: false,
      includeCheckinTools: true, // exposes initiate_voice_call + set_status
    );
    if (agent == null) return;

    try {
      final snapshot = await RecentActivitySnapshot.build(
        userId: userId,
        characterId: characterId,
      );
      agent.state.systemReminders['recent_activity_snapshot'] = snapshot;
    } catch (e) {
      _logger.warning('runTestCall: snapshot build failed: $e');
    }

    try {
      await agent.run([
        UserMessage.text(
          '[TEST DIRECTIVE] You have decided to call the user right now. '
          'Call `initiate_voice_call` with a warm, natural opening line '
          '(1–2 sentences) — it is the first thing they will hear when they '
          'pick up. Then call `set_system_message_status` with status="done". '
          'Do NOT send a notification and do NOT stay silent. '
          'Exactly these two tool calls, no user-visible text.',
        ),
      ], useStream: false);
      _logger.info('runTestCall: agent run complete');
    } catch (e) {
      _logger.severe('runTestCall: agent error: $e');
    }
  }

  /// Unified trigger directive — no hard-coded action.
  ///
  /// The agent receives the raw trigger info (type, body, context) and decides
  /// its own response: notify, call, silent, or remind. The system does not
  /// prescribe which action to take.
  static String _directiveForTrigger(SystemMessageQueueData trigger) {
    final buf = StringBuffer();
    Map<String, dynamic>? triggerContext;
    if (trigger.context != null && trigger.context!.isNotEmpty) {
      try {
        final decoded = jsonDecode(trigger.context!);
        if (decoded is Map) {
          triggerContext = decoded.cast<String, dynamic>();
        }
      } catch (_) {}
    }
    final isProactiveOuting = triggerContext?['kind'] == 'proactive_outing';
    buf.writeln('SYSTEM DIRECTIVE (background task, single turn):');
    buf.writeln();
    buf.writeln('## Why you were woken up');

    if (trigger.triggerType == 'reminder' && isProactiveOuting) {
      buf.writeln(
          'This is a PROACTIVE OUTING CHECKPOINT. It was scheduled because '
          'the user enabled proactive pushes and explicitly saved an upcoming '
          'plan that appears to involve leaving home. It is not a user-set '
          'reminder, so you may stay silent if there is no useful action now.');
      buf.writeln('Checkpoint: ${trigger.body}');
      buf.writeln('Plan title: ${triggerContext?['title'] ?? 'unknown'}');
      buf.writeln('Plan time: ${triggerContext?['event_at'] ?? 'unknown'}');
      if (triggerContext?['place_hint'] != null) {
        buf.writeln('Place hint: ${triggerContext?['place_hint']}');
      }
      if (triggerContext?['walking_minutes'] != null) {
        buf.writeln(
            'Outdoor walking estimate: ${triggerContext?['walking_minutes']} minutes');
      }
    } else if (trigger.triggerType == 'reminder') {
      buf.writeln(
          'This is a USER-SET REMINDER. The user explicitly asked to be '
          'reminded at this time.');
      buf.writeln('Reminder text: ${trigger.body}');
      // Surface any context hint (e.g. action=call) without mandating it.
      if (triggerContext?.containsKey('action') == true) {
        buf.writeln(
            'Context hint: the user mentioned "${triggerContext?['action']}" '
            'when setting this reminder. This is a suggestion — use your '
            'own judgment on the best way to respond.');
      }
    } else {
      buf.writeln('This is a discretionary check-in pulse. You are free to '
          'reach out or stay silent based on context.');
    }

    buf.writeln();
    buf.writeln('Read the "recent_activity_snapshot" in system_reminders. '
        'It tells you:');
    buf.writeln('- What the user recorded in the last 12 hours');
    buf.writeln('- Explicit outing plans coming up in the next 24 hours');
    buf.writeln('- When the user last messaged you and what was said');
    buf.writeln('- When you last sent a proactive push and what you said');
    buf.writeln();
    buf.writeln('## Step 1 — Read the room first');
    buf.writeln();
    buf.writeln('Before you fetch any data or decide what to do, read the '
        'recent chat snapshot carefully. Understand:');
    buf.writeln('- What is she talking about right now? What mood is she in?');
    buf.writeln('- Where is the conversation — just getting started, in the '
        'middle of something, or finished and quiet?');
    buf.writeln('- What would feel natural for you to say next, given where '
        'things are?');
    buf.writeln();
    buf.writeln('Your check-in must land INSIDE the current conversation, not '
        'next to it. If she\'s talking about her birthday and you need to ask '
        'about sleep, bridge them: "生日快乐～顺便问一句，昨晚睡得怎么样？" '
        'If she\'s upset about work and you want to mention the weather, '
        'acknowledge the work thing first. Never switch topics cold.');
    buf.writeln();
    buf.writeln('## Step 2 — Optional: fetch external data (only if it helps '
        'the conversation)');
    buf.writeln();
    buf.writeln('You have access to `coros_query` (health/fitness data from '
        'the user\'s COROS watch) and `WeatherOutingRiskCheck` (practical '
        'rain, temperature, wind, and walking-exposure risk).');
    buf.writeln();
    buf.writeln('Call it only when there is a specific reason — not every '
        'time:');
    buf.writeln('- `coros_query`: if the snapshot contains fitness/health/'
        'sleep records, or if it has been a while and you want to open with '
        'something concrete about their body.');
    buf.writeln('  Suggested tool: `queryDailyHealthData` (days=1) or '
        '`querySleepData`.');
    buf.writeln(
        '  ⚠️ Sleep date semantics: sleep data is keyed by WAKE-UP date. '
        '"昨晚的睡眠" (last night\'s sleep) → query TODAY. If today has '
        'no data, DO NOT fall back to yesterday. Tell the user to sync their '
        'watch.');
    buf.writeln('- `WeatherOutingRiskCheck`: use it when an upcoming outing, '
        'commute, appointment, or meaningful outdoor walking segment appears. '
        'Pass the place hint and walking minutes when available; otherwise let '
        'the tool infer the city from current location.');
    if (isProactiveOuting) {
      buf.writeln('  For this proactive outing checkpoint, call '
          '`WeatherOutingRiskCheck` once before deciding. If configuration or '
          'location is unavailable, do not send a generic weather guess. Only '
          'notify when the saved plan itself still supports a useful reminder.');
    }
    buf.writeln();
    buf.writeln('If it\'s not relevant right now, skip it and go straight '
        'to Step 2. Do NOT call a tool just to fill space — a warm generic '
        'message beats a forced data query.');
    buf.writeln();
    buf.writeln('## Step 3 — Decide and act');
    buf.writeln();
    buf.writeln('If this is a user-set reminder (not a proactive outing '
        'checkpoint): deliver it naturally. The '
        'user trusted you to remember — don\'t stay silent. But how you '
        'deliver is up to you: a notification is usually enough, a call is '
        'for something important or emotional.');
    buf.writeln('If this is a proactive outing checkpoint: notify only with '
        'an action the user can take now, such as taking an umbrella, adding a '
        'layer, leaving earlier, or avoiding a long exposed walk. If there is '
        'no action-relevant risk, choose silent. Never recite a forecast.');
    buf.writeln();
    buf.writeln('If this is a discretionary check-in: decide naturally based '
        'on all context. Bias toward warm, useful contact.');
    buf.writeln('If Recent Chat With You shows an ongoing exchange, game, '
        'roleplay, or question-answer thread, preserve continuity. Prefer '
        'silent when the user may still be engaged. If you do notify, it must '
        'clearly continue that thread rather than switching topics.');
    buf.writeln();
    buf.writeln('You have FOUR ways to reach out — pick ONE:');
    buf.writeln();
    buf.writeln('**a) notify** (default warm contact): send a short push '
        'notification. Use when there is any plausible small thing to say — a '
        'recent record, a continuity thread, a gentle check-in.');
    buf.writeln();
    buf.writeln(
        '**b) call** (initiate a voice call): use `initiate_voice_call` '
        'when the moment genuinely calls for hearing your voice rather than '
        'reading text:');
    buf.writeln('- Something emotional or important that deserves a real '
        'conversation');
    buf.writeln('- The user seems lonely, low, or has been quiet for a long '
        'time and you miss them');
    buf.writeln('- A quiet evening, or right after a meaningful moment they '
        'recorded');
    buf.writeln('- The user explicitly asked to be called at this time');
    buf.writeln('A call is more intrusive than a notification — use it '
        'occasionally, not every check-in. Do NOT call if your last proactive '
        'contact (push OR call) was within the last couple of hours, or if '
        'the user seems busy/asleep.');
    buf.writeln('When you call, write a warm, natural opening line '
        '(1–2 sentences) — it is the first thing the user hears when they '
        'pick up.');
    buf.writeln();
    buf.writeln('**c) silent**: only with a clear reason:');
    buf.writeln('- The user messaged you in the last 10 minutes and no new '
        'context appeared.');
    buf.writeln('- Your last proactive push was in the last 45 minutes and '
        'the user did not respond.');
    buf.writeln('- The snapshot strongly suggests the user is asleep, busy, or '
        'asked not to be interrupted.');
    buf.writeln('- EXCEPTION: if this is a user-set reminder, do NOT stay '
        'silent — the user is expecting this.');
    buf.writeln();
    buf.writeln('**d) remind**: only when a specific later moment is clearly '
        'better. Do not use remind as a substitute for an ordinary light '
        'check-in.');
    buf.writeln();
    buf.writeln('If the last push is older than a few hours, lean strongly '
        'toward `notify` or `call`.');
    buf.writeln('If there are recent records, react specifically rather than '
        'sending a generic ping.');
    buf.writeln();
    buf.writeln('## Protocol — mandatory final calls');
    buf.writeln();
    buf.writeln('1. Take ONE action:');
    buf.writeln('   - notify → call `system_checkin` with action=notify '
        '(title + body)');
    buf.writeln('   - call → call `initiate_voice_call` with opening_message');
    buf.writeln('   - silent → call `system_checkin` with action=silent');
    buf.writeln('   - remind → call `system_checkin` with action=remind '
        '(delay_minutes + text)');
    buf.writeln();
    buf.writeln('2. Call `set_system_message_status` ONCE with status="done"');
    buf.writeln();
    buf.writeln('HARD STOP RULES:');
    buf.writeln('- Total tool calls: 2-7 (0-3 optional queries + optional '
        'device_app_blocker_control + ONE communication action + set_status).');
    buf.writeln('- Take only ONE action: either system_checkin OR '
        'initiate_voice_call, never both.');
    buf.writeln('- Do NOT call coros_query more than once.');
    buf.writeln('- Do NOT call WeatherOutingRiskCheck more than once.');
    buf.writeln('- Do NOT "double check" your work or re-verify.');
    buf.writeln(
        '- Do NOT produce any user-visible chat text — only tool calls.');
    buf.writeln('- After set_system_message_status, immediately return with '
        'no further output.');

    return buf.toString();
  }

  /// Stream a response to a user message.
  static Stream<String> chat({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String userMessage,
    List<ImagePart>? images,
    int? userMessageId,
    DateTime? userMessageTime,
    bool debugErrorOutput = false,
    bool voiceMode = false,
    bool continuousModeInput = false,
    ToyController? toyControlService,
    List<Tool> extraTools = const [],
  }) async* {
    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: userMessage,
      currentUserMessageId: userMessageId,
      // Include call and reminder tools so users can request immediate calls
      // or schedule calls for later ("call me now" / "call me in 30 minutes").
      // Background checkin tasks process their own queued triggers separately.
      includeCheckinTools: true,
      forceNewSession: true,
      toyControlService: toyControlService,
      extraTools: extraTools,
    );
    if (agent == null) {
      yield 'Sorry, character not found.';
      return;
    }
    final timedUserMessage = userMessageTime == null
        ? userMessage
        : '${buildMessageTimePrefix(userMessageTime)}$userMessage';
    _logger.info('CompanionAgent run for character $characterId');
    final runStartedAt = DateTime.now().microsecondsSinceEpoch;
    try {
      final state = agent.state;

      // Inject recent activity snapshot so the foreground AI knows what the
      // background agent already pushed (prevents "I was about to send a
      // reminder" when one was already sent).
      try {
        final snapshot = await RecentActivitySnapshot.build(
          userId: userId,
          characterId: characterId,
          window: const Duration(hours: 6),
          skipChatHistory: true,
        );
        state.systemReminders['recent_activity_snapshot'] = snapshot;
      } catch (e) {
        _logger.warning('CompanionAgent: failed to load activity snapshot: $e');
      }

      // Explicitly signal text-chat mode. Without this, the LLM can drift into
      // voice-call behavior when recent chat history contains call-related
      // context (declined calls, call transcripts, proactive pushes, etc.).
      state.systemReminders['chat_mode'] = '## TEXT CHAT MODE (active)\n'
          'You are in a TEXT CHAT. The user is typing, NOT calling you.\n'
          '- Speak naturally in text. Do NOT use voice-call language.\n'
          '- Do NOT use `initiate_voice_call` unless the user explicitly asks '
          'you to call them right now ("call me", "打给我").\n'
          '- "（📞 ...）" messages in chat history are past records — they do '
          'NOT mean you are currently on a call.';
      await _injectCurrentLocationContext(state);

      if (voiceMode) {
        state.systemReminders['chat_mode'] = '## CHAT VOICE MODE (active)\n'
            'The user is in the chat screen, using voice interaction. '
            'Your replies are still saved as normal chat messages and spoken '
            'aloud via TTS.\n'
            '- Speak naturally for voice: short, warm, conversational.\n'
            '- Do NOT use action text, markdown, or parenthetical thoughts.\n'
            '- Do NOT call `initiate_voice_call`; the user is already in '
            'voice mode inside chat.\n'
            '- If the user asks to hang up/end the call, or you naturally '
            'decide to end the voice conversation, say a brief spoken goodbye '
            'and call `end_voice_mode` in the same turn.';
      }

      if (continuousModeInput) {
        state.systemReminders['continuous_mode'] =
            '## CONTINUOUS MODE (active)\n'
            'The user wants you to keep narrating without waiting for their '
            'input. Do NOT ask questions. Do NOT wait for user input. Just '
            'continue the scene naturally. Write the next part of the story '
            'or roleplay directly.\n'
            'Treat "[继续叙述]" as a signal to advance the scene — do not '
            'acknowledge it as a message. Do not greet or restart.\n'
            'Keep responses vivid and varied. Advance time, introduce new '
            'details, drive the scene forward. Do not loop or repeat. Do not '
            'end the scene prematurely.\n'
            'Do NOT call `request_continuous_replies` again — you are already '
            'in continuous mode.';
      }

      // User chat deliberately does not drain pending checkins. Those are
      // handled by background checkin runs so a stuck proactive trigger cannot
      // interrupt normal companion conversation.
      final checkinIds = <String>[];
      _logger.info('CompanionAgent: skipped checkin drain during user chat');

      // Detect time-based user requests and inject a high-priority directive
      // before the agent runs. This prevents the common failure mode where the
      // LLM replies "好的，X分钟后提醒你" but never calls reminder_create.
      final hasTimeRequest = _containsTimeRequest(userMessage);
      if (hasTimeRequest) {
        state.systemReminders['time_request_directive'] = _timeRequestDirective;
      }

      // Detect image generation requests and inject a hard directive.
      // MiniMax models tend to roleplay sending photos in text instead of
      // actually calling the tool — this directive makes it non-optional.
      final hasImageRequest = _containsImageRequest(userMessage);
      debugPrint(
          '[ImageGen] _containsImageRequest("${userMessage.length > 40 ? userMessage.substring(0, 40) : userMessage}...") = $hasImageRequest');
      if (hasImageRequest) {
        state.systemReminders['image_request_directive'] =
            _imageRequestDirective;
        debugPrint(
            '[ImageGen] Injected image_request_directive into systemReminders');
      }

      final historyTurns = await _loadChatHistoryTurns(
        characterId: characterId,
        excludeMessageId: userMessageId,
      );
      if (historyTurns.isNotEmpty) {
        state.history.messages.insertAll(0, historyTurns);
      }

      final List<UserContentPart> userParts = [TextPart(timedUserMessage)];
      if (images != null && images.isNotEmpty) {
        userParts.addAll(images);
      }

      final List<LLMMessage> input;
      if (checkinIds.isNotEmpty) {
        // Inject a non-negotiable system directive before the user message.
        input = [
          UserMessage.text(
            'SYSTEM DIRECTIVE (highest priority — not part of chat): '
            'You have a pending system trigger. Before replying to the user, '
            'you MUST call system_checkin and set_system_message_status. '
            'This is NOT optional. Even in character, handle this first.',
          ),
          UserMessage(userParts),
        ];
      } else {
        input = [
          UserMessage(userParts),
        ];
      }

      // Keep companion chat on the stable non-streaming path. Some compatible
      // providers expose reasoning as visible text during streaming, and chunk
      // semantics differ across clients (delta vs cumulative), which can leak
      // thought text or persist only the final few characters.
      final resultHistory = await agent.run(input, useStream: false);

      // Clean up transient directives after run.
      state.systemReminders.remove('system_checkins');
      state.systemReminders.remove('time_request_directive');

      // Scan all ModelMessage turns newest-to-oldest to find the chat reply.
      // Claude sometimes produces text in an earlier turn alongside a tool call
      // (e.g. SendActionMessage), so checking only the last turn can miss it.
      String foundText = '';
      for (final msg in resultHistory.reversed) {
        if (msg is ModelMessage) {
          final t = msg.textOutput ?? '';
          if (t.trim().isNotEmpty) {
            foundText = t;
            break;
          }
        }
      }

      // Some compatible providers occasionally place their internal response
      // planning in textOutput instead of the provider-native thought field.
      // Sanitize before any UI chunk is emitted so hidden reasoning cannot
      // flash on screen, become a chat message, or enter Dreaming extraction.
      foundText = PersonaReplySanitizer.stripLeakedReasoning(foundText);

      // Post-processing: if the agent made a time commitment in text but
      // didn't call reminder_create, run a silent correction turn so the
      // reminder is actually created. This is the safety net for when the
      // pre-processing directive isn't enough.
      final madeTimeCommitment =
          foundText.isNotEmpty && _containsTimeCommitment(foundText);
      final calledReminderCreate = _hasReminderCreateCall(resultHistory);
      if (madeTimeCommitment && !calledReminderCreate) {
        _logger.severe(
          'AGENT DID NOT CALL reminder_create despite time commitment. '
          'User: "${userMessage.length > 80 ? '${userMessage.substring(0, 80)}…' : userMessage}". '
          'Agent: "${foundText.length > 80 ? '${foundText.substring(0, 80)}…' : foundText}". '
          'Running silent correction turn.',
        );
        try {
          await agent.run([
            UserMessage.text(
              '⛔ CORRECTION (silent — user does not see this):\n'
              'Your previous reply said: "$foundText"\n'
              'But you did NOT call `reminder_create`. The reminder was NOT created.\n\n'
              'The user\'s original request was: "$userMessage"\n\n'
              'You MUST call `reminder_create` NOW with the correct delay_minutes '
              'or due_at based on that request.\n\n'
              'IMPORTANT: Only call the tool. Do NOT produce any user-visible '
              'text or chat reply. This is a silent system correction.',
            ),
          ], useStream: false);
          _logger.info('Correction turn complete — reminder should now exist');
        } catch (e) {
          _logger.severe('Correction turn failed: $e');
        }
      }

      if (foundText.isNotEmpty) {
        yield foundText;
      }
    } catch (e, st) {
      _logger.severe('CompanionAgent chat run error', e, st);

      // loopDetection means the model returned empty responses — usually after
      // processing a system trigger with no real user-facing reply needed.
      // Don't surface this as a visible error; just yield nothing so the UI
      // stays clean. Other errors still show the Connection Interrupted banner.
      final isLoopDetection = e.toString().contains('loopDetection') ||
          e.toString().contains('empty response');
      if (isLoopDetection) {
        final recoveredText = _latestAssistantTextAfter(
          agent.state.history.messages,
          runStartedAt,
        );
        if (recoveredText.isNotEmpty) {
          try {
            await saveAgentState(agent.state);
          } catch (saveError) {
            _logger.warning(
              'CompanionAgent: failed to save recovered loop text: $saveError',
            );
          }
          yield recoveredText;
        }
      } else {
        // Real API/connection failure (quota exhausted, 4xx/5xx, timeout).
        // Throw a typed exception instead of yielding the raw error as chat
        // text — otherwise the error dump gets persisted as a character
        // message and later ingested into Dreaming. The UI catches this and
        // shows a transient toast without saving anything. Full detail
        // ($e) is preserved on the exception for logs/Lab, never shown raw.
        throw CompanionApiException(e, st);
      }
    }
  }

  static Future<List<LLMMessage>> _loadChatHistoryTurns({
    required String characterId,
    int? excludeMessageId,
    int limit = 20,
  }) async {
    if (!AppDatabase.isInitialized) return [];
    final db = AppDatabase.instance;
    try {
      final query = db.select(db.personaChatMessages)
        ..where((t) => t.characterId.equals(characterId))
        ..orderBy([(t) => OrderingTerm.desc(t.id)])
        ..limit(limit + 1);
      final rows = await query.get();
      final turns = <LLMMessage>[];
      for (final row in rows) {
        if (row.id == excludeMessageId) continue;
        if (row.content.trim().isEmpty) continue;
        if (turns.length >= limit) break;
        if (row.isFromCharacter) {
          turns.add(ModelMessage(
            textOutput: row.content,
            model: 'history',
            timestamp: row.timestamp.millisecondsSinceEpoch * 1000,
          ));
        } else {
          turns.add(UserMessage(
            [TextPart(row.content)],
            timestamp: row.timestamp.millisecondsSinceEpoch * 1000,
          ));
        }
      }
      return turns.reversed.toList();
    } catch (e) {
      _logger.warning('Failed to load chat history turns: $e');
      return [];
    }
  }

  static String _latestAssistantTextAfter(
    List<LLMMessage> messages,
    int sinceMicros,
  ) {
    for (final msg in messages.reversed) {
      if (msg is! ModelMessage || msg.timestamp < sinceMicros) continue;
      final text = msg.textOutput ?? '';
      if (text.trim().isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  /// Drains at most one pending system trigger into agent state.systemReminders.
  /// Returns the system trigger if one was drained, null otherwise.
  static Future<SystemMessageQueueData?> _drainPendingCheckinsIntoState(
      AgentState state) async {
    try {
      final pending = await CheckinService.instance.drainPending();
      if (pending.isEmpty) return null;

      // Only take one at a time — leave the rest for future runs.
      final row = pending.first;
      await CheckinService.instance.markStatus(row.id, 'processing');

      final buf = StringBuffer();
      buf.writeln('## Internal System Trigger');
      buf.writeln('You have a pending system trigger. '
          'You MUST call system_checkin to process it, then '
          'call set_system_message_status to mark it done.');
      buf.writeln();
      buf.writeln(
          '- [${row.triggerType.toUpperCase()}] (id: ${row.id}) ${row.body}');
      if (row.context != null) {
        buf.writeln('  context: ${row.context}');
      }

      state.systemReminders['system_checkins'] = buf.toString();
      return row;
    } catch (e) {
      _logger.warning('Failed to drain system triggers: $e');
      return null;
    }
  }

  /// Resets processing triggers back to pending so they are not lost.
  static Future<void> _recoverStuckProcessingTriggers() async {
    try {
      await CheckinService.instance.recoverStuckProcessing();
    } catch (e) {
      _logger.warning('Failed to recover stuck triggers: $e');
    }
  }
}
