import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Reserved patch field names managed by [DomainSchemaValidator].
/// These are promoted to projection columns and must not enter [stateJson].
const _reservedPatchFields = {
  '_occurredAt',
  '_occurredEndAt',
  '_timeConfidence',
  '_timeSourceText',
  '_primaryDomain',
  '_facets',
  '_valence',
  '_arousal',
  '_schemaVersion',
};

class SharedLifeOperationDraft {
  const SharedLifeOperationDraft({
    required this.operationType,
    required this.entityType,
    required this.title,
    required this.patch,
    this.sourceKind = 'chat_message',
    this.sourceRef,
    this.rawInput,
    this.sourceMessageIds = const [],
    this.entityId,
  });

  final String operationType;
  final String entityType;
  final String title;
  final Map<String, dynamic> patch;

  /// Evidence source kind. Any non-null value allows the operation through.
  /// Supported values: chat_message / floating_ball / screenshot_ocr /
  /// health_import / manual_edit / record_button / external_share
  final String sourceKind;

  /// Generic reference ID for the source (message id, file path, batch id…)
  final String? sourceRef;

  /// Raw user input verbatim, preserved for audit.
  final String? rawInput;

  /// Legacy: chat message IDs validated against [allowedSourceMessageIds].
  /// Only checked when [sourceKind] == 'chat_message'.
  final List<int> sourceMessageIds;

  final String? entityId;
}

class SharedLifeApplyResult {
  const SharedLifeApplyResult({
    required this.operationIds,
    required this.entityIds,
    required this.entityTitles,
  });

  final List<String> operationIds;
  final List<String> entityIds;
  final List<String> entityTitles;

  bool get isEmpty => operationIds.isEmpty;
}

class SharedLifeEntitySnapshot {
  const SharedLifeEntitySnapshot({
    required this.id,
    required this.entityType,
    required this.title,
    required this.status,
    required this.state,
    required this.updatedAt,
    this.primaryDomain = 'general',
    this.facets = const [],
    this.occurredAt,
    this.occurredEndAt,
    this.valence,
    this.arousal,
    this.schemaVersion = 1,
  });

  final String id;
  final String entityType;
  final String title;
  final String status;
  final Map<String, dynamic> state;
  final int updatedAt;

  final String primaryDomain;
  final List<String> facets;
  final int? occurredAt;
  final int? occurredEndAt;
  final double? valence;
  final double? arousal;
  final int schemaVersion;

  List<String> get tags => _stringList(state['tags']);

  List<String> get relatedEntityIds => _stringList(state['related_entity_ids']);

  List<String> get relatedFactIds => _stringList(state['related_fact_ids']);

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_type': entityType,
        'title': title,
        'status': status,
        'primary_domain': primaryDomain,
        'facets': facets,
        'occurred_at': occurredAt,
        'occurred_end_at': occurredEndAt,
        'valence': valence,
        'arousal': arousal,
        'schema_version': schemaVersion,
        'tags': tags,
        'state': state,
        'updated_at': updatedAt,
      };
}

class SharedLifeEntityDetail {
  const SharedLifeEntityDetail({
    required this.entity,
    required this.operations,
    required this.sourceMessages,
  });

  final SharedLifeEntitySnapshot entity;
  final List<SharedLifeEventOperation> operations;
  final List<PersonaChatMessage> sourceMessages;
}

/// Shared life memory storage for the companion-first product.
///
/// This service deliberately has no dependency on legacy Memex cards. It owns
/// an append-only operation log and a rebuildable current-state projection.
class SharedLifeMemoryService {
  SharedLifeMemoryService(this.db);

  final AppDatabase db;
  final _logger = getLogger('SharedLifeMemoryService');
  String? _userId;

  /// Attach the current user ID so the service can publish data-change events
  /// for FTS indexing. Safe to call multiple times (e.g. after re-login).
  void attachUserId(String userId) {
    _userId = userId;
  }

