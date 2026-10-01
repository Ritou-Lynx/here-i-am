import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_execution.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_execution_controller.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';

const scope = TaskQueueHostScope(
    profileId: 'test_text_queue',
    scopeType: 'conversation',
    scopeId: 'synthetic_conversation');
final executionError = throwsA(isA<WorkbenchTaskQueueExecutionException>());

void main() {
  late AppDatabase db;
  late TaskRoomService service;
  late FakeRuntime runtime;
  late WorkbenchTaskQueueExecution execution;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TaskRoomService(db: db);
    runtime = FakeRuntime();
    execution = owner(service, runtime);
  });
  tearDown(() async {
    for (final id in runtime.taskIds) {
      try {
        await execution.cancel(id: id, scope: scope, requestId: 'cleanup');
      } on Object {/* A terminal or recovered task needs no mutation. */}
      await execution.waitForAttempt(id);
    }
    await db.close();
  });

  Future<String> enqueue({int retries = 3}) => service.enqueueTaskRoom(
        title: 'synthetic text task',
        goal: 'Write a short fictional paragraph',
        taskType: TaskType.other,
        executor: 'workbench_runtime',
        conversationId: scope.scopeId,
        queueHostScope: scope,
        maxRetries: retries,
        permissions: {
          'profile_id': scope.profileId,
          'scope_type': scope.scopeType,
          'scope_id': scope.scopeId
        },
      );

  test(
      'construction and restart leave legacy pending untouched; no provider call',
      () async {
    final id = await enqueue();
    final before = await service.getTaskRoom(id);
    expect(await TaskRoomService(db: db).restoreInterruptedTaskRoomsOnce(), 0);
    expect(await service.getTaskRoom(id), before);
    expect(runtime.sessions, isEmpty);
  });

  test('explicit start runs an isolated session and persists real output only',
      () async {
    final id = await enqueue();
    final other = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start-one');
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.running);
    expect((await service.getTaskQueueSnapshot(id))!.progressPercent, 0);
    expect((await service.getTaskQueueSnapshot(other))!.status,
        TaskStatus.pending);
    expect(runtime.manifests.single['execution_mode'], 'isolated_text_only');
    runtime.text('s1', 'A fictional, provider-produced result.');
    runtime.terminal('s1', 'completed');
    await execution.waitForAttempt(id);
    final done = (await service.getTaskQueueSnapshot(id))!;
    expect(done.status, TaskStatus.completed);
    expect(done.progressPercent, 100);
    expect(done.resultPreview, 'A fictional, provider-produced result.');
    expect((await db.select(db.personaChatMessages).get()), isEmpty);
    expect((await db.select(db.taskArtifacts).get()), isEmpty);
    expect(runtime.closed, contains('s1'));
  });

  test('duplicate start calls cannot create a second provider session',
      () async {
    final id = await enqueue();
    await Future.wait([
      execution.start(id: id, scope: scope, requestId: 'same'),
      execution.start(id: id, scope: scope, requestId: 'same'),
    ]);
    expect(runtime.sessions.length, 1);
    await expectLater(
        execution.start(id: id, scope: scope, requestId: 'different'),
        executionError);
    expect(runtime.sessions.length, 1);
  });

  test('starting is durable pending, not fake running before provider accepts',
      () async {
    final id = await enqueue();
    runtime.startGate = Completer<void>();
    final start = execution.start(id: id, scope: scope, requestId: 'start');
    await until(() async => runtime.manifests.isNotEmpty);
    final waiting = (await service.getTaskQueueSnapshot(id))!;
    expect(waiting.status, TaskStatus.pending);
    expect(waiting.executionPhase, 'starting');
    runtime.startGate!.complete();
    await start;
  });

  test('host lifecycle fences pending creation and closes its late exact session',
      () async {
    final id = await enqueue();
    final lifecycle = WorkbenchTaskQueueLifecycleOwner();
    lifecycle.register(execution);
    runtime.startGate = Completer<void>();
    final start = execution.start(id: id, scope: scope, requestId: 'start');
    await until(() async => runtime.manifests.isNotEmpty);
    final closing = lifecycle.closeForHostLifecycle();
    runtime.startGate!.complete();
    await expectLater(start, executionError);
    expect(await closing, isTrue);
    expect(runtime.closed, contains('s1'));
    final snapshot = (await service.getTaskQueueSnapshot(id))!;
    expect(snapshot.status, TaskStatus.blocked);
    expect(snapshot.interruptedReason, 'runtime_start_outcome_unknown');
    await expectLater(
        execution.resume(id: id, scope: scope, requestId: 'resume'),
        executionError);
    expect(runtime.sessions, hasLength(1));
  });

  test('host lifecycle waits for a claimed lease before creation and blocks it',
      () async {
    final id = await enqueue();
    final delayedService = _ClaimReturnedBeforeScheduleService(db: db);
    execution = owner(delayedService, runtime);
    final lifecycle = WorkbenchTaskQueueLifecycleOwner();
    lifecycle.register(execution);

    final start = execution.start(id: id, scope: scope, requestId: 'start');
    await delayedService.claimReturned.future;
    expect((await service.getTaskQueueSnapshot(id))!.executionPhase, 'starting');

    var closeSettled = false;
    final closing = lifecycle.closeForHostLifecycle().then((value) {
      closeSettled = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closeSettled, isFalse);

    delayedService.releaseClaim.complete();
    await expectLater(start, executionError);
    expect(await closing, isTrue);
    final snapshot = (await service.getTaskQueueSnapshot(id))!;
    expect(snapshot.status, TaskStatus.blocked);
    expect(snapshot.executionPhase, 'interrupted');
    expect(snapshot.interruptedReason, 'runtime_start_outcome_unknown');
    expect(runtime.sessions, isEmpty);
    expect(runtime.manifests, isEmpty);
    expect(runtime.inputs, isEmpty);
  });

  test('host lifecycle never marks a running turn cancelled', () async {
    final id = await enqueue();
    final lifecycle = WorkbenchTaskQueueLifecycleOwner();
    lifecycle.register(execution);
    await execution.start(id: id, scope: scope, requestId: 'start');
    await lifecycle.closeForHostLifecycle();
    final snapshot = (await service.getTaskQueueSnapshot(id))!;
    expect(snapshot.status, TaskStatus.blocked);
    expect(snapshot.interruptedReason, 'runtime_connection_lost');
    expect(runtime.interrupted, contains('s1'));
    expect(runtime.closed, contains('s1'));
  });

  test('host lifecycle retries an unconfirmed earlier cancel binding', () async {
    final id = await enqueue();
    final lifecycle = WorkbenchTaskQueueLifecycleOwner();
    lifecycle.register(execution);
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.closeFails = true;
    await expectLater(
        execution.cancel(id: id, scope: scope, requestId: 'cancel'),
        executionError);
    runtime.closeFails = false;
    await lifecycle.closeForHostLifecycle();
    expect(runtime.closed, contains('s1'));
    final snapshot = (await service.getTaskQueueSnapshot(id))!;
    expect(snapshot.status, TaskStatus.blocked);
    expect(snapshot.interruptedReason, isNot('user_requested'));
  });

  test('monitor retains a failed ordinary close and lifecycle reuses its binding',
      () async {
    final id = await enqueue();
    final lifecycle = WorkbenchTaskQueueLifecycleOwner();
    lifecycle.register(execution);
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.strictCloseBinding = true;
    runtime.closeFails = true;
    runtime.text('s1', 'Completed text.');
    runtime.terminal('s1', 'completed');
    await execution.waitForAttempt(id);
    expect(runtime.closeInterruptRequests, [false]);
    runtime.closeFails = false;
    expect(await lifecycle.closeForHostLifecycle(), isTrue);
    expect(runtime.closeInterruptRequests, [false, false]);
    expect(runtime.closed, contains('s1'));
  });

  test(
      'pause waits for close confirmation; resume creates a new actual attempt',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.text('s1', 'Saved partial output.');
    await until(() async =>
        (await service.getTaskQueueSnapshot(id))!.resultPreview != null);
    runtime.closeGate = Completer<void>();
    final pause = execution.pause(id: id, scope: scope, requestId: 'pause');
    await until(() async => runtime.interrupted.isNotEmpty);
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.running);
    expect(
        (await service.getTaskQueueSnapshot(id))!.executionPhase, 'stopping');
    runtime.closeGate!.complete();
    await pause;
    expect((await service.getTaskQueueSnapshot(id))!.resumableState, 'paused');
    await execution.resume(id: id, scope: scope, requestId: 'resume');
    expect(runtime.sessions.length, 2);
    expect(runtime.inputs.last, contains('Saved partial output.'));
    expect(runtime.inputs.last, contains('not a resumed provider turn'));
    runtime.text('s1', 'STALE');
    runtime.terminal('s1', 'completed');
    runtime.text('s2', 'Complete resumed result.');
    runtime.terminal('s2', 'completed');
    await execution.waitForAttempt(id);
    expect((await service.getTaskQueueSnapshot(id))!.resultPreview,
        'Complete resumed result.');
  });

  test('cancel fences late provider completion and is repeatable', () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.closeGate = Completer<void>();
    final stop = execution.cancel(id: id, scope: scope, requestId: 'cancel');
    await until(() async => runtime.interrupted.isNotEmpty);
    runtime.text('s1', 'late result');
    runtime.terminal('s1', 'completed');
    runtime.closeGate!.complete();
    await stop;
    await execution.cancel(id: id, scope: scope, requestId: 'cancel-again');
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.cancelled);
    expect((await service.getTaskQueueSnapshot(id))!.resultPreview, isNull);
  });

  test('unconfirmed stop is interrupted and never reported as cancelled',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.closeFails = true;
    await expectLater(
        execution.cancel(id: id, scope: scope, requestId: 'cancel'),
        executionError);
    final state = (await service.getTaskQueueSnapshot(id))!;
    expect(state.status, TaskStatus.blocked);
    expect(state.interruptedReason, 'runtime_stop_unconfirmed');
    await expectLater(
        execution.cancel(id: id, scope: scope, requestId: 'again'),
        executionError);
  });

  for (final receiptCase in ['interrupted', 'completed', 'wrong_epoch']) {
    test('delayed $receiptCase receipt keeps strict cancellation authority',
        () async {
      final adapter = _DelayedCloseAdapter(receiptCase);
      final client = WorkbenchTextTaskRuntimeClient(
          dio: Dio()..httpClientAdapter = adapter);
      execution = WorkbenchTaskQueueExecution(
        service: service,
        runtime: client,
        startTextSession: (manifest) =>
            client.startTextTaskSession(contextManifest: manifest),
        pollInterval: const Duration(milliseconds: 1),
        controlTimeout: const Duration(milliseconds: 10),
        closeTimeout: const Duration(seconds: 2),
      );
      final id = await enqueue();
      await execution.start(id: id, scope: scope, requestId: 'start');
      final before = jsonDecode((await service.getTaskRoom(id))!.contextJson)
          ['__queue']['execution']['epoch'];
      final stop = execution.cancel(id: id, scope: scope, requestId: 'cancel');
      final result = receiptCase == 'interrupted'
          ? expectLater(stop, completion(isTrue))
          : expectLater(stop, executionError);
      await adapter.closeEntered.future;
      // Deliberately cross the generic control deadline while DELETE is pending.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect((await service.getTaskQueueSnapshot(id))!.executionPhase, 'stopping');
      expect(adapter.closeCalls, 1);
      adapter.releaseClose.complete();
      await result;
      await execution.waitForAttempt(id);
      final state = (await service.getTaskQueueSnapshot(id))!;
      expect(state.status, receiptCase == 'interrupted'
          ? TaskStatus.cancelled : TaskStatus.blocked);
      if (receiptCase != 'interrupted') {
        expect(state.interruptedReason, 'runtime_stop_unconfirmed');
      }
      expect(jsonDecode((await service.getTaskRoom(id))!.contextJson)
          ['__queue']['execution']['epoch'], before);
      expect(adapter.closeCalls, 1);
    });
  }

  test('final close timeout retains unknown outcome and ignores late old receipt',
      () async {
    execution = WorkbenchTaskQueueExecution(
      service: service,
      runtime: runtime,
      startTextSession: runtime.startTextSession,
      pollInterval: const Duration(milliseconds: 1),
      controlTimeout: const Duration(milliseconds: 10),
      closeTimeout: const Duration(milliseconds: 80),
    );
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    final oldEpoch = runtime.manifests.single['execution_epoch'];
    final lateClose = runtime.closeGate = Completer<void>();
    await expectLater(
        execution.cancel(id: id, scope: scope, requestId: 'cancel'),
        throwsA(isA<WorkbenchTaskQueueExecutionException>().having(
            (error) => error.code, 'code', 'runtime_stop_unconfirmed')));
    final unknown = (await service.getTaskQueueSnapshot(id))!;
    expect(unknown.status, TaskStatus.blocked);
    expect(unknown.executionPhase, 'interrupted');
    expect(unknown.interruptedReason, 'runtime_stop_unconfirmed');
    expect(runtime.closed, isEmpty);

    // A separate owner can only start a new lease through explicit recovery.
    final oldOwner = execution;
    runtime.closeGate = null;
    execution = owner(service, runtime);
    await execution.resume(id: id, scope: scope, requestId: 'resume');
    expect(runtime.manifests.last['execution_epoch'], isNot(oldEpoch));
    final resumed = await service.getTaskRoom(id);
    lateClose.complete();
    await until(() async => runtime.closed.contains('s1'));
    expect(await service.getTaskRoom(id), resumed);
    expect((await service.getTaskQueueSnapshot(id))!.status, TaskStatus.running);

    // The timed-out attempt is retained for bounded lifecycle cleanup. Its
    // original lease cannot overwrite the resumed task even on a valid receipt.
    expect(await oldOwner.closeForHostLifecycle(), isTrue);
    expect(runtime.closed.where((session) => session == 's1'), hasLength(2));
    expect(await service.getTaskRoom(id), resumed);
  });

  test('completed close evidence never turns a cancel into cancellation',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.stopCancellationConfirmed = false;
    await expectLater(
        execution.cancel(id: id, scope: scope, requestId: 'cancel'),
        executionError);
    final state = (await service.getTaskQueueSnapshot(id))!;
    expect(state.status, TaskStatus.blocked);
    expect(state.interruptedReason, 'runtime_stop_unconfirmed');
  });

  test('a lost interrupt ACK can still have a confirmed cancellation receipt',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.interruptFails = true;
    expect(await execution.cancel(id: id, scope: scope, requestId: 'cancel'),
        true);
    expect((await service.getTaskQueueSnapshot(id))!.status,
        TaskStatus.cancelled);
  });

  test('replayed pause cannot stop a later resumed attempt', () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    await execution.pause(id: id, scope: scope, requestId: 'original-pause');
    await execution.resume(id: id, scope: scope, requestId: 'resume');
    final calls = runtime.interrupted.length;
    await execution.pause(id: id, scope: scope, requestId: 'original-pause');
    expect(runtime.interrupted.length, calls);
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.running);
  });

  test(
      'Bridge loss reports interrupted and explicit resume really starts again',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.readUnavailable = true;
    await execution.waitForAttempt(id);
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.blocked);
    expect((await service.getTaskQueueSnapshot(id))!.interruptedReason,
        'runtime_connection_lost');
    runtime.readUnavailable = false;
    await execution.resume(id: id, scope: scope, requestId: 'resume');
    expect(runtime.sessions.length, 2);
    runtime.text('s2', 'Fresh result after explicit recovery.');
    runtime.terminal('s2', 'completed');
    await execution.waitForAttempt(id);
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.completed);
  });

  test(
      'output limit interrupts without storing unbounded text or claiming success',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.text('s1', 'x' * 24001);
    runtime.terminal('s1', 'completed');
    await execution.waitForAttempt(id);
    expect((await service.getTaskQueueSnapshot(id))!.status, TaskStatus.failed);
    expect((await service.getTaskQueueSnapshot(id))!.resultPreview, isNull);
    expect(runtime.interrupted, contains('s1'));
  });

  test(
      'actual provider failures retry with durable cap and request deduplication',
      () async {
    final id = await enqueue(retries: 1);
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.terminal('s1', 'failed');
    await execution.waitForAttempt(id);
    expect((await service.getTaskQueueSnapshot(id))!.status, TaskStatus.failed);
    await execution.retry(id: id, scope: scope, requestId: 'retry-one');
    runtime.terminal('s2', 'failed');
    await execution.waitForAttempt(id);
    final freshOwner = owner(TaskRoomService(db: db), runtime);
    await freshOwner.retry(id: id, scope: scope, requestId: 'retry-one');
    expect(runtime.sessions.length, 2);
    await expectLater(
        freshOwner.retry(id: id, scope: scope, requestId: 'retry-two'),
        executionError);
    expect((await service.getTaskQueueSnapshot(id))!.retryCount, 1);
  });

  test('provider start rejection is a real failed attempt, no success text',
      () async {
    final id = await enqueue();
    runtime.startFails = true;
    await expectLater(execution.start(id: id, scope: scope, requestId: 'start'),
        executionError);
    final state = (await service.getTaskQueueSnapshot(id))!;
    expect(state.status, TaskStatus.failed);
    expect(state.resultPreview, isNull);
  });

  test('empty completed event is failure, not fabricated success', () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.terminal('s1', 'completed');
    await execution.waitForAttempt(id);
    expect((await service.getTaskQueueSnapshot(id))!.status, TaskStatus.failed);
  });

  test('unexpected tool requests close fail-closed, with no tool dispatcher',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.add('s1', {
      'kind': 'tool_call',
      'data': {'tool_name': 'write_file'}
    });
    await execution.waitForAttempt(id);
    expect((await service.getTaskQueueSnapshot(id))!.status, TaskStatus.failed);
    expect(runtime.closed, contains('s1'));
    expect(runtime.toolResponses, 0);
  });

  test('unknown and cross-scope task start never reaches provider', () async {
    final id = await enqueue();
    await expectLater(
        execution.start(
            id: id,
            scope: const TaskQueueHostScope(
                profileId: 'test_text_queue',
                scopeType: 'conversation',
                scopeId: 'other'),
            requestId: 'start'),
        executionError);
    await expectLater(
        execution.start(
            id: 'synthetic_missing', scope: scope, requestId: 'missing'),
        executionError);
    expect(runtime.sessions, isEmpty);
  });

  test(
      'file-backed restart fences starting attempt and preserves unrelated pending',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('p6_execution_test_');
    final file = File('${directory.path}/synthetic.sqlite');
    var durableDb = AppDatabase.forTesting(NativeDatabase(file));
    var durable = TaskRoomService(db: durableDb);
    Future<String> create() => durable.enqueueTaskRoom(
            title: 'synthetic',
            goal: 'Fiction',
            taskType: TaskType.other,
            executor: 'workbench_runtime',
            queueHostScope: scope,
            conversationId: scope.scopeId,
            permissions: {
              'profile_id': scope.profileId,
              'scope_type': scope.scopeType,
              'scope_id': scope.scopeId
            });
    final id = await create();
    final untouched = await create();
    final lease = (await durable.claimTaskQueueExecution(
        id: id, scope: scope, requestId: 'start', action: 'start'))!;
    await durableDb.close();
    durableDb = AppDatabase.forTesting(NativeDatabase(file));
    durable = TaskRoomService(db: durableDb);
    expect(await durable.restoreInterruptedTaskRoomsOnce(), 1);
    expect(
        (await durable.getTaskQueueSnapshot(id))!.status, TaskStatus.blocked);
    expect((await durable.getTaskQueueSnapshot(untouched))!.status,
        TaskStatus.pending);
    expect(
        await durable.writeTaskQueueExecution(
            lease: lease,
            expectedPhases: const {'starting', 'running'},
            phase: 'completed',
            status: TaskStatus.completed,
            resultText: 'late'),
        false);
    expect(
        await durable.claimTaskQueueExecution(
            id: id, scope: scope, requestId: 'start', action: 'start'),
        isNull);
    final next = await durable.claimTaskQueueExecution(
        id: id, scope: scope, requestId: 'resume', action: 'resume');
    expect(next!.epoch, isNot(lease.epoch));
    await durableDb.close();
    await directory.delete(recursive: true);
  });

  test('replayed provider sequence cannot duplicate persisted text', () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.text('s1', 'Once.');
    runtime.events['s1']!.add(Map.of(runtime.events['s1']!.last));
    runtime.terminal('s1', 'completed');
    await execution.waitForAttempt(id);
    expect((await service.getTaskQueueSnapshot(id))!.resultPreview, 'Once.');
    final room = (await service.getTaskRoom(id))!;
    expect(jsonDecode(room.contextJson)['__queue']['execution']['resultText'],
        'Once.');
  });

  test(
      'production wrapper host preserves start and resume replays after completion',
      () async {
    final id = await enqueue();
    final wrapper = WorkbenchRuntimeTaskQueueTool(
        loadService: () async => service,
        loadExecutionController: (_) async => execution);
    // Match the actual desktop host profile without modifying any real task.
    final room = await service.enqueueTaskRoom(
        title: 'synthetic scoped task',
        goal: 'Write fiction',
        taskType: TaskType.other,
        executor: 'workbench_runtime',
        conversationId: 'synthetic-desktop',
        queueHostScope: const TaskQueueHostScope(
            profileId: 'desktop_workbench_task_queue_v1',
            scopeType: 'conversation',
            scopeId: 'synthetic-desktop'),
        permissions: {
          'profile_id': 'desktop_workbench_task_queue_v1',
          'scope_type': 'conversation',
          'scope_id': 'synthetic-desktop'
        });
    final startAuthorization = wrapper.authorizationForTurn(
        conversationId: 'synthetic-desktop', userText: '启动长任务 $room');
    final startPayload = {
      'request_id': 'host-start',
      'action': 'start',
      'task_id': room
    };
    expect(
        (await wrapper.invoke(startPayload, authorization: startAuthorization))
            .success,
        true);
    final pauseAuth = wrapper.authorizationForTurn(
        conversationId: 'synthetic-desktop', userText: '暂停任务 $room');
    expect(
        (await wrapper.invoke({
          'request_id': 'host-pause',
          'action': 'pause',
          'task_id': room
        }, authorization: pauseAuth))
            .success,
        true);
    final resumeAuth = wrapper.authorizationForTurn(
        conversationId: 'synthetic-desktop', userText: '恢复任务 $room');
    final resumePayload = {
      'request_id': 'host-resume',
      'action': 'resume',
      'task_id': room
    };
    expect(
        (await wrapper.invoke(resumePayload, authorization: resumeAuth))
            .success,
        true);
    runtime.text('s2', 'Finished.');
    runtime.terminal('s2', 'completed');
    await execution.waitForAttempt(room);
    for (final pair in [
      (startPayload, startAuthorization),
      (resumePayload, resumeAuth)
    ]) {
      final replay = await wrapper.invoke(pair.$1, authorization: pair.$2);
      expect(replay.success, true);
      expect(jsonDecode(replay.text)['changed'], false);
    }
    expect(runtime.sessions.length, 2);
    expect((await service.getTaskQueueSnapshot(room))!.status,
        TaskStatus.completed);
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.pending);
  });

  test('queued-only cancel and execution claim serialize in either order',
      () async {
    final claimed = await enqueue();
    await service.claimTaskQueueExecution(
        id: claimed, scope: scope, requestId: 'claim', action: 'start');
    await expectLater(
        service.cancelPendingTaskQueue(
            id: claimed, scope: scope, requestId: 'cancel'),
        throwsStateError);
    expect((await service.getTaskQueueSnapshot(claimed))!.executionPhase,
        'starting');
    final cancelled = await enqueue();
    expect(
        await service.cancelPendingTaskQueue(
            id: cancelled, scope: scope, requestId: 'cancel'),
        true);
    await expectLater(
        execution.start(id: cancelled, scope: scope, requestId: 'start'),
        executionError);
    expect((await service.getTaskQueueSnapshot(cancelled))!.status,
        TaskStatus.cancelled);
    expect(runtime.sessions, isEmpty);
  });

  test(
      'provider unavailability event persists interrupted, not a fake work failure',
      () async {
    final id = await enqueue();
    await execution.start(id: id, scope: scope, requestId: 'start');
    runtime.add('s1', {
      'kind': 'error',
      'data': {'code': 'runtime_unavailable'}
    });
    await execution.waitForAttempt(id);
    expect(
        (await service.getTaskQueueSnapshot(id))!.status, TaskStatus.blocked);
    expect((await service.getTaskQueueSnapshot(id))!.resumableState,
        'interrupted');
  });
}

