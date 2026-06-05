import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/conversation_capture_agent/prompt.dart';
import 'package:memex/data/services/conversation_capture_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';

class ConversationCaptureAnalysis {
  const ConversationCaptureAnalysis({
    required this.sharedOperations,
    required this.characterMemoryOperations,
    required this.ignoredMessageIds,
  });

  final List<SharedLifeOperationDraft> sharedOperations;
  final List<Map<String, dynamic>> characterMemoryOperations;
  final List<int> ignoredMessageIds;
}

class ConversationCaptureAnalyzer {
  const ConversationCaptureAnalyzer();

  Future<ConversationCaptureAnalysis> analyze({
    required LLMClient client,
    required ModelConfig modelConfig,
    required ConversationCaptureSlice slice,
    required List<SharedLifeEntitySnapshot> relevantEntities,
    required List<String> knownTags,
  }) async {
    final response = await client.generate(
      [
        SystemMessage(conversationCaptureSystemPrompt(knownTags)),
        UserMessage([
          TextPart(jsonEncode({
            'character_id': slice.characterId,
            'messages': slice.messages
                .map((message) => {
                      'id': message.id,
                      'role': message.isFromCharacter ? 'character' : 'user',
                      'content': message.content,
                      'timestamp': message.timestamp.toIso8601String(),
                    })
                .toList(growable: false),
            'relevant_shared_entities': relevantEntities
                .map((entity) => entity.toJson())
                .toList(growable: false),
          })),
        ]),
      ],
      modelConfig: ModelConfig(
        model: modelConfig.model,
        maxTokens: 1800,
        extra: modelConfig.extra,
      ),
    );
    final text = response.textOutput;
    if (text == null || text.trim().isEmpty) {
      throw const FormatException('Conversation capture returned no JSON');
    }
    return parseConversationCaptureAnalysis(text);
  }
}

ConversationCaptureAnalysis parseConversationCaptureAnalysis(String raw) {
  final decoded = jsonDecode(_extractJsonObject(raw));
  if (decoded is! Map) {
    throw const FormatException(
        'Conversation capture response is not an object');
  }
  final json = Map<String, dynamic>.from(decoded);
  final sharedOperations = _mapList(json['shared_operations'])
      .map((operation) => SharedLifeOperationDraft(
            operationType: operation['operation_type']?.toString() ?? '',
            entityId: _nullableString(operation['entity_id']),
            entityType: operation['entity_type']?.toString() ?? '',
            title: operation['title']?.toString() ?? '',
            patch: operation['patch'] is Map
                ? Map<String, dynamic>.from(operation['patch'] as Map)
                : <String, dynamic>{},
            sourceMessageIds: _intList(operation['source_message_ids']),
          ))
      .toList(growable: false);
  return ConversationCaptureAnalysis(
    sharedOperations: sharedOperations,
    characterMemoryOperations: _mapList(json['character_memory_operations']),
    ignoredMessageIds: _intList(json['ignored_message_ids']),
  );
}

String _extractJsonObject(String raw) {
  final trimmed = raw.trim();
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException(
        'Conversation capture response contains no JSON');
  }
  return trimmed.substring(start, end + 1);
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<int> _intList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
      .whereType<int>()
      .toList(growable: false);
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
