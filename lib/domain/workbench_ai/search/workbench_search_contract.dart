library;

import 'dart:convert';

enum SearchScope {
  cardLibrary('card_library', SearchPermissionLane.contentLibrary),
  memoryV3('memory_v3', SearchPermissionLane.userTruth),
  projectMemory('project_memory', SearchPermissionLane.projectMemory),
  conversation('conversation', SearchPermissionLane.conversation),
  taskArtifact('task_artifact', SearchPermissionLane.taskArtifact);

  const SearchScope(this.wireName, this.permissionLane);
  final String wireName;
  final SearchPermissionLane permissionLane;

  static SearchScope parse(Object? value) => values.firstWhere(
        (scope) => scope.wireName == value,
        orElse: () => throw FormatException('Unknown search scope: $value'),
      );
}

enum SearchPermissionLane {
  contentLibrary('content_library'),
  userTruth('user_truth'),
  projectMemory('project_memory'),
  conversation('conversation'),
  taskArtifact('task_artifact');

  const SearchPermissionLane(this.wireName);
  final String wireName;
}

/// Grants are product-owned. A runtime/model payload never grants itself a
/// lane. Restricted grants use opaque product container refs (board/project/
/// conversation/task ids) which adapters must apply before candidate limits.
class SearchPermissionGrant {
  SearchPermissionGrant({
    required this.lane,
    this.allContainers = false,
    Set<String> allowedContainerRefs = const {},
  }) : allowedContainerRefs = Set.unmodifiable(allowedContainerRefs) {
    if (!allContainers && this.allowedContainerRefs.isEmpty) {
      throw ArgumentError('Grant must allow a lane or explicit containers');
    }
    for (final ref in this.allowedContainerRefs) {
      _requireStableIdentifier(ref, 'allowedContainerRef');
    }
  }

  final SearchPermissionLane lane;
  final bool allContainers;
  final Set<String> allowedContainerRefs;

  bool allows(String? containerRef) =>
      allContainers ||
      (containerRef != null && allowedContainerRefs.contains(containerRef));
}

class SearchAuthorization {
  SearchAuthorization({
    required this.profileId,
    required List<SearchPermissionGrant> grants,
  }) : grants = Map.unmodifiable({
          for (final grant in grants) grant.lane: grant,
        }) {
    _requireStableIdentifier(profileId, 'profileId');
    if (this.grants.length != grants.length) {
      throw ArgumentError('Search authorization contains duplicate lanes');
    }
  }

  final String profileId;
  final Map<SearchPermissionLane, SearchPermissionGrant> grants;

  SearchPermissionGrant? grantFor(SearchPermissionLane lane) => grants[lane];
}

class SearchProvenance {
  SearchProvenance({
    required this.adapterId,
    required this.sourceKind,
    required this.sourceRef,
    required this.retrievedAt,
    this.containerRef,
    this.queryStrategy,
  }) {
    _requireStableIdentifier(adapterId, 'adapterId');
    _requireStableIdentifier(sourceKind, 'sourceKind');
    _requireStableReference(sourceRef, 'sourceRef');
    if (containerRef != null) {
      _requireStableIdentifier(containerRef!, 'containerRef');
    }
    if (queryStrategy != null) {
      _requireStableIdentifier(queryStrategy!, 'queryStrategy');
    }
  }

  final String adapterId;
  final String sourceKind;
  final String sourceRef;
  final String? containerRef;
  final String? queryStrategy;
  final DateTime retrievedAt;

  Map<String, dynamic> toJson() => {
        'adapter_id': adapterId,
        'source_kind': sourceKind,
        'source_ref': sourceRef,
        if (containerRef != null) 'container_ref': containerRef,
        if (queryStrategy != null) 'query_strategy': queryStrategy,
        'retrieved_at': retrievedAt.toUtc().toIso8601String(),
      };
}

/// Bounded, stable hit metadata. No database row, arbitrary JSON, SQL, or
/// filesystem ref can cross this contract.
class SearchHitRef {
  SearchHitRef({
    required this.scope,
    required this.permissionLane,
    required this.objectType,
    required this.objectId,
    required this.stableRef,
    required this.title,
    required this.snippet,
    required this.relevance,
    required this.provenance,
  }) {
    _requireStableIdentifier(objectType, 'objectType');
    _requireStableIdentifier(objectId, 'objectId');
    _requireStableReference(stableRef, 'stableRef');
    if (title.trim().isEmpty || snippet.trim().isEmpty) {
      throw ArgumentError('Search hit title and snippet must not be blank');
    }
    if (!relevance.isFinite || relevance < 0 || relevance > 1) {
      throw ArgumentError('relevance must be between 0 and 1');
    }
  }

  final SearchScope scope;
  final SearchPermissionLane permissionLane;
  final String objectType;
  final String objectId;
  final String stableRef;
  final String title;
  final String snippet;
  final double relevance;
  final SearchProvenance provenance;

