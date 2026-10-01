import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/activity_integrity_key_repository.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/activity_outbox_process_lease.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_signal_platform.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/file_activity_outbox_store.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/ui/a3d_device_gate/a3d_device_gate_controller.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/ui/a3d_device_gate/a3d_device_gate_screen.dart';
import 'a3f_r3_owner_release_test.dart' show TestProcessLease;

Matcher hasCode(String code) =>
    isA<AndroidActivityException>().having((error) => error.code, 'code', code);

final class _MemoryIntegrityStorage implements ActivityIntegrityStorage {
  String? value;
  var reads = 0;
  var writes = 0;
  var deletes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String key, String newValue) async {
    writes++;
    value = newValue;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    value = null;
  }
}

final class _FakeActivitySignalPlatform
    implements
        AndroidActivitySignalPlatform,
        AndroidActivityDeliveryPlatform,
        AndroidActivityObservationPlatform,
        AndroidActivityOutboxLeasePlatform {
  _FakeActivitySignalPlatform(this.root);

  AndroidNativeBatchHandler? batchHandler;
  bool failAck = false;
  @override
  void setBatchHandler(AndroidNativeBatchHandler? handler) => batchHandler =
      handler == null ? null : (batch) => handler(_withStatus(batch));
  @override
  Future<void> acknowledgeBatch(
    AndroidNativeUsageBatch batch,
    List<String> outcomes,
  ) async {
    if (failAck) throw const AndroidActivityException('delivery_ack_rejected');
  }

  AndroidPrivateOutboxRoot root;
  AndroidActivityException? rootError;
  AndroidNativeSignalHandler? handler;
  AndroidNativeUsageBatch batch = const AndroidNativeUsageBatch(
    permission: UsageAccess.denied,
    readiness: 'usage_permission_denied',
    signals: [],
    counters: {'query_failures': 0, 'dropped_events': 0},
  );
  var rootCalls = 0;
  var activationCalls = 0;
  var queryCalls = 0;
  var deactivationCalls = 0;
  var statusReads = 0;
  var generation = 0;
  Completer<AndroidNativeObservationStatus>? blockedStatus;
  Future<void> Function(AndroidNativeObservationStatus)? observationHandler;
  AndroidNativeObservationStatus nativeStatus =
      const AndroidNativeObservationStatus(
    sessionId: 'test-session',
    observationId: '',
    revision: 0,
    state: AndroidNativeObservationState.unknown,
    enabled: false,
    reason: 'activity_source_unavailable',
  );
  final Map<AndroidActivitySource, TestProcessLease> leases = {};
  AndroidDiagnosticOwnerReleasePermit? permit;
  AndroidDiagnosticOwnerReleasePermit? lastEndedPermit;
  bool loseEndReplyOnce = false;
  int permitsIssued = 0;
  Completer<bool>? hangNextRelease;
  Completer<bool>? hangNextEnd;
  Completer<ActivityOutboxProcessLease>? hangNextAcquire;
  Completer<AndroidDiagnosticOwnerReleasePermit>? hangNextBegin;
  AndroidActivitySource? failReleaseOnceSource;
  void Function()? beforeNextUsageClaim;

  @override
  Future<bool> debugInvalidateObservationNotification(
    AndroidNativeObservationStatus target,
  ) async =>
      nativeStatus.matches(target) &&
      nativeStatus.state == AndroidNativeObservationState.running;

  @override
  void setObservationStatusHandler(
    Future<void> Function(AndroidNativeObservationStatus)? handler,
  ) =>
      observationHandler = handler;
  @override
  Future<AndroidNativeObservationStatus> getObservationStatus() async {
    statusReads++;
    return blockedStatus == null ? nativeStatus : blockedStatus!.future;
  }

  @override
  Future<AndroidNativeActivation> activateObservation({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
    required Map<AndroidActivitySource, ActivityOutboxProcessLease> leases,
  }) async {
    if (permit != null) {
      throw const AndroidActivityException('diagnostic_owner_release_active');
    }
    activationCalls++;
    generation++;
    nativeStatus = AndroidNativeObservationStatus(
      sessionId: 'test-session',
      observationId: 'observation-$generation',
      revision: nativeStatus.revision + 1,
      state: AndroidNativeObservationState.running,
      enabled: true,
      reason: 'ready',
    );
    return AndroidNativeActivation(
      enabled: true,
      readiness: 'ready',
      observationStatus: nativeStatus,
    );
  }

  @override
  Future<AndroidNativeStopObservationResult> stopObservation(
    AndroidNativeObservationStatus target,
  ) async {
    if (!nativeStatus.matches(target)) {
      return AndroidNativeStopObservationResult(
        outcome: AndroidNativeStopOutcome.targetChanged,
        status: nativeStatus,
      );
    }
    deactivationCalls++;
    await externalStop(push: false);
    return AndroidNativeStopObservationResult(
      outcome: AndroidNativeStopOutcome.stopped,
      status: nativeStatus,
    );
  }

  Future<void> externalStop({bool push = true}) async {
    nativeStatus = AndroidNativeObservationStatus(
      sessionId: nativeStatus.sessionId,
      observationId: nativeStatus.observationId,
      revision: nativeStatus.revision + 1,
      state: AndroidNativeObservationState.stopped,
      enabled: false,
      reason: 'notification_stop',
    );
    if (push) await observationHandler?.call(nativeStatus);
  }

  @override
  Future<ActivityOutboxProcessLease> acquireDiagnosticOutboxLease(
    AndroidActivitySource source, {
    String permitToken = '',
  }) async {
    if (leases[source]?.isHeld ?? false) {
      throw const AndroidActivityException('diagnostic_outbox_lease_held');
    }
    if ((permit != null && permitToken != permit!.token) ||
        (permit == null && permitToken.isNotEmpty)) {
      throw const AndroidActivityException('diagnostic_owner_release_active');
    }
    final lease = TestProcessLease(source.wireValue,
        beforeClaim: source == AndroidActivitySource.usageEvents
            ? beforeNextUsageClaim
            : null);
    if (source == AndroidActivitySource.usageEvents) {
      beforeNextUsageClaim = null;
    }
    leases[source] = lease;
    final pending = hangNextAcquire;
    hangNextAcquire = null;
    if (pending != null) return pending.future;
    return lease;
  }

  @override
  Future<bool> releaseDiagnosticOutboxLease(
    ActivityOutboxProcessLease lease,
  ) async {
    if (lease.hasFileClaim) {
      throw const AndroidActivityException('diagnostic_outbox_lease_held');
    }
    final pending = hangNextRelease;
    hangNextRelease = null;
    if (pending != null && !await pending.future) return false;
    if (failReleaseOnceSource?.wireValue == lease.source) {
      failReleaseOnceSource = null;
      return false;
    }
    (lease as TestProcessLease).isHeld = false;
    return true;
  }

  @override
  Future<AndroidDiagnosticOwnerReleasePermit> beginDiagnosticOwnerRelease(
    AndroidNativeObservationStatus target,
  ) async {
    if (!nativeStatus.matches(target) ||
        nativeStatus.state != AndroidNativeObservationState.stopped ||
        leases.values.any((lease) => lease.isHeld) ||
        permit != null) {
      throw const AndroidActivityException('diagnostic_owner_release_refused');
    }
    final issued = permit = AndroidDiagnosticOwnerReleasePermit(
      token: 'test-permit-${++permitsIssued}',
      status: nativeStatus,
    );
    final pending = hangNextBegin;
    hangNextBegin = null;
    return pending == null ? issued : pending.future;
  }

  @override
  Future<bool> endDiagnosticOwnerRelease(
    AndroidDiagnosticOwnerReleasePermit value,
  ) async {
    if (permit == null && identical(lastEndedPermit, value)) return true;
    if (!identical(permit, value) ||
        leases.values.any((lease) => lease.isHeld)) {
      return false;
    }
    lastEndedPermit = permit;
    permit = null;
    final pending = hangNextEnd;
    hangNextEnd = null;
    if (pending != null) return pending.future;
    if (loseEndReplyOnce) {
      loseEndReplyOnce = false;
      throw const AndroidActivityException('diagnostic_owner_release_refused');
    }
    return true;
  }

  AndroidNativeUsageBatch _withStatus(AndroidNativeUsageBatch value) =>
      AndroidNativeUsageBatch(
        permission: value.permission,
        readiness: value.readiness,
        signals: value.signals,
        screenSignals: value.screenSignals,
        deliveryEpoch: value.deliveryEpoch,
        deliveryId: value.deliveryId,
        counters: value.counters,
        queryStartedAtMs: value.queryStartedAtMs,
        queryFinishedAtMs: value.queryFinishedAtMs,
        nativeReceivedAtMs: value.nativeReceivedAtMs,
        dartIngestAtMs: value.dartIngestAtMs,
        observationStatus: value.observationStatus ?? nativeStatus,
      );

  @override
  void setSignalHandler(AndroidNativeSignalHandler? value) => handler = value;

  @override
  Future<AndroidPrivateOutboxRoot> getOutboxRoot() async {
    rootCalls++;
    final failure = rootError;
    if (failure != null) throw failure;
    return root;
  }

  @override
  Future<AndroidNativeActivation> activate({
    required bool enabled,
    required bool integrityAuthorityReady,
    required Set<AndroidActivitySource> boundSources,
    required Map<String, String> categoryMapping,
  }) async {
    activationCalls++;
    return const AndroidNativeActivation(enabled: true, readiness: 'ready');
  }

  @override
  Future<AndroidNativeUsageBatch> queryUsageEvents({
    required int startMs,
    required int endMs,
  }) async {
    queryCalls++;
    return _withStatus(batch);
  }

  @override
  Future<void> deactivate() async {
    deactivationCalls++;
  }

  Future<void> emit(Map<String, Object?> signal) async {
    await batchHandler?.call(AndroidNativeUsageBatch(
      permission: UsageAccess.granted,
      readiness: 'ready',
      signals: const [],
      screenSignals: [signal],
      counters: const {},
      observationStatus: nativeStatus,
    ));
  }
}

