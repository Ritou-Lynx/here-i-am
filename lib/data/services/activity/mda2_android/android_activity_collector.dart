import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'activity_integrity_key_repository.dart';
import 'activity_outbox_process_lease.dart';
import 'android_activity_normalizer.dart';
import 'android_activity_signal_platform.dart';
import 'file_activity_outbox_store.dart';

typedef AndroidCollectorAudit =
    void Function(String fixedCode, Map<String, int> nonSensitiveCounts);
typedef AndroidActivityCollectorStatusListener =
    void Function(AndroidActivityCollectorStatus status);

final class AndroidActivitySourceReleaseResult {
  const AndroidActivitySourceReleaseResult({
    required this.source,
    required this.closeCode,
    required this.ownerLeaseReleased,
    required this.processLeaseHeld,
    required this.fileClaimHeld,
    required this.retryable,
  });

  final AndroidActivitySource source;
  final String closeCode;
  final bool ownerLeaseReleased;
  final bool processLeaseHeld;
  final bool fileClaimHeld;
  final bool retryable;
}

final class AndroidActivityCollectorStopResult {
  const AndroidActivityCollectorStopResult({
    required this.nativeOutcome,
    required this.nativeStatus,
    required this.sourceReleases,
    this.noNativeAttempt = false,
  });

  final AndroidNativeStopOutcome? nativeOutcome;
  final bool noNativeAttempt;
  final AndroidNativeObservationStatus? nativeStatus;
  final Map<AndroidActivitySource, AndroidActivitySourceReleaseResult>
  sourceReleases;

  bool get completed =>
      (noNativeAttempt ||
          (nativeOutcome == AndroidNativeStopOutcome.stopped &&
              nativeStatus?.state == AndroidNativeObservationState.stopped &&
              nativeStatus?.enabled == false)) &&
      sourceReleases.length == AndroidActivitySource.values.length &&
      sourceReleases.values.every(
        (result) =>
            result.closeCode == 'closed' &&
            result.ownerLeaseReleased &&
            !result.processLeaseHeld &&
            !result.fileClaimHeld,
      );
}

final class AndroidActivityCollectorBindings {
  const AndroidActivityCollectorBindings({
    required this.usageEvents,
    required this.screenState,
  });

  final SyntheticProbeBinding? usageEvents;
  final SyntheticProbeBinding? screenState;
}

final class AndroidActivityCollectorConfig {
  const AndroidActivityCollectorConfig({
    this.enabled = false,
    required this.bindings,
    required this.categoryMapping,
    this.capacityPerSource = 256,
    this.ttlMs = 300000,
  });

  final bool enabled;
  final AndroidActivityCollectorBindings bindings;
  final Map<String, String> categoryMapping;
  final int capacityPerSource;
  final int ttlMs;
}

final class AndroidActivityCollectorStatus {
  const AndroidActivityCollectorStatus({
    required this.ready,
    required this.fixedCode,
    required this.usage,
    required this.screen,
    required this.usageSequence,
    required this.screenSequence,
    this.queryStartedAtMs = 0,
    this.queryFinishedAtMs = 0,
    this.nativeReceivedAtMs = 0,
    this.dartIngestAtMs = 0,
    this.deliveryDiagnostics = const {},
    this.nativeStatus,
    this.canQuery = false,
    this.canRetireWithoutObservation = false,
    this.generation = 0,
    this.sourceReleases = const {},
  });

  final bool ready;
  final String fixedCode;
  final AndroidObservationStatus? usage;
  final AndroidObservationStatus? screen;
  final int usageSequence;
  final int screenSequence;
  final int queryStartedAtMs;
  final int queryFinishedAtMs;
  final int nativeReceivedAtMs;
  final int dartIngestAtMs;
  final Map<String, int> deliveryDiagnostics;
  final AndroidNativeObservationStatus? nativeStatus;
  final int generation;
  final bool canQuery;
  final bool canRetireWithoutObservation;
  final Map<AndroidActivitySource, AndroidActivitySourceReleaseResult>
  sourceReleases;
}

/// Explicitly-started A3-I candidate. There is no timer, transport, scheduler,
/// background service, boot receiver, UI, or automatic dependency wiring here.
enum AndroidCollectorObservationKind {
  accepted,
  generation,
  pushGeneration,
  retiredSession,
  terminal,
  revision,
  published,
  readFailed,
}

/// Optional in-memory observation only. No opaque native identifiers escape.
final class AndroidCollectorObservationEvent {
  const AndroidCollectorObservationEvent({
    required this.kind,
    required this.generation,
    required this.ready,
    this.state,
    this.revision,
    this.sameIdentity,
  });
  final AndroidCollectorObservationKind kind;
  final int generation;
  final bool ready;
  final AndroidNativeObservationState? state;
  final int? revision;
  final bool? sameIdentity;
}

