import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';

Map<String, dynamic> parseQueueContext(TaskRoom room) {
  final decoded = jsonDecode(room.contextJson);
  if (decoded is Map && decoded['__queue'] is Map) {
    return Map<String, dynamic>.from(decoded['__queue']);
  }
  return {};
}

void main() {
  late AppDatabase db;
  late TaskRoomService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    TaskRoomService.init(db);
    service = TaskRoomService.instance;
  });

  tearDown(() async {
    await db.close();
  });

  group('TaskRoomService - CRUD', () {
    test('createTaskRoom creates a new task room with all fields', () async {
      final id = await service.createTaskRoom(
        title: 'Build user dashboard',
        goal: 'Create a responsive dashboard showing user metrics',
        taskType: TaskType.coding,
        executor: 'claude-code',
        permissions: {'write_code': true, 'run_tests': true},
        context: {'repo': 'memex', 'branch': 'feature/dashboard'},
        conversationId: 'conv-123',
      );

      expect(id, isNotEmpty);

      final room = await service.getTaskRoom(id);
      expect(room, isNotNull);
      expect(room!.title, 'Build user dashboard');
      expect(room.goal, 'Create a responsive dashboard showing user metrics');
      expect(room.taskType, 'coding');
      expect(room.status, 'pending');
      expect(room.executor, 'claude-code');
      expect(room.progressPercent, 0);
      expect(room.conversationId, 'conv-123');
    });

    test('getTaskRoom returns null for non-existent id', () async {
      final room = await service.getTaskRoom('non-existent-id');
      expect(room, isNull);
    });

    test('listTaskRooms filters by status', () async {
      await service.createTaskRoom(
        title: 'Task 1',
        goal: 'Goal 1',
        taskType: TaskType.coding,
      );
      final id2 = await service.createTaskRoom(
        title: 'Task 2',
        goal: 'Goal 2',
        taskType: TaskType.research,
      );
      await service.updateTaskStatus(id: id2, status: TaskStatus.running);

      final planningRooms = await service.listTaskRooms(status: TaskStatus.pending);
      expect(planningRooms.length, 1);
      expect(planningRooms[0].title, 'Task 1');

      final runningRooms = await service.listTaskRooms(status: TaskStatus.running);
      expect(runningRooms.length, 1);
      expect(runningRooms[0].title, 'Task 2');
    });

    test('listTaskRooms filters by taskType', () async {
      await service.createTaskRoom(
        title: 'Coding task',
        goal: 'Write code',
        taskType: TaskType.coding,
      );
      await service.createTaskRoom(
        title: 'Research task',
        goal: 'Research topic',
        taskType: TaskType.research,
      );

      final codingRooms = await service.listTaskRooms(taskType: TaskType.coding);
      expect(codingRooms.length, 1);
      expect(codingRooms[0].title, 'Coding task');
    });

    test('listTaskRooms excludes archived by default', () async {
      final id1 = await service.createTaskRoom(
        title: 'Active task',
        goal: 'Active goal',
        taskType: TaskType.coding,
      );
      final id2 = await service.createTaskRoom(
        title: 'Archived task',
        goal: 'Archived goal',
        taskType: TaskType.coding,
      );

      await service.archiveTaskRoom(id2);

      final activeRooms = await service.listTaskRooms();
      expect(activeRooms.length, 1);
      expect(activeRooms[0].id, id1);

      final allRooms = await service.listTaskRooms(includeArchived: true);
      expect(allRooms.length, 2);
    });

    test('listTaskRooms respects limit and offset', () async {
      for (int i = 0; i < 5; i++) {
        await service.createTaskRoom(
          title: 'Task $i',
          goal: 'Goal $i',
          taskType: TaskType.coding,
        );
      }

      final firstPage = await service.listTaskRooms(limit: 2, offset: 0);
      expect(firstPage.length, 2);

      final secondPage = await service.listTaskRooms(limit: 2, offset: 2);
      expect(secondPage.length, 2);

      final thirdPage = await service.listTaskRooms(limit: 2, offset: 4);
      expect(thirdPage.length, 1);
    });

    test('updateTaskStatus updates status and progress', () async {
      final id = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      await service.updateTaskStatus(
        id: id,
        status: TaskStatus.running,
        progressPercent: 50,
        currentStep: 'Writing tests',
      );

      final room = await service.getTaskRoom(id);
      expect(room!.status, 'running');
      expect(room.progressPercent, 50);
      expect(room.currentStep, 'Writing tests');
      expect(room.completedAt, isNull);
    });

    test('updateTaskStatus sets completedAt for completed status', () async {
      final id = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      // Must transition through running first
      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.updateTaskStatus(id: id, status: TaskStatus.completed);

      final room = await service.getTaskRoom(id);
      expect(room!.status, 'completed');
      expect(room.completedAt, isNotNull);
      expect(room.archivedAt, isNull);
    });

    test('archiveTaskRoom sets archivedAt, not completedAt', () async {
      final id = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      await service.archiveTaskRoom(id);

      final room = await service.getTaskRoom(id);
      expect(room!.status, 'archived');
      expect(room.archivedAt, isNotNull);
      expect(room.completedAt, isNull);
    });

    test('updateTaskStatus validates progressPercent range', () async {
      final id = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      await service.updateTaskStatus(id: id, status: TaskStatus.running);

      // Valid range
      await service.updateTaskStatus(id: id, status: TaskStatus.running, progressPercent: 0);
      await service.updateTaskStatus(id: id, status: TaskStatus.running, progressPercent: 50);
      await service.updateTaskStatus(id: id, status: TaskStatus.running, progressPercent: 100);

      // Invalid range
      expect(
        () => service.updateTaskStatus(id: id, status: TaskStatus.running, progressPercent: -1),
        throwsArgumentError,
      );
      expect(
        () => service.updateTaskStatus(id: id, status: TaskStatus.running, progressPercent: 101),
        throwsArgumentError,
      );
    });

    test('terminal states cannot be updated with same-state updates', () async {
      final id = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      // Transition to completed (terminal state)
      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.updateTaskStatus(id: id, status: TaskStatus.completed);

      // Attempting to update progress on completed task should fail
      expect(
        () => service.updateTaskStatus(
          id: id,
          status: TaskStatus.completed,
          progressPercent: 100,
        ),
        throwsStateError,
      );

      // Same for other terminal states
      final id2 = await service.createTaskRoom(
        title: 'Test task 2',
        goal: 'Test goal 2',
        taskType: TaskType.coding,
      );
      await service.updateTaskStatus(id: id2, status: TaskStatus.cancelled);

      expect(
        () => service.updateTaskStatus(
          id: id2,
          status: TaskStatus.cancelled,
          currentStep: 'Should not work',
        ),
        throwsStateError,
      );
    });

    test('non-terminal states allow same-state progress updates', () async {
      final id = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      await service.updateTaskStatus(id: id, status: TaskStatus.running);

      // Should succeed: running -> running with progress update
      await service.updateTaskStatus(
        id: id,
        status: TaskStatus.running,
        progressPercent: 50,
      );

      final room = await service.getTaskRoom(id);
      expect(room!.progressPercent, 50);

      // Another same-state update
      await service.updateTaskStatus(
        id: id,
        status: TaskStatus.running,
        progressPercent: 75,
        currentStep: 'Running tests',
      );

      final updated = await service.getTaskRoom(id);
      expect(updated!.progressPercent, 75);
      expect(updated.currentStep, 'Running tests');
    });

    test('updateTaskContext updates context and permissions', () async {
      final id = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      await service.updateTaskContext(
        id: id,
        context: {'new_key': 'new_value'},
        permissions: {'admin': true},
      );

      final room = await service.getTaskRoom(id);
      expect(room!.contextJson, contains('new_key'));
      expect(room.permissionsJson, contains('admin'));
    });

    test('archiveTaskRoom marks room as archived', () async {
      final taskId = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Test artifact',
        content: {'diff': 'some changes'},
      );

      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Which approach?',
        options: ['A', 'B'],
        selectedOption: 'A',
      );

      // Test soft delete (archive)
      await service.archiveTaskRoom(taskId);

      final room = await service.getTaskRoom(taskId);
      expect(room, isNotNull);
      expect(room!.status, 'archived');

      // Artifacts and decisions should still exist
      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts, isNotEmpty);

      final decisions = await service.getTaskDecisions(taskId);
      expect(decisions, isNotEmpty);
    });

    test('permanentlyDeleteTaskRoom removes room and cascades (deprecated)',
        () async {
      final taskId = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );

      await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Test artifact',
        content: {'diff': 'some changes'},
      );

      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Which approach?',
        options: ['A', 'B'],
        selectedOption: 'A',
      );

      // ignore: deprecated_member_use
      await service.permanentlyDeleteTaskRoom(taskId);

      final room = await service.getTaskRoom(taskId);
      expect(room, isNull);

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts, isEmpty);

      final decisions = await service.getTaskDecisions(taskId);
      expect(decisions, isEmpty);
    });
  });

  group('TaskRoomService - Queue', () {
    test('enqueueTaskRoom initializes queue metadata', () async {
      final id = await service.enqueueTaskRoom(
        title: 'Queue task',
        goal: 'Demonstrate enqueue',
        taskType: TaskType.contentGeneration,
        maxRetries: 5,
      );

      final room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.pending.value);
      final queue = parseQueueContext(room);
      expect(queue['maxRetries'], 5);
      expect(queue['retryCount'], 0);
    });

    test('enqueueTaskRoom rejects negative maxRetries', () async {
      expect(
        () => service.enqueueTaskRoom(
          title: 'Invalid retry policy',
          goal: 'Must reject negative retries',
          taskType: TaskType.coding,
          maxRetries: -1,
        ),
        throwsArgumentError,
      );
    });

    test('host queue scope round-trips while legacy queue stays compatible',
        () async {
      const scope = TaskQueueHostScope(
        profileId: 'desktop_workbench_task_queue_v1',
        scopeType: 'conversation',
        scopeId: 'persona-i',
      );
      final scopedId = await service.enqueueTaskRoom(
        title: 'Scoped queue task',
        goal: 'Only the product-owned conversation can control this task',
        taskType: TaskType.other,
        conversationId: 'persona-i',
        queueHostScope: scope,
      );
      final legacyId = await service.enqueueTaskRoom(
        title: 'Legacy queue task',
        goal: 'Keep the existing wire format valid',
        taskType: TaskType.other,
      );

      final scoped = await service.getTaskQueueSnapshot(scopedId);
      final legacy = await service.getTaskQueueSnapshot(legacyId);

      expect(scoped, isNotNull);
      expect(scoped!.belongsTo(scope), isTrue);
      expect(scoped.status, TaskStatus.pending);
      expect(scoped.retryCount, 0);
      expect(legacy, isNotNull);
      expect(legacy!.ownerProfileId, isNull);
      expect(legacy.maxRetries, 3);
      expect(legacy.retryCount, 0);
    });

    test('latest scoped lookup never returns another conversation task',
        () async {
      const scope = TaskQueueHostScope(
        profileId: 'desktop_workbench_task_queue_v1',
        scopeType: 'conversation',
        scopeId: 'persona-i',
      );
      const otherScope = TaskQueueHostScope(
        profileId: 'desktop_workbench_task_queue_v1',
        scopeType: 'conversation',
        scopeId: 'persona-other',
      );
      final ownedId = await service.enqueueTaskRoom(
        title: 'Owned task',
        goal: 'Stay in persona-i',
        taskType: TaskType.other,
        conversationId: 'persona-i',
        queueHostScope: scope,
      );
      await service.enqueueTaskRoom(
        title: 'Other task',
        goal: 'Stay in persona-other',
        taskType: TaskType.other,
        conversationId: 'persona-other',
        queueHostScope: otherScope,
      );

      expect((await service.findLatestTaskQueueForScope(scope))?.id, ownedId);
      expect(
        (await service.findLatestTaskQueueForScope(otherScope))?.scopeId,
        'persona-other',
      );
    });

    test('idempotent enqueue persists request key and fails closed on conflict',
        () async {
      const scope = TaskQueueHostScope(
        profileId: 'desktop_workbench_task_queue_v1',
        scopeType: 'conversation',
        scopeId: 'persona-i',
      );
      final first = await service.enqueueTaskRoomIdempotent(
        requestId: 'stable-enqueue-1',
        title: 'Stable task',
        goal: 'Create exactly one task',
        taskType: TaskType.other,
        conversationId: 'persona-i',
        queueHostScope: scope,
      );
      final repeated = await service.enqueueTaskRoomIdempotent(
        requestId: 'stable-enqueue-1',
        title: 'Stable task',
        goal: 'Create exactly one task',
        taskType: TaskType.other,
        conversationId: 'persona-i',
        queueHostScope: scope,
      );
      final restarted = TaskRoomService(db: db);
      final afterRestart = await restarted.enqueueTaskRoomIdempotent(
        requestId: 'stable-enqueue-1',
        title: 'Stable task',
        goal: 'Create exactly one task',
        taskType: TaskType.other,
        conversationId: 'persona-i',
        queueHostScope: scope,
      );

      expect(first.changed, isTrue);
      expect(repeated.changed, isFalse);
      expect(afterRestart.changed, isFalse);
      expect(repeated.snapshot.id, first.snapshot.id);
      expect(afterRestart.snapshot.id, first.snapshot.id);
      expect(first.snapshot.requestId, 'stable-enqueue-1');
      expect(
        (await service.findTaskQueueByRequestId(
          scope: scope,
          requestId: 'stable-enqueue-1',
        ))
            ?.id,
        first.snapshot.id,
      );
      expect(await db.select(db.taskRooms).get(), hasLength(1));

      await expectLater(
        restarted.enqueueTaskRoomIdempotent(
          requestId: 'stable-enqueue-1',
          title: 'Changed task',
          goal: 'Conflicting payload must not overwrite or duplicate',
          taskType: TaskType.other,
          conversationId: 'persona-i',
          queueHostScope: scope,
        ),
        throwsA(isA<TaskQueueIdempotencyConflict>()),
      );
      expect(await db.select(db.taskRooms).get(), hasLength(1));
    });

    test('getTaskStatus returns normalized status', () async {
      final id = await service.createTaskRoom(
        title: 'Status task',
        goal: 'Check status',
        taskType: TaskType.coding,
      );

      expect(await service.getTaskStatus(id), TaskStatus.pending);
      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      expect(await service.getTaskStatus(id), TaskStatus.running);
    });

    test('pause/resume support idempotent transitions and reason persistence', () async {
      final id = await service.createTaskRoom(
        title: 'Pause task',
        goal: 'Testing pause and resume',
        taskType: TaskType.planning,
      );
      await service.updateTaskStatus(id: id, status: TaskStatus.running);

      await service.pauseTaskRoom(id: id, reason: 'user requested');
      var room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.blocked.value);
      expect(parseQueueContext(room)['pauseReason'], 'user requested');
      expect(parseQueueContext(room)['resumableState'], 'paused');

      // resume is idempotent when already running
      await service.resumeTaskRoom(id);
      room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.running.value);
      expect(parseQueueContext(room).containsKey('pauseReason'), isFalse);
      expect(parseQueueContext(room).containsKey('resumableState'), isFalse);

      await service.resumeTaskRoom(id);
      room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.running.value);
    });

    test('resumeTaskRoom rejects blocked tasks not marked by the queue',
        () async {
      final id = await service.createTaskRoom(
        title: 'Domain blocked task',
        goal: 'Do not bypass another blocked reason',
        taskType: TaskType.planning,
      );
      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.updateTaskStatus(id: id, status: TaskStatus.blocked);

      expect(() => service.resumeTaskRoom(id), throwsStateError);
      final room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.blocked.value);
      expect(parseQueueContext(room).containsKey('resumableState'), isFalse);
    });

    test('cancelTaskRoom is idempotent in terminal or canceled states', () async {
      final id = await service.createTaskRoom(
        title: 'Cancel task',
        goal: 'Testing cancel',
        taskType: TaskType.debugging,
      );
      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.cancelTaskRoom(id);
      await service.cancelTaskRoom(id);

      final room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.cancelled.value);
    });

    test('retryTaskRoom enforces max retries and increments retryCount', () async {
      final id = await service.createTaskRoom(
        title: 'Retry task',
        goal: 'Testing retry',
        taskType: TaskType.media,
        maxRetries: 1,
      );

      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.updateTaskStatus(id: id, status: TaskStatus.failed, failureReason: 'network');

      var room = await service.getTaskRoom(id);
      expect(TaskStatus.fromString(room!.status), TaskStatus.failed);
      expect(parseQueueContext(room)['failedReason'], 'network');
      expect(parseQueueContext(room)['retryCount'], 0);

      await service.retryTaskRoom(id: id);
      room = await service.getTaskRoom(id);
      expect(TaskStatus.fromString(room!.status), TaskStatus.pending);
      expect(parseQueueContext(room)['retryCount'], 1);
      expect(parseQueueContext(room).containsKey('failedReason'), isFalse);

      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.updateTaskStatus(id: id, status: TaskStatus.failed, failureReason: 'again');
      expect(
        () => service.retryTaskRoom(id: id),
        throwsStateError,
      );
    });

    test('failed and retry transitions persist queue state with status',
        () async {
      final id = await service.enqueueTaskRoom(
        title: 'Atomic queue transition',
        goal: 'Keep status and queue metadata paired',
        taskType: TaskType.coding,
      );
      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.updateTaskStatus(
        id: id,
        status: TaskStatus.failed,
        failureReason: 'connection lost',
      );

      var room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.failed.value);
      expect(parseQueueContext(room)['failedReason'], 'connection lost');
      expect(parseQueueContext(room)['lastFailedAt'], isA<int>());

      await service.retryTaskRoom(id: id);
      room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.pending.value);
      expect(parseQueueContext(room)['retryCount'], 1);
      expect(parseQueueContext(room).containsKey('failedReason'), isFalse);
      expect(parseQueueContext(room).containsKey('lastFailedAt'), isFalse);
    });

    test('generic status updates cannot bypass queue retry or resume guards',
        () async {
      final failedId = await service.enqueueTaskRoom(
        title: 'Retry guard',
        goal: 'Reject direct failed to pending',
        taskType: TaskType.coding,
      );
      await service.updateTaskStatus(id: failedId, status: TaskStatus.running);
      await service.updateTaskStatus(id: failedId, status: TaskStatus.failed);
      expect(
        () => service.updateTaskStatus(id: failedId, status: TaskStatus.pending),
        throwsStateError,
      );

      final blockedId = await service.createTaskRoom(
        title: 'Resume guard',
        goal: 'Reject direct blocked to running',
        taskType: TaskType.coding,
      );
      await service.updateTaskStatus(id: blockedId, status: TaskStatus.running);
      await service.updateTaskStatus(id: blockedId, status: TaskStatus.blocked);
      expect(
        () => service.updateTaskStatus(id: blockedId, status: TaskStatus.running),
        throwsStateError,
      );
    });

    test('restoreInterruptedTaskRooms converts running tasks to blocked with recovery marker', () async {
      final runningId = await service.createTaskRoom(
        title: 'Running task',
        goal: 'Need recovery',
        taskType: TaskType.whiteboard,
      );
      await service.updateTaskStatus(id: runningId, status: TaskStatus.running);

      final completedId = await service.createTaskRoom(
        title: 'Done task',
        goal: 'Should stay done',
        taskType: TaskType.whiteboard,
      );
      await service.updateTaskStatus(
        id: completedId,
        status: TaskStatus.running,
      );
      await service.updateTaskStatus(id: completedId, status: TaskStatus.completed);

      final restored = await service.restoreInterruptedTaskRooms();
      expect(restored, 1);

      final restoredRoom = await service.getTaskRoom(runningId);
      expect(TaskStatus.fromString(restoredRoom!.status), TaskStatus.blocked);
      expect(
        parseQueueContext(restoredRoom)['pauseReason'],
        'interrupted_by_restart',
      );
      expect(parseQueueContext(restoredRoom).containsKey('interruptedReason'), isTrue);
      expect(parseQueueContext(restoredRoom)['resumableState'], 'interrupted');

      final untouchedRoom = await service.getTaskRoom(completedId);
      expect(TaskStatus.fromString(untouchedRoom!.status), TaskStatus.completed);
    });

    test('startup recovery runs once and leaves interrupted work resumable',
        () async {
      final id = await service.enqueueTaskRoom(
        title: 'Restarted task',
        goal: 'Recover only once',
        taskType: TaskType.whiteboard,
      );
      await service.updateTaskStatus(id: id, status: TaskStatus.running);

      expect(await service.restoreInterruptedTaskRoomsOnce(), 1);
      expect(await service.restoreInterruptedTaskRoomsOnce(), 1);

      final room = await service.getTaskRoom(id);
      expect(room!.status, TaskStatus.blocked.value);
      expect(parseQueueContext(room)['resumableState'], 'interrupted');
      await service.resumeTaskRoom(id);
      expect(await service.getTaskStatus(id), TaskStatus.running);
    });

    test('非法状态不允许执行 queue 操作', () async {
      final id = await service.createTaskRoom(
        title: 'Illegal queue transition',
        goal: 'Blocked case',
        taskType: TaskType.coding,
      );
      await service.updateTaskStatus(id: id, status: TaskStatus.running);
      await service.updateTaskStatus(id: id, status: TaskStatus.completed);

      expect(() => service.resumeTaskRoom(id), throwsA(isA<StateError>()));
      expect(
        () => service.pauseTaskRoom(id: id),
        throwsA(isA<StateError>()),
      );
      expect(() => service.retryTaskRoom(id: id), throwsA(isA<StateError>()));
    });
  });

  group('TaskRoomService - Artifacts', () {
    late String taskId;

    setUp(() async {
      taskId = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );
    });

    test('recordArtifact creates artifact with all fields', () async {
      final artifactId = await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Added new feature',
        content: {'files': ['file1.dart', 'file2.dart'], 'lines': 150},
        sizeBytes: 4096,
        mimeType: 'application/json',
        storageRef: 's3://bucket/artifact',
      );

      expect(artifactId, isNotEmpty);

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts.length, 1);
      expect(artifacts[0].artifactType, 'code_diff');
      expect(artifacts[0].title, 'Added new feature');
      expect(artifacts[0].sizeBytes, 4096);
      expect(artifacts[0].mimeType, 'application/json');
    });

    test('getTaskArtifacts returns artifacts in reverse chronological order',
        () async {
      await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'First',
        content: {},
      );

      await Future.delayed(const Duration(milliseconds: 10));

      await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.analysisResult,
        title: 'Second',
        content: {},
      );

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts.length, 2);
      expect(artifacts[0].title, 'Second');
      expect(artifacts[1].title, 'First');
    });

    test('getArtifactsByType filters by artifact type', () async {
      await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Code change',
        content: {},
      );

      await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.errorLog,
        title: 'Error occurred',
        content: {},
      );

      final codeDiffs =
          await service.getArtifactsByType(taskId: taskId, artifactType: ArtifactType.codeDiff);
      expect(codeDiffs.length, 1);
      expect(codeDiffs[0].title, 'Code change');

      final errorLogs =
          await service.getArtifactsByType(taskId: taskId, artifactType: ArtifactType.errorLog);
      expect(errorLogs.length, 1);
      expect(errorLogs[0].title, 'Error occurred');
    });

    test('retractArtifact filters out retracted artifacts', () async {
      final artifactId = await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Original',
        content: {'data': 'original'},
      );

      await service.retractArtifact(
        originalArtifactId: artifactId,
        reason: 'Found a better approach',
      );

      final artifacts = await service.getTaskArtifacts(taskId);
      // Should return empty because original is retracted and retraction marker is filtered
      expect(artifacts, isEmpty);
    });

    test('permanentlyDeleteArtifact removes artifact (deprecated)', () async {
      final artifactId = await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Test',
        content: {},
      );

      // ignore: deprecated_member_use
      await service.permanentlyDeleteArtifact(artifactId);

      final artifacts = await service.getTaskArtifacts(taskId);
      expect(artifacts, isEmpty);
    });
  });

  group('TaskRoomService - Decisions', () {
    late String taskId;

    setUp(() async {
      taskId = await service.createTaskRoom(
        title: 'Test task',
        goal: 'Test goal',
        taskType: TaskType.coding,
      );
    });

    test('recordDecision creates decision with all fields', () async {
      final decisionId = await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Use REST or GraphQL?',
        options: ['REST', 'GraphQL'],
        selectedOption: 'GraphQL',
        reasoning: 'Better for complex queries',
      );

      expect(decisionId, isNotEmpty);

      final decisions = await service.getTaskDecisions(taskId);
      expect(decisions.length, 1);
      expect(decisions[0].decisionType, 'approach_choice');
      expect(decisions[0].question, 'Use REST or GraphQL?');
      expect(decisions[0].selectedOption, 'GraphQL');
      expect(decisions[0].reasoning, 'Better for complex queries');
    });

    test('getTaskDecisions returns decisions in reverse chronological order',
        () async {
      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.parameterValue,
        question: 'First decision',
        options: ['A', 'B'],
        selectedOption: 'A',
      );

      await Future.delayed(const Duration(milliseconds: 10));

      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approval,
        question: 'Second decision',
        options: ['Yes', 'No'],
        selectedOption: 'Yes',
      );

      final decisions = await service.getTaskDecisions(taskId);
      expect(decisions.length, 2);
      expect(decisions[0].question, 'Second decision');
      expect(decisions[1].question, 'First decision');
    });

    test('getDecisionsByType filters by decision type', () async {
      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Approach',
        options: ['A', 'B'],
        selectedOption: 'A',
        decidedBy: 'user',
        status: DecisionStatus.resolved,
      );

      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approval,
        question: 'Approve?',
        options: ['Yes', 'No'],
        selectedOption: 'Yes',
        decidedBy: 'user',
        status: DecisionStatus.resolved,
      );

      final approaches = await service.getDecisionsByType(
          taskId: taskId, decisionType: DecisionType.approachChoice);
      expect(approaches.length, 1);
      expect(approaches[0].question, 'Approach');

      final approvals = await service.getDecisionsByType(
          taskId: taskId, decisionType: DecisionType.approval);
      expect(approvals.length, 1);
      expect(approvals[0].question, 'Approve?');
    });

    test('recordDecision supports pending decisions', () async {
      final decisionId = await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Which approach?',
        options: ['REST', 'GraphQL'],
        status: DecisionStatus.pending,
      );

      final decisions = await service.getTaskDecisions(taskId);
      expect(decisions.length, 1);
      expect(decisions[0].status, 'pending');
      expect(decisions[0].selectedOption, isNull);
      expect(decisions[0].decidedBy, isNull);
      expect(decisions[0].decidedAt, isNull);

      // Resolve the decision (creates a new record)
      final resolvedId = await service.resolveDecision(
        decisionId: decisionId,
        selectedOption: 'GraphQL',
        decidedBy: 'user',
        reasoning: 'Better for complex queries',
      );

      // After resolving, getTaskDecisions returns only the resolved version (pending is superseded)
      final resolved = await service.getTaskDecisions(taskId);
      expect(resolved.length, 1);
      expect(resolved[0].id, resolvedId);
      expect(resolved[0].status, 'resolved');
      expect(resolved[0].selectedOption, 'GraphQL');
      expect(resolved[0].decidedBy, 'user');
      expect(resolved[0].decidedAt, isNotNull);
      expect(resolved[0].supersedesDecisionId, decisionId);

      // includeSuperseded=true shows both records
      final allDecisions = await service.getTaskDecisions(taskId, includeSuperseded: true);
      expect(allDecisions.length, 2);
      final pending = allDecisions.firstWhere((d) => d.id == decisionId);
      expect(pending.status, 'pending'); // Original pending record unchanged
    });

    test('getPendingDecisions filters by pending status', () async {
      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Pending 1',
        options: ['A', 'B'],
        status: DecisionStatus.pending,
      );

      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approval,
        question: 'Resolved',
        options: ['Yes', 'No'],
        selectedOption: 'Yes',
        decidedBy: 'user',
        status: DecisionStatus.resolved,
      );

      final pending = await service.getPendingDecisions(taskId);
      expect(pending.length, 1);
      expect(pending[0].question, 'Pending 1');
    });

    test('getPendingDecisions excludes resolved decisions', () async {
      final decisionId = await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Which approach?',
        options: ['REST', 'GraphQL'],
        status: DecisionStatus.pending,
      );

      // Initially pending
      var pending = await service.getPendingDecisions(taskId);
      expect(pending.length, 1);
      expect(pending[0].id, decisionId);

      // Resolve the decision
      await service.resolveDecision(
        decisionId: decisionId,
        selectedOption: 'GraphQL',
        decidedBy: 'user',
      );

      // After resolution, getPendingDecisions should not return the original pending record
      pending = await service.getPendingDecisions(taskId);
      expect(pending.length, 0);
    });

    test('resolveDecision fails when resolving same decision twice', () async {
      final decisionId = await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Which approach?',
        options: ['REST', 'GraphQL'],
        status: DecisionStatus.pending,
      );

      // First resolution succeeds
      await service.resolveDecision(
        decisionId: decisionId,
        selectedOption: 'GraphQL',
        decidedBy: 'user',
      );

      // Second resolution should fail
      expect(
        () => service.resolveDecision(
          decisionId: decisionId,
          selectedOption: 'REST',
          decidedBy: 'user',
        ),
        throwsStateError,
      );
    });

    test('resolveDecision fails when selectedOption not in original options', () async {
      final decisionId = await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approachChoice,
        question: 'Which approach?',
        options: ['REST', 'GraphQL'],
        status: DecisionStatus.pending,
      );

      expect(
        () => service.resolveDecision(
          decisionId: decisionId,
          selectedOption: 'gRPC', // Not in original options
          decidedBy: 'user',
        ),
        throwsArgumentError,
      );
    });
  });

  group('TaskRoomService - Integration', () {
    test('getTaskRoomFullContext returns complete context', () async {
      final taskId = await service.createTaskRoom(
        title: 'Full context test',
        goal: 'Test full context',
        taskType: TaskType.coding,
      );

      await service.recordArtifact(
        taskId: taskId,
        artifactType: ArtifactType.codeDiff,
        title: 'Artifact 1',
        content: {},
      );

      await service.recordDecision(
        taskId: taskId,
        decisionType: DecisionType.approval,
        question: 'Decision 1',
        options: ['Yes', 'No'],
        selectedOption: 'Yes',
      );

      // Note: messages would need to be added through PersonaChatService
      // with taskRoomId set, which is outside the scope of this service test

      final context = await service.getTaskRoomFullContext(taskId);

      expect(context['room'], isNotNull);
      expect(context['artifacts'], hasLength(1));
      expect(context['decisions'], hasLength(1));
      expect(context['messages'], isNotNull);
    });

    test('getTaskRoomFullContext throws for non-existent task', () async {
      expect(
        () => service.getTaskRoomFullContext('non-existent'),
        throwsStateError,
      );
    });
  });
}
