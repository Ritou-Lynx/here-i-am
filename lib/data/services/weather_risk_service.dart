import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class WeatherRiskService {
  WeatherRiskService({http.Client? client}) : _client = client ?? http.Client();

  static final WeatherRiskService instance = WeatherRiskService();

  static const _amapWeatherUrl =
      'https://restapi.amap.com/v3/weather/weatherInfo';
  static const _amapGeoUrl = 'https://restapi.amap.com/v3/geocode/geo';

  final http.Client _client;
  final _logger = getLogger('WeatherRiskService');

  Future<WeatherRiskResult> assessOutingRisk({
    String? cityOrAdcode,
    int? walkingMinutes,
    DateTime? now,
  }) async {
    final config = await UserStorage.getLocationContextConfig();
    final apiKey = config.amapApiKey.trim();
    if (apiKey.isEmpty) {
      return WeatherRiskResult.error(
        'Amap Web Service API key is not configured. Ask the user to configure '
        '高德 Web 服务 Key in Location settings first.',
      );
    }

    final location = cityOrAdcode?.trim().isNotEmpty == true
        ? cityOrAdcode!.trim()
        : await _inferCityFromCurrentLocation();
    if (location == null || location.trim().isEmpty) {
      return WeatherRiskResult.error(
        'Need a city before checking weather risk. Ask which city or destination.',
      );
    }

    return assessAmapOutingRisk(
      apiKey: apiKey,
      cityOrAdcode: location,
      walkingMinutes: walkingMinutes,
      now: now,
    );
  }

  Future<WeatherRiskResult> assessAmapOutingRisk({
    required String apiKey,
    required String cityOrAdcode,
    int? walkingMinutes,
    DateTime? now,
  }) async {
    final generatedAt = now ?? DateTime.now();
    final location = cityOrAdcode.trim();
    if (location.isEmpty) {
      return WeatherRiskResult.error('City or adcode cannot be empty.');
    }

    final resolved = await _resolveAmapAdcode(
      apiKey: apiKey,
      cityOrAdcode: location,
    );
    if (resolved == null) {
      return WeatherRiskResult.error(
        'Could not resolve "$location" to an Amap city adcode.',
      );
    }

    final forecast = await _fetchAmapForecast(
      apiKey: apiKey,
      adcode: resolved.adcode,
    );
    if (forecast == null || forecast.casts.isEmpty) {
      return WeatherRiskResult.error(
        'Amap weather returned no usable forecast for ${resolved.name}.',
      );
    }

    final risks = WeatherActionRisks.fromForecast(
      forecast.casts,
      walkingMinutes: walkingMinutes,
    );

    return WeatherRiskResult(
      success: true,
      message: risks.primaryMessage,
      provider: 'amap',
      city: forecast.city.isNotEmpty ? forecast.city : resolved.name,
      adcode: forecast.adcode.isNotEmpty ? forecast.adcode : resolved.adcode,
      reportTime: forecast.reportTime,
      generatedAt: generatedAt,
      walkingMinutes: walkingMinutes,
      casts: forecast.casts,
      risks: risks,
    );
  }

  Future<String?> _inferCityFromCurrentLocation() async {
    try {
      final context = await LocationContextService.instance.getCurrentContext();
      final address = context.address;
      return address?.city ?? address?.district ?? address?.province;
    } catch (e) {
      _logger.warning('Failed to infer weather city from location: $e');
      return null;
    }
  }

  Future<_AmapResolvedCity?> _resolveAmapAdcode({
    required String apiKey,
    required String cityOrAdcode,
  }) async {
    final trimmed = cityOrAdcode.trim();
    if (RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      return _AmapResolvedCity(name: trimmed, adcode: trimmed);
    }

    final uri = Uri.parse(_amapGeoUrl).replace(queryParameters: {
      'key': apiKey,
      'address': trimmed,
      'output': 'json',
    });

    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != '1') {
        _logger.warning('Amap city geocode rejected: ${data['info']}');
        return null;
      }
      final geocodes = data['geocodes'];
      if (geocodes is! List || geocodes.isEmpty || geocodes.first is! Map) {
        return null;
      }
      final first = Map<String, dynamic>.from(geocodes.first as Map);
      final adcode = _string(first['adcode']);
      if (adcode == null || !RegExp(r'^\d{6}$').hasMatch(adcode)) {
        return null;
      }
      return _AmapResolvedCity(
        name: _string(first['city']) ??
            _string(first['district']) ??
            _string(first['formatted_address']) ??
            trimmed,
        adcode: adcode,
      );
    } catch (e) {
      _logger.warning('Amap city geocode failed: $e');
      return null;
    }
  }

  Future<_AmapWeatherForecast?> _fetchAmapForecast({
    required String apiKey,
    required String adcode,
  }) async {
    final uri = Uri.parse(_amapWeatherUrl).replace(queryParameters: {
      'key': apiKey,
      'city': adcode,
      'extensions': 'all',
      'output': 'json',
    });

    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != '1') {
        _logger.warning('Amap weather rejected: ${data['info']}');
        return null;
      }

      final forecasts = data['forecasts'];
      if (forecasts is! List || forecasts.isEmpty || forecasts.first is! Map) {
        return null;
      }

      final first = Map<String, dynamic>.from(forecasts.first as Map);
      final rawCasts = first['casts'];
      final casts = rawCasts is List
          ? rawCasts
              .whereType<Map>()
              .map((item) => WeatherDailyForecast.fromAmap(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : <WeatherDailyForecast>[];

      return _AmapWeatherForecast(
        city: _string(first['city']) ?? '',
        adcode: _string(first['adcode']) ?? adcode,
        reportTime: DateTime.tryParse(_string(first['reporttime']) ?? ''),
        casts: casts,
      );
    } catch (e) {
      _logger.warning('Amap weather failed: $e');
      return null;
    }
  }

  static String? _string(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) return _string(value.first);
    return null;
  }
}

