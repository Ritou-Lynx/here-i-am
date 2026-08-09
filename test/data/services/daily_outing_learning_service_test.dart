import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/daily_outing_learning_service.dart';
import 'package:memex/data/services/weather_risk_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('does not capture an ordinary hot comment without outing context',
      () async {
    final now = DateTime(2026, 8, 10, 12);
    final messageId = await _insertUserMessage(db, '今天真的好热', now);

    final result = await DailyOutingLearningService(
      db,
      weatherLoader: () async => _weather(now: now),
    ).captureUserTurn(
      characterId: 'char-1',
      userMessageId: messageId,
      userMessage: '今天真的好热',
      userMessageTime: now,
    );

    expect(result.captured, isFalse);
    expect(await db.select(db.sharedLifeEntities).get(), isEmpty);
  });

  test('captures outfit then appends same-day comfort feedback', () async {
    final morning = DateTime(2026, 8, 10, 8);
    await _insertCharacterMessage(
      db,
      '今天 29 度，通勤有点风，短袖加薄外套就好。',
      morning,
    );
    final service = DailyOutingLearningService(
      db,
      weatherLoader: () async => _weather(now: morning),
    );

    final outfitTime = morning.add(const Duration(minutes: 10));
    final outfitMessageId =
        await _insertUserMessage(db, '我穿短袖和薄外套', outfitTime);
    final first = await service.captureUserTurn(
      characterId: 'char-1',
      userMessageId: outfitMessageId,
      userMessage: '我穿短袖和薄外套',
      userMessageTime: outfitTime,
    );
    expect(first.captured, isTrue);

    final feedbackTime = morning.add(const Duration(hours: 4));
    final feedbackMessageId =
        await _insertUserMessage(db, '穿多了，很热', feedbackTime);
    final second = await service.captureUserTurn(
      characterId: 'char-1',
      userMessageId: feedbackMessageId,
      userMessage: '穿多了，很热',
      userMessageTime: feedbackTime,
    );

    expect(second.captured, isTrue);
    expect(second.entityId, first.entityId);
    final entities = await db.select(db.sharedLifeEntities).get();
    expect(entities, hasLength(1));
    expect(entities.single.entityType, 'outfit_log');
    final state = jsonDecode(entities.single.stateJson) as Map<String, dynamic>;
    expect(state['outfit_items'], ['薄外套', '短袖']);
    expect(state['outfit_evidence'], 'user_explicit');
    expect(state['subjective_feeling'], 'too_hot');
    expect(state['weather_snapshot']['temperature_c'], 28.0);
    expect(state['weather_snapshot']['humidity_pct'], 72);
    expect(state['feedback_history'], hasLength(1));
    expect(
      await db.select(db.sharedLifeEventOperations).get(),
      hasLength(2),
    );
  });

  test('similar weather turns prior hot feedback into a lighter-layer anchor',
      () async {
    final prior = DateTime(2026, 8, 9, 8);
    await _insertCharacterMessage(
      db,
      '今天出门 28 度，穿短袖加薄外套。',
      prior,
    );
    final service = DailyOutingLearningService(
      db,
      weatherLoader: () async => _weather(now: prior),
    );
    final feedbackAt = prior.add(const Duration(hours: 3));
    final messageId = await _insertUserMessage(db, '薄外套穿多了，很热', feedbackAt);
    await service.captureUserTurn(
      characterId: 'char-1',
      userMessageId: messageId,
      userMessage: '薄外套穿多了，很热',
      userMessageTime: feedbackAt,
    );

    final guidance = await service.buildLearnedGuidance(
      currentWeather: _weather(
        now: DateTime(2026, 8, 10, 8),
        temperature: '29',
        humidity: '68',
      ),
      now: DateTime(2026, 8, 10, 8),
    );

    expect(guidance, contains('Closest prior outing: 2026-08-09'));
    expect(guidance, contains('薄外套'));
    expect(guidance, contains('Recommend one layer lighter'));
    expect(guidance, contains('穿多了，很热'));
  });

  test('feeling and outfit parsing is deterministic', () {
    expect(
      DailyOutingLearningService.classifyFeeling('穿少了，冻死我了'),
      'too_cold',
    );
    expect(
      DailyOutingLearningService.classifyFeeling('今天不冷不热，刚刚好'),
      'comfortable',
    );
    expect(
      DailyOutingLearningService.extractOutfitItems('短袖、薄外套和长裤'),
      ['薄外套', '短袖', '长裤'],
    );
  });
}

Future<int> _insertCharacterMessage(
  AppDatabase db,
  String content,
  DateTime timestamp,
) {
  return db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: 'char-1',
          isFromCharacter: true,
          content: content,
          timestamp: timestamp,
        ),
      );
}

Future<int> _insertUserMessage(
  AppDatabase db,
  String content,
  DateTime timestamp,
) {
  return db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: 'char-1',
          isFromCharacter: false,
          content: content,
          timestamp: timestamp,
        ),
      );
}

WeatherRiskResult _weather({
  required DateTime now,
  String temperature = '28',
  String humidity = '72',
}) {
  return WeatherRiskResult(
    success: true,
    message: 'No obvious risk.',
    provider: 'amap',
    city: '北京市',
    adcode: '110000',
    generatedAt: now,
    current: WeatherCurrentConditions(
      weather: '多云',
      temperature: temperature,
      humidity: humidity,
      windDirection: '北',
      windPower: '3',
      reportTime: now,
    ),
    casts: const [
      WeatherDailyForecast(
        date: '2026-08-10',
        week: '1',
        dayWeather: '多云',
        nightWeather: '晴',
        dayTemp: '30',
        nightTemp: '22',
        dayWind: '北',
        nightWind: '北',
        dayPower: '3',
        nightPower: '2',
      ),
    ],
  );
}
