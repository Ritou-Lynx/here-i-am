/// Read API for the Memory V3 card family.
///
/// Provides UI-facing queries that flatten the V3 table graph into
/// [MemoryCardViewData] and detail DTOs. All queries read through Drift;
/// writes go exclusively through [RecordOrganizerServiceV3].
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';

import '../models/memory_card_view_data.dart';
import '../retrieval/query_expander.dart';
import 'query_log_service.dart';

/// Detail payload for [getCardDetail].
class MemoryCardDetail {
  MemoryCardDetail({
    required this.card,
    this.source,
    this.structuredFields,
    this.entityLinks = const [],
    this.relations = const [],
    this.operations = const [],
    this.assets = const [],
  });

  final MemoryCardViewData card;

  /// Raw source row (rawInput, recordedAt, recordedPlace, sourceRef).
  final MemoryCardSourceData? source;

  /// Structured fields row (machine-consumed; not displayed).
  final MemoryCardStructuredFieldsData? structuredFields;

  /// Entity links with resolved entity names.
  final List<EntityLinkData> entityLinks;

  /// Related cards (outbound relations).
  final List<MemoryCardViewData> relations;

  /// Operation history rows.
  final List<OperationData> operations;

  /// Assets linked via [memory_card_assets] + [assets] tables.
  final List<CardAssetData> assets;
}

/// Flat view of one [MemoryCardSources] row.
class MemoryCardSourceData {
  MemoryCardSourceData({
    required this.cardId,
    required this.rawInput,
    required this.recordedAt,
    this.recordedPlace,
    this.sourceRef,
    this.sourceKind,
  });

  final String cardId;
  final String rawInput;
  final int recordedAt;
  final String? recordedPlace;
  final String? sourceRef;
  final String? sourceKind;
}

/// Flat view of one [MemoryCardStructuredFields] row.
class MemoryCardStructuredFieldsData {
  MemoryCardStructuredFieldsData({
    required this.cardId,
    required this.structuredFieldsType,
    required this.fieldsJson,
    required this.userCorrected,
  });

  final String cardId;
  final String structuredFieldsType;
  final Map<String, dynamic> fieldsJson;
  final bool userCorrected;
}

/// Resolved entity link: the link row + the entity name.
class EntityLinkData {
  EntityLinkData({
    required this.linkId,
    required this.entityId,
    required this.entityName,
    required this.entityCategory,
    required this.relation,
    this.relationshipToUser,
    this.confidence,
  });

  final String linkId;
  final String entityId;
  final String entityName;
  final String entityCategory;
  final String relation;
  final String? relationshipToUser;
  final double? confidence;
}

/// One row from [memory_card_operations].
class OperationData {
  OperationData({
    required this.id,
    required this.cardId,
    required this.operationType,
    required this.payload,
    required this.sourceKind,
    required this.createdAt,
  });

  final String id;
  final String cardId;
  final String operationType;
  final Map<String, dynamic> payload;
  final String sourceKind;
  final int createdAt;
}

/// One asset linked to a card via [memory_card_assets].
class CardAssetData {
  CardAssetData({
    required this.assetId,
    required this.role,
    this.storagePath,
    this.url,
    this.mimeType,
    this.assetType,
  });

  final String assetId;
  final String role; // source / evidence / display
  final String? storagePath;
  final String? url;
  final String? mimeType;
  final String? assetType;

  bool get isImage =>
      assetType == 'image' || (mimeType?.startsWith('image/') ?? false);
}

