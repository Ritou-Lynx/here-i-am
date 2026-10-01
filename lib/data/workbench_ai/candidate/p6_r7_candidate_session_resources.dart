import 'dart:async';

import '../task_queue/workbench_task_queue_execution.dart';
import '../../memory_v3/services/task_room_service.dart'
    show TaskQueueHostScope;

/// Retains each original monitor join before a later pause/cancel can remove
/// that attempt from the shared controller's current-task map.
class P6R7CandidateExecution extends WorkbenchTaskQueueExecution {
  P6R7CandidateExecution({
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
  Future<bool> start(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _retain(
          id, () => super.start(id: id, scope: scope, requestId: requestId));

  @override
  Future<bool> resume(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _retain(
          id, () => super.resume(id: id, scope: scope, requestId: requestId));

  @override
  Future<bool> retry(
          {required String id,
          required TaskQueueHostScope scope,
          required String requestId}) =>
      _retain(
          id, () => super.retry(id: id, scope: scope, requestId: requestId));

  /// Call after quiescence and lifecycle/host close, never before stopping work.
  Future<void> drainAfterHostClose() async => Future.wait<void>(_tails);
}

enum P6R7CandidateResourceCloseState { notRequested, confirmed, unknown }

/// Local observations only. This result grants no recovery or file authority.
class P6R7CandidateSessionCloseResult {
  const P6R7CandidateSessionCloseResult._(
      this.execution, this.store, this.client);

  static const unknown = P6R7CandidateSessionCloseResult._(
    P6R7CandidateResourceCloseState.unknown,
    P6R7CandidateResourceCloseState.unknown,
    P6R7CandidateResourceCloseState.unknown,
  );

  final P6R7CandidateResourceCloseState execution;
  final P6R7CandidateResourceCloseState store;
  final P6R7CandidateResourceCloseState client;

  bool get closed => [execution, store, client]
      .every((state) => state == P6R7CandidateResourceCloseState.confirmed);

  Map<String, Object> toJson() => {
        'schema': 'p6_r7_candidate_session_close_v1',
        'execution': execution.name,
        'store': store.name,
        'client': client.name,
      };
}

/// Called only after UI quiescence, lifecycle convergence and owned-host exit.
/// Failed close is sticky: Store.close itself may become a no-op after failing.
class P6R7CandidateSessionResources {
  P6R7CandidateSessionResources({
    required Future<void> Function() drainExecution,
    required Future<void> Function() closeStore,
    required void Function() closeClient,
  })  : _drainExecution = drainExecution,
        _closeStore = closeStore,
        _closeClient = closeClient;

  final Future<void> Function() _drainExecution;
  final Future<void> Function() _closeStore;
  final void Function() _closeClient;
  Future<P6R7CandidateSessionCloseResult>? _closeFuture;
  P6R7CandidateSessionCloseResult? _result;

  P6R7CandidateSessionCloseResult? get result => _result;

  Future<P6R7CandidateSessionCloseResult> close() => _closeFuture ??= _close();

  Future<P6R7CandidateSessionCloseResult> _close() async {
    var execution = P6R7CandidateResourceCloseState.unknown;
    var store = P6R7CandidateResourceCloseState.notRequested;
    var client = P6R7CandidateResourceCloseState.notRequested;
    try {
      // Do not wait for the live turn before lifecycle close. Once the original
      // host has exited, join its remaining monitor before releasing its DB.
      await _drainExecution();
      execution = P6R7CandidateResourceCloseState.confirmed;
      try {
        await _closeStore();
        store = P6R7CandidateResourceCloseState.confirmed;
      } on Object {
        store = P6R7CandidateResourceCloseState.unknown;
      }
      try {
        _closeClient();
        client = P6R7CandidateResourceCloseState.confirmed;
      } on Object {
        client = P6R7CandidateResourceCloseState.unknown;
      }
    } on Object {
      // An unjoined monitor may still access either resource. Preserve both.
    }
    return _result =
        P6R7CandidateSessionCloseResult._(execution, store, client);
  }
}
