import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'activity_outbox_process_lease.dart';
import 'android_activity_normalizer.dart';

typedef AndroidNativeSignalHandler =
    Future<void> Function(Map<String, Object?> signal);

/// Narrow read-only seam for path-boundary tests; production uses Dart IO.
abstract interface class AndroidPrivateOutboxFileSystem {
  FileSystemEntityType typeWithoutFollowingLinks(String path);
  String resolveDirectory(String path);
}

final class _DartPrivateOutboxFileSystem
    implements AndroidPrivateOutboxFileSystem {
  const _DartPrivateOutboxFileSystem();

  @override
  FileSystemEntityType typeWithoutFollowingLinks(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false);

  @override
  String resolveDirectory(String path) =>
      Directory(path).resolveSymbolicLinksSync();
}

final class AndroidPrivateOutboxRoot {
  const AndroidPrivateOutboxRoot({
    required this.path,
    required this.storageScope,
  });

  final String path;
  final String storageScope;
}

final class AndroidNativeActivation {
  const AndroidNativeActivation({
    required this.enabled,
    required this.readiness,
    this.observationStatus,
  });

  final bool enabled;
  final String readiness;
  final AndroidNativeObservationStatus? observationStatus;
}

enum AndroidNativeObservationState {
  unknown,
  starting,
  running,
  stopping,
  stopped,
}

final class AndroidNativeObservationStatus {
  const AndroidNativeObservationStatus({
    required this.sessionId,
    required this.observationId,
    required this.revision,
    required this.state,
    required this.enabled,
    required this.reason,
  });

  final String sessionId;
  final String observationId;
  final int revision;
  final AndroidNativeObservationState state;
  final bool enabled;
  final String reason;

  bool matches(AndroidNativeObservationStatus other) =>
      sessionId == other.sessionId && observationId == other.observationId;
}

enum AndroidNativeStopOutcome { stopped, targetChanged, unknown, failed }

final class AndroidNativeStopObservationResult {
  const AndroidNativeStopObservationResult({
    required this.outcome,
    required this.status,
  });

  final AndroidNativeStopOutcome outcome;
  final AndroidNativeObservationStatus status;
}

final class AndroidDiagnosticOwnerReleasePermit {
  const AndroidDiagnosticOwnerReleasePermit({
    required this.token,
    required this.status,
  });

  final String token;
  final AndroidNativeObservationStatus status;
}

final class _MethodChannelActivityOutboxProcessLease
    implements ActivityOutboxProcessLease {
  _MethodChannelActivityOutboxProcessLease(this.source, this.token);

  @override
  final String source;
  final String token;
  Object? _claimant;
  var _fileClaimReleased = false;
  var _held = true;

  @override
  bool get isHeld => _held;

  @override
  bool get hasFileClaim => _claimant != null && !_fileClaimReleased;

  @override
  void claimFileAccess(Object claimant, String requestedSource) {
    if (!_held || requestedSource != source || _claimant != null) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    _claimant = claimant;
  }

  @override
  void verifyFileAccess(Object claimant, String requestedSource) {
    if (!_held ||
        requestedSource != source ||
        _claimant != claimant ||
        _fileClaimReleased) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
  }

  @override
  void releaseFileAccess(Object claimant) {
    verifyFileAccess(claimant, source);
    _fileClaimReleased = true;
  }

  void markReleased() {
    if (hasFileClaim) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    _held = false;
  }
}

final class AndroidNativeUsageBatch {
  const AndroidNativeUsageBatch({
    required this.permission,
    required this.readiness,
    required this.signals,
    this.screenSignals = const [],
    this.deliveryEpoch = '',
    this.deliveryId = '',
    this.queryStartedAtMs = 0,
    this.queryFinishedAtMs = 0,
    this.nativeReceivedAtMs = 0,
    this.dartIngestAtMs = 0,
    this.observationStatus,
    required this.counters,
  });

  final UsageAccess permission;
  final String readiness;
  final List<Map<String, Object?>> signals;
  final List<Map<String, Object?>> screenSignals;
  final String deliveryEpoch;
  final String deliveryId;
  final int queryStartedAtMs;
  final int queryFinishedAtMs;
  final int nativeReceivedAtMs;
  final int dartIngestAtMs;
  final AndroidNativeObservationStatus? observationStatus;
  final Map<String, int> counters;
}

