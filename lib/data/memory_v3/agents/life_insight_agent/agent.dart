/// Life Insight Agent — cross-source aggregation analysis.
///
/// Collects pre-aggregated data from multiple sources, feeds it to the LLM,
/// parses the result into [LifeInsightResult] objects. Persistence is handled
/// by [LifeInsightService].
///
/// Data sources:
/// - COROS: sleep data (last 14 days), daily health (steps, calories)
/// - AiFinanceService: weekly/monthly expense summary
/// - MemoryCardQueryService: schedule overview, sleep_record cards
/// - Reading: reading_item structured fields
///
/// This agent does NOT call tools — all data is pre-collected and passed as
/// context. This keeps the LLM call single-turn and fast.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/data/services/coros_mcp_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

import 'prompt.dart';

final _logger = getLogger('memory_v3.LifeInsightAgent');

class LifeInsightAgent {
  const LifeInsightAgent();

  /// Run the analysis for the given period.
  ///
  /// [client] / [modelConfig] are caller-supplied (uses recordOrganizerAgent
  /// config, same as Dreaming — "记忆整理" category).
  Future<LifeInsightBatch> analyze({
    required LLMClient client,
    required ModelConfig modelConfig,
    required AppDatabase db,
    required String userId,
    required DateTime now,
    required LifeInsightPeriod period,
  }) async {
    // 1. Collect aggregated data from all sources.
    final collector = _InsightDataCollector(db: db, userId: userId);
    final payload = await collector.collect(now: now, period: period);

    if (payload.isEmpty) {
      _logger.info('LifeInsight: no data collected, skipping analysis');
      return LifeInsightBatch(insights: [], period: period);
    }

    // 2. Build the LLM prompt.
    final periodLabel = _periodLabel(period, now);
    final systemPrompt = lifeInsightSystemPrompt(periodLabel: periodLabel);
    final userPayload = jsonEncode({
      'current_time': now.toIso8601String(),
      'period': period.name,
      'data': payload,
    });

    final messages = [
      SystemMessage(systemPrompt),
      UserMessage([TextPart(userPayload)]),
    ];

    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 4096,
      extra: modelConfig.extra,
    );

    // 3. Call LLM.
    final firstText =
        (await client.generate(messages, modelConfig: mc)).textOutput;
    if (firstText == null || firstText.trim().isEmpty) {
      throw const FormatException('LifeInsight agent returned no output');
    }

    // 4. Parse.
    try {
      return _parse(firstText, period);
    } on FormatException catch (e) {
      final snippet =
          firstText.length > 300 ? firstText.substring(0, 300) : firstText;
      _logger.warning(
          'LifeInsight first parse failed ($e). Raw (first 300): $snippet');
    }