final class AndroidActivityCollector {
  AndroidActivityCollector({
    required AndroidActivityCollectorConfig config,
    required ActivityIntegrityKeyRepository keyRepository,
    required AndroidActivitySignalPlatform platform,
    required int Function() clockMs,
    AndroidCollectorAudit? audit,
    this.observationHook,
    Duration stopTimeout = const Duration(seconds: 3),
  }) : _config = config,
       _keyRepository = keyRepository,
       _platform = platform,
       _clockMs = clockMs,
       _audit = audit,
       _stopTimeout = stopTimeout;

  final AndroidActivityCollectorConfig _config;
  final ActivityIntegrityKeyRepository _keyRepository;
  final AndroidActivitySignalPlatform _platform;
  final int Function() _clockMs;
  final AndroidCollectorAudit? _audit;
  final void Function(AndroidCollectorObservationEvent)? observationHook;
  bool _observationHookFailed = false;
  bool get observationHookFailed => _observationHookFailed;

  void _observe(
    AndroidCollectorObservationKind kind, [
    AndroidNativeObservationStatus? observed,
  ]) {
    final hook = observationHook;
    if (hook == null) return;
    try {
      hook(
        AndroidCollectorObservationEvent(
          kind: kind,
          generation: _generation,
          ready: _ready,
          state: observed?.state,
          revision: observed?.revision,
          sameIdentity: observed == null || _nativeStatus == null
              ? null
              : observed.matches(_nativeStatus!),
        ),
      );
    } catch (_) {
      // Observability must never change collection or its rejection decisions.
      _observationHookFailed = true;
    }
  }

  final Duration _stopTimeout;
  FileActivityOutboxStore? _usageStore;
  FileActivityOutboxStore? _screenStore;
  AndroidActivityNormalizer? _usageNormalizer;
  AndroidActivityNormalizer? _screenNormalizer;
  final Set<String> _seenUsageSignals = {};
  final Set<String> _seenScreenSignals = {};
  var _initialized = false;
  var _ready = false;
  var _fixedCode = 'collector_disabled';
  AndroidNativeUsageBatch? _lastBatch;
  final Map<String, int> _deliveryDiagnostics = {};
  String _receiptKey = '';
  List<String> _receiptOutcomes = [];
  List<String> _receiptIdentities = [];
  final Set<AndroidActivityCollectorStatusListener> _statusListeners = {};
  final Map<AndroidActivitySource, ActivityOutboxProcessLease> _processLeases =
      {};
  final Map<AndroidActivitySource, AndroidActivitySourceReleaseResult>
  _sourceReleases = {};
  final Map<AndroidActivitySource, ActivityOutboxReleaseTarget>
  _releaseTargets = {};
  AndroidNativeObservationStatus? _nativeStatus;
  var _generation = 0;
  AndroidNativeObservationStatus? _ownedObservation;
  Completer<void>? _initializationDone;
  Future<AndroidActivityCollectorStopResult>? _stopFuture;
  bool _nativeAttempted = false;
  bool _accepting = false;
  final Set<String> _terminalObservations = {};
  final Set<String> _retiredSessions = {};
  final Set<AndroidActivitySource> _closeAttempted = {};
  final Map<AndroidActivitySource, String> _ownerCloseCodes = {};
  final Set<AndroidActivitySource> _debugDeleteFailures = {};

  /// Explicit Debug diagnostic only; normal close never injects a failure.
  void debugFailNextOwnerDelete(AndroidActivitySource source) {
    final store = source == AndroidActivitySource.usageEvents
        ? _usageStore
        : _screenStore;
    if (!kDebugMode ||
        _ownedObservation == null ||
        store == null ||
        _closeAttempted.contains(source)) {
      throw const AndroidActivityException('debug_diagnostic_required');
    }
    _debugDeleteFailures.add(source);
  }

  void _beforeOwnerDelete(AndroidActivitySource source) {
    if (kDebugMode && _debugDeleteFailures.remove(source)) {
      throw const AndroidActivityException('owner_release_failed');
    }
  }

  FileActivityOutboxStore? get usageOutbox => _usageStore;
  FileActivityOutboxStore? get screenOutbox => _screenStore;

