import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/p6_r7_candidate/view_models/p6_r7_candidate_view_model.dart';
import 'package:memex/utils/result.dart';

void main() {
  late AppDatabase db;
  late TaskRoomService service;
  late P6R7CandidateViewModel viewModel;
  final persisted = <String>[];

  P6R7CandidateViewModel candidate({
    required WorkbenchRuntimeTaskQueueTool tool,
    required String? initialTaskId,
  }) =>
      P6R7CandidateViewModel(
        tool: tool,
        service: service,
        lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
        conversationId: 'p6-r7-test',
        initialTaskId: initialTaskId,
        persistTaskId: (_) async {},
      );

  setUp(() {
    persisted.clear();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TaskRoomService(db: db);
    viewModel = P6R7CandidateViewModel(
      tool: WorkbenchRuntimeTaskQueueTool(loadService: () async => service),
      service: service,
      lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
      conversationId: 'p6-r7-test',
      initialTaskId: null,
      persistTaskId: (id) async => persisted.add(id),
    );
  });

  tearDown(() async => db.close());

  test('candidate goal remains the approved public long-running task', () {
    expect(P6R7CandidateViewModel.goal, '只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。');
  });

  test('exit fences commands and waits through marker persistence', () async {
    final entered = Completer<void>();
    final persist = Completer<void>();
    final vm = P6R7CandidateViewModel(
      tool: WorkbenchRuntimeTaskQueueTool(loadService: () async => service),
      service: service,
      lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
      conversationId: 'p6-r7-test',
      initialTaskId: null,
      persistTaskId: (_) {
        entered.complete();
        return persist.future;
      },
    );
    final command = vm.enqueue.execute();
    await entered.future;
    var settled = false;
    final drain = vm.quiesceForExit()..then((_) => settled = true);
    await vm.start.execute();
    expect(vm.start.result, isA<Error<void>>());
    expect(settled, isFalse);
    persist.complete();
    await drain;
    await command;
    expect(vm.isBusy, isFalse);
    expect(vm.snapshot, isNotNull);
    await vm.refresh.execute();
    expect(vm.refresh.result, isA<Error<void>>());
    vm.dispose();
  });

  test('exit stops polling and joins already dispatched status after dispose',
      () async {
    await viewModel.enqueue.execute();
    final tool = _DelayedTool();
    final vm = candidate(tool: tool, initialTaskId: viewModel.taskId);
    vm.startStatusObservation(interval: const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(tool.calls, 1);
    final drain = vm.quiesceForExit();
    vm.dispose();
    tool.reply.complete(_successFor(viewModel.taskId!));
    await drain;
    expect(vm.isBusy, isFalse);
    vm.startStatusObservation(interval: const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(tool.calls, 1);
  });

  test('creates one fixed public task and then keeps its exact id', () async {
    var notifications = 0;
    viewModel.addListener(() => notifications++);
    await viewModel.enqueue.execute();

    expect(viewModel.taskId, isNotNull);
    expect(persisted, [viewModel.taskId]);
    expect(viewModel.snapshot!.title, P6R7CandidateViewModel.title);
    expect(viewModel.isBusy, isFalse);
    expect(notifications, greaterThan(1));

    await viewModel.enqueue.execute();
    expect(viewModel.enqueue.result, isA<Error<void>>());
    expect(await service.findLatestTaskQueueForScope(_scope), isNotNull);
  });

  test('failed persistence still fences the returned task id', () async {
    final fenced = P6R7CandidateViewModel(
      tool: WorkbenchRuntimeTaskQueueTool(loadService: () async => service),
      service: service,
      lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
      conversationId: 'p6-r7-persist-failure',
      initialTaskId: null,
      persistTaskId: (_) => Future<void>.error(StateError('marker failed')),
    );

    await fenced.enqueue.execute();

    expect(fenced.taskId, isNotNull);
    expect(fenced.enqueue.result, isA<Error<void>>());
    await fenced.start.execute();
    expect(fenced.start.result, isA<Error<void>>());
    await fenced.enqueue.execute();
    expect(fenced.enqueue.result, isA<Error<void>>());
  });

  test('recovery only reads an existing exact id and does not create work',
      () async {
    await viewModel.restoreExactTask();
    expect(viewModel.taskId, isNull);
    expect(await service.findLatestTaskQueueForScope(_scope), isNull);
  });

  test('recovery reads the supplied exact id without starting it', () async {
    await viewModel.enqueue.execute();
    final taskId = viewModel.taskId!;
    final recovered = P6R7CandidateViewModel(
      tool: WorkbenchRuntimeTaskQueueTool(loadService: () async => service),
      service: service,
      lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
      conversationId: 'p6-r7-test',
      initialTaskId: taskId,
      persistTaskId: (_) async {},
    );

    await recovered.restoreExactTask();

    expect(recovered.taskId, taskId);
    expect(recovered.snapshot!.status.name, 'pending');
  });

  test('status refresh shows a later durable completion', () async {
    await viewModel.enqueue.execute();
    final taskId = viewModel.taskId!;
    await service.updateTaskStatus(id: taskId, status: TaskStatus.running);
    await service.updateTaskStatus(id: taskId, status: TaskStatus.completed);

    await viewModel.refresh.execute();

    expect(viewModel.snapshot!.status, TaskStatus.completed);
    expect(viewModel.statusLabel, '已完成');
  });

  test('an exact id from another scope cannot replace candidate state',
      () async {
    final unrelatedId = await service.enqueueTaskRoom(
      title: P6R7CandidateViewModel.title,
      goal: P6R7CandidateViewModel.goal,
      taskType: TaskType.other,
      conversationId: 'different-candidate',
      queueHostScope: const TaskQueueHostScope(
        profileId: 'desktop_workbench_task_queue_v1',
        scopeType: 'conversation',
        scopeId: 'different-candidate',
      ),
    );
    final wrongTarget = P6R7CandidateViewModel(
      tool: WorkbenchRuntimeTaskQueueTool(loadService: () async => service),
      service: service,
      lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
      conversationId: 'p6-r7-test',
      initialTaskId: unrelatedId,
      persistTaskId: (_) async {},
    );

    await wrongTarget.restoreExactTask();

    expect(wrongTarget.taskId, unrelatedId);
    expect(wrongTarget.snapshot, isNull);
    expect(wrongTarget.errorMessage, '操作未能完成，请读取状态后再决定。');
  });

  test('different commands share one in-flight request fence', () async {
    await viewModel.enqueue.execute();
    final delayed = _DelayedTool();
    final guarded = candidate(tool: delayed, initialTaskId: viewModel.taskId);

    final first = guarded.start.execute();
    await Future<void>.delayed(Duration.zero);
    await guarded.pause.execute();

    expect(delayed.calls, 1);
    expect(guarded.pause.result, isA<Error<void>>());
    delayed.reply.complete(_successFor(viewModel.taskId!));
    await first;
    expect(guarded.isBusy, isFalse);
  });

  test('a wrong response id is rejected before it can replace state', () async {
    await viewModel.enqueue.execute();
    final wrong = candidate(
      tool: _WrongIdTool(),
      initialTaskId: viewModel.taskId,
    );

    await wrong.refresh.execute();

    expect(wrong.taskId, viewModel.taskId);
    expect(wrong.snapshot!.id, viewModel.taskId);
    expect(wrong.refresh.result, isA<Error<void>>());
  });

  test('an in-flight request may finish after view model disposal', () async {
    await viewModel.enqueue.execute();
    final delayed = _DelayedTool();
    final disposable =
        candidate(tool: delayed, initialTaskId: viewModel.taskId);

    final request = disposable.refresh.execute();
    await Future<void>.delayed(Duration.zero);
    disposable.dispose();
    delayed.reply.complete(_successFor(viewModel.taskId!));

    await request;
    expect(delayed.calls, 1);
  });

  test('resume with saved text is rejected before the queue tool changes it',
      () async {
    final id = await service.enqueueTaskRoom(
      title: P6R7CandidateViewModel.title,
      goal: P6R7CandidateViewModel.goal,
      taskType: TaskType.other,
      executor: 'workbench_runtime',
      conversationId: 'p6-r7-test',
      queueHostScope: _scope,
      permissions: const {
        'profile_id': 'desktop_workbench_task_queue_v1',
        'scope_type': 'conversation',
        'scope_id': 'p6-r7-test',
      },
    );
    final lease = (await service.claimTaskQueueExecution(
      id: id,
      scope: _scope,
      requestId: 'fixture-start',
      action: 'start',
    ))!;
    expect(
      await service.writeTaskQueueExecution(
        lease: lease,
        expectedPhases: const {'starting'},
        phase: 'interrupted',
        status: TaskStatus.blocked,
        resultText: 'partial native output',
      ),
      isTrue,
    );
    final before = await service.getTaskRoom(id);
    final tool = _FailIfCalledTool();
    final resumedCandidate = candidate(tool: tool, initialTaskId: id);

    await resumedCandidate.resume.execute();

    final after = await service.getTaskRoom(id);
    expect(tool.calls, 0);
    expect(resumedCandidate.resume.result, isA<Error<void>>());
    expect(resumedCandidate.errorMessage, '本轮验收只支持尚未生成文字的任务继续；已有文字请显式重试。');
    expect(after!.status, before!.status);
    expect(after.contextJson, before.contextJson);

    await resumedCandidate.refresh.execute();
    expect(resumedCandidate.errorMessage, '本轮验收只支持尚未生成文字的任务继续；已有文字请显式重试。');
  });
}

const _scope = TaskQueueHostScope(
  profileId: 'desktop_workbench_task_queue_v1',
  scopeType: 'conversation',
  scopeId: 'p6-r7-test',
);

class _DelayedTool extends WorkbenchRuntimeTaskQueueTool {
  _DelayedTool() : super(loadService: _unreachableService);

  final reply = Completer<WorkbenchRuntimeTaskQueueResult>();
  int calls = 0;

  @override
  Future<WorkbenchRuntimeTaskQueueResult> invoke(
    Object? arguments, {
    required WorkbenchTaskQueueAuthorization authorization,
  }) {
    calls++;
    return reply.future;
  }
}

class _WrongIdTool extends WorkbenchRuntimeTaskQueueTool {
  _WrongIdTool() : super(loadService: _unreachableService);

  @override
  Future<WorkbenchRuntimeTaskQueueResult> invoke(
    Object? arguments, {
    required WorkbenchTaskQueueAuthorization authorization,
  }) async =>
      const WorkbenchRuntimeTaskQueueResult(
        success: true,
        text: '{"status":"ok","task":{"task_id":"wrong-id"}}',
      );
}

class _FailIfCalledTool extends WorkbenchRuntimeTaskQueueTool {
  _FailIfCalledTool() : super(loadService: _unreachableService);

  int calls = 0;

  @override
  Future<WorkbenchRuntimeTaskQueueResult> invoke(
    Object? arguments, {
    required WorkbenchTaskQueueAuthorization authorization,
  }) async {
    calls++;
    return const WorkbenchRuntimeTaskQueueResult(
      success: false,
      text: '{"status":"failed"}',
    );
  }
}

Future<TaskRoomService> _unreachableService() =>
    Future<TaskRoomService>.error(StateError('unreachable'));

WorkbenchRuntimeTaskQueueResult _successFor(String id) =>
    WorkbenchRuntimeTaskQueueResult(
      success: true,
      text: '{"status":"ok","task":{"task_id":"$id"}}',
    );
