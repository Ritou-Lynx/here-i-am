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
  static const _amapPlaceAroundUrl = 'https://restapi.amap.com/v3/place/around';
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

  Future<NearbyPlaceSearchResult> searchNearbyPlaces({
    required String query,
    String? types,
    int radiusMeters = 3000,
    int limit = 5,
  }) async {
    final config = await UserStorage.getLocationContextConfig();
    final apiKey = config.amapApiKey.trim();
    if (apiKey.isEmpty) {
      return NearbyPlaceSearchResult.error(
        'Amap Web Service API key is not configured. Ask the user to configure 高德 Web 服务 Key in Location settings first.',
        query: query,
        radiusMeters: radiusMeters,
      );
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return NearbyPlaceSearchResult.error(
        'Need a nearby place keyword, such as 螺蛳粉, 商场, 咖啡, 药店, or 便利店.',
        query: query,
        radiusMeters: radiusMeters,
      );
    }

    try {
      final context = await LocationContextService.instance.getCurrentContext();
      if (!context.isFresh ||
          context.latitude == null ||
          context.longitude == null) {
        return NearbyPlaceSearchResult.error(
          'Need current device location before searching nearby places. Reason: ${context.reason ?? context.status}.',
          query: trimmedQuery,
          radiusMeters: radiusMeters,
        );
      }

      final centerGcj = _wgs84ToGcj02(context.latitude!, context.longitude!);
      final centerLabel = context.address?.summary(context.granularity) ??
          context.address?.city ??
          '当前位置';
      return searchAmapNearbyPlaces(
        apiKey: apiKey,
        query: trimmedQuery,
        center: MobilityCoordinate(
          longitude: centerGcj.longitude,
          latitude: centerGcj.latitude,
        ),
        centerLabel: centerLabel,
        types: types,
        radiusMeters: radiusMeters,
        limit: limit,
      );
    } catch (e) {
      _logger.warning('Nearby place search failed before Amap request: $e');
      return NearbyPlaceSearchResult.error(
        'Failed to get current location for nearby place search: $e',
        query: trimmedQuery,
        radiusMeters: radiusMeters,
      );
    }
  }

  Future<NearbyPlaceSearchResult> searchAmapNearbyPlaces({
    required String apiKey,
    required String query,
    required MobilityCoordinate center,
    String? centerLabel,
    String? types,
    int radiusMeters = 3000,
    int limit = 5,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return NearbyPlaceSearchResult.error(
        'Need a nearby place keyword.',
        query: query,
        radiusMeters: radiusMeters,
        centerLabel: centerLabel,
      );
    }

    final radius = radiusMeters.clamp(100, 50000).toInt();
    final offset = limit.clamp(1, 10).toInt();
    final uri = Uri.parse(_amapPlaceAroundUrl).replace(queryParameters: {
      'key': apiKey,
      'keywords': trimmedQuery,
      if (types != null && types.trim().isNotEmpty) 'types': types.trim(),
      'location': center.lonLat,
      'radius': radius.toString(),
      'sortrule': 'distance',
      'offset': offset.toString(),
      'page': '1',
      'extensions': 'base',
      'output': 'json',
    });

    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return NearbyPlaceSearchResult.error(
          'Amap nearby place search failed with HTTP ${response.statusCode}.',
          query: trimmedQuery,
          radiusMeters: radius,
          centerLabel: centerLabel,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != '1') {
        final info = _string(data['info']) ?? 'unknown error';
        _logger.warning('Amap nearby place search rejected: $info');
        return NearbyPlaceSearchResult.error(
          'Amap nearby place search rejected: $info.',
          query: trimmedQuery,
          radiusMeters: radius,
          centerLabel: centerLabel,
        );
      }

      final places = _parseNearbyPlaces(data['pois']);
      return NearbyPlaceSearchResult.success(
        query: trimmedQuery,
        radiusMeters: radius,
        centerLabel: centerLabel,
        places: places,
        message: places.isEmpty
            ? 'No nearby places found for "$trimmedQuery" within $radius meters.'
            : 'Found ${places.length} nearby places for "$trimmedQuery".',
      );
    } catch (e) {
      _logger.warning('Amap nearby place search failed: $e');
      return NearbyPlaceSearchResult.error(
        'Amap nearby place search failed: $e',
        query: trimmedQuery,
        radiusMeters: radius,
        centerLabel: centerLabel,
      );
    }
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

    if (_isCurrentLocationQuery(trimmed)) {
      final currentPlace = await _resolveCurrentLocationPlace();
      if (currentPlace != null) return currentPlace;
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

  Future<MobilityPlace?> _resolveCurrentLocationPlace() async {
    try {
      final context = await LocationContextService.instance.getCurrentContext();
      if (!context.isFresh ||
          context.latitude == null ||
          context.longitude == null) {
        _logger.warning(
          'Current location is unavailable for route planning: ${context.reason ?? context.status}',
        );
        return null;
      }
      final gcj = _wgs84ToGcj02(context.latitude!, context.longitude!);
      final label = context.address?.summary(context.granularity);
      return MobilityPlace(
        name: '当前位置',
        address: label ?? '设备当前位置',
        longitude: gcj.longitude,
        latitude: gcj.latitude,
      );
    } catch (e) {
      _logger.warning('Failed to resolve current location for route: $e');
      return null;
    }
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

  List<NearbyPlace> _parseNearbyPlaces(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) {
          final raw = Map<String, dynamic>.from(item);
          final location = _parseLonLat(raw['location']?.toString() ?? '');
          if (location == null) return null;
          return NearbyPlace(
            name: _string(raw['name']) ?? '未命名地点',
            address: _string(raw['address']) ?? '',
            longitude: location.longitude,
            latitude: location.latitude,
            distanceMeters: _toInt(raw['distance']),
            type: _string(raw['type']),
            tel: _string(raw['tel']),
          );
        })
        .whereType<NearbyPlace>()
        .toList(growable: false);
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

  bool _isCurrentLocationQuery(String raw) {
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[\s_，,。\.]+'), '');
    return normalized == '当前位置' ||
        normalized == '当前地点' ||
        normalized == '我这里' ||
        normalized == '我这儿' ||
        normalized == '这里' ||
        normalized == '此处' ||
        normalized == 'currentlocation' ||
        normalized == 'current';
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

  ({double latitude, double longitude}) _wgs84ToGcj02(
    double latitude,
    double longitude,
  ) {
    if (_outOfChina(latitude, longitude)) {
      return (latitude: latitude, longitude: longitude);
    }

    var dLat = _transformLat(longitude - 105.0, latitude - 35.0);
    var dLon = _transformLon(longitude - 105.0, latitude - 35.0);
    final radLat = latitude / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - 0.00669342162296594323 * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = (dLat * 180.0) /
        ((6378245.0 * (1 - 0.00669342162296594323)) /
            (magic * sqrtMagic) *
            math.pi);
    dLon =
        (dLon * 180.0) / (6378245.0 / sqrtMagic * math.cos(radLat) * math.pi);
    return (latitude: latitude + dLat, longitude: longitude + dLon);
  }

  bool _outOfChina(double latitude, double longitude) {
    return longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271;
  }

  double _transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y / 12.0 * math.pi) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  double _transformLon(double x, double y) {
    var ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 /
        3.0;
    return ret;
  }
}

