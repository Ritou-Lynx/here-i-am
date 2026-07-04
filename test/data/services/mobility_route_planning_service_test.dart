import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/data/services/mobility_route_planning_service.dart';

void main() {
  group('MobilityRoutePlanningService', () {
    test('plans a door-to-door Amap transit route', () async {
      final service = MobilityRoutePlanningService(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.contains('/v3/place/text')) {
            final keyword = request.url.queryParameters['keywords'];
            if (keyword == '西二旗某大厦') {
              return _jsonResponse({
                'status': '1',
                'pois': [
                  {
                    'name': '西二旗某大厦',
                    'address': '北京市海淀区',
                    'location': '116.306000,40.052000',
                  }
                ],
              });
            }
            if (keyword == '某小区') {
              return _jsonResponse({
                'status': '1',
                'pois': [
                  {
                    'name': '某小区',
                    'address': '北京市朝阳区',
                    'location': '116.456000,39.932000',
                  }
                ],
              });
            }
          }

          if (url.contains('/v3/direction/transit/integrated')) {
            expect(request.url.queryParameters['origin'], '116.306,40.052');
            expect(
                request.url.queryParameters['destination'], '116.456,39.932');
            expect(request.url.queryParameters['city'], '北京');
            return _jsonResponse({
              'status': '1',
              'route': {
                'transits': [
                  {
                    'duration': '1800',
                    'distance': '18000',
                    'walking_distance': '800',
                    'cost': '5',
                    'segments': [
                      {
                        'walking': {
                          'distance': '500',
                          'duration': '360',
                        },
                        'bus': {
                          'buslines': [
                            {
                              'name': '地铁13号线',
                              'duration': '1200',
                              'departure_stop': {'name': '西二旗'},
                              'arrival_stop': {'name': '望京西'},
                              'via_stops': [
                                {'name': '上地'},
                                {'name': '五道口'},
                              ],
                            }
                          ],
                        },
                      },
                      {
                        'walking': {
                          'distance': '300',
                          'duration': '240',
                        },
                      },
                    ],
                  }
                ],
              },
            });
          }

          return http.Response('{}', 404);
        }),
      );

      final result = await service.planAmapTransitRoute(
        apiKey: 'test-key',
        origin: '西二旗某大厦',
        destination: '某小区',
        city: '北京',
      );

      expect(result.success, isTrue, reason: result.message);
      final route = result.route!;
      expect(route.origin.name, '西二旗某大厦');
      expect(route.destination.name, '某小区');
      expect(route.durationMinutes, 30);
      expect(route.walkingDistanceMeters, 800);
      expect(route.walkingMinutes, 10);
      expect(route.cost, '5');
      expect(route.legs, hasLength(3));
      expect(route.legs[1].lineName, '地铁13号线');
      expect(route.legs[1].departureStop, '西二旗');
      expect(route.legs[1].arrivalStop, '望京西');
      expect(route.summary, contains('地铁13号线'));
    });
  });
}

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
