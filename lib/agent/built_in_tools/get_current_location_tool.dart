import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/domain/models/location_context_config.dart';

Tool buildGetCurrentLocationTool({LocationContextService? service}) {
  final locationService = service ?? LocationContextService.instance;
  return Tool(
    name: 'GetCurrentLocation',
    description: '''Get the user's current device location with reverse-geocoded address.

Use this when location matters and `current_location_context` is absent, stale,
or silent in your system reminders — e.g. the user asks "到哪了" / "我在哪" /
"你猜我在哪", or you are about to ask where they are but haven't checked first.

Returns status (fresh / stale / unavailable / disabled), coordinates when
available, a granularity-aware location summary, and a reason when unavailable.

Do NOT guess the user's location from time, chat history, or memory. Call this
tool first; only if it returns unavailable/disabled should you ask the user a
short question. Calling this repeatedly within one turn is wasteful — one call
is enough.''',
    parameters: {
      'type': 'object',
      'properties': {
        'force_refresh': {
          'type': 'boolean',
          'description':
              'If true, bypass the cache and force a fresh GPS + reverse geocode lookup. Default false. Use true only when the user explicitly says the cached location is wrong or they just moved.',
        },
      },
      'required': [],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final forceRefresh = args['force_refresh'] is bool
            ? args['force_refresh'] as bool
            : false;
        final context = await locationService.getCurrentContext(
          forceRefresh: forceRefresh,
        );
        return jsonEncode(_contextToJson(context));
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

Map<String, dynamic> _contextToJson(CurrentLocationContext context) {
  final address = context.address;
  final summary = address?.summary(context.granularity);
  return {
    'success': context.isFresh,
    'status': context.status,
    'source': context.source,
    'updated_at': context.updatedAt.toIso8601String(),
    if (context.latitude != null)
      'latitude': context.latitude,
    if (context.longitude != null)
      'longitude': context.longitude,
    if (context.accuracyMeters != null)
      'accuracy_meters': context.accuracyMeters,
    if (summary != null && summary.isNotEmpty) 'location_summary': summary,
    if (address?.city != null) 'city': address!.city,
    if (address?.district != null) 'district': address!.district,
    if (address?.neighborhood != null)
      'neighborhood': address!.neighborhood,
    if (address?.street != null) 'street': address!.street,
    if (address?.fullAddress != null)
      'full_address_candidate': address!.fullAddress,
    'granularity': context.granularity.name,
    if (context.reason != null) 'reason': context.reason,
  };
}