  AndroidActivityCollectorStatus get status => AndroidActivityCollectorStatus(
    ready: _ready,
    fixedCode: _fixedCode,
    usage: _usageNormalizer?.status,
    screen: _screenNormalizer?.status,
    usageSequence: _usageStore?.lastAllocatedSequence ?? 0,
    screenSequence: _screenStore?.lastAllocatedSequence ?? 0,
    queryStartedAtMs: _lastBatch?.queryStartedAtMs ?? 0,
    queryFinishedAtMs: _lastBatch?.queryFinishedAtMs ?? 0,
    nativeReceivedAtMs: _lastBatch?.nativeReceivedAtMs ?? 0,
    dartIngestAtMs: _lastBatch?.dartIngestAtMs ?? 0,
    deliveryDiagnostics: Map.unmodifiable(_deliveryDiagnostics),
    nativeStatus: _nativeStatus,
    canRetireWithoutObservation:
        (_initializationDone?.isCompleted ?? false) &&
        !_nativeAttempted &&
        _sourceReleases.length == AndroidActivitySource.values.length &&
        _sourceReleases.values.every(
          (r) =>
              r.closeCode == 'closed' &&
              r.ownerLeaseReleased &&
              !r.processLeaseHeld &&
              !r.fileClaimHeld,
        ),
    canQuery:
        _accepting &&
        (_platform is! AndroidActivityObservationPlatform ||
            _isCurrentObservation(_nativeStatus)),
    generation: _generation,
    sourceReleases: Map.unmodifiable(_sourceReleases),
  );

  void addStatusListener(AndroidActivityCollectorStatusListener listener) {
    _statusListeners.add(listener);
  }

  void removeStatusListener(AndroidActivityCollectorStatusListener listener) {
    _statusListeners.remove(listener);
  }

  /// Internal handoff to the explicit U recovery action; never project to UI.
  Map<AndroidActivitySource, ActivityOutboxReleaseTarget> get releaseTargets =>
      Map.unmodifiable(_releaseTargets);

  void confirmReleasedOwner(
    AndroidActivitySource source,
    ActivityOutboxReleaseTarget target,
  ) {
    if (!identical(_releaseTargets[source], target)) {
      throw const AndroidActivityException('owner_release_target_changed');
    }
    final lease = _processLeases[source];
    if ((lease?.isHeld ?? false) || (lease?.hasFileClaim ?? false)) {
      throw const AndroidActivityException('diagnostic_outbox_lease_held');
    }
    final store = source == AndroidActivitySource.usageEvents
        ? _usageStore
        : _screenStore;
    if (store != null && !store.ownerLeaseReleased) {
      throw const AndroidActivityException('diagnostic_outbox_lease_held');
    }
    _retireStore(source);
    _processLeases.remove(source);
    _ownerCloseCodes[source] = 'closed';
    _releaseTargets.remove(source);
    _sourceReleases[source] = AndroidActivitySourceReleaseResult(
      source: source,
      closeCode: 'closed',
      ownerLeaseReleased: true,
      processLeaseHeld: false,
      fileClaimHeld: false,
      retryable: false,
    );
    if (_nativeStatus?.state == AndroidNativeObservationState.stopped &&
        _ownedObservation != null &&
        _nativeStatus!.matches(_ownedObservation!) &&
        _sourceReleases.length == AndroidActivitySource.values.length &&
        _sourceReleases.values.every(
          (r) =>
              r.closeCode == 'closed' &&
              r.ownerLeaseReleased &&
              !r.processLeaseHeld &&
              !r.fileClaimHeld,
        )) {
      _fixedCode = 'collector_disabled';
    }
    _notifyStatus();
  }

  void _notifyStatus() {
    final snapshot = status;
    _observe(AndroidCollectorObservationKind.published, _nativeStatus);
    for (final listener in List.of(_statusListeners)) {
      listener(snapshot);
    }
  }

  Future<AndroidActivityCollectorStatus> synchronizeObservationStatus() async {
    final platform = _platform is AndroidActivityObservationPlatform
        ? _platform as AndroidActivityObservationPlatform
        : null;
    if (platform == null) return status;
    final generation = _generation;
    try {
      final observed = await platform.getObservationStatus();
      if (generation != _generation) {
        _observe(AndroidCollectorObservationKind.generation, observed);
        return status;
      }
      _applyObservationStatus(observed);
    } on AndroidActivityException {
      _observe(AndroidCollectorObservationKind.readFailed);
      if (generation == _generation) {
        _accepting = false;
        _ready = false;
        _fixedCode = 'observation_status_invalid';
        _notifyStatus();
      }
    }
    return status;
  }

