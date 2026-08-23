import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/search/workbench_runtime_search_tool.dart';
import 'package:memex/data/workbench_ai/search/workbench_search_facade.dart';
import 'package:memex/data/workbench_ai/search/workbench_search_tool_host.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

void main() {
  test('Runtime definition exposes only production-safe read scopes', () {
    const definition = WorkbenchSearchToolHost.dynamicToolDefinition;
    final schema = definition['input_schema'] as Map<String, dynamic>;
    final properties = schema['properties'] as Map<String, dynamic>;
    final scopes = properties['scopes'] as Map<String, dynamic>;
    final items = scopes['items'] as Map<String, dynamic>;

    expect(definition['name'], WorkbenchSearchToolHost.toolName);
    expect(schema['additionalProperties'], isFalse);
    expect(items['enum'], ['card_library', 'memory_v3', 'project_memory']);
    expect(items['enum'], isNot(contains('conversation')));
    expect(items['enum'], isNot(contains('task_artifact')));
    expect(properties, isNot(contains('authorization')));
  });

  test(
    'product authorization restricts Project Memory to projected ids',
    () async {
      final authorization = await DesktopWorkbenchSearchAuthorizationFactory(
        loadProjectedProjectIds: () async => {'project-a', 'project-b'},
      ).build();

      expect(
        authorization
            .grantFor(SearchPermissionLane.contentLibrary)
            ?.allContainers,
        isTrue,
      );
      expect(
        authorization.grantFor(SearchPermissionLane.userTruth)?.allContainers,
        isTrue,
      );
      final projectGrant = authorization.grantFor(
        SearchPermissionLane.projectMemory,
      )!;
      expect(projectGrant.allContainers, isFalse);
      expect(projectGrant.allowedContainerRefs, {'project-a', 'project-b'});
    },
  );

  test('empty Project Memory projection issues no project lane', () async {
    final authorization = await DesktopWorkbenchSearchAuthorizationFactory(
      loadProjectedProjectIds: () async => {},
    ).build();

    expect(authorization.grantFor(SearchPermissionLane.projectMemory), isNull);
  });

  test(
    'Runtime invocation preserves bounded response and deterministic trace',
    () async {
      final adapter = _RuntimeSearchAdapter();
      final tool = _tool(adapter, projectedProjectIds: {'project-a'});

      final result = await tool.invoke({
        'request_id': 'runtime-search-1',
        'query': '春雨',
        'scopes': ['card_library'],
        'budget': {
          'max_results': 1,
          'max_results_per_scope': 1,
          'max_snippet_utf8_bytes': 24,
          'max_total_utf8_bytes': 4096,
        },
      });

      expect(result.success, isTrue);
      final output = jsonDecode(result.text) as Map<String, dynamic>;
      final trace = output['trace'] as Map<String, dynamic>;
      final hits = output['hits'] as List<dynamic>;
      expect(output['status'], 'partial');
      expect(hits, hasLength(1));
      expect(trace['trace_id'], 'runtime-search-1');
      expect(trace['executed_adapters'], [adapter.adapterId]);
      expect(trace['truncation_reasons'], contains('snippet_utf8_limit'));
      expect(
        trace['serialized_output_utf8_bytes'],
        utf8.encode(result.text).length,
      );
    },
  );

  test('model payload cannot grant itself another permission lane', () async {
    final adapter = _RuntimeSearchAdapter();
    final tool = _tool(adapter, projectedProjectIds: const {});

    final result = await tool.invoke({
      'request_id': 'runtime-search-auth-escalation',
      'query': '项目',
      'scopes': ['project_memory'],
      'authorization': {
        'project_memory': {'all_containers': true},
      },
    });

    expect(result.success, isFalse);
    expect(jsonDecode(result.text), {
      'status': 'invalid_request',
      'error_code': 'invalid_search_request',
    });
    expect(adapter.calls, 0);
  });

  test('conversation Runtime registers, dispatches, and restores search',
      () async {
    final adapter = _RuntimeSearchAdapter();
    final searchTool = _tool(adapter, projectedProjectIds: {'project-a'});
    final runtime = _SearchConversationRuntime();
    final replies = <String>[];
    final coordinator = WorkbenchConversationCoordinator(
      runtime: runtime,
      searchTool: searchTool,
      addReply: (_, content) async {
        replies.add(content);
        return replies.length;
      },
      pollInterval: Duration.zero,
    );

    final first = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '找一下春雨卡片',
    );

    expect(first.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.startedTools.single, hasLength(1));
    expect(
      runtime.startedTools.single.single['name'],
      WorkbenchSearchToolHost.toolName,
    );
    expect(runtime.toolResponses.single.success, isTrue);
    final searchOutput = jsonDecode(runtime.toolResponses.single.text)
        as Map<String, dynamic>;
    expect((searchOutput['trace'] as Map)['returned_count'], 1);

    runtime.loseLocalSessionOnNextTurn = true;
    final resumed = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '继续',
    );

    expect(resumed.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.resumedTools.single, hasLength(1));
    expect(
      runtime.resumedTools.single.single['name'],
      WorkbenchSearchToolHost.toolName,
    );
    expect(replies, ['已找到。', '已恢复。']);
  });

  test('hanging search is bounded by the remaining turn deadline', () async {
    final adapter = _BlockingRuntimeSearchAdapter();
    final runtime = _SearchConversationRuntime();
    final replies = <String>[];
    final coordinator = _searchCoordinator(
      runtime: runtime,
      searchTool: _tool(adapter, projectedProjectIds: {'project-a'}),
      replies: replies,
      turnTimeout: const Duration(milliseconds: 10),
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '搜索但不要永远等待',
    );

    expect(result.errorCode, 'runtime_timeout');
    expect(replies.single, contains('等待超时'));
    expect(runtime.interruptCalls, 1);
    expect(runtime.closeSessionCalls, 1);
    expect(runtime.toolResponses, isEmpty);
  });

  test('stop during search returns promptly and cleans the local turn',
      () async {
    final adapter = _BlockingRuntimeSearchAdapter();
    final runtime = _SearchConversationRuntime();
    final replies = <String>[];
    final coordinator = _searchCoordinator(
      runtime: runtime,
      searchTool: _tool(adapter, projectedProjectIds: {'project-a'}),
      replies: replies,
    );

    final pending = coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '开始搜索',
    );
    await adapter.started.future;
    expect(await coordinator.stop('persona-i'), isTrue);
    final result = await pending;

    expect(result.outcome, WorkbenchConversationOutcome.interrupted);
    expect(result.errorCode, 'runtime_interrupted');
    expect(replies.single, '已停止这次电脑回复。');
    expect(runtime.interruptCalls, 2);
    expect(runtime.closeSessionCalls, 1);
    expect(runtime.toolResponses, isEmpty);
  });

  test('tool response transport failure abandons the runtime session',
      () async {
    final runtime = _SearchConversationRuntime(
      responseFailure: const WorkbenchRuntimeException(
        'tool_response_failed',
        'Bridge rejected the tool response.',
      ),
    );
    final replies = <String>[];
    final coordinator = _searchCoordinator(
      runtime: runtime,
      searchTool: _tool(
        _RuntimeSearchAdapter(),
        projectedProjectIds: {'project-a'},
      ),
      replies: replies,
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '搜索并回传',
    );

    expect(result.errorCode, 'tool_response_failed');
    expect(runtime.interruptCalls, 1);
    expect(runtime.closeSessionCalls, 1);
  });
}

