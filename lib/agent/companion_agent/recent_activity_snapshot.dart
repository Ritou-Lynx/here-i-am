import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/daily_outing_learning_service.dart';
import 'package:memex/data/services/proactive_outing_service.dart';
import 'package:memex/data/services/weather_risk_service.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/data/memory_v3/services/growth_pact_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

/// Builds a "what's going on in the user's life right now" snapshot for the
/// background companion agent.
///
/// Three streams of context:
/// 1. Recent timeline cards (raw YAML, last N hours) — bypasses comment pipeline
/// 2. Last user activity (chat + record) — when did the user last appear
/// 3. Last proactive push from this character — what did you already say
class RecentActivitySnapshot {
  RecentActivitySnapshot._();

  static final Logger _logger = getLogger('RecentActivitySnapshot');

  static const String kvBucket = 'companion_push';
  static String kvKey(String characterId) => 'last_push_$characterId';

  /// Compose the full snapshot as a single string to inject into the
  /// background SYSTEM DIRECTIVE.
  static Future<String> build({
    required String userId,
    required String characterId,
    Duration window = const Duration(hours: 12),
    bool skipChatHistory = false,
  }) async {
    final now = DateTime.now();
    final parts = <String>[];

    parts.add('## Current Moment');
    parts.add('Time now: ${_fmtTime(now)}');

    // --- Recent records ---
    try {
      final records = await _loadRecentRecords(userId, now, window);
      parts.add('');
      parts.add('## User Records (last ${window.inHours}h)');
      if (records.isEmpty) {
        parts.add('No records in this window.');
      } else {
        parts.addAll(records);
      }
    } catch (e) {
      _logger.warning('Failed to load recent records: $e');
    }

    // --- Upcoming explicit outings ---
    try {
      final outings = await ProactiveOutingService.instance
          .findUpcomingCandidates(now: now, horizon: const Duration(hours: 24));
      parts.add('');
      parts.add('## Upcoming Outings (next 24h)');
      if (outings.isEmpty) {
        parts.add('No explicit outing plans in this window.');
      } else {
        for (final outing in outings.take(5)) {
          final details = <String>[
            _fmtTime(outing.eventAt),
            outing.title,
            if (outing.placeHint != null) 'place: ${outing.placeHint}',
            if (outing.walkingMinutes != null)
              'walking: ${outing.walkingMinutes} min',
          ];
          parts.add('- ${details.join(' | ')}');
        }
      }
    } catch (e) {
      _logger.warning('Failed to load upcoming outings: $e');
    }

    // --- Morning weather & clothing (pre-fetched so the LLM doesn't have to) ---
    // Only fire in the morning window so we don't spam the weather API all day.
    if (now.hour >= 6 && now.hour < 11) {
      try {
        final weatherSection = await _buildMorningWeatherSection(now: now);
        if (weatherSection.isNotEmpty) {
          parts.add('');
          parts.add(weatherSection);
        }
      } catch (e) {
        _logger.warning('Failed to load morning weather: $e');
      }
    }

    // --- Active co-reading scene (book/comic open right now) ---
    // Checked before anything else so a check-in never yanks the user out of
    // a reading session by mistake (2026-08-26: check-in during 落不下
    // reading ignored the book and resumed a stale "resume tasks" thread).
    try {
      if (AppDatabase.isInitialized) {
        final scene = await _buildActiveCoReadingSection(now: now);
        if (scene.isNotEmpty) {
          parts.add('');
          parts.add(scene);
        }
      }
    } catch (e) {
      _logger.warning('Failed to load active co-reading scene: $e');
    }

    // --- Last chat activity ---
    if (!skipChatHistory) {
      try {
        final chatInfo = await _loadLastChatInfo(characterId, now);
        parts.add('');
        parts.add('## Recent Chat With You');
        parts.add(chatInfo);
      } catch (e) {
        _logger.warning('Failed to load chat info: $e');
      }
    }

    // --- User's daily rhythm (work/class/sleep schedule) ---
    try {
      if (UserRhythmService.isInitialized) {
        final rhythmSection =
            await UserRhythmService.instance.buildSnapshotSection(now: now);
        if (rhythmSection.isNotEmpty) {
          parts.add('');
          parts.add(rhythmSection);
        }
      }
    } catch (e) {
      _logger.warning('Failed to load user rhythm: $e');
    }

    // --- Menstrual cycle status (if tracked) ---
    try {
      if (UserRhythmService.isInitialized) {
        final cycleSection =
            await UserRhythmService.instance.buildMenstrualSnapshotSection(now: now);
        if (cycleSection.isNotEmpty) {
          parts.add('');
          parts.add(cycleSection);
        }
      }
    } catch (e) {
      _logger.warning('Failed to load menstrual cycle: $e');
    }

    // --- Active growth pacts (goals/habits/agreements being tracked) ---
    try {
      if (GrowthPactService.isInitialized) {
        final pactSection =
            await GrowthPactService.instance.buildSnapshotSection(now: now);
        if (pactSection.isNotEmpty) {
          parts.add('');
          parts.add(pactSection);
        }
      }
    } catch (e) {
      _logger.warning('Failed to load growth pacts: $e');
    }

    // --- Recent life insights (trends/patterns/anomalies) ---
    try {
      if (LifeInsightService.isInitialized) {
        final insightSection =
            await LifeInsightService.instance.buildSnapshotSection(now: now);
        if (insightSection.isNotEmpty) {
          parts.add('');
          parts.add(insightSection);
        }
      }
    } catch (e) {
      _logger.warning('Failed to load life insights: $e');
    }

    // --- Last proactive push ---
    try {
      final pushInfo = await _loadLastPushInfo(characterId, now);
      parts.add('');
      parts.add('## Your Last Proactive Push');
      parts.add(pushInfo);
    } catch (e) {
      _logger.warning('Failed to load last push info: $e');
    }

    return parts.join('\n');
  }

