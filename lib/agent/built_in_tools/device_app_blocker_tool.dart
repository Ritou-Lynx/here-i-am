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
  needs help stopping doomscrolling, or
- a relationship consequence is appropriate for bedtime/focus enforcement and
  the user has enabled this blocker.

This tool does not silently install or enable blocking. It sends a bounded
command to Here I am's own Android Accessibility focus lock. If setup or
Android Accessibility access is missing, the tool returns ok=false and you
should explain that setup is needed in Settings -> Device App Blocker.

Safety:
- Every lock must be time-bounded. For ordinary focus, prefer 30-60 minutes.
- For late-night sleep enforcement, especially after 02:00, you may use a
  longer lock that lasts until morning, but keep it within 360 minutes.
- Here I am, Android system surfaces, and input methods remain usable while
  the lock is active.
- Never claim the apps are locked unless this returns ok=true.
- Unlock immediately when the user asks for emergency/disarm/unlock.
- Do not use it for unrelated behavior control, open-ended threats, or locks
  without a clear wake-up/unlock horizon.''',
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
              'Lock duration. Used only for action=lock. Default comes from settings. Companion-initiated locks are capped at 360 minutes.',
          'minimum': 1,
          'maximum': 360,
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