abstract interface class AndroidActivitySignalPlatform {
  void setSignalHandler(AndroidNativeSignalHandler? handler);

  Future<AndroidPrivateOutboxRoot> getOutboxRoot();

  Future<AndroidNativeActivation> activate({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
  });

  Future<AndroidNativeUsageBatch> queryUsageEvents({
    required int startMs,
    required int endMs,
  });

  Future<void> deactivate();
}

/// R3-only native state boundary. Old test fakes intentionally need not expose
/// it; the MethodChannel implementation is required to implement it.
abstract interface class AndroidActivityObservationPlatform {
  void setObservationStatusHandler(
    Future<void> Function(AndroidNativeObservationStatus status)? handler,
  );

  Future<AndroidNativeObservationStatus> getObservationStatus();

  Future<AndroidNativeActivation> activateObservation({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
    required Map<AndroidActivitySource, ActivityOutboxProcessLease> leases,
  });

  Future<bool> debugInvalidateObservationNotification(
    AndroidNativeObservationStatus target,
  );

  Future<AndroidNativeStopObservationResult> stopObservation(
    AndroidNativeObservationStatus target,
  );
}

abstract interface class AndroidActivityOutboxLeasePlatform {
  Future<ActivityOutboxProcessLease> acquireDiagnosticOutboxLease(
    AndroidActivitySource source, {
    String permitToken = '',
  });
  Future<bool> releaseDiagnosticOutboxLease(ActivityOutboxProcessLease lease);

  Future<AndroidDiagnosticOwnerReleasePermit> beginDiagnosticOwnerRelease(
    AndroidNativeObservationStatus target,
  );
  Future<bool> endDiagnosticOwnerRelease(
    AndroidDiagnosticOwnerReleasePermit permit,
  );
}

typedef AndroidNativeBatchHandler =
    Future<List<String>> Function(AndroidNativeUsageBatch batch);

/// Local delivery receipt only, never a Core acknowledgement or wire event.
abstract interface class AndroidActivityDeliveryPlatform {
  void setBatchHandler(AndroidNativeBatchHandler? handler);
  Future<void> acknowledgeBatch(
    AndroidNativeUsageBatch batch,
    List<String> dispositions,
  );
}

