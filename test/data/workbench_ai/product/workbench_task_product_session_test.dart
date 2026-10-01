import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/product/workbench_task_product_session.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';
import 'package:memex/db/app_database.dart';

import '../task_queue/workbench_task_queue_execution_test.dart'
    show FakeRuntime;

void main() {
  test('sessions retain separate services and share one local owner', () async {
    final firstDb = AppDatabase.forTesting(NativeDatabase.memory());
    final secondDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(firstDb.close);
    addTearDown(secondDb.close);
    final first = _session(TaskRoomService(db: firstDb), FakeRuntime());
    final second = _session(TaskRoomService(db: secondDb), FakeRuntime());
    expect(identical(first.execution, first.execution), isTrue);
    expect(identical(first.taskQueueTool, first.taskQueueTool), isTrue);
    expect(identical(first.lifecycleOwner, first.lifecycleOwner), isTrue);
    expect(identical(first.lifecycleOwner, second.lifecycleOwner), isFalse);

    final result =
        await _invoke(first, _authorization('first'), _enqueue('one'));
    expect(result['status'], 'ok');
    expect(await firstDb.select(firstDb.taskRooms).get(), hasLength(1));
    expect(await secondDb.select(secondDb.taskRooms).get(), isEmpty);
  });

  test('construction and rejected binding do not start execution or write',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final runtime = FakeRuntime();
    final session = _session(TaskRoomService(db: db), runtime, accepts: false);
    expect(runtime.sessions, isEmpty);
    expect(await db.select(db.taskRooms).get(), isEmpty);

    final result =
        await _rawInvoke(session, _authorization('first'), _enqueue('no'));
    expect(jsonDecode(result.text), {
      'status': 'failed',
      'error_code': 'task_queue_session_unavailable',
    });
    expect(runtime.sessions, isEmpty);
    expect(await db.select(db.taskRooms).get(), isEmpty);
  });

  test('quiesce fences old tool references and drains an accepted await',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final gate = Completer<void>();
    final service = _DelayedService(db, gate);
    final session = _session(service, FakeRuntime());
    final oldTool = session.taskQueueTool;
    final authorization = _authorization('first');
    final accepted =
        oldTool.invoke(_enqueue('accepted'), authorization: authorization);
    await service.entered.future;
    final queued =
        oldTool.invoke(_enqueue('queued'), authorization: authorization);

    final quiescing = session.quiesce();
    var drained = false;
    unawaited(quiescing.then((_) => drained = true));
    final rejected = await oldTool.invoke(_enqueue('rejected'),
        authorization: authorization);
    expect(jsonDecode(rejected.text)['error_code'],
        'task_queue_session_unavailable');
    expect(await db.select(db.taskRooms).get(), isEmpty);
    expect(drained, isFalse);

    gate.complete();
    expect((await _decode(await accepted))['status'], 'ok');
    expect(jsonDecode((await queued).text)['error_code'],
        'task_queue_session_unavailable');
    await quiescing;
    expect(drained, isTrue);
    expect(await db.select(db.taskRooms).get(), hasLength(1));
  });

  test('first enqueue binds before concurrent enqueue can reach the queue',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final binding = _FirstTaskBinding();
    final session = _session(
      TaskRoomService(db: db),
      FakeRuntime(),
      binding: binding,
      afterInvoke: ({required result, required authorization}) async {
        final task = (jsonDecode(result.text) as Map)['task'] as Map?;
        binding.bind(task?['task_id'] as String?);
      },
    );
    final authorization = _authorization('first');
    final first = session.taskQueueTool
        .invoke(_enqueue('first'), authorization: authorization);
    final second = session.taskQueueTool
        .invoke(_enqueue('second'), authorization: authorization);

    expect((await _decode(await first))['status'], 'ok');
    expect(jsonDecode((await second).text)['error_code'],
        'task_queue_session_unavailable');
    expect(binding.boundTaskId, isNotNull);
    expect(await db.select(db.taskRooms).get(), hasLength(1));
  });

  test('after invoke failure preserves the queue record and freezes session',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final session = _session(
      TaskRoomService(db: db),
      FakeRuntime(),
      afterInvoke: ({required result, required authorization}) async {
        throw StateError('binding unavailable');
      },
    );
    final authorization = _authorization('first');
    final first = await session.taskQueueTool
        .invoke(_enqueue('written'), authorization: authorization);
    expect(
        jsonDecode(first.text)['error_code'], 'task_queue_session_unavailable');
    expect(session.isFrozen, isTrue);
    expect(await db.select(db.taskRooms).get(), hasLength(1));

    final later = await session.taskQueueTool
        .invoke(_enqueue('blocked'), authorization: authorization);
    expect(
        jsonDecode(later.text)['error_code'], 'task_queue_session_unavailable');
    expect(await db.select(db.taskRooms).get(), hasLength(1));
  });

  test('authorization factory still keeps exact user text and target scope',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final session = _session(TaskRoomService(db: db), FakeRuntime());
    final denied = session.taskQueueTool.authorizationForTurn(
      conversationId: 'first',
      userText: '不要创建长任务',
    );
    expect(denied.allowedActions, isEmpty);
    final foreign = _authorization('second');
    final result = await _rawInvoke(session, foreign, _enqueue('foreign'));
    expect(jsonDecode(result.text)['error_code'],
        'task_queue_session_unavailable');
    expect(await db.select(db.taskRooms).get(), isEmpty);
  });
}

