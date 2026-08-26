import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/context/workbench_relationship_context.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_binding_store.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';

void main() {
  test('injects host-owned relationship context into the production turn path',
      () async {
    final runtime = _FakeConversationRuntime()..enqueueCompletedReply('我记得');
    final replies = <String>[];
    final coordinator = _coordinator(
      runtime,
      replies,
      relationshipContextProvider: const _StaticRelationshipContextProvider(
        WorkbenchRelationshipContext(
          scopeStatus: WorkbenchContextLoadStatus.available,
          personaStatus: WorkbenchContextLoadStatus.available,
          recentStatus: WorkbenchContextLoadStatus.empty,
          dreamingStatus: WorkbenchContextLoadStatus.available,
          characterId: 'i',
          personaPrompt: '# 你是林埃',
          dreaming: WorkbenchDreamingRecall(
            episodes: [
              WorkbenchDreamingEpisode(
                id: 'episode-real',
                narrative: '我们一起记得的事',
                score: 42,
              ),
            ],
          ),
        ),
      ),
    );

    final result = await coordinator.send(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '你还记得吗',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.startedTurnInputs.single, contains('# 你是林埃'));
    expect(runtime.startedTurnInputs.single, contains('episode/episode-real'));
    expect(runtime.startedTurnInputs.single, contains('not User-truth'));
  });

  test('relationship backend failure does not block an ordinary reply',
      () async {
    final runtime = _FakeConversationRuntime()..enqueueCompletedReply('我在');
    final coordinator = _coordinator(
      runtime,
      <String>[],
      relationshipContextProvider: _ThrowingRelationshipContextProvider(),
    );

    final result = await coordinator.send(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '在吗',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.startedTurnInputs.single,
        contains('dreaming_status: unavailable'));
    expect(runtime.startedTurnInputs.single,
        contains('context_backend_unavailable'));
  });

  test('hanging relationship backend is bounded and ordinary reply continues',
      () async {
    final runtime = _FakeConversationRuntime()..enqueueCompletedReply('没有卡住');
    final coordinator = _coordinator(
      runtime,
      <String>[],
      relationshipContextProvider: _HangingRelationshipContextProvider(),
      relationshipContextTimeout: const Duration(milliseconds: 5),
    );

    final result = await coordinator.send(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '后端不要阻断聊天',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.startedTurnInputs.single,
        contains('dreaming_status: unavailable'));
  });

  test('rejects unsupported write tool and payload self-authorization',
      () async {
    final runtime = _FakeConversationRuntime()
      ..enqueueToolCall(
        toolName: 'record_explicit_memory',
        arguments: const {
          'authorization': 'model_granted',
          'content': 'silently write this',
        },
        reply: '没有写入',
      );
    final result = await _coordinator(runtime, <String>[]).send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '不要记录，只是聊天',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.toolResponses, hasLength(1));
    expect(runtime.toolResponses.single.success, isFalse);
    expect(
      jsonDecode(runtime.toolResponses.single.text)['error_code'],
      'unsupported_product_tool',
    );
  });

  test(
    'reuses one product conversation binding across ordinary turns',
    () async {
      final runtime = _FakeConversationRuntime()
        ..enqueueCompletedReply('第一条回复')
        ..enqueueCompletedReply('第二条回复');
      final replies = <String>[];
      final coordinator = _coordinator(runtime, replies);

      final first = await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '你好',
      );
      final second = await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '继续说',
      );

      expect(first.outcome, WorkbenchConversationOutcome.completed);
      expect(second.outcome, WorkbenchConversationOutcome.completed);
      expect(replies, ['第一条回复', '第二条回复']);
      expect(runtime.startSessionCalls, 1);
      expect(runtime.resumeSessionCalls, 0);
      expect(runtime.interruptCalls, 0);
      expect(runtime.closeSessionCalls, 0);
      expect(runtime.startedTurnSessionIds, ['local-1', 'local-1']);
      expect(coordinator.bindingFor('persona-i')?.provider, 'fake-runtime');
      expect(
        coordinator.bindingDurability,
        WorkbenchBindingDurability.processMemory,
      );
      expect(
        coordinator.bindingFor('persona-i')?.status,
        RuntimeSessionStatus.idle,
      );
    },
  );

  test(
    'resumes provider thread when Bridge forgets the local session',
    () async {
      final runtime = _FakeConversationRuntime()
        ..enqueueCompletedReply('初次回复')
        ..enqueueCompletedReply('恢复后的回复');
      final replies = <String>[];
      final coordinator = _coordinator(runtime, replies);

      await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '第一轮',
      );
      runtime.failNextStartTurn = true;
      await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: 'Bridge 重启后的第二轮',
      );

      expect(runtime.startSessionCalls, 1);
      expect(runtime.resumeSessionCalls, 1);
      expect(runtime.resumedProviderIds, ['provider-thread-1']);
      expect(runtime.startedTurnSessionIds, ['local-1', 'local-2']);
      expect(replies.last, '恢复后的回复');
      expect(
        coordinator.bindingFor('persona-i')?.providerSessionId,
        'provider-thread-1',
      );
    },
  );

  test(
      'recreated coordinator resumes a stored binding without restoring a '
      'local session', () async {
    final runtime = _FakeConversationRuntime()
      ..enqueueCompletedReply('第一进程内实例')
      ..enqueueCompletedReply('重建 coordinator 后');
    final store = InMemoryWorkbenchRuntimeBindingStore();
    final replies = <String>[];

    await _coordinator(
      runtime,
      replies,
      bindingStore: store,
    ).send(conversationId: 'persona-i', characterId: 'i', userText: '第一轮');
    final recreated = _coordinator(runtime, replies, bindingStore: store);
    final result = await recreated.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '重新创建 coordinator',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.startSessionCalls, 1);
    expect(runtime.resumeSessionCalls, 1);
    expect(runtime.startedTurnSessionIds, ['local-1', 'local-2']);
    expect(
      recreated.bindingDurability,
      WorkbenchBindingDurability.processMemory,
      reason: 'sharing a volatile store must not claim app restart recovery',
    );
  });

  test('closed stored binding starts a new provider session', () async {
    final store = InMemoryWorkbenchRuntimeBindingStore();
    final createdAt = DateTime.utc(2026, 8, 23, 10);
    final closed = RuntimeSessionBinding(
      id: 'closed-binding',
      conversationId: 'persona-i',
      provider: 'old-provider',
      providerSessionId: 'old-thread',
      profile: RuntimeProfile.workbench,
      scopeType: RuntimeScopeType.surface,
      scopeId: 'desktop_chat',
      status: RuntimeSessionStatus.closed,
      createdAt: createdAt,
      lastActiveAt: createdAt,
      closedAt: createdAt,
    );
    await store.write(closed);
    final runtime = _FakeConversationRuntime()..enqueueCompletedReply('全新会话');

    final result = await _coordinator(
      runtime,
      <String>[],
      bindingStore: store,
    ).send(conversationId: 'persona-i', characterId: 'i', userText: '重新开始');

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.startSessionCalls, 1);
    expect(runtime.resumeSessionCalls, 0);
  });

  test('stored active binding degrades instead of inventing turn recovery',
      () async {
    final store = InMemoryWorkbenchRuntimeBindingStore();
    final createdAt = DateTime.utc(2026, 8, 23, 10);
    await store.write(RuntimeSessionBinding(
      id: 'active-binding',
      conversationId: 'persona-i',
      provider: 'fake-runtime',
      providerSessionId: 'provider-thread-active',
      profile: RuntimeProfile.workbench,
      scopeType: RuntimeScopeType.surface,
      scopeId: 'desktop_chat',
      status: RuntimeSessionStatus.active,
      createdAt: createdAt,
      lastActiveAt: createdAt,
    ));
    final runtime = _FakeConversationRuntime();
    final replies = <String>[];

    final result = await _coordinator(
      runtime,
      replies,
      bindingStore: store,
    ).send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '不要猜上次 turn 是否结束',
    );

    expect(result.errorCode, 'runtime_recovery_requires_reconciliation');
    expect(replies.single, contains('结束状态无法确认'));
    expect(runtime.startSessionCalls, 0);
    expect(runtime.resumeSessionCalls, 0);
    expect(
      (await store.read('persona-i'))?.status,
      RuntimeSessionStatus.unavailable,
    );
  });

  test(
    'interrupts an active turn and persists an honest stopped reply',
    () async {
      final runtime = _FakeConversationRuntime()..blockUntilInterrupted();
      final replies = <String>[];
      final coordinator = _coordinator(runtime, replies);

      final pending = coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '慢慢回答',
      );
      await runtime.turnStarted.future;

      expect(await coordinator.stop('persona-i'), isTrue);
      final result = await pending;

      expect(result.outcome, WorkbenchConversationOutcome.interrupted);
      expect(result.errorCode, 'runtime_interrupted');
      expect(replies.single, '已停止这次电脑回复。');
      expect(runtime.interruptCalls, 1);
      expect(runtime.closeSessionCalls, 0);
      expect(
        coordinator.bindingFor('persona-i')?.status,
        RuntimeSessionStatus.interrupted,
      );
    },
  );

  test(
    'pending stop is delivered once after the turn receives its id',
    () async {
      final startGate = Completer<void>();
      final runtime = _FakeConversationRuntime(startSessionGate: startGate)
        ..blockUntilInterrupted();
      final replies = <String>[];
      final coordinator = _coordinator(runtime, replies);

      final pending = coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '启动时就停止',
      );
      while (runtime.startSessionCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await coordinator.stop('persona-i'), isTrue);
      expect(await coordinator.stop('persona-i'), isTrue);
      startGate.complete();
      final result = await pending;

      expect(result.outcome, WorkbenchConversationOutcome.interrupted);
      expect(runtime.interruptCalls, 1);
    },
  );

  test(
    'failed stop abandons the local session with an honest result',
    () async {
      final runtime = _FakeConversationRuntime(interruptFailure: true)
        ..enqueueSilentTurn();
      final replies = <String>[];
      final coordinator = _coordinator(runtime, replies);

      final pending = coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '停止后不要假装成功',
      );
      await runtime.turnStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(await coordinator.stop('persona-i'), isFalse);
      final result = await pending;

      expect(result.errorCode, 'runtime_stop_unconfirmed');
      expect(replies.single, contains('没能确认'));
      expect(
        runtime.interruptCalls,
        2,
        reason: 'cleanup retries once after the explicit stop failed',
      );
      expect(runtime.closeSessionCalls, 1);
      expect(
        coordinator.bindingFor('persona-i')?.status,
        RuntimeSessionStatus.unavailable,
      );
    },
  );

  test('hanging stop control is bounded and reported as unconfirmed', () async {
    final runtime = _FakeConversationRuntime(interruptHangs: true)
      ..enqueueSilentTurn();
    final replies = <String>[];
    final coordinator = _coordinator(
      runtime,
      replies,
      controlTimeout: const Duration(milliseconds: 10),
    );

    final pending = coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '停止控制面也不能无限等待',
    );
    await runtime.turnStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(await coordinator.stop('persona-i'), isFalse);
    final result = await pending;

    expect(result.errorCode, 'runtime_stop_unconfirmed');
    expect(replies.single, contains('没能确认'));
    expect(runtime.interruptCalls, 2);
    expect(runtime.closeSessionCalls, 1);
  });

  test(
    'runtime failure never falls through to mobile model configuration',
    () async {
      final runtime = _FakeConversationRuntime(
        startFailure: const WorkbenchRuntimeException(
          'experimental_runtime_disabled',
          'disabled',
        ),
      );
      final replies = <String>[];
      final coordinator = _coordinator(runtime, replies);

      final result = await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '普通对话',
      );

      expect(result.outcome, WorkbenchConversationOutcome.failed);
      expect(result.errorCode, 'experimental_runtime_disabled');
      expect(replies.single, contains('没有发送到手机模型'));
      expect(runtime.startSessionCalls, 1);
    },
  );

  test('binding store failure closes an otherwise untracked local session',
      () async {
    final runtime = _FakeConversationRuntime();
    final replies = <String>[];
    final coordinator = _coordinator(
      runtime,
      replies,
      bindingStore: _FailingBindingStore(failOnWrite: 1),
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '不能留下无主 session',
    );

    expect(result.errorCode, 'runtime_binding_store_unavailable');
    expect(runtime.closeSessionCalls, 1);
    expect(runtime.startedTurnSessionIds, isEmpty);
    expect(coordinator.bindingFor('persona-i'), isNull);
  });

  test('terminal store failure keeps the persisted reply but degrades reuse',
      () async {
    final runtime = _FakeConversationRuntime()
      ..enqueueCompletedReply('已经可靠写入聊天');
    final replies = <String>[];
    final coordinator = _coordinator(
      runtime,
      replies,
      bindingStore: _FailingBindingStore(failOnWrite: 3),
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '终态连续性写失败',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(result.errorCode, 'runtime_continuity_degraded');
    expect(replies.single, '已经可靠写入聊天');
    expect(runtime.closeSessionCalls, 2);
    expect(
      coordinator.bindingFor('persona-i')?.status,
      RuntimeSessionStatus.unavailable,
    );
  });

  test('timeout interrupts and closes the abandoned local turn', () async {
    final runtime = _FakeConversationRuntime()..enqueueSilentTurn();
    final replies = <String>[];
    final coordinator = _coordinator(
      runtime,
      replies,
      turnTimeout: const Duration(milliseconds: 5),
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '不要永远等下去',
    );

    expect(result.errorCode, 'runtime_timeout');
    expect(replies.single, contains('等待超时'));
    expect(runtime.interruptCalls, 1);
    expect(runtime.closeSessionCalls, 1);
    expect(
      coordinator.bindingFor('persona-i')?.status,
      RuntimeSessionStatus.unavailable,
    );

    runtime.enqueueCompletedReply('清理后恢复');
    final resumed = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '下一轮',
    );
    expect(resumed.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.resumeSessionCalls, 1);
    expect(runtime.startedTurnSessionIds.last, 'local-2');
  });

  test('one hanging event read is bounded by the turn timeout', () async {
    final runtime = _FakeConversationRuntime()..enqueueBlockingRead();
    final replies = <String>[];
    final coordinator = _coordinator(
      runtime,
      replies,
      turnTimeout: const Duration(milliseconds: 5),
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '事件读取也必须有总时限',
    );

    expect(result.errorCode, 'runtime_timeout');
    expect(runtime.interruptCalls, 1);
    expect(runtime.closeSessionCalls, 1);
  });

  test('provider mismatch during resume fails closed', () async {
    final runtime = _FakeConversationRuntime(resumeProvider: 'other-runtime')
      ..enqueueCompletedReply('第一轮')
      ..enqueueCompletedReply('不应执行');
    final replies = <String>[];
    final coordinator = _coordinator(runtime, replies);

    await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '第一轮',
    );
    runtime.failNextStartTurn = true;
    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '恢复时换 provider',
    );

    expect(result.errorCode, 'runtime_provider_mismatch');
    expect(runtime.closeSessionCalls, 2,
        reason: 'both the mismatched resume and stale local session close');
    expect(runtime.startedTurnSessionIds, ['local-1']);
  });

  test('failed start after resume closes the fresh local session', () async {
    final runtime = _FakeConversationRuntime(
      resumedStartFailure: const WorkbenchRuntimeException(
        'active_turn_conflict',
        'provider thread is still active',
      ),
    )..enqueueCompletedReply('第一轮');
    final replies = <String>[];
    final coordinator = _coordinator(runtime, replies);

    await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '第一轮',
    );
    runtime.failNextStartTurn = true;
    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '恢复后仍有活动 turn',
    );

    expect(result.errorCode, 'active_turn_conflict');
    expect(runtime.closeSessionCalls, 1);
    expect(runtime.startedTurnSessionIds, ['local-1']);
    expect(
      coordinator.bindingFor('persona-i')?.status,
      RuntimeSessionStatus.unavailable,
    );
  });

  test(
    'readEvents failure cleans up and preserves the provider error',
    () async {
      final runtime = _FakeConversationRuntime()..enqueueReadFailure();
      final replies = <String>[];
      final coordinator = _coordinator(runtime, replies);

      final result = await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '读取事件失败',
      );

      expect(result.errorCode, 'provider_error');
      expect(runtime.interruptCalls, 1);
      expect(runtime.closeSessionCalls, 1);
      expect(
        coordinator.bindingFor('persona-i')?.status,
        RuntimeSessionStatus.unavailable,
      );
    },
  );

  test(
    'cleanup interrupt failure does not replace the timeout result',
    () async {
      final runtime = _FakeConversationRuntime(interruptFailure: true)
        ..enqueueSilentTurn();
      final replies = <String>[];
      final coordinator = _coordinator(
        runtime,
        replies,
        turnTimeout: const Duration(milliseconds: 5),
      );

      final result = await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '清理失败也要保留原错误',
      );

      expect(result.errorCode, 'runtime_timeout');
      expect(runtime.interruptCalls, 1);
      expect(runtime.closeSessionCalls, 1);
    },
  );

  test(
    'terminal persistence failure cleans up instead of reusing session',
    () async {
      final runtime = _FakeConversationRuntime()
        ..enqueueCompletedReply('无法落库的回复');
      final coordinator = _coordinator(
        runtime,
        <String>[],
        failPersistence: true,
      );

      final result = await coordinator.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: '请回复',
      );

      expect(result.outcome, WorkbenchConversationOutcome.failed);
      expect(result.errorCode, 'chat_persistence_failed');
      expect(runtime.interruptCalls, 1);
      expect(runtime.closeSessionCalls, 1);
      expect(
        coordinator.bindingFor('persona-i')?.status,
        RuntimeSessionStatus.unavailable,
      );
    },
  );
}