  /// Record that a proactive push just happened. Called from the checkin tool
  /// after a successful notify action.
  static Future<void> recordPush({
    required String characterId,
    required String body,
  }) async {
    if (!AppDatabase.isInitialized) return;
    final db = AppDatabase.instance;
    final payload = jsonEncode({
      'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'body': body,
    });
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: kvKey(characterId),
            bucket: const Value(kvBucket),
            value: Value(payload),
            updatedAt: Value(now),
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Recent records (raw YAML cards)
  // ---------------------------------------------------------------------------

  static Future<List<String>> _loadRecentRecords(
    String userId,
    DateTime now,
    Duration window,
  ) async {
    final cutoff = now.subtract(window);
    final fs = FileSystemService.instance;

    // Card files for the day range touched by the window.
    final files = await fs.getCardFilesInDateRange(
      userId,
      DateTime(cutoff.year, cutoff.month, cutoff.day),
      DateTime(now.year, now.month, now.day),
    );

    final entries = <_RecordEntry>[];
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        final doc = loadYaml(content);
        final data = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;

        final tsRaw = data['timestamp'];
        if (tsRaw is! int) continue;
        final ts = DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000);
        if (ts.isBefore(cutoff)) continue;

        final summary = _extractCardSummary(data);
        if (summary.isEmpty) continue;
        entries.add(_RecordEntry(time: ts, summary: summary));
      } catch (e) {
        _logger.fine('Skip card $filePath: $e');
      }
    }

    entries.sort((a, b) => a.time.compareTo(b.time));
    return entries
        .map((e) => '- ${_fmtTime(e.time)}  ${e.summary}')
        .toList(growable: false);
  }

  /// Pull the most user-meaningful text out of a card YAML.
  /// Priority: title → insight summary → first text-bearing ui_config data.
  static String _extractCardSummary(Map<String, dynamic> data) {
    final title = (data['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) {
      return _trunc(title, 80);
    }

    if (data['insight'] is Map) {
      final insight = data['insight'] as Map;
      final s = (insight['summary'] as String?)?.trim();
      if (s != null && s.isNotEmpty) return _trunc(s, 120);
      final t = (insight['text'] as String?)?.trim();
      if (t != null && t.isNotEmpty) return _trunc(t, 120);
    }

    final uiConfigs = data['ui_configs'];
    if (uiConfigs is List) {
      for (final cfg in uiConfigs) {
        if (cfg is! Map) continue;
        final cfgData = cfg['data'];
        if (cfgData is! Map) continue;
        for (final key in ['text', 'content', 'body', 'note', 'title']) {
          final v = cfgData[key];
          if (v is String && v.trim().isNotEmpty) {
            return _trunc(v.trim(), 120);
          }
        }
      }
    }

    final tags = data['tags'];
    if (tags is List && tags.isNotEmpty) {
      return '[${tags.take(3).join(', ')}]';
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // Chat history
  // ---------------------------------------------------------------------------

  static Future<String> _loadLastChatInfo(
      String characterId, DateTime now) async {
    if (!AppDatabase.isInitialized) return 'Database not available.';
    final db = AppDatabase.instance;

    final lastUser = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.isFromCharacter.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(1))
        .getSingleOrNull();

    final lastChar = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.isFromCharacter.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(1))
        .getSingleOrNull();

    final recentMessages = await (db.select(db.personaChatMessages)
          ..where((t) => t.characterId.equals(characterId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(20))
        .get();

    final lines = <String>[];
    if (lastUser != null) {
      lines.add(
          'User last messaged: ${_fmtAgo(lastUser.timestamp, now)} — "${_trunc(lastUser.content, 80)}"');
    } else {
      lines.add('User has never messaged you in chat.');
    }
    if (lastChar != null) {
      lines.add(
          'You last replied: ${_fmtAgo(lastChar.timestamp, now)} — "${_trunc(lastChar.content, 80)}"');
    }
    if (recentMessages.isNotEmpty) {
      lines.add('');
      lines.add('Recent chat window (oldest to newest):');
      for (final message in recentMessages.reversed) {
        final speaker = message.isFromCharacter ? 'You' : 'User';
        lines.add(
          '- $speaker (${_fmtAgo(message.timestamp, now)}): '
          '"${_trunc(message.content, 120)}"',
        );
      }
    }
    return lines.join('\n');
  }

  // ---------------------------------------------------------------------------
  // Active co-reading scene
  // ---------------------------------------------------------------------------

  /// Build a "user is reading X right now" section from any active
  /// co-reading session (book or comic). Source of truth is the
  /// `coReadingSessions` table (status='active'), which is reliable while
  /// the reader is open — unlike progress timestamps, which go stale during
  /// long quiet reading sessions.
  static Future<String> _buildActiveCoReadingSection({
    required DateTime now,
  }) async {
    final db = AppDatabase.instance;
    final rows = await (db.select(db.coReadingSessions)
          ..where((s) => s.status.equals('active'))
          ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
          ..limit(1))
        .get();
    if (rows.isEmpty) return '';
    final s = rows.first;
    final started = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    final lines = <String>[
      '## 用户正在共读（进行中场景）',
      '《${s.workTitle}》 · ${s.workType == 'book' ? '第 ${s.chapterRef} 章' : ' chapter ${s.chapterRef}'}'
          '${s.chapterTitle.isNotEmpty ? '（${s.chapterTitle}）' : ''}',
      '开始于：${_fmtAgo(started, now)}',
      '',
      '用户此刻正开着这本书/这部漫画。除非本次 check-in 有真正紧急的提醒，',
      '默认围绕共读自然开场，不要把话题拽到无关的工作或任务上；也不要',
      '复述章节内容，只在用户主动聊剧情时回应。',
    ];
    return lines.join('\n');
  }

  // ---------------------------------------------------------------------------
  // Last proactive push
  // ---------------------------------------------------------------------------

  static Future<String> _loadLastPushInfo(
      String characterId, DateTime now) async {
    if (!AppDatabase.isInitialized) return 'No record.';
    final db = AppDatabase.instance;
    final row = await (db.select(db.kvStore)
          ..where((t) => t.key.equals(kvKey(characterId))))
        .getSingleOrNull();
    if (row == null || row.value == null) {
      return 'You have never sent a proactive push to this user.';
    }
    try {
      final m = jsonDecode(row.value!) as Map<String, dynamic>;
      final tsSec = m['ts'] as int?;
      final body = (m['body'] as String?) ?? '';
      if (tsSec == null) return 'No record.';
      final t = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);
      return '${_fmtAgo(t, now)} — "${_trunc(body, 100)}"';
    } catch (_) {
      return 'No record.';
    }
  }

  // ---------------------------------------------------------------------------
  // Morning weather & clothing (pre-fetched for the checkin snapshot)
  // ---------------------------------------------------------------------------

  /// Pre-fetch weather for the morning checkin snapshot so the companion agent
  /// gets clothing/umbrella context without having to call the weather tool
  /// itself (which it often skips on a plain `checkin` trigger).
  ///
  /// Returns an empty string when weather is unavailable (no Amap key, location
  /// disabled, etc.) — the agent will just not see a weather block, which is
  /// better than a misleading "weather unavailable" wall of text.
  static Future<String> _buildMorningWeatherSection({
    required DateTime now,
  }) async {
    final result =
        await WeatherRiskService.instance.assessOutingRisk(now: now);
    if (!result.success) {
      _logger.info('Morning weather prefetch skipped: ${result.message}');
      return '';
    }

    final lines = <String>[
      '## Morning Weather & Clothing',
      'City: ${result.city ?? 'unknown'}',
      'Report time: ${result.reportTime != null ? _fmtTime(result.reportTime!) : _fmtTime(now)}',
    ];

    final risks = result.risks;
    if (risks != null) {
      final flags = <String>[
        if (risks.bringUmbrella) 'umbrella',
        if (risks.eveningRainRisk) 'evening rain',
        if (risks.temperatureDropRisk) 'temp drop',
        if (risks.windRisk) 'wind',
        if (risks.heatRisk) 'heat',
        if (risks.coldRisk) 'cold',
        if (risks.longWalkExposureRisk) 'long walk exposure',
      ];
      lines.add('Risk flags: ${flags.isEmpty ? 'none' : flags.join(', ')}');
      if (risks.reasons.isNotEmpty) {
        lines.add('Reasons:');
        for (final r in risks.reasons.take(4)) {
          lines.add('- $r');
        }
      }
      if (risks.suggestions.isNotEmpty) {
        lines.add('Suggestions:');
        for (final s in risks.suggestions.take(4)) {
          lines.add('- $s');
        }
      }
    }

    final today = result.casts.isNotEmpty ? result.casts.first : null;
    final current = result.current;
    if (current != null) {
      final currentParts = <String>[
        if (current.temperatureC != null)
          '${current.temperatureC!.toStringAsFixed(1)}C',
        if (current.humidityPct != null) '${current.humidityPct}% humidity',
        if (current.weather.isNotEmpty) current.weather,
        if (current.windPower.isNotEmpty)
          '${current.windDirection}${current.windPower} wind',
      ];
      if (currentParts.isNotEmpty) {
        lines.add('Current: ${currentParts.join(', ')}');
      }
    }
    if (today != null) {
      lines.add(
        'Today: ${today.dayWeather}/${today.nightWeather}, '
        '${today.dayTempC ?? '?'}C / ${today.nightTempC ?? '?'}C',
      );
    }

    if (AppDatabase.isInitialized) {
      final learned = await DailyOutingLearningService(AppDatabase.instance)
          .buildLearnedGuidance(currentWeather: result, now: now);
      if (learned.isNotEmpty) {
        lines.add('');
        lines.add(learned);
      }
    }

    lines.add(
      'instruction: This is pre-fetched morning weather. Use it to give the '
      'user a short, natural clothing/umbrella heads-up when they are likely '
      'heading out. Apply Learned Outfit Preference when present, phrasing it '
      'as a relative correction from the user\'s own feedback. Do not recite '
      'the full forecast. Keep it to one or two sentences unless the weather '
      'is genuinely severe.',
    );
    return lines.join('\n');
  }

  // ---------------------------------------------------------------------------
  // Formatters
  // ---------------------------------------------------------------------------

  static String _fmtTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  static String _fmtAgo(DateTime past, DateTime now) {
    final diff = now.difference(past);
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static String _trunc(String s, int n) {
    final clean = s.replaceAll('\n', ' ').trim();
    if (clean.length <= n) return clean;
    return '${clean.substring(0, n)}…';
  }
}

class _RecordEntry {
  final DateTime time;
  final String summary;
  _RecordEntry({required this.time, required this.summary});
}
