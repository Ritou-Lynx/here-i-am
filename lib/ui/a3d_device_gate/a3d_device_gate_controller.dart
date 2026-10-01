import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'a3d_timing_probe.dart';

import 'package:flutter/foundation.dart';

import '../../data/services/activity/mda2_android/activity_integrity_key_repository.dart';
import '../../data/services/activity/mda2_android/activity_outbox_process_lease.dart';
import '../../data/services/activity/mda2_android/android_activity_collector.dart';
import '../../data/services/activity/mda2_android/android_activity_normalizer.dart';
import '../../data/services/activity/mda2_android/android_activity_signal_platform.dart';
import '../../data/services/activity/mda2_android/file_activity_outbox_store.dart';

const a3dEvidenceSchema = 'mda2.a3d.local_diagnostic.v1';
const a3dDiagnosticAuthority = 'synthetic_local_diagnostic';

enum A3dStatusSynchronization { checking, verified, unknown }

enum A3dResourceAction { stop, releaseOrphanOwners, reset }

/// UI-only receipt of an explicit action, independent of lifecycle reads.
final class A3dResourceActionResult {
  A3dResourceActionResult(this.action, String code)
      : code = _publicReadiness(code);

  final A3dResourceAction action;
  final String code;

  String get label => switch (action) {
        A3dResourceAction.stop => '停止并释放',
        A3dResourceAction.releaseOrphanOwners => '无损释放孤立资源',
        A3dResourceAction.reset => '显式清理',
      };

  String get message => switch (code) {
        'collector_disabled' ||
        'diagnostic_owner_release_complete' ||
        'diagnostic_reset_complete' =>
          '已完成',
        'diagnostic_outbox_absent' => '诊断目录已不存在',
        'diagnostic_owner_release_partial' => '部分完成或回执未确认，需显式重试',
        'observation_stop_failed' => '资源释放未完成',
        'diagnostic_owner_release_refused' => '释放被拒绝，资源尚不满足释放条件',
        'diagnostic_reset_requires_disposed' => '清理被拒绝，需先释放本次资源',
        _ => '未完成，请核对结果后重试',
      };
}

enum A3dDiagnosticScenario {
  complete,
  missingKey,
  missingUsageBinding,
  missingScreenBinding,
}

extension A3dDiagnosticScenarioLabel on A3dDiagnosticScenario {
  String get label => switch (this) {
        A3dDiagnosticScenario.complete => '完整本地诊断',
        A3dDiagnosticScenario.missingKey => '缺少本地密钥（负例）',
        A3dDiagnosticScenario.missingUsageBinding => '缺少 Usage binding（负例）',
        A3dDiagnosticScenario.missingScreenBinding => '缺少 Screen binding（负例）',
      };
}

final class A3dEvidenceSnapshot {
  const A3dEvidenceSnapshot(this.value);

  final Map<String, Object?> value;

  String encode() => const JsonEncoder.withIndent('  ').convert(value);
}

/// Deterministic, local-only bindings for repeatable device diagnostics. The
/// legacy A2 field name `serverIssuedPrefix` does not change their authority:
/// these values are synthetic and are never accepted as server issuance.
final class A3dDiagnosticBindingFactory {
  A3dDiagnosticBindingFactory._();

  static const capacity = 256;
  static const ttlMs = 300000;
  static const _usagePrefix = 'A3DLOCALUSAGE0000000001';
  static const _screenPrefix = 'A3DLOCALSCREEN000000001';

  static SyntheticProbeBinding create(AndroidActivitySource source) =>
      SyntheticProbeBinding(
        deviceId: 'a3d-local-diagnostic',
        probeId: source == AndroidActivitySource.usageEvents
            ? 'a3d-usage-local'
            : 'a3d-screen-local',
        serverIssuedPrefix: source == AndroidActivitySource.usageEvents
            ? _usagePrefix
            : _screenPrefix,
        source: source,
        reportIntervalMs: 30000,
        expirySloMs: ttlMs,
        coverageMode: 'discrete_best_effort',
        allowedKinds: source == AndroidActivitySource.usageEvents
            ? {'app.category_active', 'probe.permission_changed', 'probe.error'}
            : {
                'screen.interactive',
                'screen.non_interactive',
                'session.unlocked',
                'probe.error',
              },
        capabilities: source == AndroidActivitySource.usageEvents
            ? {'usage_events', 'probe_error.collection_failed'}
            : {'probe_error.collection_failed'},
      );
}

/// Reduces the already privacy-minimized outbox wire to the even narrower
/// A3-D human-gate evidence schema. Unknown fields reject the whole record.
final class A3dEvidenceCodec {
  A3dEvidenceCodec._();

  static const _wireKeys = {
    'contract',
    'schema_version',
    'event_id',
    'device_id',
    'probe_id',
    'origin_sequence',
    'kind',
    'signal_at_ms',
    'ttl_ms',
    'confidence',
    'source',
    'coverage',
    'payload',
  };
  static const _categories = {
    'chat',
    'social',
    'video',
    'reading',
    'work',
    'other',
  };

  static A3dEvidenceSnapshot project({
    required int observedAtMs,
    required String collectorReadiness,
    required UsageAccess usagePermission,
    required AndroidCoverage? usageCoverage,
    required AndroidCoverage? screenCoverage,
    required int usageSequence,
    required int screenSequence,
    required Iterable<Map<String, Object?>> usageWire,
    required Iterable<Map<String, Object?>> screenWire,
    required Map<String, int> controllerCounts,
    int queryStartedAtMs = 0,
    int queryFinishedAtMs = 0,
    int nativeReceivedAtMs = 0,
    int dartIngestAtMs = 0,
  }) {
    final counts = <String, int>{
      'usage_observations': 0,
      'permission_changes': 0,
      'collection_gaps': 0,
      'screen_interactive': 0,
      'screen_non_interactive': 0,
      'user_present': 0,
      ...controllerCounts,
    };
    final usage = <Map<String, Object?>>[];
    final latestScreenAt = <String, int?>{
      'screen_interactive': null,
      'screen_non_interactive': null,
      'user_present': null,
    };

    for (final wire in usageWire) {
      final record = _sanitizeWire(wire, AndroidActivitySource.usageEvents);
      final kind = record.$1;
      if (kind == 'app.category_active') {
        counts['usage_observations'] = counts['usage_observations']! + 1;
        usage.add({
          'category': record.$4,
          'signal_at_ms': record.$2,
          'sequence': record.$3,
        });
      } else if (kind == 'probe.permission_changed') {
        counts['permission_changes'] = counts['permission_changes']! + 1;
      } else if (kind == 'probe.error') {
        counts['collection_gaps'] = counts['collection_gaps']! + 1;
      }
    }
    for (final wire in screenWire) {
      final record = _sanitizeWire(wire, AndroidActivitySource.screenState);
      final kind = record.$1;
      final countKey = switch (kind) {
        'screen.interactive' => 'screen_interactive',
        'screen.non_interactive' => 'screen_non_interactive',
        'session.unlocked' => 'user_present',
        'probe.error' => 'collection_gaps',
        _ => throw const AndroidActivityException(
            'diagnostic_evidence_invalid',
          ),
      };
      counts[countKey] = counts[countKey]! + 1;
      if (kind != 'probe.error') latestScreenAt[countKey] = record.$2;
    }

    return A3dEvidenceSnapshot({
      'schema': a3dEvidenceSchema,
      'authority': a3dDiagnosticAuthority,
      'readiness': {
        'collector': _publicReadiness(collectorReadiness),
        'publication_completeness': 'unknown',
        'usage': _coverageReadiness(usageCoverage),
        'screen': _coverageReadiness(screenCoverage),
      },
      'usage_permission': usagePermission.name,
      'observed_at_ms': observedAtMs,
      'timing': {
        'query_started_at_ms': queryStartedAtMs,
        'query_finished_at_ms': queryFinishedAtMs,
        'native_received_at_ms': nativeReceivedAtMs,
        'dart_ingest_at_ms': dartIngestAtMs,
      },
      'sequence': {'usage': usageSequence, 'screen': screenSequence},
      'counts': Map<String, int>.unmodifiable(counts),
      'usage_observations': List<Map<String, Object?>>.unmodifiable(usage),
      'screen_observations': {
        for (final entry in latestScreenAt.entries)
          entry.key: {
            'count': counts[entry.key],
            'last_signal_at_ms': entry.value,
          },
      },
    });
  }