WorkbenchConversationCoordinator _coordinator(
  _FakeConversationRuntime runtime,
  List<String> replies, {
  Duration turnTimeout = const Duration(seconds: 2),
  Duration controlTimeout = const Duration(milliseconds: 25),
  bool failPersistence = false,
  WorkbenchRuntimeBindingStore? bindingStore,
  WorkbenchRelationshipContextProvider? relationshipContextProvider,
  Duration relationshipContextTimeout = const Duration(seconds: 2),
}) {
  return WorkbenchConversationCoordinator(
    runtime: runtime,
    bindingStore: bindingStore,
    relationshipContextProvider: relationshipContextProvider,
    relationshipContextTimeout: relationshipContextTimeout,
    addReply: (characterId, content) async {
      expect(characterId, 'i');
      if (failPersistence) throw StateError('persistence unavailable');
      replies.add(content);
      return replies.length;
    },
    pollInterval: Duration.zero,
    turnTimeout: turnTimeout,
    controlTimeout: controlTimeout,
  );
}

class _FakeConversationRuntime implements WorkbenchConversationRuntimeGateway {
  _FakeConversationRuntime({
    this.startFailure,
    this.interruptFailure = false,
    this.interruptHangs = false,
    this.startSessionGate,
    this.resumeProvider,
    this.resumedStartFailure,
  });

