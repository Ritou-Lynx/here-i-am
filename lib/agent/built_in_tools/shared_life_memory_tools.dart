import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';

List<Tool> buildSharedLifeMemoryTools({
  required SharedLifeMemoryService service,
  required String sourceCharacterId,
  String? userId,
  List<String>? knownTags,
  int? sourceMessageId,
}) {
  final tools = <Tool>[
    _buildQueryTool(service),
  ];
  if (sourceMessageId == null) return tools;

  tools.addAll([
    _buildCreateTool(
      service: service,
      sourceCharacterId: sourceCharacterId,
      userId: userId,
      knownTags: knownTags,
      sourceMessageId: sourceMessageId,
    ),
    _buildChangeTool(
      service: service,
      sourceCharacterId: sourceCharacterId,
      userId: userId,
      knownTags: knownTags,
      sourceMessageId: sourceMessageId,
      operationType: 'update',
      toolName: 'LifeMemoryUpdate',
      description:
          'Update an existing shared life record when the user explicitly corrects or adds information.',
    ),
    _buildChangeTool(
      service: service,
      sourceCharacterId: sourceCharacterId,
      userId: userId,
      knownTags: knownTags,
      sourceMessageId: sourceMessageId,
      operationType: 'complete',
      toolName: 'LifeMemoryComplete',
      description:
          'Mark an existing shared task, plan, schedule, or event as completed when the user explicitly says it is done.',
    ),
    _buildChangeTool(
      service: service,
      sourceCharacterId: sourceCharacterId,
      userId: userId,
      knownTags: knownTags,
      sourceMessageId: sourceMessageId,
      operationType: 'cancel',
      toolName: 'LifeMemoryCancel',
      description:
          'Cancel an existing shared life record without deleting its history when the user explicitly asks to cancel it.',
    ),
    _buildUndoTool(
      service: service,
      sourceCharacterId: sourceCharacterId,
      sourceMessageId: sourceMessageId,
    ),
  ]);
  return tools;
}

