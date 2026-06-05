import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class SharedLifeOperationDraft {
  const SharedLifeOperationDraft({
    required this.operationType,
    required this.entityType,
    required this.title,
    required this.patch,
    required this.sourceMessageIds,
    this.entityId,
  });

  final String operationType;
  final String entityType;
  final String title;
  final Map<String, dynamic> patch;
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
  });

  final String id;
  final String entityType;
  final String title;
  final String status;
  final Map<String, dynamic> state;
  final int updatedAt;

  List<String> get tags => _stringList(state['tags']);

  List<String> get relatedEntityIds => _stringList(state['related_entity_ids']);

  List<String> get relatedFactIds => _stringList(state['related_fact_ids']);

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_type': entityType,
        'title': title,
        'status': status,
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
  }) async {
    final query = db.select(db.sharedLifeEntities);
    if (!includeCancelled) {
      query.where((t) => t.status.isNotIn(const ['cancelled']));
    }
    query
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(60);
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
        return scoreCompare != 0
            ? scoreCompare
            : b.row.updatedAt.compareTo(a.row.updatedAt);
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
        .expand((operation) => _decodeIntList(operation.sourceMessageIds))
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

  Future<SharedLifeApplyResult> applyOperations({
    required String sourceCharacterId,
    required String? captureTaskId,
    required List<SharedLifeOperationDraft> operations,
    required Set<int> allowedSourceMessageIds,
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
        final sourceIds = draft.sourceMessageIds
            .where(allowedSourceMessageIds.contains)
            .toSet()
            .toList()
          ..sort();
        if (sourceIds.isEmpty) {
          _logger.warning('Ignored shared operation without valid evidence');
          continue;
        }

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
                createdAt: now,
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

  /// Repairs projections written by older builds that allowed an update-like
  /// operation to survive after its originating create operation was undone.
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

  /// Keeps SharedLife tags aligned with the single user tag list (`tags.md`).
  /// Older builds allowed the capture agent to invent localized tags; this
  /// appends correction operations so the event log remains truthful while the
  /// current projection stops exposing out-of-vocabulary labels.
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
    for (final row in projectionRows) {
      title = row.title.trim().isEmpty ? title : row.title;
      final patch = _decodeMap(row.patchJson);
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
    // Fire-and-forget: the event bus publishes to subscribers (FTS index).
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
    final activeRows = rows
        .where((row) =>
            row.operationType != 'undo' && !revertedIds.contains(row.id))
        .toList(growable: false);
    return activeRows;
  }

  SharedLifeEntitySnapshot _snapshotFromRow(SharedLifeEntity row) {
    return SharedLifeEntitySnapshot(
      id: row.id,
      entityType: row.entityType,
      title: row.title,
      status: row.status,
      state: _decodeMap(row.stateJson),
      updatedAt: row.updatedAt,
    );
  }
}

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
};

Set<String> _searchTerms(String text) {
  return RegExp(r'[A-Za-z0-9_\u4e00-\u9fff]{2,}')
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
    final existing = target[entry.key];
    if (existing is List && entry.value is List) {
      target[entry.key] = [...existing, ...(entry.value as List)];
    } else {
      target[entry.key] = entry.value;
    }
  }
}
