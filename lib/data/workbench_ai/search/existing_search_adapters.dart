library;

import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

/// Safe adapter over the production card-library projection. Linked Source
/// metadata is not searched or returned as a Source hit; a dedicated Source
/// adapter needs its own bounded repository query.
class CardLibraryWorkbenchSearchAdapter implements WorkbenchSearchAdapter {
  CardLibraryWorkbenchSearchAdapter(this._repository);

  final UnifiedCardRepository _repository;

  @override
  String get adapterId => 'here_i_am_card_library_v1';

  @override
  Set<SearchScope> get supportedScopes => const {SearchScope.cardLibrary};

  @override
  Future<SearchAdapterResult> search(SearchAdapterRequest request) async {
    if (request.scope != SearchScope.cardLibrary) {
      return SearchAdapterResult(hits: const []);
    }
    final grant = request.permissionGrant;
    final records = grant.allContainers
        ? (await _repository.listCards(
            CardLibraryQuery(
              search: request.query,
              loadDocuments: false,
              limit: request.limit,
            ),
          ))
            .map((record) => (record: record, containerRef: null as String?))
            .toList(growable: false)
        : await _searchAllowedBoards(request);
    final retrievedAt = DateTime.now().toUtc();
    final hits = records.take(request.limit).map((entry) {
      final record = entry.record;
      final card = record.card;
      final title = card.title.trim().isEmpty ? '无标题卡片' : card.title.trim();
      final body = card.body.trim();
      final snippet = body.isNotEmpty
          ? body
          : card.tags.isNotEmpty
              ? card.tags.join(' · ')
              : title;
      return SearchHitRef(
        scope: SearchScope.cardLibrary,
        permissionLane: SearchPermissionLane.contentLibrary,
        objectType: 'card',
        objectId: card.cardId,
        stableRef: 'card:${card.cardId}',
        title: title,
        snippet: snippet,
        relevance: _containsScore(request.query, title, snippet),
        provenance: SearchProvenance(
          adapterId: adapterId,
          sourceKind: 'card_library_projection',
          sourceRef: 'card:${card.cardId}',
          // A restricted search gets one allowed board at a time. The facade
          // rechecks this ref before returning the hit.
          containerRef: entry.containerRef,
          queryStrategy: 'bounded_substring',
          retrievedAt: retrievedAt,
        ),
      );
    }).toList(growable: false);
    return SearchAdapterResult(hits: hits);
  }

  Future<List<({UnifiedCardRecord record, String containerRef})>>
      _searchAllowedBoards(
    SearchAdapterRequest request,
  ) async {
    final byCard =
        <String, ({UnifiedCardRecord record, String containerRef})>{};
    final boards = request.permissionGrant.allowedContainerRefs.toList()
      ..sort();
    for (final boardId in boards) {
      final rows = await _repository.listCards(
        CardLibraryQuery(
          search: request.query,
          boardId: boardId,
          placedOnBoard: true,
          loadDocuments: false,
          limit: request.limit,
        ),
      );
      for (final row in rows) {
        byCard.putIfAbsent(
          row.card.cardId,
          () => (record: row, containerRef: boardId),
        );
      }
      if (byCard.length >= request.limit) break;
    }
    return byCard.values.take(request.limit).toList(growable: false);
  }
}

/// Uses the Memory V3 FTS read API without the higher-level recall method that
/// appends query-tuning logs. Restricted grants are treated as explicit card
/// ids and filtered after a bounded FTS evidence window.
class MemoryV3SearchCandidate {
  const MemoryV3SearchCandidate({
    required this.cardId,
    required this.rank,
    this.queryStrategy,
  });

  final String cardId;
  final double rank;
  final String? queryStrategy;
}

class MemoryV3SearchDocument {
  const MemoryV3SearchDocument({
    required this.cardId,
    required this.title,
    required this.dropletLabel,
    required this.retrievalText,
  });

  final String cardId;
  final String title;
  final String dropletLabel;
  final String retrievalText;
}

abstract interface class MemoryV3SearchReader {
  Future<List<MemoryV3SearchCandidate>> search(
    String query, {
    required int limit,
  });

  Future<List<MemoryV3SearchDocument>> readByIds(List<String> cardIds);
}

class MemoryCardQuerySearchReader implements MemoryV3SearchReader {
  MemoryCardQuerySearchReader(this._service);

  final MemoryCardQueryService _service;

  @override
  Future<List<MemoryV3SearchCandidate>> search(
    String query, {
    required int limit,
  }) async {
    final raw = await _service.searchCards(query, limit: limit);
    return raw.map((entry) {
      return MemoryV3SearchCandidate(
        cardId: entry['card_id']!.toString(),
        rank: (entry['rank'] as num?)?.toDouble() ?? 0,
        queryStrategy: entry['query_strategy']?.toString(),
      );
    }).toList(growable: false);
  }

  @override
  Future<List<MemoryV3SearchDocument>> readByIds(List<String> cardIds) async {
    final cards = await _service.getCardsByIds(cardIds);
    return cards.map((card) {
      return MemoryV3SearchDocument(
        cardId: card.id,
        title: card.title,
        dropletLabel: card.dropletLabel,
        retrievalText: card.retrievalText,
      );
    }).toList(growable: false);
  }
}

