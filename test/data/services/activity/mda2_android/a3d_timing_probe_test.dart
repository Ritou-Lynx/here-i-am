import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: avoid_relative_lib_imports
import '../../../../../lib/a3d_device_gate_main.dart' as entry;

// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/activity_integrity_key_repository.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/activity_outbox_process_lease.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_collector.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_signal_platform.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/ui/a3d_device_gate/a3d_device_gate_controller.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/ui/a3d_device_gate/a3d_timing_probe.dart';
import 'a3f_r3_owner_release_test.dart' show TestProcessLease;
import 'android_activity_collector_test.dart' show MemoryIntegrityStorage;

AndroidNativeObservationStatus status({
  int revision = 1,
  AndroidNativeObservationState state = AndroidNativeObservationState.running,
  String session = 'never-export-session',
}) =>
    AndroidNativeObservationStatus(
      sessionId: session,
      observationId: 'never-export-observation',
      revision: revision,
      state: state,
      enabled: state == AndroidNativeObservationState.running,
      reason: state == AndroidNativeObservationState.running
          ? 'ready'
          : 'notification_stop',
    );

final class ProbePlatform
    implements
        AndroidActivitySignalPlatform,
        AndroidActivityObservationPlatform,
        AndroidActivityDeliveryPlatform,
        AndroidActivityOutboxLeasePlatform {
  AndroidPrivateOutboxRoot root = const AndroidPrivateOutboxRoot(
      path: '/unused', storageScope: 'no_backup_private');
  AndroidNativeObservationStatus current = status();
  AndroidNativeSignalHandler? signalHandler;
  AndroidNativeBatchHandler? batchHandler;
  Future<void> Function(AndroidNativeObservationStatus)? observationHandler;
  final Map<String, List<Object?>> calls = {};
  final Map<AndroidActivitySource, TestProcessLease> leases = {};
  Completer<AndroidNativeObservationStatus>? pending;
  Future<AndroidNativeObservationStatus>? lastFuture;
  bool failGet = false;
  int gets = 0;
  final batch = const AndroidNativeUsageBatch(
      permission: UsageAccess.granted,
      readiness: 'ready',
      signals: [],
      counters: {});
  @override
  void setSignalHandler(AndroidNativeSignalHandler? handler) =>
      signalHandler = handler;
  @override
  void setBatchHandler(AndroidNativeBatchHandler? handler) =>
      batchHandler = handler;
  @override
  void setObservationStatusHandler(
          Future<void> Function(AndroidNativeObservationStatus)? handler) =>
      observationHandler = handler;
  @override
  Future<AndroidPrivateOutboxRoot> getOutboxRoot() async {
    calls['root'] = [];
    return root;
  }

  @override
  Future<AndroidNativeObservationStatus> getObservationStatus() {
    gets++;
    return lastFuture = failGet
        ? Future.error(
            const AndroidActivityException('observation_status_invalid'))
        : pending?.future ?? Future.value(current);
  }

  Future<void> push(AndroidNativeObservationStatus value) async {
    current = value;
    await observationHandler?.call(value);
  }

  @override
  Future<AndroidNativeActivation> activate(
      {required bool enabled,
      required bool integrityAuthorityReady,
      required Set<AndroidActivitySource> boundSources,
      required Map<String, String> categoryMapping}) async {
    calls['activate'] = [
      enabled,
      integrityAuthorityReady,
      boundSources,
      categoryMapping
    ];
    return AndroidNativeActivation(
        enabled: true, readiness: 'ready', observationStatus: current);
  }

  @override
  Future<AndroidNativeActivation> activateObservation(
      {required bool enabled,
      required bool integrityAuthorityReady,
      required Set<AndroidActivitySource> boundSources,
      required Map<String, String> categoryMapping,
      required Map<AndroidActivitySource, ActivityOutboxProcessLease>
          leases}) async {
    calls['activateObservation'] = [
      enabled,
      integrityAuthorityReady,
      boundSources,
      categoryMapping,
      leases
    ];
    return AndroidNativeActivation(
        enabled: true, readiness: 'ready', observationStatus: current);
  }

  @override
  Future<AndroidNativeUsageBatch> queryUsageEvents(
      {required int startMs, required int endMs}) async {
    calls['query'] = [startMs, endMs];
    return batch;
  }

  @override
  Future<void> acknowledgeBatch(
      AndroidNativeUsageBatch value, List<String> dispositions) async {
    calls['ack'] = [value, dispositions];
  }

  @override
  Future<void> deactivate() async {
    calls['deactivate'] = [];
  }

  @override
  Future<bool> debugInvalidateObservationNotification(
      AndroidNativeObservationStatus target) async {
    calls['invalidate'] = [target];
    return true;
  }

  @override
  Future<AndroidNativeStopObservationResult> stopObservation(
      AndroidNativeObservationStatus target) async {
    calls['stop'] = [target];
    current = status(
        revision: current.revision + 1,
        state: AndroidNativeObservationState.stopped);
    return AndroidNativeStopObservationResult(
        outcome: AndroidNativeStopOutcome.stopped, status: current);
  }

  @override
  Future<ActivityOutboxProcessLease> acquireDiagnosticOutboxLease(
      AndroidActivitySource source,
      {String permitToken = ''}) async {
    calls['acquire'] = [source, permitToken];
    return leases[source] = TestProcessLease(source.wireValue);
  }

  @override
  Future<bool> releaseDiagnosticOutboxLease(
      ActivityOutboxProcessLease lease) async {
    calls['release'] = [lease];
    (lease as TestProcessLease).isHeld = false;
    return true;
  }

  @override
  Future<AndroidDiagnosticOwnerReleasePermit> beginDiagnosticOwnerRelease(
      AndroidNativeObservationStatus target) async {
    calls['begin'] = [target];
    return AndroidDiagnosticOwnerReleasePermit(
        token: 'never-export-token', status: current);
  }

  @override
  Future<bool> endDiagnosticOwnerRelease(
      AndroidDiagnosticOwnerReleasePermit permit) async {
    calls['end'] = [permit];
    return true;
  }
}

