library;

import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

import 'workbench_search_facade.dart';

/// Provider-neutral domain tool boundary. Permission is passed separately by
/// trusted product code and cannot be supplied or expanded by model payloads.
class WorkbenchSearchToolHost {
  const WorkbenchSearchToolHost(this._facade);

  static const toolName = 'search_workbench_content';
  static const toolVersion = '1';

  final WorkbenchSearchFacade _facade;

  Future<Map<String, dynamic>> invoke(
    Map<String, dynamic> payload, {
    required SearchAuthorization authorization,
  }) async {
    try {
      _expectKeys(payload, const {'request_id', 'query', 'scopes', 'budget'});
      final rawScopes = payload['scopes'];
      if (rawScopes is! List || rawScopes.isEmpty) {
        throw const FormatException('scopes must be a non-empty list');
      }
      final scopes = rawScopes.map(SearchScope.parse).toSet();
      if (scopes.length != rawScopes.length) {
        throw const FormatException('scopes must not contain duplicates');
      }
      final rawBudget = payload['budget'];
      final budget = rawBudget == null
          ? WorkbenchSearchBudget()
          : _parseBudget(_asMap(rawBudget, 'budget'));
      final response = await _facade.search(
        request: WorkbenchSearchRequest(
          requestId: _asString(payload['request_id'], 'request_id'),
          query: _asString(payload['query'], 'query'),
          scopes: scopes,
          budget: budget,
        ),
        authorization: authorization,
      );
      return response.toJson();
    } on FormatException {
      return const {
        'status': 'invalid_request',
        'error_code': 'invalid_search_request',
      };
    } on ArgumentError {
      return const {
        'status': 'invalid_request',
        'error_code': 'invalid_search_request',
      };
    }
  }

  WorkbenchSearchBudget _parseBudget(Map<String, dynamic> json) {
    _expectKeys(json, const {
      'max_results',
      'max_results_per_scope',
      'max_title_utf8_bytes',
      'max_snippet_utf8_bytes',
      'max_total_utf8_bytes',
    });
    int read(String key, int fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! int) throw FormatException('$key must be an integer');
      return value;
    }

    return WorkbenchSearchBudget(
      maxResults: read('max_results', 12),
      maxResultsPerScope: read('max_results_per_scope', 8),
      maxTitleUtf8Bytes: read('max_title_utf8_bytes', 256),
      maxSnippetUtf8Bytes: read('max_snippet_utf8_bytes', 1536),
      maxTotalUtf8Bytes: read('max_total_utf8_bytes', 32768),
    );
  }
}

void _expectKeys(Map<String, dynamic> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unsupported search fields: $unknown');
  }
}

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

String _asString(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}