class NearbyPlaceSearchResult {
  const NearbyPlaceSearchResult({
    required this.success,
    required this.message,
    required this.query,
    required this.radiusMeters,
    required this.places,
    this.centerLabel,
  });

  final bool success;
  final String message;
  final String query;
  final int radiusMeters;
  final String? centerLabel;
  final List<NearbyPlace> places;

  factory NearbyPlaceSearchResult.success({
    required String query,
    required int radiusMeters,
    required List<NearbyPlace> places,
    required String message,
    String? centerLabel,
  }) {
    return NearbyPlaceSearchResult(
      success: true,
      message: message,
      query: query,
      radiusMeters: radiusMeters,
      centerLabel: centerLabel,
      places: places,
    );
  }

  factory NearbyPlaceSearchResult.error(
    String message, {
    required String query,
    required int radiusMeters,
    String? centerLabel,
  }) {
    return NearbyPlaceSearchResult(
      success: false,
      message: message,
      query: query,
      radiusMeters: radiusMeters,
      centerLabel: centerLabel,
      places: const [],
    );
  }

  String get assistantBrief {
    if (!success) return message;
    if (places.isEmpty) {
      return '附近 ${_formatDistance(radiusMeters)} 内没有找到“$query”，可以扩大范围或换一个关键词。';
    }
    final nearest = places.first;
    return '附近 ${_formatDistance(radiusMeters)} 内找到 ${places.length} 个“$query”，最近的是 ${nearest.name}，约 ${_formatDistance(nearest.distanceMeters)}。';
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'query': query,
        'provider': 'amap',
        'radius_meters': radiusMeters,
        if (centerLabel != null && centerLabel!.trim().isNotEmpty)
          'center_label': centerLabel,
        'origin_for_route': '当前位置',
        'assistant_brief': assistantBrief,
        'places': places.map((place) => place.toJson()).toList(),
      };
}