Tool _buildQueryTool(SharedLifeMemoryService service) {
  return Tool(
    name: 'LifeMemoryQuery',
    description: '''Query the user's shared life records.

Use this before answering questions about recorded events, tasks, plans,
schedules, or durable facts. This store is separate from character-private
memory. Query first instead of guessing. A blank query returns recent records.''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Keywords or a natural-language question. Omit for recent records.',
        },
        'status': {
          'type': 'string',
          'enum': ['active', 'completed', 'cancelled'],
          'description': 'Optional status filter.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of records to return. Defaults to 12.',
        },
      },
      'required': [],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final text = _string(args['query']);
        final status = _string(args['status']);
        final limit = _limit(args['limit']);
        final entities = text.isEmpty
            ? await service.listEntities(limit: limit)
            : await service.queryRelevantEntities(
                text,
                limit: limit,
                includeCancelled: status == 'cancelled',
              );
        final filtered = status.isEmpty
            ? entities
            : entities.where((entity) => entity.status == status).toList();
        return jsonEncode({
          'success': true,
          'entities': filtered.map((entity) => entity.toJson()).toList(),
        });
      } catch (e) {
        return _error(e);
      }
    },
  );
}

Tool _buildCreateTool({
  required SharedLifeMemoryService service,
  required String sourceCharacterId,
  required String? userId,
  required List<String>? knownTags,
  required int sourceMessageId,
}) {
  return Tool(
    name: 'LifeMemoryCreate',
    description: '''Create a shared life record from the user's current message.

Use this only when the user explicitly asks you to remember or record an
objective event, task, plan, schedule, or durable fact. Do not use it for casual
conversation or character-private relationship memory. Use tags only from the
single user tag list in tags.md; do not invent, translate, or create synonyms.
entity_type describes behavior, not topic taxonomy. Query first when the
request may refer to an existing record, then update instead of creating a
duplicate.''',
    parameters: {
      'type': 'object',
      'properties': {
        'entity_type': {
          'type': 'string',
          'enum': ['event', 'task', 'plan', 'schedule', 'fact'],
        },
        'title': {
          'type': 'string',
          'description': 'Short factual title for the record.',
        },
        'patch': _patchSchema,
        'tags': _tagsSchema,
      },
      'required': ['entity_type', 'title'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        return _apply(
          service: service,
          sourceCharacterId: sourceCharacterId,
          sourceMessageId: sourceMessageId,
          operation: SharedLifeOperationDraft(
            operationType: 'create',
            entityType: _requiredString(args, 'entity_type'),
            title: _requiredString(args, 'title'),
            patch: await _patchWithTags(
              args,
              userId: userId,
              knownTags: knownTags,
            ),
            sourceMessageIds: [sourceMessageId],
          ),
        );
      } catch (e) {
        return _error(e);
      }
    },
  );
}

Tool _buildChangeTool({
  required SharedLifeMemoryService service,
  required String sourceCharacterId,
  required String? userId,
  required List<String>? knownTags,
  required int sourceMessageId,
  required String operationType,
  required String toolName,
  required String description,
}) {
  return Tool(
    name: toolName,
    description: '$description Query with `LifeMemoryQuery` first.',
    parameters: {
      'type': 'object',
      'properties': {
        'entity_id': {
          'type': 'string',
          'description': 'Exact shared life entity ID from LifeMemoryQuery.',
        },
        'title': {
          'type': 'string',
          'description': 'Optional corrected short title.',
        },
        'patch': _patchSchema,
        'tags': _tagsSchema,
      },
      'required': ['entity_id'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final entityId = _requiredString(args, 'entity_id');
        final detail = await service.getEntityDetail(entityId);
        if (detail == null) {
          return _error('Shared life record not found: $entityId');
        }
        return _apply(
          service: service,
          sourceCharacterId: sourceCharacterId,
          sourceMessageId: sourceMessageId,
          operation: SharedLifeOperationDraft(
            operationType: operationType,
            entityType: detail.entity.entityType,
            title: _string(args['title']).isEmpty
                ? detail.entity.title
                : _string(args['title']),
            patch: await _patchWithTags(
              args,
              userId: userId,
              knownTags: knownTags,
            ),
            sourceMessageIds: [sourceMessageId],
            entityId: entityId,
          ),
        );
      } catch (e) {
        return _error(e);
      }
    },
  );
}

Tool _buildUndoTool({
  required SharedLifeMemoryService service,
  required String sourceCharacterId,
  required int sourceMessageId,
}) {
  return Tool(
    name: 'LifeMemoryUndo',
    description:
        'Undo the latest active operation for one shared life record when the user explicitly asks to revert it.',
    parameters: {
      'type': 'object',
      'properties': {
        'entity_id': {
          'type': 'string',
          'description': 'Exact shared life entity ID from LifeMemoryQuery.',
        },
      },
      'required': ['entity_id'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final entityId = _requiredString(args, 'entity_id');
        final changed = await service.undoLatestEntityOperation(
          entityId: entityId,
          sourceCharacterId: sourceCharacterId,
          sourceMessageId: sourceMessageId,
        );
        return jsonEncode({'success': changed, 'entity_id': entityId});
      } catch (e) {
        return _error(e);
      }
    },
  );
}

Future<String> _apply({
  required SharedLifeMemoryService service,
  required String sourceCharacterId,
  required int sourceMessageId,
  required SharedLifeOperationDraft operation,
}) async {
  final result = await service.applyManualOperation(
    sourceCharacterId: sourceCharacterId,
    sourceMessageId: sourceMessageId,
    operation: operation,
  );
  if (!result.isEmpty) {
    EventBusService.instance.emitEvent(
      ConversationCaptureRememberedMessage(
        characterId: sourceCharacterId,
        operationIds: result.operationIds,
        entityTitles: result.entityTitles,
      ),
    );
  }
  return jsonEncode({
    'success': !result.isEmpty,
    'operation_ids': result.operationIds,
    'entity_ids': result.entityIds,
    'entity_titles': result.entityTitles,
  });
}

const _patchSchema = {
  'type': 'object',
  'description':
      'Structured factual fields such as summary, time, place, details, related_entity_ids, or related_fact_ids.',
  'additionalProperties': true,
};

const _tagsSchema = {
  'type': 'array',
  'items': {'type': 'string'},
  'description':
      'Optional durable semantic topic labels. Must exactly match tags from tags.md. Do not repeat the entity type, invent new tags, translate tags, or create synonyms.',
};

Future<Map<String, dynamic>> _patchWithTags(
  Map<String, dynamic> args, {
  required String? userId,
  required List<String>? knownTags,
}) async {
  final rawPatch = args['patch'];
  final patch = rawPatch is Map
      ? Map<String, dynamic>.from(rawPatch)
      : <String, dynamic>{};
  if (args.containsKey('tags')) {
    patch['tags'] = (args['tags'] as List<dynamic>? ?? const [])
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }
  return _restrictPatchTagsToKnownTags(
    patch,
    knownTags ?? await _loadKnownTags(userId),
  );
}

Future<List<String>> _loadKnownTags(String? userId) async {
  if (userId == null) return const [];
  final tagsData = await FileSystemService.instance.readTagsFile(userId);
  return tagsData
      .map((tag) => tag['name']?.toString().trim() ?? '')
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic> _restrictPatchTagsToKnownTags(
  Map<String, dynamic> patch,
  List<String> knownTags,
) {
  final canonicalTags = <String, String>{
    for (final tag in knownTags)
      if (tag.trim().isNotEmpty) tag.trim().toLowerCase(): tag.trim(),
  };
  final rawTags = patch['tags'];
  if (rawTags is! List || canonicalTags.isEmpty) {
    patch.remove('tags');
    return patch;
  }

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
  return patch;
}

String _requiredString(Map<String, dynamic> args, String key) {
  final value = _string(args[key]);
  if (value.isEmpty) throw FormatException('Missing required field: $key');
  return value;
}

String _string(dynamic value) => value?.toString().trim() ?? '';

int _limit(dynamic value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return (parsed ?? 12).clamp(1, 50);
}

String _error(Object error) =>
    jsonEncode({'success': false, 'error': error.toString()});
