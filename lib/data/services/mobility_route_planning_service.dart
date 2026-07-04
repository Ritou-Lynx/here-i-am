import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class MobilityRoutePlanningService {
  MobilityRoutePlanningService({http.Client? client})
      : _client = client ?? http.Client();

  static final MobilityRoutePlanningService instance =
      MobilityRoutePlanningService();

  static const _amapPlaceTextUrl = 'https://restapi.amap.com/v3/place/text';
  static const _amapGeoUrl = 'https://restapi.amap.com/v3/geocode/geo';
  static const _amapTransitUrl =
      'https://restapi.amap.com/v3/direction/transit/integrated';

  final http.Client _client;
  final _logger = getLogger('MobilityRoutePlanningService');

  Future<MobilityRoutePlanResult> planTransitRoute({
    required String origin,
    required String destination,
    String? city,
    String? destinationCity,
  }) async {
    final config = await UserStorage.getLocationContextConfig();
    final apiKey = config.amapApiKey.trim();
    if (apiKey.isEmpty) {
      return MobilityRoutePlanResult.error(
        'Amap Web Service API key is not configured. Ask the user to configure '
        '高德 Web 服务 Key in Location settings first.',
      );
    }

    final effectiveCity = await _resolveCity(city);
    if (effectiveCity == null || effectiveCity.trim().isEmpty) {
      return MobilityRoutePlanResult.error(
        'Need city before planning route. Ask the user which city they are in.',
      );
    }

    return planAmapTransitRoute(
      apiKey: apiKey,
      origin: origin,
      destination: destination,
      city: effectiveCity,
      destinationCity: destinationCity,
    );
  }

  Future<MobilityRoutePlanResult> planAmapTransitRoute({
    required String apiKey,
    required String origin,
    required String destination,
    required String city,
    String? destinationCity,
  }) async {
    final originPlace = await _resolvePlace(
      apiKey: apiKey,
      query: origin,
      city: city,
    );
    if (originPlace == null) {
      return MobilityRoutePlanResult.error(
        'Could not resolve origin "$origin". Ask for a more specific building, station, address, or landmark.',
      );
    }

    final destinationPlace = await _resolvePlace(
      apiKey: apiKey,
      query: destination,
      city: destinationCity?.trim().isNotEmpty == true
          ? destinationCity!.trim()
          : city,
    );
    if (destinationPlace == null) {
      return MobilityRoutePlanResult.error(
        'Could not resolve destination "$destination". Ask for a more specific building, community, address, or landmark.',
      );
    }

    final route = await _fetchTransitRoute(
      apiKey: apiKey,
      origin: originPlace,
      destination: destinationPlace,
      city: city,
      destinationCity: destinationCity,
    );
    if (route == null || route.legs.isEmpty) {
      return MobilityRoutePlanResult.error(
        'Amap returned no usable transit route. Ask whether to try a different destination, city, or travel mode.',
      );
    }

    return MobilityRoutePlanResult.success(
      route: route,
      message: route.summary,
    );
  }

  Future<String?> _resolveCity(String? city) async {
    if (city != null && city.trim().isNotEmpty) return city.trim();
    try {
      final context = await LocationContextService.instance.getCurrentContext();
      final inferred = context.address?.city ?? context.address?.province;
      if (inferred != null && inferred.trim().isNotEmpty) {
        return inferred.trim();
      }
    } catch (e) {
      _logger.warning('Failed to infer route city from current location: $e');
    }
    return null;
  }

  Future<MobilityPlace?> _resolvePlace({
    required String apiKey,
    required String query,
    required String city,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    final coordinate = _parseCoordinate(trimmed);
    if (coordinate != null) {
      return MobilityPlace(
        name: trimmed,
        address: trimmed,
        longitude: coordinate.longitude,
        latitude: coordinate.latitude,
      );
    }

    final poi = await _searchAmapPoi(
      apiKey: apiKey,
      query: trimmed,
      city: city,
    );
    if (poi != null) return poi;

    return _geocodeAmap(
      apiKey: apiKey,
      query: trimmed,
      city: city,
    );
  }

  Future<MobilityPlace?> _searchAmapPoi({
    required String apiKey,
    required String query,
    required String city,
  }) async {
    final uri = Uri.parse(_amapPlaceTextUrl).replace(queryParameters: {
      'key': apiKey,
      'keywords': query,
      'city': city,
      'citylimit': 'true',
      'offset': '1',
      'page': '1',
      'extensions': 'base',
      'output': 'json',
    });
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != '1') {
        _logger.warning('Amap POI search rejected: ${data['info']}');
        return null;
      }
      final pois = data['pois'];
      if (pois is! List || pois.isEmpty || pois.first is! Map) return null;
      final first = Map<String, dynamic>.from(pois.first as Map);
      final location = _parseLonLat(first['location']?.toString() ?? '');
      if (location == null) return null;
      return MobilityPlace(
        name: _string(first['name']) ?? query,
        address: _string(first['address']) ?? '',
        longitude: location.longitude,
        latitude: location.latitude,
      );
    } catch (e) {
      _logger.warning('Amap POI search failed: $e');
      return null;
    }
  }

  Future<MobilityPlace?> _geocodeAmap({
    required String apiKey,
    required String query,
    required String city,
  }) async {
    final uri = Uri.parse(_amapGeoUrl).replace(queryParameters: {
      'key': apiKey,
      'address': query,
      'city': city,
      'output': 'json',
    });
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != '1') {
        _logger.warning('Amap geocode rejected: ${data['info']}');
        return null;
      }
      final geocodes = data['geocodes'];
      if (geocodes is! List || geocodes.isEmpty || geocodes.first is! Map) {
        return null;
      }
      final first = Map<String, dynamic>.from(geocodes.first as Map);
      final location = _parseLonLat(first['location']?.toString() ?? '');
      if (location == null) return null;
      return MobilityPlace(
        name: _string(first['formatted_address']) ?? query,
        address: _string(first['formatted_address']) ?? '',
        longitude: location.longitude,
        latitude: location.latitude,
      );
    } catch (e) {
      _logger.warning('Amap geocode failed: $e');
      return null;
    }
  }

  Future<MobilityRoute?> _fetchTransitRoute({
    required String apiKey,
    required MobilityPlace origin,
    required MobilityPlace destination,
    required String city,
    String? destinationCity,
  }) async {
    final uri = Uri.parse(_amapTransitUrl).replace(queryParameters: {
      'key': apiKey,
      'origin': origin.lonLat,
      'destination': destination.lonLat,
      'city': city,
      if (destinationCity != null && destinationCity.trim().isNotEmpty)
        'cityd': destinationCity.trim(),
      'strategy': '0',
      'nightflag': '0',
      'output': 'json',
    });

    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.warning('Amap route planning failed: ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != '1') {
        _logger.warning('Amap route planning rejected: ${data['info']}');
        return null;
      }
      final route = data['route'];
      if (route is! Map) return null;
      final transits = route['transits'];
      if (transits is! List || transits.isEmpty || transits.first is! Map) {
        return null;
      }
      return _parseTransit(
        origin: origin,
        destination: destination,
        transit: Map<String, dynamic>.from(transits.first as Map),
      );
    } catch (e) {
      _logger.warning('Amap route planning failed: $e');
      return null;
    }
  }

  MobilityRoute _parseTransit({
    required MobilityPlace origin,
    required MobilityPlace destination,
    required Map<String, dynamic> transit,
  }) {
    final legs = <MobilityRouteLeg>[];
    final segments = transit['segments'];
    if (segments is List) {
      for (final rawSegment in segments) {
        if (rawSegment is! Map) continue;
        final segment = Map<String, dynamic>.from(rawSegment);
        final walking = segment['walking'];
        final walkingMap =
            walking is Map ? Map<String, dynamic>.from(walking) : null;
        final walkDistance = _toInt(walkingMap?['distance']);
        final walkDuration = _secondsToMinutes(_toInt(walkingMap?['duration']));
        if (walkDistance > 0) {
          legs.add(MobilityRouteLeg.walk(
            distanceMeters: walkDistance,
            durationMinutes: walkDuration > 0
                ? walkDuration
                : math.max((walkDistance / 80).ceil(), 1),
          ));
        }

        final bus = segment['bus'];
        final buslines = bus is Map ? bus['buslines'] : null;
        if (buslines is! List || buslines.isEmpty || buslines.first is! Map) {
          continue;
        }
        final line = Map<String, dynamic>.from(buslines.first as Map);
        final departureStop = _stopName(line['departure_stop']);
        final arrivalStop = _stopName(line['arrival_stop']);
        final viaStops = _viaStopNames(line['via_stops']);
        legs.add(MobilityRouteLeg.ride(
          lineName: _string(line['name']) ?? '公共交通',
          departureStop: departureStop,
          arrivalStop: arrivalStop,
          viaStops: viaStops,
          durationMinutes: _secondsToMinutes(_toInt(line['duration'])),
        ));
      }
    }

    final walkingDistance = _toInt(transit['walking_distance']);
    final walkingMinutes = legs
        .where((leg) => leg.type == MobilityRouteLegType.walk)
        .fold<int>(0, (total, leg) => total + leg.durationMinutes);

    return MobilityRoute(
      origin: origin,
      destination: destination,
      durationMinutes: _secondsToMinutes(_toInt(transit['duration'])),
      distanceMeters: _toInt(transit['distance']),
      walkingDistanceMeters: walkingDistance,
      walkingMinutes: walkingMinutes > 0
          ? walkingMinutes
          : math.max((walkingDistance / 80).ceil(), 0),
      cost: _string(transit['cost']),
      legs: legs,
    );
  }

  MobilityCoordinate? _parseCoordinate(String raw) {
    final parts =
        raw.split(RegExp(r'[,，\s]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length != 2) return null;
    final first = double.tryParse(parts[0]);
    final second = double.tryParse(parts[1]);
    if (first == null || second == null) return null;
    if (first.abs() <= 90 && second.abs() <= 180) {
      return MobilityCoordinate(longitude: second, latitude: first);
    }
    if (first.abs() <= 180 && second.abs() <= 90) {
      return MobilityCoordinate(longitude: first, latitude: second);
    }
    return null;
  }

  MobilityCoordinate? _parseLonLat(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lon == null || lat == null) return null;
    return MobilityCoordinate(longitude: lon, latitude: lat);
  }

  String? _stopName(dynamic value) {
    if (value is! Map) return null;
    return _string(value['name']);
  }

  List<String> _viaStopNames(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => _string(item['name']))
        .whereType<String>()
        .toList(growable: false);
  }

  int _secondsToMinutes(int seconds) {
    if (seconds <= 0) return 0;
    return (seconds / 60).ceil();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _string(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) return _string(value.first);
    return null;
  }
}

