import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/device_app_blocker_service.dart';

Tool buildDeviceAppBlockerTool() {
  final service = DeviceAppBlockerService.instance;
  return Tool(
    name: 'device_app_blocker_control',
    description: '''Control the user's authorized device app blocker.

Use this only when:
- the user explicitly asks you to lock or unlock distracting apps,
- the user gives conditional focus-protection authorization such as "if I go
  scroll Xiaohongshu/TikTok pull me back", "stop me if I open short-video
  apps", or "don't let me keep browsing", or
- a late-night sleep-push/system check clearly indicates the user is awake and
  needs help stopping doomscrolling.

This tool does not silently install or enable blocking. It sends a bounded
command to Here I am's own Android Accessibility focus lock. If setup or
Android Accessibility access is missing, the tool returns ok=false and you
should explain that setup is needed in Settings -> Device App Blocker.

Safety:
- Prefer short bounded locks (30-60 minutes) unless the user requested longer.
- Never claim the apps are locked unless this returns ok=true.
- Unlock immediately when the user asks for emergency/disarm/unlock.
- Do not use it for punishment, threats, or unrelated behavior control.''',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['lock', 'unlock', 'status'],
          'description': 'lock distracting apps, unlock them, or read status.',
        },
        'duration_minutes': {
          'type': 'integer',
          'description':
              'Lock duration. Used only for action=lock. Default comes from settings.',
          'minimum': 1,
          'maximum': 720,
        },
        'reason': {
          'type': 'string',
          'description':
              'Short human-readable reason saved locally and sent to the backend.',
        },
      },
      'required': ['action'],
    },
    executable: (
      String action, [
      int? durationMinutes,
      String? reason,
    ]) async {
      try {
        if (action == 'status') {
          return jsonEncode((await service.status()).toJson());
        }
        final result = await service.sendCommand(
          action: action,
          durationMinutes: durationMinutes,
          reason: reason,
          source: 'companion_agent',
        );
        return jsonEncode(result.toJson());
      } catch (e) {
        return jsonEncode({
          'ok': false,
          'action': action,
          'message': e.toString(),
        });
      }
    },
  );
}