final class _Rig {
  int now = 1000000;
  late final Directory scratch;
  late final Directory root;
  late final _MemoryIntegrityStorage storage;
  late final ActivityIntegrityKeyRepository keys;
  late final _FakeActivitySignalPlatform platform;
  late final A3dDeviceGateController controller;

  Future<void> initialize() async {
    scratch = await Directory.systemTemp.createTemp('mda2_a3d_gate_');
    root = Directory(
      '${scratch.path}${Platform.pathSeparator}no_backup'
      '${Platform.pathSeparator}mda2_activity',
    );
    storage = _MemoryIntegrityStorage();
    keys = ActivityIntegrityKeyRepository(
      storage: storage,
      randomBytes: (length) => List<int>.generate(length, (index) => index),
    );
    platform = _FakeActivitySignalPlatform(
      AndroidPrivateOutboxRoot(
        path: root.path,
        storageScope: 'no_backup_private',
      ),
    );
    controller = A3dDeviceGateController(
      keyRepository: keys,
      platform: platform,
      clockMs: () => now,
      categoryMapping: const {'local.diagnostic.target': 'other'},
    );
  }

  Future<void> dispose() async {
    if (controller.hasCollectorResources) await controller.stop();
    controller.dispose();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  }
}

Future<void> _expectActionSurvivesReadOnlySync(
    _Rig rig, A3dResourceAction action, String code) async {
  final result = rig.controller.lastResourceActionResult;
  expect(result?.action, action);
  expect(result?.code, code);
  final files = <String, List<int>>{
    if (rig.root.existsSync())
      for (final file in rig.root.listSync(recursive: true).whereType<File>())
        if (!file.path.endsWith('owner.gate')) file.path: file.readAsBytesSync(),
  };
  final leases = {
    for (final lease in rig.platform.leases.values)
      lease: (lease.isHeld, lease.hasFileClaim, lease.claims),
  };
  final starts = rig.platform.activationCalls;
  final stops = rig.platform.deactivationCalls;
  final queries = rig.platform.queryCalls;
  final permits = rig.platform.permitsIssued;
  final reads = rig.platform.statusReads;
  void check() {
    expect(identical(rig.controller.lastResourceActionResult, result), isTrue);
    expect(rig.controller.active, isFalse);
    expect(rig.controller.canQuery, isFalse);
    expect(rig.platform.activationCalls, starts);
    expect(rig.platform.deactivationCalls, stops);
    expect(rig.platform.queryCalls, queries);
    expect(rig.platform.permitsIssued, permits);
    for (final entry in leases.entries) {
      final lease = entry.key;
      expect((lease.isHeld, lease.hasFileClaim, lease.claims), entry.value);
    }
    for (final entry in files.entries) {
      expect(File(entry.key).readAsBytesSync(), entry.value);
    }
  }

  rig.controller.setForeground(true);
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  expect(rig.platform.statusReads, greaterThanOrEqualTo(reads + 2));
  check();
  await rig.controller.refreshEvidence();
  check();
  rig.controller.setForeground(false);
  rig.controller.setForeground(true);
  await Future<void>.delayed(Duration.zero);
  check();
  rig.controller.setForeground(false);
}

