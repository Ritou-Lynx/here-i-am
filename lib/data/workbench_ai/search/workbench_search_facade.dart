library;

import 'dart:convert';

import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

/// Aggregates product-owned search adapters behind one bounded, fail-closed
/// contract. Adapters receive permission constraints before querying and hits
/// are checked again before they can enter the response.
class WorkbenchSearchFacade {
  WorkbenchSearchFacade({required List<WorkbenchSearchAdapter> adapters})
      : _adapters = List.unmodifiable(adapters) {
    if (_adapters.length > WorkbenchSearchHardLimits.maxAdapters) {
      throw ArgumentError('Too many workbench search adapters');
    }
    final ids = <String>{};
    for (final adapter in _adapters) {
      if (!RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(adapter.adapterId)) {
        throw ArgumentError('Invalid search adapter id');
      }
      if (!ids.add(adapter.adapterId)) {
        throw ArgumentError(
          'Duplicate search adapter id: ${adapter.adapterId}',
        );
      }
      if (adapter.supportedScopes.isEmpty) {
        throw ArgumentError('Search adapter must support at least one scope');
      }
    }
  }

  final List<WorkbenchSearchAdapter> _adapters;

  Future<WorkbenchSearchResponse> search({
    required WorkbenchSearchRequest request,
    required SearchAuthorization authorization,
  }) async {
    final requestedScopes = request.scopes.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final deniedScopes = <SearchScope>[];
    final unsupportedScopes = <SearchScope>[];
    final failedScopes = <SearchScope>[];
    final executedAdapters = <String>{};
    final candidates = <SearchHitRef>[];
    final reasons = <String>{};

    for (final scope in requestedScopes) {
      final grant = authorization.grantFor(scope.permissionLane);
      if (grant == null) {
        deniedScopes.add(scope);
        continue;
      }
      final adapters = _adapters
          .where((adapter) => adapter.supportedScopes.contains(scope))
          .toList()
        ..sort((a, b) => a.adapterId.compareTo(b.adapterId));
      if (adapters.isEmpty) {
        unsupportedScopes.add(scope);
        continue;
      }

      for (final adapter in adapters) {
        executedAdapters.add(adapter.adapterId);
        try {
          final hits = await adapter.search(
            SearchAdapterRequest(
              requestId: request.requestId,
              query: request.query,
              scope: scope,
              limit: request.budget.maxResultsPerScope,
              permissionGrant: grant,
            ),
          );
          if (hits.length > request.budget.maxResultsPerScope) {
            reasons.add('adapter_result_limit');
          }
          for (final hit in hits.take(request.budget.maxResultsPerScope)) {
            final valid = hit.scope == scope &&
                hit.permissionLane == scope.permissionLane &&
                hit.provenance.adapterId == adapter.adapterId &&
                grant.allows(hit.provenance.containerRef);
            if (!valid) {
              reasons.add('invalid_or_unauthorized_adapter_hit');
              continue;
            }
            candidates.add(_boundHit(hit, request.budget, reasons));
          }
        } catch (_) {
          if (!failedScopes.contains(scope)) failedScopes.add(scope);
        }
      }
    }

    final byRef = <String, SearchHitRef>{};
    for (final hit in candidates) {
      final existing = byRef[hit.stableRef];
      if (existing == null || hit.relevance > existing.relevance) {
        byRef[hit.stableRef] = hit;
      }
    }
    if (byRef.length != candidates.length) reasons.add('duplicate_stable_ref');
    final hits = byRef.values.toList()
      ..sort((a, b) {
        final byRelevance = b.relevance.compareTo(a.relevance);
        if (byRelevance != 0) return byRelevance;
        final byScope = a.scope.index.compareTo(b.scope.index);
        if (byScope != 0) return byScope;
        return a.stableRef.compareTo(b.stableRef);
      });
    if (hits.length > request.budget.maxResults) {
      reasons.add('total_result_limit');
      hits.removeRange(request.budget.maxResults, hits.length);
    }

    final trace = WorkbenchSearchTrace(
      traceId: request.requestId,
      requestedScopes: List.unmodifiable(requestedScopes),
      executedAdapters: List.unmodifiable(executedAdapters.toList()..sort()),
      deniedScopes: List.unmodifiable(deniedScopes),
      unsupportedScopes: List.unmodifiable(unsupportedScopes),
      failedScopes: List.unmodifiable(failedScopes),
      candidateCount: candidates.length,
      returnedCount: hits.length,
      truncationReasons: const [],
      serializedUtf8Bytes: 0,
    );
    return _fitResponse(
      hits: hits,
      trace: trace,
      budget: request.budget,
      reasons: reasons,
    );
  }