WorkbenchConversationCoordinator _searchCoordinator({
  required _SearchConversationRuntime runtime,
  required WorkbenchRuntimeSearchTool searchTool,
  required List<String> replies,
  Duration turnTimeout = const Duration(seconds: 2),
}) {
  return WorkbenchConversationCoordinator(
    runtime: runtime,
    searchTool: searchTool,
    addReply: (_, content) async {
      replies.add(content);
      return replies.length;
    },
    pollInterval: Duration.zero,
    turnTimeout: turnTimeout,
  );
}

WorkbenchRuntimeSearchTool _tool(
  WorkbenchSearchAdapter adapter, {
  required Set<String> projectedProjectIds,
}) {
  return WorkbenchRuntimeSearchTool(
    loadHost: () async =>
        WorkbenchSearchToolHost(WorkbenchSearchFacade(adapters: [adapter])),
    authorizationFactory: DesktopWorkbenchSearchAuthorizationFactory(
      loadProjectedProjectIds: () async => projectedProjectIds,
    ),
  );
}

class _RuntimeSearchAdapter implements WorkbenchSearchAdapter {
  int calls = 0;

  @override
  String get adapterId => 'runtime_search_test_adapter';

  @override
  Set<SearchScope> get supportedScopes => const {
        SearchScope.cardLibrary,
        SearchScope.projectMemory,
      };

