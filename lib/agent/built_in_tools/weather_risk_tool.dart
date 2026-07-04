import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/weather_risk_service.dart';

Tool buildWeatherOutingRiskTool({WeatherRiskService? service}) {
  final weatherService = service ?? WeatherRiskService.instance;
  return Tool(
    name: 'WeatherOutingRiskCheck',
    description:
        '''Check practical outing weather risks using the configured Amap Web Service key.

Use when weather can affect the user's real action: leaving home, commuting,
going to a destination, deciding whether to take an umbrella, choosing whether
to walk, or reacting to rain/wind/temperature changes. Do not use it just to
recite a full weather forecast.

If the city is unknown, leave city empty and the system will try current
location. If that fails, ask one short question for the city.''',
    parameters: {
      'type': 'object',
      'properties': {
        'city': {
          'type': 'string',
          'description':
              'City, district, destination area, or Amap adcode. Optional if current location can infer it.',
        },
        'walking_minutes': {
          'type': 'integer',
          'description':
              'Approximate outdoor walking time, if known. Use it to assess exposure risk.',
        },
      },
      'required': [],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final result = await weatherService.assessOutingRisk(
          cityOrAdcode: _string(args['city']),
          walkingMinutes: _int(args['walking_minutes']),
        );
        return jsonEncode(result.toJson());
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

String? _string(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
