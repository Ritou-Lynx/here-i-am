import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/data/services/weather_risk_service.dart';

void main() {
  group('WeatherRiskService', () {
    test('turns Amap forecast into practical outing risks', () async {
      final service = WeatherRiskService(
        client: MockClient((request) async {
          if (request.url.toString().contains('/v3/geocode/geo')) {
            return _jsonResponse(
              jsonEncode({
                'status': '1',
                'geocodes': [
                  {
                    'city': '北京市',
                    'adcode': '110000',
                    'formatted_address': '北京市',
                  }
                ],
              }),
            );
          }

          if (request.url.toString().contains('/v3/weather/weatherInfo')) {
            expect(request.url.queryParameters['city'], '110000');
            if (request.url.queryParameters['extensions'] == 'base') {
              return _jsonResponse(
                jsonEncode({
                  'status': '1',
                  'lives': [
                    {
                      'weather': '多云',
                      'temperature': '27.5',
                      'humidity': '71',
                      'winddirection': '北',
                      'windpower': '3',
                      'reporttime': '2026-07-04 08:10:00',
                    }
                  ],
                }),
              );
            }
            expect(request.url.queryParameters['extensions'], 'all');
            return _jsonResponse(
              jsonEncode({
                'status': '1',
                'forecasts': [
                  {
                    'city': '北京市',
                    'adcode': '110000',
                    'reporttime': '2026-07-04 08:00:00',
                    'casts': [
                      {
                        'date': '2026-07-04',
                        'week': '6',
                        'dayweather': '多云',
                        'nightweather': '小雨',
                        'daytemp': '31',
                        'nighttemp': '20',
                        'daywind': '北',
                        'nightwind': '北',
                        'daypower': '3',
                        'nightpower': '4',
                      }
                    ],
                  }
                ],
              }),
            );
          }

          return http.Response('{}', 404);
        }),
      );

      final result = await service.assessAmapOutingRisk(
        apiKey: 'test-key',
        cityOrAdcode: '北京',
        walkingMinutes: 18,
      );

      expect(result.success, isTrue, reason: result.message);
      expect(result.city, '北京市');
      expect(result.adcode, '110000');
      expect(result.risks?.bringUmbrella, isTrue);
      expect(result.risks?.eveningRainRisk, isTrue);
      expect(result.risks?.temperatureDropRisk, isTrue);
      expect(result.risks?.windRisk, isTrue);
      expect(result.risks?.longWalkExposureRisk, isTrue);
      expect(result.risks?.uvRiskAvailable, isFalse);
      expect(result.risks?.suggestions, isNotEmpty);
      expect(result.current?.temperatureC, 27.5);
      expect(result.current?.humidityPct, 71);
      expect(result.toJson()['current']['wind_power'], '3');
    });

    test('accepts an Amap adcode directly', () async {
      final service = WeatherRiskService(
        client: MockClient((request) async {
          expect(request.url.toString().contains('/v3/geocode/geo'), isFalse);
          if (request.url.queryParameters['extensions'] == 'base') {
            return _jsonResponse(jsonEncode({'status': '1', 'lives': []}));
          }
          return _jsonResponse(
            jsonEncode({
              'status': '1',
              'forecasts': [
                {
                  'city': '上海市',
                  'adcode': '310000',
                  'reporttime': '2026-07-04 08:00:00',
                  'casts': [
                    {
                      'date': '2026-07-04',
                      'week': '6',
                      'dayweather': '晴',
                      'nightweather': '晴',
                      'daytemp': '28',
                      'nighttemp': '23',
                      'daywind': '东',
                      'nightwind': '东',
                      'daypower': '<3',
                      'nightpower': '<3',
                    }
                  ],
                }
              ],
            }),
          );
        }),
      );

      final result = await service.assessAmapOutingRisk(
        apiKey: 'test-key',
        cityOrAdcode: '310000',
      );

      expect(result.success, isTrue, reason: result.message);
      expect(result.risks?.bringUmbrella, isFalse);
      expect(result.risks?.suggestions, isEmpty);
    });
  });
}

http.Response _jsonResponse(String body) {
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
