library;

import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

/// Safe adapter over the production Card/Source projection. Rich-text and
/// Source object files are deliberately not loaded.
class CardSourceWorkbenchSearchAdapter implements WorkbenchSearchAdapter {
  CardSourceWorkbenchSearchAdapter(this._repository);

  final UnifiedCardRepository _repository;

  @override
  String get adapterId => 'here_i_am_card_source_v1';

  @override
  Set<SearchScope> get supportedScopes => const {SearchScope.cardSource};

  @override
  Future<List<SearchHitRef>> search(SearchAdapterRequest request) async {
    if (request.scope != SearchScope.cardSource) return const [];
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
    return records.take(request.limit).map((entry) {
      final record = entry.record;
      final card = record.card;
      final title = card.title.trim().isEmpty ? '无标题卡片' : card.title.trim();
      final body = card.body.trim();
      final snippet = body.isNotEmpty
          ? body
          : card.tags.isNotEmpty
              ? card.tags.join(' · ')
              : title;
      final sourceId = record.source?.sourceId;
      return SearchHitRef(
        scope: SearchScope.cardSource,
        permissionLane: SearchPermissionLane.contentLibrary,
        objectType: 'card',
        objectId: card.cardId,
        stableRef: 'card:${card.cardId}',
        title: title,
        snippet: snippet,
        relevance: _containsScore(request.query, title, snippet),
        provenance: SearchProvenance(
          adapterId: adapterId,
          sourceKind:
              sourceId == null ? 'card_projection' : 'source_projection',
          sourceRef:
              sourceId == null ? 'card:${card.cardId}' : 'source:$sourceId',
          // A restricted search gets one allowed board at a time. The facade
          // rechecks this ref before returning the hit.
          containerRef: entry.containerRef,
          queryStrategy: 'bounded_substring',
          retrievedAt: retrievedAt,
        ),
      );
    }).toList(growable: false);
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
class MemoryV3WorkbenchSearchAdapter implements WorkbenchSearchAdapter {
  MemoryV3WorkbenchSearchAdapter(this._service);

  final MemoryCardQueryService _service;

  @override
  String get adapterId => 'here_i_am_memory_v3_v1';

  @override
  Set<SearchScope> get supportedScopes => const {SearchScope.memoryV3};

  @override
  Future<List<SearchHitRef>> search(SearchAdapterRequest request) async {
    if (request.scope != SearchScope.memoryV3) return const [];
    final raw = await _service.searchCards(request.query, limit: request.limit);
    final allowed = request.permissionGrant;
    final filtered = raw.where((entry) {
      final id = entry['card_id']?.toString();
      return id != null && (allowed.allContainers || allowed.allows(id));
    }).toList(growable: false);
    final ids = filtered.map((entry) => entry['card_id']!.toString()).toList();
    final cards = await _service.getCardsByIds(ids);
    final byId = {for (final card in cards) card.id: card};
    final retrievedAt = DateTime.now().toUtc();
    final results = <SearchHitRef>[];
    for (final entry in filtered) {
      final id = entry['card_id']!.toString();
      final card = byId[id];
      if (card == null) continue;
      final title = card.title.trim().isEmpty
          ? card.dropletLabel.trim().isEmpty
              ? '记忆卡片'
              : card.dropletLabel.trim()
          : card.title.trim();
      final snippet =
          card.retrievalText.trim().isEmpty ? title : card.retrievalText.trim();
      final rank = (entry['rank'] as num?)?.toDouble() ?? 0;
      results.add(
        SearchHitRef(
          scope: SearchScope.memoryV3,
          permissionLane: SearchPermissionLane.userTruth,
          objectType: 'memory_card',
          objectId: id,
          stableRef: 'memory_card:$id',
          title: title,
          snippet: snippet,
          relevance: _ftsRelevance(rank),
          provenance: SearchProvenance(
            adapterId: adapterId,
            sourceKind: 'memory_v3_card',
            sourceRef: 'memory_card:$id',
            containerRef: id,
            queryStrategy: entry['query_strategy']?.toString(),
            retrievedAt: retrievedAt,
          ),
        ),
      );
    }
    return results;
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
  Future<List<SearchHitRef>> search(SearchAdapterRequest request) async {
    if (request.scope != SearchScope.projectMemory) return const [];
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
    return hits.map((hit) {
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
