import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late TaskRoomService service;
  late WorkbenchRuntimeTaskQueueTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TaskRoomService(db: db);
    tool = WorkbenchRuntimeTaskQueueTool(
      loadService: () async => service,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('dynamic definition exposes actions but no scope or authorization', () {
    const definition = WorkbenchTaskQueueToolHost.dynamicToolDefinition;
    final schema = definition['input_schema'] as Map<String, dynamic>;
    final properties = schema['properties'] as Map<String, dynamic>;

    expect(definition['name'], WorkbenchTaskQueueToolHost.toolName);
    expect(properties.keys, containsAll(['action', 'task_id', 'title', 'goal']));
    expect(properties, isNot(contains('authorization')));
    expect(properties, isNot(contains('scope')));
    expect(schema['additionalProperties'], isFalse);
  });

  test('production authorization requires explicit queue and lifecycle words',
      () {
    const factory = DesktopWorkbenchTaskQueueAuthorizationFactory();

    expect(
      factory
          .build(
            conversationId: 'persona-i',
            userText: '把这项工作作为长任务排队',
          )
          .allowedActions,
      {WorkbenchTaskQueueAction.enqueue},
    );
    expect(
      factory
          .build(
            conversationId: 'persona-i',
            userText: '暂停长任务并查看任务状态',
          )
          .allowedActions,
      {
        WorkbenchTaskQueueAction.pause,
        WorkbenchTaskQueueAction.status,
      },
    );
    expect(
      factory
          .build(conversationId: 'persona-i', userText: '今天天气怎么样')
          .allowedActions,
      isEmpty,
    );
    expect(
      factory
          .build(
            conversationId: 'persona-i',
            userText: '不要创建长任务',
          )
          .allowedActions,
      isEmpty,
    );
    expect(
      factory
          .build(
            conversationId: 'persona-i',
            userText: '不要暂停任务，只查看任务状态',
          )
          .allowedActions,
      {WorkbenchTaskQueueAction.status},
    );
    expect(
      factory
          .build(
            conversationId: 'persona-i',
            userText: "don't retry the task, only check task status",
          )
          .allowedActions,
      {WorkbenchTaskQueueAction.status},
    );
    expect(
      factory
          .build(
            conversationId: 'persona-i',
            userText: 'do not queue this long task',
          )
          .allowedActions,
      isEmpty,
    );
  });

  test('enqueue request id is durable and conflicting payload fails closed',
      () async {
    final authorization = _authorization(
      'persona-i',
      {WorkbenchTaskQueueAction.enqueue},
    );
    const payload = {
      'request_id': 'durable-runtime-request',
      'action': 'enqueue',
      'title': 'Durable idempotent task',
      'goal': 'Return one stable TaskRoom across retries and restarts',
    };

    final first = await _invoke(tool, authorization, payload);
    final repeated = await _invoke(tool, authorization, payload);
    final restartedTool = WorkbenchRuntimeTaskQueueTool(
      loadService: () async => TaskRoomService(db: db),
    );
    final afterRestart = await _invoke(
      restartedTool,
      authorization,
      payload,
    );

    final firstTask = first['task'] as Map;
    expect(first['changed'], isTrue);
    expect(repeated['changed'], isFalse);
    expect(afterRestart['changed'], isFalse);
    expect((repeated['task'] as Map)['task_id'], firstTask['task_id']);
    expect((afterRestart['task'] as Map)['task_id'], firstTask['task_id']);
    expect(await db.select(db.taskRooms).get(), hasLength(1));

    final conflict = await _invoke(restartedTool, authorization, {
      ...payload,
      'title': 'Changed title',
    });
    expect(conflict, {
      'status': 'rejected',
      'error_code': 'task_queue_request_conflict',
    });
    expect(await db.select(db.taskRooms).get(), hasLength(1));
  });

  test('host supports scoped full lifecycle and honest failure state',
      () async {
    final authorization = _authorization(
      'persona-i',
      WorkbenchTaskQueueAction.values.toSet(),
    );
    final enqueued = await _invoke(tool, authorization, {
      'request_id': 'enqueue-1',
      'action': 'enqueue',
      'title': '整理一批研究资料',
      'goal': '在后台完成有独立生命周期的资料整理',
    });
    expect(enqueued['status'], 'ok');
    final taskId = (enqueued['task'] as Map)['task_id'] as String;
    expect((enqueued['task'] as Map)['status'], 'pending');

    final room = await service.getTaskRoom(taskId);
    expect(room!.conversationId, 'persona-i');
    expect(room.executor, 'workbench_runtime');
    expect(jsonDecode(room.permissionsJson), {
      'profile_id': DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
      'scope_type': 'conversation',
      'scope_id': 'persona-i',
    });

    await service.updateTaskStatus(id: taskId, status: TaskStatus.running);
    final paused = await _invoke(tool, authorization, {
      'request_id': 'pause-1',
      'action': 'pause',
      'task_id': taskId,
    });
    expect((paused['task'] as Map)['status'], 'blocked');
    expect((paused['task'] as Map)['resumable_state'], 'paused');

    final resumed = await _invoke(tool, authorization, {
      'request_id': 'resume-1',
      'action': 'resume',
    });
    expect((resumed['task'] as Map)['status'], 'running');

    await service.updateTaskStatus(
      id: taskId,
      status: TaskStatus.failed,
      failureReason: 'provider_unavailable',
    );
    final failedStatus = await _invoke(tool, authorization, {
      'request_id': 'status-failed',
      'action': 'status',
    });
    expect((failedStatus['task'] as Map)['status'], 'failed');
    expect(
      (failedStatus['task'] as Map)['failure_reason'],
      'provider_unavailable',
    );

    final retried = await _invoke(tool, authorization, {
      'request_id': 'retry-1',
      'action': 'retry',
      'task_id': taskId,
    });
    expect((retried['task'] as Map)['status'], 'pending');
    expect((retried['task'] as Map)['retry_count'], 1);

    final cancelled = await _invoke(tool, authorization, {
      'request_id': 'cancel-1',
      'action': 'cancel',
    });
    expect((cancelled['task'] as Map)['status'], 'cancelled');
  });

  test('unknown and cross-conversation task ids are rejected identically',
      () async {
    final otherAuthorization = _authorization(
      'persona-other',
      {WorkbenchTaskQueueAction.enqueue},
    );
    final other = await _invoke(tool, otherAuthorization, {
      'request_id': 'enqueue-other',
      'action': 'enqueue',
      'title': 'Other conversation task',
      'goal': 'Must remain outside persona-i scope',
    });
    final otherId = (other['task'] as Map)['task_id'] as String;
    final authorization = _authorization(
      'persona-i',
      {WorkbenchTaskQueueAction.status},
    );

    final unknown = await _invoke(tool, authorization, {
      'request_id': 'unknown',
      'action': 'status',
      'task_id': 'does-not-exist',
    });
    final crossScope = await _invoke(tool, authorization, {
      'request_id': 'cross-scope',
      'action': 'status',
      'task_id': otherId,
    });

    expect(unknown['error_code'], 'task_not_available');
    expect(crossScope['error_code'], 'task_not_available');
    expect(unknown['status'], crossScope['status']);
  });

  test('model payload cannot add authorization or enqueue on a short turn',
      () async {
    final authorization = _authorization('persona-i', const {});
    final before = await db.select(db.taskRooms).get();

    final unauthorized = await _invoke(tool, authorization, {
      'request_id': 'not-authorized',
      'action': 'enqueue',
      'title': 'Must not be created',
      'goal': 'The model cannot grant itself queue permission',
    });
    final injected = await _invoke(tool, authorization, {
      'request_id': 'injected-auth',
      'action': 'status',
      'authorization': {'enqueue': true},
    });

    expect(unauthorized['error_code'], 'task_queue_action_not_authorized');
    expect(injected['error_code'], 'invalid_task_queue_request');
    expect(await db.select(db.taskRooms).get(), before);
  });

  test('new service instance restores running task as resumable interrupted',
      () async {
    final authorization = _authorization(
      'persona-i',
      {WorkbenchTaskQueueAction.enqueue},
    );
    final enqueued = await _invoke(tool, authorization, {
      'request_id': 'restart-enqueue',
      'action': 'enqueue',
      'title': 'Restart recovery task',
      'goal': 'Never remain falsely running after product restart',
    });
    final taskId = (enqueued['task'] as Map)['task_id'] as String;
    await service.updateTaskStatus(id: taskId, status: TaskStatus.running);

    final restartedService = TaskRoomService(db: db);
    expect(await restartedService.restoreInterruptedTaskRoomsOnce(), 1);
    final restored = await restartedService.getTaskQueueSnapshot(taskId);

    expect(restored!.status, TaskStatus.blocked);
    expect(restored.resumableState, 'interrupted');
    expect(restored.interruptedReason, 'interrupted_by_restart');
    expect(restored.belongsTo(authorization.scope), isTrue);
  });

  test('conversation coordinator registers and dispatches production queue tool',
      () async {
    final runtime = _QueueConversationRuntime({
      'request_id': 'runtime-enqueue',
      'action': 'enqueue',
      'title': 'Runtime reachable task',
      'goal': 'Prove the production conversation coordinator can reach P6',
    });
    final replies = <String>[];
    final coordinator = WorkbenchConversationCoordinator(
      runtime: runtime,
      taskQueueTool: tool,
      addReply: (_, content) async {
        replies.add(content);
        return replies.length;
      },
      pollInterval: Duration.zero,
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '把这项工作作为长任务排队',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.startedTools.single, hasLength(1));
    expect(
      runtime.startedTools.single.single['name'],
      WorkbenchTaskQueueToolHost.toolName,
    );
    expect(runtime.toolResponses.single.success, isTrue);
    expect(await db.select(db.taskRooms).get(), hasLength(1));
    expect(replies.single, '长任务已排队。');
  });

  test('coordinator rejects a model-enqueued TaskRoom on ordinary short chat',
      () async {
    final runtime = _QueueConversationRuntime(
      {
        'request_id': 'runtime-overreach',
        'action': 'enqueue',
        'title': 'Unauthorized task',
        'goal': 'Must not exist',
      },
      reply: '未执行队列操作。',
    );
    final coordinator = WorkbenchConversationCoordinator(
      runtime: runtime,
      taskQueueTool: tool,
      addReply: (_, __) async => 1,
      pollInterval: Duration.zero,
    );

    final result = await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '今天天气怎么样？',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.toolResponses.single.success, isFalse);
    expect(
      (jsonDecode(runtime.toolResponses.single.text) as Map)['error_code'],
      'task_queue_action_not_authorized',
    );
    expect(await db.select(db.taskRooms).get(), isEmpty);
    expect(runtime.startedInputs.single, contains('没有授权任何长任务队列动作'));
  });

  test('coordinator rejects a specifically negated enqueue without a write',
      () async {
    final runtime = _QueueConversationRuntime(
      {
        'request_id': 'runtime-negated-enqueue',
        'action': 'enqueue',
        'title': 'Negated task',
        'goal': 'Must not exist',
      },
      reply: '未执行队列操作。',
    );
    final coordinator = WorkbenchConversationCoordinator(
      runtime: runtime,
      taskQueueTool: tool,
      addReply: (_, __) async => 1,
      pollInterval: Duration.zero,
    );

    await coordinator.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '不要创建长任务，只查看任务状态',
    );

    expect(runtime.toolResponses.single.success, isFalse);
    expect(
      (jsonDecode(runtime.toolResponses.single.text) as Map)['error_code'],
      'task_queue_action_not_authorized',
    );
    expect(await db.select(db.taskRooms).get(), isEmpty);
    expect(runtime.startedInputs.single, contains('只授权长任务队列动作：status'));
  });
}