class NearbyPlace {
  const NearbyPlace({
    required this.name,
    required this.address,
    required this.longitude,
    required this.latitude,
    required this.distanceMeters,
    this.type,
    this.tel,
  });

  final String name;
  final String address;
  final double longitude;
  final double latitude;
  final int distanceMeters;
  final String? type;
  final String? tel;

  String get lonLat => '$longitude,$latitude';

  String get routeDestination {
    if (address.trim().isEmpty) return name;
    return '$name $address';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (address.trim().isNotEmpty) 'address': address,
        'distance_meters': distanceMeters,
        if (type != null) 'type': type,
        if (tel != null) 'tel': tel,
        'longitude': longitude,
        'latitude': latitude,
        'route_destination': lonLat,
        'readable': '$name，约 ${_formatDistance(distanceMeters)}',
      };
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
        if (route != null) 'assistant_brief': route!.assistantBrief,
        if (route != null) 'steps': route!.readableSteps,
        if (route != null && route!.cautions.isNotEmpty)
          'cautions': route!.cautions,
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

  String get assistantBrief {
    final rideLines = legs
        .where((leg) => leg.type == MobilityRouteLegType.ride)
        .map((leg) => leg.lineName)
        .whereType<String>()
        .toList(growable: false);
    final parts = [
      '${origin.name} 到 ${destination.name}',
      if (durationMinutes > 0) '预计 $durationMinutes 分钟',
      if (walkingMinutes > 0)
        '步行约 $walkingMinutes 分钟（约 ${_formatDistance(walkingDistanceMeters)}）',
      if (rideLines.isNotEmpty) '主要乘坐 ${rideLines.join(' / ')}',
      if (cost != null) '票价约 $cost 元',
    ];
    return '${parts.join('，')}。';
  }

  String get summary => assistantBrief;

  List<String> get readableSteps {
    if (legs.isEmpty) return const [];
    return [
      for (var i = 0; i < legs.length; i++)
        '${i + 1}. ${legs[i].readableDescription}',
    ];
  }

  List<String> get cautions {
    final items = <String>[];
    final rideCount =
        legs.where((leg) => leg.type == MobilityRouteLegType.ride).length;
    if (walkingMinutes >= 15 || walkingDistanceMeters >= 1200) {
      items.add('步行暴露偏长，出门前建议顺手看一下天气，雨天或暴晒时考虑少走路的方案。');
    }
    if (rideCount >= 2) {
      items.add('这条路线有换乘，出发后可以让 I 帮你盯下车点和换乘点。');
    }
    if (rideCount == 0) {
      items.add('高德没有返回明确的公交/地铁乘车段，建议和用户确认是否需要步行、打车或重新规划。');
    }
    return items;
  }

  Map<String, dynamic> toJson() => {
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'duration_minutes': durationMinutes,
        'distance_meters': distanceMeters,
        'walking_distance_meters': walkingDistanceMeters,
        'walking_minutes': walkingMinutes,
        if (cost != null) 'cost': cost,
        'assistant_brief': assistantBrief,
        'summary': summary,
        'steps': readableSteps,
        if (cautions.isNotEmpty) 'cautions': cautions,
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

  String get readableDescription {
    switch (type) {
      case MobilityRouteLegType.walk:
        return '步行约 $durationMinutes 分钟（约 ${_formatDistance(distanceMeters)}）';
      case MobilityRouteLegType.ride:
        final parts = [
          '乘坐 ${lineName ?? '公共交通'}',
          if (departureStop != null) '从 $departureStop 上车',
          if (arrivalStop != null) '到 $arrivalStop 下车',
          if (viaStops.isNotEmpty) '途经 ${viaStops.length} 站',
          if (durationMinutes > 0) '约 $durationMinutes 分钟',
        ];
        return parts.join('，');
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'duration_minutes': durationMinutes,
        if (distanceMeters > 0) 'distance_meters': distanceMeters,
        if (lineName != null) 'line_name': lineName,
        if (departureStop != null) 'departure_stop': departureStop,
        if (arrivalStop != null) 'arrival_stop': arrivalStop,
        if (viaStops.isNotEmpty) 'via_stop_count': viaStops.length,
        if (viaStops.isNotEmpty) 'via_stops': viaStops,
        'readable': readableDescription,
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

  String get lonLat => '$longitude,$latitude';
}

String _formatDistance(int meters) {
  if (meters <= 0) return '未知距离';
  if (meters < 1000) return '$meters 米';
  final kilometers = meters / 1000;
  return '${kilometers.toStringAsFixed(kilometers >= 10 ? 0 : 1)} 公里';
}
