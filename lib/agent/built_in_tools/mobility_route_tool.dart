import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/mobility_route_planning_service.dart';

Tool buildMobilityRoutePlanTool({MobilityRoutePlanningService? service}) {
  final routeService = service ?? MobilityRoutePlanningService.instance;
  return Tool(
    name: 'MobilityRoutePlan',
    description:
        '''Plan a practical door-to-door public transit route using Amap.

Use when the user asks how to get from one real place to another: building,
community, station, landmark, address, or remembered place. This plans the route
only; it does not start an active follow-up session. If the user wants you to
watch stops/transfers during the trip, use TransitPlanStart after or instead.''',
    parameters: {
      'type': 'object',
      'properties': {
        'origin': {
          'type': 'string',
          'description':
              'Origin building, community, station, landmark, address, or coordinates.',
        },
        'destination': {
          'type': 'string',
          'description':
              'Destination building, community, station, landmark, address, or coordinates.',
        },
        'city': {
          'type': 'string',
          'description':
              'Transit city, e.g. 北京 or 上海. Optional if current location can infer it.',
        },
        'destination_city': {
          'type': 'string',
          'description':
              'Destination city for cross-city routes, if different.',
        },
      },
      'required': ['origin', 'destination'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final result = await routeService.planTransitRoute(
          origin: _requiredString(args, 'origin'),
          destination: _requiredString(args, 'destination'),
          city: _string(args['city']),
          destinationCity: _string(args['destination_city']),
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

String _requiredString(Map<String, dynamic> args, String key) {
  final value = _string(args[key]);
  if (value == null) {
    throw FormatException('Missing required field: $key');
  }
  return value;
}