WorkbenchTaskQueueExecution owner(
        TaskRoomService service, FakeRuntime runtime) =>
    WorkbenchTaskQueueExecution(
        service: service,
        runtime: runtime,
        startTextSession: runtime.startTextSession,
        pollInterval: const Duration(milliseconds: 1));

Future<void> until(Future<bool> Function() condition) async {
  for (var i = 0; i < 500; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Expected state was never reached');
}

/// Keeps the real durable claim but delays delivery to the execution owner.
/// This exposes the post-claim/pre-session lifecycle boundary without adding a
/// production-only hook.
class _ClaimReturnedBeforeScheduleService extends TaskRoomService {
  _ClaimReturnedBeforeScheduleService({required super.db});

  final claimReturned = Completer<void>();
  final releaseClaim = Completer<void>();

  @override
  Future<TaskQueueExecutionLease?> claimTaskQueueExecution({
    required String id,
    required TaskQueueHostScope scope,
    required String requestId,
    required String action,
  }) async {
    final lease = await super.claimTaskQueueExecution(
      id: id,
      scope: scope,
      requestId: requestId,
      action: action,
    );
    claimReturned.complete();
    await releaseClaim.future;
    return lease;
  }
}

/// In-memory HTTP boundary; the production client validates every receipt.
class _DelayedCloseAdapter implements HttpClientAdapter {
  _DelayedCloseAdapter(this.receiptCase);

  final String receiptCase;
  final closeEntered = Completer<void>();
  final releaseClose = Completer<void>();
  String? epoch;
  int closeCalls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) async {
    Map<String, dynamic> body;
    if (options.method == 'DELETE') {
      closeCalls++;
      if (!closeEntered.isCompleted) closeEntered.complete();
      await releaseClose.future;
      body = {
        'stop_receipt': {
          'profile': 'workbench_text_only_v1',
          'version': 2,
          'local_session_id': 'text-session',
          'execution_epoch': receiptCase == 'wrong_epoch' ? 'stale-epoch' : epoch,
          'provider_thread_id': 'provider-session',
          'outcome': 'closed',
          'local_turn_id': 'local-turn',
          'turn_id': 'provider-turn',
          'interrupt_dispatched': true,
          'interrupt_dispatch_sequence': 9,
          'provider_terminal_confirmed': true,
          'provider_terminal_status':
              receiptCase == 'completed' ? 'completed' : 'interrupted',
          'provider_terminal_sequence': 11,
          'cancellation_confirmed': receiptCase != 'completed',
          'local_child_close_observed': true,
          'proxy_drained': true,
        }
      };
    } else if (options.path.endsWith('/sessions')) {
      epoch = ((options.data as Map)['context_manifest'] as Map)
          ['execution_epoch'] as String;
      body = {
        'session_id': 'text-session',
        'provider_metadata': {
          'provider': 'synthetic',
          'provider_session_id': 'provider-session',
        },
        'execution_profile_receipt': {
          'profile': 'workbench_text_only_v1',
          'version': 2,
          'local_session_id': 'text-session',
          'execution_epoch': epoch,
          'provider_thread_id': 'provider-session',
          'isolation_verified': true,
          'tools_disabled': true,
        },
      };
    } else if (options.path.endsWith('/turns')) {
      body = {
        'local_session_id': 'text-session',
        'provider_thread_id': 'provider-session',
        'execution_epoch': epoch,
        'local_turn_id': 'local-turn',
        'provider_turn_id': 'provider-turn',
      };
    } else {
      body = {'status': 'active', 'events': [], 'next_sequence': 0};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

class FakeRuntime implements WorkbenchTextTaskStopGateway {
  final List<WorkbenchRuntimeSession> sessions = [];
  final List<Map<String, dynamic>> manifests = [];
  final List<String> inputs = [];
  final List<String> closed = [];
  final List<String> interrupted = [];
  final Map<String, List<Map<String, dynamic>>> events = {};
  Completer<void>? startGate;
  Completer<void>? closeGate;
  bool closeFails = false;
  bool startFails = false;
  bool readUnavailable = false;
  bool interruptFails = false;
  bool stopCancellationConfirmed = true;
  bool strictCloseBinding = false;
  final List<bool> closeInterruptRequests = [];
  int toolResponses = 0;
  Iterable<String> get taskIds =>
      manifests.map((m) => m['task_id'] as String).toSet();

  Future<WorkbenchTextTaskSession> startTextSession(
      Map<String, dynamic> manifest) async {
    manifests.add(manifest);
    await startGate?.future;
    if (startFails) {
      throw const WorkbenchRuntimeException(
          'runtime_unavailable', 'Fake rejection');
    }
    final id = 's${sessions.length + 1}';
    final session = WorkbenchTextTaskSession(
        sessionId: id,
        provider: 'fake',
        providerSessionId: 'provider-$id',
        providerThreadId: 'provider-$id',
        executionEpoch: manifest['execution_epoch'] as String);
    sessions.add(session);
    events[id] = [];
    return session;
  }

  void add(String id, Map<String, dynamic> event) => events[id]!.add({
        'sequence': events[id]!.length + 1,
        'turn_id': 'turn-$id',
        ...event,
      });
  void text(String id, String text) => add(id, {
        'kind': 'message_delta',
        'data': {'text': text}
      });
  void terminal(String id, String status) =>
      add(id, {'kind': 'turn_status', 'status': status});

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
    inputs.add(input);
    return WorkbenchRuntimeTurn(turnId: 'turn-$sessionId');
  }

  @override
  Future<WorkbenchTextTaskTurn> startTextTaskTurn(
      WorkbenchTextTaskSession session, String input) async {
    inputs.add(input);
    return WorkbenchTextTaskTurn(
      localTurnId: 'turn-${session.sessionId}',
      providerTurnId: 'provider-turn-${session.sessionId}',
      executionEpoch: session.executionEpoch,
    );
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(String sessionId,
      {int afterSequence = 0}) async {
    if (readUnavailable) {
      throw const WorkbenchRuntimeException(
          'session_not_found', 'Fake Bridge restart');
    }
    return WorkbenchRuntimeEvents(
        status: 'active',
        events: events[sessionId]!
            .where((event) => (event['sequence'] as int) > afterSequence)
            .toList(),
        nextSequence: events[sessionId]!.length);
  }

  @override
  Future<void> interruptTurn(
      {required String sessionId, required String turnId}) async {
    interrupted.add(sessionId);
    if (interruptFails) throw StateError('Fake interrupt ACK lost');
  }

  @override
  Future<void> closeSession(String sessionId) async {
    await closeGate?.future;
    if (closeFails) throw StateError('Fake close unavailable');
    closed.add(sessionId);
  }

  @override
  Future<WorkbenchTextTaskStopResult> closeTextTaskSession({
    required WorkbenchTextTaskSession session,
    WorkbenchTextTaskTurn? turn,
    required bool interruptRequested,
  }) async {
    if (strictCloseBinding && closeInterruptRequests.isNotEmpty &&
        closeInterruptRequests.first != interruptRequested) {
      throw StateError('close binding changed');
    }
    closeInterruptRequests.add(interruptRequested);
    await closeGate?.future;
    if (closeFails) throw StateError('Fake close unavailable');
    closed.add(session.sessionId);
    return WorkbenchTextTaskStopResult(
      ordinaryCloseConfirmed: true,
      cancellationConfirmed:
          turn == null || (interruptRequested && stopCancellationConfirmed),
    );
  }

  @override
  Future<WorkbenchRuntimeSession> startSession(
          {required List<Map<String, dynamic>> dynamicTools,
          Map<String, dynamic> contextManifest = const {}}) =>
      throw UnimplementedError('Unsafe generic start forbidden');
  @override
  Future<WorkbenchRuntimeSession> resumeSession(
          {required String provider,
          required String providerSessionId,
          required List<Map<String, dynamic>> dynamicTools}) =>
      throw UnimplementedError('Tasks use new isolated attempts');
  @override
  Future<void> respondToToolCall(
      {required String toolCallId,
      required bool success,
      required String text}) async {
    toolResponses++;
  }
}
