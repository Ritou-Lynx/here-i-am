import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';

void main() {
  test('reuses one product conversation binding across ordinary turns',
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
    expect(
      coordinator.bindingFor('persona-i')?.status,
      RuntimeSessionStatus.idle,
    );
  });

  test('resumes provider thread when Bridge forgets the local session',
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
  });

  test('interrupts an active turn and persists an honest stopped reply',
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
  });

  test('runtime failure never falls through to mobile model configuration',
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

  test('readEvents failure cleans up and preserves the provider error',
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
  });

  test('cleanup interrupt failure does not replace the timeout result',
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
  });

  test('terminal persistence failure cleans up instead of reusing session',
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
  });
}

WorkbenchConversationCoordinator _coordinator(
  _FakeConversationRuntime runtime,
  List<String> replies, {
  Duration turnTimeout = const Duration(seconds: 2),
  bool failPersistence = false,
}) {
  return WorkbenchConversationCoordinator(
    runtime: runtime,
    addReply: (characterId, content) async {
      expect(characterId, 'i');
      if (failPersistence) throw StateError('persistence unavailable');
      replies.add(content);
      return replies.length;
    },
    pollInterval: Duration.zero,
    turnTimeout: turnTimeout,
  );
}

class _FakeConversationRuntime implements WorkbenchConversationRuntimeGateway {
  _FakeConversationRuntime({
    this.startFailure,
    this.interruptFailure = false,
  });

  final WorkbenchRuntimeException? startFailure;
  final bool interruptFailure;
  final List<_TurnScript> _scripts = [];
  final Completer<void> turnStarted = Completer<void>();
  final List<String> startedTurnSessionIds = [];
  final List<String> resumedProviderIds = [];
  int startSessionCalls = 0;
  int resumeSessionCalls = 0;
  int interruptCalls = 0;
  int closeSessionCalls = 0;
  int _sessionSerial = 0;
  int _turnSerial = 0;
  bool failNextStartTurn = false;
  _RunningTurn? _running;

  void enqueueCompletedReply(String reply) {
    _scripts.add(_TurnScript.completed(reply));
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

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    startSessionCalls++;
    if (startFailure != null) throw startFailure!;
    expect(dynamicTools, isEmpty);
    expect(contextManifest['conversation_id'], 'persona-i');
    _sessionSerial++;
    return WorkbenchRuntimeSession(
      sessionId: 'local-$_sessionSerial',
      providerSessionId: 'provider-thread-1',
    );
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String providerSessionId,
  }) async {
    resumeSessionCalls++;
    resumedProviderIds.add(providerSessionId);
    _sessionSerial++;
    return WorkbenchRuntimeSession(
      sessionId: 'local-$_sessionSerial',
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
    startedTurnSessionIds.add(sessionId);
    expect(input, contains('Here I am 桌面工作台中的林埃'));
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
    return _events(running.turnId, running.script.reply!, 'completed');
  }

  WorkbenchRuntimeEvents _events(
    String turnId,
    String reply,
    String terminalStatus,
  ) {
    return WorkbenchRuntimeEvents(
      status: 'idle',
      events: [
        if (reply.isNotEmpty)
          {
            'sequence': 1,
            'turn_id': turnId,
            'kind': 'message_delta',
            'status': 'running',
            'data': {'text': reply},
          },
        {
          'sequence': 2,
          'turn_id': turnId,
          'kind': 'turn_status',
          'status': terminalStatus,
          'data': <String, dynamic>{},
        },
      ],
      nextSequence: 2,
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
    if (!running.script.release.isCompleted) running.script.release.complete();
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {
    fail('ordinary conversation must not expose product write tools');
  }

  @override
  Future<void> closeSession(String sessionId) async {
    closeSessionCalls++;
  }
}

class _TurnScript {
  _TurnScript.completed(this.reply)
      : blocking = false,
        silent = false,
        readFailure = false,
        release = Completer<void>();

  _TurnScript.blocking()
      : reply = null,
        blocking = true,
        silent = false,
        readFailure = false,
        release = Completer<void>();

  _TurnScript.silent()
      : reply = null,
        blocking = false,
        silent = true,
        readFailure = false,
        release = Completer<void>();

  _TurnScript.readFailure()
      : reply = null,
        blocking = false,
        silent = false,
        readFailure = true,
        release = Completer<void>();

  final String? reply;
  final bool blocking;
  final bool silent;
  final bool readFailure;
  final Completer<void> release;
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