  /// Public only so privacy-negative tests can exercise the exact production
  /// evidence reducer without exposing a second codec.
  static void validateWireForEvidence(
    Map<String, Object?> wire,
    AndroidActivitySource source,
  ) {
    _sanitizeWire(wire, source);
  }

  static (String, int, int, String?) _sanitizeWire(
    Map<String, Object?> wire,
    AndroidActivitySource expectedSource,
  ) {
    if (wire.keys.toSet().length != _wireKeys.length ||
        wire.keys.any((key) => !_wireKeys.contains(key)) ||
        wire['contract'] != 'device.activity.v1' ||
        wire['schema_version'] != 1 ||
        wire['source'] != expectedSource.wireValue ||
        wire['event_id'] is! String ||
        wire['device_id'] is! String ||
        wire['probe_id'] is! String ||
        wire['origin_sequence'] is! int ||
        wire['signal_at_ms'] is! int ||
        wire['ttl_ms'] is! int ||
        wire['confidence'] is! String ||
        wire['coverage'] is! Map ||
        wire['payload'] is! Map) {
      throw const AndroidActivityException('diagnostic_evidence_invalid');
    }
    final coverage = Map<String, Object?>.from(wire['coverage']! as Map);
    const coverageKeys = {
      'mode',
      'window_start_ms',
      'window_end_ms',
      'expected_report_interval_ms',
    };
    if (coverage.keys.toSet().length != coverageKeys.length ||
        coverage.keys.any((key) => !coverageKeys.contains(key)) ||
        coverage['mode'] != 'discrete_best_effort' ||
        coverage['window_start_ms'] is! int ||
        coverage['window_end_ms'] is! int ||
        coverage['expected_report_interval_ms'] is! int) {
      throw const AndroidActivityException('diagnostic_evidence_invalid');
    }
    final kind = wire['kind'];
    final sequence = wire['origin_sequence']! as int;
    final atMs = wire['signal_at_ms']! as int;
    if (kind is! String || sequence < 1 || atMs < 0) {
      throw const AndroidActivityException('diagnostic_evidence_invalid');
    }
    final payload = Map<String, Object?>.from(wire['payload']! as Map);
    String? category;
    switch (kind) {
      case 'app.category_active':
        if (expectedSource != AndroidActivitySource.usageEvents ||
            payload.keys.toSet().length != 1 ||
            !payload.containsKey('category') ||
            !_categories.contains(payload['category'])) {
          throw const AndroidActivityException('diagnostic_evidence_invalid');
        }
        category = payload['category']! as String;
        break;
      case 'probe.permission_changed':
        if (expectedSource != AndroidActivitySource.usageEvents ||
            payload.keys.toSet().length != 2 ||
            payload['capability'] != 'usage_events' ||
            payload['available'] is! bool) {
          throw const AndroidActivityException('diagnostic_evidence_invalid');
        }
        break;
      case 'probe.error':
        if (payload.keys.toSet().length != 1 ||
            payload['code'] != 'collection_failed') {
          throw const AndroidActivityException('diagnostic_evidence_invalid');
        }
        break;
      case 'screen.interactive':
      case 'screen.non_interactive':
      case 'session.unlocked':
        if (expectedSource != AndroidActivitySource.screenState ||
            payload.isNotEmpty) {
          throw const AndroidActivityException('diagnostic_evidence_invalid');
        }
        break;
      default:
        throw const AndroidActivityException('diagnostic_evidence_invalid');
    }
    return (kind, atMs, sequence, category);
  }
}

/// No production caller owns this controller. The A3-D entrypoint constructs it
/// only after debug/flavor guards have passed, and every effect is user-driven.
final class A3dDeviceGateController extends ChangeNotifier {
  // The contract measures action -> published unknown, not just Future wait.
  // Reserve 500ms of its 3s deadline for scheduling and snapshot publication.
  // Share this budget with observer reads because explicit actions coalesce
  // onto the existing Future. This is headroom, not a hard-real-time guarantee.
  static const _statusReplyWaitBudget = Duration(milliseconds: 2500);

  A3dDeviceGateController({
    required ActivityIntegrityKeyRepository keyRepository,
    required AndroidActivitySignalPlatform platform,
    required int Function() clockMs,
    required Map<String, String> categoryMapping,
    this.timingProbe,
  })  : _keyRepository = keyRepository,
        _platform = platform,
        _clockMs = clockMs,
        _categoryMapping = Map.unmodifiable(categoryMapping) {
    _snapshot = _emptySnapshot(clockMs());
  }

  final A3dTimingProbe? timingProbe;
  bool _timingHookFailed = false;

  void startTimingTrace() {
    if (kDebugMode && timingProbe?.start() == true) notifyListeners();
  }

  void armTimingRead(A3dTimingAction action) {
    if (kDebugMode && timingProbe?.arm(action) == true) notifyListeners();
  }

  void endTimingTrace() {
    timingProbe?.seal();
    notifyListeners();
  }

  Map<String, Object?> readTimingTrace() =>
      timingProbe?.readTrace(
        callbackFailed:
            _timingHookFailed || (_collector?.observationHookFailed ?? false),
      ) ??
      const {
        'schema': 'a3d.timing.v1',
        'complete': false,
        'sealed': false,
        'recording': false,
        'events': <Object>[],
      };

  void _trace(A3dTimingEvent event, {
    AndroidNativeObservationStatus? observed,
    bool? foreground,
  }) {
    timingProbe?.record(
      event,
      generation: _syncGeneration,
      foreground: foreground ?? _foreground,
      synchronization: _synchronization.index,
      status: observed ?? _nativeStatus,
      sameIdentity: observed == null || _nativeStatus == null
          ? null : observed.matches(_nativeStatus!),
      evidenceReady: (_snapshot.value['readiness'] as Map)['collector'] == 'ready',
      active: active,
      canQuery: canQuery,
    );
  }

