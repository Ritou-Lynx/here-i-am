import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/record_organizer_agent/prompt.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('RecordOrganizerAnalyzer');

class RecordOrganizerAnalysis {
  const RecordOrganizerAnalysis({required this.operations});

  final List<SharedLifeOperationDraft> operations;

  bool get isEmpty => operations.isEmpty;
}

class RecordOrganizerAnalyzer {
  const RecordOrganizerAnalyzer();

  Future<RecordOrganizerAnalysis> analyze({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String rawInput,
    required String sourceKind,
    required List<String> knownTags,
    required List<SharedLifeEntitySnapshot> relevantEntities,
    required DateTime now,
  }) async {
    final entitySummaries = relevantEntities
        .map((e) => '[${e.id}] ${e.entityType}: ${e.title}')
        .toList();

    final messages = [
      SystemMessage(recordOrganizerSystemPrompt(
        knownTags: knownTags,
        relevantEntitySummaries: entitySummaries,
      )),
      UserMessage([
        TextPart(jsonEncode({
          'current_time': now.toIso8601String(),
          'content': rawInput,
        })),
      ]),
    ];
    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 2000,
      extra: modelConfig.extra,
    );

    // First attempt.
    final firstText = (await client.generate(messages, modelConfig: mc))
        .textOutput;
    if (firstText == null || firstText.trim().isEmpty) {
      throw const FormatException('Record organizer returned no output');
    }
    try {
      return _parse(firstText, rawInput: rawInput, sourceKind: sourceKind);
    } on FormatException catch (e) {
      _logger.warning('First parse failed ($e); retrying with hardened reminder');
    }

    // Retry once with a hardened reminder appended. LLMs occasionally emit
    // markdown fences or trailing prose; one nudge usually fixes it.
    final hardenedMessages = [
      SystemMessage(recordOrganizerSystemPrompt(
        knownTags: knownTags,
        relevantEntitySummaries: entitySummaries,
      )),
      UserMessage([
        TextPart(jsonEncode({
          'current_time': now.toIso8601String(),
          'content': rawInput,
        })),
        TextPart(
          'STRICT: Reply with ONLY a single JSON object. '
          'No ```json fences, no commentary before or after, no trailing comma. '
          'The first character of your response must be "{".',
        ),
      ]),
    ];
    final retryText = (await client.generate(hardenedMessages, modelConfig: mc))
        .textOutput;
    if (retryText == null || retryText.trim().isEmpty) {
      throw const FormatException('Record organizer retry returned no output');
    }
    return _parse(retryText, rawInput: rawInput, sourceKind: sourceKind);
  }
}

RecordOrganizerAnalysis _parse(
  String raw, {
  required String rawInput,
  required String sourceKind,
}) {
  // Strip common markdown wrappers before slicing braces. LLMs frequently
  // wrap JSON in ```json … ``` even when told not to.
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
    throw const FormatException('Record organizer response contains no JSON');
  }
  final decoded = jsonDecode(trimmed.substring(start, end + 1));
  if (decoded is! Map) {
    throw const FormatException('Record organizer response is not an object');
  }
  final json = Map<String, dynamic>.from(decoded);
  final rawOps = json['operations'];
  if (rawOps is! List) {
    return const RecordOrganizerAnalysis(operations: []);
  }

  final operations = rawOps
      .whereType<Map>()
      .map((op) {
        final patch = op['patch'] is Map
            ? Map<String, dynamic>.from(op['patch'] as Map)
            : <String, dynamic>{};
        final entityId = _nullableString(op['entity_id']);
        return SharedLifeOperationDraft(
          operationType: op['operation_type']?.toString() ?? 'create',
          entityId: entityId,
          entityType: op['entity_type']?.toString() ?? 'event',
          title: op['title']?.toString() ?? '',
          patch: patch,
          sourceKind: sourceKind,
          rawInput: rawInput,
        );
      })
      .where((op) => op.title.isNotEmpty)
      .toList(growable: false);

  return RecordOrganizerAnalysis(operations: operations);
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