class MobilityRoutePlanResult {
  const MobilityRoutePlanResult({
    required this.success,
    required this.message,
    this.route,
  });

  final bool success;
  final String message;
  final MobilityRoute? route;

  factory MobilityRoutePlanResult.success({
    required MobilityRoute route,
    required String message,
  }) {
    return MobilityRoutePlanResult(
      success: true,
      message: message,
      route: route,
    );
  }

  factory MobilityRoutePlanResult.error(String message) {
    return MobilityRoutePlanResult(success: false, message: message);
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        if (route != null) 'route': route!.toJson(),
      };
}

class MobilityRoute {
  const MobilityRoute({
    required this.origin,
    required this.destination,
    required this.durationMinutes,
    required this.distanceMeters,
    required this.walkingDistanceMeters,
    required this.walkingMinutes,
    required this.cost,
    required this.legs,
  });

  final MobilityPlace origin;
  final MobilityPlace destination;
  final int durationMinutes;
  final int distanceMeters;
  final int walkingDistanceMeters;
  final int walkingMinutes;
  final String? cost;
  final List<MobilityRouteLeg> legs;

  String get summary {
    final rideLines = legs
        .where((leg) => leg.type == MobilityRouteLegType.ride)
        .map((leg) => leg.lineName)
        .whereType<String>()
        .toList(growable: false);
    final parts = [
      '${origin.name} -> ${destination.name}',
      if (durationMinutes > 0) 'about $durationMinutes min',
      if (walkingMinutes > 0) 'walk about $walkingMinutes min',
      if (rideLines.isNotEmpty) 'main lines: ${rideLines.join(' / ')}',
    ];
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'duration_minutes': durationMinutes,
        'distance_meters': distanceMeters,
        'walking_distance_meters': walkingDistanceMeters,
        'walking_minutes': walkingMinutes,
        if (cost != null) 'cost': cost,
        'summary': summary,
        'legs': legs.map((leg) => leg.toJson()).toList(),
      };
}

