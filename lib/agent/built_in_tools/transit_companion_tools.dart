import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/transit_companion_service.dart';

List<Tool> buildTransitCompanionTools({required String characterId}) {
  final service = TransitCompanionService.instance;
  return [
    _buildStartTool(service: service, characterId: characterId),
    _buildProgressTool(service: service, characterId: characterId),
    _buildEndTool(service: service, characterId: characterId),
  ];
}

Tool _buildStartTool({
  required TransitCompanionService service,
  required String characterId,
}) {
  return Tool(
    name: 'TransitPlanStart',
    description: '''Start a natural-language transit companion session.

Use when the user asks you to accompany a public-transit trip, prevent missed
stops/transfers, or plan "from A to B" by subway/bus. This is invisible to the
user; keep the visible interaction as ordinary chat.

Call this only after you know at least:
- origin station/place
- destination station/place

If city is missing and cannot be inferred from current location, ask the user
for the city first. If the user says "home" or "company", resolve that from
memory first when possible; otherwise ask a short clarification.

After this tool succeeds, tell the user the first leg, the key transfer/get-off
station, and that you will check in on their progress. Call `GetCurrentLocation`
when you need to know where they are along the route; only if it is unavailable
should you ask them directly. Do not say you know their live location unless
they explicitly report it or `GetCurrentLocation` returns a fresh result.''',
    parameters: {
      'type': 'object',
      'properties': {
        'origin': {
          'type': 'string',
          'description': 'Origin station, landmark, address, or coordinates.',
        },
        'destination': {
          'type': 'string',
          'description':
              'Destination station, landmark, address, or coordinates.',
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
        'current_station': {
          'type': 'string',
          'description':
              'Current station if the user already reported it separately.',
        },
      },
      'required': ['origin', 'destination'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final result = await service.startSession(
          characterId: characterId,
          origin: _requiredString(args, 'origin'),
          destination: _requiredString(args, 'destination'),
          city: _string(args['city']),
          destinationCity: _string(args['destination_city']),
          currentStation: _string(args['current_station']),
        );
        return jsonEncode(result.toJson());
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

Tool _buildProgressTool({
  required TransitCompanionService service,
  required String characterId,
}) {
  return Tool(
    name: 'TransitProgressUpdate',
    description:
        '''Update an active transit companion session from the user's natural-language station report.

Use when the user says they arrived at, passed, are near, or are about to reach
a station during an active trip. Extract the station name and call this tool.

Examples:
- "到大钟寺了" -> current_station="大钟寺"
- "快到西直门" -> current_station="西直门"
- "我好像坐过站了，到积水潭了" -> current_station="积水潭", note="user may have overshot"

After this tool succeeds, tell the user the next concrete action: keep riding,
prepare to get off, transfer now, or re-plan if the station does not match.''',
    parameters: {
      'type': 'object',
      'properties': {
        'current_station': {
          'type': 'string',
          'description': 'Station name reported by the user.',
        },
        'note': {
          'type': 'string',
          'description':
              'Optional user wording, especially if they may be off-route.',
        },
      },
      'required': ['current_station'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final result = await service.updateProgress(
          characterId: characterId,
          currentStation: _requiredString(args, 'current_station'),
          note: _string(args['note']),
        );
        return jsonEncode(result.toJson());
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

Tool _buildEndTool({
  required TransitCompanionService service,
  required String characterId,
}) {
  return Tool(
    name: 'TransitPlanEnd',
    description:
        'End the active transit companion session when the user arrives, cancels the trip, or asks you to stop tracking the route.',
    parameters: {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
    executable: (_, __) async {
      final removed = await service.endSession(characterId);
      return jsonEncode({'success': true, 'ended_existing_session': removed});
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
