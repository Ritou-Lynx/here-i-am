import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/data/services/reminder_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class TransitCompanionService {
  TransitCompanionService._();
  static final TransitCompanionService instance = TransitCompanionService._();

  static const _sessionKeyPrefix = 'transit_companion_session_';
  static const _amapPlaceTextUrl = 'https://restapi.amap.com/v3/place/text';
  static const _amapGeoUrl = 'https://restapi.amap.com/v3/geocode/geo';
  static const _amapTransitUrl =
      'https://restapi.amap.com/v3/direction/transit/integrated';

  final _logger = getLogger('TransitCompanionService');

  Future<TransitPlanResult> startSession({
    required String characterId,
    required String origin,
    required String destination,
    String? city,
    String? destinationCity,
    String? currentStation,
  }) async {
    final apiKey = await _requireAmapApiKey();
    final effectiveCity = await _resolveCity(city);
    if (effectiveCity == null || effectiveCity.trim().isEmpty) {
      return TransitPlanResult.error(
        'Need city before planning transit. Ask the user which city they are in.',
      );
    }

    final resolvedOrigin = await _resolvePlace(
      query: origin,
      city: effectiveCity,
      apiKey: apiKey,
    );
    if (resolvedOrigin == null) {
      return TransitPlanResult.error(
        'Could not resolve origin "$origin". Ask for a more specific station or landmark.',
      );
    }

    final resolvedDestination = await _resolvePlace(
      query: destination,
      city: destinationCity?.trim().isNotEmpty == true
          ? destinationCity!.trim()
          : effectiveCity,
      apiKey: apiKey,
    );
    if (resolvedDestination == null) {
      return TransitPlanResult.error(
        'Could not resolve destination "$destination". Ask for a more specific station, address, or landmark.',
      );
    }

    final route = await _fetchTransitRoute(
      origin: resolvedOrigin,
      destination: resolvedDestination,
      city: effectiveCity,
      destinationCity: destinationCity,
      apiKey: apiKey,
    );
    if (route == null || route.steps.isEmpty) {
      return TransitPlanResult.error(
        'Amap returned no usable transit route. Ask whether to try a different destination, city, or travel mode.',
      );
    }

    final now = DateTime.now();
    final session = TransitSession(
      id: 'transit_${now.microsecondsSinceEpoch}',
      characterId: characterId,
      originLabel: origin.trim(),
      destinationLabel: destination.trim(),
      city: effectiveCity,
      destinationCity: destinationCity?.trim(),
      route: route,
      startedAt: now,
      updatedAt: now,
      currentStationName: currentStation?.trim(),
    );
    await _saveSession(session);

    final reminder = await _scheduleNextCheckIn(
      session,
      reason: 'start',
      minutes: _initialCheckInMinutes(route),
    );

    return TransitPlanResult.success(
      session: session,
      message: 'Transit companion session started.',
      nextInstruction: _nextInstructionForSession(session),
      reminderId: reminder.id,
      nextCheckInMinutes: reminder.minutes,
    );
  }

  Future<TransitProgressResult> updateProgress({
    required String characterId,
    required String currentStation,
    String? note,
  }) async {
    final session = await getSession(characterId);
    if (session == null) {
      return TransitProgressResult.error(
        'No active transit companion session. Ask for origin and destination, then start a session.',
      );
    }

    final station = currentStation.trim();
    if (station.isEmpty) {
      return TransitProgressResult.error('Current station cannot be empty.');
    }

    final match = session.route.findStation(station);
    final updated = match == null
        ? session.copyWith(
            updatedAt: DateTime.now(),
            currentStationName: station,
            lastUserNote: note?.trim(),
            clearMatchedStation: true,
          )
        : session.copyWith(
            updatedAt: DateTime.now(),
            currentStationName: station,
            currentStepIndex: match.stepIndex,
            currentStationIndex: match.stationIndex,
            lastUserNote: note?.trim(),
          );
    await _saveSession(updated);

    if (match == null) {
      return TransitProgressResult.success(
        session: updated,
        matched: false,
        message:
            'Station not found on the active route. The user may be off-route or using a different station name; ask a short clarification or re-plan.',
        nextInstruction: 'Ask whether they changed route or want to re-plan.',
        remainingStops: null,
        nextCheckInMinutes: null,
        reminderId: null,
      );
    }

    final next = _progressInstruction(updated, match);
    final reminder = await _scheduleNextCheckIn(
      updated,
      reason: 'progress',
      minutes: next.checkInMinutes,
    );

    return TransitProgressResult.success(
      session: updated,
      matched: true,
      message: 'Progress updated.',
      nextInstruction: next.text,
      remainingStops: next.remainingStops,
      nextCheckInMinutes: reminder.minutes,
      reminderId: reminder.id,
    );
  }

  Future<TransitSession?> getSession(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_sessionKeyPrefix$characterId');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return TransitSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      _logger.warning('Failed to parse transit session: $e');
      await prefs.remove('$_sessionKeyPrefix$characterId');
      return null;
    }
  }

  Future<bool> endSession(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.remove('$_sessionKeyPrefix$characterId');
  }

  Future<void> _saveSession(TransitSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_sessionKeyPrefix${session.characterId}',
      jsonEncode(session.toJson()),
    );
  }

  Future<String> _requireAmapApiKey() async {
    final config = await UserStorage.getLocationContextConfig();
    if (!config.transitCompanionEnabled) {
      throw StateError(
        'Transit companion routes are disabled. Ask the user to enable 出行陪跑路线 in Location settings.',
      );
    }
    final key = config.amapApiKey.trim();
    if (key.isEmpty) {
      throw StateError(
        'Amap Web Service API key is not configured. Ask the user to configure 高德 Web 服务 Key in Location settings first.',
      );
    }
    return key;
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
      _logger.warning('Failed to infer city for transit route: $e');
    }
    return null;
  }

  Future<TransitPlace?> _resolvePlace({
    required String query,
    required String city,
    required String apiKey,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    final coordinate = _parseCoordinate(trimmed);
    if (coordinate != null) {
      return TransitPlace(
        name: trimmed,
        address: trimmed,
        longitude: coordinate.longitude,
        latitude: coordinate.latitude,
      );
    }

    final poi = await _searchAmapPoi(
      query: trimmed,
      city: city,
      apiKey: apiKey,
    );
    if (poi != null) return poi;

    return _geocodeAmap(query: trimmed, city: city, apiKey: apiKey);
  }

  Future<TransitPlace?> _searchAmapPoi({
    required String query,
    required String city,
    required String apiKey,
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
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
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
      return TransitPlace(
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

  Future<TransitPlace?> _geocodeAmap({
    required String query,
    required String city,
    required String apiKey,
  }) async {
    final uri = Uri.parse(_amapGeoUrl).replace(queryParameters: {
      'key': apiKey,
      'address': query,
      'city': city,
      'output': 'json',
    });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
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
      return TransitPlace(
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

  Future<TransitRoute?> _fetchTransitRoute({
    required TransitPlace origin,
    required TransitPlace destination,
    required String city,
    required String? destinationCity,
    required String apiKey,
  }) async {
    final params = {
      'key': apiKey,
      'origin': origin.lonLat,
      'destination': destination.lonLat,
      'city': city,
      if (destinationCity != null && destinationCity.trim().isNotEmpty)
        'cityd': destinationCity.trim(),
      'strategy': '0',
      'nightflag': '0',
      'output': 'json',
    };
    final uri = Uri.parse(_amapTransitUrl).replace(queryParameters: params);
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.warning('Amap transit route failed: ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != '1') {
        _logger.warning('Amap transit route rejected: ${data['info']}');
        return null;
      }
      final route = data['route'];
      if (route is! Map) return null;
      final transits = route['transits'];
      if (transits is! List || transits.isEmpty || transits.first is! Map) {
        return null;
      }
      final firstTransit = Map<String, dynamic>.from(transits.first as Map);
      return _parseTransitRoute(
        origin: origin,
        destination: destination,
        transit: firstTransit,
      );
    } catch (e) {
      _logger.warning('Amap transit route failed: $e');
      return null;
    }
  }

  TransitRoute _parseTransitRoute({
    required TransitPlace origin,
    required TransitPlace destination,
    required Map<String, dynamic> transit,
  }) {
    final steps = <TransitStep>[];
    final segments = transit['segments'];
    if (segments is List) {
      for (final rawSegment in segments) {
        if (rawSegment is! Map) continue;
        final segment = Map<String, dynamic>.from(rawSegment);
        final walking = segment['walking'];
        final walkDistance = walking is Map ? _toInt(walking['distance']) : 0;
        if (walkDistance > 0) {
          steps.add(TransitStep.walk(distanceMeters: walkDistance));
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
        final stationNames = <String>[
          if (departureStop != null) departureStop,
          ...viaStops,
          if (arrivalStop != null) arrivalStop,
        ];
        steps.add(
          TransitStep.ride(
            lineName: _string(line['name']) ?? '公共交通',
            departureStop: departureStop,
            arrivalStop: arrivalStop,
            viaStops: viaStops,
            stationNames: stationNames,
            durationMinutes: _secondsToMinutes(_toInt(line['duration'])),
          ),
        );
      }
    }

    return TransitRoute(
      origin: origin,
      destination: destination,
      durationMinutes: _secondsToMinutes(_toInt(transit['duration'])),
      walkingDistanceMeters: _toInt(transit['walking_distance']),
      distanceMeters: _toInt(transit['distance']),
      cost: _string(transit['cost']),
      steps: steps,
    );
  }

  String _nextInstructionForSession(TransitSession session) {
    final firstRide =
        session.route.steps.where((step) => step.isRide).firstOrNull;
    if (firstRide == null) {
      return 'No ride segment found. Use the route summary and ask the user to confirm the next station.';
    }
    final departure = firstRide.departureStop ?? '上车站';
    final arrival = firstRide.arrivalStop ?? '下车站';
    final count = math.max(firstRide.stationNames.length - 1, 0);
    return 'Start from $departure on ${firstRide.lineName}, ride toward $arrival, about $count stops before the next key stop.';
  }

  _ProgressInstruction _progressInstruction(
    TransitSession session,
    TransitStationMatch match,
  ) {
    final step = session.route.steps[match.stepIndex];
    if (!step.isRide) {
      return const _ProgressInstruction(
        text:
            'You are on a walking segment. Ask the user to report the next station or landmark after walking.',
        remainingStops: null,
        checkInMinutes: 5,
      );
    }

    final arrivalIndex = step.stationNames.length - 1;
    final remaining = math.max(arrivalIndex - match.stationIndex, 0);
    if (remaining == 0) {
      final nextRide = session.route.nextRideAfter(match.stepIndex);
      if (nextRide == null) {
        return _ProgressInstruction(
          text:
              'They have reached ${step.arrivalStop ?? step.stationNames.last}. This is the final transit stop; guide them through the last walking segment to ${session.destinationLabel}.',
          remainingStops: 0,
          checkInMinutes: 4,
        );
      }
      return _ProgressInstruction(
        text:
            'They are at ${step.arrivalStop ?? step.stationNames.last}. Tell them to get off now and transfer to ${nextRide.lineName} from ${nextRide.departureStop ?? 'the next departure stop'}.',
        remainingStops: 0,
        checkInMinutes: 4,
      );
    }

    final nextStop = step.stationNames[
        math.min(match.stationIndex + 1, step.stationNames.length - 1)];
    final arrival = step.arrivalStop ?? step.stationNames.last;
    return _ProgressInstruction(
      text:
          'They are at ${step.stationNames[match.stationIndex]}. Next stop is $nextStop. They need to get off at $arrival in $remaining stops.',
      remainingStops: remaining,
      checkInMinutes: _checkInMinutesForRemainingStops(remaining),
    );
  }

  int _initialCheckInMinutes(TransitRoute route) {
    final firstRide = route.steps.where((step) => step.isRide).firstOrNull;
    if (firstRide == null) return 5;
    final stops = math.max(firstRide.stationNames.length - 1, 1);
    return _checkInMinutesForRemainingStops(stops);
  }

  int _checkInMinutesForRemainingStops(int stops) {
    if (stops <= 1) return 2;
    return (stops * 3 - 2).clamp(3, 15);
  }

  Future<_ScheduledTransitReminder> _scheduleNextCheckIn(
    TransitSession session, {
    required String reason,
    required int minutes,
  }) async {
    final delay = minutes.clamp(2, 20);
    final dueAt = DateTime.now().add(Duration(minutes: delay));
    final text = [
      'Transit companion follow-up.',
      'Ask the user naturally where they are now, then use TransitProgressUpdate if they report a station.',
      'Do not claim certainty from time alone.',
      'Session: ${session.originLabel} -> ${session.destinationLabel}.',
      if (session.currentStationName != null)
        'Last reported station: ${session.currentStationName}.',
    ].join(' ');
    final id = await ReminderService.instance.createReminder(
      text: text,
      dueAt: dueAt,
      contextJson: jsonEncode({
        'type': 'transit_companion',
        'session_id': session.id,
        'reason': reason,
      }),
    );
    await CheckinService.instance.scheduleReminderAlarm(
      reminderId: id,
      dueAt: dueAt,
    );
    return _ScheduledTransitReminder(id: id, minutes: delay);
  }

  TransitCoordinate? _parseCoordinate(String raw) {
    final parts =
        raw.split(RegExp(r'[,，\s]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length != 2) return null;
    final first = double.tryParse(parts[0]);
    final second = double.tryParse(parts[1]);
    if (first == null || second == null) return null;
    if (first.abs() <= 90 && second.abs() <= 180) {
      return TransitCoordinate(longitude: second, latitude: first);
    }
    if (first.abs() <= 180 && second.abs() <= 90) {
      return TransitCoordinate(longitude: first, latitude: second);
    }
    return null;
  }

  TransitCoordinate? _parseLonLat(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lon == null || lat == null) return null;
    return TransitCoordinate(longitude: lon, latitude: lat);
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

class TransitPlanResult {
  const TransitPlanResult({
    required this.success,
    required this.message,
    this.session,
    this.nextInstruction,
    this.nextCheckInMinutes,
    this.reminderId,
  });

  final bool success;
  final String message;
  final TransitSession? session;
  final String? nextInstruction;
  final int? nextCheckInMinutes;
  final String? reminderId;

  factory TransitPlanResult.success({
    required TransitSession session,
    required String message,
    required String nextInstruction,
    required int nextCheckInMinutes,
    required String reminderId,
  }) {
    return TransitPlanResult(
      success: true,
      message: message,
      session: session,
      nextInstruction: nextInstruction,
      nextCheckInMinutes: nextCheckInMinutes,
      reminderId: reminderId,
    );
  }

  factory TransitPlanResult.error(String message) {
    return TransitPlanResult(success: false, message: message);
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        if (session != null) 'session': session!.toJson(),
        if (nextInstruction != null) 'next_instruction': nextInstruction,
        if (nextCheckInMinutes != null)
          'next_check_in_minutes': nextCheckInMinutes,
        if (reminderId != null) 'reminder_id': reminderId,
      };
}

class TransitProgressResult {
  const TransitProgressResult({
    required this.success,
    required this.matched,
    required this.message,
    this.session,
    this.nextInstruction,
    this.remainingStops,
    this.nextCheckInMinutes,
    this.reminderId,
  });

  final bool success;
  final bool matched;
  final String message;
  final TransitSession? session;
  final String? nextInstruction;
  final int? remainingStops;
  final int? nextCheckInMinutes;
  final String? reminderId;

  factory TransitProgressResult.success({
    required TransitSession session,
    required bool matched,
    required String message,
    required String nextInstruction,
    required int? remainingStops,
    required int? nextCheckInMinutes,
    required String? reminderId,
  }) {
    return TransitProgressResult(
      success: true,
      matched: matched,
      message: message,
      session: session,
      nextInstruction: nextInstruction,
      remainingStops: remainingStops,
      nextCheckInMinutes: nextCheckInMinutes,
      reminderId: reminderId,
    );
  }

  factory TransitProgressResult.error(String message) {
    return TransitProgressResult(
      success: false,
      matched: false,
      message: message,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'matched': matched,
        'message': message,
        if (session != null) 'session': session!.toJson(),
        if (nextInstruction != null) 'next_instruction': nextInstruction,
        if (remainingStops != null) 'remaining_stops': remainingStops,
        if (nextCheckInMinutes != null)
          'next_check_in_minutes': nextCheckInMinutes,
        if (reminderId != null) 'reminder_id': reminderId,
      };
}

class TransitSession {
  const TransitSession({
    required this.id,
    required this.characterId,
    required this.originLabel,
    required this.destinationLabel,
    required this.city,
    required this.route,
    required this.startedAt,
    required this.updatedAt,
    this.destinationCity,
    this.currentStationName,
    this.currentStepIndex,
    this.currentStationIndex,
    this.lastUserNote,
  });

  final String id;
  final String characterId;
  final String originLabel;
  final String destinationLabel;
  final String city;
  final String? destinationCity;
  final TransitRoute route;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String? currentStationName;
  final int? currentStepIndex;
  final int? currentStationIndex;
  final String? lastUserNote;

  TransitSession copyWith({
    DateTime? updatedAt,
    String? currentStationName,
    int? currentStepIndex,
    int? currentStationIndex,
    String? lastUserNote,
    bool clearMatchedStation = false,
  }) {
    return TransitSession(
      id: id,
      characterId: characterId,
      originLabel: originLabel,
      destinationLabel: destinationLabel,
      city: city,
      destinationCity: destinationCity,
      route: route,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currentStationName: currentStationName ?? this.currentStationName,
      currentStepIndex: clearMatchedStation
          ? null
          : currentStepIndex ?? this.currentStepIndex,
      currentStationIndex: clearMatchedStation
          ? null
          : currentStationIndex ?? this.currentStationIndex,
      lastUserNote: lastUserNote ?? this.lastUserNote,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'character_id': characterId,
        'origin_label': originLabel,
        'destination_label': destinationLabel,
        'city': city,
        if (destinationCity != null) 'destination_city': destinationCity,
        'route': route.toJson(),
        'started_at': startedAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (currentStationName != null)
          'current_station_name': currentStationName,
        if (currentStepIndex != null) 'current_step_index': currentStepIndex,
        if (currentStationIndex != null)
          'current_station_index': currentStationIndex,
        if (lastUserNote != null) 'last_user_note': lastUserNote,
      };

  factory TransitSession.fromJson(Map<String, dynamic> json) {
    return TransitSession(
      id: json['id'] as String,
      characterId: json['character_id'] as String,
      originLabel: json['origin_label'] as String,
      destinationLabel: json['destination_label'] as String,
      city: json['city'] as String,
      destinationCity: json['destination_city'] as String?,
      route: TransitRoute.fromJson(json['route'] as Map<String, dynamic>),
      startedAt: DateTime.parse(json['started_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      currentStationName: json['current_station_name'] as String?,
      currentStepIndex: json['current_step_index'] as int?,
      currentStationIndex: json['current_station_index'] as int?,
      lastUserNote: json['last_user_note'] as String?,
    );
  }
}

class TransitRoute {
  const TransitRoute({
    required this.origin,
    required this.destination,
    required this.durationMinutes,
    required this.walkingDistanceMeters,
    required this.distanceMeters,
    required this.steps,
    this.cost,
  });

  final TransitPlace origin;
  final TransitPlace destination;
  final int durationMinutes;
  final int walkingDistanceMeters;
  final int distanceMeters;
  final String? cost;
  final List<TransitStep> steps;

  TransitStationMatch? findStation(String station) {
    final needle = _normalizeStation(station);
    if (needle.isEmpty) return null;
    for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
      final step = steps[stepIndex];
      for (var stationIndex = 0;
          stationIndex < step.stationNames.length;
          stationIndex++) {
        final candidate = _normalizeStation(step.stationNames[stationIndex]);
        if (candidate == needle ||
            candidate.contains(needle) ||
            needle.contains(candidate)) {
          return TransitStationMatch(
            stepIndex: stepIndex,
            stationIndex: stationIndex,
          );
        }
      }
    }
    return null;
  }

  TransitStep? nextRideAfter(int stepIndex) {
    for (var i = stepIndex + 1; i < steps.length; i++) {
      if (steps[i].isRide) return steps[i];
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'duration_minutes': durationMinutes,
        'walking_distance_meters': walkingDistanceMeters,
        'distance_meters': distanceMeters,
        if (cost != null) 'cost': cost,
        'steps': steps.map((step) => step.toJson()).toList(),
      };

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      origin: TransitPlace.fromJson(json['origin'] as Map<String, dynamic>),
      destination:
          TransitPlace.fromJson(json['destination'] as Map<String, dynamic>),
      durationMinutes: json['duration_minutes'] as int? ?? 0,
      walkingDistanceMeters: json['walking_distance_meters'] as int? ?? 0,
      distanceMeters: json['distance_meters'] as int? ?? 0,
      cost: json['cost'] as String?,
      steps: ((json['steps'] as List?) ?? const [])
          .whereType<Map>()
          .map((step) => TransitStep.fromJson(Map<String, dynamic>.from(step)))
          .toList(growable: false),
    );
  }

  static String _normalizeStation(String input) {
    return input
        .replaceAll(RegExp(r'[\s站地铁公交车次号线线路（）()\[\]【】]'), '')
        .toLowerCase();
  }
}

class TransitStep {
  const TransitStep({
    required this.type,
    required this.stationNames,
    this.lineName,
    this.departureStop,
    this.arrivalStop,
    this.viaStops = const [],
    this.durationMinutes,
    this.distanceMeters,
  });

  factory TransitStep.walk({required int distanceMeters}) {
    return TransitStep(
      type: 'walk',
      stationNames: const [],
      distanceMeters: distanceMeters,
    );
  }

  factory TransitStep.ride({
    required String lineName,
    required String? departureStop,
    required String? arrivalStop,
    required List<String> viaStops,
    required List<String> stationNames,
    required int durationMinutes,
  }) {
    return TransitStep(
      type: 'ride',
      lineName: lineName,
      departureStop: departureStop,
      arrivalStop: arrivalStop,
      viaStops: viaStops,
      stationNames: stationNames,
      durationMinutes: durationMinutes,
    );
  }

  final String type;
  final String? lineName;
  final String? departureStop;
  final String? arrivalStop;
  final List<String> viaStops;
  final List<String> stationNames;
  final int? durationMinutes;
  final int? distanceMeters;

  bool get isRide => type == 'ride';

  Map<String, dynamic> toJson() => {
        'type': type,
        if (lineName != null) 'line_name': lineName,
        if (departureStop != null) 'departure_stop': departureStop,
        if (arrivalStop != null) 'arrival_stop': arrivalStop,
        if (viaStops.isNotEmpty) 'via_stops': viaStops,
        if (stationNames.isNotEmpty) 'station_names': stationNames,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        if (distanceMeters != null) 'distance_meters': distanceMeters,
      };

  factory TransitStep.fromJson(Map<String, dynamic> json) {
    return TransitStep(
      type: json['type'] as String? ?? 'walk',
      lineName: json['line_name'] as String?,
      departureStop: json['departure_stop'] as String?,
      arrivalStop: json['arrival_stop'] as String?,
      viaStops: ((json['via_stops'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      stationNames: ((json['station_names'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      durationMinutes: json['duration_minutes'] as int?,
      distanceMeters: json['distance_meters'] as int?,
    );
  }
}

class TransitPlace {
  const TransitPlace({
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
        'address': address,
        'longitude': longitude,
        'latitude': latitude,
      };

  factory TransitPlace.fromJson(Map<String, dynamic> json) {
    return TransitPlace(
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      longitude: (json['longitude'] as num).toDouble(),
      latitude: (json['latitude'] as num).toDouble(),
    );
  }
}

class TransitCoordinate {
  const TransitCoordinate({required this.longitude, required this.latitude});
  final double longitude;
  final double latitude;
}

class TransitStationMatch {
  const TransitStationMatch({
    required this.stepIndex,
    required this.stationIndex,
  });

  final int stepIndex;
  final int stationIndex;
}

class _ScheduledTransitReminder {
  const _ScheduledTransitReminder({required this.id, required this.minutes});
  final String id;
  final int minutes;
}

class _ProgressInstruction {
  const _ProgressInstruction({
    required this.text,
    required this.remainingStops,
    required this.checkInMinutes,
  });

  final String text;
  final int? remainingStops;
  final int checkInMinutes;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