  SearchHitRef _boundHit(
    SearchHitRef hit,
    WorkbenchSearchBudget budget,
    Set<String> reasons,
  ) {
    final title = _truncateUtf8(hit.title, budget.maxTitleUtf8Bytes);
    final snippet = _truncateUtf8(hit.snippet, budget.maxSnippetUtf8Bytes);
    if (title != hit.title) reasons.add('title_utf8_limit');
    if (snippet != hit.snippet) reasons.add('snippet_utf8_limit');
    return hit.copyWith(title: title, snippet: snippet);
  }

  WorkbenchSearchResponse _fitResponse({
    required List<SearchHitRef> hits,
    required WorkbenchSearchTrace trace,
    required WorkbenchSearchBudget budget,
    required Set<String> reasons,
  }) {
    final boundedHits = List<SearchHitRef>.of(hits);
    while (true) {
      final orderedReasons = reasons.toList()..sort();
      final status = _statusFor(
        hits: boundedHits,
        trace: trace,
        hasTruncation: orderedReasons.isNotEmpty,
      );
      var response = WorkbenchSearchResponse(
        status: status,
        hits: List.unmodifiable(boundedHits),
        trace: trace.copyWith(
          returnedCount: boundedHits.length,
          truncationReasons: List.unmodifiable(orderedReasons),
          serializedUtf8Bytes: 0,
        ),
        budget: budget,
      );
      // The byte count is part of the receipt. Iterate until its digit width is
      // stable, then apply the total response budget.
      for (var i = 0; i < 4; i++) {
        final bytes = response.serializedUtf8Bytes;
        response = response.copyWith(
          trace: response.trace.copyWith(serializedUtf8Bytes: bytes),
        );
      }
      final bytes = response.serializedUtf8Bytes;
      if (bytes <= budget.maxTotalUtf8Bytes) {
        if (bytes != response.trace.serializedUtf8Bytes) {
          response = response.copyWith(
            trace: response.trace.copyWith(serializedUtf8Bytes: bytes),
          );
        }
        return response;
      }
      if (boundedHits.isEmpty) {
        throw StateError('Search budget is too small for the response receipt');
      }
      boundedHits.removeLast();
      reasons.add('total_utf8_limit');
    }
  }

  WorkbenchSearchStatus _statusFor({
    required List<SearchHitRef> hits,
    required WorkbenchSearchTrace trace,
    required bool hasTruncation,
  }) {
    final allDenied = trace.deniedScopes.length == trace.requestedScopes.length;
    if (allDenied) return WorkbenchSearchStatus.permissionDenied;
    final incomplete = hasTruncation ||
        trace.deniedScopes.isNotEmpty ||
        trace.unsupportedScopes.isNotEmpty ||
        trace.failedScopes.isNotEmpty;
    if (incomplete) return WorkbenchSearchStatus.partial;
    return hits.isEmpty
        ? WorkbenchSearchStatus.empty
        : WorkbenchSearchStatus.ok;
  }
}

String _truncateUtf8(String value, int maxBytes) {
  if (utf8.encode(value).length <= maxBytes) return value;
  const suffix = '…';
  final suffixBytes = utf8.encode(suffix).length;
  final contentBudget = maxBytes > suffixBytes ? maxBytes - suffixBytes : 0;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final bytes = utf8.encode(character).length;
    if (used + bytes > contentBudget) break;
    buffer.write(character);
    used += bytes;
  }
  return contentBudget == 0 ? suffix : '${buffer.toString()}$suffix';
}