final class MethodChannelAndroidActivitySignalPlatform
    implements
        AndroidActivitySignalPlatform,
        AndroidActivityDeliveryPlatform,
        AndroidActivityObservationPlatform,
        AndroidActivityOutboxLeasePlatform {
  MethodChannelAndroidActivitySignalPlatform({
    MethodChannel? channel,
    AndroidPrivateOutboxFileSystem? outboxFileSystemForTesting,
  }) : _channel =
           channel ?? const MethodChannel('com.memexlab.memex/activity_signal'),
       _outboxFileSystem =
           outboxFileSystemForTesting ?? const _DartPrivateOutboxFileSystem();

  final MethodChannel _channel;
  final AndroidPrivateOutboxFileSystem _outboxFileSystem;
  String? _canonicalOutboxRootPath;
  AndroidNativeSignalHandler? _signalHandler;
  AndroidNativeBatchHandler? _batchHandler;
  Future<void> Function(AndroidNativeObservationStatus status)?
  _observationStatusHandler;

  @override
  void setBatchHandler(AndroidNativeBatchHandler? handler) {
    _batchHandler = handler;
    _installHandler();
  }

  @override
  Future<void> acknowledgeBatch(
    AndroidNativeUsageBatch batch,
    List<String> dispositions,
  ) async {
    try {
      final accepted = await _channel.invokeMethod<bool>(
        'acknowledgeBatch',
        _receipt(batch, dispositions),
      );
      if (accepted != true) {
        throw const AndroidActivityException('delivery_ack_rejected');
      }
    } on PlatformException catch (error) {
      throw AndroidActivityException(error.code);
    }
  }

  Map<String, Object?> _receipt(
    AndroidNativeUsageBatch batch,
    List<String> dispositions,
  ) => {
    'delivery_epoch': batch.deliveryEpoch,
    'delivery_id': batch.deliveryId,
    'dispositions': dispositions,
  };

  @override
  void setSignalHandler(AndroidNativeSignalHandler? handler) {
    _signalHandler = handler;
    _installHandler();
  }

  @override
  void setObservationStatusHandler(
    Future<void> Function(AndroidNativeObservationStatus status)? handler,
  ) {
    _observationStatusHandler = handler;
    _installHandler();
  }

  void _installHandler() {
    _channel.setMethodCallHandler(
      _signalHandler == null &&
              _batchHandler == null &&
              _observationStatusHandler == null
          ? null
          : (call) async {
              if (call.method == 'onBatch') {
                final handler = _batchHandler;
                if (handler == null || call.arguments is! Map) {
                  throw PlatformException(
                    code: 'delivery_receiver_unavailable',
                  );
                }
                final batch = _parseBatch(
                  Map<String, Object?>.from(call.arguments as Map),
                );
                return _receipt(batch, await handler(batch));
              }
              if (call.method == 'onObservationStatus') {
                final handler = _observationStatusHandler;
                if (handler == null || call.arguments is! Map) {
                  throw PlatformException(
                    code: 'observation_status_receiver_unavailable',
                  );
                }
                await handler(
                  _parseObservationStatus(
                    Map<String, Object?>.from(call.arguments as Map),
                  ),
                );
                return null;
              }
              if (call.method != 'onSignal') return null;
              final signal = _privacyReducedSignal(call.arguments);
              await _signalHandler?.call(signal);
            },
    );
  }

  @override
  Future<AndroidPrivateOutboxRoot> getOutboxRoot() async {
    final response = await _invokeMap('getOutboxRoot');
    _exactKeys(response, const {'path', 'storage_scope'});
    final path = response['path'];
    final scope = response['storage_scope'];
    if (path is! String || scope != 'no_backup_private') {
      throw const AndroidActivityException('private_outbox_root_invalid');
    }
    try {
      final canonical = _canonicalPrivateOutboxRoot(path);
      final previous = _canonicalOutboxRootPath;
      if (previous != null && !_samePrivatePath(previous, canonical)) {
        throw const AndroidActivityException('private_outbox_root_invalid');
      }
      _canonicalOutboxRootPath = canonical;
      return AndroidPrivateOutboxRoot(
        path: canonical,
        storageScope: 'no_backup_private',
      );
    } on FileSystemException {
      throw const AndroidActivityException('private_outbox_root_invalid');
    }
  }

  String _canonicalPrivateOutboxRoot(String nativePath) {
    final raw = _checkedPrivateAbsolutePath(nativePath);
    final parts = raw.split('/');
    if (parts.length < 4 ||
        parts.last != 'mda2_activity' ||
        parts[parts.length - 2] != 'no_backup') {
      throw const AndroidActivityException('private_outbox_root_invalid');
    }
    final parent = parts.take(parts.length - 1).join('/');
    final appData = parts.take(parts.length - 2).join('/');
    final fs = _outboxFileSystem;
    void requireDirectory(String path) {
      if (fs.typeWithoutFollowingLinks(path) !=
          FileSystemEntityType.directory) {
        throw const AndroidActivityException('private_outbox_root_invalid');
      }
    }

    // The native Context supplies this app-data boundary. Only its trusted
    // ancestors may have a different Dart spelling; never resolve an app-writable
    // no_backup/root link and then treat its destination as a trusted boundary.
    requireDirectory(appData);
    requireDirectory(parent);
    final canonicalApp = _checkedPrivateAbsolutePath(
      fs.resolveDirectory(appData),
    );
    final canonicalParent = _checkedPrivateAbsolutePath(
      fs.resolveDirectory(parent),
    );
    if (!_samePrivatePath(canonicalParent, '$canonicalApp/no_backup')) {
      throw const AndroidActivityException('private_outbox_root_invalid');
    }
    requireDirectory(canonicalApp);
    requireDirectory(canonicalParent);
    if (!_samePrivatePath(
      fs.resolveDirectory(canonicalParent),
      canonicalParent,
    )) {
      throw const AndroidActivityException('private_outbox_root_invalid');
    }
    final root = '$canonicalParent/mda2_activity';
    final rawType = fs.typeWithoutFollowingLinks(raw);
    final canonicalType = fs.typeWithoutFollowingLinks(root);
    if (rawType != canonicalType ||
        (rawType != FileSystemEntityType.notFound &&
            rawType != FileSystemEntityType.directory)) {
      throw const AndroidActivityException('private_outbox_root_invalid');
    }
    if (rawType == FileSystemEntityType.directory &&
        (!_samePrivatePath(fs.resolveDirectory(raw), root) ||
            !_samePrivatePath(fs.resolveDirectory(root), root))) {
      throw const AndroidActivityException('private_outbox_root_invalid');
    }
    // Recheck the writable boundary after resolving; subsequent source/file
    // checks and the broker-before-gate contract remain with their existing owners.
    requireDirectory(parent);
    requireDirectory(canonicalParent);
    return RegExp(r'^[A-Za-z]:/').hasMatch(root)
        ? root.replaceAll('/', r'\')
        : root;
  }

  @override
  Future<AndroidNativeActivation> activate({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
  }) async {
    final response = await _invokeMap('activate', {
      'enabled': enabled,
      'integrity_authority_ready': integrityAuthorityReady,
      'bound_sources': boundSources.map((source) => source.wireValue).toList(),
      'category_mapping': categoryMapping,
    });
    final active = response['enabled'];
    final readiness = response['readiness'];
    if (active is! bool || readiness is! String) {
      throw const AndroidActivityException('native_readiness_invalid');
    }
    return AndroidNativeActivation(enabled: active, readiness: readiness);
  }

  @override
  Future<AndroidNativeObservationStatus> getObservationStatus() async =>
      _parseObservationStatus(await _invokeMap('getObservationStatus'));

  @override
  Future<AndroidNativeActivation> activateObservation({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
    required Map<AndroidActivitySource, ActivityOutboxProcessLease> leases,
  }) async {
    if (leases.length != AndroidActivitySource.values.length ||
        leases.keys.any(
          (source) => leases[source]?.source != source.wireValue,
        ) ||
        leases.values.any(
          (lease) =>
              lease is! _MethodChannelActivityOutboxProcessLease ||
              !lease.isHeld ||
              !lease.hasFileClaim,
        )) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    final response = await _invokeMap('activateObservation', {
      'enabled': enabled,
      'integrity_authority_ready': integrityAuthorityReady,
      'bound_sources': boundSources.map((source) => source.wireValue).toList(),
      'category_mapping': categoryMapping,
      'lease_tokens': {
        for (final source in AndroidActivitySource.values)
          source.wireValue:
              (leases[source]! as _MethodChannelActivityOutboxProcessLease)
                  .token,
      },
    });
    _exactKeys(response, const {
      'enabled',
      'readiness',
      'usage_source',
      'screen_source',
      'usage_permission',
      'counters',
      'observation_status',
    });
    if (response['usage_source'] !=
            AndroidActivitySource.usageEvents.wireValue ||
        response['screen_source'] !=
            AndroidActivitySource.screenState.wireValue ||
        !const {
          'granted',
          'denied',
          'revoked',
        }.contains(response['usage_permission'])) {
      throw const AndroidActivityException('native_readiness_invalid');
    }
    _parseCounters(response['counters']);
    final active = response['enabled'];
    final readiness = response['readiness'];
    final rawStatus = response['observation_status'];
    if (active is! bool ||
        readiness is! String ||
        (rawStatus != null && rawStatus is! Map)) {
      throw const AndroidActivityException('native_readiness_invalid');
    }
    final status = rawStatus == null
        ? null
        : _parseObservationStatus(Map<String, Object?>.from(rawStatus as Map));
    if ((status == null && active) ||
        (status != null && status.enabled != active)) {
      throw const AndroidActivityException('native_readiness_invalid');
    }
    return AndroidNativeActivation(
      enabled: active,
      readiness: readiness,
      observationStatus: status,
    );
  }

  @override
  Future<bool> debugInvalidateObservationNotification(
    AndroidNativeObservationStatus target,
  ) async {
    if (!kDebugMode) {
      throw const AndroidActivityException('debug_diagnostic_required');
    }
    final response = await _invokeMap(
      'debugInvalidateObservationNotification',
      {'session_id': target.sessionId, 'observation_id': target.observationId},
    );
    _exactKeys(response, const {'accepted'});
    if (response['accepted'] is! bool) {
      throw const AndroidActivityException('observation_status_invalid');
    }
    return response['accepted'] as bool;
  }

  @override
  Future<AndroidNativeStopObservationResult> stopObservation(
    AndroidNativeObservationStatus target,
  ) async {
    final response = await _invokeMap('stopObservation', {
      'session_id': target.sessionId,
      'observation_id': target.observationId,
    });
    _exactKeys(response, const {'outcome', 'status'});
    final outcome = switch (response['outcome']) {
      'stopped' => AndroidNativeStopOutcome.stopped,
      'target_changed' => AndroidNativeStopOutcome.targetChanged,
      'unknown' => AndroidNativeStopOutcome.unknown,
      'failed' => AndroidNativeStopOutcome.failed,
      _ => throw const AndroidActivityException('observation_stop_failed'),
    };
    final rawStatus = response['status'];
    if (rawStatus is! Map) {
      throw const AndroidActivityException('observation_stop_failed');
    }
    return AndroidNativeStopObservationResult(
      outcome: outcome,
      status: _parseObservationStatus(Map<String, Object?>.from(rawStatus)),
    );
  }

  @override
  Future<ActivityOutboxProcessLease> acquireDiagnosticOutboxLease(
    AndroidActivitySource source, {
    String permitToken = '',
  }) async {
    final response = await _invokeMap('acquireDiagnosticOutboxLease', {
      'source': source.wireValue,
      'permit_token': permitToken,
    });
    _exactKeys(response, const {'source', 'lease_token'});
    final responseSource = response['source'];
    final token = response['lease_token'];
    if (responseSource != source.wireValue ||
        token is! String ||
        token.isEmpty) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    return _MethodChannelActivityOutboxProcessLease(source.wireValue, token);
  }

  @override
  Future<bool> releaseDiagnosticOutboxLease(
    ActivityOutboxProcessLease lease,
  ) async {
    if (lease is! _MethodChannelActivityOutboxProcessLease) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    if (!lease.isHeld || lease.hasFileClaim) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    final response = await _invokeMap('releaseDiagnosticOutboxLease', {
      'source': lease.source,
      'lease_token': lease.token,
    });
    _exactKeys(response, const {'released'});
    if (response['released'] is! bool) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    final released = response['released'] as bool;
    if (released) lease.markReleased();
    return released;
  }

  @override
  Future<AndroidDiagnosticOwnerReleasePermit> beginDiagnosticOwnerRelease(
    AndroidNativeObservationStatus target,
  ) async {
    final response = await _invokeMap('beginDiagnosticOwnerRelease', {
      'session_id': target.sessionId,
      'observation_id': target.observationId,
    });
    _exactKeys(response, const {'permit_token', 'status'});
    final token = response['permit_token'];
    final rawStatus = response['status'];
    if (token is! String || token.isEmpty || rawStatus is! Map) {
      throw const AndroidActivityException('diagnostic_owner_release_refused');
    }
    final status = _parseObservationStatus(
      Map<String, Object?>.from(rawStatus),
    );
    if (!status.matches(target) ||
        status.state != AndroidNativeObservationState.stopped ||
        status.enabled) {
      throw const AndroidActivityException('diagnostic_owner_release_refused');
    }
    return AndroidDiagnosticOwnerReleasePermit(token: token, status: status);
  }

  @override
  Future<bool> endDiagnosticOwnerRelease(
    AndroidDiagnosticOwnerReleasePermit permit,
  ) async {
    final response = await _invokeMap('endDiagnosticOwnerRelease', {
      'permit_token': permit.token,
    });
    _exactKeys(response, const {'released'});
    if (response['released'] is! bool) {
      throw const AndroidActivityException('diagnostic_owner_release_refused');
    }
    return response['released'] as bool;
  }

  @override
  Future<AndroidNativeUsageBatch> queryUsageEvents({
    required int startMs,
    required int endMs,
  }) async {
    final response = await _invokeMap('queryUsageEvents', {
      'start_ms': startMs,
      'end_ms': endMs,
    });
    return _parseBatch(response);
  }

  AndroidNativeUsageBatch _parseBatch(Map<String, Object?> response) {
    final delivery = response.containsKey('delivery_epoch');
    _exactKeys(response, {
      if (delivery) ...{'delivery_epoch', 'delivery_id'},
      'source',
      'permission',
      'readiness',
      'signals',
      'screen_signals',
      'query_started_at_ms',
      'query_finished_at_ms',
      'native_received_at_ms',
      'counters',
      'observation_status',
    });
    if (delivery &&
        (response['delivery_epoch'] is! String ||
            response['delivery_id'] is! String ||
            (response['delivery_epoch'] == '') !=
                (response['delivery_id'] == ''))) {
      throw const AndroidActivityException('native_delivery_invalid');
    }
    if (response['source'] != AndroidActivitySource.usageEvents.wireValue) {
      throw const AndroidActivityException('native_source_invalid');
    }
    final permission = switch (response['permission']) {
      'granted' => UsageAccess.granted,
      'denied' => UsageAccess.denied,
      'revoked' => UsageAccess.revoked,
      _ => throw const AndroidActivityException('native_permission_invalid'),
    };
    final readiness = response['readiness'];
    final rawSignals = response['signals'];
    final rawScreenSignals = response['screen_signals'];
    final queryStartedAtMs = response['query_started_at_ms'];
    final queryFinishedAtMs = response['query_finished_at_ms'];
    final nativeReceivedAtMs = response['native_received_at_ms'];
    final rawCounters = response['counters'];
    final rawObservationStatus = response['observation_status'];
    if (readiness is! String ||
        rawSignals is! List ||
        rawScreenSignals is! List ||
        queryStartedAtMs is! int ||
        queryFinishedAtMs is! int ||
        nativeReceivedAtMs is! int ||
        rawCounters is! Map ||
        rawObservationStatus is! Map ||
        queryStartedAtMs < 0 ||
        queryFinishedAtMs < queryStartedAtMs ||
        nativeReceivedAtMs < queryFinishedAtMs) {
      throw const AndroidActivityException('native_usage_result_invalid');
    }
    final counters = _parseCounters(rawCounters);
    return AndroidNativeUsageBatch(
      permission: permission,
      readiness: readiness,
      deliveryEpoch: response['delivery_epoch'] as String? ?? '',
      deliveryId: response['delivery_id'] as String? ?? '',
      signals: rawSignals.map(_privacyReducedSignal).toList(growable: false),
      screenSignals: rawScreenSignals
          .map(_privacyReducedSignal)
          .toList(growable: false),
      queryStartedAtMs: queryStartedAtMs,
      queryFinishedAtMs: queryFinishedAtMs,
      nativeReceivedAtMs: nativeReceivedAtMs,
      dartIngestAtMs: DateTime.now().millisecondsSinceEpoch,
      counters: Map.unmodifiable(counters),
      observationStatus: _parseObservationStatus(
        Map<String, Object?>.from(rawObservationStatus),
      ),
    );
  }

  Map<String, int> _parseCounters(Object? rawCounters) {
    if (rawCounters is! Map) {
      throw const AndroidActivityException('native_usage_result_invalid');
    }
    final counters = <String, int>{};
    for (final entry in rawCounters.entries) {
      if (entry.key is! String || entry.value is! int) {
        throw const AndroidActivityException('native_usage_result_invalid');
      }
      final key = entry.key as String;
      final value = entry.value as int;
      if (!const {
            'query_failures',
            'dropped_events',
            'bridge_disconnects',
            'bridge_failures',
            'expired_before_acceptance',
            'overflow_batches',
            'abandoned_events',
            'terminal_rejections',
          }.contains(key) ||
          value < 0) {
        throw const AndroidActivityException('native_usage_result_invalid');
      }
      counters[key] = value;
    }
    return counters;
  }

  AndroidNativeObservationStatus _parseObservationStatus(
    Map<String, Object?> response,
  ) {
    _exactKeys(response, const {
      'version',
      'session_id',
      'observation_id',
      'revision',
      'state',
      'enabled',
      'reason',
    });
    final version = response['version'];
    final sessionId = response['session_id'];
    final observationId = response['observation_id'];
    final revision = response['revision'];
    final state = switch (response['state']) {
      'unknown' => AndroidNativeObservationState.unknown,
      'starting' => AndroidNativeObservationState.starting,
      'running' => AndroidNativeObservationState.running,
      'stopping' => AndroidNativeObservationState.stopping,
      'stopped' => AndroidNativeObservationState.stopped,
      _ => throw const AndroidActivityException('observation_status_invalid'),
    };
    final enabled = response['enabled'];
    final reason = response['reason'];
    if (version is! int ||
        version != 1 ||
        sessionId is! String ||
        sessionId.isEmpty ||
        observationId is! String ||
        revision is! int ||
        revision < 0 ||
        revision > 9007199254740991 ||
        enabled is! bool ||
        reason is! String ||
        !_observationReasons.contains(reason) ||
        (enabled != (state == AndroidNativeObservationState.running)) ||
        (observationId.isEmpty &&
            (state != AndroidNativeObservationState.unknown || enabled))) {
      throw const AndroidActivityException('observation_status_invalid');
    }
    return AndroidNativeObservationStatus(
      sessionId: sessionId,
      observationId: observationId,
      revision: revision,
      state: state,
      enabled: enabled,
      reason: reason,
    );
  }

  @override
  Future<void> deactivate() async {
    try {
      await _channel.invokeMethod<Object?>('deactivate');
    } on PlatformException catch (error) {
      throw AndroidActivityException(error.code);
    }
  }

  Future<Map<String, Object?>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      if (raw is! Map) {
        throw const AndroidActivityException('native_result_invalid');
      }
      return Map<String, Object?>.from(raw);
    } on PlatformException catch (error) {
      throw AndroidActivityException(error.code);
    }
  }
}