class WeatherRiskResult {
  const WeatherRiskResult({
    required this.success,
    required this.message,
    this.provider,
    this.city,
    this.adcode,
    this.reportTime,
    this.generatedAt,
    this.walkingMinutes,
    this.casts = const [],
    this.risks,
  });

  final bool success;
  final String message;
  final String? provider;
  final String? city;
  final String? adcode;
  final DateTime? reportTime;
  final DateTime? generatedAt;
  final int? walkingMinutes;
  final List<WeatherDailyForecast> casts;
  final WeatherActionRisks? risks;

  factory WeatherRiskResult.error(String message) {
    return WeatherRiskResult(success: false, message: message);
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        if (provider != null) 'provider': provider,
        if (city != null) 'city': city,
        if (adcode != null) 'adcode': adcode,
        if (reportTime != null) 'report_time': reportTime!.toIso8601String(),
        if (generatedAt != null) 'generated_at': generatedAt!.toIso8601String(),
        if (walkingMinutes != null) 'walking_minutes': walkingMinutes,
        if (risks != null) 'risks': risks!.toJson(),
        'forecast': casts.map((cast) => cast.toJson()).toList(),
      };
}

class WeatherActionRisks {
  const WeatherActionRisks({
    required this.bringUmbrella,
    required this.eveningRainRisk,
    required this.temperatureDropRisk,
    required this.windRisk,
    required this.heatRisk,
    required this.coldRisk,
    required this.longWalkExposureRisk,
    required this.uvRiskAvailable,
    required this.reasons,
    required this.suggestions,
  });

  final bool bringUmbrella;
  final bool eveningRainRisk;
  final bool temperatureDropRisk;
  final bool windRisk;
  final bool heatRisk;
  final bool coldRisk;
  final bool longWalkExposureRisk;
  final bool uvRiskAvailable;
  final List<String> reasons;
  final List<String> suggestions;

  String get primaryMessage {
    if (suggestions.isEmpty) {
      return 'No obvious outing weather risk in the forecast.';
    }
    return suggestions.first;
  }

  factory WeatherActionRisks.fromForecast(
    List<WeatherDailyForecast> casts, {
    int? walkingMinutes,
  }) {
    final today = casts.isNotEmpty ? casts.first : null;
    final reasons = <String>[];
    final suggestions = <String>[];

    if (today == null) {
      return const WeatherActionRisks(
        bringUmbrella: false,
        eveningRainRisk: false,
        temperatureDropRisk: false,
        windRisk: false,
        heatRisk: false,
        coldRisk: false,
        longWalkExposureRisk: false,
        uvRiskAvailable: false,
        reasons: [],
        suggestions: [],
      );
    }

    final dayRain = _hasPrecipitation(today.dayWeather);
    final nightRain = _hasPrecipitation(today.nightWeather);
    final bringUmbrella = dayRain || nightRain;
    if (bringUmbrella) {
      reasons.add(
        'Forecast mentions precipitation: ${today.dayWeather}/${today.nightWeather}.',
      );
      suggestions.add(
        nightRain
            ? 'Tonight has rain risk. Ask the user to take an umbrella before leaving.'
            : 'There is rain risk today. Ask the user to take an umbrella.',
      );
    }

    final dayTemp = today.dayTempC;
    final nightTemp = today.nightTempC;
    final tempDrop =
        dayTemp != null && nightTemp != null ? dayTemp - nightTemp : null;
    final temperatureDropRisk = tempDrop != null && tempDrop >= 8;
    if (temperatureDropRisk) {
      reasons.add('Day-night temperature gap is ${tempDrop.round()}C.');
      suggestions.add(
        'The temperature drops a lot after dark. Suggest taking a light jacket.',
      );
    }

    final windRisk =
        _windPowerRisk(today.dayPower) || _windPowerRisk(today.nightPower);
    if (windRisk) {
      reasons.add('Wind power is ${today.dayPower}/${today.nightPower}.');
      suggestions.add(
        'Wind may be noticeable today. Mention wind protection if they walk outside.',
      );
    }

    final heatRisk = dayTemp != null && dayTemp >= 32;
    if (heatRisk) {
      reasons.add('Day temperature reaches ${dayTemp.round()}C.');
      suggestions.add(
        'It may be hot outside. Suggest shade, water, or reducing long walks.',
      );
    }

    final coldRisk = nightTemp != null && nightTemp <= 5;
    if (coldRisk) {
      reasons.add('Night temperature drops to ${nightTemp.round()}C.');
      suggestions.add(
        'It may be cold when returning. Suggest warmer clothing before leaving.',
      );
    }

    final longWalkExposureRisk = (walkingMinutes ?? 0) >= 15 &&
        (bringUmbrella || windRisk || heatRisk || coldRisk);
    if (longWalkExposureRisk) {
      reasons.add('Route includes about $walkingMinutes minutes of walking.');
      suggestions.add(
        'Because the route has a long walking segment, connect the weather risk to the route.',
      );
    }

    return WeatherActionRisks(
      bringUmbrella: bringUmbrella,
      eveningRainRisk: nightRain,
      temperatureDropRisk: temperatureDropRisk,
      windRisk: windRisk,
      heatRisk: heatRisk,
      coldRisk: coldRisk,
      longWalkExposureRisk: longWalkExposureRisk,
      uvRiskAvailable: false,
      reasons: reasons,
      suggestions: suggestions,
    );
  }

