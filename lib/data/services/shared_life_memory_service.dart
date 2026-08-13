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
  '_emotionConfidence',
  '_emotionEvidence',
  '_emotionOverride',
  '_placeName',
  '_placeLat',
  '_placeLng',
  '_dropletLabel',
  '_sourceExcerpts',
  '_structuredFields',
  '_relatedMemoryIds',
  '_schemaVersion',
  '_presentation',
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
    this.sourceSyncIds = const [],
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

  /// Stable cross-device IDs mirroring [sourceMessageIds]. Callers that already
  /// hold the chat rows (record button, floating ball) should pass these
  /// directly; auto-capture leaves them empty and the service resolves them
  /// from [sourceMessageIds] at write time.
  final List<String> sourceSyncIds;

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
    this.emotionConfidence,
    this.emotionEvidence,
    this.emotionOverride,
    this.timeConfidence,
    this.timeSourceText,
    this.placeName,
    this.placeLat,
    this.placeLng,
    this.dropletLabel,
    this.sourceExcerptsJson,
    this.structuredFieldsJson,
    this.relatedMemoryIdsJson,
    this.schemaVersion = 1,
    this.presentationJson,
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

  /// AI confidence in the (valence, arousal) pair, 0..1. Null when AI did not
  /// score the record (treat as low confidence in the UI).
  final double? emotionConfidence;

  /// Raw source snippet supporting the emotion coords. Shown in detail view.
  final String? emotionEvidence;

  /// JSON `{"valence": x, "arousal": y}` of user-corrected coords, or null.
  final String? emotionOverride;

  /// Confidence in [occurredAt] inference, 0..1.
  final double? timeConfidence;

  /// Raw NL fragment that produced [occurredAt] (e.g. "上周三").
  final String? timeSourceText;

  /// Place name as the user said it ("家"/"望京 SOHO"). Optional.
  final String? placeName;

  /// Coordinates if a geocoder/device supplied them. Null when name-only.
  final double? placeLat;
  final double? placeLng;

  /// 2-4 char droplet label shown on the timeline droplet view. Distinct
  /// from [tags]: tags categorize, dropletLabel names this single record.
  final String? dropletLabel;

  /// JSON array of verbatim user-quote snippets supporting this record.
  /// Decode via [sourceExcerpts].
  final String? sourceExcerptsJson;

  /// JSON object of typed atomic fields for cross-record SQL queries.
  /// Decode via [structuredFields].
  final String? structuredFieldsJson;

  /// JSON array of soft-related entity IDs. Decode via [relatedMemoryIds].
  final String? relatedMemoryIdsJson;

  /// Convenience: decoded list of source-excerpt strings.
  List<String> get sourceExcerpts =>
      _stringList(_decodeJsonList(sourceExcerptsJson));

  /// Convenience: decoded structured-fields map.
  Map<String, dynamic> get structuredFields {
    final raw = structuredFieldsJson;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Convenience: decoded list of related entity IDs.
  List<String> get relatedMemoryIds =>
      _stringList(_decodeJsonList(relatedMemoryIdsJson));

  final int schemaVersion;

  /// Effective valence for display: user override (if any) wins over AI coord.
  double? get effectiveValence => _overridePair?.$1 ?? valence;

  /// Effective arousal for display: user override (if any) wins over AI coord.
  double? get effectiveArousal => _overridePair?.$2 ?? arousal;

  /// True when the user has manually corrected the emotion coords.
  bool get emotionOverridden => _overridePair != null;

  (double, double)? get _overridePair {
    final raw = emotionOverride;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final v = decoded['valence'];
      final a = decoded['arousal'];
      if (v is num && a is num) {
        return (v.toDouble().clamp(-1.0, 1.0), a.toDouble().clamp(0.0, 1.0));
      }
    } catch (_) {}
    return null;
  }

  /// Raw PresentationModule JSON. Decode with `PresentationModule.tryParse`.
  /// Null when the record was created before presentation generation existed
  /// or the analyzer chose to omit one.
  final String? presentationJson;

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
        if (emotionConfidence != null) 'emotion_confidence': emotionConfidence,
        if (emotionEvidence != null) 'emotion_evidence': emotionEvidence,
        if (emotionOverride != null) 'emotion_override': emotionOverride,
        if (timeConfidence != null) 'time_confidence': timeConfidence,
        if (timeSourceText != null) 'time_source_text': timeSourceText,
        if (placeName != null) 'place_name': placeName,
        if (placeLat != null) 'place_lat': placeLat,
        if (placeLng != null) 'place_lng': placeLng,
        if (dropletLabel != null) 'droplet_label': dropletLabel,
        if (sourceExcerptsJson != null) 'source_excerpts': sourceExcerpts,
        if (structuredFieldsJson != null) 'structured_fields': structuredFields,
        if (relatedMemoryIdsJson != null) 'related_memory_ids': relatedMemoryIds,
        'schema_version': schemaVersion,
        'tags': tags,
        'state': state,
        if (presentationJson != null) 'presentation_json': presentationJson,
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

  static SharedLifeMemoryService? _instance;

  /// Process-wide singleton. Throws when accessed before [init].
  static SharedLifeMemoryService get instance {
    final service = _instance;
    if (service == null) {
      throw StateError('SharedLifeMemoryService has not been initialized');
    }
    return service;
  }

  static bool get isInitialized => _instance != null;

  /// Initialize the singleton. Safe to call multiple times — replaces the
  /// previous instance (e.g. after re-login switching userIds).
  static void init(AppDatabase db, String userId) {
    _instance = SharedLifeMemoryService(db);
    _instance!.attachUserId(userId);
  }

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

  /// Batch-fetch entities by ID, preserving the order of [ids] and silently
  /// dropping any IDs that no longer exist (e.g. the related entity was
  /// deleted). UI uses this to resolve
  /// [SharedLifeEntitySnapshot.relatedMemoryIds] (AI soft links) and
  /// `state.related_entity_ids` (user hard links) into renderable card stubs.
  Future<List<SharedLifeEntitySnapshot>> getEntitiesByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    // De-dup while preserving first-seen order so the caller's intent stands.
    final seen = <String>{};
    final ordered = <String>[
      for (final id in ids)
        if (id.isNotEmpty && seen.add(id)) id,
    ];
    if (ordered.isEmpty) return const [];

    final rows = await (db.select(db.sharedLifeEntities)
          ..where((t) => t.id.isIn(ordered)))
        .get();
    final byId = {for (final r in rows) r.id: r};
    return [
      for (final id in ordered)
        if (byId[id] != null) _snapshotFromRow(byId[id]!),
    ];
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
    final sourceMessages = await _resolveOperationSourceMessages(operations);

    return SharedLifeEntityDetail(
      entity: _snapshotFromRow(entityRow),
      operations: operations,
      sourceMessages: sourceMessages,
    );
  }

  /// Loads the chat messages cited as evidence by [operations].
  ///
  /// Reads prefer the stable [SharedLifeEventOperations.sourceSyncIds] column
  /// and fall back to the legacy [SharedLifeEventOperations.sourceMessageIds]
  /// int array when stable IDs are missing (rows written before v56 dual-write
  /// or still awaiting backfill). A message that cannot be resolved by either
  /// is silently dropped, mirroring the pre-stable-ref behaviour.
  Future<List<PersonaChatMessage>> _resolveOperationSourceMessages(
    List<SharedLifeEventOperation> operations,
  ) async {
    final stableIds = <String>{};
    final legacyIds = <int>{};
    for (final op in operations) {
      final syncs = _decodeStringList(op.sourceSyncIds);
      if (syncs.isNotEmpty) {
        stableIds.addAll(syncs);
      } else {
        legacyIds.addAll(_decodeIntList(op.sourceMessageIds));
      }
    }
    if (stableIds.isEmpty && legacyIds.isEmpty) {
      return const <PersonaChatMessage>[];
    }
    final query = db.select(db.personaChatMessages)
      ..where(
        (t) => t.syncId.isIn(stableIds) | t.id.isIn(legacyIds),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    return query.get();
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

        // Source message IDs are stored as evidence for the detail view.
        // 'chat_message' originates from AI auto-capture and must be filtered
        // against allowedSourceMessageIds to block hallucinated IDs.
        // Other sourceKinds (record_button, floating_ball, manual_edit…)
        // carry IDs the user/UI supplied directly — trust those as-is.
        final List<int> sourceIds;
        final List<String> sourceSyncIds;
        if (draft.sourceKind == 'chat_message') {
          sourceIds = draft.sourceMessageIds
              .where(allowedSourceMessageIds.contains)
              .toSet()
              .toList()
            ..sort();
          // For auto-captured chat_message evidence, only resolve sync_ids for
          // IDs that survived the hallucination filter above.
          sourceSyncIds = await _resolveSyncIdsForIntIds(db, sourceIds);
        } else {
          sourceIds = draft.sourceMessageIds.toSet().toList()..sort();
          // Non-chat sources (record_button, floating_ball…) may carry a
          // draft-provided stable list; otherwise resolve from int IDs.
          sourceSyncIds = draft.sourceSyncIds.isNotEmpty
              ? draft.sourceSyncIds.toSet().toList()
              : await _resolveSyncIdsForIntIds(db, sourceIds);
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
                sourceSyncIds: sourceSyncIds.isEmpty
                    ? const Value(null)
                    : Value(jsonEncode(sourceSyncIds)),
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
    double? emotionConfidence;
    String? emotionEvidence;
    String? emotionOverride;
    double? timeConfidence;
    String? timeSourceText;
    String? placeName;
    double? placeLat;
    double? placeLng;
    String? dropletLabel;
    String? sourceExcerptsJson;
    String? structuredFieldsJson;
    String? relatedMemoryIdsJson;
    int schemaVersion = 1;
    String? presentationJson;

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
      if (reserved['_emotionConfidence'] case final double v) {
        emotionConfidence = v;
      }
      if (reserved['_emotionEvidence'] case final String s) {
        emotionEvidence = s;
      }
      if (reserved['_emotionOverride'] case final String s) {
        emotionOverride = s;
      }
      if (reserved['_timeConfidence'] case final double v) timeConfidence = v;
      if (reserved['_timeSourceText'] case final String s) timeSourceText = s;
      if (reserved['_placeName'] case final String s) placeName = s;
      if (reserved['_placeLat'] case final double v) placeLat = v;
      if (reserved['_placeLng'] case final double v) placeLng = v;
      if (reserved['_dropletLabel'] case final String s) dropletLabel = s;
      if (reserved['_sourceExcerpts'] case final String s) {
        sourceExcerptsJson = s;
      }
      if (reserved['_structuredFields'] case final String s) {
        structuredFieldsJson = s;
      }
      if (reserved['_relatedMemoryIds'] case final String s) {
        relatedMemoryIdsJson = s;
      }
      if (reserved['_schemaVersion'] case final int v) schemaVersion = v;
      // Latest operation that supplies a presentation wins (covers update/correct).
      if (reserved['_presentation'] case final String json) {
        presentationJson = json;
        final blockCount =
            RegExp(r'"type"\s*:\s*"').allMatches(json).length;
        _logger.info(
            'Rebuild entity $entityId: presentationJson set ($blockCount block(s), '
            '${json.length} chars)');
      }

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
            emotionConfidence: Value(emotionConfidence),
            emotionEvidence: Value(emotionEvidence),
            emotionOverride: Value(emotionOverride),
            timeConfidence: Value(timeConfidence),
            timeSourceText: Value(timeSourceText),
            placeName: Value(placeName),
            placeLat: Value(placeLat),
            placeLng: Value(placeLng),
            dropletLabel: Value(dropletLabel),
            sourceExcerpts: Value(sourceExcerptsJson),
            structuredFields: Value(structuredFieldsJson),
            relatedMemoryIds: Value(relatedMemoryIdsJson),
            schemaVersion: Value(schemaVersion),
            presentationJson: Value(presentationJson),
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
      emotionConfidence: row.emotionConfidence,
      emotionEvidence: row.emotionEvidence,
      emotionOverride: row.emotionOverride,
      timeConfidence: row.timeConfidence,
      timeSourceText: row.timeSourceText,
      placeName: row.placeName,
      placeLat: row.placeLat,
      placeLng: row.placeLng,
      dropletLabel: row.dropletLabel,
      sourceExcerptsJson: row.sourceExcerpts,
      structuredFieldsJson: row.structuredFields,
      relatedMemoryIdsJson: row.relatedMemoryIds,
      schemaVersion: row.schemaVersion,
      presentationJson: row.presentationJson,
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
  'outfit_log',
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
      case '_emotionConfidence':
      case '_timeConfidence':
      case '_placeLat':
      case '_placeLng':
        if (value is num) result[key] = value.toDouble();
      case '_emotionEvidence':
      case '_timeSourceText':
      case '_placeName':
      case '_dropletLabel':
        if (value is String && value.trim().isNotEmpty) result[key] = value;
      case '_sourceExcerpts':
      case '_relatedMemoryIds':
        // Both are JSON arrays of strings. Accept list or pre-encoded string.
        if (value is List) {
          final cleaned = value
              .map((e) => e?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList(growable: false);
          if (cleaned.isNotEmpty) result[key] = jsonEncode(cleaned);
        } else if (value is String && value.trim().isNotEmpty) {
          result[key] = value;
        }
      case '_structuredFields':
        // JSON object of typed atomic fields. Accept map or pre-encoded string.
        if (value is Map) {
          if (value.isNotEmpty) result[key] = jsonEncode(value);
        } else if (value is String && value.trim().isNotEmpty) {
          result[key] = value;
        }
      case '_emotionOverride':
        // Expected shape: {"valence": <num>, "arousal": <num>}
        if (value is Map) {
          result[key] = jsonEncode(value);
        } else if (value is String && value.trim().isNotEmpty) {
          result[key] = value;
        }
      case '_schemaVersion':
        if (value is int) result[key] = value;
      case '_presentation':
        if (value is Map) {
          result[key] = jsonEncode(value);
        } else if (value is String && value.trim().isNotEmpty) {
          result[key] = value;
        }
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

List<String> _decodeStringList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .map((item) => item is String ? item : '$item')
        .where((s) => s.isNotEmpty)
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

/// Resolves local persona_chat_messages integer IDs to their stable sync_ids.
///
/// Used during dual-write so every operation row carries a stable cross-device
/// reference alongside the legacy int IDs. Rows missing a sync_id (should not
/// happen post-v55) are silently dropped from the stable list; the int list is
/// still written as-is for back-compat.
Future<List<String>> _resolveSyncIdsForIntIds(
  AppDatabase db,
  Iterable<int> intIds,
) async {
  final unique = intIds.where((id) => id > 0).toSet();
  if (unique.isEmpty) return const [];
  final rows = await (db.select(db.personaChatMessages)
        ..where((t) => t.id.isIn(unique)))
      .get();
  return rows
      .map((row) => row.syncId)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
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