  final ActivityIntegrityKeyRepository _keyRepository;
  final AndroidActivitySignalPlatform _platform;
  final int Function() _clockMs;
  final Map<String, String> _categoryMapping;
  final Map<String, int> _counts = {
    'start_requests': 0,
    'usage_queries': 0,
    'manual_refreshes': 0,
    'reset_requests': 0,
  };
  late A3dEvidenceSnapshot _snapshotValue;
  A3dEvidenceSnapshot get _snapshot => _snapshotValue;
  set _snapshot(A3dEvidenceSnapshot value) {
    _snapshotValue = value;
    _trace(A3dTimingEvent.snapshot);
  }
  AndroidActivityCollector? _collector;
  AndroidActivityCollectorStatus? _collectorStatus;
  int? _nextUsageStartMs;
  bool _busy = false;
  bool _consented = false;
  String _readiness = 'diagnostic_not_started';
  A3dResourceActionResult? _lastResourceActionResult;
  A3dStatusSynchronization _synchronizationValue =
      A3dStatusSynchronization.unknown;
  A3dStatusSynchronization get _synchronization => _synchronizationValue;
  set _synchronization(A3dStatusSynchronization value) {
    _synchronizationValue = value;
    _trace(
      value == A3dStatusSynchronization.checking
          ? A3dTimingEvent.checkingAssigned
          : A3dTimingEvent.synchronizationAssigned,
    );
  }

  AndroidNativeObservationStatus? _nativeStatus;
  Timer? _foregroundTimer;
  Future<bool>? _checking;
  int _syncGeneration = 0;
  bool _disposed = false;
  bool _foreground = false;
  AndroidDiagnosticOwnerReleasePermit? _releasePermit;
  Future<AndroidDiagnosticOwnerReleasePermit>? _pendingBeginPermit;
  final Map<AndroidActivitySource, Future<ActivityOutboxProcessLease>>
      _pendingAcquires = {};
  final Map<ActivityOutboxProcessLease, Future<bool>> _pendingLeaseReleases =
      {};
  final Map<AndroidDiagnosticOwnerReleasePermit, Future<bool>>
      _pendingPermitEnds = {};
  final Set<ActivityOutboxProcessLease> _timedOutLeaseReleases = {};
  final Set<AndroidDiagnosticOwnerReleasePermit> _timedOutPermitEnds = {};
  bool _pendingReset = false;
  int _resourceAction = 0;
  final Map<Object, int> _resourceAttempts = {};
  final Map<AndroidActivitySource, ActivityOutboxProcessLease> _recoveryLeases =
      {};
  final Map<AndroidActivitySource, ActivityOutboxReleaseTarget> _orphanTargets =
      {};
  final Map<AndroidActivitySource, String> _ownerReleaseCodes = {};
  final Set<AndroidActivitySource> _releasedTargets = {};
  final Set<AndroidActivitySource> _absentOwnerSources = {};
  List<Map<String, Object?>> _lastUsageWire = [];
  List<Map<String, Object?>> _lastScreenWire = [];
  int _lastUsageSequence = 0;
  int _lastScreenSequence = 0;
  bool _releaseInspectionComplete = false;
  String? _releaseRoot;

  bool get busy => _busy;
  bool get consented => _consented;
  bool get active =>
      _synchronization == A3dStatusSynchronization.verified &&
      _nativeStatus?.state == AndroidNativeObservationState.running &&
      _nativeStatus?.enabled == true &&
      _collector != null &&
      (_collectorStatus?.ready ?? false);
  bool get canQuery =>
      _synchronization == A3dStatusSynchronization.verified &&
      _nativeStatus?.state == AndroidNativeObservationState.running &&
      _nativeStatus?.enabled == true &&
      (_collectorStatus?.canQuery ?? false);
  bool get hasCollectorResources => _collector != null;
  A3dStatusSynchronization get synchronization => _synchronization;
  String get nativeState =>
      _synchronization == A3dStatusSynchronization.verified
          ? _nativeStatus?.state.name ?? 'unknown'
          : 'unknown';
  String get nativeReason => _synchronization ==
          A3dStatusSynchronization.verified
      ? _publicReadiness(_nativeStatus?.reason ?? 'activity_source_unavailable')
      : 'activity_source_unavailable';
  bool get canInjectOwnerFailure =>
      kDebugMode &&
      _collector != null &&
      _nativeStatus?.state == AndroidNativeObservationState.stopped &&
      _nativeStatus?.enabled == false;
  List<String> get resourceReleaseSummary => [
        for (final result in _collectorStatus?.sourceReleases.values ??
            const <AndroidActivitySourceReleaseResult>[])
          '${result.source.wireValue}: ${_publicReadiness(result.closeCode)}; '
              '文件租约已释放=${result.ownerLeaseReleased}; '
              '进程租约仍持有=${result.processLeaseHeld}; 文件声明仍持有=${result.fileClaimHeld}',
        for (final entry in _ownerReleaseCodes.entries)
          '${entry.key.wireValue}: ${_publicReadiness(entry.value)}',
        if (_releasePermit != null) '恢复许可仍持有，需完成显式释放',
        if (_pendingBeginPermit != null ||
            _pendingAcquires.isNotEmpty ||
            _pendingLeaseReleases.isNotEmpty ||
            _pendingPermitEnds.isNotEmpty)
          _pendingReset ? '清理请求等待回执；再次点击显式清理以接续原请求' : '恢复请求等待回执；再次点击无损释放以接续原请求',
      ];
  String get readiness => _readiness;
  A3dResourceActionResult? get lastResourceActionResult =>
      _lastResourceActionResult;
  A3dEvidenceSnapshot get evidence => _snapshot;