  Future<List<SharedLifeEntitySnapshot>> queryRelevantEntities(
    String text, {
    int limit = 12,
    bool includeCancelled = false,
    String? domain,
    int? occurredAfter,
    int? occurredBefore,
    String? entityType,
  }) async {
    final query = db.select(db.sharedLifeEntities);
    if (!includeCancelled) {
      query.where((t) => t.status.isNotIn(const ['cancelled']));
    }
    if (domain != null) {
      query.where((t) =>
          t.primaryDomain.equals(domain) |
          t.facets.like('%"$domain"%'));
    }
    if (occurredAfter != null) {
      query.where((t) =>
          t.occurredAt.isNull() | t.occurredAt.isBiggerOrEqualValue(occurredAfter));
    }
    if (occurredBefore != null) {
      query.where((t) =>
          t.occurredAt.isNull() | t.occurredAt.isSmallerOrEqualValue(occurredBefore));
    }
    if (entityType != null) {
      query.where((t) => t.entityType.equals(entityType));
    }
    // For schedule/task queries, sort by event time asc (soonest first);
    // otherwise sort by most recently updated.
    final timeAscMode = entityType == 'schedule' || entityType == 'task' ||
        domain == 'schedule' || domain == 'task';
    if (timeAscMode) {
      query.orderBy([
        (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.asc,
            nulls: NullsOrder.last),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    } else {
      query.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    }
    query.limit(200);
    final rows = await query.get();
    final terms = _searchTerms(text);
    final ranked = rows
        .map((row) {
          final haystack =
              '${row.title}\n${row.entityType}\n${row.stateJson}'.toLowerCase();
          final score = terms.where(haystack.contains).length;
          return (row: row, score: score);
        })
        .where((entry) => terms.isEmpty || entry.score > 0)
        .toList()
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        // Preserve domain-aware secondary order from the DB query
        if (timeAscMode) {
          final aTime = a.row.occurredAt;
          final bTime = b.row.occurredAt;
          if (aTime != null && bTime != null) return aTime.compareTo(bTime);
          if (aTime != null) return -1;
          if (bTime != null) return 1;
        }
        return b.row.updatedAt.compareTo(a.row.updatedAt);
      });

    final selected = ranked.isEmpty && terms.isNotEmpty
        ? rows.take(limit)
        : ranked.take(limit).map((entry) => entry.row);
    return selected.map(_snapshotFromRow).toList(growable: false);
  }

  Future<List<SharedLifeEntitySnapshot>> listEntities({int limit = 50}) async {
    final rows = await (db.select(db.sharedLifeEntities)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(limit))
        .get();
    return rows.map(_snapshotFromRow).toList(growable: false);
  }

