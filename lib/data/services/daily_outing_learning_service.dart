import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/weather_risk_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

typedef OutingWeatherLoader = Future<WeatherRiskResult> Function();

/// Closes the small learning loop around proactive clothing advice.
///
/// This is intentionally narrower than general chat-memory extraction. A user
/// turn is captured only when it contains an outfit/comfort signal and either:
/// - follows a recent character message about clothing/weather, or
/// - updates an outfit log already opened for the same day.
///
/// The resulting `outfit_log` is explicit feature-scoped evidence for future
/// outing advice, not a licence to auto-capture ordinary companion chat.
class DailyOutingLearningService {
  DailyOutingLearningService(
    this.db, {
    OutingWeatherLoader? weatherLoader,
  }) : _weatherLoader = weatherLoader ??
            (() => WeatherRiskService.instance.assessOutingRisk());

  static const String entityType = 'outfit_log';
  static const Duration feedbackContextWindow = Duration(hours: 18);

  final AppDatabase db;
  final OutingWeatherLoader _weatherLoader;
  final _logger = getLogger('DailyOutingLearningService');

  Future<DailyOutingCaptureResult> captureUserTurn({
    required String characterId,
    required int userMessageId,
    required String userMessage,
    DateTime? userMessageTime,
  }) async {
    final text = userMessage.trim();
    if (text.isEmpty || userMessageId <= 0) {
      return const DailyOutingCaptureResult.ignored();
    }

    final duplicate = await (db.select(db.sharedLifeEventOperations)
          ..where((t) =>
              t.entityType.equals(entityType) &
              t.sourceKind.equals('chat_message') &
              t.sourceRef.equals(userMessageId.toString()))
          ..limit(1))
        .getSingleOrNull();
    if (duplicate != null) {
      return const DailyOutingCaptureResult.ignored();
    }

    final now = userMessageTime ?? DateTime.now();
    final feeling = classifyFeeling(text);
    final feedbackTags = classifyFeedbackTags(text);
    final explicitItems = extractOutfitItems(text);
    if (feeling == null && feedbackTags.isEmpty && explicitItems.isEmpty) {
      return const DailyOutingCaptureResult.ignored();
    }

    final existing = await _findDayLog(now, characterId);
    final prompt = await _findRecentOutingPrompt(characterId, now);
    if (existing == null && prompt == null) {
      return const DailyOutingCaptureResult.ignored();
    }

    final existingState =
        existing == null ? <String, dynamic>{} : _decodeMap(existing.stateJson);
    final suggestedItems = prompt == null
        ? _stringList(existingState['suggested_outfit_items'])
        : extractOutfitItems(prompt.content);
    final priorItems = _stringList(existingState['outfit_items']);
    final outfitItems = explicitItems.isNotEmpty
        ? explicitItems
        : (priorItems.isNotEmpty ? priorItems : suggestedItems);
    final outfitEvidence = explicitItems.isNotEmpty
        ? 'user_explicit'
        : (existingState['outfit_evidence']?.toString() ??
            (outfitItems.isNotEmpty
                ? 'inferred_from_companion_suggestion'
                : null));

    WeatherRiskResult? weather;
    try {
      final loaded = await _weatherLoader();
      if (loaded.success) weather = loaded;
    } catch (e) {
      _logger.warning('Outing feedback weather snapshot failed: $e');
    }
    final weatherSnapshot = weather == null
        ? _mapOrEmpty(existingState['weather_snapshot'])
        : weatherSnapshotFrom(weather);

    final history = _mapList(existingState['feedback_history']);
    if (feeling != null || feedbackTags.isNotEmpty) {
      history.add({
        'message_id': userMessageId,
        'recorded_at': now.toIso8601String(),
        'raw': text,
        if (feeling != null) 'feeling': feeling,
        if (feedbackTags.isNotEmpty) 'tags': feedbackTags,
      });
    }

    final date = _ymd(now);
    final structured = <String, dynamic>{
      'date': date,
      if (weatherSnapshot.isNotEmpty) 'weatherSnapshot': weatherSnapshot,
      if (outfitItems.isNotEmpty) 'outfitItems': outfitItems,
      if (suggestedItems.isNotEmpty) 'suggestedOutfitItems': suggestedItems,
      if (feeling != null) 'subjectiveFeeling': feeling,
      if (feedbackTags.isNotEmpty) 'feedbackTags': feedbackTags,
      if (weather?.walkingMinutes != null)
        'commuteContext': {
          'walkingMinutes': weather!.walkingMinutes,
        },
      'sourceMessageId': userMessageId,
    };
    final patch = <String, dynamic>{
      'date': date,
      if (weatherSnapshot.isNotEmpty) 'weather_snapshot': weatherSnapshot,
      if (outfitItems.isNotEmpty) 'outfit_items': outfitItems,
      if (suggestedItems.isNotEmpty) 'suggested_outfit_items': suggestedItems,
      if (outfitEvidence != null) 'outfit_evidence': outfitEvidence,
      if (feeling != null) 'subjective_feeling': feeling,
      if (feedbackTags.isNotEmpty) 'feedback_tags': feedbackTags,
      if (history.isNotEmpty) 'feedback_history': history,
      if (prompt != null) ...{
        'suggestion_message_id': prompt.id,
        'suggestion_text': prompt.content,
      },
      '_primaryDomain': 'clothing',
      '_facets': const ['health', 'schedule'],
      '_occurredAt': now.toIso8601String(),
      '_timeConfidence': 1.0,
      '_timeSourceText': '当天出门反馈',
      '_dropletLabel': '穿衣',
      '_sourceExcerpts': [text],
      '_structuredFields': structured,
      '_schemaVersion': 1,
    };

    final memory = SharedLifeMemoryService(db);
    final operation = SharedLifeOperationDraft(
      operationType: existing == null ? 'create' : 'update',
      entityType: entityType,
      entityId: existing?.id,
      title: '${now.month}月${now.day}日出门穿衣',
      patch: patch,
      sourceKind: 'chat_message',
      sourceRef: userMessageId.toString(),
      rawInput: text,
      sourceMessageIds: [userMessageId],
    );
    final applied = await memory.applyOperations(
      sourceCharacterId: characterId,
      captureTaskId: 'daily_outing_learning:$date',
      operations: [operation],
      allowedSourceMessageIds: {userMessageId},
    );
    if (applied.isEmpty) return const DailyOutingCaptureResult.ignored();
    return DailyOutingCaptureResult(
      captured: true,
      entityId: applied.entityIds.first,
      feeling: feeling,
    );
  }

