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

    // 1. Load recent chat messages
    final messages = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.messageType.equals('chat'))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(messageLimit))
        .get();

    if (messages.isEmpty) return 0;

    // 2. Deterministic extraction first — regex-based, no LLM. Covers the
    // canonical routine phrasings reliably even when the configured model
    // is unavailable / rejects the payload (observed: 422 on large inputs).
    final deterministicSignals = extractDeterministicSignals(messages);
    if (deterministicSignals.isNotEmpty) {
      final created = await _persistSignals(deterministicSignals);
      _logger.info('Rhythm deterministic extraction created/updated '
          '$created rhythm(s)');
      return created;
    }

    // 3. Load existing rhythms for dedup context (mutable — the upsert
    // loop below replaces consumed entries so later signals in the same
    // batch dedup against the freshly-updated state).
    final existingRhythms =
        await UserRhythmService.instance.getActiveRhythms();
    final existingDescriptions =
        existingRhythms.map((r) => '${r.kind}: ${r.description}').toList();

    // 4. Build LLM prompt
    final chatText = messages.reversed.map((m) {
      final speaker = m.isFromCharacter ? 'I' : 'user';
      final ts = m.timestamp;
      final dateStr = '${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
      return '[$dateStr] $speaker: ${m.content}';
    }).join('\n');

    final systemPrompt = _buildPrompt(
      existingRhythms: existingDescriptions,
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
  /// Returns at most one signal per kind (latest mention wins).
  /// Patterns are tuned against the user's real phrasings:
  /// "七点才下班" / "我晚上七点才下班" /
  /// "周日周五周二晚上是 10:00 到 11:30（上网课/兼职）" /
  /// "我一般1点才睡".
  static List<RhythmSignal> extractDeterministicSignals(
      List<PersonaChatMessage> messages) {
    final results = <String, RhythmSignal>{};

    // Only read what the USER stated, not the character's own utterances.
    for (final m in messages) {
      if (m.isFromCharacter) continue;
      final text = m.content;

      // 1) work_schedule: "七点才下班" / "我晚上七点才下班" / "每天7点下班"。
      //    疑问句（"我几点下班？"）不算声明。
      final offWork = RegExp(
              r'(?:每天|每日)?(?:我)?(?:晚上|下午|傍晚)?([0-9一二两三四五六七八九十]+)[点時时:：](?:[0-9]{1,2}分?|半)?(?:才|就|左右)?下班')
          .firstMatch(text);
      if (offWork != null && !text.contains('?') && !text.contains('？')) {
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
      final classContext =
          RegExp(r'(上课|网课|兼职|教课|授课|学生的课)').hasMatch(text);
      if (daysMatch != null &&
          rangeMatch != null &&
          classContext &&
          (daysMatch.start - rangeMatch.end).abs() <= 30) {
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
      if (sleep != null && habitMarker) {
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