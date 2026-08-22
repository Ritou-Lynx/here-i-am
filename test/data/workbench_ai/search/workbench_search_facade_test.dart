import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/search/context_search_projection.dart';
import 'package:memex/data/workbench_ai/search/workbench_search_facade.dart';
import 'package:memex/data/workbench_ai/search/workbench_search_tool_host.dart';
import 'package:memex/domain/workbench_ai/context/context_envelope.dart';
import 'package:memex/domain/workbench_ai/context/context_envelope_codec.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';
import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

void main() {
  final retrievedAt = DateTime.utc(2026, 8, 22, 10);

  SearchHitRef hit({
    required SearchScope scope,
    required String id,
    required String adapterId,
    required double relevance,
    String container = 'workspace-current',
    String? snippet,
  }) {
    return SearchHitRef(
      scope: scope,
      permissionLane: scope.permissionLane,
      objectType: _objectType(scope),
      objectId: id,
      stableRef: '${scope.wireName}:$id',
      title: 'Title $id',
      snippet: snippet ?? 'Snippet $id',
      relevance: relevance,
      provenance: SearchProvenance(
        adapterId: adapterId,
        sourceKind: '${scope.wireName}_projection',
        sourceRef: 'source:$id',
        containerRef: container,
        queryStrategy: 'fake_match',
        retrievedAt: retrievedAt,
      ),
    );
  }

  SearchAuthorization allLanes() => SearchAuthorization(
        profileId: 'workbench-test',
        grants: SearchPermissionLane.values
            .map((lane) =>
                SearchPermissionGrant(lane: lane, allContainers: true))
            .toList(),
      );

  test(
    'aggregates every scope with stable deterministic refs and trace',
    () async {
      final adapters = SearchScope.values.map((scope) {
        final id = 'adapter-${scope.wireName}';
        return _FakeAdapter(
          adapterId: id,
          scopes: {scope},
          hits: {
            scope: [
              hit(
                scope: scope,
                id: 'id-${scope.index}',
                adapterId: id,
                relevance: 1 - scope.index * 0.1,
              ),
            ],
          },
        );
      }).toList();
      final response = await WorkbenchSearchFacade(adapters: adapters).search(
        request: WorkbenchSearchRequest(
          requestId: 'trace-all-scopes',
          query: '林埃',
          scopes: SearchScope.values.toSet(),
        ),
        authorization: allLanes(),
      );

      expect(response.status, WorkbenchSearchStatus.ok);
      expect(response.hits, hasLength(5));
      expect(response.hits.map((entry) => entry.stableRef), [
        'card_source:id-0',
        'memory_v3:id-1',
        'project_memory:id-2',
        'conversation:id-3',
        'task_artifact:id-4',
      ]);
      expect(response.trace.traceId, 'trace-all-scopes');
      expect(response.trace.requestedScopes, SearchScope.values);
      expect(response.trace.executedAdapters, hasLength(5));
      expect(response.trace.candidateCount, 5);
      expect(response.trace.returnedCount, 5);
      expect(response.trace.serializedUtf8Bytes, response.serializedUtf8Bytes);
    },
  );

  test(
    'filters denied scopes before adapters and restricted hits afterwards',
    () async {
      final project = _FakeAdapter(
        adapterId: 'project-adapter',
        scopes: {SearchScope.projectMemory},
        hits: {
          SearchScope.projectMemory: [
            hit(
              scope: SearchScope.projectMemory,
              id: 'allowed',
              adapterId: 'project-adapter',
              relevance: 0.9,
              container: 'project-1',
            ),
            hit(
              scope: SearchScope.projectMemory,
              id: 'blocked',
              adapterId: 'project-adapter',
              relevance: 1,
              container: 'project-2',
            ),
          ],
        },
      );
      final chat = _FakeAdapter(
        adapterId: 'chat-adapter',
        scopes: {SearchScope.conversation},
        hits: const {},
      );
      final response =
          await WorkbenchSearchFacade(adapters: [project, chat]).search(
        request: WorkbenchSearchRequest(
          requestId: 'trace-permissions',
          query: '进度',
          scopes: {SearchScope.projectMemory, SearchScope.conversation},
        ),
        authorization: SearchAuthorization(
          profileId: 'project-only',
          grants: [
            SearchPermissionGrant(
              lane: SearchPermissionLane.projectMemory,
              allowedContainerRefs: {'project-1'},
            ),
          ],
        ),
      );

      expect(response.status, WorkbenchSearchStatus.partial);
      expect(response.hits.single.objectId, 'allowed');
      expect(response.trace.deniedScopes, [SearchScope.conversation]);
      expect(project.requests.single.permissionGrant.allowedContainerRefs, {
        'project-1',
      });
      expect(chat.requests, isEmpty);
      expect(
        response.trace.truncationReasons,
        contains('invalid_or_unauthorized_adapter_hit'),
      );
    },
  );

  test('enforces total results and exact UTF-8 response budget', () async {
    final adapter = _FakeAdapter(
      adapterId: 'memory-adapter',
      scopes: {SearchScope.memoryV3},
      hits: {
        SearchScope.memoryV3: List.generate(
          8,
          (index) => hit(
            scope: SearchScope.memoryV3,
            id: 'memory-$index',
            adapterId: 'memory-adapter',
            relevance: 1 - index / 10,
            snippet: List.filled(80, '汉🙂').join(),
          ),
        ),
      },
    );
    final response = await WorkbenchSearchFacade(adapters: [adapter]).search(
      request: WorkbenchSearchRequest(
        requestId: 'trace-utf8',
        query: '汉字',
        scopes: {SearchScope.memoryV3},
        budget: WorkbenchSearchBudget(
          maxResults: 3,
          maxResultsPerScope: 8,
          maxTitleUtf8Bytes: 64,
          maxSnippetUtf8Bytes: 40,
          maxTotalUtf8Bytes: 2400,
        ),
      ),
      authorization: allLanes(),
    );

    expect(response.hits.length, lessThanOrEqualTo(3));
    expect(response.serializedUtf8Bytes, lessThanOrEqualTo(2400));
    expect(response.trace.serializedUtf8Bytes, response.serializedUtf8Bytes);
    expect(response.trace.truncationReasons, contains('snippet_utf8_limit'));
    expect(response.trace.truncationReasons, contains('total_result_limit'));
    for (final result in response.hits) {
      expect(utf8.encode(result.snippet).length, lessThanOrEqualTo(40));
    }
  });

  test(
    'adapter failure is safe, scoped, and does not expose exception text',
    () async {
      final response = await WorkbenchSearchFacade(
        adapters: [
          _FakeAdapter(
            adapterId: 'broken-chat',
            scopes: {SearchScope.conversation},
            hits: const {},
            error: StateError('raw SQL and secret should never escape'),
          ),
        ],
      ).search(
        request: WorkbenchSearchRequest(
          requestId: 'trace-failure',
          query: 'hello',
          scopes: {SearchScope.conversation},
        ),
        authorization: allLanes(),
      );

      final encoded = jsonEncode(response.toJson());
      expect(response.status, WorkbenchSearchStatus.partial);
      expect(response.trace.failedScopes, [SearchScope.conversation]);
      expect(encoded, isNot(contains('raw SQL')));
      expect(encoded, isNot(contains('secret')));
    },
  );

  test(
    'projects on-demand hits into bounded untrusted Context Envelope refs',
    () async {
      final response = await WorkbenchSearchFacade(
        adapters: [
          _FakeAdapter(
            adapterId: 'cards',
            scopes: {SearchScope.cardSource},
            hits: {
              SearchScope.cardSource: [
                hit(
                  scope: SearchScope.cardSource,
                  id: 'card-1',
                  adapterId: 'cards',
                  relevance: 1,
                ),
              ],
            },
          ),
        ],
      ).search(
        request: WorkbenchSearchRequest(
          requestId: 'trace-context',
          query: 'whiteboard',
          scopes: {SearchScope.cardSource},
        ),
        authorization: allLanes(),
      );
      final first = ContextSearchProjection.toRecallSnippets(response);
      final second = ContextSearchProjection.toRecallSnippets(response);
      expect(first.single.recallId, second.single.recallId);
      expect(first.single.sourceId, 'card_source:card-1');
      expect(first.single.content.trust, ContextTrust.untrustedContent);
      final unicodeResponse = response.copyWith(
        hits: [
          response.hits.single.copyWith(snippet: '🙂🙂🙂🙂🙂🙂'),
        ],
      );
      final tiny = ContextSearchProjection.toRecallSnippets(
        unicodeResponse,
        maxCharacters: 10,
      );
      expect(tiny.single.content.text.length, lessThanOrEqualTo(10));
      expect(() => jsonEncode(tiny.single.toJson()), returnsNormally);

      final envelope = ContextEnvelope(
        conversationId: 'conversation-1',
        identityPromptVersionRef: 'identity-v1',
        toolsetVersion: 'search-v1',
        permissionProfileId: 'workbench-test',
        runtimeProfile: RuntimeProfile.workbench,
        turnInstruction: ContextText(
          text: '查找相关内容',
          trust: ContextTrust.userInstruction,
        ),
        surface: ContextSurface(
          surfaceType: 'whiteboard',
          surfaceId: 'board-1',
        ),
        recallSnippets: first,
        createdAt: retrievedAt.add(const Duration(seconds: 1)),
      );
      final restored = ContextEnvelopeCodec.decode(
        ContextEnvelopeCodec.encode(envelope),
      );
      expect(restored.recallSnippets.single.sourceId, 'card_source:card-1');
    },
  );

  test('tool host rejects runtime-supplied permission fields', () async {
    final host = WorkbenchSearchToolHost(
      WorkbenchSearchFacade(adapters: const []),
    );
    final result = await host.invoke({
      'request_id': 'trace-invalid',
      'query': 'anything',
      'scopes': ['memory_v3'],
      'authorization': {'all': true},
    }, authorization: allLanes());
    expect(result, {
      'status': 'invalid_request',
      'error_code': 'invalid_search_request',
    });
  });

  test('stable refs reject filesystem and network references', () {
    expect(
      () => SearchProvenance(
        adapterId: 'adapter',
        sourceKind: 'card',
        sourceRef: r'C:\private\card.txt',
        retrievedAt: retrievedAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => SearchProvenance(
        adapterId: 'adapter',
        sourceKind: 'card',
        sourceRef: 'https://example.com/card',
        retrievedAt: retrievedAt,
      ),
      throwsArgumentError,
    );
  });
}

class _FakeAdapter implements WorkbenchSearchAdapter {
  _FakeAdapter({
    required this.adapterId,
    required Set<SearchScope> scopes,
    required this.hits,
    this.error,
  }) : supportedScopes = Set.unmodifiable(scopes);

  @override
  final String adapterId;
  @override
  final Set<SearchScope> supportedScopes;
  final Map<SearchScope, List<SearchHitRef>> hits;
  final Object? error;
  final List<SearchAdapterRequest> requests = [];

  @override
  Future<List<SearchHitRef>> search(SearchAdapterRequest request) async {
    requests.add(request);
    if (error != null) throw error!;
    return hits[request.scope] ?? const [];
  }
}

String _objectType(SearchScope scope) => switch (scope) {
      SearchScope.cardSource => 'card',
      SearchScope.memoryV3 => 'memory_card',
      SearchScope.projectMemory => 'project_memory_item',
      SearchScope.conversation => 'chat_message',
      SearchScope.taskArtifact => 'task_artifact',
    };
