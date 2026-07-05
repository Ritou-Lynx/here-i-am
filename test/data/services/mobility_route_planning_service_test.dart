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
      expect(route.assistantBrief, contains('预计 30 分钟'));
      expect(route.assistantBrief, contains('步行约 10 分钟'));
      expect(route.readableSteps, contains('1. 步行约 6 分钟（约 500 米）'));
      expect(
        route.readableSteps,
        contains('2. 乘坐 地铁13号线，从 西二旗 上车，到 望京西 下车，途经 2 站，约 20 分钟'),
      );

      final json = result.toJson();
      expect(json['assistant_brief'], contains('西二旗某大厦 到 某小区'));
      expect(json['steps'], isA<List>());
      expect(json['steps'], hasLength(3));
      expect(json['cautions'], isNull);
    });

    test('marks long walking exposure as a caution', () {
      final route = MobilityRoute(
        origin: const MobilityPlace(
          name: '起点',
          address: '',
          longitude: 116.3,
          latitude: 40.0,
        ),
        destination: const MobilityPlace(
          name: '终点',
          address: '',
          longitude: 116.4,
          latitude: 40.1,
        ),
        durationMinutes: 35,
        distanceMeters: 9000,
        walkingDistanceMeters: 1600,
        walkingMinutes: 20,
        cost: null,
        legs: [
          MobilityRouteLeg.walk(durationMinutes: 20, distanceMeters: 1600),
          MobilityRouteLeg.ride(
            lineName: '地铁13号线',
            departureStop: '上地',
            arrivalStop: '知春路',
            viaStops: const [],
            durationMinutes: 15,
          ),
        ],
      );

      expect(route.cautions.single, contains('步行暴露偏长'));
      expect(route.toJson()['cautions'], isA<List>());
    });

    test('searches nearby Amap POIs around a coordinate', () async {
      final service = MobilityRoutePlanningService(
        client: MockClient((request) async {
          expect(request.url.path, '/v3/place/around');
          expect(request.url.queryParameters['key'], 'test-key');
          expect(request.url.queryParameters['keywords'], '螺蛳粉');
          expect(request.url.queryParameters['location'], '116.306,40.052');
          expect(request.url.queryParameters['radius'], '3000');
          expect(request.url.queryParameters['sortrule'], 'distance');
          expect(request.url.queryParameters['offset'], '3');
          return _jsonResponse({
            'status': '1',
            'pois': [
              {
                'name': '柳州螺蛳粉',
                'address': '某某商场B1',
                'location': '116.307000,40.052500',
                'distance': '260',
                'type': '餐饮服务;中餐厅',
              },
              {
                'name': '阿姐螺蛳粉',
                'address': '某某街',
                'location': '116.308000,40.053000',
                'distance': '480',
              }
            ],
          });
        }),
      );

      final result = await service.searchAmapNearbyPlaces(
        apiKey: 'test-key',
        query: '螺蛳粉',
        center: const MobilityCoordinate(longitude: 116.306, latitude: 40.052),
        centerLabel: '西二旗',
        radiusMeters: 3000,
        limit: 3,
      );

      expect(result.success, isTrue, reason: result.message);
      expect(result.places, hasLength(2));
      expect(result.places.first.name, '柳州螺蛳粉');
      expect(result.places.first.distanceMeters, 260);
      expect(result.assistantBrief, contains('最近的是 柳州螺蛳粉'));
      expect(result.toJson()['origin_for_route'], '当前位置');
      expect(
        (result.toJson()['places'] as List).first['route_destination'],
        '116.307,40.0525',
      );
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
