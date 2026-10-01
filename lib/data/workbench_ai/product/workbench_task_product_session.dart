library;

import 'dart:async';

import 'package:memex/data/memory_v3/services/task_room_service.dart';

import '../task_queue/workbench_runtime_task_queue_tool.dart';
import '../task_queue/workbench_task_queue_execution.dart';
import '../task_queue/workbench_task_queue_lifecycle_owner.dart';
import '../task_queue/workbench_task_queue_tool_host.dart';
import '../workbench_runtime_client.dart';

/// Trusted product bootstrap decides whether a queue authorization belongs to
/// this already-open TaskRoom. It is deliberately an input to the session:
/// runtime arguments never select a database, host, task, or scope.
abstract interface class WorkbenchTaskProductSessionBinding {
  bool accepts(WorkbenchTaskQueueAuthorization authorization);
}

/// Trusted host callback for the result that actually crossed the queue host.
/// It may bind an exact persisted task to its witness before this result is
/// returned or a later invocation is considered. It receives no model-supplied
/// authority fields.
typedef WorkbenchTaskProductSessionAfterInvoke = Future<void> Function({
  required WorkbenchRuntimeTaskQueueResult result,
  required WorkbenchTaskQueueAuthorization authorization,
});

/// A bounded composition for one already-open product TaskRoom and one
/// already-proven text runtime. Construction only wires existing resources; it
/// never starts a host, performs admission, scans/recoveries, or starts work.
class WorkbenchTaskProductSession {
  WorkbenchTaskProductSession({
    required TaskRoomService taskRoomService,
    required WorkbenchTextTaskStopGateway textRuntime,
    required WorkbenchTaskTextSessionStarter startTextSession,
    required WorkbenchTaskProductSessionBinding binding,
    required WorkbenchTaskProductSessionAfterInvoke afterInvoke,
    WorkbenchTaskQueueLifecycleOwner? lifecycleOwner,
    DesktopWorkbenchTaskQueueAuthorizationFactory authorizationFactory =
        const DesktopWorkbenchTaskQueueAuthorizationFactory(),
  })  : _binding = binding,
        _afterInvoke = afterInvoke,
        execution = WorkbenchTaskProductSessionExecution(
          service: taskRoomService,
          runtime: textRuntime,
          startTextSession: startTextSession,
        ),
        lifecycleOwner = lifecycleOwner ?? WorkbenchTaskQueueLifecycleOwner() {
    // This owner is session-local unless the trusted product bootstrap shares
    // one explicitly. Never fall back to the application singleton here.
    this.lifecycleOwner.register(execution);
    taskQueueTool = _WorkbenchTaskProductSessionTool(
      session: this,
      service: taskRoomService,
      execution: execution,
      authorizationFactory: authorizationFactory,
    );
  }

  final WorkbenchTaskProductSessionBinding _binding;
  final WorkbenchTaskProductSessionAfterInvoke _afterInvoke;
  final WorkbenchTaskProductSessionExecution execution;
  final WorkbenchTaskQueueLifecycleOwner lifecycleOwner;
  late final WorkbenchRuntimeTaskQueueTool taskQueueTool;

  final Set<Future<void>> _acceptedInvocations = {};
  Future<void> _serial = Future<void>.value();
  bool _acceptingInvocations = true;
  bool _frozen = false;

  bool get isQuiesced => !_acceptingInvocations;
  bool get isFrozen => _frozen;

  /// Synchronously fences every old reference to [taskQueueTool], then joins
  /// only calls that passed this session's binding before that fence. It does
  /// not close native resources or decide host lifecycle order.
  Future<void> quiesce() {
    _acceptingInvocations = false;
    return drainAcceptedInvocations();
  }

  /// Joins accepted tool calls without changing the admission fence.
  Future<void> drainAcceptedInvocations() =>
      Future.wait<void>(_acceptedInvocations.toList(growable: false));

