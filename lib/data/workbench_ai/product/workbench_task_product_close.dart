import 'dart:async';

import '../candidate/p6_r7_candidate_session_resources.dart';

enum WorkbenchTaskProductClosePhase {
  accepting,
  quiescing,
  conversation,
  queue,
  host,
  resources,
  witness,
  closed,
}

/// Application close ordering for an explicitly owned product session.
///
/// The bootstrap supplies the actual conversation, queue, held-process and
/// resource owners. This controller neither discovers processes nor grants
/// recovery authority. In particular, a detached notification cannot prove
/// that Windows waited for this Future or that the App exited.
class WorkbenchTaskProductClose {
  WorkbenchTaskProductClose({
    required void Function() fenceNewWork,
    required Future<bool> Function() closeConversation,
    required Future<void> Function() joinQueueInvocations,
    required Future<bool> Function() closeQueue,
    required Future<bool> Function() closeOwnedHost,
    required Future<P6R7CandidateSessionCloseResult> Function() closeResources,
    required Future<bool> Function() recordAppClosed,
  })  : _fenceNewWork = fenceNewWork,
        _closeConversation = closeConversation,
        _joinQueueInvocations = joinQueueInvocations,
        _closeQueue = closeQueue,
        _closeOwnedHost = closeOwnedHost,
        _closeResources = closeResources,
        _recordAppClosed = recordAppClosed;

  final void Function() _fenceNewWork;
  final Future<bool> Function() _closeConversation;
  final Future<void> Function() _joinQueueInvocations;
  final Future<bool> Function() _closeQueue;
  final Future<bool> Function() _closeOwnedHost;
  final Future<P6R7CandidateSessionCloseResult> Function() _closeResources;
  final Future<bool> Function() _recordAppClosed;

  WorkbenchTaskProductClosePhase _phase =
      WorkbenchTaskProductClosePhase.accepting;
  WorkbenchTaskProductClosePhase get phase => _phase;
  bool get acceptsNewWork => _phase == WorkbenchTaskProductClosePhase.accepting;
  bool get closed => _phase == WorkbenchTaskProductClosePhase.closed;

  Future<bool>? _attempt;
  bool _fenced = false;
  bool _fenceFailed = false;
  bool _conversationClosed = false;
  bool _invocationsJoined = false;
  bool _queueClosed = false;
  bool _hostClosed = false;
  Future<P6R7CandidateSessionCloseResult>? _resources;
  Future<bool>? _witness;

  /// Fence synchronously before returning control to an input/window callback.
  /// Unknown conversation/queue/host close can retry using the same owners.
  /// Resource and witness failures remain sticky: a second no-op close cannot
  /// manufacture proof after a partly closed Store or lost acknowledgement.
  Future<bool> close() {
    if (closed) return Future<bool>.value(true);
    final pending = _attempt;
    if (pending != null) return pending;
    final completion = Completer<bool>();
    final attempt = completion.future;
    _attempt = attempt;
    _phase = WorkbenchTaskProductClosePhase.quiescing;
    if (!_fenced && !_fenceFailed) {
      try {
        _fenceNewWork();
        _fenced = true;
      } on Object {
        _fenceFailed = true;
      }
    }
    unawaited(_run().then((result) {
      if (identical(_attempt, attempt)) _attempt = null;
      completion.complete(result);
    }));
    return attempt;
  }

  Future<bool> _run() async {
    if (_fenceFailed || !_fenced) return false;
    try {
      _phase = WorkbenchTaskProductClosePhase.conversation;
      if (!_conversationClosed) {
        _conversationClosed = await _closeConversation();
      }
      if (!_conversationClosed) return false;
      _phase = WorkbenchTaskProductClosePhase.queue;
      if (!_invocationsJoined) {
        await _joinQueueInvocations();
        _invocationsJoined = true;
      }
      if (!_queueClosed) _queueClosed = await _closeQueue();
      if (!_queueClosed) return false;
      _phase = WorkbenchTaskProductClosePhase.host;
      if (!_hostClosed) _hostClosed = await _closeOwnedHost();
      if (!_hostClosed) return false;
      _phase = WorkbenchTaskProductClosePhase.resources;
      _resources ??=
          Future<P6R7CandidateSessionCloseResult>.sync(_closeResources).onError(
              (Object _, StackTrace __) =>
                  P6R7CandidateSessionCloseResult.unknown);
      if (!(await _resources!).closed) return false;
      _phase = WorkbenchTaskProductClosePhase.witness;
      _witness ??= Future<bool>.sync(_recordAppClosed)
          .onError((Object _, StackTrace __) => false);
      if (!await _witness!) return false;
      _phase = WorkbenchTaskProductClosePhase.closed;
      return true;
    } on Object {
      return false;
    }
  }
}
