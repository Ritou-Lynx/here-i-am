import 'dart:convert';

import 'package:memex/agent/conversation_capture_agent/conversation_capture_analyzer.dart';
import 'package:memex/data/services/conversation_capture_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('ConversationCaptureHandler');

Future<void> handleConversationCapture(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final characterId = payload['character_id'] as String?;
  final afterMessageId = payload['after_message_id'] as int?;
  final throughMessageId = payload['through_message_id'] as int?;
  if (characterId == null ||
      afterMessageId == null ||
      throughMessageId == null) {
    throw const FormatException('Invalid conversation capture task payload');
  }

  final service = ConversationCaptureService.instance;
  final slice = await service.loadSlice(
    characterId: characterId,
    afterMessageId: afterMessageId,
    throughMessageId: throughMessageId,
  );
  if (slice == null) {
    await service.markSliceExtracted(
      userId: userId,
      characterId: characterId,
      throughMessageId: throughMessageId,
    );
    return;
  }

  final relevantEntities = await service.sharedLifeMemory.queryRelevantEntities(
    slice.combinedText,
  );

  // Read controlled tag vocabulary so the LLM reuses existing tags.
  final tagsData = await FileSystemService.instance.readTagsFile(userId);
  final knownTags = tagsData
      .map((t) => t['name'] as String)
      .where((name) => name.isNotEmpty)
      .toList(growable: false);

  final resources = await UserStorage.getAgentLLMResources(
    AgentDefinitions.conversationCaptureAgent,
    defaultClientKey: LLMConfig.defaultClientKey,
  );
  final analysis = await const ConversationCaptureAnalyzer().analyze(
    client: resources.client,
    modelConfig: resources.modelConfig,
    slice: slice,
    relevantEntities: relevantEntities,
    knownTags: knownTags,
  );
  final applied = await service.sharedLifeMemory.applyOperations(
    sourceCharacterId: characterId,
    captureTaskId: context.taskId,
    operations: service.filterBackgroundOperations(
      slice: slice,
      operations: restrictOperationTagsToKnownTags(
        operations: analysis.sharedOperations,
        knownTags: knownTags,
      ),
    ),
    allowedSourceMessageIds: slice.userMessageIds,
  );
  await service.markSliceExtracted(
    userId: userId,
    characterId: characterId,
    throughMessageId: throughMessageId,
  );
  await LocalTaskExecutor.instance.updateTaskResult(
    context.taskId,
    jsonEncode({
      'operation_ids': applied.operationIds,
      'entity_ids': applied.entityIds,
      'entity_titles': applied.entityTitles,
      'ignored_message_ids': analysis.ignoredMessageIds,
      'character_memory_operation_count':
          analysis.characterMemoryOperations.length,
    }),
  );

  if (!applied.isEmpty) {
    EventBusService.instance.emitEvent(
      ConversationCaptureRememberedMessage(
        characterId: characterId,
        operationIds: applied.operationIds,
        entityTitles: applied.entityTitles,
      ),
    );
  }
}

List<SharedLifeOperationDraft> restrictOperationTagsToKnownTags({
  required List<SharedLifeOperationDraft> operations,
  required List<String> knownTags,
}) {
  final canonicalTags = <String, String>{
    for (final tag in knownTags)
      if (tag.trim().isNotEmpty) tag.trim().toLowerCase(): tag.trim(),
  };

  return operations.map((operation) {
    final patch = Map<String, dynamic>.from(operation.patch);
    final rawTags = patch['tags'];
    if (rawTags is! List || canonicalTags.isEmpty) {
      patch.remove('tags');
    } else {
      final tags = rawTags
          .map((tag) => canonicalTags[tag.toString().trim().toLowerCase()])
          .whereType<String>()
          .toSet()
          .take(3)
          .toList();
      if (tags.isEmpty) {
        patch.remove('tags');
      } else {
        patch['tags'] = tags;
      }
    }

    return SharedLifeOperationDraft(
      operationType: operation.operationType,
      entityId: operation.entityId,
      entityType: operation.entityType,
      title: operation.title,
      patch: patch,
      sourceMessageIds: operation.sourceMessageIds,
    );
  }).toList(growable: false);
}

Future<void> handleConversationCaptureFailure(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
  Object error,
  StackTrace? stackTrace,
) async {
  final characterId = payload['character_id'] as String?;
  final throughMessageId = payload['through_message_id'] as int?;
  if (characterId != null && throughMessageId != null) {
    await ConversationCaptureService.instance.releaseSlice(
      characterId: characterId,
      throughMessageId: throughMessageId,
    );
  }
  _logger.warning(
    'Conversation capture permanently failed for $characterId',
    error,
    stackTrace,
  );
}
