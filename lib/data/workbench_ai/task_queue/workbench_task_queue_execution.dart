library;

import 'dart:async';

import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';

import '../workbench_runtime_client.dart';
import 'workbench_task_queue_execution_controller.dart';
import 'workbench_task_queue_lifecycle_owner.dart';

const _executionErrorCodes = {
  'task_not_available',
  'task_not_startable',
  'task_not_resumable',
  'task_not_retryable',
  'task_retry_limit_reached',
  'execution_already_active',
  'execution_owner_unavailable',
  'execution_state_changed',
  'execution_claim_lost',
  'execution_request_limit',
  'runtime_stop_unconfirmed',
};

/// Supplied by the production text-only boundary. The ordinary conversation
/// gateway is NOT a safe default: empty dynamicTools does not disable built-ins.
typedef WorkbenchTaskTextSessionStarter = Future<WorkbenchTextTaskSession>
    Function(Map<String, dynamic> manifest);

/// Owns bounded provider-driven text attempts, completely separate from persona
/// sessions. Construction never scans, launches or changes existing tasks.
class WorkbenchTaskQueueExecution
    implements WorkbenchTaskQueueExecutionController, WorkbenchTaskQueueLifecycleController {
  WorkbenchTaskQueueExecution({
    required TaskRoomService service,
    required WorkbenchTextTaskStopGateway runtime,
    required WorkbenchTaskTextSessionStarter startTextSession,
    Duration pollInterval = const Duration(milliseconds: 350),
    Duration controlTimeout = const Duration(seconds: 25),
    Duration closeTimeout = const Duration(seconds: 150),
    Duration attemptTimeout = const Duration(minutes: 10),
  })  : _service = service,
        _runtime = runtime,
        _startTextSession = startTextSession,
        _pollInterval = pollInterval,
        _controlTimeout = controlTimeout,
        _closeTimeout = closeTimeout,
        _attemptTimeout = attemptTimeout;

  final TaskRoomService _service;
  final WorkbenchTextTaskStopGateway _runtime;
  final WorkbenchTaskTextSessionStarter _startTextSession;
  final Duration _pollInterval;
  final Duration _controlTimeout;
  final Duration _closeTimeout;
  final Duration _attemptTimeout;
  final Map<String, _ExecutionAttempt> _attempts = {};
  final Map<String, Future<bool>> _controls = {};
  final Set<_ExecutionAttempt> _lifecycleRetained = {};
  bool _hostClosing = false;

  @override
  Future<bool> start(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _schedule(id, scope, requestId, 'start');

  @override
  Future<bool> resume(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _schedule(id, scope, requestId, 'resume');

  @override
  Future<bool> retry(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _schedule(id, scope, requestId, 'retry');

  Future<bool> _schedule(String id, TaskQueueHostScope scope, String requestId,
          String action) =>
      _serialize(id, () async {
        if (_hostClosing) throw StateError('execution_owner_unavailable');
        final lease = await _service.claimTaskQueueExecution(
          id: id,
          scope: scope,
          requestId: requestId,
          action: action,
        );
        if (lease == null) return false;
        final attempt = _ExecutionAttempt(lease);
        _attempts[id] = attempt;
        try {
          if (_hostClosing) {
            attempt.hostClosing = true;
            throw StateError('runtime_stop_unconfirmed');
          }
          // Do not time out and abandon a session-creation Future: its late
          // result would leak a live session. The transport bounds this request.
          attempt.session = await _startTextSession({
            'task_id': id,
            'execution_epoch': lease.epoch,
            'execution_mode': 'isolated_text_only',
          });
          if (attempt.hostClosing || _hostClosing) {
            attempt.hostClosing = true;
            await _tryClose(attempt);
            _lifecycleRetained.add(attempt);
            throw StateError('runtime_stop_unconfirmed');
          }
          if (!await _service.writeTaskQueueExecution(
            lease: lease,
            expectedPhases: const {'starting'},
            phase: 'starting',
            status: TaskStatus.pending,
            sessionId: attempt.session!.sessionId,
          )) {
            await _close(attempt);
            throw StateError('execution_claim_lost');
          }
          if (attempt.hostClosing || _hostClosing) {
            attempt.hostClosing = true;
            await _tryClose(attempt);
            _lifecycleRetained.add(attempt);
            throw StateError('runtime_stop_unconfirmed');
          }
          attempt.turn = await _runtime.startTextTaskTurn(
            attempt.session!,
            _input(lease),
          );
          if (attempt.hostClosing || _hostClosing) {
            attempt.hostClosing = true;
            await _tryClose(attempt, interruptRequested: true);
            _lifecycleRetained.add(attempt);
            throw StateError('runtime_stop_unconfirmed');
          }
          final accepted = await _service.writeTaskQueueExecution(
            lease: lease,
            expectedPhases: const {'starting'},
            phase: 'running',
            status: TaskStatus.running,
            turnId: attempt.turn!.turnId,
            currentStep: action == 'resume'
                ? '已在新会话按任务目标和保存的部分文本重新执行'
                : '文字执行已开始；进度比例未知',
          );
          if (!accepted) {
            await _close(attempt);
            throw StateError('execution_claim_lost');
          }
          attempt.finished = _monitor(attempt);
          // Keep the Future available for lifecycle joins, and also observe its
          // error so a storage outage cannot become an unhandled background error.
          unawaited(attempt.finished!.catchError((Object _) {}));
          return true;
        } on Object catch (error) {
          final unavailable = error is WorkbenchRuntimeException &&
              error.code == 'unsupported_capability';
          final hostInterrupted = attempt.hostClosing;
          final stopped = hostInterrupted
              ? false
              : error is WorkbenchTextTaskIsolationException
              ? error.cleanupConfirmed
              : attempt.session == null ||
                  (await _tryClose(attempt))?.ordinaryCloseConfirmed == true;
          await _service.writeTaskQueueExecution(
            lease: lease,
            expectedPhases: const {'starting', 'running'},
            phase: stopped ? 'failed' : 'interrupted',
            status: stopped ? TaskStatus.failed : TaskStatus.blocked,
            reason: stopped
                ? (unavailable
                    ? 'text_only_isolation_unverified'
                    : 'runtime_start_failed')
                : (unavailable
                    ? 'text_only_isolation_unverified_cleanup_unconfirmed'
                    : 'runtime_start_outcome_unknown'),
            currentStep: stopped
                ? (unavailable ? '当前执行能力尚未通过文字任务隔离校验，未启动任务' : '执行未能启动')
                : (unavailable ? '任务未启动；隔离校验失败且会话关闭未确认' : '连接失败，执行结果未知；需显式恢复'),
          );
          if ((hostInterrupted || !stopped) && attempt.session != null) {
            _lifecycleRetained.add(attempt);
          }
          if (identical(_attempts[id], attempt)) _attempts.remove(id);
          rethrow;
        }
      });

  String _input(TaskQueueExecutionLease lease) =>
      'Complete the following standalone text task using only the supplied '
      'text. Return the requested text result. No tools, outside data, product '
      'actions, files, shell, network or memory writes are available. '
      'If the task needs those, explain the limitation in the text result.\n'
      'Task goal:\n${lease.goal}\n'
      '${lease.previousText.isEmpty ? '' : '\nThis is a new execution attempt, '
          'not a resumed provider turn. Previously saved partial text follows; '
          'produce one complete final result:\n${lease.previousText}'}';

  Future<void> _monitor(_ExecutionAttempt attempt) async {
    final deadline = DateTime.now().add(_attemptTimeout);
    try {
      while (!attempt.stopping) {
        if (DateTime.now().isAfter(deadline)) {
          throw const WorkbenchRuntimeException(
              'timeout', 'Task deadline reached');
        }
        final batch = await _runtime.readEvents(
          attempt.session!.sessionId,
          afterSequence: attempt.sequence,
        );
        if (attempt.stopping) return;
        for (final event in batch.events) {
          final sequence = (event['sequence'] as num?)?.toInt();
          if (sequence == null || sequence <= attempt.sequence) continue;
          attempt.sequence = sequence;
          final eventTurn = event['turn_id'];
          if (eventTurn != null && eventTurn != attempt.turn!.turnId) continue;
          final kind = event['kind'];
          if (kind == 'error' &&
              event['data'] is Map &&
              const ['runtime_unavailable', 'session_not_found', 'timeout']
                  .contains((event['data'] as Map)['code'])) {
            throw const WorkbenchRuntimeException(
                'runtime_unavailable', 'Runtime event reports connection loss');
          }
          if (kind == 'error' ||
              kind == 'approval_request' ||
              kind == 'tool_call') {
            throw const WorkbenchRuntimeException(
              'runtime_execution_rejected',
              'Provider failed or requested a tool',
            );
          }
          if (eventTurn != attempt.turn!.turnId) continue;
          if (kind == 'message_delta') {
            final data = event['data'];
            final text = data is Map ? data['text'] : null;
            if (text is! String) throw StateError('invalid_provider_text');
            if (attempt.text.length + text.length > 24000) {
              throw StateError('execution_output_limit');
            }
            attempt.text += text;
            if (!await _service.writeTaskQueueExecution(
              lease: attempt.lease,
              expectedPhases: const {'running'},
              phase: 'running',
              status: TaskStatus.running,
              sequence: sequence,
              resultText: attempt.text,
              currentStep: '已收到执行文本；进度比例未知',
            )) {
              return;
            }
          }
          if (kind == 'turn_status') {
            final status = event['status'];
            if (status == 'completed') {
              if (attempt.text.trim().isEmpty) {
                throw StateError('empty_provider_result');
              }
              await _service.writeTaskQueueExecution(
                lease: attempt.lease,
                expectedPhases: const {'running'},
                phase: 'completed',
                status: TaskStatus.completed,
                sequence: sequence,
                resultText: attempt.text,
                currentStep: '文字结果已完成并保存于独立任务',
              );
              return;
            }
            if (status == 'failed') throw StateError('provider_turn_failed');
            if (status == 'interrupted') {
              await _service.writeTaskQueueExecution(
                lease: attempt.lease,
                expectedPhases: const {'running'},
                phase: 'interrupted',
                status: TaskStatus.blocked,
                reason: 'provider_interrupted',
                currentStep: '执行已中断，需显式恢复',
              );
              return;
            }
          }
        }
        if (const ['closed', 'unavailable', 'failed'].contains(batch.status)) {
          throw const WorkbenchRuntimeException(
              'runtime_unavailable', 'Runtime session is no longer available');
        }
        // Polling delay drives transport only; it never fabricates progress.
        await Future<void>.delayed(_pollInterval);
      }
    } on Object catch (error) {
      if (!attempt.stopping) {
        final stopped =
            (await _tryClose(attempt))?.ordinaryCloseConfirmed ?? false;
        final unavailable = error is WorkbenchRuntimeException &&
            const ['runtime_unavailable', 'session_not_found', 'timeout']
                .contains(error.code);
        final interrupted = !stopped || unavailable;
        if (!stopped && attempt.session != null) {
          _lifecycleRetained.add(attempt);
        }
        await _service.writeTaskQueueExecution(
          lease: attempt.lease,
          expectedPhases: const {'running'},
          phase: interrupted ? 'interrupted' : 'failed',
          status: interrupted ? TaskStatus.blocked : TaskStatus.failed,
          reason: interrupted
              ? 'runtime_connection_lost'
              : 'provider_execution_failed',
          currentStep: interrupted ? '执行连接中断，结果未知；需显式恢复' : '执行失败，未生成完成结果',
        );
      }
    } finally {
      if (!attempt.stopping) {
        final receipt = await _tryClose(attempt);
        if (receipt?.ordinaryCloseConfirmed != true && attempt.session != null) {
          _lifecycleRetained.add(attempt);
        }
        if (identical(_attempts[attempt.lease.taskId], attempt)) {
          _attempts.remove(attempt.lease.taskId);
        }
      }
    }
  }

  @override
  Future<bool> pause(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _stop(id, scope, requestId, cancel: false);

  @override
  Future<bool> cancel(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _stop(id, scope, requestId, cancel: true);

  Future<bool> _stop(String id, TaskQueueHostScope scope, String requestId,
          {required bool cancel}) =>
      _serialize(id, () async {
        final snapshot = await _service.getTaskQueueSnapshot(id);
        if (snapshot == null || !snapshot.belongsTo(scope)) {
          throw StateError('task_not_available');
        }
        final attempt = _attempts[id];
        final fenced = await _service.beginTaskQueueExecutionStop(
          id: id,
          scope: scope,
          requestId: requestId,
          cancel: cancel,
          lease: attempt?.lease,
        );
        if (!fenced || attempt == null) return fenced;
        attempt.stopping = true;
        final receipt = await _tryClose(attempt, interruptRequested: true);
        final stopped = receipt?.cancellationConfirmed ?? false;
        if (receipt?.ordinaryCloseConfirmed != true && attempt.session != null) {
          _lifecycleRetained.add(attempt);
        }
        await _service.writeTaskQueueExecution(
          lease: attempt.lease,
          expectedPhases: const {'stopping'},
          phase: stopped ? (cancel ? 'cancelled' : 'paused') : 'interrupted',
          status: stopped
              ? (cancel ? TaskStatus.cancelled : TaskStatus.blocked)
              : TaskStatus.blocked,
          reason: stopped ? 'user_requested' : 'runtime_stop_unconfirmed',
          currentStep: stopped
              ? (cancel ? '执行已取消' : '执行已暂停；恢复将在新会话重新执行')
              : '无法确认执行器已停止；结果未知',
        );
        if (identical(_attempts[id], attempt)) _attempts.remove(id);
        if (!stopped) throw StateError('runtime_stop_unconfirmed');
        return true;
      });

  Future<WorkbenchTextTaskStopResult?> _close(
    _ExecutionAttempt attempt, {
    bool interruptRequested = false,
  }) async {
    if (attempt.closeReceipt != null) return attempt.closeReceipt;
    if (attempt.session == null) return null;
    final inFlight = attempt.closeFuture;
    if (inFlight != null) return inFlight;
    final requested =
        attempt.closeInterruptRequested ??= interruptRequested;
    final close = _closeBoundAttempt(attempt, interruptRequested: requested);
    attempt.closeFuture = close;
    try {
      final receipt = await close;
      attempt.closeReceipt = receipt;
      return receipt;
    } on Object {
      if (identical(attempt.closeFuture, close)) attempt.closeFuture = null;
      rethrow;
    }
  }

  Future<WorkbenchTextTaskStopResult> _closeBoundAttempt(
    _ExecutionAttempt attempt, {
    required bool interruptRequested,
  }) async {
    if (attempt.turn != null) {
      try {
        await _runtime
            .interruptTurn(
                sessionId: attempt.session!.sessionId,
                 turnId: attempt.turn!.turnId)
            .timeout(_controlTimeout);
      } on Object {
        // The typed receipt, not an interrupt ACK, is the authority on whether
        // dispatch reached the host. It can still prove a cancellation after a
        // lost response from this RPC.
      }
    }
    return _runtime
        .closeTextTaskSession(
          session: attempt.session!,
          turn: attempt.turn,
          interruptRequested: interruptRequested,
        )
        // Teardown can outlast an interrupt RPC while native resources drain.
        // Keep this wait finite without discarding its verified receipt early.
        .timeout(_closeTimeout);
  }

  Future<WorkbenchTextTaskStopResult?> _tryClose(
    _ExecutionAttempt attempt, {
    bool interruptRequested = false,
  }) async {
    try {
      return await _close(attempt, interruptRequested: interruptRequested);
    } on Object {
      return null;
    }
  }

  /// Fences only attempts already owned by this controller. It never discovers
  /// durable tasks or creates a replacement controller during host shutdown.
  @override
  Future<bool> closeForHostLifecycle() async {
    _hostClosing = true;
    // Existing controls include claim/create futures. Wait for them so a late
    // session is fenced and closed by _schedule before this result settles.
    await Future.wait<void>(_controls.values.map((control) async {
      try {
        await control;
      } on Object {
        // Its attempt, if any, remains in the retained set below.
      }
    }));
    final attempts = <_ExecutionAttempt>{
      ..._attempts.values,
      ..._lifecycleRetained,
    };
    final results = await Future.wait<bool>(attempts.map((attempt) async {
      attempt.hostClosing = true;
      attempt.stopping = true;
      _lifecycleRetained.add(attempt);
      final receipt =
          await _tryClose(attempt, interruptRequested: attempt.turn != null);
      try {
        await _service.writeTaskQueueExecution(
          lease: attempt.lease,
          expectedPhases: const {'starting', 'running', 'stopping'},
          phase: 'interrupted',
          status: TaskStatus.blocked,
          reason: 'runtime_connection_lost',
          currentStep: '宿主正在退出，执行停止结果未知；需显式恢复',
        );
      } on Object {
        // A persistence outage is also an unknown lifecycle outcome.
        return false;
      }
      final confirmed = receipt?.ordinaryCloseConfirmed == true;
      if (confirmed) {
        _lifecycleRetained.remove(attempt);
      }
      return confirmed;
    }));
    return results.every((result) => result);
  }

  Future<bool> _serialize(String id, Future<bool> Function() operation) {
    final previous = _controls[id] ?? Future<bool>.value(false);
    final next = previous
        .then((_) => operation(), onError: (Object _) => operation())
        .catchError((Object error) {
      if (error is WorkbenchTaskQueueExecutionException) throw error;
      if (error is TaskQueueIdempotencyConflict) {
        throw const WorkbenchTaskQueueExecutionException(
            'task_queue_request_conflict');
      }
      if (error is WorkbenchRuntimeException &&
          error.code == 'unsupported_capability') {
        throw const WorkbenchTaskQueueExecutionException(
            'text_only_isolation_unverified');
      }
      final code = error is StateError ? error.message : null;
      throw WorkbenchTaskQueueExecutionException(
        code is String && _executionErrorCodes.contains(code)
            ? code
            : 'runtime_execution_failed',
      );
    });
    _controls[id] = next;
    unawaited(next.then((_) {
      if (identical(_controls[id], next)) _controls.remove(id);
    }, onError: (Object _) {
      if (identical(_controls[id], next)) _controls.remove(id);
    }));
    return next;
  }

  /// Deterministic test/host lifecycle join; no polling of unrelated tasks.
  Future<void> waitForAttempt(String id) async {
    await _controls[id];
    await _attempts[id]?.finished;
  }
}

class _ExecutionAttempt {
  _ExecutionAttempt(this.lease);
  final TaskQueueExecutionLease lease;
  WorkbenchTextTaskSession? session;
  WorkbenchTextTaskTurn? turn;
  Future<void>? finished;
  int sequence = 0;
  String text = '';
  bool stopping = false;
  Future<WorkbenchTextTaskStopResult>? closeFuture;
  WorkbenchTextTaskStopResult? closeReceipt;
  bool? closeInterruptRequested;
  bool hostClosing = false;
}
