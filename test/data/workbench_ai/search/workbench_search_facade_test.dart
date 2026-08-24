import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/workbench_ai/search/context_search_projection.dart';
import 'package:memex/data/workbench_ai/search/existing_search_adapters.dart';
import 'package:memex/data/workbench_ai/search/workbench_search_facade.dart';
import 'package:memex/data/workbench_ai/search/workbench_search_tool_host.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/workbench_ai/context/context_envelope.dart';
import 'package:memex/domain/workbench_ai/context/context_envelope_codec.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';
import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final retrievedAt = DateTime.utc(2026, 8, 22, 10);
  late bool fts5Available;

  setUpAll(() {
    fts5Available = _checkFts5();
    if (!fts5Available) {
      print('[search-facade-test] FTS5 not available on this runtime.');
    }
  });

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
      stableRef: _stableRef(scope, id),
      title: 'Title $id',
      snippet: snippet ?? 'Snippet $id',
      relevance: relevance,
      provenance: SearchProvenance(
        adapterId: adapterId,
        sourceKind: '${scope.wireName}_projection',
        sourceRef: _stableRef(scope, id),
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
        'card:id-0',
        'memory_card:id-1',
        'project_memory:id-2',
        'chat_message:id-3',
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

  test('production card-library adapter returns only card hits', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('p2-card-search-');
    addTearDown(() async {
      await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    await repository.createTextCard(
      cardId: 'card-alpha',
      title: 'Alpha card',
      body: 'search needle',
    );
    final result = await CardLibraryWorkbenchSearchAdapter(repository).search(
      SearchAdapterRequest(
        requestId: 'trace-card-library',
        query: 'needle',
        scope: SearchScope.cardLibrary,
        limit: 4,
        permissionGrant: SearchPermissionGrant(
          lane: SearchPermissionLane.contentLibrary,
          allContainers: true,
        ),
      ),
    );

    expect(SearchScope.cardLibrary.wireName, 'card_library');
    expect(
      SearchScope.values.map((scope) => scope.wireName),
      isNot(contains('card_source')),
    );
    expect(result.hits.single.scope, SearchScope.cardLibrary);
    expect(result.hits.single.objectType, 'card');
    expect(result.hits.single.stableRef, 'card:card-alpha');
    expect(result.hits.single.provenance.sourceRef, 'card:card-alpha');
  });

  test('real Memory V3 data can be matched through FTS-backed search', () async {
    if (!fts5Available) return;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.createFtsTables();
    await _insertMemoryCard(
      db,
      id: 'memory-card-needle',
      type: 'fact',
      title: '日常记忆',
      label: '拿铁',
      text: '用户今天喝了一杯拿铁，下午更有精神。',
    );
    final adapter = MemoryV3WorkbenchSearchAdapter(
      MemoryCardQuerySearchReader(MemoryCardQueryService(db)),
    );
    final response = await WorkbenchSearchFacade(adapters: [adapter]).search(
      request: WorkbenchSearchRequest(
        requestId: 'trace-memory-real-hit',
        query: '咖啡',
        scopes: {SearchScope.memoryV3},
        budget:
            const WorkbenchSearchBudget(maxResults: 1, maxResultsPerScope: 1),
      ),
      authorization: SearchAuthorization(
        profileId: 'memory-v3-real',
        grants: [
          SearchPermissionGrant(
            lane: SearchPermissionLane.userTruth,
            allContainers: true,
          ),
        ],
      ),
    );

    expect(response.status, WorkbenchSearchStatus.ok);
    expect(response.hits, hasLength(1));
    expect(response.hits.single.objectId, 'memory-card-needle');
    expect(response.hits.single.scope, SearchScope.memoryV3);
    expect(response.hits.single.stableRef, 'memory_card:memory-card-needle');
    expect(response.hits.single.permissionLane, SearchPermissionLane.userTruth);
    expect(response.trace.candidateCount, 1);
    await db.close();
  });

  test('real Memory V3 query returns empty when no matching card', () async {
    if (!fts5Available) return;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.createFtsTables();
    await _insertMemoryCard(
      db,
      id: 'memory-card-weather',
      type: 'fact',
      title: '天气记忆',
      label: '晴天',
      text: '明天要下雨。',
    );
    final adapter = MemoryV3WorkbenchSearchAdapter(
      MemoryCardQuerySearchReader(MemoryCardQueryService(db)),
    );
    final response = await WorkbenchSearchFacade(adapters: [adapter]).search(
      request: WorkbenchSearchRequest(
        requestId: 'trace-memory-real-empty',
        query: '记账',
        scopes: {SearchScope.memoryV3},
        budget:
            const WorkbenchSearchBudget(maxResults: 1, maxResultsPerScope: 1),
      ),
      authorization: SearchAuthorization(
        profileId: 'memory-v3-real-empty',
        grants: [
          SearchPermissionGrant(
            lane: SearchPermissionLane.userTruth,
            allContainers: true,
          ),
        ],
      ),
    );

    expect(response.status, WorkbenchSearchStatus.empty);
    expect(response.hits, isEmpty);
    expect(response.trace.returnedCount, 0);
    await db.close();
  });

  test(
    'adapter-level backend unavailability degrades to partial and returns no secrets',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final service = MemoryCardQueryService(db);
      await db.close();
      final adapter = MemoryV3WorkbenchSearchAdapter(
        MemoryCardQuerySearchReader(service),
      );
      final response = await WorkbenchSearchFacade(adapters: [adapter]).search(
        request: WorkbenchSearchRequest(
          requestId: 'trace-memory-backend-unavailable',
          query: '拿铁',
          scopes: {SearchScope.memoryV3},
        ),
        authorization: SearchAuthorization(
          profileId: 'memory-v3-unavailable',
          grants: [
            SearchPermissionGrant(
              lane: SearchPermissionLane.userTruth,
              allContainers: true,
            ),
          ],
        ),
      );
      final encoded = jsonEncode(response.toJson());

      expect(response.status, WorkbenchSearchStatus.partial);
      expect(response.trace.failedScopes, [SearchScope.memoryV3]);
      expect(encoded, isNot(contains('MemoryCardQueryService')));
      expect(encoded, isNot(contains('database')));
      await db.close();
    },
  );

  test('restricted Memory V3 searches evidence before the result limit',
      () async {
    final reader = _FakeMemoryV3Reader(
      candidates: List.generate(
        6,
        (index) => MemoryV3SearchCandidate(
          cardId: 'memory-$index',
          rank: -1 + index / 10,
          queryStrategy: 'fake_fts',
        ),
      ),
    );
    final adapter = MemoryV3WorkbenchSearchAdapter.withReader(reader);
    final response = await WorkbenchSearchFacade(adapters: [adapter]).search(
      request: WorkbenchSearchRequest(
        requestId: 'trace-memory-allow-list',
        query: 'needle',
        scopes: {SearchScope.memoryV3},
        budget: WorkbenchSearchBudget(maxResults: 1, maxResultsPerScope: 1),
      ),
      authorization: SearchAuthorization(
        profileId: 'one-memory-card',
        grants: [
          SearchPermissionGrant(
            lane: SearchPermissionLane.userTruth,
            allowedContainerRefs: {'memory-5'},
          ),
        ],
      ),
    );

    expect(
      reader.requestedLimits,
      [MemoryV3WorkbenchSearchAdapter.restrictedEvidenceWindow],
    );
    expect(response.hits.single.objectId, 'memory-5');
    expect(response.trace.candidateCount, 6);
    expect(
      response.trace.truncationReasons,
      isNot(contains('memory_permission_evidence_window')),
    );

    final exhaustedReader = _FakeMemoryV3Reader(
      candidates: List.generate(
        MemoryV3WorkbenchSearchAdapter.restrictedEvidenceWindow + 1,
        (index) => MemoryV3SearchCandidate(
          cardId: 'blocked-$index',
          rank: -1,
          queryStrategy: 'fake_fts',
        ),
      )..last = const MemoryV3SearchCandidate(
          cardId: 'allowed-beyond-window',
          rank: -0.1,
          queryStrategy: 'fake_fts',
        ),
    );
    final exhausted = await WorkbenchSearchFacade(
      adapters: [MemoryV3WorkbenchSearchAdapter.withReader(exhaustedReader)],
    ).search(
      request: WorkbenchSearchRequest(
        requestId: 'trace-memory-window-exhausted',
        query: 'needle',
        scopes: {SearchScope.memoryV3},
        budget: WorkbenchSearchBudget(maxResults: 1, maxResultsPerScope: 1),
      ),
      authorization: SearchAuthorization(
        profileId: 'beyond-window',
        grants: [
          SearchPermissionGrant(
            lane: SearchPermissionLane.userTruth,
            allowedContainerRefs: {'allowed-beyond-window'},
          ),
        ],
      ),
    );
    expect(exhausted.hits, isEmpty);
    expect(exhausted.status, WorkbenchSearchStatus.partial);
    expect(
      exhausted.trace.candidateCount,
      MemoryV3WorkbenchSearchAdapter.restrictedEvidenceWindow,
    );
    expect(
      exhausted.trace.truncationReasons,
      contains('memory_permission_evidence_window'),
    );
  });

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
            scopes: {SearchScope.cardLibrary},
            hits: {
              SearchScope.cardLibrary: [
                hit(
                  scope: SearchScope.cardLibrary,
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
          scopes: {SearchScope.cardLibrary},
        ),
        authorization: allLanes(),
      );
      final first = ContextSearchProjection.toRecallSnippets(response);
      final second = ContextSearchProjection.toRecallSnippets(response);
      expect(first.single.recallId, second.single.recallId);
      expect(first.single.sourceId, 'card:card-1');
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
      expect(restored.recallSnippets.single.sourceId, 'card:card-1');
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
  Future<SearchAdapterResult> search(SearchAdapterRequest request) async {
    requests.add(request);
    if (error != null) throw error!;
    final results = hits[request.scope] ?? const [];
    return SearchAdapterResult(hits: results);
  }
}

class _FakeMemoryV3Reader implements MemoryV3SearchReader {
  _FakeMemoryV3Reader({required this.candidates});

  final List<MemoryV3SearchCandidate> candidates;
  final List<int> requestedLimits = [];

  @override
  Future<List<MemoryV3SearchCandidate>> search(
    String query, {
    required int limit,
  }) async {
    requestedLimits.add(limit);
    return candidates.take(limit).toList(growable: false);
  }

  @override
  Future<List<MemoryV3SearchDocument>> readByIds(List<String> cardIds) async {
    return cardIds
        .map(
          (id) => MemoryV3SearchDocument(
            cardId: id,
            title: 'Title $id',
            dropletLabel: '记忆',
            retrievalText: 'Snippet $id',
          ),
        )
        .toList(growable: false);
  }
}

String _objectType(SearchScope scope) => switch (scope) {
      SearchScope.cardLibrary => 'card',
      SearchScope.memoryV3 => 'memory_card',
      SearchScope.projectMemory => 'project_memory_item',
      SearchScope.conversation => 'chat_message',
      SearchScope.taskArtifact => 'task_artifact',
    };

String _stableRef(SearchScope scope, String id) => switch (scope) {
      SearchScope.cardLibrary => 'card:$id',
      SearchScope.memoryV3 => 'memory_card:$id',
      SearchScope.projectMemory => 'project_memory:$id',
      SearchScope.conversation => 'chat_message:$id',
      SearchScope.taskArtifact => 'task_artifact:$id',
    };

Future<void> _insertMemoryCard(
  AppDatabase db, {
  required String id,
  required String type,
  required String title,
  required String label,
  required String text,
}) async {
  final now = DateTime(2026, 8, 24, 12).millisecondsSinceEpoch;
  await db.into(db.memoryCards).insert(
        MemoryCardsCompanion.insert(
          id: id,
          type: type,
          title: title,
          dropletLabel: label,
          presentationModule: '[]',
          retrievalText: text,
          valence: 0,
          arousal: 0.2,
          createdAt: now,
          updatedAt: now,
          status: const Value.absent(),
          needsFollowUp: const Value.absent(),
        ),
      );
  await db.searchDao.upsertMemoryV3Fts(
    cardId: id,
    dropletLabel: label,
    title: title,
    retrievalText: text,
  );
}

bool _checkFts5() {
  try {
    final db = sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE _fts5_check USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    return false;
  }
}