  Future<WorkbenchRuntimeTaskQueueResult> _invoke(
    Future<WorkbenchRuntimeTaskQueueResult> Function() invoke,
    WorkbenchTaskQueueAuthorization authorization,
  ) {
    if (!_acceptingInvocations) return Future.value(_sessionUnavailable());
    // The call may be waiting behind a previous result-binding callback. It is
    // intentionally rechecked at dispatch so quiesce/freeze never lets a
    // queued call create a later DB write.
    final result = _serial.then<WorkbenchRuntimeTaskQueueResult>(
      (_) => _dispatch(invoke, authorization),
    );
    late final Future<void> retained;
    retained = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _acceptedInvocations.add(retained);
    unawaited(
        retained.whenComplete(() => _acceptedInvocations.remove(retained)));
    _serial = retained;
    return result;
  }

  Future<WorkbenchRuntimeTaskQueueResult> _dispatch(
    Future<WorkbenchRuntimeTaskQueueResult> Function() invoke,
    WorkbenchTaskQueueAuthorization authorization,
  ) async {
    if (!_acceptingInvocations || !_accepts(authorization)) {
      return _sessionUnavailable();
    }
    final result = await Future.sync(invoke);
    try {
      // Complete the trusted binding before exposing the queue result or
      // allowing another invocation to re-evaluate the binding.
      await _afterInvoke(result: result, authorization: authorization);
    } on Object {
      // The queue record is durable already. Do not invent a rollback or allow
      // another operation to run with an unbound/unknown host relationship.
      _frozen = true;
      _acceptingInvocations = false;
      return _sessionUnavailable();
    }
    return result;
  }

  bool _accepts(WorkbenchTaskQueueAuthorization authorization) {
    try {
      return _binding.accepts(authorization);
    } on Object {
      // A missing/failed trusted-host observation never permits DB access.
      return false;
    }
  }

  WorkbenchRuntimeTaskQueueResult _sessionUnavailable() =>
      const WorkbenchRuntimeTaskQueueResult(
        success: false,
        text:
            '{"status":"failed","error_code":"task_queue_session_unavailable"}',
      );
}

/// Retains each original monitor tail, including an older paused attempt that
/// a later resume has displaced from the base controller's active map.
class WorkbenchTaskProductSessionExecution extends WorkbenchTaskQueueExecution {
  WorkbenchTaskProductSessionExecution({
    required super.service,
    required super.runtime,
    required super.startTextSession,
  });

  final List<Future<void>> _tails = [];

  Future<bool> _retain(String id, Future<bool> Function() operation) async {
    try {
      return await operation();
    } finally {
      final tail = super.waitForAttempt(id);
      _tails.add(tail);
      unawaited(tail.catchError((Object _) {}));
    }
  }

  @override
  Future<bool> start({
    required String id,
    required TaskQueueHostScope scope,
    required String requestId,
  }) =>
      _retain(
          id, () => super.start(id: id, scope: scope, requestId: requestId));

  @override
  Future<bool> resume({
    required String id,
    required TaskQueueHostScope scope,
    required String requestId,
  }) =>
      _retain(
          id, () => super.resume(id: id, scope: scope, requestId: requestId));

  @override
  Future<bool> retry({
    required String id,
    required TaskQueueHostScope scope,
    required String requestId,
  }) =>
      _retain(
          id, () => super.retry(id: id, scope: scope, requestId: requestId));

  /// Call only after host/lifecycle closure has been resolved by the caller.
  Future<void> drainExecutionTails() => Future.wait<void>(_tails);
}

class _WorkbenchTaskProductSessionTool extends WorkbenchRuntimeTaskQueueTool {
  _WorkbenchTaskProductSessionTool({
    required this.session,
    required TaskRoomService service,
    required WorkbenchTaskProductSessionExecution execution,
    required super.authorizationFactory,
  }) : super(
          loadService: () async => service,
          loadExecutionController: (_) async => execution,
        );

  final WorkbenchTaskProductSession session;

  @override
  Future<WorkbenchRuntimeTaskQueueResult> invoke(
    Object? arguments, {
    required WorkbenchTaskQueueAuthorization authorization,
  }) =>
      session._invoke(
        () => super.invoke(arguments, authorization: authorization),
        authorization,
      );
}
