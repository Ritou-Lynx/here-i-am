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
    _buildDeleteTool(
      service: service,
      sourceCharacterId: sourceCharacterId,
      sourceMessageId: sourceMessageId,
    ),
  ]);
  return tools;
}

Tool _buildDeleteTool({
  required SharedLifeMemoryService service,
  required String sourceCharacterId,
  required int sourceMessageId,
}) {
  return Tool(
    name: 'LifeMemoryDelete',
    description:
        'Permanently delete a shared life record. Use this when the user '
        'explicitly asks to delete / remove / clear / discard a record — '
        'including test data, saved reading items, or notes they no longer '
        'want. This undoes every operation on the entity and removes its '
        'projection row. Prefer this over LifeMemoryUndo when the user '
        'wants the whole record gone, not just the latest change reverted.',
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
        final deleted = await service.fullyDeleteEntity(
          entityId: entityId,
          sourceCharacterId: sourceCharacterId,
          sourceMessageId: sourceMessageId,
        );
        return jsonEncode({'success': deleted, 'entity_id': entityId});
      } catch (e) {
        return _error(e);
      }
    },
  );
}

Tool _buildQueryTool(SharedLifeMemoryService service) {
  return Tool(
    name: 'LifeMemoryQuery',
    description: '''Query the user's shared life records.

Use this before answering questions about recorded events, tasks, plans,
schedules, or durable facts. This store is separate from character-private
memory. Query first instead of guessing. A blank query returns recent records.
Narrow results with domain, entity_type, or time_start/time_end filters.''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Keywords or a natural-language question. Omit for recent records.',
        },
        'domain': {
          'type': 'string',
          'enum': [
            'health',
            'finance',
            'schedule',
            'task',
            'social',
            'interest',
            'clothing',
            'general',
          ],
          'description': 'Filter to a specific life domain.',
        },
        'entity_type': {
          'type': 'string',
          'enum': ['event', 'task', 'plan', 'schedule', 'fact'],
          'description': 'Filter by record type.',
        },
        'time_start': {
          'type': 'string',
          'description':
              'ISO 8601 datetime. Only return records whose event time is on or after this.',
        },
        'time_end': {
          'type': 'string',
          'description':
              'ISO 8601 datetime. Only return records whose event time is on or before this.',
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
        final domain = _string(args['domain']);
        final entityType = _string(args['entity_type']);
        final timeStart = _parseTimestamp(args['time_start']);
        final timeEnd = _parseTimestamp(args['time_end']);
        final limit = _limit(args['limit']);

        final entities = await service.queryRelevantEntities(
          text,
          limit: limit,
          includeCancelled: status == 'cancelled',
          domain: domain.isEmpty ? null : domain,
          entityType: entityType.isEmpty ? null : entityType,
          occurredAfter: timeStart,
          occurredBefore: timeEnd,
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

int? _parseTimestamp(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  final dt = DateTime.tryParse(s);
  return dt?.microsecondsSinceEpoch;
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

ONLY call this tool when the user's current message contains an explicit
record-request phrase such as: "记一下"、"帮我记"、"记录一下"、"保存一下"、
"存一下"、"加到记录里"、"记住这个". Mentioning facts, events, or plans in
ordinary conversation does NOT qualify — do not call this tool in that case.

Do not use for casual conversation or character-private memory. Use tags only
from the user tag list in tags.md; do not invent or translate tags.
Bare URLs, 小红书 links, 微信公众号 links, and generic web links are chat
material by default, not record requests. Create a record for a link only when
the same user message explicitly asks to save/record/remember/add it.
entity_type describes behavior, not topic. Query first if the request may
refer to an existing record, then update instead of creating a duplicate.

Patch reserved fields (prefixed with _) are promoted to columns:
- _primaryDomain: one of health/finance/schedule/task/social/interest/clothing/general
- _facets: list of secondary domains
- _occurredAt: ISO 8601 datetime when the event actually happened
- _valence: -1.0 to 1.0 emotional polarity. Omit when neutral.
- _arousal: 0.0 to 1.0 emotional intensity. Omit when neutral.
- _emotionConfidence: 0.0 to 1.0 your honest confidence in the (_valence,
  _arousal) pair. Weak signals score < 0.4. The UI fades low-confidence halos.
- _emotionEvidence: verbatim source snippet (≤ 60 chars) supporting the coords.
- _timeConfidence: 0.0 to 1.0 confidence in _occurredAt inference.
- _timeSourceText: the verbatim NL fragment that produced _occurredAt
  (e.g. "上周三"). Omit both when _occurredAt is omitted.
- _placeName: verbatim place phrase from the user ("家"/"望京 SOHO"). Omit
  when no place is mentioned. Do not invent.
- _dropletLabel: 2-4 char punchy name for the timeline droplet view
  ("体检"/"搬家"). NOT a tag. Skip when the title is already this short.
- _sourceExcerpts: JSON array of 1-3 verbatim user-quote snippets supporting
  this record. Each ≤ 60 chars. Used for the detail-view evidence panel.
- _structuredFields: JSON object of typed atomic fields useful for queries
  (snake_case keys). E.g. {"amount_cny": 128, "duration_min": 30,
  "distance_km": 5, "with_whom": "妈妈"}. Omit when nothing fits.
- _relatedMemoryIds: JSON array of existing entity IDs this record meaningfully
  continues or references. Use only IDs returned by a prior query_shared_life
  call — never invent IDs. Omit when no clear connection.
- _presentation: REQUIRED. The visible Memory Summary Card payload.
  {
    "title": "optional short title shown above blocks",
    "subjectRef": "optional, e.g. 妈妈 · 通话中",
    "blocks": [
      { "type": "text", "text": "...", "emphases": ["substring"] },
      { "type": "quote", "text": "...", "context": "optional tone note" },
      { "type": "number", "value": "...", "unit": "...", "note": "..." },
      { "type": "table", "rows": [{ "label": "...", "value": "..." }] },
      { "type": "sparkline", "points": [..], "caption": "..." },
      { "type": "progressBar", "value": 5, "max": 10, "unit": "kg", "label": "减肥目标" },
      { "type": "media", "assetPath": "...", "kind": "image|audio|video" },
      { "type": "linkAttachment", "url": "...", "title": "...", "source": "..." }
    ]
  }
  Pick the smallest set of blocks that conveys the essence. Omit empty fields
  rather than fabricating. Use progressBar only when there is a clear target
  ceiling (weight goal, savings target, weekly habit count, reading pages).''',
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