  bool _applyObservationStatus(AndroidNativeObservationStatus observed) {
    final current = _nativeStatus;
    if (_retiredSessions.contains(observed.sessionId)) {
      _observe(AndroidCollectorObservationKind.retiredSession, observed);
      _accepting = false;
      _fail('observation_status_invalid');
      return false;
    }
    if (current != null && current.sessionId != observed.sessionId) {
      _retiredSessions.add(current.sessionId);
    }
    final identity = '${observed.sessionId}/${observed.observationId}';
    if (_terminalObservations.contains(identity) &&
        observed.state == AndroidNativeObservationState.running) {
      _observe(AndroidCollectorObservationKind.terminal, observed);
      _accepting = false;
      _fail('observation_status_invalid');
      return false;
    }
    if (observed.state == AndroidNativeObservationState.stopped ||
        observed.state == AndroidNativeObservationState.stopping) {
      _terminalObservations.add(identity);
    }
    if (current != null &&
        current.sessionId == observed.sessionId &&
        (observed.revision < current.revision ||
            (observed.revision == current.revision &&
                (observed.state != current.state ||
                    observed.enabled != current.enabled ||
                    observed.reason != current.reason ||
                    !observed.matches(current))))) {
      _observe(AndroidCollectorObservationKind.revision, observed);
      _accepting = false;
      _fail('observation_status_invalid');
      return false;
    }
    _observe(AndroidCollectorObservationKind.accepted, observed);
    _nativeStatus = observed;
    final own = _ownedObservation;
    if ((own != null && !own.matches(observed)) ||
        observed.state == AndroidNativeObservationState.stopped ||
        observed.state == AndroidNativeObservationState.stopping ||
        observed.state == AndroidNativeObservationState.unknown) {
      _accepting = false;
      _ready = false;
      _fixedCode = own != null && !own.matches(observed)
          ? 'observation_target_changed'
          : observed.reason;
    }
    // Lifecycle running is not evidence of a successful Usage query.
    _notifyStatus();
    return true;
  }

  Future<AndroidActivityCollectorStatus> initialize() async {
    if (_initialized) {
      throw const AndroidActivityException('collector_already_initialized');
    }
    _initialized = true;
    final done = _initializationDone = Completer<void>();
    final generation = ++_generation;
    try {
      await _initialize(generation);
    } finally {
      try {
        if (!_nativeAttempted) await _closeStores();
      } finally {
        done.complete();
      }
    }
    _notifyStatus();
    return status;
  }