  SearchHitRef copyWith({String? title, String? snippet}) => SearchHitRef(
        scope: scope,
        permissionLane: permissionLane,
        objectType: objectType,
        objectId: objectId,
        stableRef: stableRef,
        title: title ?? this.title,
        snippet: snippet ?? this.snippet,
        relevance: relevance,
        provenance: provenance,
      );

  Map<String, dynamic> toJson() => {
        'scope': scope.wireName,
        'permission_lane': permissionLane.wireName,
        'object_type': objectType,
        'object_id': objectId,
        'stable_ref': stableRef,
        'title': title,
        'snippet': snippet,
        'relevance': relevance,
        'provenance': provenance.toJson(),
      };
}

abstract final class WorkbenchSearchHardLimits {
  static const maxQueryCharacters = 1024;
  static const maxAdapters = 8;
  static const maxResults = 64;
  static const maxResultsPerScope = 32;
  static const maxTitleUtf8Bytes = 512;
  static const maxSnippetUtf8Bytes = 4096;
  static const maxTotalUtf8Bytes = 65536;
}

class WorkbenchSearchBudget {
  WorkbenchSearchBudget({
    this.maxResults = 12,
    this.maxResultsPerScope = 8,
    this.maxTitleUtf8Bytes = 256,
    this.maxSnippetUtf8Bytes = 1536,
    this.maxTotalUtf8Bytes = 32768,
  }) {
    _requireBudget(
      maxResults,
      WorkbenchSearchHardLimits.maxResults,
      'maxResults',
    );
    _requireBudget(
      maxResultsPerScope,
      WorkbenchSearchHardLimits.maxResultsPerScope,
      'maxResultsPerScope',
    );
    _requireBudget(
      maxTitleUtf8Bytes,
      WorkbenchSearchHardLimits.maxTitleUtf8Bytes,
      'maxTitleUtf8Bytes',
    );
    _requireBudget(
      maxSnippetUtf8Bytes,
      WorkbenchSearchHardLimits.maxSnippetUtf8Bytes,
      'maxSnippetUtf8Bytes',
    );
    if (maxTitleUtf8Bytes < 3 || maxSnippetUtf8Bytes < 3) {
      throw ArgumentError('UTF-8 text budgets must be at least 3 bytes');
    }
    _requireBudget(
      maxTotalUtf8Bytes,
      WorkbenchSearchHardLimits.maxTotalUtf8Bytes,
      'maxTotalUtf8Bytes',
    );
    if (maxTotalUtf8Bytes < 2048) {
      throw ArgumentError('maxTotalUtf8Bytes must be at least 2048');
    }
  }

  final int maxResults;
  final int maxResultsPerScope;
  final int maxTitleUtf8Bytes;
  final int maxSnippetUtf8Bytes;
  final int maxTotalUtf8Bytes;

  Map<String, dynamic> toJson() => {
        'max_results': maxResults,
        'max_results_per_scope': maxResultsPerScope,
        'max_title_utf8_bytes': maxTitleUtf8Bytes,
        'max_snippet_utf8_bytes': maxSnippetUtf8Bytes,
        'max_total_utf8_bytes': maxTotalUtf8Bytes,
      };
}

class WorkbenchSearchRequest {
  WorkbenchSearchRequest({
    required this.requestId,
    required this.query,
    required Set<SearchScope> scopes,
    WorkbenchSearchBudget? budget,
  })  : scopes = Set.unmodifiable(scopes),
        budget = budget ?? WorkbenchSearchBudget() {
    _requireStableIdentifier(requestId, 'requestId');
    if (query.trim().isEmpty ||
        query.length > WorkbenchSearchHardLimits.maxQueryCharacters) {
      throw ArgumentError('query is blank or exceeds its hard limit');
    }
    if (this.scopes.isEmpty) throw ArgumentError('scopes must not be empty');
  }

  final String requestId;
  final String query;
  final Set<SearchScope> scopes;
  final WorkbenchSearchBudget budget;
}

class SearchAdapterRequest {
  const SearchAdapterRequest({
    required this.requestId,
    required this.query,
    required this.scope,
    required this.limit,
    required this.permissionGrant,
  });

  final String requestId;
  final String query;
  final SearchScope scope;
  final int limit;
  final SearchPermissionGrant permissionGrant;
}

abstract interface class WorkbenchSearchAdapter {
  String get adapterId;
  Set<SearchScope> get supportedScopes;
  Future<SearchAdapterResult> search(SearchAdapterRequest request);
}