List<Map<String, Object?>> events(A3dTimingProbe probe, [String? event]) =>
    (probe.readTrace()['events']! as List<Map<String, Object?>>)
        .where((item) => event == null || item['event'] == event)
        .toList();

ActivityIntegrityKeyRepository keys() => ActivityIntegrityKeyRepository(
    storage: MemoryIntegrityStorage(),
    randomBytes: (n) => List.generate(n, (i) => i));

A3dDeviceGateController controller(
        ProbePlatform native, A3dTimingProbe probe) =>
    A3dDeviceGateController(
        keyRepository: keys(),
        platform: A3dTimingSignalPlatform(native, probe),
        timingProbe: probe,
        clockMs: () => 1000000,
        categoryMapping: const {});

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<(AndroidActivityCollector, ProbePlatform, Directory)> collectorRig(
    A3dTimingProbe probe,
    {void Function(AndroidCollectorObservationEvent)? hook}) async {
  final root = await Directory.systemTemp.createTemp('timing_probe_');
  final native = ProbePlatform()
    ..root = AndroidPrivateOutboxRoot(
        path: root.path, storageScope: 'no_backup_private');
  final repository = keys();
  await repository.provision();
  final collector = AndroidActivityCollector(
      config: AndroidActivityCollectorConfig(
          enabled: true,
          bindings: AndroidActivityCollectorBindings(
              usageEvents: A3dDiagnosticBindingFactory.create(
                  AndroidActivitySource.usageEvents),
              screenState: A3dDiagnosticBindingFactory.create(
                  AndroidActivitySource.screenState)),
          categoryMapping: const {}),
      keyRepository: repository,
      platform: A3dTimingSignalPlatform(native, probe),
      clockMs: () => 1000000,
      observationHook: hook ?? probe.collector);
  await collector.initialize();
  expect(collector.status.nativeStatus?.state,
      AndroidNativeObservationState.running);
  addTearDown(() async {
    await collector.stop();
    probe.dispose();
    root.deleteSync(recursive: true);
  });
  return (collector, native, root);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('service reader permits VM routing only and cannot arm or mutate',
      () async {
    final native = ProbePlatform();
    final probe = A3dTimingProbe();
    final c = controller(native, probe);
    final off = await entry
        .readTimingTraceExtension(c, {'isolateId': 'private-routing'});
    expect(off.isError(), isFalse);
    expect(jsonDecode(off.result!)['recording'], isFalse);
    expect(off.result, isNot(contains('private-routing')));
    c.startTimingTrace();
    final before = jsonEncode(c.readTimingTrace());
    for (final parameter in ['arm', 'start', 'stop', 'delay', 'action']) {
      final denied = await entry.readTimingTraceExtension(
          c, {'isolateId': 'private-routing', parameter: 'true'});
      expect(denied.isError(), isTrue);
    }
    expect(jsonEncode(c.readTimingTrace()), before);
    expect(probe.armed, isNull);
    expect(native.gets, 0);
    expect(native.calls, isEmpty);
    c.endTimingTrace();
    final sealed = await entry.readTimingTraceExtension(c, {});
    expect(jsonDecode(sealed.result!)['complete'], isTrue);
    c.dispose();
  });

  test('four interfaces forward every method, callback, lease and argument',
      () async {
    final native = ProbePlatform();
    final probe = A3dTimingProbe();
    final wrapper = A3dTimingSignalPlatform(native, probe);
    Future<void> signal(Map<String, Object?> _) async {}
    Future<List<String>> batch(AndroidNativeUsageBatch _) async => [];
    Future<void> observation(AndroidNativeObservationStatus _) async {}
    wrapper.setSignalHandler(signal);
    wrapper.setBatchHandler(batch);
    wrapper.setObservationStatusHandler(observation);
    expect(identical(native.signalHandler, signal), isTrue);
    expect(identical(native.batchHandler, batch), isTrue);
    expect(identical(native.observationHandler, observation), isTrue);
    expect(await wrapper.getOutboxRoot(), same(native.root));
    expect(await wrapper.getObservationStatus(), same(native.current));
    final sources = {AndroidActivitySource.usageEvents};
    final mapping = {'test': 'other'};
    final lease = await wrapper.acquireDiagnosticOutboxLease(
        AndroidActivitySource.usageEvents,
        permitToken: 'permit');
    final leases = {AndroidActivitySource.usageEvents: lease};
    await wrapper.activate(
        enabled: true,
        integrityAuthorityReady: false,
        boundSources: sources,
        categoryMapping: mapping);
    expect(native.calls['activate']!.take(2), [true, false]);
    expect(native.calls['activate']![2], same(sources));
    expect(native.calls['activate']![3], same(mapping));
    await wrapper.activateObservation(
        enabled: false,
        integrityAuthorityReady: true,
        boundSources: sources,
        categoryMapping: mapping,
        leases: leases);
    expect(native.calls['activateObservation']!.take(2), [false, true]);
    expect(native.calls['activateObservation']![2], same(sources));
    expect(native.calls['activateObservation']![3], same(mapping));
    expect(native.calls['activateObservation']![4], same(leases));
    expect(await wrapper.queryUsageEvents(startMs: 4, endMs: 8),
        same(native.batch));
    expect(native.calls['query'], [4, 8]);
    final dispositions = ['accepted'];
    await wrapper.acknowledgeBatch(native.batch, dispositions);
    expect(native.calls['ack']![0], same(native.batch));
    expect(native.calls['ack']![1], same(dispositions));
    final target = native.current;
    await wrapper.debugInvalidateObservationNotification(target);
    await wrapper.stopObservation(target);
    expect(native.calls['invalidate']!.single, same(target));
    expect(native.calls['stop']!.single, same(target));
    expect(
        native.calls['acquire'], [AndroidActivitySource.usageEvents, 'permit']);
    await wrapper.releaseDiagnosticOutboxLease(lease);
    expect(native.calls['release']!.single, same(lease));
    final permit = await wrapper.beginDiagnosticOwnerRelease(target);
    await wrapper.endDiagnosticOwnerRelease(permit);
    expect(native.calls['begin']!.single, same(target));
    expect(native.calls['end']!.single, same(permit));
    await wrapper.deactivate();
    expect(native.calls.containsKey('deactivate'), isTrue);
    wrapper.setSignalHandler(null);
    wrapper.setBatchHandler(null);
    wrapper.setObservationStatusHandler(null);
    expect(native.signalHandler, isNull);
    expect(native.batchHandler, isNull);
    expect(native.observationHandler, isNull);
    expect(events(probe), isEmpty);
  });

  test('default off forwards the original Future and cannot arm', () async {
    final native = ProbePlatform();
    final probe = A3dTimingProbe();
    expect(probe.arm(A3dTimingAction.manual), isFalse);
    final work = A3dTimingSignalPlatform(native, probe).getObservationStatus();
    expect(work, same(native.lastFuture));
    await work;
    expect(events(probe), isEmpty);
    expect(probe.readTrace()['complete'], isFalse);
    expect(probe.holdDuration, const Duration(seconds: 20));
    expect(probe.window, const Duration(seconds: 180));
  });

  test(
      'hold starts only after real reply and delivers same object once; push stays immediate',
      () async {
    final native = ProbePlatform()..pending = Completer();
    final hold = Completer<void>();
    var delays = 0;
    final probe = A3dTimingProbe.testing(delay: (_) {
      delays++;
      return hold.future;
    })
      ..start();
    final wrapper = A3dTimingSignalPlatform(native, probe);
    probe.arm(A3dTimingAction.manual);
    var delivered = 0;
    final work = probe.read(A3dTimingAction.manual, () async {
      final first = wrapper.getObservationStatus();
      final second = wrapper.getObservationStatus();
      expect(await second, same(native.current));
      return first;
    }).then((value) {
      delivered++;
      return value;
    });
    await flush();
    expect(delays, 0);
    native.pending!.complete(native.current);
    await flush();
    expect(delays, 1);
    expect(delivered, 0);
    var pushed = false;
    wrapper.setObservationStatusHandler((_) async {
      pushed = true;
    });
    final captured = native.current;
    await native.push(
        status(revision: 2, state: AndroidNativeObservationState.stopped));
    expect(pushed, isTrue);
    expect(delivered, 0);
    hold.complete();
    expect(await work, same(captured));
    expect(delivered, 1);
    expect(events(probe, 'holdStarted'), hasLength(1));
    expect(events(probe, 'getDelivered'), hasLength(2));
    probe.seal();
    expect(probe.readTrace()['complete'], isTrue);
    final encoded = jsonEncode(probe.readTrace());
    expect(encoded, isNot(contains('never-export')));
    expect(encoded, isNot(contains('sessionId')));
  });

  test('poll and observer do not consume the next manual injection', () async {
    final native = ProbePlatform();
    final hold = Completer<void>();
    final probe = A3dTimingProbe.testing(delay: (_) => hold.future)..start();
    final wrapper = A3dTimingSignalPlatform(native, probe);
    probe.arm(A3dTimingAction.manual);
    await probe.read(A3dTimingAction.poll, wrapper.getObservationStatus);
    await probe.read(A3dTimingAction.observer, wrapper.getObservationStatus);
    expect(probe.armed, A3dTimingAction.manual);
    final work =
        probe.read(A3dTimingAction.manual, wrapper.getObservationStatus);
    await flush();
    expect(events(probe, 'holdStarted'), hasLength(1));
    expect(probe.armed, isNull);
    hold.complete();
    await work;
    probe.seal();
    expect(probe.readTrace()['complete'], isTrue);
  });

  test('delegate failure is not delayed or fabricated and token cannot retry',
      () async {
    final native = ProbePlatform()..failGet = true;
    var delays = 0;
    final probe = A3dTimingProbe.testing(delay: (_) async {
      delays++;
    })
      ..start();
    final wrapper = A3dTimingSignalPlatform(native, probe);
    probe.arm(A3dTimingAction.manual);
    await expectLater(
        probe.read(A3dTimingAction.manual, wrapper.getObservationStatus),
        throwsA(isA<AndroidActivityException>()));
    expect(delays, 0);
    expect(events(probe, 'getCaptured'), isEmpty);
    expect(events(probe, 'getDelivered'), isEmpty);
    native.failGet = false;
    await probe.read(A3dTimingAction.manual, wrapper.getObservationStatus);
    expect(delays, 0);
    probe.seal();
  });

  test('pending controller read coalesces; selected arm is marked unused',
      () async {
    final native = ProbePlatform()..pending = Completer();
    var delays = 0;
    final probe = A3dTimingProbe.testing(delay: (_) async {
      delays++;
    })
      ..start();
    final c = controller(native, probe);
    final first = c.refreshEvidence();
    probe.arm(A3dTimingAction.manual);
    final second = c.refreshEvidence();
    expect(native.gets, 1);
    expect(events(probe, 'coalesced'), hasLength(1));
    expect(events(probe, 'armUnused'), hasLength(1));
    native.pending!.complete(native.current);
    await Future.wait([first, second]);
    await c.refreshEvidence();
    expect(delays, 0);
    probe.seal();
    c.dispose();
  });

  test(
      'manual checking is synchronous and early timeout reserves projection headroom',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds);
      final c = controller(native, probe);
      c.setForeground(true);
      time.flushMicrotasks();
      c.startTimingTrace();
      probe.arm(A3dTimingAction.manual);
      unawaited(c.refreshEvidence());
      expect(c.synchronization, A3dStatusSynchronization.checking);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 2499));
      expect(c.synchronization, A3dStatusSynchronization.checking);
      time.elapse(const Duration(milliseconds: 1));
      expect(c.synchronization, A3dStatusSynchronization.unknown);
      final unknown = events(probe, 'synchronizationAssigned').last;
      expect(unknown['us'], 2500000);
      expect(
          unknown['synchronization'], A3dStatusSynchronization.unknown.index);
      expect(unknown['foreground'], isTrue);
      final manual = events(probe, 'action').last;
      expect(
          events(probe)
              .where((e) =>
                  (e['seq']! as int) >= (manual['seq']! as int) &&
                  (e['seq']! as int) <= (unknown['seq']! as int))
              .every((e) => e['foreground'] != false),
          isTrue);
      expect(events(probe, 'getDelivered'), isEmpty);
      c.setForeground(false);
      time.elapse(const Duration(milliseconds: 17500));
      expect(events(probe, 'getDelivered'), hasLength(1));
      expect(c.synchronization, A3dStatusSynchronization.unknown);
      probe.seal();
      expect(probe.readTrace()['complete'], isTrue);
      c.dispose();
    });
  });

  test('resume Timer stays outside selected Zone; fresh poll is not old bounce',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds)
            ..start();
      final c = controller(native, probe);
      probe.arm(A3dTimingAction.resume);
      c.setForeground(true);
      expect(c.synchronization, A3dStatusSynchronization.checking);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 2500));
      expect(c.synchronization, A3dStatusSynchronization.unknown);
      time.elapse(const Duration(milliseconds: 500));
      expect(c.synchronization, A3dStatusSynchronization.verified);
      expect(events(probe, 'holdStarted'), hasLength(1));
      final captured = events(probe, 'getCaptured');
      expect(captured.length, greaterThanOrEqualTo(2));
      expect(captured.first['requestId'], isNot(captured.last['requestId']));
      final observer = events(probe, 'readStarted').last;
      expect(observer['action'], 'observer');
      c.setForeground(false);
      time.elapse(const Duration(seconds: 17));
      probe.seal();
      expect(probe.readTrace()['complete'], isTrue);
      c.dispose();
    });
  });

  test(
      '300ms delayed timeout callback still publishes unknown before strict 3s',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds);
      final c = controller(native, probe);
      c.setForeground(true);
      time.flushMicrotasks();
      c.startTimingTrace();
      native.pending = Completer<AndroidNativeObservationStatus>();
      unawaited(c.refreshEvidence());
      time.flushMicrotasks();
      final action = events(probe, 'action').last;
      time.elapse(const Duration(milliseconds: 2490));
      expect(c.synchronization, A3dStatusSynchronization.checking);
      // Simulate occupied event-loop time; do not run the due Timer early.
      time.elapseBlocking(const Duration(milliseconds: 300));
      time.elapse(Duration.zero);
      expect(c.synchronization, A3dStatusSynchronization.unknown);
      final published = events(probe, 'published').last;
      expect(
          published['synchronization'], A3dStatusSynchronization.unknown.index);
      expect(published['foreground'], isTrue);
      expect(published['active'], isFalse);
      expect(published['canQuery'], isFalse);
      expect(published['evidenceReady'], isFalse);
      expect((published['us']! as int) - (action['us']! as int), 2790000);
      expect((published['us']! as int) - (action['us']! as int),
          lessThanOrEqualTo(3000000));
      expect(events(probe, 'getDelivered'), isEmpty);
      native.pending!.complete(native.current);
      time.flushMicrotasks();
      c.setForeground(false);
      c.endTimingTrace();
      c.dispose();
    });
  });

  test(
      'manual coalescing onto observer retains original early deadline and one native read',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds);
      final c = controller(native, probe);
      c.setForeground(true);
      time.flushMicrotasks();
      c.startTimingTrace();
      final priorGets = native.gets;
      native.pending = Completer<AndroidNativeObservationStatus>();
      time.elapse(const Duration(seconds: 1));
      expect(events(probe, 'readStarted').single['action'], 'observer');
      time.elapse(const Duration(milliseconds: 100));
      unawaited(c.refreshEvidence());
      time.flushMicrotasks();
      final action = events(probe, 'action').last;
      expect(events(probe, 'coalesced'), hasLength(1));
      expect(native.gets, priorGets + 1);
      time.elapse(const Duration(milliseconds: 2399));
      expect(c.synchronization, A3dStatusSynchronization.checking);
      time.elapse(const Duration(milliseconds: 1));
      expect(c.synchronization, A3dStatusSynchronization.unknown);
      final published = events(probe, 'published').last;
      expect(published['us'], 3500000);
      expect((published['us']! as int) - (action['us']! as int), 2400000);
      expect(events(probe, 'readStarted'), hasLength(1));
      expect(native.gets, priorGets + 1);
      native.pending!.complete(native.current);
      time.flushMicrotasks();
      c.setForeground(false);
      c.endTimingTrace();
      c.dispose();
    });
  });

  test('valid reply before early budget is accepted without premature unknown',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds);
      final c = controller(native, probe);
      c.setForeground(true);
      time.flushMicrotasks();
      c.startTimingTrace();
      native.pending = Completer<AndroidNativeObservationStatus>();
      unawaited(c.refreshEvidence());
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 2499));
      expect(c.synchronization, A3dStatusSynchronization.checking);
      native.pending!.complete(native.current);
      time.flushMicrotasks();
      expect(c.synchronization, A3dStatusSynchronization.verified);
      expect(c.nativeState, 'running');
      expect(events(probe, 'readTimedOut'), isEmpty);
      expect(
          events(probe, 'synchronizationAssigned').where((event) =>
              event['synchronization'] ==
              A3dStatusSynchronization.unknown.index),
          isEmpty);
      c.endTimingTrace();
      c.setForeground(false);
      c.dispose();
    });
  });

  test(
      'native unknown reply publishes unknown immediately instead of spending the wait budget',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds);
      final c = controller(native, probe);
      c.setForeground(true);
      time.flushMicrotasks();
      c.startTimingTrace();
      native.current = status(state: AndroidNativeObservationState.unknown);
      unawaited(c.refreshEvidence());
      time.flushMicrotasks();
      final action = events(probe, 'action').last;
      final published = events(probe, 'published').last;
      expect(c.synchronization, A3dStatusSynchronization.unknown);
      expect(
          published['synchronization'], A3dStatusSynchronization.unknown.index);
      expect(published['foreground'], isTrue);
      expect(published['evidenceReady'], isFalse);
      expect((published['us']! as int) - (action['us']! as int), 0);
      expect(events(probe, 'readTimedOut'), isEmpty);
      c.endTimingTrace();
      c.setForeground(false);
      c.dispose();
    });
  });

  test('controller generation rejection is recorded before timeout', () async {
    final native = ProbePlatform();
    final hold = Completer<void>();
    final probe = A3dTimingProbe.testing(delay: (_) => hold.future)..start();
    final c = controller(native, probe);
    probe.arm(A3dTimingAction.manual);
    final work = c.refreshEvidence();
    await flush();
    c.setForeground(false);
    hold.complete();
    await work;
    expect(events(probe, 'controllerRejectedGeneration'), hasLength(1));
    expect(c.synchronization, A3dStatusSynchronization.unknown);
    probe.seal();
    c.dispose();
  });

  test('real collector rejects delivered held running after terminal push',
      () async {
    final hold = Completer<void>();
    final probe = A3dTimingProbe.testing(delay: (_) => hold.future);
    final (collector, native, _) = await collectorRig(probe);
    probe.start();
    probe.arm(A3dTimingAction.manual);
    final work = probe.read(
        A3dTimingAction.manual, collector.synchronizeObservationStatus);
    await flush();
    await native.push(
        status(revision: 2, state: AndroidNativeObservationState.stopped));
    expect(collector.status.canQuery, isFalse);
    hold.complete();
    await work;
    expect(events(probe, 'getDelivered'), hasLength(1));
    expect(events(probe, 'collectorRejectedTerminal'), hasLength(1));
    expect(events(probe, 'getDelivered').single['requestId'],
        events(probe, 'collectorRejectedTerminal').single['requestId']);
    expect(collector.status.ready, isFalse);
    probe.seal();
    expect(probe.readTrace()['complete'], isTrue);
  });

  test(
      'page stop changes collector generation; old get and old push both reject',
      () async {
    final hold = Completer<void>();
    final probe = A3dTimingProbe.testing(delay: (_) => hold.future);
    final (collector, native, _) = await collectorRig(probe);
    final oldPush = native.observationHandler!;
    final running = native.current;
    probe.start();
    probe.arm(A3dTimingAction.manual);
    final work = probe.read(
        A3dTimingAction.manual, collector.synchronizeObservationStatus);
    await flush();
    await collector.stop();
    await oldPush(running);
    hold.complete();
    await work;
    expect(events(probe, 'collectorRejectedPushGeneration'), hasLength(1));
    expect(events(probe, 'collectorRejectedGeneration'), hasLength(1));
    expect(events(probe, 'getDelivered'), hasLength(1));
    expect(collector.status.ready, isFalse);
    probe.seal();
  });

  test('revision and retired-session rejection hooks preserve original guards',
      () async {
    final probe = A3dTimingProbe();
    final native = ProbePlatform();
    final collector = AndroidActivityCollector(
        config: const AndroidActivityCollectorConfig(
            bindings: AndroidActivityCollectorBindings(
                usageEvents: null, screenState: null),
            categoryMapping: {}),
        keyRepository: keys(),
        platform: A3dTimingSignalPlatform(native, probe),
        clockMs: () => 1000000,
        observationHook: probe.collector);
    probe.start();
    native.current = status(revision: 4);
    await collector.synchronizeObservationStatus();
    native.current = status(revision: 3);
    await collector.synchronizeObservationStatus();
    expect(events(probe, 'collectorRejectedRevision'), hasLength(1));
    native.current = status(session: 'second-private-session');
    await collector.synchronizeObservationStatus();
    native.current = status(revision: 5);
    await collector.synchronizeObservationStatus();
    expect(events(probe, 'collectorRejectedRetiredSession'), hasLength(1));
    expect(collector.status.ready, isFalse);
    expect(jsonEncode(probe.readTrace()), isNot(contains('private-session')));
    probe.seal();
  });

  test(
      'throwing collector hook cannot change normal decisions; evidence invalid',
      () async {
    final probe = A3dTimingProbe();
    final (collector, native, _) = await collectorRig(probe,
        hook: (_) => throw StateError('never-export-exception'));
    expect(collector.observationHookFailed, isTrue);
    final result = await collector.synchronizeObservationStatus();
    expect(result.nativeStatus, same(native.current));
    probe.start();
    probe.seal();
    expect(
        probe.readTrace(
            callbackFailed: collector.observationHookFailed)['complete'],
        isFalse);
    expect(
        probe.readTrace(callbackFailed: true)['invalid'], contains('callback'));
  });

  test(
      'overflow preserves bounded tail and fails completeness; reads are immutable',
      () {
    final probe = A3dTimingProbe.testing(capacity: 4)..start();
    for (var i = 0; i < 8; i++) {
      probe.record(A3dTimingEvent.snapshot);
    }
    probe.seal();
    expect(events(probe), hasLength(4));
    expect(events(probe).first['seq'], greaterThan(1));
    expect(probe.readTrace()['complete'], isFalse);
    expect(probe.readTrace()['invalid'], contains('overflow'));
    expect(() => events(probe).first['seq'] = 3, throwsUnsupportedError);
    expect(jsonEncode(probe.readTrace()), jsonEncode(probe.readTrace()));
  });

  test(
      'default 180s expiry automatically seals, without polling or native action',
      () {
    fakeAsync((time) {
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds)
            ..start();
      time.elapse(const Duration(seconds: 179));
      expect(probe.sealed, isFalse);
      time.elapse(const Duration(seconds: 1));
      expect(probe.sealed, isTrue);
      expect(probe.recording, isFalse);
      expect(events(probe).last['event'], 'expired');
      expect(probe.readTrace()['complete'], isTrue);
    });
  });

  test('sealing pending hold is incomplete and does not pretend rejection',
      () async {
    final native = ProbePlatform();
    final hold = Completer<void>();
    final probe = A3dTimingProbe.testing(delay: (_) => hold.future)..start();
    final wrapper = A3dTimingSignalPlatform(native, probe);
    probe.arm(A3dTimingAction.manual);
    final work =
        probe.read(A3dTimingAction.manual, wrapper.getObservationStatus);
    await flush();
    probe.seal();
    expect(probe.readTrace()['complete'], isFalse);
    expect(probe.readTrace()['invalid'], contains('pendingAtSeal'));
    expect(probe.start(), isFalse);
    hold.complete();
    expect(await work, same(native.current));
    expect(events(probe, 'getDelivered'), isEmpty);
  });

  test('dispose explicitly cancels held reply, never reports a fake rejection',
      () async {
    final native = ProbePlatform();
    final hold = Completer<void>();
    final probe = A3dTimingProbe.testing(delay: (_) => hold.future)..start();
    probe.arm(A3dTimingAction.manual);
    final work = probe.read(A3dTimingAction.manual,
        A3dTimingSignalPlatform(native, probe).getObservationStatus);
    await flush();
    probe.dispose();
    final failure = expectLater(work, throwsA(isA<AndroidActivityException>()));
    hold.complete();
    await failure;
    expect(events(probe, 'holdCancelled'), hasLength(1));
    expect(events(probe, 'getDelivered'), isEmpty);
    expect(probe.readTrace()['invalid'], contains('cancelled'));
    expect(probe.readTrace()['complete'], isFalse);
  });

  test('trace callback failure leaves same native result and invalid evidence',
      () async {
    final native = ProbePlatform();
    final probe =
        A3dTimingProbe.testing(elapsedUs: () => throw StateError('private'))
          ..start();
    expect(await A3dTimingSignalPlatform(native, probe).getObservationStatus(),
        same(native.current));
    probe.seal();
    expect(probe.readTrace()['complete'], isFalse);
    expect(probe.readTrace()['invalid'], contains('callback'));
    expect(jsonEncode(probe.readTrace()), isNot(contains('private')));
  });

  test('179s arm is refused without modifying the native read', () {
    fakeAsync((time) {
      final native = ProbePlatform();
      var delays = 0;
      final probe = A3dTimingProbe.testing(
          elapsedUs: () => time.elapsed.inMicroseconds,
          delay: (_) async {
            delays++;
          })
        ..start();
      time.elapse(const Duration(seconds: 179));
      expect(probe.arm(A3dTimingAction.manual), isFalse);
      expect(probe.armed, isNull);
      AndroidNativeObservationStatus? delivered;
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((value) => delivered = value);
      time.flushMicrotasks();
      expect(delivered, same(native.current));
      expect(native.gets, 1);
      expect(delays, 0);
      expect(events(probe, 'armWindowRejected'), hasLength(1));
      expect(events(probe, 'holdStarted'), isEmpty);
      time.elapse(const Duration(seconds: 1));
      expect(probe.sealed, isTrue);
    });
  });

  test('getter entry rechecks an arm issued before the remaining window shrank',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      var delays = 0;
      final probe = A3dTimingProbe.testing(
          elapsedUs: () => time.elapsed.inMicroseconds,
          delay: (_) async {
            delays++;
          })
        ..start();
      expect(probe.arm(A3dTimingAction.manual), isTrue);
      time.elapse(const Duration(seconds: 160));
      AndroidNativeObservationStatus? delivered;
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((value) => delivered = value);
      time.flushMicrotasks();
      expect(delivered, same(native.current));
      expect(native.gets, 1);
      expect(delays, 0);
      expect(events(probe, 'holdWindowRejected'), hasLength(1));
      expect(events(probe, 'armUnused'), hasLength(1));
      probe.seal();
      expect(probe.readTrace()['complete'], isFalse);
      expect(probe.readTrace()['invalid'], contains('window'));
    });
  });

  test(
      'real capture rechecks budget after slow delegate and passes same reply immediately',
      () {
    fakeAsync((time) {
      final native = ProbePlatform()..pending = Completer();
      var delays = 0;
      final probe = A3dTimingProbe.testing(
          elapsedUs: () => time.elapsed.inMicroseconds,
          delay: (_) async {
            delays++;
          })
        ..start();
      time.elapse(const Duration(seconds: 158));
      expect(probe.arm(A3dTimingAction.manual), isTrue);
      AndroidNativeObservationStatus? delivered;
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((value) => delivered = value);
      time.elapse(const Duration(seconds: 2));
      native.pending!.complete(native.current);
      time.flushMicrotasks();
      expect(delivered, same(native.current));
      expect(native.gets, 1);
      expect(delays, 0);
      expect(events(probe, 'getDelivered').single['us'], 160000000);
      expect(events(probe, 'holdStarted'), isEmpty);
      expect(events(probe, 'holdWindowRejected'), hasLength(1));
      probe.seal();
      expect(probe.readTrace()['complete'], isFalse);
    });
  });

  test('delegate returning after 180s never acquires a new 20s hold', () {
    fakeAsync((time) {
      final native = ProbePlatform()..pending = Completer();
      var delays = 0;
      var deliveries = 0;
      AndroidNativeObservationStatus? delivered;
      final probe = A3dTimingProbe.testing(
          elapsedUs: () => time.elapsed.inMicroseconds,
          delay: (_) async {
            delays++;
          })
        ..start();
      time.elapse(const Duration(seconds: 158));
      expect(probe.arm(A3dTimingAction.manual), isTrue);
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((value) {
        delivered = value;
        deliveries++;
      });
      time.elapse(const Duration(seconds: 22));
      expect(probe.sealed, isTrue);
      expect(deliveries, 0);
      time.elapse(const Duration(seconds: 1));
      native.pending!.complete(native.current);
      time.flushMicrotasks();
      expect(delivered, same(native.current));
      expect(deliveries, 1);
      expect(delays, 0);
      expect(native.gets, 1);
      expect(events(probe, 'holdCancelled'), hasLength(1));
      expect(events(probe, 'holdStarted'), isEmpty);
      expect(probe.readTrace()['complete'], isFalse);
      expect(probe.readTrace()['invalid'], contains('window'));
    });
  });

  test(
      '180s deadline releases existing hold once even if delay future has not completed',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final hold = Completer<void>();
      var deliveries = 0;
      int? deliveredUs;
      AndroidNativeObservationStatus? delivered;
      final probe = A3dTimingProbe.testing(
          elapsedUs: () => time.elapsed.inMicroseconds,
          delay: (_) => hold.future)
        ..start();
      time.elapse(const Duration(seconds: 158));
      expect(probe.arm(A3dTimingAction.manual), isTrue);
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((value) {
        delivered = value;
        deliveredUs = time.elapsed.inMicroseconds;
        deliveries++;
      });
      time.flushMicrotasks();
      final heldRequest = events(probe, 'holdStarted').single['requestId'];
      time.elapse(const Duration(seconds: 22));
      expect(delivered, same(native.current));
      expect(deliveredUs, 180000000);
      expect(deliveries, 1);
      expect(events(probe, 'holdCancelled').single['requestId'], heldRequest);
      expect(probe.readTrace()['complete'], isFalse);
      time.elapse(const Duration(seconds: 2));
      hold.complete();
      time.flushMicrotasks();
      expect(deliveries, 1);
      expect(native.gets, 1);
    });
  });

  test(
      '159s boundary permits 20s hold with one full second of observation tail',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds)
            ..start();
      time.elapse(const Duration(seconds: 159));
      expect(probe.arm(A3dTimingAction.manual), isTrue);
      AndroidNativeObservationStatus? delivered;
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((value) => delivered = value);
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 20));
      expect(delivered, same(native.current));
      expect(events(probe, 'getDelivered').single['us'], 179000000);
      expect(probe.sealed, isFalse);
      time.elapse(const Duration(seconds: 1));
      expect(probe.readTrace()['complete'], isTrue);
      expect(events(probe, 'holdCancelled'), isEmpty);
    });
  });

  test(
      'background change stays visible in the same case and cannot count as continuous foreground',
      () {
    fakeAsync((time) {
      final native = ProbePlatform();
      final probe =
          A3dTimingProbe.testing(elapsedUs: () => time.elapsed.inMicroseconds);
      final c = controller(native, probe);
      c.setForeground(true);
      time.flushMicrotasks();
      c.startTimingTrace();
      c.armTimingRead(A3dTimingAction.manual);
      unawaited(c.refreshEvidence());
      time.flushMicrotasks();
      final manual = events(probe, 'action').last;
      time.elapse(const Duration(seconds: 1));
      c.setForeground(false);
      time.elapse(const Duration(seconds: 2));
      final changes = events(probe, 'foregroundChanged');
      expect(changes.single['foreground'], isFalse);
      expect(changes.single['caseId'], manual['caseId']);
      expect(events(probe, 'foregroundEntered').single['foreground'], isFalse);
      expect(events(probe, 'controllerRejectedGeneration'), hasLength(1));
      final caseEvents =
          events(probe).where((e) => e['caseId'] == manual['caseId']);
      expect(caseEvents.every((e) => e['foreground'] != false), isFalse);
      time.elapse(const Duration(seconds: 17));
      c.endTimingTrace();
      c.dispose();
    });
  });

  for (final entryPoint in ['record', 'action', 'arm', 'read', 'get']) {
    test('stalled Timer cannot extend deadline through $entryPoint', () {
      fakeAsync((time) {
        var nowUs = 0;
        final native = ProbePlatform();
        var delays = 0;
        final probe = A3dTimingProbe.testing(
            elapsedUs: () => nowUs,
            delay: (_) async {
              delays++;
            })
          ..start();
        expect(probe.arm(A3dTimingAction.manual), isTrue);
        final wrapper = A3dTimingSignalPlatform(native, probe);
        nowUs = 181000123;
        // Monotonic time advanced, but the event-loop Timer has not run.
        expect(time.elapsed, Duration.zero);
        final beforeRead = jsonEncode(probe.readTrace());
        expect(probe.readTrace()['complete'], isFalse);
        expect(jsonEncode(probe.readTrace()), beforeRead);
        AndroidNativeObservationStatus? delivered;
        switch (entryPoint) {
          case 'record':
            probe.record(A3dTimingEvent.snapshot);
          case 'action':
            probe.action(A3dTimingAction.manual);
          case 'arm':
            expect(probe.arm(A3dTimingAction.resume), isFalse);
          case 'read':
            probe
                .read(A3dTimingAction.manual, wrapper.getObservationStatus)
                .then((value) => delivered = value);
          case 'get':
            wrapper.getObservationStatus().then((value) => delivered = value);
        }
        time.flushMicrotasks();
        expect(probe.sealed, isTrue);
        expect(probe.recording, isFalse);
        expect(probe.armed, isNull);
        expect(probe.readTrace()['complete'], isFalse);
        expect(probe.readTrace()['invalid'], contains('window'));
        expect(events(probe, 'expired').single['us'], nowUs);
        expect(events(probe, 'snapshot'), isEmpty);
        expect(events(probe, 'action'), isEmpty);
        expect(events(probe, 'holdStarted'), isEmpty);
        expect(delays, 0);
        final isRead = entryPoint == 'read' || entryPoint == 'get';
        expect(native.gets, isRead ? 1 : 0);
        if (isRead) expect(delivered, same(native.current));
      });
    });
  }

  test(
      'synchronous expiry releases captured hold without fabricating an in-window timestamp',
      () {
    fakeAsync((time) {
      var nowUs = 0;
      final native = ProbePlatform();
      final delay = Completer<void>();
      final probe = A3dTimingProbe.testing(
          elapsedUs: () => nowUs, delay: (_) => delay.future)
        ..start();
      probe.arm(A3dTimingAction.manual);
      var delivered = 0;
      AndroidNativeObservationStatus? value;
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((reply) {
        delivered++;
        value = reply;
      });
      time.flushMicrotasks();
      final request = events(probe, 'holdStarted').single['requestId'];
      nowUs = 181000123;
      probe.record(A3dTimingEvent.snapshot);
      time.flushMicrotasks();
      expect(delivered, 1);
      expect(value, same(native.current));
      final cancelled = events(probe, 'holdCancelled').single;
      expect(cancelled['requestId'], request);
      expect(cancelled['us'], nowUs);
      expect(events(probe, 'expired').single['us'], nowUs);
      expect(events(probe, 'snapshot'), isEmpty);
      expect(probe.readTrace()['complete'], isFalse);
      delay.complete();
      time.flushMicrotasks();
      expect(delivered, 1);
      expect(native.gets, 1);
    });
  });

  test(
      'capture after monotonic deadline with stalled Timer adds no artificial delay',
      () {
    fakeAsync((time) {
      var nowUs = 0;
      final native = ProbePlatform()..pending = Completer();
      var delays = 0;
      final probe = A3dTimingProbe.testing(
          elapsedUs: () => nowUs,
          delay: (_) async {
            delays++;
          })
        ..start();
      probe.arm(A3dTimingAction.manual);
      AndroidNativeObservationStatus? delivered;
      probe
          .read(A3dTimingAction.manual,
              A3dTimingSignalPlatform(native, probe).getObservationStatus)
          .then((value) => delivered = value);
      nowUs = 181000123;
      native.pending!.complete(native.current);
      time.flushMicrotasks();
      expect(delivered, same(native.current));
      expect(delays, 0);
      expect(native.gets, 1);
      expect(events(probe, 'getCaptured'), isEmpty);
      expect(events(probe, 'expired').single['us'], nowUs);
      expect(probe.readTrace()['complete'], isFalse);
    });
  });

  test('late Timer seal itself cannot produce complete evidence', () {
    fakeAsync((time) {
      var nowUs = 0;
      final probe = A3dTimingProbe.testing(elapsedUs: () => nowUs)..start();
      nowUs = 181000123;
      time.elapse(const Duration(seconds: 180));
      expect(probe.sealed, isTrue);
      expect(probe.readTrace()['complete'], isFalse);
      expect(probe.readTrace()['invalid'], contains('window'));
      expect(events(probe, 'expired').single['us'], nowUs);
    });
  });

  test(
      'full controller trace distinguishes timeout, fresh poll and rejected late reply without ready bounce',
      () {
    final root = Directory.systemTemp.createTempSync('timing_controller_');
    try {
      fakeAsync((time) {
        final native = ProbePlatform()
          ..root = AndroidPrivateOutboxRoot(
              path: root.path, storageScope: 'no_backup_private');
        final probe = A3dTimingProbe.testing(
            elapsedUs: () => time.elapsed.inMicroseconds);
        final c = controller(native, probe);
        unawaited(c.beginDiagnostic(A3dDiagnosticScenario.complete));
        time.flushMicrotasks();
        expect(c.active, isTrue);
        c.startTimingTrace();
        c.armTimingRead(A3dTimingAction.resume);
        c.setForeground(true);
        expect(c.synchronization, A3dStatusSynchronization.checking);
        time.flushMicrotasks();
        final oldRequest = events(probe, 'holdStarted').single['requestId'];
        time.elapse(const Duration(milliseconds: 2490));
        time.elapseBlocking(const Duration(milliseconds: 300));
        time.elapse(Duration.zero);
        expect(c.synchronization, A3dStatusSynchronization.unknown);
        final unknownPublished = events(probe, 'published').last;
        final resumeAction = events(probe, 'action').last;
        final publicationDelay = (unknownPublished['us']! as int) -
            (resumeAction['us']! as int);
        expect(publicationDelay, 2790000);
        expect(publicationDelay, lessThanOrEqualTo(3000000));
        final unknown = events(probe, 'synchronizationAssigned').last;
        expect(unknown['foreground'], isTrue);
        expect(
            events(probe)
                .where((e) =>
                    e['caseId'] == unknown['caseId'] &&
                    (e['seq']! as int) <= (unknown['seq']! as int))
                .every((e) => e['foreground'] != false),
            isTrue);
        expect(events(probe, 'getDelivered'), isEmpty);
        time.elapse(const Duration(milliseconds: 210));
        expect(c.active, isTrue);
        expect(events(probe, 'getDelivered').single['requestId'],
            isNot(oldRequest));
        unawaited(native.push(
            status(revision: 2, state: AndroidNativeObservationState.stopped)));
        time.flushMicrotasks();
        final terminalSeq =
            events(probe, 'collectorAccepted').last['seq']! as int;
        expect(c.active, isFalse);
        time.elapse(const Duration(seconds: 17));
        final delivered = events(probe, 'getDelivered')
            .where((e) => e['requestId'] == oldRequest)
            .single;
        final rejected = events(probe, 'collectorRejectedTerminal').single;
        expect(rejected['requestId'], oldRequest);
        expect(delivered['seq']! as int, lessThan(rejected['seq']! as int));
        expect(delivered['us'], 20000000);
        final tail = events(probe)
            .where((e) =>
                (e['seq']! as int) > terminalSeq &&
                (e['event'] == 'published' || e['event'] == 'snapshot'))
            .toList();
        expect(tail, isNotEmpty);
        expect(
            tail.every(
                (e) => e['active'] == false && e['evidenceReady'] == false),
            isTrue);
        expect(tail.every((e) => e['foreground'] == true), isTrue);
        c.setForeground(false);
        c.endTimingTrace();
        expect(c.readTimingTrace()['complete'], isTrue);
        unawaited(c.stop());
        time.flushMicrotasks();
        expect(c.hasCollectorResources, isFalse);
        c.dispose();
      });
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
