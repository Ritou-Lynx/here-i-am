import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/companion_agent/intimate_scene_prompt.dart';
import 'package:memex/agent/companion_agent/intimate_scene_state.dart';
import 'package:memex/utils/logger.dart';

/// Deterministic phrase detection for intimate scene entry/exit signals.
///
/// These gate an autonomous narration run, so the patterns are deliberately
/// conservative and the entry check requires a short, start-anchored message
/// (the user starts the scene with a single short phrase, per requirements
/// §1). The list is the configurable trigger set; extend it when needed.
class IntimateScenePhrases {
  IntimateScenePhrases._();

  static final RegExp _startPattern = RegExp(
    r'^我们开始(?:做爱|吧|了|做吧|好不好|好么)|'
    r'^开始做爱|^来做爱(?:吧|了|么)?$|^做爱吧$|^我们来做爱',
  );

  /// Orgasm signal. Only evaluated while a scene is active, so the surface
  /// for false positives is small.
  static final RegExp _orgasmPattern = RegExp(
    r'高潮了|我到了|我高潮|要去了|不行了|'
    r'到了(?:！|!|~|～)?$|去了(?:！|!|~|～)?$',
  );

  static bool matchesStart(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return _startPattern.hasMatch(t);
  }

  static bool matchesOrgasm(String text) =>
      _orgasmPattern.hasMatch(text.trim());
}

/// Plans an intimate scene into a beat sheet with one LLM call before the
/// first narration turn. Returns null when planning fails; the caller falls
/// back to a plain continuous run so the entry never dead-ends.
class IntimateScenePlanner {
  IntimateScenePlanner._();
  static final _logger = getLogger('IntimateScenePlanner');

  static Future<IntimateScenePlan?> plan({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userText,
    required int totalMessages,
    String profileText = '',
  }) async {
    try {
      final prompt = buildIntimateScenePlanningPrompt(
        userText: userText,
        totalMessages: totalMessages,
        profileText: profileText,
      );
      final res = await client.generate(
        [UserMessage([TextPart(prompt)])],
        modelConfig: modelConfig,
      );
      final text = res.textOutput?.trim() ?? '';
      if (text.isEmpty) return null;
      final decoded = jsonDecode(_extractJson(text));
      if (decoded is! List || decoded.isEmpty) return null;
      final beats = <IntimateSceneBeat>[
        for (final item in decoded)
          if (item is Map)
            IntimateSceneBeat.fromJson(Map<String, dynamic>.from(item)),
      ];
      if (beats.isEmpty) return null;
      return IntimateScenePlan(beats: beats);
    } catch (e) {
      _logger.warning('IntimateScenePlanner: planning failed: $e');
      return null;
    }
  }

  /// Strip markdown fences if the model wrapped the JSON.
  static String _extractJson(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('```')) {
      final first = trimmed.indexOf('\n');
      final last = trimmed.lastIndexOf('```');
      if (first >= 0 && last > first) {
        return trimmed.substring(first + 1, last).trim();
      }
    }
    return trimmed;
  }
}