  @override
  Future<SearchAdapterResult> search(SearchAdapterRequest request) async {
    calls++;
    final project = request.scope == SearchScope.projectMemory;
    return SearchAdapterResult(
      hits: [
        SearchHitRef(
          scope: request.scope,
          permissionLane: request.scope.permissionLane,
          objectType: project ? 'project_memory_item' : 'card',
          objectId: project ? 'project-item-1' : 'card-1',
          stableRef: project ? 'project_memory:project-item-1' : 'card:card-1',
          title: project ? '项目进展' : '春雨卡片',
          snippet: '这是一段会被 UTF-8 预算安全截断的搜索摘要内容。',
          relevance: 0.8,
          provenance: SearchProvenance(
            adapterId: adapterId,
            sourceKind: project ? 'project_memory_projection' : 'test_card',
            sourceRef:
                project ? 'project_memory:project-item-1' : 'card:card-1',
            containerRef: project ? 'project-a' : null,
            retrievedAt: DateTime.utc(2026, 8, 23),
          ),
        ),
      ],
    );
  }
}

class _BlockingRuntimeSearchAdapter implements WorkbenchSearchAdapter {
  final Completer<void> started = Completer<void>();
  final Completer<SearchAdapterResult> _never =
      Completer<SearchAdapterResult>();

  @override
  String get adapterId => 'blocking_runtime_search_adapter';

  @override
  Set<SearchScope> get supportedScopes => const {SearchScope.cardLibrary};

  @override
  Future<SearchAdapterResult> search(SearchAdapterRequest request) {
    if (!started.isCompleted) started.complete();
    return _never.future;
  }
}

class _SearchConversationRuntime
    implements WorkbenchConversationRuntimeGateway {
  _SearchConversationRuntime({this.responseFailure});

  final WorkbenchRuntimeException? responseFailure;
  final List<List<Map<String, dynamic>>> startedTools = [];
  final List<List<Map<String, dynamic>>> resumedTools = [];
  final List<({bool success, String text})> toolResponses = [];
  bool loseLocalSessionOnNextTurn = false;
  int _sessionSerial = 0;
  int _turnSerial = 0;
  int _activeTurn = 0;
  int interruptCalls = 0;
  int closeSessionCalls = 0;

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    startedTools.add(dynamicTools);
    return WorkbenchRuntimeSession(
      sessionId: 'local-${++_sessionSerial}',
      provider: 'fake-search-runtime',
      providerSessionId: 'provider-1',
    );
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async {
    expect(provider, 'fake-search-runtime');
    resumedTools.add(dynamicTools);
    return WorkbenchRuntimeSession(
      sessionId: 'local-${++_sessionSerial}',
      provider: provider,
      providerSessionId: providerSessionId,
    );
  }

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
    if (loseLocalSessionOnNextTurn) {
      loseLocalSessionOnNextTurn = false;
      throw const WorkbenchRuntimeException(
        'session_not_found',
        'Bridge local session was lost.',
      );
    }
    _activeTurn = ++_turnSerial;
    return WorkbenchRuntimeTurn(turnId: 'turn-$_activeTurn');
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    final first = _activeTurn == 1;
    return WorkbenchRuntimeEvents(
      status: 'idle',
      events: [
        if (first)
          {
            'turn_id': 'turn-1',
            'kind': 'tool_call',
            'status': 'running',
            'data': {
              'tool_call_id': 'call-search-1',
              'tool_name': WorkbenchSearchToolHost.toolName,
              'arguments': {
                'request_id': 'conversation-search-1',
                'query': '春雨',
                'scopes': ['card_library'],
              },
            },
          },
        {
          'turn_id': 'turn-$_activeTurn',
          'kind': 'message_delta',
          'status': 'running',
          'data': {'text': first ? '已找到。' : '已恢复。'},
        },
        {
          'turn_id': 'turn-$_activeTurn',
          'kind': 'turn_status',
          'status': 'completed',
          'data': <String, dynamic>{},
        },
      ],
      nextSequence: first ? 3 : 2,
    );
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {
    if (responseFailure != null) throw responseFailure!;
    toolResponses.add((success: success, text: text));
  }

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {
    interruptCalls++;
  }

  @override
  Future<void> closeSession(String sessionId) async {
    closeSessionCalls++;
  }
}