  Map<String, dynamic> toJson() => {
        'bring_umbrella': bringUmbrella,
        'evening_rain_risk': eveningRainRisk,
        'temperature_drop_risk': temperatureDropRisk,
        'wind_risk': windRisk,
        'heat_risk': heatRisk,
        'cold_risk': coldRisk,
        'long_walk_exposure_risk': longWalkExposureRisk,
        'uv_risk_available': uvRiskAvailable,
        'reasons': reasons,
        'suggestions': suggestions,
      };

  static bool _hasPrecipitation(String value) {
    final text = value.toLowerCase();
    return text.contains('雨') ||
        text.contains('雪') ||
        text.contains('雷阵雨') ||
        text.contains('rain') ||
        text.contains('snow') ||
        text.contains('shower');
  }

  static bool _windPowerRisk(String value) {
    final numbers = RegExp(r'\d+')
        .allMatches(value)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .toList(growable: false);
    if (numbers.isEmpty) return false;
    return numbers.reduce((a, b) => a > b ? a : b) >= 4;
  }
}

class WeatherDailyForecast {
  const WeatherDailyForecast({
    required this.date,
    required this.week,
    required this.dayWeather,
    required this.nightWeather,
    required this.dayTemp,
    required this.nightTemp,
    required this.dayWind,
    required this.nightWind,
    required this.dayPower,
    required this.nightPower,
  });

  final String date;
  final String week;
  final String dayWeather;
  final String nightWeather;
  final String dayTemp;
  final String nightTemp;
  final String dayWind;
  final String nightWind;
  final String dayPower;
  final String nightPower;

  int? get dayTempC => _parseTemperature(dayTemp);
  int? get nightTempC => _parseTemperature(nightTemp);

  factory WeatherDailyForecast.fromAmap(Map<String, dynamic> json) {
    return WeatherDailyForecast(
      date: _string(json['date']) ?? '',
      week: _string(json['week']) ?? '',
      dayWeather: _string(json['dayweather']) ?? '',
      nightWeather: _string(json['nightweather']) ?? '',
      dayTemp: _string(json['daytemp']) ?? '',
      nightTemp: _string(json['nighttemp']) ?? '',
      dayWind: _string(json['daywind']) ?? '',
      nightWind: _string(json['nightwind']) ?? '',
      dayPower: _string(json['daypower']) ?? '',
      nightPower: _string(json['nightpower']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'week': week,
        'day_weather': dayWeather,
        'night_weather': nightWeather,
        'day_temp_c': dayTemp,
        'night_temp_c': nightTemp,
        'day_wind': dayWind,
        'night_wind': nightWind,
        'day_power': dayPower,
        'night_power': nightPower,
      };

  static String? _string(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) return _string(value.first);
    return null;
  }

  static int? _parseTemperature(String value) {
    final match = RegExp(r'-?\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '');
  }
}

class _AmapWeatherForecast {
  const _AmapWeatherForecast({
    required this.city,
    required this.adcode,
    required this.reportTime,
    required this.casts,
  });

  final String city;
  final String adcode;
  final DateTime? reportTime;
  final List<WeatherDailyForecast> casts;
}

class _AmapResolvedCity {
  const _AmapResolvedCity({required this.name, required this.adcode});

  final String name;
  final String adcode;
}