  void setForeground(bool foreground) {
    if (foreground) timingProbe?.action(A3dTimingAction.resume);
    _trace(A3dTimingEvent.foregroundEntered, foreground: foreground);
    if (_disposed) {
      _trace(A3dTimingEvent.controllerRejectedDisposed);
      return;
    }
    _foreground = foreground;
    _trace(A3dTimingEvent.foregroundChanged);
    _foregroundTimer?.cancel();
    if (!foreground) {
      ++_syncGeneration;
      _checking = null;
      _synchronization = A3dStatusSynchronization.unknown;
      return;
    }
    // Schedule outside widget build. Reads never create a collector or key.
    _synchronization = A3dStatusSynchronization.checking;
    scheduleMicrotask(() {
      if (!_disposed && _foreground) {
        unawaited(_synchronize(A3dTimingAction.resume));
      }
    });
    _foregroundTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_checking == null && _readiness != 'diagnostic_starting') {
        unawaited(_synchronize(A3dTimingAction.observer));
      }
    });
  }

  void _onCollectorStatus(AndroidActivityCollectorStatus status) {
    if (_disposed) {
      _trace(A3dTimingEvent.controllerRejectedDisposed);
      return;
    }
    final observed = status.nativeStatus;
    final prior = _nativeStatus;
    if (observed != null &&
        prior != null &&
        observed.sessionId == prior.sessionId &&
        (observed.revision < prior.revision ||
            (prior.matches(observed) &&
                prior.state == AndroidNativeObservationState.stopped &&
                observed.state == AndroidNativeObservationState.running))) {
      _trace(A3dTimingEvent.controllerRejectedRevision, observed: observed);
      return;
    }
    _trace(A3dTimingEvent.controllerAccepted, observed: observed);
    _collectorStatus = status;
    _nativeStatus = status.nativeStatus;
    if (!status.ready) {
      if (!_busy || _releasePermit == null) {
        _readiness = _publicReadiness(status.fixedCode);
      }
      _synchronization = status.nativeStatus == null ||
              status.nativeStatus!.state ==
                  AndroidNativeObservationState.unknown
          ? A3dStatusSynchronization.unknown
          : A3dStatusSynchronization.verified;
    }
    _refreshSnapshot();
    notifyListeners();
  }

  Future<bool> _synchronize([A3dTimingAction action = A3dTimingAction.poll]) {
    final pending = _checking;
    if (pending != null) {
      timingProbe?.skipped(action);
      return pending;
    }
    final generation = ++_syncGeneration;
    _synchronization = A3dStatusSynchronization.checking;
    _refreshSnapshot();
    notifyListeners();
    final work =
        timingProbe?.read(action, () => _readCurrentStatus(generation)) ??
            _readCurrentStatus(generation);
    _checking = work;
    return work.whenComplete(() {
      if (identical(_checking, work)) _checking = null;
    });
  }

  Future<bool> _readCurrentStatus(int generation) async {
    try {
      final collector = _collector;
      AndroidNativeObservationStatus? observed;
      var validRead = true;
      if (collector != null) {
        final status = await collector.synchronizeObservationStatus().timeout(
              _statusReplyWaitBudget,
            );
        if (_disposed ||
            generation != _syncGeneration ||
            !identical(collector, _collector)) {
          _trace(
            _disposed
                ? A3dTimingEvent.controllerRejectedDisposed
                : generation != _syncGeneration
                    ? A3dTimingEvent.controllerRejectedGeneration
                    : A3dTimingEvent.controllerRejectedCollector,
          );
          return false;
        }
        _collectorStatus = status;
        observed = status.nativeStatus;
        _readiness = _publicReadiness(status.fixedCode);
        validRead = status.fixedCode != 'observation_status_invalid';
      } else if (_platform is AndroidActivityObservationPlatform) {
        observed = await (_platform as AndroidActivityObservationPlatform)
            .getObservationStatus()
            .timeout(_statusReplyWaitBudget);
        if (_disposed || generation != _syncGeneration) {
          _trace(
            _disposed
                ? A3dTimingEvent.controllerRejectedDisposed
                : A3dTimingEvent.controllerRejectedGeneration,
          );
          return false;
        }
      }
      _trace(A3dTimingEvent.controllerAccepted, observed: observed);
      _nativeStatus = observed;
      final known = validRead &&
          observed != null &&
          observed.state != AndroidNativeObservationState.unknown;
      _synchronization = known
          ? A3dStatusSynchronization.verified
          : A3dStatusSynchronization.unknown;
      return known;
    } catch (error) {
      _trace(error is TimeoutException
          ? A3dTimingEvent.readTimedOut : A3dTimingEvent.readFailed);
      if (_disposed || generation != _syncGeneration) {
        _trace(
          _disposed
              ? A3dTimingEvent.controllerRejectedDisposed
              : A3dTimingEvent.controllerRejectedGeneration,
        );
        return false;
      }
      _synchronization = A3dStatusSynchronization.unknown;
      return false;
    } finally {
      if (!_disposed && generation == _syncGeneration) {
        _refreshSnapshot();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    timingProbe?.dispose();
    _disposed = true;
    ++_syncGeneration;
    _foregroundTimer?.cancel();
    _collector?.removeStatusListener(_onCollectorStatus);
    // Disposal only removes UI observation. Resource release is explicit.
    super.dispose();
  }

  @override
  void notifyListeners() {
    _timingHookFailed |= _collector?.observationHookFailed ?? false;
    if (!_disposed) {
      _trace(A3dTimingEvent.published);
      super.notifyListeners();
    }
  }

  Future<void> beginDiagnostic(A3dDiagnosticScenario scenario) async {
    if (_busy ||
        _collector != null ||
        _releasePermit != null ||
        _recoveryLeases.isNotEmpty ||
        _pendingBeginPermit != null ||
        _pendingAcquires.isNotEmpty) {
      return;
    }
    ++_syncGeneration;
    _checking = null;
    _busy = true;
    _consented = true;
    // A newly requested generation must never inherit an old action receipt.
    _lastResourceActionResult = null;
    _counts['start_requests'] = _counts['start_requests']! + 1;
    _readiness = 'diagnostic_starting';
    notifyListeners();
    try {
      if (scenario == A3dDiagnosticScenario.complete) {
        await _keyRepository.provision();
      }
      final bindings = _bindingsFor(scenario);
      final collector = AndroidActivityCollector(
        config: AndroidActivityCollectorConfig(
          enabled: true,
          bindings: bindings,
          categoryMapping: _categoryMapping,
          capacityPerSource: A3dDiagnosticBindingFactory.capacity,
          ttlMs: A3dDiagnosticBindingFactory.ttlMs,
        ),
        keyRepository: _keyRepository,
        platform: _platform,
        clockMs: _clockMs,
        audit: (_, __) {},
        observationHook: timingProbe?.collector,
      );
      _collector = collector;
      collector.addStatusListener(_onCollectorStatus);
      // Keep the R2 ten-second native startup window intact. A missing channel
      // reply must still return control to the explicit stop action.
      final status = await collector.initialize().timeout(
            const Duration(seconds: 12),
          );
      if (_disposed || !identical(collector, _collector)) return;
      _collectorStatus = status;
      _nativeStatus = status.nativeStatus;
      _readiness = _publicReadiness(status.fixedCode);
      _synchronization =
          status.nativeStatus?.state == AndroidNativeObservationState.running &&
                  status.ready
              ? A3dStatusSynchronization.verified
              : A3dStatusSynchronization.unknown;
      if (status.ready) {
        _nextUsageStartMs = _clockMs();
      } else if (status.canRetireWithoutObservation) {
        collector.removeStatusListener(_onCollectorStatus);
        _collector = null;
      }
    } on TimeoutException {
      _readiness = 'diagnostic_status_unknown';
      _synchronization = A3dStatusSynchronization.unknown;
    } on AndroidActivityException catch (error) {
      _readiness = _publicReadiness(error.code);
    } catch (_) {
      _readiness = 'diagnostic_failed';
    } finally {
      _busy = false;
      _refreshSnapshot();
      notifyListeners();
    }
  }

  Future<void> pollUsage() async {
    final collector = _collector;
    if (_busy || collector == null) return;
    _busy = true;
    notifyListeners();
    try {
      if (!await _synchronize() ||
          !canQuery ||
          !identical(collector, _collector)) {
        return;
      }
      _counts['usage_queries'] = _counts['usage_queries']! + 1;
      final startMs = _nextUsageStartMs ?? _clockMs();
      var endMs = _clockMs() + 1;
      if (endMs <= startMs) endMs = startMs + 1;
      _nextUsageStartMs = endMs;
      _collectorStatus = await collector.pollUsage(
        startMs: startMs,
        endMs: endMs,
      );
      _readiness = _publicReadiness(_collectorStatus!.fixedCode);
    } on AndroidActivityException catch (error) {
      _readiness = _publicReadiness(error.code);
    } catch (_) {
      _readiness = 'diagnostic_failed';
    } finally {
      _busy = false;
      _refreshSnapshot();
      notifyListeners();
    }
  }

  Future<void> refreshEvidence() async {
    timingProbe?.action(A3dTimingAction.manual);
    if (_busy) {
      timingProbe?.skipped(A3dTimingAction.manual, busy: true);
      return;
    }
    _counts['manual_refreshes'] = _counts['manual_refreshes']! + 1;
    await _synchronize(A3dTimingAction.manual);
  }

  Future<void> stop() async {
    final collector = _collector;
    if (_busy || collector == null) return;
    ++_syncGeneration;
    _checking = null;
    _busy = true;
    _lastResourceActionResult = null;
    var actionCode = 'diagnostic_failed';
    notifyListeners();
    try {
      _collectorStatus = collector.status;
      _refreshSnapshot();
      final result = await collector.stop();
      _collectorStatus = collector.status;
      _nativeStatus = result.nativeStatus;
      if (result.completed) {
        collector.removeStatusListener(_onCollectorStatus);
        _collector = null;
      }
      _nextUsageStartMs = null;
      _readiness = actionCode =
          result.completed ? 'collector_disabled' : 'observation_stop_failed';
      _synchronization =
          _nativeStatus?.state == AndroidNativeObservationState.stopped
              ? A3dStatusSynchronization.verified
              : A3dStatusSynchronization.unknown;
    } catch (_) {
      _readiness = actionCode = 'diagnostic_failed';
    } finally {
      _lastResourceActionResult =
          A3dResourceActionResult(A3dResourceAction.stop, actionCode);
      _busy = false;
      _refreshSnapshot();
      notifyListeners();
    }
  }

  Future<void> debugInvalidateNotificationEvidence() async {
    if (!kDebugMode ||
        _busy ||
        !active ||
        _platform is! AndroidActivityObservationPlatform) {
      return;
    }
    _busy = true;
    try {
      if (!await _synchronize() || !active) return;
      final accepted = await (_platform as AndroidActivityObservationPlatform)
          .debugInvalidateObservationNotification(_nativeStatus!);
      _readiness = accepted
          ? 'diagnostic_notification_loss_injected'
          : 'diagnostic_failed';
      // This only arms evidence loss. No stop or fabricated terminal receipt.
    } on AndroidActivityException catch (error) {
      _readiness = _publicReadiness(error.code);
    } catch (_) {
      _readiness = 'diagnostic_failed';
    } finally {
      _busy = false;
      _refreshSnapshot();
      notifyListeners();
    }
  }

  Future<void> debugFailUsageOwnerDeletion() async {
    if (!canInjectOwnerFailure || _busy) return;
    final collector = _collector!;
    _busy = true;
    try {
      if (!await _synchronize() ||
          !canInjectOwnerFailure ||
          !identical(collector, _collector)) {
        return;
      }
      collector.debugFailNextOwnerDelete(AndroidActivitySource.usageEvents);
      _busy = false;
      await stop();
    } on AndroidActivityException catch (error) {
      _readiness = _publicReadiness(error.code);
    } finally {
      _busy = false;
      _refreshSnapshot();
      notifyListeners();
    }
  }

  Future<void> releaseOrphanOwners() async {
    if (_busy) return;
    if (_pendingReset) {
      _readiness = 'diagnostic_reset_refused';
      _lastResourceActionResult = A3dResourceActionResult(
          A3dResourceAction.releaseOrphanOwners, _readiness);
      notifyListeners();
      return;
    }
    var preflightPassed = false;
    var actionCode = 'diagnostic_owner_release_refused';
    _lastResourceActionResult = null;
    // Only this attempt's primitive results can authorize confirmation.
    _releasedTargets.clear();
    ++_resourceAction;
    _busy = true;
    notifyListeners();
    try {
      if (!await _synchronize() ||
          _nativeStatus?.state != AndroidNativeObservationState.stopped ||
          _nativeStatus!.enabled ||
          _nativeStatus!.observationId.isEmpty ||
          _platform is! AndroidActivityOutboxLeasePlatform) {
        throw const AndroidActivityException(
          'diagnostic_owner_release_refused',
        );
      }
      final broker = _platform as AndroidActivityOutboxLeasePlatform;
      // A timeout never abandons an acquire whose token may arrive later.
      if (_pendingBeginPermit != null) {
        _releasePermit = await _awaitBeginPermit();
      }
      for (final source in _pendingAcquires.keys.toList()) {
        _recoveryLeases[source] = await _awaitAcquire(source);
      }
      // Retained unknown broker releases must complete before acquiring again.
      await _releaseRecoveryLeases(broker);
      if (_recoveryLeases.isNotEmpty) {
        throw const AndroidActivityException('diagnostic_outbox_lease_held');
      }
      final current = _nativeStatus!;
      final retainedPermit = _releasePermit;
      if (retainedPermit != null && !retainedPermit.status.matches(current)) {
        throw const AndroidActivityException('observation_target_changed');
      }
      // Native may already have ended the permit while its reply was lost.
      // Reconcile that exact token before trying to acquire any new lease.
      if (retainedPermit != null) {
        if (!await _endRecoveryPermit(broker, retainedPermit)) {
          throw const AndroidActivityException(
              'diagnostic_owner_release_active');
        }
        _releasePermit = null;
      }
      if (_releasePermit == null) {
        _pendingBeginPermit = broker.beginDiagnosticOwnerRelease(current);
        _releasePermit = await _awaitBeginPermit();
      }
      final permit = _releasePermit!;
      if (!permit.status.matches(current) ||
          permit.status.state != AndroidNativeObservationState.stopped ||
          permit.status.enabled) {
        throw const AndroidActivityException(
          'diagnostic_owner_release_refused',
        );
      }
      for (final source in AndroidActivitySource.values) {
        _pendingAcquires[source] = broker.acquireDiagnosticOutboxLease(
          source,
          permitToken: permit.token,
        );
        _recoveryLeases[source] = await _awaitAcquire(source);
      }
      final key = await _keyRepository.readRequired();
      final root = await _validatedRoot();
      if (_releaseRoot != null && _releaseRoot != root.path) {
        throw const AndroidActivityException('owner_release_target_changed');
      }
      _releaseRoot = root.path;
      if (!_releaseInspectionComplete) {
        final retained = _collector?.releaseTargets ??
            const <AndroidActivitySource, ActivityOutboxReleaseTarget>{};
        for (final source in AndroidActivitySource.values) {
          final ownTarget = retained[source];
          if (ownTarget != null) {
            _orphanTargets.putIfAbsent(source, () => ownTarget);
            continue;
          }
          if (_orphanTargets.containsKey(source)) continue;
          final directory = _sourceDirectory(root, source);
          if (!directory.existsSync()) {
            _ownerReleaseCodes[source] = 'diagnostic_outbox_absent';
            _absentOwnerSources.add(source);
            continue;
          }
          if (!File('${directory.path}${Platform.pathSeparator}owner.json')
              .existsSync()) {
            final priorRelease = _collectorStatus?.sourceReleases[source];
            if (priorRelease?.closeCode != 'closed' ||
                !priorRelease!.ownerLeaseReleased ||
                priorRelease.processLeaseHeld ||
                priorRelease.fileClaimHeld) {
              throw const AndroidActivityException(
                  'diagnostic_owner_release_refused');
            }
            _ownerReleaseCodes[source] = 'closed';
            _absentOwnerSources.add(source);
            continue;
          }
          _orphanTargets[source] = FileActivityOutboxStore.inspectReleaseTarget(
            directory: directory,
            integrityKey: key,
            binding: A3dDiagnosticBindingFactory.create(source),
          );
        }
        _releaseInspectionComplete = true;
      }
      // Both sources are preflighted before any deletion. The file primitive
      // repeats the byte checks inside each OS gate immediately before delete.
      for (final entry in _orphanTargets.entries) {
        FileActivityOutboxStore.verifyReleaseTarget(
          directory: _sourceDirectory(root, entry.key),
          integrityKey: key,
          target: entry.value,
        );
      }
      for (final source in _absentOwnerSources) {
        if (File(
                '${_sourceDirectory(root, source).path}${Platform.pathSeparator}owner.json')
            .existsSync()) {
          throw const AndroidActivityException('owner_release_target_changed');
        }
      }
      preflightPassed = true;
      for (final source in AndroidActivitySource.values) {
        final target = _orphanTargets[source];
        if (target == null) continue;
        try {
          final result = FileActivityOutboxStore.releaseExactOwner(
            directory: _sourceDirectory(root, source),
            integrityKey: key,
            target: target,
            processLease: _recoveryLeases[source]!,
          );
          _releasedTargets.add(source);
          _ownerReleaseCodes[source] =
              result == ActivityOutboxOwnerReleaseOutcome.released
                  ? 'owner_released'
                  : 'target_absent';
        } on AndroidActivityException catch (error) {
          _releasedTargets.remove(source);
          _ownerReleaseCodes[source] = _publicReadiness(error.code);
        } catch (_) {
          _releasedTargets.remove(source);
          _ownerReleaseCodes[source] = 'owner_release_failed';
        }
      }
      _readiness = actionCode =
          _orphanTargets.keys.every(_releasedTargets.contains)
          ? 'diagnostic_owner_release_complete'
          : 'diagnostic_owner_release_partial';
    } on AndroidActivityException catch (error) {
      _readiness = actionCode = _publicReadiness(error.code);
    } catch (_) {
      _readiness = actionCode = 'diagnostic_owner_release_refused';
    } finally {
      var confirmationFailed = false;
      if (_platform is AndroidActivityOutboxLeasePlatform) {
        final broker = _platform as AndroidActivityOutboxLeasePlatform;
        await _releaseRecoveryLeases(broker);
        if (_recoveryLeases.isEmpty &&
            _pendingAcquires.isEmpty &&
            _pendingBeginPermit == null) {
          final collector = _collector;
          if (collector != null && preflightPassed) {
            for (final source in _releasedTargets) {
              final target = _orphanTargets[source];
              if (target != null &&
                  identical(collector.releaseTargets[source], target)) {
                try {
                  collector.confirmReleasedOwner(source, target);
                } catch (_) {
                  confirmationFailed = true;
                  _ownerReleaseCodes[source] = 'owner_release_failed';
                }
              }
            }
            final status = collector.status;
            if (status.sourceReleases.length ==
                    AndroidActivitySource.values.length &&
                status.sourceReleases.values.every(
                  (result) =>
                      result.closeCode == 'closed' &&
                      result.ownerLeaseReleased &&
                      !result.processLeaseHeld &&
                      !result.fileClaimHeld,
                )) {
              collector.removeStatusListener(_onCollectorStatus);
              _collectorStatus = status;
              _collector = null;
            }
          }
          final permit = _releasePermit;
          if (permit != null && !confirmationFailed) {
            try {
              if (await _endRecoveryPermit(broker, permit)) {
                _releasePermit = null;
              }
            } catch (_) {
              /* Keep the exact permit for an explicit retry. */
            }
          }
        }
      }
      if (_recoveryLeases.isNotEmpty ||
          _releasePermit != null ||
          _pendingBeginPermit != null ||
          _pendingAcquires.isNotEmpty) {
        _readiness = actionCode = 'diagnostic_owner_release_partial';
      }
      _lastResourceActionResult = A3dResourceActionResult(
          A3dResourceAction.releaseOrphanOwners, actionCode);
      _busy = false;
      _refreshSnapshot();
      notifyListeners();
    }
  }

  Future<Directory> _validatedRoot() async {
    final root = await _platform.getOutboxRoot();
    if (root.storageScope != 'no_backup_private' ||
        !_isExactDiagnosticRoot(root.path)) {
      throw const AndroidActivityException('diagnostic_reset_scope_invalid');
    }
    final directory = Directory(root.path);
    if (directory.existsSync()) {
      final resolved = directory.resolveSymbolicLinksSync();
      bool same(String left, String right) => Platform.isWindows
          ? left.toLowerCase() == right.toLowerCase()
          : left == right;
      if (!same(resolved, directory.absolute.path) ||
          FileSystemEntity.typeSync(directory.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw const AndroidActivityException('diagnostic_reset_scope_invalid');
      }
      final names = AndroidActivitySource.values
          .map((source) => source.wireValue)
          .toSet();
      if (directory.listSync(followLinks: false).any(
            (entity) =>
                entity is! Directory || !names.contains(_basename(entity.path)),
          )) {
        throw const AndroidActivityException('diagnostic_reset_scope_invalid');
      }
    }
    return directory;
  }

  Directory _sourceDirectory(Directory root, AndroidActivitySource source) =>
      Directory('${root.path}${Platform.pathSeparator}${source.wireValue}');

  Future<void> _releaseRecoveryLeases(
    AndroidActivityOutboxLeasePlatform broker,
  ) async {
    for (final entry in _recoveryLeases.entries.toList().reversed) {
      final lease = entry.value;
      if (lease.hasFileClaim) continue;
      if (!lease.isHeld) {
        _recoveryLeases.remove(entry.key);
        _pendingLeaseReleases.remove(lease);
        _timedOutLeaseReleases.remove(lease);
        continue;
      }
      if (_resourceAttempts[lease] == _resourceAction) continue;
      _resourceAttempts[lease] = _resourceAction;
      try {
        if (_timedOutLeaseReleases.remove(lease)) {
          _pendingLeaseReleases.remove(lease);
        }
        final pending = _pendingLeaseReleases[lease] ??=
            broker.releaseDiagnosticOutboxLease(lease);
        final released =
            !lease.isHeld || await pending.timeout(const Duration(seconds: 3));
        _pendingLeaseReleases.remove(lease);
        if (released && !lease.isHeld) {
          _recoveryLeases.remove(entry.key);
        }
      } on TimeoutException {
        // The token is known. A later explicit retry may resend this exact
        // release; an old receipt can only change its original lease object.
        _timedOutLeaseReleases.add(lease);
      } catch (_) {
        _pendingLeaseReleases.remove(lease);
        /* Retain the actual resource until native proof exists. */
      }
    }
  }

  Future<AndroidDiagnosticOwnerReleasePermit> _awaitBeginPermit() async {
    try {
      final permit =
          await _pendingBeginPermit!.timeout(const Duration(seconds: 3));
      _pendingBeginPermit = null;
      return permit;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      _pendingBeginPermit = null;
      rethrow;
    }
  }

  Future<ActivityOutboxProcessLease> _awaitAcquire(
      AndroidActivitySource source) async {
    try {
      final lease =
          await _pendingAcquires[source]!.timeout(const Duration(seconds: 3));
      _pendingAcquires.remove(source);
      return lease;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      _pendingAcquires.remove(source);
      rethrow;
    }
  }

  Future<bool> _endRecoveryPermit(AndroidActivityOutboxLeasePlatform broker,
      AndroidDiagnosticOwnerReleasePermit permit) async {
    if (_resourceAttempts[permit] == _resourceAction) {
      throw const AndroidActivityException('diagnostic_owner_release_active');
    }
    _resourceAttempts[permit] = _resourceAction;
    try {
      if (_timedOutPermitEnds.remove(permit)) _pendingPermitEnds.remove(permit);
      final pending = _pendingPermitEnds[permit] ??=
          broker.endDiagnosticOwnerRelease(permit);
      final ended = await pending.timeout(const Duration(seconds: 3));
      _pendingPermitEnds.remove(permit);
      return ended;
    } on TimeoutException {
      _timedOutPermitEnds.add(permit);
      rethrow;
    } catch (_) {
      _pendingPermitEnds.remove(permit);
      rethrow;
    }
  }

  /// Explicit reset for this diagnostic namespace only. It never clears app
  /// data or the integrity key. A stale owner must first be proven stale by the
  /// existing signed recovery authority plus the stable OS gate.
  Future<void> resetDiagnosticOutbox() async {
    if (_busy) return;
    if (_collector != null ||
        _releasePermit != null ||
        _pendingBeginPermit != null ||
        (_pendingAcquires.isNotEmpty && !_pendingReset)) {
      _readiness = 'diagnostic_reset_requires_disposed';
      _lastResourceActionResult =
          A3dResourceActionResult(A3dResourceAction.reset, _readiness);
      notifyListeners();
      return;
    }
    _busy = true;
    _lastResourceActionResult = null;
    var actionCode = 'diagnostic_reset_refused';
    ++_resourceAction;
    _counts['reset_requests'] = _counts['reset_requests']! + 1;
    notifyListeners();
    try {
      if (_platform is! AndroidActivityOutboxLeasePlatform) {
        throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
      }
      final broker = _platform as AndroidActivityOutboxLeasePlatform;
      for (final source in _pendingAcquires.keys.toList()) {
        _recoveryLeases[source] = await _awaitAcquire(source);
      }
      await _releaseRecoveryLeases(broker);
      if (_recoveryLeases.isNotEmpty) {
        throw const AndroidActivityException('diagnostic_outbox_lease_held');
      }
      final key = await _keyRepository.readRequired();
      final directory = await _validatedRoot();
      if (!directory.existsSync()) {
        _readiness = actionCode = 'diagnostic_outbox_absent';
        return;
      }
      for (final source in AndroidActivitySource.values) {
        _pendingReset = true;
        _pendingAcquires[source] = broker.acquireDiagnosticOutboxLease(source);
        _recoveryLeases[source] = await _awaitAcquire(source);
      }
      for (final source in AndroidActivitySource.values) {
        final sourceDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}${source.wireValue}',
        );
        if (!sourceDirectory.existsSync()) continue;
        _releaseVerifiedOwner(
          sourceDirectory,
          source,
          key,
          _recoveryLeases[source]!,
        );
      }
      for (final source in AndroidActivitySource.values) {
        final sourceDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}${source.wireValue}',
        );
        if (sourceDirectory.existsSync()) {
          sourceDirectory.deleteSync(recursive: true);
        }
      }
      if (directory.existsSync() && directory.listSync().isEmpty) {
        directory.deleteSync();
      }
      _collectorStatus = null;
      _orphanTargets.clear();
      _releasedTargets.clear();
      _absentOwnerSources.clear();
      _ownerReleaseCodes.clear();
      _releaseRoot = null;
      _releaseInspectionComplete = false;
      _lastUsageWire = [];
      _lastScreenWire = [];
      _lastUsageSequence = 0;
      _lastScreenSequence = 0;
      _readiness = actionCode = 'diagnostic_reset_complete';
      _snapshot = _emptySnapshot(_clockMs());
    } on AndroidActivityException catch (error) {
      _readiness = actionCode = _publicReadiness(error.code);
    } catch (_) {
      _readiness = actionCode = 'diagnostic_reset_refused';
    } finally {
      if (_platform is AndroidActivityOutboxLeasePlatform) {
        await _releaseRecoveryLeases(
          _platform as AndroidActivityOutboxLeasePlatform,
        );
        if (_recoveryLeases.isNotEmpty) {
          _readiness = actionCode = 'diagnostic_reset_refused';
        }
      }
      if (_recoveryLeases.isEmpty && _pendingAcquires.isEmpty) {
        _pendingReset = false;
      }
      _lastResourceActionResult =
          A3dResourceActionResult(A3dResourceAction.reset, actionCode);
      _busy = false;
      notifyListeners();
    }
  }

  void _releaseVerifiedOwner(
    Directory directory,
    AndroidActivitySource source,
    List<int> key,
    ActivityOutboxProcessLease processLease,
  ) {
    const allowedFiles = {
      'anchor.json',
      'state.json',
      'journal.json',
      'owner.json',
      'owner.gate',
    };
    final entries = directory.listSync(followLinks: false);
    if (entries.any(
      (entity) =>
          entity is! File || !allowedFiles.contains(_basename(entity.path)),
    )) {
      throw const AndroidActivityException('diagnostic_reset_scope_invalid');
    }
    final owner = File('${directory.path}${Platform.pathSeparator}owner.json');
    if (!owner.existsSync()) {
      _proveGateIsFree(directory, source, processLease);
      return;
    }
    final inspection = FileActivityOutboxStore.inspectRecovery(
      directory: directory,
      integrityKey: key,
    );
    if (inspection.source != source) {
      throw const AndroidActivityException('diagnostic_reset_scope_invalid');
    }
    final store = FileActivityOutboxStore.open(
      directory: directory,
      binding: A3dDiagnosticBindingFactory.create(source),
      capacity: A3dDiagnosticBindingFactory.capacity,
      integrityKey: key,
      ageProofProvider: HmacActivityAgeProofProvider(integrityKey: key),
      clockMs: _clockMs,
      recoveryAuthority: ActivityOutboxRecoveryAuthority.fromInspection(
        inspection,
      ),
      processLease: processLease,
    );
    store.close();
    if (owner.existsSync()) {
      throw const AndroidActivityException('diagnostic_reset_owner_present');
    }
  }

  void _proveGateIsFree(
    Directory directory,
    AndroidActivitySource source,
    ActivityOutboxProcessLease processLease,
  ) {
    final claimant = Object();
    processLease.claimFileAccess(claimant, source.wireValue);
    RandomAccessFile? gate;
    try {
      processLease.verifyFileAccess(claimant, source.wireValue);
      gate = File(
        '${directory.path}${Platform.pathSeparator}owner.gate',
      ).openSync(mode: FileMode.append);
      gate.lockSync(FileLock.exclusive);
    } catch (_) {
      throw const AndroidActivityException('diagnostic_reset_owner_present');
    } finally {
      gate?.closeSync();
      processLease.releaseFileAccess(claimant);
    }
  }

  AndroidActivityCollectorBindings _bindingsFor(
    A3dDiagnosticScenario scenario,
  ) =>
      AndroidActivityCollectorBindings(
        usageEvents: scenario == A3dDiagnosticScenario.missingUsageBinding
            ? null
            : A3dDiagnosticBindingFactory.create(
                AndroidActivitySource.usageEvents),
        screenState: scenario == A3dDiagnosticScenario.missingScreenBinding
            ? null
            : A3dDiagnosticBindingFactory.create(
                AndroidActivitySource.screenState),
      );

  void _refreshSnapshot() {
    final status = _collector?.status ?? _collectorStatus;
    try {
      final usageStore = _collector?.usageOutbox;
      final screenStore = _collector?.screenOutbox;
      if (usageStore != null) {
        _lastUsageWire = usageStore.durableRecords
            .map((record) => record.event.toJson())
            .toList();
        _lastUsageSequence = usageStore.lastAllocatedSequence;
      }
      if (screenStore != null) {
        _lastScreenWire = screenStore.durableRecords
            .map((record) => record.event.toJson())
            .toList();
        _lastScreenSequence = screenStore.lastAllocatedSequence;
      }
      final displayedReadiness =
          _synchronization == A3dStatusSynchronization.checking
              ? 'diagnostic_status_checking'
              : _readiness == 'ready' &&
                      _synchronization != A3dStatusSynchronization.verified
                  ? 'diagnostic_status_unknown'
                  : _readiness;
      _snapshot = A3dEvidenceCodec.project(
        observedAtMs: _clockMs(),
        collectorReadiness: displayedReadiness,
        usagePermission: status?.usage?.permission ?? UsageAccess.unknown,
        usageCoverage: status?.usage?.coverage,
        screenCoverage: status?.screen?.coverage,
        usageSequence: _lastUsageSequence,
        screenSequence: _lastScreenSequence,
        usageWire: _lastUsageWire,
        screenWire: _lastScreenWire,
        controllerCounts: {..._counts, ...?status?.deliveryDiagnostics},
        queryStartedAtMs: status?.queryStartedAtMs ?? 0,
        queryFinishedAtMs: status?.queryFinishedAtMs ?? 0,
        nativeReceivedAtMs: status?.nativeReceivedAtMs ?? 0,
        dartIngestAtMs: status?.dartIngestAtMs ?? 0,
      );
    } on AndroidActivityException {
      _readiness = 'diagnostic_evidence_invalid';
      _snapshot = _emptySnapshot(_clockMs());
    }
  }

  A3dEvidenceSnapshot _emptySnapshot(int observedAtMs) =>
      A3dEvidenceCodec.project(
        observedAtMs: observedAtMs,
        collectorReadiness: _readiness,
        usagePermission: UsageAccess.unknown,
        usageCoverage: null,
        screenCoverage: null,
        usageSequence: 0,
        screenSequence: 0,
        usageWire: const [],
        screenWire: const [],
        controllerCounts: _counts,
      );
}