  final WorkbenchRuntimeException? startFailure;
  final bool interruptFailure;
  final bool interruptHangs;
  final Completer<void>? startSessionGate;
  final String? resumeProvider;
  final WorkbenchRuntimeException? resumedStartFailure;
  final List<_TurnScript> _scripts = [];
  final Completer<void> turnStarted = Completer<void>();
  final List<String> startedTurnSessionIds = [];
  final List<String> startedTurnInputs = [];
  final List<String> resumedProviderIds = [];
  final List<_ToolResponse> toolResponses = [];
  int startSessionCalls = 0;
  int resumeSessionCalls = 0;
  int interruptCalls = 0;
  int closeSessionCalls = 0;
  int _sessionSerial = 0;
  int _turnSerial = 0;
  bool failNextStartTurn = false;
  final Completer<void> _interruptGate = Completer<void>();
  _RunningTurn? _running;

  void enqueueCompletedReply(String reply) {
    _scripts.add(_TurnScript.completed(reply));
  }

  void enqueueToolCall({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String reply,
  }) {
    _scripts.add(_TurnScript.toolCall(toolName, arguments, reply));
  }

  void blockUntilInterrupted() {
    _scripts.add(_TurnScript.blocking());
  }

  void enqueueSilentTurn() {
    _scripts.add(_TurnScript.silent());
  }

