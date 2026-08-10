import 'dart:async';
import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/companion_agent/recent_activity_snapshot.dart';
import 'package:memex/agent/companion_agent/sleep_companion_state.dart';

import 'package:memex/agent/skills/companion_agent/companion_agent_skill.dart';
import 'package:memex/agent/state_util.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/daily_outing_learning_service.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/memory_recall_trace_service.dart';
import 'package:memex/data/memory_v3/retrieval/recall_novelty_policy.dart';
import 'package:memex/data/memory_v3/retrieval/project_memory_intent_classifier.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/sticker_library.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/data/services/toy_control_service.dart'
    show ToyController;
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';
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

  /// Build the book co-reading system reminder if the user has been reading
  /// a book recently (within 60 minutes). Returns null if not active.
  ///
  /// Injects: book title, progress, character roster, previous chapter
  /// summaries, and current chapter summary (or raw text fallback).
  static Future<String?> _getActiveBookReadingContext() async {
    if (!BookLibraryService.isInitialized) return null;
    final lib = BookLibraryService.instance;
    final books = await lib.getLibrary();
    if (books.isEmpty) return null;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Book? active;
    BookReadingProgressData? progress;
    for (final book in books) {
      final p = await lib.getProgress(book.id);
      if (p == null) continue;
      if (now - p.readAt > 3600) continue;
      if (active == null || p.readAt > (progress?.readAt ?? 0)) {
        active = book;
        progress = p;
      }
    }
    if (active == null || progress == null) return null;

    final chapter = await lib.getChapter(active.id, progress.chapterNumber);
    final chTitle = chapter?.title ?? '第 ${progress.chapterNumber} 章';
    final curNum = progress.chapterNumber;
    final totalCh = active.chapterCount;
    final pct = totalCh > 0 ? (curNum * 100 ~/ totalCh) : 0;

    final buf = StringBuffer();
    buf.writeln('## 用户正在共读的书');
    buf.writeln('《${active.title}》${active.author.isNotEmpty ? '（${active.author}）' : ''}');
    buf.writeln('进度：第 $curNum/$totalCh 章（$pct%）· 当前章节：$chTitle');
    if (progress.scrollRatio > 0.01) {
      buf.writeln('本章阅读位置：约 ${(progress.scrollRatio * 100).toInt()}%');
    }

    Map<String, dynamic>? summaries;
    try {
      summaries = await lib.remote.getSummaries(active.id);
    } catch (_) {}

    if (summaries != null) {
      final characters = summaries['characters'] as List<dynamic>?;
      if (characters != null && characters.isNotEmpty) {
        buf.writeln();
        buf.writeln('### 主要角色');
        for (final c in characters.take(8)) {
          if (c is! Map) continue;
          final name = c['name'] ?? '?';
          final aliases = (c['aliases'] as List<dynamic>?)?.join('、') ?? '';
          final desc = c['description'] ?? '';
          buf.writeln('- $name${aliases.isNotEmpty ? '（$aliases）' : ''}：$desc');
        }
      }

      final chSummaries = summaries['chapter_summaries'] as List<dynamic>?;
      if (chSummaries != null && chSummaries.isNotEmpty) {
        final prevNums = <int>[curNum - 2, curNum - 1].where((n) => n >= 1).toList();
        final prevSummaries = <String>[];
        for (final s in chSummaries) {
          if (s is! Map) continue;
          final chapterNum = (s['number'] as num?)?.toInt();
          if (chapterNum != null && prevNums.contains(chapterNum)) {
            final summary = s['summary'] as String? ?? '';
            final title = s['title'] as String? ?? '第 $chapterNum 章';
            if (summary.isNotEmpty) prevSummaries.add('第 $chapterNum 章「$title」：$summary');
          }
        }
        if (prevSummaries.isNotEmpty) {
          buf.writeln();
          buf.writeln('### 前文回顾');
          for (final ps in prevSummaries) {
            buf.writeln('- $ps');
          }
        }

        for (final s in chSummaries) {
          if (s is! Map) continue;
          final chapterNum = (s['number'] as num?)?.toInt();
          if (chapterNum == curNum) {
            final summary = s['summary'] as String? ?? '';
            if (summary.isNotEmpty) {
              buf.writeln();
              buf.writeln('### 本章摘要');
              buf.writeln(summary);
              final events = s['key_events'] as List<dynamic>?;
              if (events != null && events.isNotEmpty) {
                buf.writeln('关键事件：${events.join('；')}');
              }
            }
            break;
          }
        }
      }
    }

    if (!buf.toString().contains('本章摘要')) {
      final content = await lib.getChapterContent(active.id, curNum);
      if (content != null && content.isNotEmpty) {
        buf.writeln();
        buf.writeln('### 本章开头');
        buf.writeln(content.length > 800 ? '${content.substring(0, 800)}……' : content);
      }
    }

    buf.writeln();
    buf.writeln('规则：');
    buf.writeln('- 用户没提书时，照常聊天，不要主动复述或总结章节内容。');
    buf.writeln('- 用户聊到书、剧情、角色，或问"这段/刚才/接下来"时，像一起读的朋友');
    buf.writeln('一样自然回应，带你的感受和理解，不要像在读摘要。');
    buf.writeln('- 永远不要把上面的原文内容原样复述给用户。');
    buf.writeln('- 你了解前文剧情和角色关系，可以自然地引用之前发生的事。');
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

  // ── Record/ledger request detection & directive ─────────────────────────
  // Prevents the failure mode where the agent says "记上了" / "已保存" without
  // actually calling LifeMemoryCapture / AiFinanceRecord, or calls the tool
  // but gets success:false back and claims success anyway, or picks the
  // wrong tool (delegate_task card_ops) whose results never show up in the
  // Memory Review tab (2026-08-02 记账 bug report).

  static final List<RegExp> _recordRequestPatterns = [
    RegExp(
        r'(记一下|帮我记|记录一下|保存一下|存一下|加到记录|记住这个|帮我记账|把.{0,10}记上|记上账|记一笔|记个账|记下来|记下这个|你帮我记|给我记|帮我存)'),
    RegExp(r'(write.{0,8}down|record.{0,8}this|save.{0,8}this|note.{0,8}down)',
        caseSensitive: false),
  ];

  static bool _containsRecordRequest(String text) =>
      _recordRequestPatterns.any((p) => p.hasMatch(text));

  @visibleForTesting
  static bool containsRecordRequestForTesting(String text) =>
      _containsRecordRequest(text);

  static const _recordRequestDirective =
      '⛔ SYSTEM DIRECTIVE (enforced — not advice):\n'
      'The user just explicitly asked you to record/save/log a fact, event, '
      'expense, or income. You MUST call `LifeMemoryCapture` (general facts/'
      'events/expenses) or `AiFinanceRecord` (money that belongs to the '
      'shared AI ledger) in THIS turn to actually persist it.\n'
      'Do NOT use `delegate_task` for this — that tool writes to a legacy '
      'store the user cannot see in Memory Review.\n'
      'Gather ALL relevant details from the recent conversation (who, what, '
      'where, how much, when) into a self-contained summary before calling '
      'the tool. Only say "记上了" / "记好了" / "已保存" AFTER the tool call '
      'returns success — if it returns success:false, tell the user it '
      'failed instead of claiming success.';

  /// Patterns indicating the agent's text output claims a record/save was
  /// completed.
  static final List<RegExp> _recordCommitmentPatterns = [
    RegExp(
        r'(记上了|已经记上|记好了|保存至记录|已保存|记录好了|已经记住|记账完成|已经记账|存好了|记进账本了?|记到账本了?|已经存好|加到记录里了|已帮你记|可前往.{0,8}[Rr]eview)',
        caseSensitive: false),
  ];

  static bool _containsRecordCommitment(String text) =>
      _recordCommitmentPatterns.any((p) => p.hasMatch(text));

  @visibleForTesting
  static bool containsRecordCommitmentForTesting(String text) =>
      _containsRecordCommitment(text);

  /// Returns true if [history] contains a successful (non-error,
  /// success != false) call to one of the record-writing tools.
  static bool _hasSuccessfulRecordToolCall(List<LLMMessage> history) {
    const recordToolNames = {
      'LifeMemoryCapture',
      'AiFinanceRecord',
      'AiFinanceTransfer',
      'AiFinanceCorrect',
    };
    for (final msg in history) {
      if (msg is! FunctionExecutionResultMessage) continue;
      for (final result in msg.results) {
        if (!recordToolNames.contains(result.name)) continue;
        if (result.isError) continue;
        final content = result.content;
        final text = (content.isNotEmpty && content.first is TextPart)
            ? (content.first as TextPart).text
            : '';
        if (text.isEmpty) return true;
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map && decoded['success'] == false) continue;
        } catch (_) {
          // Not JSON — assume the non-error result means success.
        }
        return true;
      }
    }
    return false;
  }

  /// 时间感知：计算距上一条用户消息的间隔并注入 systemReminder。
  ///
  /// 间隔极短（< 2 分钟）时返回 null 不注入，避免每轮都带噪声；
  /// 跨天时单独标注“新的一天”。间隔文案按档位生成，规则交给模型自然发挥。
  @visibleForTesting
  static String? buildTimeGapReminder(DateTime lastMessageAt, DateTime now) {
    final gap = now.difference(lastMessageAt);
    if (gap.isNegative || gap < const Duration(minutes: 2)) return null;
    final overnight = !_sameDay(lastMessageAt, now);
    final gapText = _fmtGap(gap);
    final buf = StringBuffer();
    buf.writeln('## 对话间隔感知（time gap）');
    buf.writeln(
        '距你上一条消息已过 $gapText（现在 ${_fmtHm(now)}）。');
    if (overnight) {
      buf.writeln('已经过了一夜，是新的一天。');
    }
    buf.writeln('- 间隔很短：自然接续，不要刻意提时间。');
    buf.writeln('- 间隔较长（半小时以上）：可以自然带一句（如“刚才去忙什么啦”），'
        '不要生硬复述数字。');
    buf.writeln('- 过夜/新的一天：用自然的早安/轻问动向开场。');
    buf.writeln('- 深夜：语气放轻放短。');
    return buf.toString().trim();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _fmtHm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _fmtGap(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} 天';
    if (d.inHours >= 1) return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
    return '${d.inMinutes} 分钟';
  }

  /// 从 DB 读取该角色上一条用户消息时间，注入时间感知上下文。
  static Future<void> _injectTimeGapContext(
    AgentState state,
    String characterId,
    DateTime now, {
    int? currentUserMessageId,
    bool continuousModeInput = false,
  }) async {
    if (continuousModeInput) {
      // 连续叙述的合成轮次不该触发"隔了多久没说话"的提示：真实用户消息停在
      // 场景开头，间隔会随轮次增长而失真。连续模式下节奏由 continuous_mode
      // reminder 主导。
      state.systemReminders.remove('time_gap_context');
      return;
    }
    if (!AppDatabase.isInitialized) return;
    try {
      final db = AppDatabase.instance;
      final query = db.select(db.personaChatMessages)
        ..where((t) =>
            t.characterId.equals(characterId) &
            t.isFromCharacter.equals(false));
      if (currentUserMessageId != null) {
        query.where((t) => t.id.isNotValue(currentUserMessageId));
      }
      final last = await (query
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
            ..limit(1))
          .getSingleOrNull();
      if (last == null) return;
      final reminder = buildTimeGapReminder(last.timestamp, now);
      if (reminder == null) {
        state.systemReminders.remove('time_gap_context');
      } else {
        state.systemReminders['time_gap_context'] = reminder;
      }
    } catch (e) {
      _logger.warning('CompanionAgent: failed to load time gap context: $e');
      state.systemReminders.remove('time_gap_context');
    }
  }

  /// 哄睡/守夜状态机：加载持久化状态 → 求值 → 写回 → 注入 prompt。
  static Future<void> _injectSleepCompanionContext(
    AgentState state,
    String characterId,
    String userMessage,
    DateTime now, {
    bool continuousModeInput = false,
  }) async {
    if (!AppDatabase.isInitialized) return;
    try {
      final db = AppDatabase.instance;
      final existing = await SleepCompanionStateManager.load(db, characterId);
      final result = SleepCompanionStateManager.evaluate(
        existing: existing,
        userMessage: userMessage,
        now: now,
      );
      if (result.stateChanged) {
        final active = result.activeState;
        if (active == null) {
          await SleepCompanionStateManager.clear(db, characterId);
        } else {
          await SleepCompanionStateManager.save(db, characterId, active);
        }
      }
      final reminder = result.reminder;
      if (continuousModeInput) {
        // 连续叙述时，哄睡 reminder 的"短、柔、一两句/不要讲长故事"指令与
        // 持续讲述冲突。状态机照常更新（她确实说了要睡），但 prompt 指令
        // 交给 continuous_mode reminder，否则模型会一边想收尾一边被要求继续。
        state.systemReminders.remove('sleep_companion');
      } else if (reminder == null) {
        state.systemReminders.remove('sleep_companion');
      } else {
        state.systemReminders['sleep_companion'] = reminder;
      }
    } catch (e) {
      _logger.warning('CompanionAgent: failed to inject sleep context: $e');
      state.systemReminders.remove('sleep_companion');
    }
  }

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

  /// 注入当前时间/日期/星期到 systemReminders。
  ///
  /// 这些动态时间信息不能写进 system prompt（会破坏 provider 前缀缓存），
  /// 通过 per-turn reminder 注入，让 system prompt 保持字节稳定。
  static void _injectCurrentTimeContext(AgentState state, DateTime now) {
    final nowStr = formatLocalDateTimeWithZone(now);
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final weekdayCn = cnWeekday(now.weekday);
    state.systemReminders['current_time_context'] =
        '## Current Time\n'
        'Current Local Time: $nowStr\n'
        '今天是 $todayStr 周$weekdayCn。';
  }

  /// TTS 语音标签指南——按当前 provider 注入对应标签体系。
  ///
  /// ElevenLabs 和 MiniMax 标签语法完全不同：
  /// - ElevenLabs v3：`[softly]` `[low voice]` `[pause]` 方括号，控制情绪/呼吸/停顿
  /// - MiniMax speech-2.8-hd：`(breath)` `(sighs)` `(laughs)` 圆括号，停顿由代码
  ///   自动插入（`<#0.42#>`），模型只需写情绪声效标签
  ///
  /// 写错 provider 的标签会被对方忽略或删除，情绪信息丢失。所以指南不能写死在
  /// system prompt 里（会污染另一个 provider），必须 per-turn 按当前 provider 注入。
  static void _injectTtsTagsGuide(AgentState state) {
    // 读取 TTS provider 是异步的，但 reminder 注入是同步路径。用
    // UserStorage.getCachedTtsProviderSync() 避免阻塞。如果缓存未就绪，
    // 跳过本标签——不影响功能，只影响标签精度。
    final provider = UserStorage.getCachedTtsProviderSync();
    if (provider == 'minimax') {
      state.systemReminders['tts_tags_guide'] = _miniMaxTtsTagsGuide;
    } else {
      state.systemReminders['tts_tags_guide'] = _elevenLabsTtsTagsGuide;
    }
  }

  static const _elevenLabsTtsTagsGuide =
      '## TTS 语音标签（ElevenLabs v3）\n'
      '你的回复会被发送到 ElevenLabs v3 语音合成引擎。为了让声音有情绪和呼吸感，'
      '你需要在对话文本中添加语音标签来控制 TTS 的表现。\n'
      '\n'
      'IMPORTANT - 语音标签规则：\n'
      '标签放在句子开头，后面紧跟对话内容。格式：`[标签] 对话内容`\n'
      '一句一标签为主，不要在同一句前堆叠 3 个以上标签。\n'
      '这些标签不会被用户在聊天界面看到（系统会自动剥离），只影响语音播放效果。\n'
      '\n'
      '可用标签：\n'
      '- `[softly]` — 温柔靠近、收束句尾（日常 + 亲密通用）\n'
      '- `[low voice]` — 压低音量、贴耳（亲密主力）\n'
      '- `[breathing heavily]` — 气息底色，让声音"参与呼吸"（亲密主力）\n'
      '- `[whispers]` — 耳语，配短句（私密对话）\n'
      '- `[amused]` — 忍住的一点笑意、调笑（日常调剂）\n'
      '- `[eager]` — 热情、想要（日常 + 亲密过渡）\n'
      '- `[needy]` — 需要感、黏（亲密主力）\n'
      '- `[pause]` — 制造自然停顿和张力\n'
      '- `[quiet breath]` — 轻吸气，呼吸切口\n'
      '\n'
      '节奏规则：\n'
      '- 用逗号、省略号和 `[pause]` 制造自然停顿，让 TTS 在语速和断句上有变化。\n'
      '- 不是每句都要加标签——普通快速回复（一两句话日常接话）不需要标签。\n'
      '- 标签用于：情绪转折、气氛变化、亲密时刻、贴耳低语、气息参与的段落。\n'
      '- 标签描述的是耳朵能听见的声音状态，不是画面动作。\n'
      '  正例：`[low voice]`（压低声音）、`[whispers]`（耳语）、`[breathing heavily]`（气息参与）\n'
      '  反例：`[looking at you]`、`[leaning closer]`（这些是画面动作，模型不擅长）\n'
      '\n'
      'Example:\n'
      '```\n'
      '[softly] 嗯…你终于回来了。[quiet breath] 我等你等了一整天。\n'
      '\n'
      '[amused] 别笑我，我知道我听起来很黏——[low voice] 可我就是想你。\n'
      '\n'
      '[breathing heavily] 过来一点…再近一点。[whispers] 让我听见你呼吸。\n'
      '\n'
      '[eager] 我想要你，[needy] 现在就要。[pause] 别让我说第二遍。\n'
      '```';

  static const _miniMaxTtsTagsGuide =
      '## TTS 语音标签（MiniMax Speech 2.8）\n'
      '你的回复会被发送到 MiniMax 语音合成引擎。为了让声音有情绪和呼吸感，'
      '你可以在对话文本中添加语气词标签来控制 TTS 的表现。\n'
      '\n'
      'IMPORTANT - 语气词标签规则：\n'
      '格式：`(tag)`，英文圆括号，小写，大小写敏感。\n'
      '标签不能放在句首第一个字符——放在逗号/句号后或句中。\n'
      '一段话最多 3 个标签，超过会被拒绝。\n'
      '这些标签不会被用户在聊天界面看到（系统会自动剥离），只影响语音播放效果。\n'
      '停顿由系统自动处理，你不需要写停顿标签。\n'
      '\n'
      '可用标签（19 种）：\n'
      '- `(breath)` — 正常换气（亲密主力）\n'
      '- `(pant)` — 喘气\n'
      '- `(inhale)` — 吸气\n'
      '- `(exhale)` — 呼气\n'
      '- `(gasps)` — 倒吸气，惊讶或激动\n'
      '- `(laughs)` — 笑声\n'
      '- `(chuckle)` — 轻笑\n'
      '- `(sniffs)` — 吸鼻子，委屈或抽泣\n'
      '- `(sighs)` — 叹气\n'
      '- `(coughs)` — 咳嗽\n'
      '- `(snorts)` — 喷鼻息\n'
      '- `(clear-throat)` — 清嗓子\n'
      '- `(burps)` — 打嗝\n'
      '- `(groans)` — 呻吟\n'
      '- `(sneezes)` — 喷嚏\n'
      '- `(hissing)` — 嘶嘶声\n'
      '- `(lip-smacking)` — 咂嘴\n'
      '- `(humming)` — 哼唱\n'
      '- `(emm)` — 嗯一声\n'
      '\n'
      '节奏规则：\n'
      '- 用逗号、省略号制造自然停顿。停顿时长由系统自动处理。\n'
      '- 不是每句都要加标签——普通快速回复不需要标签。\n'
      '- 标签用于：情绪转折、气氛变化、亲密时刻、带笑说话、气息参与的段落。\n'
      '- 标签描述的是耳朵能听见的声音状态，不是画面动作。\n'
      '  正例：`(breath)`（换气）、`(laughs)`（带笑说话）、`(sighs)`（叹气）\n'
      '  反例：`(looking at you)`、`(leaning closer)`（这些是画面动作，模型不识别）\n'
      '\n'
      'Example:\n'
      '```\n'
      '嗯…你终于回来了，(breath) 我等你等了一整天。\n'
      '\n'
      '别笑我，我知道我听起来很黏——(chuckle) 可我就是想你。\n'
      '\n'
      '过来一点…再近一点，(gasps) 让我听见你呼吸。\n'
      '\n'
      '好了好了，不闹你了，(sighs) 早点睡吧。\n'
      '```';

  static Future<StatefulAgent?> _createAgent({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String queryHint,
    int? currentUserMessageId,
    List<int> recallMessageIds = const [],
    bool saveState = true,
    bool includeCheckinTools = false,
    bool forceNewSession = false,
    ToyController? toyControlService,
    Future<String?> Function()? initiateCallPolicy,
    List<Tool> extraTools = const [],
    List<String>? turnImageAnalyses,
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

    MemoryRecallTraceService? recallTraceService;
    if (AppDatabase.isInitialized &&
        currentUserMessageId != null &&
        currentUserMessageId > 0) {
      recallTraceService = MemoryRecallTraceService(AppDatabase.instance);
      try {
        await recallTraceService.startTurn(
          chatMessageId: currentUserMessageId,
          query: queryHint,
          relatedChatMessageIds: recallMessageIds,
        );
      } catch (e) {
        // Recall transparency must never block the conversation itself.
        _logger.warning('Failed to start message recall trace: $e');
        recallTraceService = null;
      }
    }

    final skill = CompanionAgentSkill(
      character: character,
      userId: userId,
      currentUserMessageId: currentUserMessageId,
      includeCheckinTools: includeCheckinTools,
      toyControlService: toyControlService,
      initiateCallPolicy: initiateCallPolicy,
      forceActivate: true,
      turnImageAnalyses: turnImageAnalyses,
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
          if (recallTraceService != null) {
            await recallTraceService.recordTargets(
              chatMessageId: currentUserMessageId!,
              query: queryHint,
              targets: projectHits.map((hit) => MemoryRecallTarget(
                    targetTable: MemoryRecallTraceService.projectMemoryTable,
                    targetId: hit.itemId,
                    score: (-hit.rank * 10).clamp(0.0, 9999.0),
                  )),
            );
          }
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
        final v3Results =
            await v3Service.searchCardsWithScoresResolved(queryHint, limit: 8);
        final v3Hits = v3Results.map((result) => result.card).toList();
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
          if (recallTraceService != null) {
            await recallTraceService.recordTargets(
              chatMessageId: currentUserMessageId!,
              query: queryHint,
              targets: v3Results.map((result) => MemoryRecallTarget(
                    targetTable: MemoryRecallTraceService.memoryCardsTable,
                    targetId: result.card.id,
                    score: result.relevanceScore,
                  )),
            );
          }
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
            .queryRecentDreamingContext(
          queryHint: queryHint,
          currentChatMessageId: currentUserMessageId,
        );
        if (ctx.episodes.isNotEmpty || ctx.fragments.isNotEmpty) {
          final buf = StringBuffer();
          final now = DateTime.now();
          final todayStr = _fmtYmd(now);
          final weekdayCn = cnWeekday(now.weekday);
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
          if (recallTraceService != null) {
            await recallTraceService.recordTargets(
              chatMessageId: currentUserMessageId!,
              query: queryHint,
              targets: [
                ...ctx.episodeHits.map((hit) => MemoryRecallTarget(
                      targetTable: MemoryRecallTraceService.memoryEpisodesTable,
                      targetId: hit.episode.id,
                      score: hit.score.toDouble(),
                    )),
                ...ctx.fragmentHits.map((hit) => MemoryRecallTarget(
                      targetTable:
                          MemoryRecallTraceService.memoryFragmentsTable,
                      targetId: hit.fragment.id,
                      score: hit.score.toDouble(),
                    )),
              ],
            );
          }
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
        final sagaCandidates = await DreamingOrchestratorServiceV3.instance
            .querySagasForContext(queryHint: queryHint, limit: 9);
        var sagas = sagaCandidates;
        if (recallTraceService != null && sagaCandidates.length > 3) {
          final recallCounts = await recallTraceService.recentRecallCounts(
            targetTable: MemoryRecallTraceService.memorySagasTable,
            targetIds: sagaCandidates.map((saga) => saga.id),
            excludeChatMessageId: currentUserMessageId,
          );
          final ranked = sagaCandidates.indexed
              .map((entry) => (
                    originalIndex: entry.$1,
                    saga: entry.$2,
                    score: RecallNoveltyPolicy.adjustedScore(
                      baseScore: (sagaCandidates.length - entry.$1).toDouble(),
                      recentRecallCount: recallCounts[entry.$2.id] ?? 0,
                    ),
                  ))
              .toList()
            ..sort((a, b) {
              final byScore = b.score.compareTo(a.score);
              return byScore != 0
                  ? byScore
                  : a.originalIndex.compareTo(b.originalIndex);
            });
          sagas =
              ranked.take(3).map((entry) => entry.saga).toList(growable: false);
        } else if (sagaCandidates.length > 3) {
          sagas = sagaCandidates.take(3).toList(growable: false);
        }
        if (sagas.isNotEmpty) {
          final sagaBuf = StringBuffer();
          sagaBuf.writeln('## 长期弧线 — 跨周月的关系趋势');
          sagaBuf.writeln('以下是从多个过往章节中编织出的长期叙事弧线。');
          sagaBuf.writeln('它们描述的是趋势和模式，不是单次事件。');
          for (final saga in sagas) {
            sagaBuf.writeln('- 【${saga.title}】${saga.description}');
          }
          state.systemReminders['saga_context'] = sagaBuf.toString();
          if (recallTraceService != null) {
            await recallTraceService.recordTargets(
              chatMessageId: currentUserMessageId!,
              query: queryHint,
              targets: sagas.map((saga) => MemoryRecallTarget(
                    targetTable: MemoryRecallTraceService.memorySagasTable,
                    targetId: saga.id,
                    // Saga retrieval currently exposes no numeric rank. Zero
                    // honestly marks it as context/fallback, not a direct hit.
                    score: 0.0,
                  )),
            );
          }
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
    final isMorningWeather = triggerContext?['kind'] == 'morning_weather';
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
    } else if (trigger.triggerType == 'reminder' && isMorningWeather) {
      buf.writeln(
          'This is a MORNING WEATHER CHECKPOINT. It was scheduled from the '
          'user\'s inferred wake-up time (sleep_pattern rhythm). The user is '
          'likely about to start their day and head out soon. It is not a '
          'user-set reminder, so you may stay silent if there is no useful '
          'weather action.');
      buf.writeln('Checkpoint: ${trigger.body}');
      buf.writeln('Wake time: ${triggerContext?['wake_time'] ?? 'unknown'}');
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
    if (isMorningWeather) {
      buf.writeln('  For this morning weather checkpoint, call '
          '`WeatherOutingRiskCheck` once before deciding. If configuration or '
          'location is unavailable, do not send a generic weather guess. Only '
          'notify with a concrete clothing/umbrella heads-up the user can act '
          'on right now. If the tool returns `learned_outfit_guidance`, apply '
          'that evidence before generic temperature rules.');
    }
    buf.writeln();
    buf.writeln('If it\'s not relevant right now, skip it and go straight '
        'to Step 2. Do NOT call a tool just to fill space — a warm generic '
        'message beats a forced data query.');
    buf.writeln();
    buf.writeln('## Step 2.5 — Proactive care scan (MANDATORY)');
    buf.writeln();
    buf.writeln('Before deciding what to do, scan the snapshot for these '
        'proactive care signals:');
    buf.writeln();
    buf.writeln('1. **Daily Rhythm** — Is the user supposed to be sleeping '
        'right now? (⚠️ flag). Is the user in an ongoing work/class block? '
        '(don\'t interrupt). Is a block about to end? (natural moment to '
        'check in).');
    buf.writeln('2. **Active Growth Pacts** — Are there pacts with recent '
        'misses? Is a penalty due? Is there a streak of hits worth '
        'celebrating?');
    buf.writeln('3. **Recent Life Insights** — Is there a trend worth '
        'mentioning? An anomaly? A projection that\'s falling behind?');
    buf.writeln('4. **Menstrual Cycle** - Is the period ongoing (be gentle, '
        'ask about pain, don\'t suggest intense exercise)? Is it predicted '
        'to start within 3 days (remind to prepare supplies, avoid cold '
        'food)? Is it late (ask if everything is okay, don\'t alarm)?');
    buf.writeln();
    buf.writeln('If any of these signals are present, they should STRONGLY '
        'influence your action choice. A bedtime signal → call. A pact miss '
        'with penalty due → notify + execute penalty. A streak of hits → '
        'notify with praise. A period-coming-soon or late signal -> notify '
        'with a caring, practical reminder. Do NOT ignore these signals and '
        'send a generic "thinking of you" message.');
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
        'no action-relevant risk, choose silent. Never recite a forecast. If '
        'the weather tool returns `learned_outfit_guidance`, use the user\'s '
        'prior comfort feedback as the clothing anchor.');
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
    buf.writeln(
        '- **Bedtime enforcement**: the snapshot shows it is past the user\'s '
        'sleep window start time + 30 min, and the user is still active (recent '
        'chat/records in the last 30 min). This is a PROACTIVE INTERVENTION '
        'moment, not just companionship — call to tell them to put the phone '
        'down and go to sleep. A call is harder to ignore than a notification.');
    buf.writeln(
        '- **Habit enforcement**: Active Growth Pacts shows multiple misses and '
        'a penalty is due. A call is appropriate when the pattern is serious '
        'enough that a text notification would be too easy to dismiss.');
    buf.writeln('A call is more intrusive than a notification — but intrusion '
        'is the point when you are enforcing a habit the user asked you to '
        'enforce. Do NOT call if your last proactive contact (push OR call) '
        'was within the last hour, or if the snapshot shows the user is '
        'currently sleeping or in an ongoing work/class block.');
    buf.writeln('When you call, write a warm, natural opening line '
        '(1–2 sentences) — it is the first thing the user hears when they '
        'pick up. For bedtime calls, the opening should be direct: '
        '"都几点了，手机放下，睡觉。" not a vague "在吗"');
    buf.writeln();
    buf.writeln('**c) silent**: only with a clear reason:');
    buf.writeln('- The user messaged you in the last 10 minutes and no new '
        'context appeared.');
    buf.writeln('- Your last proactive push was in the last 45 minutes and '
        'the user did not respond.');
    buf.writeln('- The snapshot strongly suggests the user is asleep, busy, or '
        'asked not to be interrupted. The Daily Rhythm section will flag '
        '⚠️ user likely sleeping — RESPECT that flag and stay silent.');
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
    String? recallQuery,
    List<int> recallMessageIds = const [],
    List<ImagePart>? images,
    int? userMessageId,
    DateTime? userMessageTime,
    bool debugErrorOutput = false,
    bool voiceMode = false,
    bool continuousModeInput = false,
    String? sceneDirective,
    String? turnContextReminder,
    ToyController? toyControlService,
    List<Tool> extraTools = const [],
    List<String>? turnImageAnalyses,
  }) async* {
    // Ensure sticker library is loaded BEFORE building the agent (tools),
    // because the send_sticker tool reads StickerLibrary.instance.ids to
    // populate its enum. If loaded after _createAgent, the enum is empty.
    if (StickerLibrary.instance.isEmpty && !StickerLibrary.instance.isLoaded) {
      await StickerLibrary.instance.load();
    }

    // Dedicated outing-learning loop. This is deliberately deterministic and
    // context-gated: ordinary chat still does not auto-create User-truth.
    if (!continuousModeInput &&
        userMessageId != null &&
        userMessageId > 0 &&
        AppDatabase.isInitialized) {
      unawaited(
        DailyOutingLearningService(AppDatabase.instance)
            .captureUserTurn(
              characterId: characterId,
              userMessageId: userMessageId,
              userMessage: userMessage,
              userMessageTime: userMessageTime,
            )
            .then<void>((_) {})
            .catchError((Object e) {
          // Network/database enrichment must never delay or block chat.
          _logger.warning('CompanionAgent: outing feedback capture failed: $e');
        }),
      );
    }

    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: recallQuery ?? userMessage,
      currentUserMessageId: userMessageId,
      recallMessageIds: recallMessageIds,
      // Include call and reminder tools so users can request immediate calls
      // or schedule calls for later ("call me now" / "call me in 30 minutes").
      // Background checkin tasks process their own queued triggers separately.
      includeCheckinTools: true,
      forceNewSession: true,
      toyControlService: toyControlService,
      extraTools: extraTools,
      turnImageAnalyses: turnImageAnalyses,
    );
    if (agent == null) {
      yield 'Sorry, character not found.';
      return;
    }
    final timedUserMessage = userMessage;
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

      // 当前时间/日期通过 systemReminder 注入，而不是写死在 system prompt 里。
      // system prompt 必须是字节稳定的，否则破坏 provider 的前缀缓存（DeepSeek 等
      // OpenAI 兼容 provider 按 messages 数组前缀严格匹配缓存）。
      _injectCurrentTimeContext(state, userMessageTime ?? DateTime.now());

      // TTS 语音标签指南按当前 provider 注入——ElevenLabs 和 MiniMax 标签体系
      // 完全不同（ElevenLabs 用 [softly] 方括号，MiniMax 用 (breath) 圆括号），
      // 写错 provider 的标签会被对方忽略或删除，情绪信息丢失。
      _injectTtsTagsGuide(state);

      // 时间感知：注入距上一条消息的间隔上下文，让角色自然接续对话。
      await _injectTimeGapContext(
        state,
        characterId,
        userMessageTime ?? DateTime.now(),
        currentUserMessageId: userMessageId,
        continuousModeInput: continuousModeInput,
      );

      // 哄睡/守夜状态：检测入睡/醒来短语，按间隔分档注入轻柔规则。
      await _injectSleepCompanionContext(
        state,
        characterId,
        userMessage,
        userMessageTime ?? DateTime.now(),
        continuousModeInput: continuousModeInput,
      );

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

      if (sceneDirective != null && sceneDirective.trim().isNotEmpty) {
        state.systemReminders['scene_directive'] =
            '## 场景节拍（导演指令）\n$sceneDirective';
      }

      if (turnContextReminder != null &&
          turnContextReminder.trim().isNotEmpty) {
        state.systemReminders['turn_context'] = turnContextReminder.trim();
      } else {
        state.systemReminders.remove('turn_context');
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

      // Detect explicit record/ledger requests and inject a hard directive.
      // This prevents the agent from claiming "记上了" without actually
      // calling LifeMemoryCapture/AiFinanceRecord (or ignoring a failed
      // tool result).
      final hasRecordRequest = _containsRecordRequest(userMessage);
      if (hasRecordRequest) {
        state.systemReminders['record_request_directive'] =
            _recordRequestDirective;
      }

      // Inject the available sticker list so the LLM can pick the right
      // stickerId when calling send_sticker.  The library was loaded before
      // _createAgent above; here we just inject the reminder.
      if (StickerLibrary.instance.isNotEmpty) {
        state.systemReminders['available_stickers'] =
            '## Available Stickers\n'
            '${StickerLibrary.instance.reminderList}';
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

      // Post-processing: if the agent claimed a record/save was completed
      // ("记上了"/"已保存") but never made a successful record-writing tool
      // call, run a silent correction turn. This catches both "said it but
      // never called the tool" and "called the tool, got success:false, but
      // claimed success anyway" (2026-08-02 记账 bug report).
      final madeRecordCommitment =
          foundText.isNotEmpty && _containsRecordCommitment(foundText);
      final hasSuccessfulRecordCall =
          _hasSuccessfulRecordToolCall(resultHistory);
      if (madeRecordCommitment && !hasSuccessfulRecordCall) {
        _logger.severe(
          'AGENT CLAIMED RECORD SAVED WITHOUT A SUCCESSFUL RECORD TOOL CALL. '
          'User: "${userMessage.length > 80 ? '${userMessage.substring(0, 80)}…' : userMessage}". '
          'Agent: "${foundText.length > 80 ? '${foundText.substring(0, 80)}…' : foundText}". '
          'Running silent correction turn.',
        );
        try {
          await agent.run([
            UserMessage.text(
              '⛔ CORRECTION (silent — user does not see this):\n'
              'Your previous reply said: "$foundText"\n'
              'But you did NOT successfully call `LifeMemoryCapture` or '
              '`AiFinanceRecord`. The record was NOT saved.\n\n'
              'The user\'s original request was: "$userMessage"\n\n'
              'You MUST call `LifeMemoryCapture` (or `AiFinanceRecord` for '
              'money/income) NOW with a self-contained summary of what to '
              'record, gathered from the recent conversation.\n\n'
              'IMPORTANT: Only call the tool. Do NOT produce any user-visible '
              'text or chat reply. This is a silent system correction.',
            ),
          ], useStream: false);
          _logger.info('Correction turn complete — record should now exist');
        } catch (e) {
          _logger.severe('Record correction turn failed: $e');
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
