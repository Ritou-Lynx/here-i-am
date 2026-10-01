import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';

import '../task_queue/workbench_task_queue_execution_test.dart'
    show FakeRuntime;

void main() {
  test('retains old paused monitor while resumed attempt is also closed',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = TaskRoomService(db: db);
    final runtime = _HeldReadRuntime();
    final execution = P6R7CandidateExecution(
        service: service,
        runtime: runtime,
        startTextSession: runtime.startTextSession);
    const scope = TaskQueueHostScope(
        profileId: 'test_text_queue',
        scopeType: 'conversation',
        scopeId: 'synthetic_conversation');
    final id = await service.enqueueTaskRoom(
        title: 'fixture',
        goal: 'fixture',
        taskType: TaskType.other,
        executor: 'workbench_runtime',
        conversationId: scope.scopeId,
        queueHostScope: scope,
        permissions: {
          'profile_id': scope.profileId,
          'scope_type': scope.scopeType,
          'scope_id': scope.scopeId
        });
    expect(await execution.start(id: id, scope: scope, requestId: 'start'),
        isTrue);
    expect(await execution.pause(id: id, scope: scope, requestId: 'pause'),
        isTrue);
    expect(await execution.resume(id: id, scope: scope, requestId: 'resume'),
        isTrue);
    expect(await execution.closeForHostLifecycle(), isTrue);
    var storeClosed = false;
    final resources = P6R7CandidateSessionResources(
      drainExecution: execution.drainAfterHostClose,
      closeStore: () async {
        await db.close();
        storeClosed = true;
      },
      closeClient: () {},
    );
    final closed = resources.close();
    runtime.reads['s2']!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(storeClosed, isFalse);
    runtime.reads['s1']!.complete();
    expect((await closed).closed, isTrue);
    expect(storeClosed, isTrue);
  });
  test(
      'joins remaining execution before store and client; concurrent close shares',
      () async {
    final drain = Completer<void>();
    final store = Completer<void>();
    final calls = <String>[];
    final resources = P6R7CandidateSessionResources(
      drainExecution: () {
        calls.add('drain');
        return drain.future;
      },
      closeStore: () {
        calls.add('store');
        return store.future;
      },
      closeClient: () => calls.add('client'),
    );
    final first = resources.close();
    expect(identical(first, resources.close()), isTrue);
    expect(calls, ['drain']);
    expect(resources.result, isNull);
    drain.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['drain', 'store']);
    store.complete();
    final result = await first;
    expect(result.closed, isTrue);
    expect(calls, ['drain', 'store', 'client']);
    expect(identical(await resources.close(), result), isTrue);
    expect(result.toJson(), {
      'schema': 'p6_r7_candidate_session_close_v1',
      'execution': 'confirmed',
      'store': 'confirmed',
      'client': 'confirmed',
    });
  });

  test('store failure is sticky even when its next call would be a no-op',
      () async {
    var stores = 0;
    var clients = 0;
    final resources = P6R7CandidateSessionResources(
      drainExecution: () async {},
      closeStore: () async {
        if (++stores == 1) throw StateError('fixture');
      },
      closeClient: () {
        clients++;
      },
    );
    final first = await resources.close();
    expect(first.store, P6R7CandidateResourceCloseState.unknown);
    expect(first.client, P6R7CandidateResourceCloseState.confirmed);
    expect((await resources.close()).closed, isFalse);
    expect(stores, 1);
    expect(clients, 1);
  });

  test('failed execution join preserves resources, never retries unknown',
      () async {
    var drains = 0;
    final resources = P6R7CandidateSessionResources(
      drainExecution: () async {
        drains++;
        throw StateError('fixture');
      },
      closeStore: () async => fail('store still in use'),
      closeClient: () => fail('client still in use'),
    );
    final result = await resources.close();
    expect(result.execution, P6R7CandidateResourceCloseState.unknown);
    expect(result.store, P6R7CandidateResourceCloseState.notRequested);
    expect(result.client, P6R7CandidateResourceCloseState.notRequested);
    expect((await resources.close()).closed, isFalse);
    expect(drains, 1);
  });

  test('client throw remains unknown after completed store close', () async {
    var clients = 0;
    final resources = P6R7CandidateSessionResources(
      drainExecution: () async {},
      closeStore: () async {},
      closeClient: () {
        clients++;
        throw StateError('fixture');
      },
    );
    final result = await resources.close();
    expect(result.store, P6R7CandidateResourceCloseState.confirmed);
    expect(result.client, P6R7CandidateResourceCloseState.unknown);
    expect((await resources.close()).closed, isFalse);
    expect(clients, 1);
  });
}

class _HeldReadRuntime extends FakeRuntime {
  final reads = <String, Completer<void>>{};
  @override
  Future<WorkbenchRuntimeEvents> readEvents(String sessionId,
      {int afterSequence = 0}) async {
    await (reads[sessionId] ??= Completer<void>()).future;
    return super.readEvents(sessionId, afterSequence: afterSequence);
  }
}