Map<String, Object?> _validWire({
  AndroidActivitySource source = AndroidActivitySource.usageEvents,
  String? kind,
  Map<String, Object?>? payload,
}) =>
    {
      'contract': 'device.activity.v1',
      'schema_version': 1,
      'event_id': 'A3DLOCALUSAGE0000000001.1',
      'device_id': 'a3d-local-diagnostic',
      'probe_id': 'a3d-usage-local',
      'origin_sequence': 1,
      'kind': kind ?? 'app.category_active',
      'signal_at_ms': 1000000,
      'ttl_ms': 300000,
      'confidence': 'medium',
      'source': source.wireValue,
      'coverage': {
        'mode': 'discrete_best_effort',
        'window_start_ms': 1000000,
        'window_end_ms': 1000000,
        'expected_report_interval_ms': 30000,
      },
      'payload': payload ?? {'category': 'other'},
    };

void main() {
  test(
      'initialize without an acquire reply returns unknown and preserves explicit stop ownership',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final pending = Completer<ActivityOutboxProcessLease>();
    rig.platform.hangNextAcquire = pending;
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.readiness, 'diagnostic_status_unknown');
    expect(rig.controller.hasCollectorResources, isTrue);
    expect(rig.platform.activationCalls, 0);
    final writes = rig.storage.writes;
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    expect(rig.storage.writes, writes);
    final stopping = rig.controller.stop();
    pending.complete(rig.platform.leases[AndroidActivitySource.usageEvents]!);
    await stopping;
    expect(rig.controller.active, isFalse);
    expect(rig.platform.activationCalls, 0);
  });

  test(
      'unknown begin token keeps its pending Future until the original permit arrives',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.platform.externalStop();
    await rig.controller.debugFailUsageOwnerDeletion();
    final pending = Completer<AndroidDiagnosticOwnerReleasePermit>();
    rig.platform.hangNextBegin = pending;
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.readiness, 'diagnostic_owner_release_partial');
    expect(rig.platform.permitsIssued, 1);
    final issued = rig.platform.permit!;
    await _expectActionSurvivesReadOnlySync(rig,
        A3dResourceAction.releaseOrphanOwners, 'diagnostic_owner_release_partial');
    pending.complete(issued);
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.readiness, 'diagnostic_owner_release_complete');
    expect(rig.controller.lastResourceActionResult?.code,
        'diagnostic_owner_release_complete');
    expect(rig.platform.lastEndedPermit, isNotNull);
    expect(rig.platform.permitsIssued, 2);
  });

  for (final hangEnd in [false, true]) {
    test(
        'pending known ${hangEnd ? 'end' : 'release'} stops waiting and exact-token retry completes',
        () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
      await rig.platform.externalStop();
      await rig.controller.debugFailUsageOwnerDeletion();
      final never = Completer<bool>();
      if (hangEnd) {
        rig.platform.hangNextEnd = never;
      } else {
        rig.platform.hangNextRelease = never;
      }
      await rig.controller.releaseOrphanOwners();
      expect(rig.controller.busy, isFalse);
      expect(rig.controller.readiness, 'diagnostic_owner_release_partial');
      expect(never.isCompleted, isFalse);
      await rig.controller.releaseOrphanOwners();
      expect(rig.controller.busy, isFalse);
      expect(rig.controller.readiness, 'diagnostic_owner_release_complete');
      final completedAction = rig.controller.lastResourceActionResult;
      expect(completedAction?.code, 'diagnostic_owner_release_complete');
      never.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(identical(rig.controller.lastResourceActionResult, completedAction),
          isTrue);
      expect(
          rig.platform.leases.values.every((lease) => !lease.isHeld), isTrue);
    });
  }

  test(
      'unknown acquire token remains on the original Future and late identity is resumed',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.platform.externalStop();
    await rig.controller.debugFailUsageOwnerDeletion();
    final pending = Completer<ActivityOutboxProcessLease>();
    rig.platform.hangNextAcquire = pending;
    await rig.controller.releaseOrphanOwners();
    final originalLease =
        rig.platform.leases[AndroidActivitySource.usageEvents]!;
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.readiness, 'diagnostic_owner_release_partial');
    expect(originalLease.isHeld, isTrue);
    expect(originalLease.claims, 0);
    expect(rig.platform.permitsIssued, 1);
    final owner = File(
        '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}/owner.json');
    expect(owner.existsSync(), isTrue);
    pending.complete(originalLease);
    await rig.controller.releaseOrphanOwners();
    expect(originalLease.isHeld, isFalse);
    expect(
        identical(rig.platform.leases[AndroidActivitySource.usageEvents],
            originalLease),
        isFalse);
    expect(owner.existsSync(), isFalse);
    expect(rig.controller.readiness, 'diagnostic_owner_release_complete');
  });

  test(
      'reset with a pending known release returns and explicit retry reconciles it',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.controller.stop();
    final never = Completer<bool>();
    rig.platform.hangNextRelease = never;
    await rig.controller.resetDiagnosticOutbox();
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.readiness, 'diagnostic_reset_refused');
    await _expectActionSurvivesReadOnlySync(
        rig, A3dResourceAction.reset, 'diagnostic_reset_refused');
    await rig.controller.resetDiagnosticOutbox();
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.readiness, 'diagnostic_outbox_absent');
    expect(rig.controller.lastResourceActionResult?.code,
        'diagnostic_outbox_absent');
    never.complete(true);
  });

  test(
      'lost end reply retries the exact already-ended permit before acquiring again',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.platform.externalStop();
    await rig.controller.debugFailUsageOwnerDeletion();
    rig.platform.loseEndReplyOnce = true;
    await rig.controller.releaseOrphanOwners();
    expect(rig.platform.permit,
        isNull); // Native effect happened; only reply was lost.
    expect(rig.controller.readiness, 'diagnostic_owner_release_partial');
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.resourceReleaseSummary.join(), contains('恢复许可仍持有'));
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.readiness, 'diagnostic_owner_release_complete');
    expect(rig.platform.permitsIssued, 2);
    expect(rig.controller.resourceReleaseSummary.join(),
        isNot(contains('恢复许可仍持有')));
    expect(rig.platform.activationCalls, 1);
  });

  test(
      'partial recovery retry detects a successor even for an already released source',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.platform.externalStop();
    await rig.controller.debugFailUsageOwnerDeletion();
    rig.platform.failReleaseOnceSource = AndroidActivitySource.usageEvents;
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.readiness, 'diagnostic_owner_release_partial');
    expect(rig.platform.permit, isNotNull);
    final directory = Directory(
        '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}');
    final key = await rig.keys.readRequired();
    // Synthetic foreign writer: a valid successor after the original FD closed.
    final successor = FileActivityOutboxStore.open(
        directory: directory,
        binding: A3dDiagnosticBindingFactory.create(
            AndroidActivitySource.usageEvents),
        capacity: A3dDiagnosticBindingFactory.capacity,
        integrityKey: key,
        ageProofProvider: HmacActivityAgeProofProvider(integrityKey: key),
        clockMs: () => rig.now);
    successor.releaseProcessLeaseForTest();
    final owner = File('${directory.path}/owner.json');
    final bytes = owner.readAsBytesSync();
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.readiness, 'owner_release_target_changed');
    expect(owner.readAsBytesSync(), bytes);
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.hasCollectorResources, isTrue);
  });

  test('retry claim failure invalidates historical owner release proof', () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.platform.externalStop();
    await rig.controller.debugFailUsageOwnerDeletion();
    rig.platform.failReleaseOnceSource = AndroidActivitySource.usageEvents;
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.readiness, 'diagnostic_owner_release_partial');
    final directory = Directory(
        '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}');
    final owner = File('${directory.path}/owner.json');
    expect(owner.existsSync(), isFalse);
    final key = await rig.keys.readRequired();
    var claims = 0;
    late List<int> successorBytes;
    // This runs after both UI preflights, before the primitive opens a gate FD.
    rig.platform.beforeNextUsageClaim = () {
      claims++;
      final successor = FileActivityOutboxStore.open(
          directory: directory,
          binding: A3dDiagnosticBindingFactory.create(
              AndroidActivitySource.usageEvents),
          capacity: A3dDiagnosticBindingFactory.capacity,
          integrityKey: key,
          ageProofProvider: HmacActivityAgeProofProvider(integrityKey: key),
          clockMs: () => rig.now);
      successor.releaseProcessLeaseForTest();
      successorBytes = owner.readAsBytesSync();
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    };
    await rig.controller.releaseOrphanOwners();
    expect(claims, 1);
    expect(rig.controller.readiness, 'diagnostic_owner_release_partial');
    expect(rig.controller.busy, isFalse);
    expect(rig.controller.hasCollectorResources, isTrue);
    expect(rig.controller.resourceReleaseSummary.join(),
        contains('owner_lock_cleanup_failed'));
    expect(rig.controller.resourceReleaseSummary.join(),
        contains('diagnostic_outbox_lease_invalid'));
    expect(owner.readAsBytesSync(), successorBytes);
    await _expectActionSurvivesReadOnlySync(rig,
        A3dResourceAction.releaseOrphanOwners, 'diagnostic_owner_release_partial');
  });

  test(
      'terminal push clears ready without closing owners; explicit stop releases them',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    expect(rig.controller.active, isTrue);
    await rig.platform.externalStop();
    expect(rig.controller.active, isFalse);
    expect(rig.controller.nativeState, 'stopped');
    expect(rig.controller.hasCollectorResources, isTrue);
    expect(rig.platform.leases.values.every((lease) => lease.hasFileClaim),
        isTrue);
    final starts = rig.platform.activationCalls;
    await rig.controller.refreshEvidence();
    expect(rig.platform.activationCalls, starts);
    expect(rig.platform.queryCalls, 0);
    await rig.controller.stop();
    expect(rig.controller.hasCollectorResources, isFalse);
    expect(
        rig.platform.leases.values
            .every((lease) => !lease.isHeld && !lease.hasFileClaim),
        isTrue);
  });

  test(
      'refresh and query precheck discover a missed terminal push with no usage query',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.platform.externalStop(push: false);
    await rig.controller.pollUsage();
    expect(rig.controller.active, isFalse);
    expect(rig.platform.queryCalls, 0);
    expect(rig.controller.nativeState, 'stopped');
  });

  test(
      'three-second status timeout is unknown and old completion after stop cannot restore ready',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    final oldRunning = rig.platform.nativeStatus;
    final blocked = Completer<AndroidNativeObservationStatus>();
    rig.platform.blockedStatus = blocked;
    final refresh = rig.controller.refreshEvidence();
    expect(rig.controller.synchronization, A3dStatusSynchronization.checking);
    expect(rig.controller.active, isFalse);
    await refresh;
    expect(rig.controller.synchronization, A3dStatusSynchronization.unknown);
    expect(rig.controller.nativeState, 'unknown');
    await rig.controller.stop();
    blocked.complete(oldRunning);
    rig.platform.blockedStatus = null;
    await Future<void>.delayed(Duration.zero);
    expect(rig.controller.active, isFalse);
    expect(rig.controller.nativeState, 'stopped');
  });

  test('foreground read-only fallback discovers terminal state without a push',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    rig.controller.setForeground(true);
    await Future<void>.delayed(Duration.zero);
    await rig.platform.externalStop(push: false);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(rig.controller.active, isFalse);
    expect(rig.controller.nativeState, 'stopped');
    expect(rig.platform.queryCalls, 0);
    expect(rig.platform.activationCalls, 1);
    rig.controller.setForeground(false);
  });

  test(
      'H4 requires a separate explicit release and preserves state, sequence and key',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    final key = rig.storage.value;
    await rig.platform.externalStop();
    await rig.controller.debugFailUsageOwnerDeletion();
    expect(rig.controller.hasCollectorResources, isTrue);
    expect(rig.controller.resourceReleaseSummary.join(),
        contains('owner_lock_cleanup_failed'));
    final owner = File(
        '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}/owner.json');
    expect(owner.existsSync(), isTrue);
    final persistent = <String, List<int>>{
      for (final entity in rig.root.listSync(recursive: true).whereType<File>())
        if (!entity.path.endsWith('owner.gate') &&
            !entity.path.endsWith('owner.json'))
          entity.path: entity.readAsBytesSync(),
    };
    await _expectActionSurvivesReadOnlySync(
        rig, A3dResourceAction.stop, 'observation_stop_failed');
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.lastResourceActionResult?.code,
        'diagnostic_owner_release_complete');
    expect(owner.existsSync(), isFalse);
    expect(rig.controller.hasCollectorResources, isFalse);
    expect(rig.storage.value, key);
    for (final entry in persistent.entries) {
      expect(File(entry.key).readAsBytesSync(), entry.value);
    }
    expect(rig.platform.activationCalls, 1);
    expect(rig.platform.queryCalls, 0);
    await rig.controller.refreshEvidence();
    expect(rig.platform.activationCalls, 1);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    expect(rig.controller.readiness, 'recovery_authority_required');
    expect(rig.controller.lastResourceActionResult, isNull);
  });

  test(
      'stopped service with live store leases refuses recovery before another file claim',
      () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    await rig.platform.externalStop();
    final claims =
        rig.platform.leases.values.map((lease) => lease.claims).toList();
    await rig.controller.releaseOrphanOwners();
    expect(rig.controller.readiness, 'diagnostic_owner_release_refused');
    expect(rig.platform.leases.values.map((lease) => lease.claims), claims);
    expect(rig.platform.leases.values.every((lease) => lease.hasFileClaim),
        isTrue);
    await _expectActionSurvivesReadOnlySync(rig,
        A3dResourceAction.releaseOrphanOwners, 'diagnostic_owner_release_refused');
    await rig.controller.stop();
    expect(rig.controller.lastResourceActionResult?.action,
        A3dResourceAction.stop);
    expect(rig.controller.lastResourceActionResult?.code, 'collector_disabled');
    await rig.controller.resetDiagnosticOutbox();
    expect(rig.controller.lastResourceActionResult?.code,
        'diagnostic_reset_complete');
    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
    expect(rig.controller.active, isTrue);
    expect(rig.controller.lastResourceActionResult, isNull);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'proactive durable batch then refresh without poll reads current evidence',
    () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
      rig.now += 10;
      await rig.platform.batchHandler!(
        AndroidNativeUsageBatch(
          permission: UsageAccess.granted,
          readiness: 'ready',
          signals: const [],
          screenSignals: [
            {'type': 'user_present', 'signal_at_ms': rig.now},
          ],
          deliveryEpoch: 'epoch-a',
          deliveryId: '1',
          counters: const {},
        ),
      );
      await rig.controller.refreshEvidence();
      final snapshot = rig.controller.evidence.value;
      expect((snapshot['sequence'] as Map)['screen'], 1);
      expect((snapshot['counts'] as Map)['user_present'], 1);
      expect((snapshot['readiness'] as Map)['screen'], 'fresh');
      expect(
        (snapshot['readiness'] as Map)['publication_completeness'],
        'unknown',
      );
      expect(rig.platform.queryCalls, 0);
      await rig.platform.batchHandler!(
        const AndroidNativeUsageBatch(
          permission: UsageAccess.granted,
          readiness: 'usage_query_empty_unproven',
          signals: [],
          counters: {'expired_before_acceptance': 1},
        ),
      );
      await rig.controller.refreshEvidence();
      expect(
        (rig.controller.evidence.value['readiness'] as Map)['collector'],
        'usage_query_empty_unproven',
      );
      expect(
        (rig.controller.evidence.value['counts']
            as Map)['native_expired_before_acceptance'],
        1,
      );
    },
  );

  test('default screen construction has zero diagnostic effects', () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);

    expect(rig.controller.consented, isFalse);
    expect(rig.controller.readiness, 'diagnostic_not_started');
    expect(rig.storage.reads, 0);
    expect(rig.storage.writes, 0);
    expect(rig.platform.rootCalls, 0);
    expect(rig.platform.activationCalls, 0);
    expect(rig.platform.queryCalls, 0);
    expect(rig.root.existsSync(), isFalse);
    expect(rig.controller.evidence.value['authority'], a3dDiagnosticAuthority);
  });

  for (final scenario in [
    A3dDiagnosticScenario.missingKey,
    A3dDiagnosticScenario.missingUsageBinding,
    A3dDiagnosticScenario.missingScreenBinding,
  ]) {
    test('$scenario rejects before native or outbox effects', () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);

      await rig.controller.beginDiagnostic(scenario);

      expect(rig.controller.active, isFalse);
      expect(
        rig.controller.readiness,
        scenario == A3dDiagnosticScenario.missingKey
            ? 'integrity_key_missing'
            : 'source_binding_missing',
      );
      expect(rig.storage.writes, 0);
      expect(rig.platform.rootCalls, 0);
      expect(rig.platform.activationCalls, 0);
      expect(rig.platform.queryCalls, 0);
      expect(rig.platform.deactivationCalls, 0);
      expect(rig.root.existsSync(), isFalse);
      final sequence =
          rig.controller.evidence.value['sequence']! as Map<String, Object?>;
      expect(sequence, {'usage': 0, 'screen': 0});
    });
  }

  test(
    'complete start provisions only after consent and does not query',
    () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);

      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);

      expect(rig.controller.consented, isTrue);
      expect(rig.controller.active, isTrue);
      expect(rig.controller.readiness, 'ready');
      expect(rig.storage.writes, 1);
      expect(rig.platform.rootCalls, 1);
      expect(rig.platform.activationCalls, 1);
      expect(rig.platform.queryCalls, 0);
      expect(rig.root.existsSync(), isTrue);
    },
  );

  test(
    'usage and three screen observations export only minimal evidence',
    () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);

      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: [
          {
            'type': 'usage_category',
            'signal_at_ms': rig.now,
            'category': 'other',
          },
        ],
        counters: const {'query_failures': 0, 'dropped_events': 0},
      );
      await rig.controller.pollUsage();
      for (final type in [
        'screen_interactive',
        'screen_non_interactive',
        'user_present',
      ]) {
        rig.now++;
        await rig.platform.emit({'type': type, 'signal_at_ms': rig.now});
      }
      await rig.controller.refreshEvidence();

      final encoded = rig.controller.evidence.encode();
      expect(encoded, contains('"category": "other"'));
      expect(encoded, contains('"screen_interactive": 1'));
      expect(encoded, contains('"screen_non_interactive": 1'));
      expect(encoded, contains('"user_present": 1'));
      expect(encoded, isNot(contains('local.diagnostic.target')));
      expect(encoded, isNot(contains('event_id')));
      expect(encoded, isNot(contains('device_id')));
      expect(encoded, isNot(contains('probe_id')));
      expect(encoded, isNot(contains('owner')));
      expect(encoded, isNot(contains(rig.root.path)));
    },
  );

  test(
    'revocation and explicit recheck preserve permission unknown-gap semantics',
    () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);

      rig.platform.batch = const AndroidNativeUsageBatch(
        permission: UsageAccess.revoked,
        readiness: 'usage_permission_revoked',
        signals: [],
        counters: {'query_failures': 0, 'dropped_events': 0},
      );
      await rig.controller.pollUsage();
      var readiness =
          rig.controller.evidence.value['readiness']! as Map<String, Object?>;
      expect(rig.controller.evidence.value['usage_permission'], 'revoked');
      expect(readiness['usage'], 'permission_unavailable');
      await rig.controller.refreshEvidence();
      expect(rig.controller.active, isFalse);
      expect(rig.controller.canQuery, isTrue);
      expect(rig.platform.queryCalls, 1);

      rig.now++;
      rig.platform.batch = const AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: [],
        counters: {'query_failures': 0, 'dropped_events': 0},
      );
      await rig.controller.pollUsage();
      readiness =
          rig.controller.evidence.value['readiness']! as Map<String, Object?>;
      expect(rig.controller.evidence.value['usage_permission'], 'granted');
      expect(readiness['usage'], 'recovery_pending');
      expect(rig.platform.queryCalls, 2);
    },
  );

  test(
    'existing state refuses activation query and sequence allocation',
    () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.keys.provision();
      final usage = Directory(
        '${rig.root.path}${Platform.pathSeparator}android_usage_events',
      )..createSync(recursive: true);
      File(
        '${usage.path}${Platform.pathSeparator}state.json',
      ).writeAsStringSync('existing');

      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);

      expect(rig.controller.readiness, 'recovery_authority_required');
      expect(rig.platform.activationCalls, 0);
      expect(rig.platform.queryCalls, 0);
      final sequence =
          rig.controller.evidence.value['sequence']! as Map<String, Object?>;
      expect(sequence, {'usage': 0, 'screen': 0});
    },
  );

  test('privacy-negative fields reject instead of being stripped', () {
    for (final key in [
      'packageName',
      'appName',
      'rawUsageEvents',
      'privatePath',
      'token',
      'exception',
    ]) {
      final wire = _validWire()..[key] = 'private value';
      expect(
        () => A3dEvidenceCodec.validateWireForEvidence(
          wire,
          AndroidActivitySource.usageEvents,
        ),
        throwsA(hasCode('diagnostic_evidence_invalid')),
      );
    }
    final payload = _validWire(
      payload: {'category': 'other', 'privatePath': 'private value'},
    );
    expect(
      () => A3dEvidenceCodec.validateWireForEvidence(
        payload,
        AndroidActivitySource.usageEvents,
      ),
      throwsA(hasCode('diagnostic_evidence_invalid')),
    );
    final coverage = _validWire();
    (coverage['coverage']! as Map)['token'] = 'private value';
    expect(
      () => A3dEvidenceCodec.validateWireForEvidence(
        coverage,
        AndroidActivitySource.usageEvents,
      ),
      throwsA(hasCode('diagnostic_evidence_invalid')),
    );
  });

  test('unknown platform exception code is not echoed', () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    rig.platform.rootError = const AndroidActivityException(
      'private path and exception body',
    );

    await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);

    expect(rig.controller.readiness, 'diagnostic_failed');
    expect(
      rig.controller.evidence.encode(),
      isNot(contains('private path and exception body')),
    );
  });

  test(
    'reset refuses while active then deletes only disposed diagnostic state',
    () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);

      await rig.controller.resetDiagnosticOutbox();
      expect(rig.controller.readiness, 'diagnostic_reset_requires_disposed');
      expect(rig.root.existsSync(), isTrue);

      await rig.controller.stop();
      final keyBefore = rig.storage.value;
      await rig.controller.resetDiagnosticOutbox();
      expect(rig.controller.readiness, 'diagnostic_reset_complete');
      final resetReadiness =
          rig.controller.evidence.value['readiness']! as Map<String, Object?>;
      expect(resetReadiness['collector'], 'diagnostic_reset_complete');
      expect(rig.root.existsSync(), isFalse);
      expect(rig.storage.value, keyBefore);
      expect(rig.storage.deletes, 0);
    },
  );

  test('reset rejects unknown child without deleting it', () async {
    final rig = _Rig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.keys.provision();
    final unrelated = File(
      '${rig.root.path}${Platform.pathSeparator}unrelated.txt',
    )..createSync(recursive: true);

    await rig.controller.resetDiagnosticOutbox();

    expect(rig.controller.readiness, 'diagnostic_reset_scope_invalid');
    expect(unrelated.existsSync(), isTrue);
  });

  test(
    'restart with stale owner fails closed until explicit verified reset',
    () async {
      final rig = _Rig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final key = await rig.keys.provision();
      for (final source in AndroidActivitySource.values) {
        final directory = Directory(
          '${rig.root.path}${Platform.pathSeparator}${source.wireValue}',
        );
        final store = FileActivityOutboxStore.create(
          directory: directory,
          binding: A3dDiagnosticBindingFactory.create(source),
          capacity: A3dDiagnosticBindingFactory.capacity,
          integrityKey: key,
          ageProofProvider: HmacActivityAgeProofProvider(integrityKey: key),
          clockMs: () => rig.now,
        );
        store.releaseProcessLeaseForTest();
      }

      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
      expect(rig.controller.readiness, 'recovery_authority_required');
      expect(rig.platform.activationCalls, 0);
      expect(rig.platform.queryCalls, 0);
      final readiness =
          rig.controller.evidence.value['readiness']! as Map<String, Object?>;
      expect(readiness['usage'], 'unknown');
      expect(readiness['screen'], 'unknown');

      await rig.controller.resetDiagnosticOutbox();
      expect(rig.controller.readiness, 'diagnostic_reset_complete');
      final resetReadiness =
          rig.controller.evidence.value['readiness']! as Map<String, Object?>;
      expect(resetReadiness['collector'], 'diagnostic_reset_complete');
      expect(rig.root.existsSync(), isFalse);
    },
  );

  testWidgets('resource action refusal stays visible after foreground tick',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rig = _Rig();
    await tester.runAsync(rig.initialize);
    addTearDown(rig.dispose);
    await tester.pumpWidget(A3dDeviceGateApp(controller: rig.controller));
    await tester.runAsync(() async {
      await rig.controller.beginDiagnostic(A3dDiagnosticScenario.complete);
      await rig.platform.externalStop();
      await rig.controller.releaseOrphanOwners();
    });
    await tester.pump();
    expect(find.textContaining('diagnostic_owner_release_refused'),
        findsAtLeastNWidgets(1));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('diagnostic_owner_release_refused'),
        findsAtLeastNWidgets(1));
    expect(find.textContaining('最近资源动作：无损释放孤立资源'), findsOneWidget);
    await tester.runAsync(rig.controller.refreshEvidence);
    await tester.pump();
    expect(find.byKey(const ValueKey('resource_action_result')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining('diagnostic_owner_release_refused'),
        findsAtLeastNWidgets(1));
    expect(rig.controller.active, isFalse);
    expect(rig.platform.activationCalls, 1);
    expect(rig.platform.queryCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('widget keeps start as the only initial collection action', (
    tester,
  ) async {
    final rig = _Rig();
    await tester.runAsync(rig.initialize);
    addTearDown(rig.dispose);
    await tester.pumpWidget(A3dDeviceGateApp(controller: rig.controller));

    expect(find.text('开始诊断'), findsOneWidget);
    expect(find.textContaining('synthetic/local diagnostic'), findsOneWidget);
    expect(rig.storage.writes, 0);
    expect(rig.platform.rootCalls, 0);
    expect(rig.platform.activationCalls, 0);

    final start = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start_diagnostic')),
    );
    final poll = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('poll_usage')),
    );
    final stop = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('stop_diagnostic')),
    );
    expect(start.onPressed, isNotNull);
    expect(poll.onPressed, isNull);
    expect(stop.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