  Future<AndroidActivityCollectorStatus> _initialize(int generation) async {
    if (!_config.enabled) return _fail('collector_disabled');

    final usageBinding = _config.bindings.usageEvents;
    final screenBinding = _config.bindings.screenState;
    if (!_bindingsComplete(usageBinding, screenBinding)) {
      return _fail('source_binding_missing');
    }

    late final List<int> key;
    try {
      key = await _keyRepository.readRequired();
    } on AndroidActivityException catch (error) {
      return generation == _generation ? _fail(error.code) : status;
    }
    if (generation != _generation) return status;
    if (key.length != ActivityIntegrityKeyRepository.keyLength) {
      return _fail('integrity_key_invalid');
    }

    late final AndroidPrivateOutboxRoot root;
    try {
      root = await _platform.getOutboxRoot();
    } on AndroidActivityException catch (error) {
      return generation == _generation ? _fail(error.code) : status;
    }
    if (generation != _generation) return status;
    if (root.storageScope != 'no_backup_private' ||
        !_isAbsolutePath(root.path)) {
      return _fail('private_outbox_root_invalid');
    }

    final observationPlatform = _platform is AndroidActivityObservationPlatform
        ? _platform as AndroidActivityObservationPlatform
        : null;
    final leasePlatform = _platform is AndroidActivityOutboxLeasePlatform
        ? _platform as AndroidActivityOutboxLeasePlatform
        : null;
    if ((observationPlatform == null) != (leasePlatform == null)) {
      return _fail('observation_control_required');
    }
    if (leasePlatform != null) {
      try {
        for (final source in AndroidActivitySource.values) {
          _processLeases[source] = await leasePlatform
              .acquireDiagnosticOutboxLease(source);
          if (generation != _generation) return status;
        }
      } on AndroidActivityException catch (error) {
        return generation == _generation ? _fail(error.code) : status;
      }
      if (generation != _generation) return status;
    }

    final usageDirectory = Directory(
      '${root.path}${Platform.pathSeparator}${AndroidActivitySource.usageEvents.wireValue}',
    );
    final screenDirectory = Directory(
      '${root.path}${Platform.pathSeparator}${AndroidActivitySource.screenState.wireValue}',
    );
    if (_hasState(usageDirectory) || _hasState(screenDirectory)) {
      return _fail('recovery_authority_required');
    }

    try {
      final proof = HmacActivityAgeProofProvider(integrityKey: key);
      _usageStore = FileActivityOutboxStore.create(
        directory: usageDirectory,
        binding: usageBinding!,
        capacity: _config.capacityPerSource,
        integrityKey: key,
        ageProofProvider: proof,
        clockMs: _clockMs,
        audit: _audit,
        processLease: _processLeases[AndroidActivitySource.usageEvents],
        beforeOwnerDeleteForTesting: () =>
            _beforeOwnerDelete(AndroidActivitySource.usageEvents),
      );
      _screenStore = FileActivityOutboxStore.create(
        directory: screenDirectory,
        binding: screenBinding!,
        capacity: _config.capacityPerSource,
        integrityKey: key,
        ageProofProvider: proof,
        clockMs: _clockMs,
        audit: _audit,
        processLease: _processLeases[AndroidActivitySource.screenState],
        beforeOwnerDeleteForTesting: () =>
            _beforeOwnerDelete(AndroidActivitySource.screenState),
      );
      _usageNormalizer = AndroidActivityNormalizer(
        outbox: _usageStore!,
        clockMs: _clockMs,
        ttlMs: _config.ttlMs,
      );
      _screenNormalizer = AndroidActivityNormalizer(
        outbox: _screenStore!,
        clockMs: _clockMs,
        ttlMs: _config.ttlMs,
      );
    } on AndroidActivityException catch (error) {
      await _closeStores();
      return generation == _generation ? _fail(error.code) : status;
    }

    _platform.setSignalHandler(
      (signal) => _acceptScreenSignal(signal, generation),
    );
    final deliveryPlatform = _platform is AndroidActivityDeliveryPlatform
        ? _platform as AndroidActivityDeliveryPlatform
        : null;
    if (deliveryPlatform != null) {
      deliveryPlatform.setBatchHandler(
        (batch) => _acceptBatch(batch, generation),
      );
    }
    observationPlatform?.setObservationStatusHandler(
      (observed) async => _acceptObservationStatus(observed, generation),
    );
    _nativeAttempted = true;
    try {
      final activation = observationPlatform == null
          ? await _platform.activate(
              enabled: true,
              integrityAuthorityReady: true,
              boundSources: AndroidActivitySource.values.toSet(),
              categoryMapping: Map.unmodifiable(_config.categoryMapping),
            )
          : await observationPlatform.activateObservation(
              enabled: true,
              integrityAuthorityReady: true,
              boundSources: AndroidActivitySource.values.toSet(),
              categoryMapping: Map.unmodifiable(_config.categoryMapping),
              leases: Map.unmodifiable(_processLeases),
            );
      // Only this activation receipt grants ownership. Status reads never do.
      _ownedObservation = activation.observationStatus;
      if (observationPlatform != null && activation.observationStatus == null) {
        _nativeAttempted = false; // Exact null receipt proves no startup claim.
      }
      if (generation != _generation) return status;
      final observed = activation.observationStatus;
      if (observed != null &&
          _nativeStatus != null &&
          _nativeStatus!.observationId.isNotEmpty &&
          !_nativeStatus!.matches(observed)) {
        return _fail('observation_target_changed');
      }
      if (observed != null && !_applyObservationStatus(observed)) return status;
      if (!activation.enabled ||
          activation.readiness != 'ready' ||
          (observationPlatform != null &&
              (observed == null ||
                  observed.state != AndroidNativeObservationState.running ||
                  !observed.enabled))) {
        return _fail(activation.readiness);
      }
      _accepting = true;
      _ready = true;
      _fixedCode = 'ready';
      _auditCode('collector_ready', {'sources': 2});
      _notifyStatus();
      return status;
    } on AndroidActivityException catch (error) {
      return generation == _generation ? _fail(error.code) : status;
    }
  }

  Future<AndroidActivityCollectorStatus> pollUsage({
    required int startMs,
    required int endMs,
  }) async {
    final generation = _generation;
    if (!_accepting) return status;
    if (_platform is AndroidActivityObservationPlatform) {
      await synchronizeObservationStatus();
      if (generation != _generation || !_accepting) return status;
    }
    try {
      final batch = await _platform.queryUsageEvents(
        startMs: startMs,
        endMs: endMs,
      );
      if (generation != _generation ||
          !_accepting ||
          (_platform is AndroidActivityObservationPlatform &&
              !_isCurrentObservation(batch.observationStatus))) {
        return status;
      }
      final dispositions = await _acceptBatch(batch, generation);
      if (generation != _generation || !_accepting) return status;
      if (batch.deliveryId.isNotEmpty &&
          _platform is AndroidActivityDeliveryPlatform) {
        try {
          await (_platform as AndroidActivityDeliveryPlatform).acknowledgeBatch(
            batch,
            dispositions,
          );
        } on AndroidActivityException catch (error) {
          if (generation == _generation && _accepting) {
            _fixedCode = error.code;
            _countDelivery('ack_failures');
          }
        }
      }
    } on AndroidActivityException catch (error) {
      if (generation == _generation && _accepting) {
        _ready = false;
        _fixedCode = error.code;
        _markUsageGap();
        _auditCode(error.code, {'queries': 1});
      }
    }
    _notifyStatus();
    return status;
  }

