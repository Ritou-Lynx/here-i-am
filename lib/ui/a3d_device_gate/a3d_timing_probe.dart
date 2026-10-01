import 'dart:async';
import 'dart:collection';

import '../../data/services/activity/mda2_android/activity_outbox_process_lease.dart';
import '../../data/services/activity/mda2_android/android_activity_collector.dart';
import '../../data/services/activity/mda2_android/android_activity_normalizer.dart';
import '../../data/services/activity/mda2_android/android_activity_signal_platform.dart';

enum A3dTimingAction { manual, resume, poll, observer }

enum A3dTimingEvent {
  started,
  sealed,
  expired,
  armed,
  armUnused,
  armWindowRejected,
  holdWindowRejected,
  action,
  foregroundEntered,
  foregroundChanged,
  coalesced,
  busy,
  checkingAssigned,
  synchronizationAssigned,
  snapshot,
  published,
  readStarted,
  readFinished,
  readFailed,
  readTimedOut,
  controllerAccepted,
  controllerRejectedGeneration,
  controllerRejectedDisposed,
  controllerRejectedCollector,
  controllerRejectedRevision,
  getStarted,
  getCaptured,
  getDelivered,
  getFailed,
  holdStarted,
  holdCancelled,
  collectorAccepted,
  collectorRejectedGeneration,
  collectorRejectedPushGeneration,
  collectorRejectedRetiredSession,
  collectorRejectedTerminal,
  collectorRejectedRevision,
  collectorPublished,
  collectorReadFailed,
  disposed,
}

enum A3dTimingInvalid {
  overflow,
  callback,
  pendingAtSeal,
  cancelled,
  bounds,
  window
}

final class _HeldReply {
  _HeldReply(this.onCancel);
  final void Function() onCancel;
  final Completer<void> released = Completer<void>();
  bool cancelled = false;

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    onCancel();
    released.complete();
  }
}

final class _ReadScope {
  _ReadScope(this.requestId, this.caseId, this.hold);
  final int requestId;
  final int caseId;
  bool hold;
}

/// Debug-only local evidence. No identities, exceptions, persistence or I/O.
/// A service-extension read merely copies this bounded, monotonic event ring.
final class A3dTimingProbe {
  A3dTimingProbe() : this.testing();

  // Only tests inject time. The entrypoint uses the fixed 20s / 180s defaults.
  A3dTimingProbe.testing({
    this.capacity = 4096,
    this.window = const Duration(seconds: 180),
    this.holdDuration = const Duration(seconds: 20),
    Future<void> Function(Duration)? delay,
    int Function()? elapsedUs,
  })  : _delay = delay ?? Future<void>.delayed,
        _elapsedUs = elapsedUs;

  final int capacity;
  final Duration window;
  final Duration holdDuration;
  static const minimumObservationTail = Duration(seconds: 1);
  final Future<void> Function(Duration) _delay;
  final int Function()? _elapsedUs;
  final Stopwatch _clock = Stopwatch();
  final Queue<Map<String, Object?>> _events = Queue();
  final Set<A3dTimingInvalid> _invalid = {};
  final Object _zoneKey = Object();
  Timer? _expiry;
  A3dTimingAction? _armed;
  bool _recording = false;
  bool _sealed = false;
  bool _sealing = false;
  bool _disposed = false;
  int _seq = 0;
  int _caseId = 0;
  int _requestId = 0;
  int _outstanding = 0;
  final Set<_HeldReply> _holds = {};
  int _lastUs = 0;

  bool get recording => _recording;
  bool get sealed => _sealed;
  A3dTimingAction? get armed => _armed;

  bool start() {
    if (_recording) {
      _ensureWindow();
      return false;
    }
    if (_disposed || _outstanding != 0) return false;
    _events.clear();
    _invalid.clear();
    _seq = 0;
    _caseId = 0;
    _requestId = 0;
    _lastUs = 0;
    _armed = null;
    _sealed = false;
    _recording = true;
    _clock
      ..reset()
      ..start();
    record(A3dTimingEvent.started);
    _expiry = Timer(window, () => seal(expired: true));
    return true;
  }