WorkbenchTaskQueueAuthorization _authorization(
  String conversationId,
  Set<WorkbenchTaskQueueAction> actions,
) =>
    WorkbenchTaskQueueAuthorization(
      profileId: DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
      conversationId: conversationId,
      allowedActions: actions,
    );

Future<Map<String, dynamic>> _invoke(
  WorkbenchRuntimeTaskQueueTool tool,
  WorkbenchTaskQueueAuthorization authorization,
  Map<String, dynamic> payload,
) async {
  final result = await tool.invoke(payload, authorization: authorization);
  return Map<String, dynamic>.from(jsonDecode(result.text) as Map);
}

class _QueueConversationRuntime
    implements WorkbenchConversationRuntimeGateway {
  _QueueConversationRuntime(
    this.arguments, {
    this.reply = '长任务已排队。',
  });

  final Map<String, dynamic> arguments;
  final String reply;
  final List<List<Map<String, dynamic>>> startedTools = [];
  final List<String> startedInputs = [];
  final List<({bool success, String text})> toolResponses = [];
  int _turnSerial = 0;
  bool _delivered = false;

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    startedTools.add(dynamicTools);
    return const WorkbenchRuntimeSession(
      sessionId: 'local-queue-1',
      provider: 'fake-queue-runtime',
      providerSessionId: 'provider-queue-1',
    );
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async =>
      WorkbenchRuntimeSession(
        sessionId: 'local-queue-resumed',
        provider: provider,
        providerSessionId: providerSessionId,
      );

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
    startedInputs.add(input);
    return WorkbenchRuntimeTurn(turnId: 'turn-${++_turnSerial}');
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    if (_delivered) {
      return WorkbenchRuntimeEvents(
        status: 'idle',
        events: const [],
        nextSequence: afterSequence,
      );
    }
    _delivered = true;
    final turnId = 'turn-$_turnSerial';
    return WorkbenchRuntimeEvents(
      status: 'idle',
      events: [
        {
          'turn_id': turnId,
          'kind': 'tool_call',
          'status': 'running',
          'data': {
            'tool_call_id': 'call-queue-1',
            'tool_name': WorkbenchTaskQueueToolHost.toolName,
            'arguments': arguments,
          },
        },
        {
          'turn_id': turnId,
          'kind': 'message_delta',
          'status': 'running',
          'data': {'text': reply},
        },
        {
          'turn_id': turnId,
          'kind': 'turn_status',
          'status': 'completed',
          'data': <String, dynamic>{},
        },
      ],
      nextSequence: 3,
    );
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {
    toolResponses.add((success: success, text: text));
  }

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {}

  @override
  Future<void> closeSession(String sessionId) async {}
}