class MemoryV3WorkbenchSearchAdapter implements WorkbenchSearchAdapter {
  MemoryV3WorkbenchSearchAdapter(MemoryCardQueryService service)
      : this.withReader(MemoryCardQuerySearchReader(service));

  MemoryV3WorkbenchSearchAdapter.withReader(this._reader);

  static const restrictedEvidenceWindow = 128;

  final MemoryV3SearchReader _reader;

  @override
  String get adapterId => 'here_i_am_memory_v3_v1';

  @override
  Set<SearchScope> get supportedScopes => const {SearchScope.memoryV3};

  @override
  Future<SearchAdapterResult> search(SearchAdapterRequest request) async {
    if (request.scope != SearchScope.memoryV3) {
      return SearchAdapterResult(hits: const []);
    }
    final allowed = request.permissionGrant;
    final evidenceLimit =
        allowed.allContainers ? request.limit : restrictedEvidenceWindow;
    final raw = await _reader.search(request.query, limit: evidenceLimit);
    final filtered = raw.where((entry) {
      return allowed.allContainers || allowed.allows(entry.cardId);
    }).toList(growable: false);
    final selected = filtered.take(request.limit).toList(growable: false);
    final ids = selected.map((entry) => entry.cardId).toList(growable: false);
    final cards = await _reader.readByIds(ids);
    final byId = {for (final card in cards) card.cardId: card};
    final retrievedAt = DateTime.now().toUtc();
    final results = <SearchHitRef>[];
    for (final entry in selected) {
      final id = entry.cardId;
      final card = byId[id];
      if (card == null) continue;
      final title = card.title.trim().isEmpty
          ? card.dropletLabel.trim().isEmpty
              ? '记忆卡片'
              : card.dropletLabel.trim()
          : card.title.trim();
      final snippet =
          card.retrievalText.trim().isEmpty ? title : card.retrievalText.trim();
      results.add(
        SearchHitRef(
          scope: SearchScope.memoryV3,
          permissionLane: SearchPermissionLane.userTruth,
          objectType: 'memory_card',
          objectId: id,
          stableRef: 'memory_card:$id',
          title: title,
          snippet: snippet,
          relevance: _ftsRelevance(entry.rank),
          provenance: SearchProvenance(
            adapterId: adapterId,
            sourceKind: 'memory_v3_card',
            sourceRef: 'memory_card:$id',
            containerRef: id,
            queryStrategy: entry.queryStrategy,
            retrievedAt: retrievedAt,
          ),
        ),
      );
    }
    final reasons = <String>[];
    if (!allowed.allContainers && raw.length >= restrictedEvidenceWindow) {
      reasons.add('memory_permission_evidence_window');
    }
    if (filtered.length > request.limit) {
      reasons.add('memory_authorized_result_limit');
    }
    return SearchAdapterResult(
      hits: results,
      examinedCandidateCount: raw.length,
      truncationReasons: reasons,
    );
  }
}

/// Project Memory already filters allowed projects before FTS rank/limit, so
/// its existing policy-gated read service maps cleanly to the workbench lane.
class ProjectMemoryWorkbenchSearchAdapter implements WorkbenchSearchAdapter {
  ProjectMemoryWorkbenchSearchAdapter(this._service);

  final ProjectMemoryService _service;

  @override
  String get adapterId => 'here_i_am_project_memory_v1';

  @override
  Set<SearchScope> get supportedScopes => const {SearchScope.projectMemory};

  @override
  Future<SearchAdapterResult> search(SearchAdapterRequest request) async {
    if (request.scope != SearchScope.projectMemory) {
      return SearchAdapterResult(hits: const []);
    }
    final grant = request.permissionGrant;
    final projectIds = grant.allContainers
        ? await _service.projectedProjectIds()
        : grant.allowedContainerRefs;
    final hits = await _service.search(
      request.query,
      scope: ProjectMemoryQueryScope(
        isProjectIntent: true,
        allowedProjectIds: projectIds,
      ),
      limit: request.limit,
    );
    final results = hits.map((hit) {
      final details = <String>[
        hit.summary,
        ...hit.decisions.map((value) => '决定：$value'),
        ...hit.openLoops.map((value) => '未完：$value'),
      ].join('\n');
      return SearchHitRef(
        scope: SearchScope.projectMemory,
        permissionLane: SearchPermissionLane.projectMemory,
        objectType: 'project_memory_item',
        objectId: hit.itemId,
        stableRef: 'project_memory:${hit.itemId}',
        title: hit.projectKey,
        snippet: details,
        relevance: _ftsRelevance(hit.rank),
        provenance: SearchProvenance(
          adapterId: adapterId,
          sourceKind: 'project_memory_projection',
          sourceRef: 'project_memory:${hit.itemId}',
          containerRef: hit.projectId,
          queryStrategy: 'policy_gated_fts',
          retrievedAt: DateTime.now().toUtc(),
        ),
      );
    }).toList(growable: false);
    return SearchAdapterResult(hits: results);
  }
}

double _containsScore(String query, String title, String snippet) {
  final needle = query.trim().toLowerCase();
  if (title.toLowerCase() == needle) return 1;
  if (title.toLowerCase().contains(needle)) return 0.9;
  if (snippet.toLowerCase().contains(needle)) return 0.7;
  return 0.5;
}

double _ftsRelevance(double rank) {
  final evidence = rank.abs();
  return evidence == 0 ? 0.5 : evidence / (1 + evidence);
}