const _publicReadinessCodes = {
  'diagnostic_status_checking',
  'diagnostic_status_unknown',
  'diagnostic_notification_loss_injected',
  'observation_status_invalid',
  'observation_stop_failed',
  'observation_target_changed',
  'observation_control_required',
  'notification_stop',
  'user_stop',
  'service_destroyed',
  'activity_starting',
  'closed',
  'not_created',
  'owner_lock_cleanup_failed',
  'owner_still_active',
  'owner_release_failed',
  'owner_release_target_changed',
  'owner_release_journal_present',
  'owner_release_path_invalid',
  'owner_released',
  'target_absent',
  'diagnostic_owner_release_complete',
  'diagnostic_owner_release_partial',
  'diagnostic_owner_release_refused',
  'diagnostic_owner_release_active',
  'diagnostic_outbox_lease_held',
  'diagnostic_outbox_lease_invalid',
  'outbox_lease_file_claim_invalid',
  'diagnostic_not_started',
  'diagnostic_starting',
  'ready',
  'collector_disabled',
  'collector_already_active',
  'source_binding_missing',
  'integrity_authority_missing',
  'integrity_key_missing',
  'integrity_key_invalid',
  'integrity_key_unavailable',
  'integrity_key_generation_failed',
  'integrity_key_write_failed',
  'private_outbox_root_invalid',
  'recovery_authority_required',
  'usage_permission_denied',
  'usage_permission_revoked',
  'usage_query_failed',
  'usage_query_null',
  'usage_query_empty_unproven',
  'usage_query_window_consumed',
  'usage_events_expired',
  'device_locked',
  'activity_opt_in_required',
  'debug_diagnostic_required',
  'foreground_start_not_allowed',
  'foreground_start_failed',
  'foreground_state_lost',
  'notification_not_visible',
  'appops_watcher_unavailable',
  'boot_marker_unavailable',
  'boot_marker_changed',
  'owner_fence_mismatch',
  'service_instance_mismatch',
  'activity_source_unavailable',
  'activity_authority_invalid',
  'epoch_state_corrupt',
  'epoch_state_write_failed',
  'epoch_opened_no_backfill',
  'query_epoch_tainted',
  'clock_uncertain',
  'diagnostic_evidence_invalid',
  'diagnostic_reset_requires_disposed',
  'diagnostic_reset_scope_invalid',
  'diagnostic_reset_owner_present',
  'diagnostic_reset_complete',
  'diagnostic_reset_refused',
  'diagnostic_outbox_absent',
};

String _publicReadiness(String code) =>
    _publicReadinessCodes.contains(code) ? code : 'diagnostic_failed';

String _coverageReadiness(AndroidCoverage? coverage) => switch (coverage) {
      null => 'unknown',
      AndroidCoverage.unobserved => 'unknown',
      AndroidCoverage.permissionUnavailable => 'permission_unavailable',
      AndroidCoverage.recoveryPending => 'recovery_pending',
      AndroidCoverage.gap => 'gap',
      AndroidCoverage.fresh => 'fresh',
      AndroidCoverage.stale => 'stale',
      AndroidCoverage.clockUncertain => 'clock_uncertain',
      AndroidCoverage.lineageBlocked => 'lineage_blocked',
    };

bool _isExactDiagnosticRoot(String path) {
  if (!(path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path))) {
    return false;
  }
  return _basename(path) == 'mda2_activity';
}

String _basename(String path) =>
    path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).last;
