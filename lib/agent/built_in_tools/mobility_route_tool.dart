import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/mobility_route_planning_service.dart';

Tool buildNearbyPlaceSearchTool({MobilityRoutePlanningService? service}) {
  final routeService = service ?? MobilityRoutePlanningService.instance;
  return Tool(
    name: 'NearbyPlaceSearch',
    description:
        '''Search nearby real-world places from the user's current location using Amap POI nearby search.

Use for requests like "附近找一家螺蛳粉", "最近的商场", "周边有没有咖啡/药店/餐厅",
or when the user asks for a nearby place before planning where to go. Prefer this
over web search for local nearby POI requests. If the user then wants directions,
use `origin_for_route` as the origin and a selected place's `route_destination`
with MobilityRoutePlan.

Do not reveal the user's exact coordinates unless the user explicitly asks.''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Nearby place keyword, such as 螺蛳粉, 商场, 咖啡, 药店, 便利店.',
        },
        'radius_meters': {
          'type': 'integer',
          'description':
              'Search radius in meters. Default 3000. Use 1000-3000 for food, up to 10000 for malls or sparse categories.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of places to return. Default 5.',
        },
        'types': {
          'type': 'string',
          'description':
              'Optional Amap POI type code or type text when known. Usually leave empty.',
        },
      },
      'required': ['query'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final result = await routeService.searchNearbyPlaces(
          query: _requiredString(args, 'query'),
          radiusMeters: _int(args['radius_meters']) ?? 3000,
          limit: _int(args['limit']) ?? 5,
          types: _string(args['types']),
        );
        return jsonEncode(result.toJson());
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

Tool buildMobilityRoutePlanTool({MobilityRoutePlanningService? service}) {
  final routeService = service ?? MobilityRoutePlanningService.instance;
  return Tool(
    name: 'MobilityRoutePlan',
    description:
        '''Plan a practical door-to-door public transit route using Amap.

Use when the user asks how to get from one real place to another: building,
community, station, landmark, address, or remembered place. This plans the route
only; it does not start an active follow-up session. If the user wants you to
watch stops/transfers during the trip, use TransitPlanStart after or instead.
Use assistant_brief, steps, and cautions from the result when answering.''',
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

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
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