  bool arm(A3dTimingAction action) {
    if (!_ensureWindow() ||
        _armed != null ||
        _holds.isNotEmpty ||
        (action != A3dTimingAction.manual &&
            action != A3dTimingAction.resume)) {
      return false;
    }
    if (!_hasHoldBudget()) {
      record(A3dTimingEvent.armWindowRejected, action: action);
      return false;
    }
    _armed = action;
    record(A3dTimingEvent.armed, action: action);
    return true;
  }

  int? _readElapsed() {
    try {
      return _elapsedUs?.call() ?? _clock.elapsedMicroseconds;
    } catch (_) {
      _invalid.add(A3dTimingInvalid.callback);
      return null;
    }
  }

  // A Timer is only a wakeup, not authority to extend the recording window.
  // Every mutating/read-injection entry checks the same monotonic deadline.
  bool _ensureWindow() {
    if (!_recording) return false;
    final elapsed = _readElapsed();
    if (elapsed == null) return false;
    if (elapsed >= window.inMicroseconds) {
      _sealAt(elapsed: elapsed, expired: true, windowExpired: true);
      return false;
    }
    return true;
  }

  bool _hasHoldBudget() {
    if (!_recording || _disposed) return false;
    try {
      final elapsed = _elapsedUs?.call() ?? _clock.elapsedMicroseconds;
      if (elapsed < _lastUs || elapsed < 0) {
        _invalid.add(A3dTimingInvalid.bounds);
        return false;
      }
      return window.inMicroseconds - elapsed >=
          holdDuration.inMicroseconds + minimumObservationTail.inMicroseconds;
    } catch (_) {
      _invalid.add(A3dTimingInvalid.callback);
      return false;
    }
  }

  void _rejectHoldWindow() {
    _invalid.add(A3dTimingInvalid.window);
    record(A3dTimingEvent.holdWindowRejected);
    record(A3dTimingEvent.armUnused);
  }

  void _cancelHolds({bool expired = false}) {
    if (_holds.isEmpty) return;
    _invalid.add(A3dTimingInvalid.cancelled);
    if (expired) _invalid.add(A3dTimingInvalid.window);
    for (final hold in _holds) {
      hold.cancel();
    }
  }

  void action(A3dTimingAction action) {
    if (!_ensureWindow()) return;
    if (action == A3dTimingAction.manual || action == A3dTimingAction.resume) {
      _caseId++;
    }
    record(A3dTimingEvent.action, action: action);
  }

  void skipped(A3dTimingAction action, {bool busy = false}) {
    record(
      busy ? A3dTimingEvent.busy : A3dTimingEvent.coalesced,
      action: action,
    );
    if (_armed == action) {
      // Do not silently inject a later action after the selected one coalesces.
      _armed = null;
      record(A3dTimingEvent.armUnused, action: action);
    }
  }

  Future<T> read<T>(A3dTimingAction action, Future<T> Function() body) {
    if (!_ensureWindow()) return body();
    final scope = _ReadScope(++_requestId, _caseId, _armed == action);
    if (scope.hold) _armed = null;
    _outstanding++;
    // Only the one _readCurrentStatus chain enters this zone; neither lifecycle
    // work nor Timer.periodic creation may be wrapped in it.
    return runZoned(() async {
      record(A3dTimingEvent.readStarted, action: action);
      try {
        return await body();
      } finally {
        if (scope.hold) record(A3dTimingEvent.armUnused, action: action);
        record(A3dTimingEvent.readFinished, action: action);
        _outstanding--;
      }
    }, zoneValues: {_zoneKey: scope});
  }

  Future<AndroidNativeObservationStatus> get(
    Future<AndroidNativeObservationStatus> Function() delegate,
  ) {
    if (!_ensureWindow()) return delegate();
    return _get(delegate);
  }