  void enqueueReadFailure() {
    _scripts.add(_TurnScript.readFailure());
  }

  void enqueueBlockingRead() {
    _scripts.add(_TurnScript.blockingRead());
  }

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    startSessionCalls++;
    if (startSessionGate != null) await startSessionGate!.future;
    if (startFailure != null) throw startFailure!;
    expect(dynamicTools, isEmpty);
    expect(contextManifest['conversation_id'], startsWith('persona'));
    _sessionSerial++;
    return WorkbenchRuntimeSession(
      sessionId: 'local-$_sessionSerial',
      provider: 'fake-runtime',
      providerSessionId: 'provider-thread-1',
    );
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async {
    expect(provider, 'fake-runtime');
    expect(dynamicTools, isEmpty);
    resumeSessionCalls++;
    resumedProviderIds.add(providerSessionId);
    _sessionSerial++;
    return WorkbenchRuntimeSession(
      sessionId: 'local-$_sessionSerial',
      provider: resumeProvider ?? provider,
      providerSessionId: providerSessionId,
    );
  }

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
    if (failNextStartTurn) {
      failNextStartTurn = false;
      throw const WorkbenchRuntimeException(
        'session_not_found',
        'local session was lost',
      );
    }
    if (sessionId != 'local-1' && resumedStartFailure != null) {
      throw resumedStartFailure!;
    }
    startedTurnSessionIds.add(sessionId);
    startedTurnInputs.add(input);
    expect(input, contains('Here I am 桌面工作台'));
    final turnId = 'turn-${++_turnSerial}';
    _running = _RunningTurn(
      sessionId: sessionId,
      turnId: turnId,
      script: _scripts.removeAt(0),
    );
    if (!turnStarted.isCompleted) turnStarted.complete();
    return WorkbenchRuntimeTurn(turnId: turnId);
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    final running = _running!;
    expect(sessionId, running.sessionId);
    if (running.script.readFailure) {
      throw const WorkbenchRuntimeException(
        'provider_error',
        'event stream failed',
      );
    }
    if (running.script.blockingRead) {
      await running.script.release.future;
    }
    if (running.script.silent) {
      return WorkbenchRuntimeEvents(
        status: 'running',
        events: const [],
        nextSequence: afterSequence,
      );
    }
    if (running.script.blocking) {
      await running.script.release.future;
      return _events(running.turnId, '', 'interrupted');
    }
    if (running.delivered) {
      return WorkbenchRuntimeEvents(
        status: 'idle',
        events: const [],
        nextSequence: afterSequence,
      );
    }
    running.delivered = true;
    return _events(
      running.turnId,
      running.script.reply!,
      'completed',
      toolName: running.script.toolName,
      toolArguments: running.script.toolArguments,
    );
  }

  WorkbenchRuntimeEvents _events(
    String turnId,
    String reply,
    String terminalStatus, {
    String? toolName,
    Map<String, dynamic>? toolArguments,
  }) {
    return WorkbenchRuntimeEvents(
      status: 'idle',
      events: [
        if (toolName != null)
          {
            'sequence': 1,
            'turn_id': turnId,
            'kind': 'tool_call',
            'status': 'running',
            'data': {
              'tool_call_id': 'tool-call-1',
              'tool_name': toolName,
              'arguments': toolArguments,
            },
          },
        if (reply.isNotEmpty)
          {
            'sequence': toolName == null ? 1 : 2,
            'turn_id': turnId,
            'kind': 'message_delta',
            'status': 'running',
            'data': {'text': reply},
          },
        {
          'sequence': toolName == null ? 2 : 3,
          'turn_id': turnId,
          'kind': 'turn_status',
          'status': terminalStatus,
          'data': <String, dynamic>{},
        },
      ],
      nextSequence: toolName == null ? 2 : 3,
    );
  }

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {
    interruptCalls++;
    final running = _running!;
    expect(sessionId, running.sessionId);
    expect(turnId, running.turnId);
    if (interruptFailure) {
      throw const WorkbenchRuntimeException(
        'runtime_unavailable',
        'interrupt failed',
      );
    }
    if (interruptHangs) await _interruptGate.future;
    if (!running.script.release.isCompleted) running.script.release.complete();
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {
    toolResponses.add(_ToolResponse(
      toolCallId: toolCallId,
      success: success,
      text: text,
    ));
  }

  @override
  Future<void> closeSession(String sessionId) async {
    closeSessionCalls++;
  }
}