  /// Builds a concise evidence block for the next morning/checkpoint prompt.
  /// The caller already fetched current weather, so no extra API call occurs.
  Future<String> buildLearnedGuidance({
    required WeatherRiskResult currentWeather,
    DateTime? now,
  }) async {
    if (!currentWeather.success) return '';
    final target = weatherSnapshotFrom(currentWeather);
    if (_temperature(target) == null) return '';
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(hours: 4));
    final rows = await (db.select(db.sharedLifeEntities)
          ..where((t) =>
              t.entityType.equals(entityType) &
              t.status.equals('active') &
              t.occurredAt.isSmallerThanValue(cutoff.microsecondsSinceEpoch))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(60))
        .get();

    _ComparableOutfitLog? best;
    for (final row in rows) {
      final state = _decodeMap(row.stateJson);
      final feeling = state['subjective_feeling']?.toString();
      if (feeling == null || feeling.isEmpty) continue;
      final weather = _mapOrEmpty(state['weather_snapshot']);
      final distance = _weatherDistance(target, weather);
      if (distance == null || distance > 1.6) continue;
      final candidate = _ComparableOutfitLog(
        date: state['date']?.toString() ?? 'unknown date',
        feeling: feeling,
        rawFeedback: _latestRawFeedback(state),
        outfitItems: _stringList(state['outfit_items']),
        weather: weather,
        distance: distance,
      );
      if (best == null || candidate.distance < best.distance) best = candidate;
    }
    if (best == null) return '';