  void _countDelivery(String code) {
    _deliveryDiagnostics[code] = (_deliveryDiagnostics[code] ?? 0) + 1;
    _auditCode(code, {'delivery_omissions': 1});
  }

  Future<List<String>> _acceptBatch(
    AndroidNativeUsageBatch batch,
    int generation,
  ) async {
    final signals = [...batch.signals, ...batch.screenSignals];
    if (!_accepting ||
        generation != _generation ||
        (_platform is AndroidActivityObservationPlatform &&
            !_isCurrentObservation(batch.observationStatus))) {
      return List.filled(signals.length, 'retry');
    }
    _lastBatch = batch;
    var nativeGap = false;
    for (final entry in batch.counters.entries) {
      final key = 'native_${entry.key}';
      final previous = _deliveryDiagnostics[key] ?? 0;
      if (entry.value > previous) {
        _deliveryDiagnostics[key] = entry.value;
        if (entry.key != 'query_failures') nativeGap = true;
      }
    }
    final key = '${batch.deliveryEpoch}/${batch.deliveryId}';
    final identities = signals.map(_signalIdentity).toList();
    if (batch.deliveryId.isNotEmpty &&
        key == _receiptKey &&
        (identities.length != _receiptIdentities.length ||
            List.generate(
              identities.length,
              (i) => identities[i] != _receiptIdentities[i],
            ).contains(true))) {
      throw const AndroidActivityException('delivery_batch_changed');
    }
    final outcomes = batch.deliveryId.isNotEmpty && key == _receiptKey
        ? List<String>.from(_receiptOutcomes)
        : List.filled(signals.length, 'retry');
    var usageGap = nativeGap;
    var screenGap = nativeGap;
    var permissionReady = true;
    try {
      _usageNormalizer!.acceptSynthetic({
        'type': 'usage_permission',
        'state': batch.permission.name,
      });
    } on AndroidActivityException catch (error) {
      _fixedCode = error.code;
      permissionReady = false;
      _countDelivery('enqueue_failures');
    }
    for (var i = 0; i < signals.length; i++) {
      if (outcomes[i] != 'retry') continue;
      final signal = signals[i];
      final usage = i < batch.signals.length;
      final normalizer = usage ? _usageNormalizer! : _screenNormalizer!;
      final seen = usage ? _seenUsageSignals : _seenScreenSignals;
      if (batch.permission != UsageAccess.granted ||
          (usage && !permissionReady)) {
        continue;
      }
      if (seen.contains(identities[i])) {
        outcomes[i] = 'duplicate';
        continue;
      }
      try {
        final at = signal['signal_at_ms'];
        if (at is! int) {
          throw const AndroidActivityException('invalid_signal_time');
        }
        final rejection = normalizer.deliveryRejectionAt(at);
        if (rejection != null) {
          outcomes[i] = rejection;
          _countDelivery(rejection);
          if (usage) {
            usageGap = true;
          } else {
            screenGap = true;
          }
          continue;
        }
        final event = normalizer.acceptDeliverySignal(signal);
        if (event != null) {
          outcomes[i] = 'accepted';
          _remember(seen, identities[i]);
        }
      } on AndroidActivityException catch (error) {
        _fixedCode = error.code;
        _countDelivery('enqueue_failures');
        if (usage) {
          usageGap = true;
        } else {
          screenGap = true;
        }
      }
    }
    // Process valid members first. This does not emit a now-dated event or move
    // the occurrence barrier; known omissions remain separately visible forever.
    if (usageGap) _usageNormalizer!.noteDeliveryGap();
    if (screenGap) _screenNormalizer!.noteDeliveryGap();
    if (batch.deliveryId.isNotEmpty) {
      _receiptKey = key;
      _receiptOutcomes = List.from(outcomes);
      _receiptIdentities = identities;
    }
    if (!outcomes.contains('retry')) _fixedCode = batch.readiness;
    _ready = batch.readiness == 'ready' && !outcomes.contains('retry');
    _notifyStatus();
    return outcomes;
  }

  Future<AndroidActivityCollectorStopResult> stop() {
    final pending = _stopFuture;
    if (pending != null) return pending;
    ++_generation;
    _accepting = false;
    _ready = false;
    _fixedCode = 'collector_disabled';
    _notifyStatus();
    return _stopFuture = _stop().whenComplete(() => _stopFuture = null);
  }