class _TurnScript {
  _TurnScript.completed(this.reply)
      : blocking = false,
        blockingRead = false,
        silent = false,
        readFailure = false,
        toolName = null,
        toolArguments = null,
        release = Completer<void>();

  _TurnScript.toolCall(this.toolName, this.toolArguments, this.reply)
      : blocking = false,
        blockingRead = false,
        silent = false,
        readFailure = false,
        release = Completer<void>();

  _TurnScript.blocking()
      : reply = null,
        blocking = true,
        blockingRead = false,
        silent = false,
        readFailure = false,
        toolName = null,
        toolArguments = null,
        release = Completer<void>();

  _TurnScript.silent()
      : reply = null,
        blocking = false,
        blockingRead = false,
        silent = true,
        readFailure = false,
        toolName = null,
        toolArguments = null,
        release = Completer<void>();

  _TurnScript.readFailure()
      : reply = null,
        blocking = false,
        blockingRead = false,
        silent = false,
        readFailure = true,
        toolName = null,
        toolArguments = null,
        release = Completer<void>();

  _TurnScript.blockingRead()
      : reply = null,
        blocking = false,
        blockingRead = true,
        silent = false,
        readFailure = false,
        toolName = null,
        toolArguments = null,
        release = Completer<void>();

  final String? reply;
  final bool blocking;
  final bool blockingRead;
  final bool silent;
  final bool readFailure;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final Completer<void> release;
}