    final adjustment = switch (best.feeling) {
      'too_hot' ||
      'hot' =>
        'Recommend one layer lighter than that experience. Do not automatically repeat a suggested outer layer.',
      'too_cold' ||
      'cold' =>
        'Recommend one layer warmer than that experience, especially for exposed walking or the return trip.',
      'comfortable' =>
        'Use that outfit as the anchor and only adjust for the measured weather difference.',
      _ => 'Use this as a soft comfort calibration, not a universal rule.',
    };
    final temp = _temperature(best.weather);
    final humidity = _number(best.weather['humidity_pct']);
    final conditions = <String>[
      if (temp != null) '${temp.toStringAsFixed(1)}C',
      if (humidity != null) '${humidity.round()}% humidity',
      if (best.weather['wind_power'] != null)
        'wind ${best.weather['wind_power']}',
      if (best.weather['weather'] != null) best.weather['weather'].toString(),
    ];
    return [
      '## Learned Outfit Preference',
      'Closest prior outing: ${best.date} (${conditions.join(', ')}).',
      if (best.outfitItems.isNotEmpty)
        'Outfit/suggested items: ${best.outfitItems.join(', ')}.',
      'User feedback: ${best.feeling}'
          '${best.rawFeedback == null ? '.' : ' ("${best.rawFeedback}").'}',
      'Adjustment: $adjustment',
      'Instruction: express the advice as a relative correction grounded in '
          'this experience. One matching day is weak evidence; do not claim a '
          'stable preference until the pattern repeats.',
    ].join('\n');
  }

  Future<SharedLifeEntity?> _findDayLog(
    DateTime now,
    String characterId,
  ) async {
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return (db.select(db.sharedLifeEntities)
          ..where((t) =>
              t.entityType.equals(entityType) &
              t.sourceCharacterId.equals(characterId) &
              t.status.equals('active') &
              t.occurredAt.isBiggerOrEqualValue(start.microsecondsSinceEpoch) &
              t.occurredAt.isSmallerThanValue(end.microsecondsSinceEpoch))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<PersonaChatMessage?> _findRecentOutingPrompt(
    String characterId,
    DateTime now,
  ) async {
    final cutoff = now.subtract(feedbackContextWindow);
    final rows = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.isFromCharacter.equals(true) &
              t.timestamp.isBiggerOrEqualValue(cutoff) &
              t.timestamp.isSmallerOrEqualValue(now))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timestamp),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(12))
        .get();
    for (final row in rows) {
      if (looksLikeOutingClothingPrompt(row.content)) return row;
    }
    return null;
  }

  @visibleForTesting
  static String? classifyFeeling(String input) {
    final text = input.toLowerCase();
    if (RegExp(r'(穿多了|穿厚了|太热|热死|闷热|捂汗|overdressed|too hot)').hasMatch(text)) {
      return 'too_hot';
    }
    if (RegExp(r'(穿少了|穿薄了|太冷|冷死|冻死|冻透|underdressed|too cold)').hasMatch(text)) {
      return 'too_cold';
    }
    if (RegExp(r'(刚刚好|正合适|很合适|不冷不热|体感刚好|just right|comfortable)')
        .hasMatch(text)) {
      return 'comfortable';
    }
    if (RegExp(r'(有点热|好热|很热|热了|出汗|hot)').hasMatch(text)) {
      return 'hot';
    }
    if (RegExp(r'(有点冷|好冷|很冷|冷了|冻着|cold)').hasMatch(text)) {
      return 'cold';
    }
    return null;
  }

  @visibleForTesting
  static List<String> classifyFeedbackTags(String input) {
    final tags = <String>[];
    if (RegExp(r'(潮|湿|闷|黏|humidity|humid)', caseSensitive: false)
        .hasMatch(input)) {
      tags.add('humid');
    }
    if (RegExp(r'(风大|吹透|风冷|windy|wind chill)', caseSensitive: false)
        .hasMatch(input)) {
      tags.add('windy');
    }
    return tags;
  }

  @visibleForTesting
  static List<String> extractOutfitItems(String input) {
    const patterns = <String, String>{
      '羽绒服': r'羽绒服|down jacket',
      '厚外套': r'厚外套|厚大衣|heavy coat',
      '薄外套': r'薄外套|薄夹克|light jacket',
      '外套': r'外套|夹克|jacket|coat',
      '卫衣': r'卫衣|hoodie',
      '毛衣': r'毛衣|针织衫|sweater',
      '长袖': r'长袖|long[- ]sleeve',
      '短袖': r'短袖|T恤|T-shirt|tee',
      '衬衫': r'衬衫|shirt',
      '长裤': r'长裤|牛仔裤|trousers|jeans',
      '短裤': r'短裤|shorts',
      '裙子': r'裙子|连衣裙|dress|skirt',
      '帽子': r'帽子|遮阳帽|hat|cap',
      '围巾': r'围巾|scarf',
    };
    final found = <String>[];
    var remainder = input;
    for (final entry in patterns.entries) {
      final pattern = RegExp(entry.value, caseSensitive: false);
      if (!pattern.hasMatch(remainder)) continue;
      found.add(entry.key);
      remainder = remainder.replaceAll(pattern, '');
    }
    return found;
  }

  @visibleForTesting
  static bool looksLikeOutingClothingPrompt(String input) {
    final hasOutfit = extractOutfitItems(input).isNotEmpty ||
        RegExp(r'(穿什么|穿衣|加一层|减一层|少穿|多穿|保暖|防晒|带伞|雨伞|umbrella)',
                caseSensitive: false)
            .hasMatch(input);
    final hasOutingWeather = RegExp(
      r'(天气|温度|降温|升温|冷|热|风|雨|湿度|出门|出发|通勤|上班|下班|weather|temperature|commute)',
      caseSensitive: false,
    ).hasMatch(input);
    return hasOutfit && hasOutingWeather;
  }

  @visibleForTesting
  static Map<String, dynamic> weatherSnapshotFrom(WeatherRiskResult result) {
    final today = result.casts.isEmpty ? null : result.casts.first;
    final current = result.current;
    return <String, dynamic>{
      if (result.provider != null) 'provider': result.provider,
      if (result.city != null) 'city': result.city,
      if (result.adcode != null) 'adcode': result.adcode,
      if (current?.temperatureC != null)
        'temperature_c': current!.temperatureC
      else if (today?.dayTempC != null)
        'temperature_c': today!.dayTempC,
      if (current?.humidityPct != null) 'humidity_pct': current!.humidityPct,
      if (current?.weather.isNotEmpty == true) 'weather': current!.weather,
      if (current?.windDirection.isNotEmpty == true)
        'wind_direction': current!.windDirection,
      if (current?.windPower.isNotEmpty == true)
        'wind_power': current!.windPower,
      if (today?.dayTempC != null) 'day_temp_c': today!.dayTempC,
      if (today?.nightTempC != null) 'night_temp_c': today!.nightTempC,
      if (today != null)
        'forecast': '${today.dayWeather}/${today.nightWeather}',
      if (result.risks != null) 'risk_flags': result.risks!.toJson(),
      'captured_at': (result.generatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  static double? _weatherDistance(
    Map<String, dynamic> target,
    Map<String, dynamic> prior,
  ) {
    final targetTemp = _temperature(target);
    final priorTemp = _temperature(prior);
    if (targetTemp == null || priorTemp == null) return null;
    final components = <double>[(targetTemp - priorTemp).abs() / 6.0];
    final targetHumidity = _number(target['humidity_pct']);
    final priorHumidity = _number(prior['humidity_pct']);
    if (targetHumidity != null && priorHumidity != null) {
      components.add((targetHumidity - priorHumidity).abs() / 25.0);
    }
    final targetWind = _windNumber(target['wind_power']);
    final priorWind = _windNumber(prior['wind_power']);
    if (targetWind != null && priorWind != null) {
      components.add((targetWind - priorWind).abs() / 3.0);
    }
    if (_isWet(target) != _isWet(prior)) components.add(0.75);
    return components.reduce((a, b) => a + b) / components.length;
  }

  static double? _temperature(Map<String, dynamic> weather) =>
      _number(weather['temperature_c'] ?? weather['day_temp_c']);

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static double? _windNumber(dynamic value) {
    final matches = RegExp(r'\d+').allMatches(value?.toString() ?? '');
    final numbers = matches
        .map((match) => double.tryParse(match.group(0) ?? ''))
        .whereType<double>()
        .toList();
    if (numbers.isEmpty) return null;
    return numbers.reduce((a, b) => a > b ? a : b);
  }

  static bool _isWet(Map<String, dynamic> weather) {
    final text = '${weather['weather'] ?? ''} ${weather['forecast'] ?? ''}'
        .toLowerCase();
    return RegExp(r'(雨|雪|rain|snow|shower)').hasMatch(text);
  }

  static String? _latestRawFeedback(Map<String, dynamic> state) {
    final history = _mapList(state['feedback_history']);
    if (history.isEmpty) return null;
    return history.last['raw']?.toString();
  }

  static String _ymd(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Map<String, dynamic> _mapOrEmpty(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _mapList(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  static List<String> _stringList(dynamic value) => value is List
      ? value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList()
      : <String>[];
}

class DailyOutingCaptureResult {
  const DailyOutingCaptureResult({
    required this.captured,
    this.entityId,
    this.feeling,
  });

  const DailyOutingCaptureResult.ignored()
      : captured = false,
        entityId = null,
        feeling = null;

  final bool captured;
  final String? entityId;
  final String? feeling;
}

class _ComparableOutfitLog {
  const _ComparableOutfitLog({
    required this.date,
    required this.feeling,
    required this.rawFeedback,
    required this.outfitItems,
    required this.weather,
    required this.distance,
  });

  final String date;
  final String feeling;
  final String? rawFeedback;
  final List<String> outfitItems;
  final Map<String, dynamic> weather;
  final double distance;
}