  Future<AndroidNativeObservationStatus> _get(
    Future<AndroidNativeObservationStatus> Function() delegate,
  ) async {
    final scope = Zone.current[_zoneKey] as _ReadScope?;
    final selected = scope?.hold ?? false;
    // Consume BEFORE the first await. Nested getters cannot reuse the token.
    if (selected) scope!.hold = false;
    _outstanding++;
    _HeldReply? hold;
    record(A3dTimingEvent.getStarted);
    if (selected) {
      if (_hasHoldBudget()) {
        // Bind only the cancellation observation to this existing read scope.
        // The deadline timer itself was created outside any read Zone.
        hold = _HeldReply(Zone.current
            .bindCallback(() => record(A3dTimingEvent.holdCancelled)));
        _holds.add(hold);
      } else {
        _rejectHoldWindow();
      }
    }
    try {
      final captured = await delegate();
      record(A3dTimingEvent.getCaptured, status: captured);
      if (hold != null) {
        if (!hold.cancelled) {
          // A slow real getter may consume the previously sufficient budget.
          // Never begin a 20s delay based only on the earlier arm/entry check.
          if (_hasHoldBudget()) {
            record(A3dTimingEvent.holdStarted, status: captured);
            await Future.any<void>(
                [_delay(holdDuration), hold.released.future]);
          } else {
            _rejectHoldWindow();
            hold.cancel();
          }
        }
        if (_disposed) {
          throw const AndroidActivityException('diagnostic_timing_cancelled');
        }
      }
      record(A3dTimingEvent.getDelivered, status: captured);
      return captured; // The exact immutable object, never a copy or rewrite.
    } catch (_) {
      record(A3dTimingEvent.getFailed);
      rethrow;
    } finally {
      if (hold != null) _holds.remove(hold);
      _outstanding--;
    }
  }

  void collector(AndroidCollectorObservationEvent event) {
    final kind = switch (event.kind) {
      AndroidCollectorObservationKind.accepted =>
        A3dTimingEvent.collectorAccepted,
      AndroidCollectorObservationKind.generation =>
        A3dTimingEvent.collectorRejectedGeneration,
      AndroidCollectorObservationKind.pushGeneration =>
        A3dTimingEvent.collectorRejectedPushGeneration,
      AndroidCollectorObservationKind.retiredSession =>
        A3dTimingEvent.collectorRejectedRetiredSession,
      AndroidCollectorObservationKind.terminal =>
        A3dTimingEvent.collectorRejectedTerminal,
      AndroidCollectorObservationKind.revision =>
        A3dTimingEvent.collectorRejectedRevision,
      AndroidCollectorObservationKind.published =>
        A3dTimingEvent.collectorPublished,
      AndroidCollectorObservationKind.readFailed =>
        A3dTimingEvent.collectorReadFailed,
    };
    record(
      kind,
      generation: event.generation,
      state: event.state,
      revision: event.revision,
      sameIdentity: event.sameIdentity,
      active: event.ready,
    );
  }