    // 5. Retry with hardened prompt.
    final retryMessages = [
      SystemMessage(systemPrompt),
      UserMessage([
        TextPart(userPayload),
        TextPart(
          'STRICT: Reply with ONLY a single JSON object. '
          'No ```json fences, no commentary, no trailing comma. '
          'The first character of your response must be "{".',
        ),
      ]),
    ];
    final retryText =
        (await client.generate(retryMessages, modelConfig: mc)).textOutput;
    if (retryText == null || retryText.trim().isEmpty) {
      throw const FormatException('LifeInsight retry returned no output');
    }
    try {
      return _parse(retryText, period);
    } on FormatException catch (e) {
      _logger.severe('LifeInsight retry parse also failed: $e');
      final snippet =
          retryText.length > 400 ? retryText.substring(0, 400) : retryText;
      throw FormatException(
          'LifeInsight returned invalid JSON even after retry. '
          'Raw response (first 400 chars):\n$snippet');
    }
  }

  LifeInsightBatch _parse(String raw, LifeInsightPeriod period) {
    var trimmed = raw.trim();
    // Strip <think>...</think> reasoning blocks
    trimmed = trimmed.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final unclosedThink = trimmed.indexOf('<think>');
    if (unclosedThink >= 0) {
      final braceAfter = trimmed.indexOf('{', unclosedThink);
      trimmed = braceAfter >= 0 ? trimmed.substring(braceAfter) : '';
    }
    // Strip code fences
    RegExpMatch? fenceMatch = RegExp(
      r'^```(?:json|JSON)?\s*\n([\s\S]*?)\n```\s*$',
    ).firstMatch(trimmed);
    fenceMatch ??= RegExp(
      r'```(?:json|JSON)?\s*\n([\s\S]*?)\n```',
    ).firstMatch(trimmed);
    if (fenceMatch != null) {
      trimmed = fenceMatch.group(1)!.trim();
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('LifeInsight response contains no JSON');
    }
    var jsonPart = trimmed.substring(start, end + 1);
    jsonPart = _repairLLMJson(jsonPart);
    final decoded = jsonDecode(jsonPart);
    if (decoded is! Map) {
      throw const FormatException('LifeInsight JSON root must be an object');
    }
    final insightsRaw = decoded['insights'];
    if (insightsRaw is! List) {
      return LifeInsightBatch(insights: [], period: period);
    }
    final insights = <LifeInsightResult>[];
    for (final item in insightsRaw) {
      if (item is! Map) continue;
      try {
        insights.add(LifeInsightResult.fromJson(item.cast<String, dynamic>()));
      } catch (e) {
        _logger.warning('LifeInsight: skipping malformed insight entry: $e');
      }
    }
    return LifeInsightBatch(insights: insights, period: period);
  }

  String _repairLLMJson(String json) {
    var repaired = json.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    repaired = repaired.replaceAll(',,', ',');
    repaired = _escapeRawCharsInStrings(repaired);
    return repaired;
  }

  String _escapeRawCharsInStrings(String input) {
    final buf = StringBuffer();
    var inString = false;
    var prev = '';
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '"' && prev != '\\') {
        inString = !inString;
        buf.write(ch);
      } else if (inString) {
        switch (ch) {
          case '\n':
            buf.write(r'\n');
          case '\r':
            buf.write(r'\r');
          case '\t':
            buf.write(r'\t');
          default:
            buf.write(ch);
        }
      } else {
        buf.write(ch);
      }
      prev = ch;
    }
    return buf.toString();
  }

  String _periodLabel(LifeInsightPeriod period, DateTime now) {
    switch (period) {
      case LifeInsightPeriod.daily:
        return 'today (${now.toIso8601String().split('T').first})';
      case LifeInsightPeriod.weekly:
        final weekAgo = now.subtract(const Duration(days: 7));
        return 'last 7 days (${weekAgo.toIso8601String().split('T').first} to ${now.toIso8601String().split('T').first})';
      case LifeInsightPeriod.monthly:
        final monthAgo = now.subtract(const Duration(days: 30));
        return 'last 30 days (${monthAgo.toIso8601String().split('T').first} to ${now.toIso8601String().split('T').first})';
    }
  }
}

// =============================================================================
// Data collector — gathers pre-aggregated data from all sources
// =============================================================================

class _InsightDataCollector {
  _InsightDataCollector({required this.db, required this.userId});

  final AppDatabase db;
  final String userId;