  Future<SharedLifeEntityDetail?> getEntityDetail(String entityId) async {
    final entityRow = await (db.select(db.sharedLifeEntities)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    if (entityRow == null) return null;

    final operations = await (db.select(db.sharedLifeEventOperations)
          ..where((t) => t.entityId.equals(entityId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final sourceMessageIds = operations
        .expand((op) => _decodeIntList(op.sourceMessageIds))
        .toSet()
        .toList()
      ..sort();
    final sourceMessages = sourceMessageIds.isEmpty
        ? const <PersonaChatMessage>[]
        : await (db.select(db.personaChatMessages)
              ..where((t) => t.id.isIn(sourceMessageIds))
              ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
            .get();

    return SharedLifeEntityDetail(
      entity: _snapshotFromRow(entityRow),
      operations: operations,
      sourceMessages: sourceMessages,
    );
  }

  /// Apply a list of operation drafts to the event log and rebuild projections.
  ///
  /// Evidence gating:
  /// - When [draft.sourceKind] == 'chat_message', the draft's [sourceMessageIds]
  ///   are filtered against [allowedSourceMessageIds]; empty result is still
  ///   accepted (the sourceKind itself is evidence enough).
  /// - Any other [sourceKind] bypasses the message-ID check entirely.
  Future<SharedLifeApplyResult> applyOperations({
    required String sourceCharacterId,
    required String? captureTaskId,
    required List<SharedLifeOperationDraft> operations,
    Set<int> allowedSourceMessageIds = const {},
  }) async {
    final operationIds = <String>[];
    final entityIds = <String>[];
    final titles = <String>{};

    await db.transaction(() async {
      for (final draft in operations) {
        final normalizedType = draft.operationType.trim().toLowerCase();
        if (!_supportedCaptureOperations.contains(normalizedType)) {
          _logger
              .warning('Ignored unsupported shared operation: $normalizedType');
          continue;
        }
        final entityType = draft.entityType.trim().toLowerCase();
        if (!_supportedEntityTypes.contains(entityType)) {
          _logger
              .warning('Ignored unsupported shared entity type: $entityType');
          continue;
        }

        // Determine validated source message IDs for back-compat storage
        final sourceIds = draft.sourceKind == 'chat_message'
            ? (draft.sourceMessageIds
                .where(allowedSourceMessageIds.contains)
                .toSet()
                .toList()
              ..sort())
            : <int>[];

        final existingEntity = draft.entityId == null
            ? null
            : await (db.select(db.sharedLifeEntities)
                  ..where((t) => t.id.equals(draft.entityId!)))
                .getSingleOrNull();
        final createsEntity =
            normalizedType == 'create' || normalizedType == 'derive';
        if (!createsEntity && existingEntity == null) {
          _logger.warning(
              'Ignored $normalizedType for missing entity ${draft.entityId}');
          continue;
        }

        final entityId = createsEntity ? _uuid.v4() : existingEntity!.id;
        final operationId = _uuid.v4();
        final title = draft.title.trim().isNotEmpty
            ? draft.title.trim()
            : existingEntity?.title ?? draft.entityType.trim();
        final now = DateTime.now().microsecondsSinceEpoch;

        // Extract domain from patch reserved fields
        final primaryDomain = draft.patch['_primaryDomain'] as String? ??
            existingEntity?.primaryDomain ??
            'general';
        final facetsRaw = draft.patch['_facets'];
        final facets = facetsRaw is List
            ? jsonEncode(facetsRaw)
            : (facetsRaw as String?);

        await db.into(db.sharedLifeEventOperations).insert(
              SharedLifeEventOperationsCompanion.insert(
                id: operationId,
                entityId: entityId,
                operationType: normalizedType,
                entityType: entityType,
                title: title,
                patchJson: jsonEncode(draft.patch),
                sourceMessageIds: jsonEncode(sourceIds),
                sourceCharacterId: sourceCharacterId,
                captureTaskId: Value(captureTaskId),
                revertsOperationId: const Value(null),
                createdAt: now,
                sourceKind: Value(draft.sourceKind),
                sourceRef: Value(draft.sourceRef),
                rawInput: Value(draft.rawInput),
                primaryDomain: Value(primaryDomain),
                facets: Value(facets),
              ),
            );
        await _rebuildEntity(entityId);
        operationIds.add(operationId);
        entityIds.add(entityId);
        titles.add(title);
      }
    });

    return SharedLifeApplyResult(
      operationIds: operationIds,
      entityIds: entityIds,
      entityTitles: titles.toList(growable: false),
    );
  }

  Future<SharedLifeApplyResult> applyManualOperation({
    required String sourceCharacterId,
    required int sourceMessageId,
    required SharedLifeOperationDraft operation,
  }) {
    return applyOperations(
      sourceCharacterId: sourceCharacterId,
      captureTaskId: null,
      operations: [operation],
      allowedSourceMessageIds: {sourceMessageId},
    );
  }

  /// Apply an operation directly without a chat message (e.g. UI edit, floating ball).
  Future<SharedLifeApplyResult> applyDirectOperation({
    required String sourceCharacterId,
    required SharedLifeOperationDraft operation,
  }) {
    return applyDirectOperations(
      sourceCharacterId: sourceCharacterId,
      operations: [operation],
    );
  }

  /// Apply multiple operations directly (e.g. RecordOrganizerService batch).
  Future<SharedLifeApplyResult> applyDirectOperations({
    required String sourceCharacterId,
    required List<SharedLifeOperationDraft> operations,
  }) {
    return applyOperations(
      sourceCharacterId: sourceCharacterId,
      captureTaskId: null,
      operations: operations,
    );
  }

  Future<bool> undoLatestEntityOperation({
    required String entityId,
    required String sourceCharacterId,
    required int sourceMessageId,
  }) async {
    final rows = await (db.select(db.sharedLifeEventOperations)
          ..where((t) => t.entityId.equals(entityId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    final revertedIds =
        rows.map((row) => row.revertsOperationId).whereType<String>().toSet();
    for (final row in rows) {
      if (row.operationType == 'undo' || revertedIds.contains(row.id)) {
        continue;
      }
      await undoOperations(
        [row.id],
        sourceCharacterId: sourceCharacterId,
        sourceMessageIds: [sourceMessageId],
      );
      return true;
    }
    return false;
  }

  /// Fully delete an entity by undoing every one of its still-active operations.
  Future<bool> fullyDeleteEntity({
    required String entityId,
    required String sourceCharacterId,
    int? sourceMessageId,
  }) async {
    final activeRows = await _activeRowsForEntity(entityId);
    if (activeRows.isEmpty) return false;
    final idsNewestFirst = activeRows.reversed.map((r) => r.id).toList();
    await undoOperations(
      idsNewestFirst,
      sourceCharacterId: sourceCharacterId,
      sourceMessageIds: sourceMessageId != null ? [sourceMessageId] : [],
    );
    return true;
  }

  Future<void> undoOperations(
    List<String> operationIds, {
    String? sourceCharacterId,
    List<int>? sourceMessageIds,
  }) async {
    if (operationIds.isEmpty) return;
    await db.transaction(() async {
      final rows = await (db.select(db.sharedLifeEventOperations)
            ..where((t) => t.id.isIn(operationIds)))
          .get();
      for (final row in rows) {
        final alreadyUndone = await (db.select(db.sharedLifeEventOperations)
              ..where((t) => t.revertsOperationId.equals(row.id)))
            .getSingleOrNull();
        if (alreadyUndone != null) continue;
        final now = DateTime.now().microsecondsSinceEpoch;
        await db.into(db.sharedLifeEventOperations).insert(
              SharedLifeEventOperationsCompanion.insert(
                id: _uuid.v4(),
                entityId: row.entityId,
                operationType: 'undo',
                entityType: row.entityType,
                title: row.title,
                patchJson: '{}',
                sourceMessageIds: sourceMessageIds == null
                    ? row.sourceMessageIds
                    : jsonEncode(sourceMessageIds),
                sourceCharacterId: sourceCharacterId ?? row.sourceCharacterId,
                revertsOperationId: Value(row.id),
                createdAt: now,
              ),
            );
        await _rebuildEntity(row.entityId);
      }
    });
  }

  /// Repairs projections where a create operation was undone but update ops survived.
  Future<int> repairOrphanedEntities() async {
    final rows = await db.select(db.sharedLifeEntities).get();
    var repaired = 0;
    for (final row in rows) {
      final activeRows = await _activeRowsForEntity(row.id);
      if (activeRows.any(_createsEntity)) continue;
      await _rebuildEntity(row.id);
      repaired++;
    }
    if (repaired > 0) {
      _logger.info('Removed $repaired orphaned shared life projection(s)');
    }
    return repaired;
  }

  /// Keeps SharedLife tags aligned with the known tag vocabulary.
  Future<int> repairTagsAgainstKnownTags(List<String> knownTags) async {
    final canonicalTags = <String, String>{
      for (final tag in knownTags)
        if (tag.trim().isNotEmpty) tag.trim().toLowerCase(): tag.trim(),
    };
    final rows = await db.select(db.sharedLifeEntities).get();
    var repaired = 0;

    await db.transaction(() async {
      for (final row in rows) {
        final state = _decodeMap(row.stateJson);
        final currentTags = _stringList(state['tags']);
        final filteredTags = currentTags
            .map((tag) => canonicalTags[tag.toLowerCase()])
            .whereType<String>()
            .toSet()
            .toList(growable: false);
        if (_sameStringList(currentTags, filteredTags)) continue;

        final now = DateTime.now().microsecondsSinceEpoch;
        await db.into(db.sharedLifeEventOperations).insert(
              SharedLifeEventOperationsCompanion.insert(
                id: _uuid.v4(),
                entityId: row.id,
                operationType: 'correct',
                entityType: row.entityType,
                title: row.title,
                patchJson: jsonEncode({'tags': filteredTags}),
                sourceMessageIds: '[]',
                sourceCharacterId: row.sourceCharacterId,
                createdAt: now,
              ),
            );
        await _rebuildEntity(row.id);
        repaired++;
      }
    });

    if (repaired > 0) {
      _logger.info('Repaired tags for $repaired shared life record(s)');
    }
    return repaired;
  }

  Future<void> _rebuildEntity(String entityId) async {
    final activeRows = await _activeRowsForEntity(entityId);
    final originIndex = activeRows.indexWhere(_createsEntity);
    if (originIndex < 0) {
      await (db.delete(db.sharedLifeEntities)
            ..where((t) => t.id.equals(entityId)))
          .go();
      _publishEntityChange(entityId, DataChangeOp.delete);
      return;
    }
    final projectionRows = activeRows.sublist(originIndex);

    final first = projectionRows.first;
    var title = first.title;
    var status = 'active';
    final state = <String, dynamic>{};

    // Promoted columns — accumulated across patches
    String primaryDomain = 'general';
    String? facets;
    int? occurredAt;
    int? occurredEndAt;
    double? valence;
    double? arousal;
    int schemaVersion = 1;

    for (final row in projectionRows) {
      title = row.title.trim().isEmpty ? title : row.title;
      final patch = _decodeMap(row.patchJson);

      // Extract reserved fields before merging into state
      final reserved = _extractReservedFields(patch);
      if (reserved['_primaryDomain'] case final String d) primaryDomain = d;
      if (reserved['_facets'] case final String f) facets = f;
      if (reserved['_occurredAt'] case final int ts) occurredAt = ts;
      if (reserved['_occurredEndAt'] case final int ts) occurredEndAt = ts;
      if (reserved['_valence'] case final double v) valence = v;
      if (reserved['_arousal'] case final double v) arousal = v;
      if (reserved['_schemaVersion'] case final int v) schemaVersion = v;

      // domain columns on the operation row take precedence if set
      if (row.primaryDomain != 'general') primaryDomain = row.primaryDomain;
      if (row.facets != null) facets = row.facets;

      switch (row.operationType) {
        case 'append':
          _appendPatch(state, patch);
        case 'complete':
          _mergePatch(state, patch);
          status = 'completed';
        case 'cancel':
          _mergePatch(state, patch);
          status = 'cancelled';
        default:
          _mergePatch(state, patch);
      }
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    final wasNew = await (db.select(db.sharedLifeEntities)
              ..where((t) => t.id.equals(entityId)))
            .getSingleOrNull() ==
        null;
    await db.into(db.sharedLifeEntities).insertOnConflictUpdate(
          SharedLifeEntitiesCompanion.insert(
            id: entityId,
            entityType: projectionRows.last.entityType,
            title: title,
            stateJson: jsonEncode(state),
            status: Value(status),
            sourceCharacterId: projectionRows.last.sourceCharacterId,
            lastOperationId: projectionRows.last.id,
            createdAt: first.createdAt,
            updatedAt: now,
            primaryDomain: Value(primaryDomain),
            facets: Value(facets),
            occurredAt: Value(occurredAt),
            occurredEndAt: Value(occurredEndAt),
            valence: Value(valence),
            arousal: Value(arousal),
            schemaVersion: Value(schemaVersion),
          ),
        );
    _publishEntityChange(
      entityId,
      wasNew ? DataChangeOp.insert : DataChangeOp.update,
    );
  }

  void _publishEntityChange(String entityId, DataChangeOp op) {
    final userId = _userId;
    if (userId == null) return;
    GlobalEventBus.instance.publish(
      userId: userId,
      event: SystemEvent<DataChangeRecord>(
        type: SystemEventTypes.dataChanged,
        source: 'shared_life_memory',
        payload: DataChangeRecord(
          op: op,
          ns: DataChangeNs.sharedLifeEntity,
          documentKey: entityId,
        ),
      ),
    );
  }

  Future<List<SharedLifeEventOperation>> _activeRowsForEntity(
      String entityId) async {
    final rows = await (db.select(db.sharedLifeEventOperations)
          ..where((t) => t.entityId.equals(entityId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final revertedIds =
        rows.map((row) => row.revertsOperationId).whereType<String>().toSet();
    return rows
        .where((row) =>
            row.operationType != 'undo' && !revertedIds.contains(row.id))
        .toList(growable: false);
  }

  SharedLifeEntitySnapshot _snapshotFromRow(SharedLifeEntity row) {
    return SharedLifeEntitySnapshot(
      id: row.id,
      entityType: row.entityType,
      title: row.title,
      status: row.status,
      state: _decodeMap(row.stateJson),
      updatedAt: row.updatedAt,
      primaryDomain: row.primaryDomain,
      facets: _stringList(_decodeJsonList(row.facets)),
      occurredAt: row.occurredAt,
      occurredEndAt: row.occurredEndAt,
      valence: row.valence,
      arousal: row.arousal,
      schemaVersion: row.schemaVersion,
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

bool _createsEntity(SharedLifeEventOperation row) =>
    row.operationType == 'create' || row.operationType == 'derive';

const _supportedCaptureOperations = {
  'create',
  'append',
  'update',
  'complete',
  'cancel',
  'correct',
  'derive',
};

const _supportedEntityTypes = {
  'event',
  'task',
  'plan',
  'schedule',
  'fact',
  'reading_item',
};

/// Extracts reserved `_*` fields from a patch, returning a map of promoted values.
/// The patch itself is not mutated here — callers decide how to merge the rest.
Map<String, Object> _extractReservedFields(Map<String, dynamic> patch) {
  final result = <String, Object>{};
  for (final key in _reservedPatchFields) {
    final value = patch[key];
    if (value == null) continue;
    switch (key) {
      case '_primaryDomain':
        if (value is String) result[key] = value;
      case '_facets':
        if (value is List) result[key] = jsonEncode(value);
        if (value is String) result[key] = value;
      case '_occurredAt':
      case '_occurredEndAt':
        if (value is String) {
          final ts = DateTime.tryParse(value)?.microsecondsSinceEpoch;
          if (ts != null) result[key] = ts;
        } else if (value is int) {
          result[key] = value;
        }
      case '_valence':
      case '_arousal':
        if (value is num) result[key] = value.toDouble();
      case '_schemaVersion':
        if (value is int) result[key] = value;
    }
  }
  return result;
}

Set<String> _searchTerms(String text) {
  return RegExp(r'[A-Za-z0-9_一-鿿]{2,}')
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)!)
      .take(16)
      .toSet();
}

Map<String, dynamic> _decodeMap(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

dynamic _decodeJsonList(String? value) {
  if (value == null) return null;
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

List<int> _decodeIntList(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
        .whereType<int>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

bool _sameStringList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _mergePatch(Map<String, dynamic> target, Map<String, dynamic> patch) {
  for (final entry in patch.entries) {
    if (_reservedPatchFields.contains(entry.key)) continue; // never enters state
    final existing = target[entry.key];
    if (entry.value == null) {
      target.remove(entry.key);
    } else if (existing is Map && entry.value is Map) {
      final nested = Map<String, dynamic>.from(existing);
      _mergePatch(nested, Map<String, dynamic>.from(entry.value as Map));
      target[entry.key] = nested;
    } else {
      target[entry.key] = entry.value;
    }
  }
}

void _appendPatch(Map<String, dynamic> target, Map<String, dynamic> patch) {
  for (final entry in patch.entries) {
    if (_reservedPatchFields.contains(entry.key)) continue; // never enters state
    final existing = target[entry.key];
    if (existing is List && entry.value is List) {
      target[entry.key] = [...existing, ...(entry.value as List)];
    } else {
      target[entry.key] = entry.value;
    }
  }
}
