import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';

void main() {
  test('host close returns unknown when an interrupted turn never settles',
      () async {
    final runtime = _HangingRuntime();
    final coordinator = WorkbenchConversationCoordinator(
      runtime: runtime,
      addReply: (_, __) async => 1,
      turnTimeout: const Duration(minutes: 1),
      controlTimeout: const Duration(milliseconds: 1),
      hostCloseTimeout: const Duration(milliseconds: 10),
    );

    final send = coordinator.send(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '仍在进行的回复',
    );
    await runtime.readStarted.future;

    expect(await coordinator.closeForHostLifecycle(), isFalse);
    expect(runtime.interrupts, 1);
    expect(runtime.closes, 0);

    runtime.release(const WorkbenchRuntimeEvents(
      status: 'ok',
      nextSequence: 1,
      events: [
        {
          'kind': 'turn_status',
          'turn_id': 'turn-1',
          'status': 'interrupted',
          'data': <String, dynamic>{},
        },
      ],
    ));
    await send;
  });
}

class _HangingRuntime implements WorkbenchConversationRuntimeGateway {
  final readStarted = Completer<void>();
  final _events = Completer<WorkbenchRuntimeEvents>();
  int interrupts = 0;
  int closes = 0;

  void release(WorkbenchRuntimeEvents events) => _events.complete(events);

  @override
  Future<void> closeSession(String sessionId) async {
    closes++;
  }

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {
    interrupts++;
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) {
    if (!readStarted.isCompleted) readStarted.complete();
    return _events.future;
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {}

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) =>
      throw UnimplementedError();

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async =>
      const WorkbenchRuntimeSession(
        sessionId: 'session-1',
        provider: 'fake',
        providerSessionId: 'provider-1',
      );

  @override
  Future<WorkbenchRuntimeTurn> startTurn(
          String sessionId, String input) async =>
      const WorkbenchRuntimeTurn(turnId: 'turn-1');
}