  /// Collect all available data. Returns a map keyed by domain.
  /// Only includes domains where data was successfully collected.
  Future<Map<String, dynamic>> collect({
    required DateTime now,
    required LifeInsightPeriod period,
  }) async {
    final data = <String, dynamic>{};

    // Health: COROS sleep data + daily health
    try {
      final healthData = await _collectHealthData(now, period);
      if (healthData != null) {
        data['health'] = healthData;
      }
    } catch (e) {
      _logger.warning('LifeInsight: health data collection failed: $e');
    }

    // Finance: ledger summary
    try {
      final financeData = await _collectFinanceData(now, period);
      if (financeData != null) {
        data['finance'] = financeData;
      }
    } catch (e) {
      _logger.warning('LifeInsight: finance data collection failed: $e');
    }

    // Schedule: task/schedule overview
    try {
      final scheduleData = await _collectScheduleData(now);
      if (scheduleData != null) {
        data['schedule'] = scheduleData;
      }
    } catch (e) {
      _logger.warning('LifeInsight: schedule data collection failed: $e');
    }

    // Reading: reading progress
    try {
      final readingData = await _collectReadingData(now);
      if (readingData != null) {
        data['reading'] = readingData;
      }
    } catch (e) {
      _logger.warning('LifeInsight: reading data collection failed: $e');
    }

    return data;
  }

  // ── Health ──

  Future<Map<String, dynamic>?> _collectHealthData(
      DateTime now, LifeInsightPeriod period) async {
    final days = period == LifeInsightPeriod.daily
        ? 2
        : period == LifeInsightPeriod.weekly
            ? 14
            : 30;

    final result = <String, dynamic>{};

    // Try COROS live API first
    try {
      final coros = CorosMcpService.instance;
      if (coros.isConnected) {
        final sleepData = await coros.querySleepData(days: days);
        result['sleep_raw'] = sleepData.text;
        final healthData = await coros.queryDailyHealthData(days: days);
        result['daily_health_raw'] = healthData.text;
        return result.isNotEmpty ? result : null;
      }
    } catch (e) {
      _logger.fine('LifeInsight: COROS live API failed, trying cache: $e');
    }

    // Fallback to cached files
    try {
      final dirPath = await _getCorosCacheDir();
      final sleepFile = File('$dirPath/sleep_data.json');
      if (await sleepFile.exists()) {
        result['sleep_raw'] = await sleepFile.readAsString();
      }
      final healthFile = File('$dirPath/daily_health.json');
      if (await healthFile.exists()) {
        result['daily_health_raw'] = await healthFile.readAsString();
      }
    } catch (e) {
      _logger.fine('LifeInsight: COROS cache read failed: $e');
    }

    // Also collect from Memory Cards (sleep_record type)
    try {
      final queryService = MemoryCardQueryService(db);
      final sleepCards = await queryService.listCardsByStructuredFieldTypes(
        {'sleep_record'},
        limit: days,
      );
      if (sleepCards.isNotEmpty) {
        result['sleep_cards'] = sleepCards.map((c) => {
              'title': c.title,
              'dropletLabel': c.dropletLabel,
              'retrievalText': c.retrievalText,
              'eventTime': c.eventTimeMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(c.eventTimeMs!)
                      .toIso8601String()
                  : null,
              'structuredFields': c.structuredFieldsMap,
            }).toList();
      }
    } catch (e) {
      _logger.fine('LifeInsight: sleep cards query failed: $e');
    }

    // Collect menstrual_record cards for cycle pattern analysis
    try {
      final queryService = MemoryCardQueryService(db);
      final menstrualCards = await queryService.listCardsByStructuredFieldTypes(
        {'menstrual_record'},
        limit: 30,
      );
      if (menstrualCards.isNotEmpty) {
        result['menstrual_records'] = menstrualCards.map((c) => {
              'title': c.title,
              'retrievalText': c.retrievalText,
              'eventTime': c.eventTimeMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(c.eventTimeMs!)
                      .toIso8601String()
                  : null,
              'structuredFields': c.structuredFieldsMap,
            }).toList();
      }
    } catch (e) {
      _logger.fine('LifeInsight: menstrual cards query failed: $e');
    }

    return result.isNotEmpty ? result : null;
  }

  // ── Finance ──