/// Adapter-local evidence receipt. A bounded adapter may inspect more
/// candidates than it returns (for example, to apply an allow-list). If its
/// evidence window is exhausted, it must report a stable truncation reason.
class SearchAdapterResult {
  SearchAdapterResult({
    required List<SearchHitRef> hits,
    int? examinedCandidateCount,
    List<String> truncationReasons = const [],
  })  : hits = List.unmodifiable(hits),
        examinedCandidateCount = examinedCandidateCount ?? hits.length,
        truncationReasons = List.unmodifiable(truncationReasons) {
    if (this.examinedCandidateCount < hits.length) {
      throw ArgumentError('examinedCandidateCount cannot be below hit count');
    }
    for (final reason in truncationReasons) {
      if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(reason)) {
        throw ArgumentError('Invalid adapter truncation reason');
      }
    }
  }

  final List<SearchHitRef> hits;
  final int examinedCandidateCount;
  final List<String> truncationReasons;
}

enum WorkbenchSearchStatus {
  ok('ok'),
  partial('partial'),
  empty('empty'),
  permissionDenied('permission_denied');

  const WorkbenchSearchStatus(this.wireName);
  final String wireName;
}

class WorkbenchSearchTrace {
  const WorkbenchSearchTrace({
    required this.traceId,
    required this.requestedScopes,
    required this.executedAdapters,
    required this.deniedScopes,
    required this.unsupportedScopes,
    required this.failedScopes,
    required this.candidateCount,
    required this.returnedCount,
    required this.truncationReasons,
    required this.serializedUtf8Bytes,
  });

  final String traceId;
  final List<SearchScope> requestedScopes;
  final List<String> executedAdapters;
  final List<SearchScope> deniedScopes;
  final List<SearchScope> unsupportedScopes;
  final List<SearchScope> failedScopes;
  final int candidateCount;
  final int returnedCount;
  final List<String> truncationReasons;
  final int serializedUtf8Bytes;

  WorkbenchSearchTrace copyWith({
    int? returnedCount,
    List<String>? truncationReasons,
    int? serializedUtf8Bytes,
  }) =>
      WorkbenchSearchTrace(
        traceId: traceId,
        requestedScopes: requestedScopes,
        executedAdapters: executedAdapters,
        deniedScopes: deniedScopes,
        unsupportedScopes: unsupportedScopes,
        failedScopes: failedScopes,
        candidateCount: candidateCount,
        returnedCount: returnedCount ?? this.returnedCount,
        truncationReasons: truncationReasons ?? this.truncationReasons,
        serializedUtf8Bytes: serializedUtf8Bytes ?? this.serializedUtf8Bytes,
      );

  Map<String, dynamic> toJson() => {
        'trace_id': traceId,
        'requested_scopes': requestedScopes.map((e) => e.wireName).toList(),
        'executed_adapters': executedAdapters,
        'denied_scopes': deniedScopes.map((e) => e.wireName).toList(),
        'unsupported_scopes': unsupportedScopes.map((e) => e.wireName).toList(),
        'failed_scopes': failedScopes.map((e) => e.wireName).toList(),
        'candidate_count': candidateCount,
        'returned_count': returnedCount,
        'truncation_reasons': truncationReasons,
        'serialized_output_utf8_bytes': serializedUtf8Bytes,
      };
}

class WorkbenchSearchResponse {
  const WorkbenchSearchResponse({
    required this.status,
    required this.hits,
    required this.trace,
    required this.budget,
  });

  final WorkbenchSearchStatus status;
  final List<SearchHitRef> hits;
  final WorkbenchSearchTrace trace;
  final WorkbenchSearchBudget budget;

  WorkbenchSearchResponse copyWith({
    WorkbenchSearchStatus? status,
    List<SearchHitRef>? hits,
    WorkbenchSearchTrace? trace,
  }) =>
      WorkbenchSearchResponse(
        status: status ?? this.status,
        hits: hits ?? this.hits,
        trace: trace ?? this.trace,
        budget: budget,
      );

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'hits': hits.map((hit) => hit.toJson()).toList(),
        'trace': trace.toJson(),
        'budget': budget.toJson(),
      };

  int get serializedUtf8Bytes => utf8.encode(jsonEncode(toJson())).length;
}

void _requireBudget(int value, int hardLimit, String field) {
  if (value <= 0 || value > hardLimit) {
    throw ArgumentError('$field must be between 1 and $hardLimit');
  }
}

void _requireStableIdentifier(String value, String field) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 256 || trimmed.contains('\u0000')) {
    throw ArgumentError('$field is not a valid stable identifier');
  }
  if (_looksLikeAbsolutePath(trimmed)) {
    throw ArgumentError('$field must not be an absolute path');
  }
}

void _requireStableReference(String value, String field) {
  _requireStableIdentifier(value, field);
  final separator = value.indexOf(':');
  if (separator <= 0 || separator == value.length - 1) {
    throw ArgumentError('$field must be a namespaced stable reference');
  }
  final scheme = value.substring(0, separator);
  if (!RegExp(r'^[a-z][a-z0-9_.-]*$').hasMatch(scheme) ||
      const {'file', 'http', 'https'}.contains(scheme)) {
    throw ArgumentError('$field uses an unsupported reference namespace');
  }
}

bool _looksLikeAbsolutePath(String value) =>
    RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value) ||
    value.startsWith('/') ||
    value.startsWith(r'\\');