class _ToolResponse {
  const _ToolResponse({
    required this.toolCallId,
    required this.success,
    required this.text,
  });

  final String toolCallId;
  final bool success;
  final String text;
}

class _StaticRelationshipContextProvider
    implements WorkbenchRelationshipContextProvider {
  const _StaticRelationshipContextProvider(this.context);

  final WorkbenchRelationshipContext context;

  @override
  Future<WorkbenchRelationshipContext> assemble({
    required String conversationId,
    required String characterId,
    required String userText,
  }) async =>
      context;
}

class _ThrowingRelationshipContextProvider
    implements WorkbenchRelationshipContextProvider {
  @override
  Future<WorkbenchRelationshipContext> assemble({
    required String conversationId,
    required String characterId,
    required String userText,
  }) =>
      Future.error(StateError('backend unavailable'));
}

class _HangingRelationshipContextProvider
    implements WorkbenchRelationshipContextProvider {
  @override
  Future<WorkbenchRelationshipContext> assemble({
    required String conversationId,
    required String characterId,
    required String userText,
  }) =>
      Completer<WorkbenchRelationshipContext>().future;
}

class _RunningTurn {
  _RunningTurn({
    required this.sessionId,
    required this.turnId,
    required this.script,
  });

  final String sessionId;
  final String turnId;
  final _TurnScript script;
  bool delivered = false;
}

class _FailingBindingStore implements WorkbenchRuntimeBindingStore {
  _FailingBindingStore({required this.failOnWrite});

  final int failOnWrite;
  final Map<String, RuntimeSessionBinding> _bindings = {};
  int _writes = 0;

  @override
  WorkbenchBindingDurability get durability =>
      WorkbenchBindingDurability.applicationRestart;

  @override
  Future<RuntimeSessionBinding?> read(String conversationId) async =>
      _bindings[conversationId];

  @override
  Future<void> write(RuntimeSessionBinding binding) async {
    _writes++;
    if (_writes == failOnWrite) throw StateError('store unavailable');
    _bindings[binding.conversationId] = binding;
  }
}