WorkbenchTaskProductSession _session(
  TaskRoomService service,
  FakeRuntime runtime, {
  bool accepts = true,
  WorkbenchTaskProductSessionBinding? binding,
  WorkbenchTaskProductSessionAfterInvoke? afterInvoke,
}) =>
    WorkbenchTaskProductSession(
      taskRoomService: service,
      textRuntime: runtime,
      startTextSession: runtime.startTextSession,
      binding: binding ?? _Binding(accepts),
      afterInvoke: afterInvoke ?? _afterNoop,
    );

Future<void> _afterNoop({
  required dynamic result,
  required WorkbenchTaskQueueAuthorization authorization,
}) async {}

WorkbenchTaskQueueAuthorization _authorization(String conversationId) =>
    WorkbenchTaskQueueAuthorization(
      profileId: 'test_text_queue',
      conversationId: conversationId,
      allowedActions: {WorkbenchTaskQueueAction.enqueue},
    );

Map<String, dynamic> _enqueue(String requestId) => {
      'request_id': requestId,
      'action': 'enqueue',
      'title': 'fixture',
      'goal': 'fixture',
    };

Future<Map<String, dynamic>> _invoke(
  WorkbenchTaskProductSession session,
  WorkbenchTaskQueueAuthorization authorization,
  Map<String, dynamic> payload,
) async =>
    _decode(await _rawInvoke(session, authorization, payload));

Future<dynamic> _rawInvoke(
  WorkbenchTaskProductSession session,
  WorkbenchTaskQueueAuthorization authorization,
  Map<String, dynamic> payload,
) =>
    session.taskQueueTool.invoke(payload, authorization: authorization);

Future<Map<String, dynamic>> _decode(dynamic result) async =>
    Map<String, dynamic>.from(jsonDecode(result.text) as Map);

class _Binding implements WorkbenchTaskProductSessionBinding {
  const _Binding(this.enabled);
  final bool enabled;

  @override
  bool accepts(WorkbenchTaskQueueAuthorization authorization) =>
      enabled &&
      authorization.profileId == 'test_text_queue' &&
      authorization.conversationId == 'first';
}

class _FirstTaskBinding implements WorkbenchTaskProductSessionBinding {
  String? boundTaskId;

  void bind(String? id) => boundTaskId ??= id;

  @override
  bool accepts(WorkbenchTaskQueueAuthorization authorization) =>
      authorization.profileId == 'test_text_queue' &&
      authorization.conversationId == 'first' &&
      (boundTaskId == null || authorization.targetTaskId == boundTaskId);
}

class _DelayedService extends TaskRoomService {
  _DelayedService(AppDatabase db, this.gate) : super(db: db);

  final Completer<void> gate;
  final entered = Completer<void>();

  @override
  Future<TaskQueueEnqueueResult> enqueueTaskRoomIdempotent({
    required String requestId,
    required String title,
    required String goal,
    required TaskType taskType,
    required TaskQueueHostScope queueHostScope,
    String? executor,
    Map<String, dynamic>? permissions,
    Map<String, dynamic>? context,
    String? conversationId,
    String? parentTaskId,
    String? boardId,
    int maxRetries = 3,
  }) async {
    entered.complete();
    await gate.future;
    return super.enqueueTaskRoomIdempotent(
      requestId: requestId,
      title: title,
      goal: goal,
      taskType: taskType,
      executor: executor,
      queueHostScope: queueHostScope,
      permissions: permissions,
      context: context,
      conversationId: conversationId,
      parentTaskId: parentTaskId,
      boardId: boardId,
      maxRetries: maxRetries,
    );
  }
}