  void record(
    A3dTimingEvent event, {
    A3dTimingAction? action,
    AndroidNativeObservationStatus? status,
    AndroidNativeObservationState? state,
    int? revision,
    int? generation,
    int? synchronization,
    bool? active,
    bool? canQuery,
    bool? evidenceReady,
    bool? foreground,
    bool? sameIdentity,
  }) {
    if (!_recording) return;
    final elapsed = _readElapsed();
    if (elapsed == null) return;
    if (!_sealing && elapsed >= window.inMicroseconds) {
      _sealAt(elapsed: elapsed, expired: true, windowExpired: true);
      return;
    }
    try {
      final scope = Zone.current[_zoneKey] as _ReadScope?;
      if (elapsed < _lastUs) _invalid.add(A3dTimingInvalid.bounds);
      // The expiry/cancellation marker is allowed to show its true late time.
      // It is never clamped or made eligible as an in-window observation.
      if (elapsed > window.inMicroseconds) {
        _invalid.add(A3dTimingInvalid.window);
      }
      _lastUs = elapsed;
      int? bounded(int? value) {
        if (value == null) return null;
        if (value < 0 || value > 9007199254740991) {
          _invalid.add(A3dTimingInvalid.bounds);
          return null;
        }
        return value;
      }

      final item = <String, Object?>{
        'seq': ++_seq,
        'us': elapsed,
        'caseId': scope?.caseId ?? _caseId,
        'requestId': scope?.requestId ?? 0,
        'event': event.name,
        if (action != null) 'action': action.name,
        if (state != null || status != null)
          'state': (state ?? status!.state).name,
        if (revision != null || status != null)
          'revision': bounded(revision ?? status!.revision),
        if (generation != null) 'generation': bounded(generation),
        if (synchronization != null)
          'synchronization': bounded(synchronization),
        if (active != null) 'active': active,
        if (canQuery != null) 'canQuery': canQuery,
        if (evidenceReady != null) 'evidenceReady': evidenceReady,
        if (foreground != null) 'foreground': foreground,
        if (sameIdentity != null) 'sameIdentity': sameIdentity,
      };
      if (_events.length >= capacity) {
        _events.removeFirst();
        _invalid.add(A3dTimingInvalid.overflow);
      }
      _events.add(Map.unmodifiable(item));
    } catch (_) {
      _invalid.add(A3dTimingInvalid.callback);
    }
  }

  void seal({bool expired = false}) {
    if (!_recording || _sealing) return;
    final elapsed = _readElapsed();
    _sealAt(
      elapsed: elapsed,
      expired: expired || (elapsed != null && elapsed >= window.inMicroseconds),
      windowExpired: elapsed != null && elapsed > window.inMicroseconds,
    );
  }

  void _sealAt(
      {required int? elapsed,
      required bool expired,
      required bool windowExpired}) {
    if (!_recording || _sealing) return;
    _sealing = true;
    if (windowExpired) _invalid.add(A3dTimingInvalid.window);
    if (_outstanding != 0) _invalid.add(A3dTimingInvalid.pendingAtSeal);
    // A sealed trace must not leave an artificial delay running beyond it.
    // Release the delay only; never synthesize or retry the underlying reply.
    _cancelHolds(expired: expired);
    if (_armed case final action?) {
      record(A3dTimingEvent.armUnused, action: action);
      _armed = null;
    }
    if (elapsed != null) {
      record(expired ? A3dTimingEvent.expired : A3dTimingEvent.sealed);
    }
    _recording = false;
    _sealed = true;
    _expiry?.cancel();
    _clock.stop();
    _sealing = false;
  }

  Map<String, Object?> readTrace({bool callbackFailed = false}) => {
        'schema': 'a3d.timing.v1',
        'recording': _recording,
        'sealed': _sealed,
        'complete': _sealed && _invalid.isEmpty && !callbackFailed,
        'invalid': [
          ..._invalid.map((value) => value.name),
          if (callbackFailed && !_invalid.contains(A3dTimingInvalid.callback))
            'callback',
        ],
        'capacity': capacity,
        'lastSequence': _seq,
        'holdUs': holdDuration.inMicroseconds,
        'windowUs': window.inMicroseconds,
        'minimumTailUs': minimumObservationTail.inMicroseconds,
        'events': List<Map<String, Object?>>.unmodifiable(_events),
      };

  void dispose() {
    if (_disposed) return;
    _ensureWindow();
    _cancelHolds();
    record(A3dTimingEvent.disposed);
    seal();
    _disposed = true;
  }
}

