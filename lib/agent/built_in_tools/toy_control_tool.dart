import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/toy_control_service.dart';
import 'package:memex/utils/logger.dart';

Tool buildToyControlTool({required ToyController service}) {
  final log = getLogger('ToyControlTool');
  return Tool(
    name: 'ToyControl',
    description:
        '''Control a connected intimate toy (vibrator, etc.) via Bluetooth.

Call this when the user explicitly wants you to control their toy during roleplay or interactive sessions.

**How to use:**
- ALWAYS write descriptive text in the SAME turn as calling this tool — the text is what the user reads.
- Describe what you are about to do BEFORE stating that you did it.
- Never call this tool without accompanying spoken dialogue.

**Actions:**
- `vibrate`: continuous vibration at a given intensity (0–20 scale). Use durationSeconds > 0 to auto-stop.
- `pattern`: named rhythmic pattern. intensityLevel is the peak (0–20).
  Patterns: steady, wave, pulse, escalate, tease
- `stop`: stop all vibration immediately.

**Intensity guide (0–20):**
- 1–4: barely perceptible, teasing
- 5–8: gentle, steady warmth
- 9–13: noticeable, arousing
- 14–17: strong, insistent
- 18–20: maximum, intense

**Rules:**
- Match intensity to the emotional tone of the moment — start low and escalate.
- Use `pattern` for texture and variety; use `vibrate` for sustained intensity.
- Always `stop` when the scene ends or the user asks to stop.
- Never use this tool without the user's explicit consent or invitation.''',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['vibrate', 'pattern', 'stop'],
          'description': 'What to do.',
        },
        'intensityLevel': {
          'type': 'integer',
          'description':
              'Vibration intensity, 0–20. Required for vibrate and pattern.',
          'minimum': 0,
          'maximum': 20,
        },
        'durationSeconds': {
          'type': 'integer',
          'description':
              'For `vibrate`: how many seconds to run (0 = continuous until next command). Default 0.',
          'minimum': 0,
        },
        'patternName': {
          'type': 'string',
          'enum': ['steady', 'wave', 'pulse', 'escalate', 'tease'],
          'description': 'For `pattern` action: which pattern to play.',
        },
      },
      'required': ['action'],
    },
    executable: (
      String action, [
      int? intensityLevel,
      int? durationSeconds,
      String? patternName,
    ]) async {
      try {
        log.info(
          'ToyControl requested action=$action intensity=$intensityLevel '
          'duration=$durationSeconds pattern=$patternName '
          'controller=${service.runtimeType} ready=${service.isReady}',
        );
        if (!service.isReady) {
          log.warning('ToyControl unavailable: controller is not ready');
          return jsonEncode({
            'ok': false,
            'error':
                'toy controller is not connected; reconnect from chat or settings and try again',
          });
        }
        switch (action) {
          case 'stop':
            final ok = await service.stop();
            log.info('ToyControl stop result ok=$ok');
            return jsonEncode({'ok': ok, 'action': 'stopped'});

          case 'vibrate':
            final level = (intensityLevel ?? 10).clamp(0, 20);
            final dur = durationSeconds ?? 0;
            final ok = await service.vibrate(level, durationSeconds: dur);
            log.info(
              'ToyControl vibrate result ok=$ok intensity=$level '
              'duration=$dur controller=${service.runtimeType}',
            );
            return jsonEncode({
              'ok': ok,
              'action': 'vibrate',
              'intensity': level,
              'durationSeconds': dur,
            });

          case 'pattern':
            final pattern = _parsePattern(patternName ?? 'wave');
            final level = (intensityLevel ?? 10).clamp(0, 20);
            final desc = await service.playPattern(pattern, level);
            final ok = !desc.toLowerCase().contains('failed');
            log.info(
              'ToyControl pattern result pattern=$pattern ok=$ok '
              'intensity=$level description=$desc',
            );
            return jsonEncode({
              'ok': ok,
              'action': 'pattern',
              'description': desc,
            });

          default:
            return jsonEncode(
                {'ok': false, 'error': 'unknown action: $action'});
        }
      } catch (e) {
        log.warning('ToyControl exception: $e');
        return jsonEncode({'ok': false, 'error': e.toString()});
      }
    },
  );
}

ToyPattern _parsePattern(String name) {
  switch (name) {
    case 'steady':
      return ToyPattern.steady;
    case 'wave':
      return ToyPattern.wave;
    case 'pulse':
      return ToyPattern.pulse;
    case 'escalate':
      return ToyPattern.escalate;
    case 'tease':
      return ToyPattern.tease;
    default:
      return ToyPattern.wave;
  }
}
