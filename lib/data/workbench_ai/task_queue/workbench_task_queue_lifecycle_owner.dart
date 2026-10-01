library;

import 'dart:async';

abstract interface class WorkbenchTaskQueueLifecycleController {
  /// `true` only when every binding this controller owned for this lifecycle
  /// request established ordinary close proof. `false` retains an unknown
  /// binding for retry.
  Future<bool> closeForHostLifecycle();
}

/// Application-level holder for controllers that have already been created by
/// the queue tool. It neither opens a database nor discovers persisted work.
class WorkbenchTaskQueueLifecycleOwner {
  WorkbenchTaskQueueLifecycleOwner();

  static final instance = WorkbenchTaskQueueLifecycleOwner();

  final Set<WorkbenchTaskQueueLifecycleController> _controllers = {};
  final Map<WorkbenchTaskQueueLifecycleController, Future<bool>> _requested =
      {};
  Future<bool>? _closing;
  bool _closeRequested = false;
  int _registrationEpoch = 0;

  void register(WorkbenchTaskQueueLifecycleController controller) {
    _controllers.add(controller);
    _registrationEpoch++;
    if (_closeRequested) {
      // A controller created after detached was requested is fenced now. An
      // active drain observes this same Future before it can report success.
      _requested.putIfAbsent(controller, () => _closeOne(controller));
    }
  }

  /// Best effort only. `false` means at least one binding remains unknown; it
  /// never represents a cancellation or task-completion receipt.
  Future<bool> closeForHostLifecycle() {
    final active = _closing;
    if (active != null) return active;
    _closeRequested = true;
    _requested.clear();
    final attempt = _drainCloseRequests();
    _closing = attempt;
    attempt.whenComplete(() {
      if (identical(_closing, attempt)) _closing = null;
    });
    return attempt;
  }

  Future<bool> _drainCloseRequests() async {
    var allConfirmed = true;
    while (true) {
      final epoch = _registrationEpoch;
      final controllers = _controllers.toList(growable: false);
      final results = await Future.wait<bool>(controllers.map(
        (controller) => _requested.putIfAbsent(
          controller,
          () => _closeOne(controller),
        ),
      ));
      allConfirmed = allConfirmed && results.every((result) => result);
      if (epoch == _registrationEpoch) return allConfirmed;
    }
  }

  Future<bool> _closeOne(WorkbenchTaskQueueLifecycleController controller) async {
    try {
      return await controller.closeForHostLifecycle();
    } on Object {
      // The controller retains its binding for a later lifecycle retry. A
      // detached Flutter callback must not turn a close error into success.
      return false;
    }
  }
}
