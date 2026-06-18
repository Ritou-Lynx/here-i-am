import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/services/phone_usage_service.dart';

Tool buildPhoneUsageQueryTool({
  PhoneUsageService? service,
}) {
  final usageService = service ?? PhoneUsageService.instance;
  return Tool(
    name: 'PhoneUsageQuery',
    description: '''Query the user's local Android app usage summary.

Use this when recent phone activity matters: the user asks about phone usage,
screen time, doomscrolling, "what was I doing just now", whether they are stuck
in an app, which apps took the most time, or when late-night support depends on
knowing whether they were still using distracting apps. This reads local Android
Usage Access data only. If permission is missing, explain that Android Usage
Access must be enabled for Here I am in system settings.''',
    parameters: {
      'type': 'object',
      'properties': {
        'range': {
          'type': 'string',
          'enum': ['today', 'yesterday', 'seven_days'],
          'description': 'Time window to query. Defaults to today.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of apps to return. Defaults to 10.',
        },
      },
      'required': [],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      final range = (args['range'] as String?) ?? 'today';
      final limit = _coerceLimit(args['limit']);
      if (!usageService.isSupported) {
        return jsonEncode({
          'success': false,
          'reason': 'unsupported_platform',
        });
      }

      final granted = await usageService.isUsageAccessGranted();
      if (!granted) {
        return jsonEncode({
          'success': false,
          'reason': 'permission_required',
        });
      }

      try {
        final window = _windowFor(range);
        final snapshot = await usageService.loadRange(
          startTime: window.$1,
          endTime: window.$2,
          limit: limit,
        );
        return jsonEncode({
          'success': true,
          'range': range,
          'start_time': snapshot.startTime.toIso8601String(),
          'end_time': snapshot.endTime.toIso8601String(),
          'total_minutes': snapshot.totalTime.inMinutes,
          'apps': snapshot.records
              .map((record) => {
                    'app_name': record.appName,
                    'package_name': record.packageName,
                    'minutes': record.totalTime.inMinutes,
                    if (record.lastUsedAt != null)
                      'last_used_at': record.lastUsedAt!.toIso8601String(),
                  })
              .toList(),
        });
      } on PlatformException catch (e) {
        return jsonEncode({
          'success': false,
          'reason': e.code == 'PERMISSION_DENIED'
              ? 'permission_required'
              : 'query_failed',
          'error': e.message,
        });
      } catch (e) {
        return jsonEncode({
          'success': false,
          'reason': 'query_failed',
          'error': e.toString(),
        });
      }
    },
  );
}

(DateTime, DateTime) _windowFor(String range) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  return switch (range) {
    'yesterday' => (
        todayStart.subtract(const Duration(days: 1)),
        todayStart,
      ),
    'seven_days' => (
        todayStart.subtract(const Duration(days: 6)),
        now,
      ),
    _ => (todayStart, now),
  };
}

int _coerceLimit(Object? raw) {
  if (raw is num) return raw.toInt().clamp(1, 30);
  return 10;
}
