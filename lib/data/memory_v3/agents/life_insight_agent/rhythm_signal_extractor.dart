/// Rhythm Signal Extractor — detects recurring schedule/routine mentions
/// in chat messages and writes them as UserRhythms.
///
/// Runs alongside LifeInsight analysis. Two extraction layers:
/// 1. **Deterministic regex layer** (always runs, no LLM): catches
///    well-formed routine statements ("我7点下班", "周二五日晚上10点到
///    11点半上网课", "一般1点才睡") reliably and cheaply.
/// 2. **LLM layer** (runs only when the deterministic layer found
///    nothing): detects looser phrasings.
///
/// This is the "conversation → structured rhythm" bridge that solves the
/// "told you 100 times I get off work at 7pm but you still ask at 5pm" problem.
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('memory_v3.RhythmSignalExtractor');

class RhythmSignalExtractor {
  const RhythmSignalExtractor();

  /// Extract rhythm signals from recent chat messages and write them to
  /// UserRhythmService.
  ///
  /// [existingRhythms] is passed to the LLM so it doesn't re-detect rhythms
  /// that are already stored.
  Future<int> extractAndPersist({
    required LLMClient client,
    required ModelConfig modelConfig,
    required AppDatabase db,
    required String characterId,
    int messageLimit = 100,
  }) async {
    if (!UserRhythmService.isInitialized) return 0;

    // 1. Load recent chat messages. Two windows:
    //   - [messages] (wide): 7 days ∩ 2000 cap, used by lifecycle actions and
    //     the deterministic layer. Heavy chatters can burn through 100
    //     messages in a day, which pushed canonical routine declarations
    //     ("7点下班", "周二五日10点到11点半上课") out of the old count-only
    //     window before they were ever extracted. Regex scanning is cheap,
    //     so the wide window is free.
    //   - [llmMessages] (narrow): the same window capped at [messageLimit]
    //     for the LLM layer, keeping prompt size/cost bounded.
    // Timestamps are stored in seconds (drift dateTime() default).
    final since = DateTime.now().subtract(const Duration(days: 7));
    final messages = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.messageType.equals('chat') &
              t.timestamp.isBiggerOrEqualValue(since))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(2000))
        .get();

    if (messages.isEmpty) return 0;
    final llmMessages =
        messages.length <= messageLimit ? messages : messages.sublist(0, messageLimit);

    // 2. Load existing rhythms once — shared by lifecycle actions, the
    // freshness filter and the upsert dedup path below.
    final existingRhythms =
        await UserRhythmService.instance.getActiveRhythms();

    // 3. Lifecycle actions first — terminations ("实习结束了") and one-off
    //    cancellations ("今天这节课不上了"). Always applied regardless of
    //    freshness: they are explicit user actions on existing rhythms.
    await _applyLifecycleActions(messages, existingRhythms);

    // 4. Deterministic extraction — regex-based, no LLM. Covers the
    // canonical routine phrasings reliably even when the configured model
    // is unavailable / rejects the payload (observed: 422 on large inputs).
    final deterministicSignals =
        extractDeterministicSignals(messages, existingRhythms);
    if (deterministicSignals.isNotEmpty) {
      final created = await _persistSignals(deterministicSignals);
      _logger.info('Rhythm deterministic extraction created/updated '
          '$created rhythm(s)');
      return created;
    }

    // 5. Build LLM prompt — only messages newer than the newest rhythm
    // update, so old statements can't resurrect stale values via the LLM.
    final threshold = existingRhythms.isEmpty
        ? 0
        : existingRhythms
            .map((r) => r.updatedAt)
            .reduce((a, b) => a > b ? a : b);
    final chatText = llmMessages.reversed
        .where((m) => !m.isFromCharacter)
        .where((m) => m.timestamp.millisecondsSinceEpoch > threshold)
        .map((m) {
      final speaker = m.isFromCharacter ? 'I' : 'user';
      final ts = m.timestamp;
      final dateStr = '${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
      return '[$dateStr] $speaker: ${m.content}';
    }).join('\n');

    final systemPrompt = _buildPrompt(
      existingRhythms:
          existingRhythms.map((r) => '${r.kind}: ${r.description}').toList(),
    );

    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 2048,
      extra: modelConfig.extra,
    );

    final response = await client.generate(
      [
        SystemMessage(systemPrompt),
        UserMessage([TextPart(chatText)]),
      ],
      modelConfig: mc,
    );

    final text = response.textOutput?.trim();
    if (text == null || text.isEmpty) return 0;

    // 5. Parse and persist
    final signals = _parseSignals(text);
    if (signals.isEmpty) return 0;

    return _persistSignals(signals);
  }

  /// Shared upsert path for both extraction layers.
  Future<int> _persistSignals(List<RhythmSignal> signals) async {
    final existingRhythms =
        await UserRhythmService.instance.getActiveRhythms();

    var created = 0;
    for (final signal in signals) {
      try {
        // Upsert semantics: if a rhythm of the same kind with an
        // overlapping description already exists, UPDATE it instead of
        // skipping — the user's routine can change ("7点下班" → "8点下班"),
        // and the newer extraction must win. Only skip when both the
        // rrule and location already match (true no-op duplicate).
        final existing = existingRhythms.where((r) =>
            r.kind == signal.kind &&
            _descriptionsOverlap(r.description, signal.description));
        if (existing.isNotEmpty) {
          final target = existing.first;
          final unchanged =
              target.rrule == signal.rrule && target.location == signal.location;
          if (unchanged) {
            _logger.fine('Rhythm signal skipped (identical): '
                '${signal.kind} ${signal.description}');
            continue;
          }
          await UserRhythmService.instance.updateRhythm(
            target.id,
            description: signal.description,
            rrule: signal.rrule,
            location: signal.location,
            confidence: signal.confidence,
          );
          // Keep the in-memory view consistent for subsequent signals:
          // replace the consumed entry with its updated form.
          final idx = existingRhythms.indexOf(target);
          if (idx >= 0) {
            existingRhythms[idx] = target.copyWith(
              description: signal.description,
              rrule: signal.rrule,
              location: signal.location,
              confidence: signal.confidence,
            );
          }
          created++;
          _logger.info('Rhythm signal updated: ${signal.kind} '
              '"${signal.description}" rrule=${signal.rrule}');
          continue;
        }

        // Note: menstrual_cycle signals are intentionally NOT handled here.
        // Period tracking is driven by menstrual_record Memory Cards via
        // UserRhythmService.rebuildMenstrualRhythmFromCards(), not by chat
        // signal extraction. This avoids double-writes and respects the
        // memory contract (User-truth only via explicit record actions).

        await UserRhythmService.instance.createRhythm(
          kind: signal.kind,
          description: signal.description,
          rrule: signal.rrule,
          location: signal.location,
          authority: 'agent_inferred',
          origin: 'conversation',
          confidence: signal.confidence,
        );
        created++;
        _logger.info('Rhythm signal captured: ${signal.kind} '
            '"${signal.description}" rrule=${signal.rrule}');
      } catch (e) {
        _logger.warning('Failed to persist rhythm signal: $e');
      }
    }

    return created;
  }

  // ────────────────────────────────────────────────────────────────────
  // Lifecycle actions — termination & one-off cancellation
  // ────────────────────────────────────────────────────────────────────────────

  /// Test entry point for the lifecycle action scan (termination +
  /// one-off cancellation). Production callers go through
  /// [extractAndPersist]; tests use this directly to avoid needing an
  /// LLM client.
  static Future<void> applyLifecycleActionsForTest(
          List<PersonaChatMessage> messages, List<UserRhythm> existing) =>
      const RhythmSignalExtractor()._applyLifecycleActions(messages, existing);

  /// Test entry point for [_resolveDayToken].
  static String? resolveDayTokenForTest(String token, DateTime msgTime) =>
      _resolveDayToken(token, msgTime);

  /// Detect and apply rhythm lifecycle actions from user messages:
  /// - **Termination** ("实习结束了"/"课上完了"/"离职了") → expireRhythm。
  ///   行保留、validUntil=now：历史还在，但不再注入 snapshot。只在确实
  ///   存在匹配的活跃节律时才执行——避免误杀。
  /// - **One-off cancellation** ("今天这节课不上了"/"明天的课取消了") →
  ///   addException(rhythmId, date)。节律本身不动，只是那天跳过。
  ///
  /// 歧义消解：日期词 + 取消标记 = 单次例外；"不上了/不干了"且无日期词
  /// = 终止。日常"下班"永不触发终止（"班"前的"下"被排除）。
  Future<void> _applyLifecycleActions(List<PersonaChatMessage> messages,
      List<UserRhythm> existingRhythms) async {
    final dayTokenRe = RegExp(
        r'(今天|今日|明天|明日|后天|(?:这|下)?(?:周|星期|礼拜)[一二三四五六日天])');
    // 强标记：明确的取消表述。弱标记：请假/调休，需要用户主语且不是 routine
    // 描述才生效（真机误判："请假了，我先把周四周六的班级的作业改了"把
    // "周四"解析成下个周四、把 routine 班次当单日取消；"雨已经停了"把
    // 天气"停了"当取消词——“停了”已从强标记移除）。
    final strongCancelRe =
        RegExp(r'(不上|不去了|取消了|不用上|停课|没课|没班)');
    final weakCancelRe = RegExp(r'(请假|调休|临时有事)');
    // 两个及以上周X日期词 = routine 班次描述（"周四周六的班级"），不是单日。
    final weekdayTokenRe = RegExp(r'(?:周|星期|礼拜)[一二三四五六日天]');
    final termRe = RegExp(
        r'(课|实习|兼职|工作|班).{0,6}(?:结束了|上完了|结课了|完了|停了|不上了|不干了|离职了|辞职了)');

    // 自愈：本次扫描确认过“今天有取消声明”的 rhythm；其余带“今天”例外的
    // rhythm 视为历史误判，撤销——防止昨天的误判影响今天的 snapshot。
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final todayCancelled = <String>{};

    for (final m in messages) {
      if (m.isFromCharacter) continue;
      final text = m.content;
      if (text.contains('?') || text.contains('？')) continue;

      // 1) 单次取消：日期词 + 取消标记。
      final dayMatch = dayTokenRe.firstMatch(text);
      if (dayMatch != null) {
        final strong = strongCancelRe.hasMatch(text);
        final weak = weakCancelRe.hasMatch(text);
        if (strong || weak) {
          final routinePhrasing =
              weekdayTokenRe.allMatches(text).length >= 2;
          // 弱标记（请假/调休）：要求用户主语“我”、不是“学生请假”、
          // 且不是 routine 班次描述。
          final weakOk = weak &&
              !routinePhrasing &&
              text.contains('我') &&
              !text.contains('学生');
          final strongOk = strong && !routinePhrasing;
          if (strongOk || weakOk) {
            final dateStr = _resolveDayToken(dayMatch.group(1)!, m.timestamp);
            if (dateStr == null) continue;
            final kind = _rhythmKindFromContext(text);
            final candidates = existingRhythms
                .where((r) => r.kind == kind && r.validUntil == null)
                .toList();
            if (candidates.isEmpty) continue;
            // 多个候选（少见）：应用于最近更新的那个。
            final target =
                candidates.reduce((a, b) => a.updatedAt > b.updatedAt ? a : b);
            if (UserRhythmService.parseExceptions(target.exceptionsJson)
                .contains(dateStr)) {
              continue; // idempotent
            }
            await UserRhythmService.instance.addException(target.id, dateStr);
            if (dateStr == todayStr) todayCancelled.add(target.id);
            _logger.info('Rhythm one-off cancellation applied: '
                '${target.kind} "${target.description}" date=$dateStr');
            continue;
          }
        }
      }

      // 2) 终止：结束表述 + 上下文词。
      final termMatch = termRe.firstMatch(text);
      if (termMatch == null) continue;
      final ctx = termMatch.group(1)!;
      if (ctx == '班' &&
          termMatch.start > 0 &&
          text[termMatch.start - 1] == '下') {
        continue; // 下班 = 日常下班，不是终止
      }
      // "班级结束了"：上下文词是"班"，但"班"后紧跟"级"= 班级语境 → class。
      final classCtx = ctx == '课' ||
          (ctx == '班' &&
              termMatch.start + 1 < text.length &&
              text[termMatch.start + 1] == '级');
      final kinds = classCtx
          ? {'class_schedule'}
          : ctx == '班' || ctx == '实习' || ctx == '工作'
              ? {'work_schedule'}
              : {'work_schedule', 'class_schedule'}; // 兼职：两边都可能
      var victims = existingRhythms
          .where((r) => kinds.contains(r.kind) && r.validUntil == null)
          .toList();
      // 兼职类表述：优先只结束描述里提到同一上下文词的节律，避免
      // "兼职结束了"误杀同类的另一个节律。
      if (ctx == '兼职' && victims.length > 1) {
        final described =
            victims.where((r) => r.description.contains('兼职')).toList();
        if (described.isNotEmpty) victims = described;
      }
      for (final v in victims) {
        await UserRhythmService.instance.expireRhythm(v.id);
        _logger.info('Rhythm terminated: ${v.kind} '
            '"${v.description}" (user said it ended)');
      }
      if (victims.isNotEmpty) {
        existingRhythms.removeWhere(victims.contains);
      }
    }

    // 3) 自愈：已有“今天”例外但没有对应取消声明 → 撤销。
    //    误判来源如“周四周六的班级…请假了”把 routine 班次解析成单日。
    for (final r in existingRhythms) {
      if (r.validUntil != null) continue;
      if (!UserRhythmService.isExceptedOn(r, DateTime.now())) continue;
      if (todayCancelled.contains(r.id)) continue;
      await UserRhythmService.instance.removeException(r.id, todayStr);
      _logger.info('Rhythm exception self-healed (no cancellation today): '
          '${r.kind} "${r.description}" date=$todayStr');
    }
  }

  /// 取消上下文 → 节律 kind：含"课" → class，其余（班/上班/无上下文）→ work。
  static String _rhythmKindFromContext(String text) {
    if (text.contains('课')) return 'class_schedule';
    return 'work_schedule';
  }

  /// 日期词 → yyyy-MM-dd，相对**消息时间**（不是提取时间——批处理是
  /// 事后跑的）。"周三" = 从消息当天起的下一个周三（当天是周三就是
  /// 当天）；"下周X" 永远跳到下周。
  static String? _resolveDayToken(String token, DateTime msgTime) {
    DateTime day;
    if (token == '今天' || token == '今日') {
      day = msgTime;
    } else if (token == '明天' || token == '明日') {
      day = msgTime.add(const Duration(days: 1));
    } else if (token == '后天') {
      day = msgTime.add(const Duration(days: 2));
    } else {
      final wdChar = token.substring(token.length - 1);
      const isoMap = {
        '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
      };
      final iso = isoMap[wdChar];
      if (iso == null) return null;
      var delta = iso - msgTime.weekday;
      if (delta < 0) delta += 7;
      if (token.contains('下') && delta < 7) delta += 7;
      day = msgTime.add(Duration(days: delta));
    }
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Deterministic extraction layer (no LLM)
  // ────────────────────────────────────────────────────────────────────

  static final _weekdayMap = {
    '一': 'MO', '二': 'TU', '三': 'WE', '四': 'TH',
    '五': 'FR', '六': 'SA', '日': 'SU', '天': 'SU',
  };

  static final _cnDigitMap = {
    '零': 0, '一': 1, '两': 2, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    '十一': 11, '十二': 12,
  };

  /// Parse a time-of-day token: "10:00" / "22:30" / "7点" / "十点半" / "8点半".
  /// Returns (hour, minute) or null.
  static (int, int)? _parseTimeToken(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    // HH:MM / HH：MM
    final colon = RegExp(r'^(\d{1,2})[:：](\d{2})$').firstMatch(raw);
    if (colon != null) {
      return (int.parse(colon.group(1)!), int.parse(colon.group(2)!));
    }
    // N点[半|M分] — Arabic or Chinese numerals
    final dian = RegExp(r'^([0-9一二两三四五六七八九十]+)点(半|[0-9一二两三四五六七八九十]+分?)?$')
        .firstMatch(raw);
    if (dian != null) {
      final h = _parseNumber(dian.group(1)!);
      if (h == null) return null;
      final mRaw = dian.group(2);
      var m = 0;
      if (mRaw == '半') {
        m = 30;
      } else if (mRaw != null && mRaw.isNotEmpty) {
        m = _parseNumber(mRaw.replaceAll('分', '')) ?? 0;
      }
      return (h, m);
    }
    return null;
  }

  static int? _parseNumber(String raw) {
    final arabic = int.tryParse(raw);
    if (arabic != null) return arabic;
    // Chinese numeral ≤ 12 (十 / 十一 / 十二 / 一…九)
    final mapped = _cnDigitMap[raw];
    if (mapped != null) return mapped;
    if (raw.startsWith('十')) {
      final rest = raw.substring(1);
      if (rest.isEmpty) return 10;
      final unit = _cnDigitMap[rest];
      if (unit != null && unit <= 9) return 10 + unit;
    }
    return null;
  }

  /// Detect canonical routine statements in user messages via regex.
  /// Returns at most one signal per kind; **newest mention wins** (messages
  /// are expected newest-first, so the first match per kind is kept).
  ///
  /// **Freshness rule**: a statement older than the matched rhythm's
  /// `updatedAt` is skipped — old statements can never override a newer
  /// routine value. This is what makes routine *changes* trackable:
  /// "从下周开始8点下班" wins over fifty older "七点才下班" complaints.
  ///
  /// Patterns are tuned against the user's real phrasings:
  /// "七点才下班" / "我晚上七点才下班" /
  /// "周日周五周二晚上是 10:00 到 11:30（上网课/兼职）" /
  /// "我一般1点才睡".
  static List<RhythmSignal> extractDeterministicSignals(
      List<PersonaChatMessage> messages,
      [List<UserRhythm> existingRhythms = const []]) {
    final results = <String, RhythmSignal>{};
    // Newest updatedAt per kind — the freshness gate for that kind.
    final kindUpdatedAt = <String, int>{};
    for (final r in existingRhythms) {
      final prev = kindUpdatedAt[r.kind];
      if (prev == null || r.updatedAt > prev) kindUpdatedAt[r.kind] = r.updatedAt;
    }

    // Only read what the USER stated, not the character's own utterances.
    for (final m in messages) {
      if (m.isFromCharacter) continue;
      final text = m.content;

      bool freshFor(String kind) {
        final ts = kindUpdatedAt[kind];
        return ts == null || m.timestamp.millisecondsSinceEpoch > ts;
      }

      // 1) work_schedule: "七点才下班" / "我晚上七点才下班" / "每天7点下班"。
      //    疑问句（"我几点下班？"）不算声明。
      final offWork = RegExp(
              r'(?:每天|每日)?(?:我)?(?:晚上|下午|傍晚)?([0-9一二两三四五六七八九十]+)[点時时:：](?:[0-9]{1,2}分?|半)?(?:才|就|左右)?下班')
          .firstMatch(text);
      if (offWork != null &&
          !text.contains('?') &&
          !text.contains('？') &&
          freshFor('work_schedule') &&
          !results.containsKey('work_schedule')) {
        final parsed = _parseTimeToken('${offWork.group(1)}点');
        if (parsed != null) {
          var hour = parsed.$1;
          // 下班语境：1-8 点按 12h 制（晚 7 点 ≫ 凌晨 7 点下班常见）
          if (hour >= 1 && hour <= 8) hour += 12;
          final end = _hhmm(hour, parsed.$2);
          results['work_schedule'] = RhythmSignal(
            kind: 'work_schedule',
            description: '工作日上班，$end 下班',
            rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;10:00-$end',
            location: 'office',
            confidence: 0.85,
          );
        }
      }

      // 2) class_schedule: 周几列表 + 时间段，两者顺序可互换，允许间隔
      //    少量文字（"周日周五周二晚上是 10:00 到 11:30"后接兼职/网课/上课）。
      final daysRe = RegExp(
          r'((?:周|星期|礼拜)[一二三四五六日天](?:(?:、|和|与|,|，)?(?:周|星期|礼拜)?[一二三四五六日天])*)');
      final rangeRe = RegExp(
          r'([0-9一二两三四五六七八九十]+[点時时:：]?(?:[0-9]{1,2}分?|半)?|\d{1,2}[:：]\d{2})'
          r'\s*(?:到|至|-|~|—)\s*'
          r'([0-9一二两三四五六七八九十]+[点時时:：]?(?:[0-9]{1,2}分?|半)?|\d{1,2}[:：]\d{2})');
      final daysMatch = daysRe.firstMatch(text);
      final rangeMatch = rangeRe.firstMatch(text);
      // 作息表句式（"周日周五周二晚上是 10:00 到 11:30"）无"课/兼职"
      // 字，也算课程上下文——真实语料里这是紧随"我的兼职课是从8点半到
      // 10点半"的补全句。
      final classContext = RegExp(
              r'(上课|网课|兼职|教课|授课|学生的课|晚上是|白天是|点是|时间)')
          .hasMatch(text);
      if (daysMatch != null &&
          rangeMatch != null &&
          classContext &&
          (daysMatch.start - rangeMatch.end).abs() <= 30 &&
          freshFor('class_schedule') &&
          !results.containsKey('class_schedule')) {
        final days = <String>{};
        for (final ch in daysMatch.group(1)!.split('')) {
          final mapped = _weekdayMap[ch];
          if (mapped != null) days.add(mapped);
        }
        final startParsed = _parseTimeToken(rangeMatch.group(1));
        final endParsed = _parseTimeToken(rangeMatch.group(2));
        if (days.isNotEmpty && startParsed != null && endParsed != null) {
          var (startH, startM) = startParsed;
          var (endH, endM) = endParsed;
          // 晚上语境：1-11 点按 12h 制
          final eveningContext =
              RegExp(r'(晚上|晚间|夜里|下午)').hasMatch(text);
          if (eveningContext) {
            if (startH >= 1 && startH <= 11) startH += 12;
            if (endH >= 1 && endH <= 11) endH += 12;
          }
          final daysStr = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']
              .where(days.contains)
              .join(',');
          results['class_schedule'] = RhythmSignal(
            kind: 'class_schedule',
            description: '固定课程（兼职/网课）',
            rrule:
                'FREQ=WEEKLY;BYDAY=$daysStr;${_hhmm(startH, startM)}-${_hhmm(endH, endM)}',
            location: text.contains('在家') ? 'home' : 'unknown',
            confidence: 0.85,
          );
        }
      }

      // 3) sleep_pattern: "我一般1点才睡" / "最近都2点睡" / "通常12点半睡"。
      //    需要习惯性标记（一般/通常/都/最近…）才算 routine。
      final sleep = RegExp(
              r'(?:一般|通常|都|基本|平时|最近)?(?:我)?(?:要|会)?(?:凌晨|夜里|晚上)?([0-9一二两三四五六七八九十]+)[点時时](半)?(?:才|就|左右)?(?:睡|入睡|上床)')
          .firstMatch(text);
      final habitMarker =
          RegExp(r'(一般|通常|都|基本|平时|最近|每天|每日)').hasMatch(text);
      if (sleep != null &&
          habitMarker &&
          freshFor('sleep_pattern') &&
          !results.containsKey('sleep_pattern')) {
        final parsed = _parseTimeToken('${sleep.group(1)}点');
        if (parsed != null) {
          var hour = parsed.$1;
          final minute = sleep.group(2) == '半' ? 30 : parsed.$2;
          // 睡眠语境：1-8 点 = 凌晨；9-11 点 = 晚上
          if (hour >= 1 && hour <= 8) {
            results['sleep_pattern'] = RhythmSignal(
              kind: 'sleep_pattern',
              description: '晚睡作息（凌晨$hour 点左右入睡）',
              rrule: 'FREQ=DAILY;${_hhmm(hour, minute)}-09:00',
              location: 'home',
              confidence: 0.7,
            );
          } else if (hour >= 9 && hour <= 11) {
            hour += 12;
            results['sleep_pattern'] = RhythmSignal(
              kind: 'sleep_pattern',
              description: '作息（$hour 点左右入睡）',
              rrule: 'FREQ=DAILY;${_hhmm(hour, minute)}-07:30',
              location: 'home',
              confidence: 0.7,
            );
          }
        }
      }
    }

    return results.values.toList();
  }

  static String _hhmm(int h, int m) =>
      '${(h % 24).toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  String _buildPrompt({required List<String> existingRhythms}) {
    final existingContext = existingRhythms.isEmpty
        ? '(none)'
        : existingRhythms.map((r) => '  - $r').join('\n');

    return '''
You are a rhythm signal extractor for the Here I am companion app.

Read the chat history below and detect any mentions of recurring schedules,
routines, or patterns in the user's life. These are things the user does
regularly — work hours, class schedules, sleep patterns, meal times, exercise
routines, commute patterns.

Already-known rhythms (do NOT re-detect these):
$existingContext

## What to detect

- **work_schedule**: "我7点下班", "上班时间是10点到7点", "实习到9月"
- **class_schedule**: "周二周五周日有课", "晚上8点半到10点半上课", "在家上网课"
- **sleep_pattern**: "我一般1点才睡", "最近都2点才睡", "8点起床"
- **meal_pattern**: "我一般12点吃午饭", "晚上7点吃饭"
- **exercise_pattern**: "我每周三跑步", "每天走路上班"
- **commute_pattern**: "坐地铁40分钟", "骑车15分钟到公司"

## What NOT to detect

- One-time events ("明天有个面试") - that's a schedule card, not a rhythm
- Emotional states ("最近很累") - not a rhythm
- Preferences ("我喜欢晚睡") - not a concrete schedule
- Things the user is asking about, not stating ("我是不是该早点睡？")
- Menstrual cycle / period mentions - these are tracked via explicit
  menstrual_record Memory Cards, not rhythm signals

## Output format

Return a JSON array ONLY. Each item:
```json
{
  "kind": "work_schedule|class_schedule|sleep_pattern|meal_pattern|exercise_pattern|commute_pattern",
  "description": "short Chinese description, e.g. 实习上班",
  "rrule": "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;10:00-19:00",
  "location": "home|office|remote|commute|unknown",
  "confidence": 0.0-1.0,
  "extra": null
}
```

RRULE format: FREQ=DAILY|WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU;HH:MM-HH:MM
- For daily patterns without specific days: FREQ=DAILY;HH:MM-HH:MM
- For weekly patterns: FREQ=WEEKLY;BYDAY=TU,FR,SU;22:00-23:30
- Sleep patterns that cross midnight: use the bedtime as start (e.g. 23:30-07:00)

confidence:
- 0.9+: user stated it clearly and repeatedly ("我7点下班" said multiple times)
- 0.7: user stated it once clearly
- 0.5: user implied it but didn't state directly
- Below 0.5: skip, don't include

If no new rhythms are detected, return an empty array: []

Return ONLY the JSON array. No markdown, no explanation.
''';
  }

  List<RhythmSignal> _parseSignals(String raw) {
    var trimmed = raw.trim();
    // Strip code fences
    final fenceMatch = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```')
        .firstMatch(trimmed);
    if (fenceMatch != null) {
      trimmed = fenceMatch.group(1)!.trim();
    }
    // Find the JSON array
    final start = trimmed.indexOf('[');
    final end = trimmed.lastIndexOf(']');
    if (start < 0 || end <= start) return [];

    try {
      final decoded = jsonDecode(trimmed.substring(start, end + 1));
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => RhythmSignal(
                kind: m['kind'] as String? ?? 'custom',
                description: m['description'] as String? ?? '',
                rrule: m['rrule'] as String? ?? '',
                location: m['location'] as String? ?? 'unknown',
                confidence: (m['confidence'] as num?)?.toDouble() ?? 0.5,
                extra: m['extra'] as Map<String, dynamic>?,
              ))
          .where((s) => s.description.isNotEmpty)
          .where((s) => s.confidence >= 0.5)
          .toList();
    } catch (e) {
      _logger.warning('Failed to parse rhythm signals: $e');
      return [];
    }
  }

  bool _descriptionsOverlap(String a, String b) {
    // Simple overlap check: if one contains the other, or they share
    // significant words
    final aLower = a.toLowerCase();
    final bLower = b.toLowerCase();
    if (aLower.contains(bLower) || bLower.contains(aLower)) return true;

    // Check word overlap for Chinese (character-level)
    final aChars = aLower.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
    final bChars = bLower.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
    if (aChars.isEmpty || bChars.isEmpty) return false;

    // If >60% of characters overlap, consider it a duplicate
    var overlap = 0;
    for (final c in aChars.split('')) {
      if (bChars.contains(c)) overlap++;
    }
    return overlap / aChars.length > 0.6;
  }
}

class RhythmSignal {
  final String kind;
  final String description;
  final String rrule;
  final String location;
  final double confidence;
  final Map<String, dynamic>? extra;

  RhythmSignal({
    required this.kind,
    required this.description,
    required this.rrule,
    required this.location,
    required this.confidence,
    this.extra,
  });
}