/// Rhythm Signal Extractor — detects recurring schedule/routine mentions
/// in chat messages and writes them as UserRhythms.
///
/// Runs alongside LifeInsight analysis. Reads recent chat messages, uses a
/// lightweight LLM call to detect rhythm signals (work hours, class schedule,
/// sleep patterns, etc.), and upserts them into UserRhythmService.
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

    // 2. Load existing rhythms for dedup context
    final existingRhythms =
        await UserRhythmService.instance.getActiveRhythms();
    final existingDescriptions =
        existingRhythms.map((r) => '${r.kind}: ${r.description}').toList();

    // 3. Build LLM prompt
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

    // 4. Parse and persist
    final signals = _parseSignals(text);
    if (signals.isEmpty) return 0;

    var created = 0;
    for (final signal in signals) {
      try {
        // Check if a similar rhythm already exists (by kind + description overlap)
        final isDuplicate = existingRhythms.any((r) =>
            r.kind == signal.kind &&
            _descriptionsOverlap(r.description, signal.description));
        if (isDuplicate) {
          _logger.fine('Rhythm signal skipped (duplicate): '
              '${signal.kind} ${signal.description}');
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