  Future<AndroidActivityCollectorStopResult> _stop() async {
    try {
      await _initializationDone?.future.timeout(_stopTimeout);
    } on TimeoutException {
      _fixedCode = 'observation_stop_failed';
      _snapshotUnreleasedSources();
      _notifyStatus();
      return AndroidActivityCollectorStopResult(
        nativeOutcome: AndroidNativeStopOutcome.unknown,
        nativeStatus: _nativeStatus,
        sourceReleases: Map.unmodifiable(_sourceReleases),
      );
    }
    final platform = _platform is AndroidActivityObservationPlatform
        ? _platform as AndroidActivityObservationPlatform
        : null;
    AndroidNativeStopOutcome? outcome;
    AndroidNativeObservationStatus? terminal;
    final target = _ownedObservation;
    var canClose = !_nativeAttempted;
    if (platform != null && target != null && target.observationId.isNotEmpty) {
      try {
        final result = await platform
            .stopObservation(target)
            .timeout(_stopTimeout);
        outcome = result.outcome;
        terminal = result.status;
        final valid = _applyObservationStatus(terminal);
        canClose =
            valid &&
            outcome == AndroidNativeStopOutcome.stopped &&
            terminal.matches(target) &&
            terminal.state == AndroidNativeObservationState.stopped &&
            !terminal.enabled;
      } on TimeoutException {
        outcome = AndroidNativeStopOutcome.unknown;
      } on AndroidActivityException {
        outcome = AndroidNativeStopOutcome.failed;
      }
    } else if (platform == null && _nativeAttempted) {
      // Compatibility only for local synthetic fakes; production implements R3.
      try {
        await _platform.deactivate().timeout(_stopTimeout);
        canClose = true;
      } on TimeoutException {
        canClose = false;
      } on AndroidActivityException {
        canClose = false;
      }
    }
    if (canClose) await _closeStores();
    _snapshotUnreleasedSources();
    final completeResources = _sourceReleases.values.every(
      (r) =>
          r.closeCode == 'closed' &&
          r.ownerLeaseReleased &&
          !r.processLeaseHeld &&
          !r.fileClaimHeld,
    );
    _fixedCode = canClose && completeResources
        ? 'collector_disabled'
        : 'observation_stop_failed';
    _notifyStatus();
    return AndroidActivityCollectorStopResult(
      nativeOutcome: outcome,
      nativeStatus: terminal,
      noNativeAttempt: !_nativeAttempted,
      sourceReleases: Map.unmodifiable(_sourceReleases),
    );
  }

  Future<void> dispose() async {
    await stop();
  }

  Future<void> _acceptScreenSignal(
    Map<String, Object?> signal,
    int generation,
  ) async {
    if (!_accepting ||
        generation != _generation ||
        _platform is AndroidActivityObservationPlatform) {
      return;
    }
    final identity = _signalIdentity(signal);
    if (_seenScreenSignals.contains(identity)) return;
    try {
      final event = _screenNormalizer!.acceptSynthetic(signal);
      if (event != null) _remember(_seenScreenSignals, identity);
    } on AndroidActivityException catch (error) {
      _fixedCode = error.code;
      _auditCode(error.code, {'signals': 1});
    }
  }

  bool _bindingsComplete(
    SyntheticProbeBinding? usage,
    SyntheticProbeBinding? screen,
  ) {
    if (usage == null ||
        screen == null ||
        usage.source != AndroidActivitySource.usageEvents ||
        screen.source != AndroidActivitySource.screenState ||
        usage.serverIssuedPrefix == screen.serverIssuedPrefix ||
        usage.probeId == screen.probeId) {
      return false;
    }
    return usage.allowedKinds.containsAll(const {
          'app.category_active',
          'probe.permission_changed',
          'probe.error',
        }) &&
        usage.capabilities.containsAll(const {
          'usage_events',
          'probe_error.collection_failed',
        }) &&
        screen.allowedKinds.containsAll(const {
          'screen.interactive',
          'screen.non_interactive',
          'session.unlocked',
          'probe.error',
        }) &&
        screen.capabilities.contains('probe_error.collection_failed');
  }

  bool _hasState(Directory directory) =>
      directory.existsSync() && directory.listSync().isNotEmpty;

  String _signalIdentity(Map<String, Object?> signal) =>
      '${signal['type']}|${signal['signal_at_ms']}|${signal['category'] ?? ''}';

  void _remember(Set<String> target, String identity) {
    if (target.length >= 512) target.remove(target.first);
    target.add(identity);
  }