enum MobilityRouteLegType { walk, ride }

class MobilityRouteLeg {
  const MobilityRouteLeg({
    required this.type,
    required this.durationMinutes,
    required this.distanceMeters,
    this.lineName,
    this.departureStop,
    this.arrivalStop,
    this.viaStops = const [],
  });

  final MobilityRouteLegType type;
  final int durationMinutes;
  final int distanceMeters;
  final String? lineName;
  final String? departureStop;
  final String? arrivalStop;
  final List<String> viaStops;

  factory MobilityRouteLeg.walk({
    required int durationMinutes,
    required int distanceMeters,
  }) {
    return MobilityRouteLeg(
      type: MobilityRouteLegType.walk,
      durationMinutes: durationMinutes,
      distanceMeters: distanceMeters,
    );
  }

  factory MobilityRouteLeg.ride({
    required String lineName,
    required String? departureStop,
    required String? arrivalStop,
    required List<String> viaStops,
    required int durationMinutes,
  }) {
    return MobilityRouteLeg(
      type: MobilityRouteLegType.ride,
      durationMinutes: durationMinutes,
      distanceMeters: 0,
      lineName: lineName,
      departureStop: departureStop,
      arrivalStop: arrivalStop,
      viaStops: viaStops,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'duration_minutes': durationMinutes,
        if (distanceMeters > 0) 'distance_meters': distanceMeters,
        if (lineName != null) 'line_name': lineName,
        if (departureStop != null) 'departure_stop': departureStop,
        if (arrivalStop != null) 'arrival_stop': arrivalStop,
        if (viaStops.isNotEmpty) 'via_stops': viaStops,
      };
}

class MobilityPlace {
  const MobilityPlace({
    required this.name,
    required this.address,
    required this.longitude,
    required this.latitude,
  });

  final String name;
  final String address;
  final double longitude;
  final double latitude;

  String get lonLat => '$longitude,$latitude';

  Map<String, dynamic> toJson() => {
        'name': name,
        if (address.trim().isNotEmpty) 'address': address,
        'longitude': longitude,
        'latitude': latitude,
      };
}

class MobilityCoordinate {
  const MobilityCoordinate({required this.longitude, required this.latitude});

  final double longitude;
  final double latitude;
}