class MemoryCardQueryService {
  MemoryCardQueryService(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Card detail
  // ---------------------------------------------------------------------------

  /// Fetch a complete [MemoryCardDetail] for one card.
  Future<MemoryCardDetail> getCardDetail(String cardId) async {
    // 1. Card row
    final cardRow = await (_db.select(_db.memoryCards)
          ..where((t) => t.id.equals(cardId)))
        .getSingleOrNull();

    if (cardRow == null) {
      throw StateError('Memory card not found: $cardId');
    }

    final card = _toViewData(cardRow);

    // 2. Source row (fetch separately; Drift doesn't support
    //    left-join across tables that aren't FK-constrained)
    final sourceRow = await (_db.select(_db.memoryCardSources)
          ..where((t) => t.cardId.equals(cardId)))
        .getSingleOrNull();

    MemoryCardSourceData? source;
    if (sourceRow != null) {
      source = MemoryCardSourceData(
        cardId: sourceRow.cardId,
        rawInput: sourceRow.rawInput,
        recordedAt: sourceRow.recordedAt,
        recordedPlace: sourceRow.recordedPlace,
        sourceRef: sourceRow.sourceRef,
        sourceKind: sourceRow.sourceKind,
      );
      // Patch source data onto card for convenience
      card.rawInput = source.rawInput;
      card.recordedAt = source.recordedAt;
      card.recordedPlace = source.recordedPlace;
    }

    // 3. Structured fields
    final sfRow = await (_db.select(_db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(cardId)))
        .getSingleOrNull();

    MemoryCardStructuredFieldsData? structuredFields;
    if (sfRow != null) {
      structuredFields = MemoryCardStructuredFieldsData(
        cardId: sfRow.cardId,
        structuredFieldsType: sfRow.structuredFieldsType,
        fieldsJson: _decodeJson(sfRow.fieldsJson),
        userCorrected: sfRow.userCorrected,
      );
    }

    // 4. Entity links with resolved entity names
    final linkRows = await (_db.select(_db.memoryEntityLinks)
          ..where((t) =>
              t.sourceTable.equals('memory_cards') & t.sourceId.equals(cardId)))
        .get();

    final entityLinks = <EntityLinkData>[];
    for (final link in linkRows) {
      final entity = await (_db.select(_db.memoryEntities)
            ..where((t) => t.id.equals(link.entityId)))
          .getSingleOrNull();
      entityLinks.add(EntityLinkData(
        linkId: link.id,
        entityId: link.entityId,
        entityName: entity?.name ?? '(已删除)',
        entityCategory: entity?.category ?? 'unknown',
        relation: link.relation,
        relationshipToUser: entity?.relationshipToUser,
        confidence: link.confidence,
      ));
    }

    // 5. Related cards (outbound relations)
    final relRows = await (_db.select(_db.memoryCardRelations)
          ..where(
              (t) => t.fromCardId.equals(cardId) | t.toCardId.equals(cardId)))
        .get();

    final relations = <MemoryCardViewData>[];
    for (final rel in relRows) {
      final relatedCardId =
          rel.fromCardId == cardId ? rel.toCardId : rel.fromCardId;
      final relatedRow = await (_db.select(_db.memoryCards)
            ..where((t) => t.id.equals(relatedCardId)))
          .getSingleOrNull();
      if (relatedRow != null) {
        relations.add(_toViewData(relatedRow));
      }
    }

    // 6. Operation history
    final opRows = await (_db.select(_db.memoryCardOperations)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();

    final operations = opRows
        .map((op) => OperationData(
              id: op.id,
              cardId: op.cardId,
              operationType: op.operationType,
              payload: _decodeJson(op.payload),
              sourceKind: op.sourceKind,
              createdAt: op.createdAt,
            ))
        .toList();

    // 7. Assets (JOIN memory_card_assets → assets).
    //    assetId is normally a UUID, but legacy data may have a file path.
    final assetLinkRows = await (_db.select(_db.memoryCardAssets)
          ..where((t) => t.cardId.equals(cardId)))
        .get();

    final assets = <CardAssetData>[];
    for (final link in assetLinkRows) {
      // Try UUID match first.
      var assetRow = await (_db.select(_db.assets)
            ..where((t) => t.id.equals(link.assetId)))
          .getSingleOrNull();
      // Fallback: legacy data where assetId is a storagePath.
      assetRow ??= await (_db.select(_db.assets)
            ..where((t) => t.storagePath.equals(link.assetId)))
          .getSingleOrNull();
      if (assetRow != null) {
        assets.add(CardAssetData(
          assetId: assetRow.id,
          role: link.role,
          storagePath: assetRow.storagePath,
          url: assetRow.url,
          mimeType: assetRow.mimeType,
          assetType: assetRow.assetType,
        ));
      }
    }

    return MemoryCardDetail(
      card: card,
      source: source,
      structuredFields: structuredFields,
      entityLinks: entityLinks,
      relations: relations,
      operations: operations,
      assets: assets,
    );
  }

  // ---------------------------------------------------------------------------
  // Card listing
  // ---------------------------------------------------------------------------

  /// Fetch cards by their IDs. Missing IDs are silently skipped.
  Future<List<MemoryCardViewData>> getCardsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows =
        await (_db.select(_db.memoryCards)..where((t) => t.id.isIn(ids))).get();
    final cards = rows.map(_toViewData).toList();
    await _attachStructuredFields(cards);
    return cards;
  }

  /// List recent cards ordered by their EVENT TIME descending (not updatedAt).
  ///
  /// Event time is resolved per-card from [MemoryCardViewData.eventTimeMs]
  /// using structured-fields time anchors (paidAt / receivedAt / occurredAt /
  /// wakeDate / startAt / dueAt). Cards without structured-field anchors fall
  /// back to source.recordedAt, then card.createdAt. Sorting is done in Dart
  /// because the event time lives inside a JSON column.
  Future<List<MemoryCardViewData>> listRecentCards({int limit = 100}) async {
    final rows = await (_db.select(_db.memoryCards)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(limit))
        .get();

    final cards = rows.map(_toViewData).toList();
    await _attachStructuredFields(cards);
    await _attachSourceInfo(cards);

    cards.sort((a, b) {
      final aMs = a.eventTimeMs ?? a.createdAt;
      final bMs = b.eventTimeMs ?? b.createdAt;
      return bMs.compareTo(aMs);
    });
    return cards;
  }

  /// List cards whose structured fields belong to one of [types].
  Future<List<MemoryCardViewData>> listCardsByStructuredFieldTypes(
    Set<String> types, {
    int limit = 100,
  }) async {
    if (types.isEmpty) return [];

    final rows = await (_db.select(_db.memoryCards).join([
      innerJoin(
        _db.memoryCardStructuredFields,
        _db.memoryCardStructuredFields.cardId.equalsExp(_db.memoryCards.id),
      ),
    ])
          ..where(_db.memoryCardStructuredFields.structuredFieldsType
              .isIn(types.toList()))
          ..orderBy([OrderingTerm.desc(_db.memoryCards.updatedAt)])
          ..limit(limit))
        .get();

    final cards = rows
        .map((row) => _toViewData(row.readTable(_db.memoryCards)))
        .toList();
    await _attachStructuredFields(cards);
    cards.sort((a, b) {
      final aMs = a.eventTimeMs ?? a.createdAt;
      final bMs = b.eventTimeMs ?? b.createdAt;
      return bMs.compareTo(aMs);
    });
    return cards;
  }

  // ---------------------------------------------------------------------------
  // Schedule / task aggregation
  // ---------------------------------------------------------------------------

  /// List active task-like cards (type in task / schedule / plan) with
  /// structured fields attached. Used by the Schedule observation panel.
  ///
  /// Cards are returned in ascending due-time order (soonest first).
  /// Cards without a time anchor are placed at the end (unscheduled).
  Future<List<MemoryCardViewData>> listScheduleCards({
    Set<String> types = const {'task', 'schedule', 'plan'},
    bool includeCompleted = false,
    int limit = 200,
  }) async {
    final query = _db.select(_db.memoryCards)
      ..where((t) => t.type.isIn(types.toList()))
      ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)])
      ..limit(limit);

    if (!includeCompleted) {
      query.where((t) => t.status.equals('active') | t.status.isNull());
    }

    final rows = await query.get();
    final cards = rows.map(_toViewData).toList();
    await _attachStructuredFields(cards);
    await _attachSourceInfo(cards);

    // Sort by business event time ascending; nulls (unscheduled) go last.
    // Uses structuredEventTimeMs (not eventTimeMs) so cards recorded without
    // a time anchor sort as unscheduled instead of by their recording time.
    cards.sort((a, b) {
      final aMs = a.structuredEventTimeMs;
      final bMs = b.structuredEventTimeMs;
      if (aMs == null && bMs == null) return 0;
      if (aMs == null) return 1;
      if (bMs == null) return -1;
      return aMs.compareTo(bMs);
    });
    return cards;
  }

  /// Count active task-like cards grouped by urgency bucket.
  /// Returns {overdue: n, today: n, upcoming: n, unscheduled: n}.
  Future<Map<String, int>> getScheduleOverview() async {
    final cards = await listScheduleCards();
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    var overdue = 0;
    var today = 0;
    var upcoming = 0;
    var unscheduled = 0;

    for (final card in cards) {
      final ms = card.structuredEventTimeMs;
      if (ms == null) {
        unscheduled++;
      } else {
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        if (dt.isBefore(DateTime(now.year, now.month, now.day))) {
          overdue++;
        } else if (dt.isBefore(todayEnd)) {
          today++;
        } else {
          upcoming++;
        }
      }
    }
    return {
      'overdue': overdue,
      'today': today,
      'upcoming': upcoming,
      'unscheduled': unscheduled,
    };
  }

  // ---------------------------------------------------------------------------
  // Follow-up cards
  // ---------------------------------------------------------------------------

  /// List cards that have pending follow-up fields.
  Future<List<MemoryCardViewData>> getFollowUpCards({int limit = 20}) async {
    final rows = await (_db.select(_db.memoryCards)
          ..where((t) => t.needsFollowUp.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(limit))
        .get();

    return rows.map(_toViewData).toList();
  }

  // ---------------------------------------------------------------------------
  // Search (FTS5)
  // ---------------------------------------------------------------------------

  /// Search memory cards via FTS5 on retrievalText + dropletLabel + title.
  /// Returns card IDs with relevance rank and text snippets.
  Future<List<Map<String, dynamic>>> searchCards(
    String query, {
    int limit = 20,
  }) async {
    final plan = QueryExpander.expand(query);
    if (plan.variants.isEmpty) return [];

    final merged = <String, Map<String, dynamic>>{};
    final eagerVariants = plan.variants.where(
      (v) => v.strategy != QueryExpansionStrategy.relaxed,
    );
    final relaxedVariants = plan.variants.where(
      (v) => v.strategy == QueryExpansionStrategy.relaxed,
    );

    for (final variant in eagerVariants) {
      final hits = await _db.searchDao.searchMemoryV3Cards(
        variant.query,
        limit: _perVariantLimit(limit),
      );
      _mergeSearchHits(merged, hits, variant);
    }

    // Automatic loosening: only fall back to short distinctive terms when
    // original + expanded queries fail. This avoids flooding normal recall
    // with generic matches while still preventing brittle zero-result cases.
    if (merged.isEmpty) {
      for (final variant in relaxedVariants) {
        final hits = await _db.searchDao.searchMemoryV3Cards(
          variant.query,
          limit: _perVariantLimit(limit),
        );
        _mergeSearchHits(merged, hits, variant);
      }
    }

    final results = merged.values.toList()
      ..sort((a, b) {
        final rankA = (a['rank'] as num).toDouble();
        final rankB = (b['rank'] as num).toDouble();
        return rankA.compareTo(rankB);
      });
    return results.take(limit).toList();
  }

  /// Search and resolve to full [MemoryCardViewData] objects.
  ///
  /// Every call is logged to [QueryLogService] for Phase 3 Lite+ synonym-table
  /// tuning. Zero-result entries are the primary signal for missing synonyms.
  Future<List<MemoryCardViewData>> searchCardsResolved(
    String query, {
    int limit = 20,
  }) async {
    final hits = await searchCards(query, limit: limit);

    // Determine the best strategy that produced results.
    String topStrategy = 'none';
    if (hits.isNotEmpty) {
      topStrategy = hits.first['query_strategy'] as String? ?? 'none';
    }

    final cards = <MemoryCardViewData>[];
    for (final hit in hits) {
      final cardId = hit['card_id'] as String;
      final row = await (_db.select(_db.memoryCards)
            ..where((t) => t.id.equals(cardId)))
          .getSingleOrNull();
      if (row != null) {
        cards.add(_toViewData(row));
      }
    }

    // Fire-and-forget: never block the caller on logging.
    unawaited(QueryLogService.log(QueryLogEntry(
      query: query,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      resultCount: cards.length,
      topStrategy: topStrategy,
      topCards: cards
          .take(5)
          .map((card) => QueryLogCardHit(
                id: card.id,
                title: card.title,
                dropletLabel: card.dropletLabel,
                type: card.type,
              ))
          .toList(),
    )));

    return cards;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Convert a Drift [MemoryCard] row to the UI-friendly view.
  MemoryCardViewData _toViewData(MemoryCard row) {
    return MemoryCardViewData(
      id: row.id,
      type: row.type,
      title: row.title,
      dropletLabel: row.dropletLabel,
      presentationModule: row.presentationModule,
      retrievalText: row.retrievalText,
      valence: row.valence,
      arousal: row.arousal,
      status: row.status,
      needsFollowUp: MemoryCardViewData.parseNeedsFollowUp(row.needsFollowUp),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// Patch structured-fields data onto a list of view data in a single
  /// batched query. The constructor cannot join directly because callers
  /// sometimes only select `memory_cards` (e.g. [listRecentCards]).
  Future<void> _attachStructuredFields(List<MemoryCardViewData> cards) async {
    if (cards.isEmpty) return;
    final ids = cards.map((c) => c.id).toList();
    final rows = await (_db.select(_db.memoryCardStructuredFields)
          ..where((t) => t.cardId.isIn(ids)))
        .get();
    final byId = {for (final r in rows) r.cardId: r};
    for (final card in cards) {
      final sf = byId[card.id];
      if (sf != null) {
        card.structuredFieldsType = sf.structuredFieldsType;
        card.structuredFieldsJson = sf.fieldsJson;
      }
    }
  }

  /// Patch source row data (recordedAt, recordedPlace, rawInput) onto a
  /// list of view data in a single batched query. Same rationale as
  /// [_attachStructuredFields].
  Future<void> _attachSourceInfo(List<MemoryCardViewData> cards) async {
    if (cards.isEmpty) return;
    final ids = cards.map((c) => c.id).toList();
    final rows = await (_db.select(_db.memoryCardSources)
          ..where((t) => t.cardId.isIn(ids)))
        .get();
    final byId = {for (final r in rows) r.cardId: r};
    for (final card in cards) {
      final s = byId[card.id];
      if (s != null) {
        card.recordedAt = s.recordedAt;
        card.recordedPlace = s.recordedPlace;
        card.rawInput = s.rawInput;
      }
    }
  }

  static Map<String, dynamic> _decodeJson(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  static int _perVariantLimit(int limit) => limit < 20 ? 20 : limit * 2;

  static void _mergeSearchHits(
    Map<String, Map<String, dynamic>> merged,
    List<Map<String, dynamic>> hits,
    QueryVariant variant,
  ) {
    for (final hit in hits) {
      final cardId = hit['card_id'] as String?;
      if (cardId == null || cardId.isEmpty) continue;

      final enriched = Map<String, dynamic>.from(hit)
        ..['matched_query'] = variant.query
        ..['query_strategy'] = variant.strategy.name;

      final existing = merged[cardId];
      if (existing == null) {
        merged[cardId] = enriched;
        continue;
      }

      final existingRank = (existing['rank'] as num).toDouble();
      final newRank = (hit['rank'] as num).toDouble();
      if (newRank < existingRank) {
        merged[cardId] = enriched;
      }
    }
  }
}