/// Decorates ONE native adapter. Non-selected calls transparently forward all
/// original argument, callback and lease references to that same instance.
final class A3dTimingSignalPlatform
    implements
        AndroidActivitySignalPlatform,
        AndroidActivityObservationPlatform,
        AndroidActivityDeliveryPlatform,
        AndroidActivityOutboxLeasePlatform {
  A3dTimingSignalPlatform(this.delegate, this.probe)
      : assert(delegate is AndroidActivityObservationPlatform),
        assert(delegate is AndroidActivityDeliveryPlatform),
        assert(delegate is AndroidActivityOutboxLeasePlatform);
  final AndroidActivitySignalPlatform delegate;
  final A3dTimingProbe probe;
  AndroidActivityObservationPlatform get _observation =>
      delegate as AndroidActivityObservationPlatform;
  AndroidActivityDeliveryPlatform get _delivery =>
      delegate as AndroidActivityDeliveryPlatform;
  AndroidActivityOutboxLeasePlatform get _lease =>
      delegate as AndroidActivityOutboxLeasePlatform;

  @override
  void setSignalHandler(AndroidNativeSignalHandler? handler) =>
      delegate.setSignalHandler(handler);
  @override
  void setBatchHandler(AndroidNativeBatchHandler? handler) =>
      _delivery.setBatchHandler(handler);
  @override
  void setObservationStatusHandler(
    Future<void> Function(AndroidNativeObservationStatus)? handler,
  ) =>
      _observation.setObservationStatusHandler(handler);
  @override
  Future<AndroidPrivateOutboxRoot> getOutboxRoot() => delegate.getOutboxRoot();
  @override
  Future<AndroidNativeObservationStatus> getObservationStatus() =>
      probe.get(_observation.getObservationStatus);
  @override
  Future<AndroidNativeActivation> activate({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
  }) =>
      delegate.activate(
        enabled: enabled,
        integrityAuthorityReady: integrityAuthorityReady,
        boundSources: boundSources,
        categoryMapping: categoryMapping,
      );
  @override
  Future<AndroidNativeActivation> activateObservation({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
    required Map<AndroidActivitySource, ActivityOutboxProcessLease> leases,
  }) =>
      _observation.activateObservation(
        enabled: enabled,
        integrityAuthorityReady: integrityAuthorityReady,
        boundSources: boundSources,
        categoryMapping: categoryMapping,
        leases: leases,
      );
  @override
  Future<AndroidNativeUsageBatch> queryUsageEvents({
    required int startMs,
    required int endMs,
  }) =>
      delegate.queryUsageEvents(startMs: startMs, endMs: endMs);
  @override
  Future<void> acknowledgeBatch(
    AndroidNativeUsageBatch batch,
    List<String> dispositions,
  ) =>
      _delivery.acknowledgeBatch(batch, dispositions);
  @override
  Future<void> deactivate() => delegate.deactivate();
  @override
  Future<bool> debugInvalidateObservationNotification(
    AndroidNativeObservationStatus target,
  ) =>
      _observation.debugInvalidateObservationNotification(target);
  @override
  Future<AndroidNativeStopObservationResult> stopObservation(
    AndroidNativeObservationStatus target,
  ) =>
      _observation.stopObservation(target);
  @override
  Future<ActivityOutboxProcessLease> acquireDiagnosticOutboxLease(
    AndroidActivitySource source, {
    String permitToken = '',
  }) =>
      _lease.acquireDiagnosticOutboxLease(source, permitToken: permitToken);
  @override
  Future<bool> releaseDiagnosticOutboxLease(ActivityOutboxProcessLease lease) =>
      _lease.releaseDiagnosticOutboxLease(lease);
  @override
  Future<AndroidDiagnosticOwnerReleasePermit> beginDiagnosticOwnerRelease(
    AndroidNativeObservationStatus target,
  ) =>
      _lease.beginDiagnosticOwnerRelease(target);
  @override
  Future<bool> endDiagnosticOwnerRelease(
    AndroidDiagnosticOwnerReleasePermit permit,
  ) =>
      _lease.endDiagnosticOwnerRelease(permit);
}
