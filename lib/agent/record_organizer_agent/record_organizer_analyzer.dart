import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/record_organizer_agent/prompt.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';

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

    final response = await client.generate(
      [
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
      ],
      modelConfig: ModelConfig(
        model: modelConfig.model,
        maxTokens: 2000,
        extra: modelConfig.extra,
      ),
    );

    final text = response.textOutput;
    if (text == null || text.trim().isEmpty) {
      throw const FormatException('Record organizer returned no output');
    }
    return _parse(text, rawInput: rawInput, sourceKind: sourceKind);
  }
}

RecordOrganizerAnalysis _parse(
  String raw, {
  required String rawInput,
  required String sourceKind,
}) {
  final trimmed = raw.trim();
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
