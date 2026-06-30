/// V3 Record Organizer agent.
///
/// Thin orchestrator: assemble prompt context, call LLM, parse JSON into
/// [OrganizedRecord]. See docs/memory-research/MEMORY_PROPOSAL_V3.md § 9.
///
/// Persistence is handled by [RecordOrganizerServiceV3] in
/// services/record_organizer_service.dart. This file is pure analysis.
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/utils/logger.dart';

import '../../models/organized_record.dart';
import 'prompt.dart';

final _logger = getLogger('memory_v3.RecordOrganizerAgent');

class RecordOrganizerAgentV3 {
  const RecordOrganizerAgentV3();

  /// Run the organizer.
  ///
  /// [client] / [modelConfig] are caller-supplied so the user's model
  /// configuration (per V3 § 10.3 — "记忆抽取" function category) decides which
  /// model to use.
  Future<OrganizedRecord> organize({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String rawInput,
    required DateTime now,
    List<String> relevantExistingCardSummaries = const [],
    List<String> recentEntityNames = const [],
    List<Map<String, String>>? inputMedia,
  }) async {
    final userPayload = <String, dynamic>{
      'current_time': now.toIso8601String(),
      'content': rawInput,
    };
    if (inputMedia != null && inputMedia.isNotEmpty) {
      userPayload['media'] = inputMedia;
    }

    final messages = [
      SystemMessage(recordOrganizerSystemPromptV3(
        relevantExistingCardSummaries: relevantExistingCardSummaries,
        recentEntityNames: recentEntityNames,
      )),
      UserMessage([TextPart(jsonEncode(userPayload))]),
    ];
    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 2000,
      extra: modelConfig.extra,
    );

    final firstText =
        (await client.generate(messages, modelConfig: mc)).textOutput;
    if (firstText == null || firstText.trim().isEmpty) {
      throw const FormatException('V3 Record Organizer returned no output');
    }

    try {
      return _parse(firstText);
    } on FormatException catch (e) {
      _logger
          .warning('First parse failed ($e); retrying with hardened reminder');
    }

    final hardenedMessages = [
      SystemMessage(recordOrganizerSystemPromptV3(
        relevantExistingCardSummaries: relevantExistingCardSummaries,
        recentEntityNames: recentEntityNames,
      )),
      UserMessage([
        TextPart(jsonEncode(userPayload)),
        TextPart(
          'STRICT: Reply with ONLY a single JSON object. '
          'No ```json fences, no commentary before or after, no trailing comma. '
          'The first character of your response must be "{".',
        ),
      ]),
    ];
    final retryText =
        (await client.generate(hardenedMessages, modelConfig: mc)).textOutput;
    if (retryText == null || retryText.trim().isEmpty) {
      throw const FormatException(
          'V3 Record Organizer retry returned no output');
    }
    try {
      return _parse(retryText);
    } on FormatException catch (e) {
      _logger.severe('Retry parse also failed. Raw output (first 500): ${retryText.substring(0, retryText.length.clamp(0, 500))}');
      throw FormatException(
          'Record Organizer returned invalid JSON (after retry). '
          'This usually means the model produced malformed JSON. Try a different model.');
    }
  }

  OrganizedRecord _parse(String raw) {
    var trimmed = raw.trim();
    final fenceMatch = RegExp(
      r'^```(?:json|JSON)?\s*\n?([\s\S]*?)\n?```\s*$',
    ).firstMatch(trimmed);
    if (fenceMatch != null) {
      trimmed = fenceMatch.group(1)!.trim();
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException(
          'V3 Record Organizer response contains no JSON');
    }
    var jsonPart = trimmed.substring(start, end + 1);
    jsonPart = _repairLLMJson(jsonPart);
    final decoded = jsonDecode(jsonPart);
    if (decoded is! Map) {
      throw const FormatException(
          'V3 Record Organizer JSON root must be an object');
    }
    return OrganizedRecord.fromJson(decoded.cast<String, dynamic>());
  }

  /// Repair common LLM JSON formatting errors before [jsonDecode].
  ///
  /// Handles: trailing commas (e.g. `"val": 1,}`), empty double commas.
  /// Deliberately limited — complex repairs belong in the hardened retry prompt.
  static String _repairLLMJson(String json) {
    // Remove trailing commas before } or ]
    var repaired = json.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    // Remove empty double commas: ,,
    repaired = repaired.replaceAll(',,', ',');
    return repaired;
  }
}