  void _markUsageGap() {
    try {
      _usageNormalizer?.markCollectionGap();
    } on AndroidActivityException catch (error) {
      _auditCode(error.code, {'gaps': 1});
    }
  }

  Future<void> _acceptObservationStatus(
    AndroidNativeObservationStatus observed,
    int generation,
  ) async {
    if (generation != _generation) {
      _observe(AndroidCollectorObservationKind.pushGeneration, observed);
      return;
    }
    _applyObservationStatus(observed);
  }

  bool _isCurrentObservation(AndroidNativeObservationStatus? observed) {
    final own = _ownedObservation;
    final current = _nativeStatus;
    return _accepting &&
        observed != null &&
        own != null &&
        current != null &&
        own.matches(observed) &&
        current.matches(observed) &&
        current.state == AndroidNativeObservationState.running &&
        observed.revision >= current.revision &&
        (observed.revision != current.revision ||
            observed.reason == current.reason) &&
        observed.state == AndroidNativeObservationState.running &&
        observed.enabled;
  }

  void _retireStore(AndroidActivitySource source) {
    if (source == AndroidActivitySource.usageEvents) {
      _usageStore = null;
      _usageNormalizer = null;
    } else {
      _screenStore = null;
      _screenNormalizer = null;
    }
  }

  void _snapshotUnreleasedSources() {
    for (final source in AndroidActivitySource.values) {
      if (_sourceReleases.containsKey(source)) continue;
      final store = source == AndroidActivitySource.usageEvents
          ? _usageStore
          : _screenStore;
      final lease = _processLeases[source];
      _sourceReleases[source] = AndroidActivitySourceReleaseResult(
        source: source,
        closeCode: 'not_attempted',
        ownerLeaseReleased: store?.ownerLeaseReleased ?? true,
        processLeaseHeld: lease?.isHeld ?? false,
        fileClaimHeld: lease?.hasFileClaim ?? false,
        retryable: true,
      );
    }
  }

  Future<void> _closeStores() async {
    for (final source in AndroidActivitySource.values.reversed) {
      final store = source == AndroidActivitySource.usageEvents
          ? _usageStore
          : _screenStore;
      final lease = _processLeases[source];
      var ownerCode = _ownerCloseCodes[source] ?? 'closed';
      if (store != null && !_closeAttempted.contains(source)) {
        try {
          _releaseTargets[source] = store.inspectOwnReleaseTarget();
          _closeAttempted.add(source);
          store.close();
          ownerCode = 'closed';
          _releaseTargets.remove(source);
        } on AndroidActivityException catch (error) {
          ownerCode = error.code;
          // This refusal occurs before close marks the store closed/poisoned.
          if (error.code == 'attempt_in_progress') {
            _closeAttempted.remove(source);
          }
          _auditCode(error.code, {'stores': 1});
        }
      }
      _ownerCloseCodes[source] = ownerCode;
      final fdReleased =
          store?.ownerLeaseReleased ??
          _sourceReleases[source]?.ownerLeaseReleased ??
          true;
      var code = ownerCode;
      if (fdReleased &&
          !(lease?.hasFileClaim ?? false) &&
          lease != null &&
          lease.isHeld &&
          _platform is AndroidActivityOutboxLeasePlatform) {
        try {
          final released =
              await (_platform as AndroidActivityOutboxLeasePlatform)
                  .releaseDiagnosticOutboxLease(lease)
                  .timeout(_stopTimeout);
          if (!released || lease.isHeld) code = 'diagnostic_outbox_lease_held';
        } on TimeoutException {
          code = 'diagnostic_outbox_lease_held';
        } on AndroidActivityException catch (error) {
          code = error.code;
        }
      }
      final held = lease?.isHeld ?? false;
      final claim = lease?.hasFileClaim ?? false;
      _sourceReleases[source] = AndroidActivitySourceReleaseResult(
        source: source,
        closeCode: code,
        ownerLeaseReleased: fdReleased,
        processLeaseHeld: held,
        fileClaimHeld: claim,
        retryable: code != 'closed' || !fdReleased || held || claim,
      );
      if (fdReleased) _retireStore(source);
      if (!held && !claim) _processLeases.remove(source);
    }
  }

  AndroidActivityCollectorStatus _fail(String code) {
    _ready = false;
    _fixedCode = code;
    _auditCode(code, {'sources': 0});
    _notifyStatus();
    return status;
  }

  void _auditCode(String code, Map<String, int> counts) {
    _audit?.call(code, Map.unmodifiable(counts));
  }
}

bool _isAbsolutePath(String value) =>
    value.startsWith('/') ||
    value.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