  Future<Map<String, dynamic>?> _collectFinanceData(
      DateTime now, LifeInsightPeriod period) async {
    try {
      final financeService = AiFinanceService(db: db);

      // Current month summary
      final monthStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final summary = await financeService.getSummary(month: monthStr);

      // Previous month for comparison
      final prevMonthDate = DateTime(now.year, now.month - 1);
      final prevMonthStr =
          '${prevMonthDate.year}-${prevMonthDate.month.toString().padLeft(2, '0')}';
      final prevSummary = await financeService.getSummary(month: prevMonthStr);

      // Recent entries for pattern detection
      final recentEntries = await financeService.getRecentEntries(limit: 30);

      return {
        'current_month': monthStr,
        'summary': summary,
        'previous_month_summary': prevSummary,
        'recent_entries': recentEntries,
      };
    } catch (e) {
      _logger.warning('LifeInsight: finance collection failed: $e');
      return null;
    }
  }

  // ── Schedule ──

  Future<Map<String, dynamic>?> _collectScheduleData(DateTime now) async {
    try {
      final queryService = MemoryCardQueryService(db);
      final overview = await queryService.getScheduleOverview();
      final scheduleCards = await queryService.listScheduleCards(limit: 50);

      return {
        'overview': overview,
        'active_tasks': scheduleCards.map((c) => {
              'title': c.title,
              'type': c.type,
              'status': c.status,
              'eventTime': c.eventTimeMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(c.eventTimeMs!)
                      .toIso8601String()
                  : null,
              'structuredFields': c.structuredFieldsMap,
            }).toList(),
      };
    } catch (e) {
      _logger.warning('LifeInsight: schedule collection failed: $e');
      return null;
    }
  }

  // ── Reading ──

  Future<Map<String, dynamic>?> _collectReadingData(DateTime now) async {
    try {
      final queryService = MemoryCardQueryService(db);
      final readingCards = await queryService.listCardsByStructuredFieldTypes(
        {'reading_item'},
        limit: 50,
      );
      if (readingCards.isEmpty) return null;

      return {
        'reading_items': readingCards.map((c) => {
              'title': c.title,
              'retrievalText': c.retrievalText,
              'eventTime': c.eventTimeMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(c.eventTimeMs!)
                      .toIso8601String()
                  : null,
              'structuredFields': c.structuredFieldsMap,
            }).toList(),
      };
    } catch (e) {
      _logger.warning('LifeInsight: reading collection failed: $e');
      return null;
    }
  }

  Future<String> _getCorosCacheDir() async {
    final userId = await UserStorage.getUserId() ?? '';
    return '${FileSystemService.instance.getUserSettingsPath(userId)}/external_data/coros';
  }
}

// =============================================================================
// Result types
// =============================================================================

enum LifeInsightPeriod { daily, weekly, monthly }

class LifeInsightBatch {
  final List<LifeInsightResult> insights;
  final LifeInsightPeriod period;

  LifeInsightBatch({required this.insights, required this.period});
}

class LifeInsightResult {
  final String domain;
  final String insightType;
  final String period; // daily | weekly | monthly
  final int periodStart;
  final int periodEnd;
  final String narrative;
  final List<Map<String, dynamic>> dataPoints;
  final double confidence;
  final Map<String, dynamic>? pactSignal;

  LifeInsightResult({
    required this.domain,
    required this.insightType,
    required this.period,
    required this.periodStart,
    required this.periodEnd,
    required this.narrative,
    this.dataPoints = const [],
    this.confidence = 0.5,
    this.pactSignal,
  });

  factory LifeInsightResult.fromJson(Map<String, dynamic> json) {
    return LifeInsightResult(
      domain: json['domain'] as String,
      insightType: json['insightType'] as String,
      period: json['period'] as String? ?? 'weekly',
      periodStart: (json['periodStart'] as num?)?.toInt() ?? 0,
      periodEnd: (json['periodEnd'] as num?)?.toInt() ?? 0,
      narrative: json['narrative'] as String? ?? '',
      dataPoints: (json['dataPoints'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      pactSignal: json['pactSignal'] as Map<String, dynamic>?,
    );
  }
}