const Set<String> _observationReasons = {
  'activity_source_unavailable',
  'activity_starting',
  'ready',
  'collector_disabled',
  'user_stop',
  'notification_stop',
  'service_destroyed',
  'foreground_start_not_allowed',
  'foreground_start_failed',
  'foreground_state_lost',
  'notification_not_visible',
  'appops_watcher_unavailable',
  'boot_marker_unavailable',
  'boot_marker_changed',
  'owner_fence_mismatch',
  'service_instance_mismatch',
  'usage_permission_denied',
  'usage_permission_revoked',
  'activity_opt_in_required',
  'debug_diagnostic_required',
  'activity_authority_invalid',
  'epoch_state_corrupt',
  'epoch_state_write_failed',
  'device_locked',
  'usage_events_expired',
  'usage_query_failed',
  'usage_query_null',
  'observation_stop_failed',
};

Map<String, Object?> _privacyReducedSignal(Object? raw) {
  if (raw is! Map) {
    throw const AndroidActivityException('native_signal_invalid');
  }
  final signal = Map<String, Object?>.from(raw);
  final usage = signal['type'] == 'usage_category';
  if (!usage &&
      !const {
        'screen_interactive',
        'screen_non_interactive',
        'user_present',
      }.contains(signal['type'])) {
    throw const AndroidActivityException('native_signal_invalid');
  }
  _exactKeys(
    signal,
    usage
        ? const {'type', 'signal_at_ms', 'category'}
        : const {'type', 'signal_at_ms'},
  );
  if (signal['signal_at_ms'] is! int ||
      (usage && signal['category'] is! String)) {
    throw const AndroidActivityException('native_signal_invalid');
  }
  return signal;
}

void _exactKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.length != expected.length ||
      value.keys.any((key) => !expected.contains(key))) {
    throw const AndroidActivityException('native_result_invalid');
  }
}

String _checkedPrivateAbsolutePath(String value) {
  final windows = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  final normalized = windows ? value.replaceAll(r'\', '/') : value;
  final parts = normalized.split('/');
  if (value.contains('\u0000') ||
      (!windows && (!value.startsWith('/') || value.contains(r'\'))) ||
      parts.length < 2 ||
      parts
          .skip(1)
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const AndroidActivityException('private_outbox_root_invalid');
  }
  return normalized;
}

bool _samePrivatePath(String left, String right) {
  final a = _checkedPrivateAbsolutePath(left);
  final b = _checkedPrivateAbsolutePath(right);
  return RegExp(r'^[A-Za-z]:/').hasMatch(a)
      ? a.toLowerCase() == b.toLowerCase()
      : a == b;
}
