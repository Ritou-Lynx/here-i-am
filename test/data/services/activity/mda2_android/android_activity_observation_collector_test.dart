import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/activity_integrity_key_repository.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_collector.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_signal_platform.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/file_activity_outbox_store.dart';
import 'android_activity_collector_test.dart' as fixtures;

Map<String, Object?> observation({
  String id = 'own',
  int revision = 1,
  String state = 'running',
}) => {
  'version': 1,
  'session_id': 'session',
  'observation_id': id,
  'revision': revision,
  'state': state,
  'enabled': state == 'running',
  'reason': state == 'running'
      ? 'ready'
      : state == 'stopped'
      ? 'notification_stop'
      : 'activity_source_unavailable',
};

const activationFields = <String, Object?>{
  'usage_source': 'android_usage_events',
  'screen_source': 'android_screen_state',
  'usage_permission': 'granted',
  'counters': {'query_failures': 0, 'dropped_events': 0},
};

class Rig {
  late final Directory root;
  late final MethodChannel channel;
  late final MethodChannelAndroidActivitySignalPlatform platform;
  late final AndroidActivityCollector collector;
  late final ActivityIntegrityKeyRepository keys;
  Map<String, Object?> current = observation();
  final leases = <String, String>{};
  final stops = <String>[];
  final failRelease = <String>{};
  final releaseLostReply = <String>{};
  final releaseError = <String>{};
  final lastReleased = <String, String>{};
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Completer<Object?>? activation;
  Completer<Object?>? query;
  Completer<Object?>? ack;
  Completer<Object?>? acquire;
  Completer<Object?>? pendingStop;
  Completer<Object?>? pendingRelease;
  int acquireCalls = 0;
  int activationCalls = 0;
  int ackCalls = 0;
  int queryCalls = 0;
  bool stopUnknown = false;
  bool failActivation = false;
  bool failQuery = false;
  bool rejectActivation = false;
  String? queryForeignId;
  String queryReadiness = 'ready';

  Future<void> create() async {
    final scratch = await Directory.systemTemp.createTemp('r3_dart_');
    root = Directory(
      '${scratch.path}${Platform.pathSeparator}no_backup${Platform.pathSeparator}mda2_activity',
    );
    root.createSync(recursive: true);
    channel = MethodChannel('r3/${root.path.hashCode}');
    platform = MethodChannelAndroidActivitySignalPlatform(channel: channel);
    keys = ActivityIntegrityKeyRepository(
      storage: fixtures.MemoryIntegrityStorage(),
      randomBytes: (n) => List.generate(n, (i) => i),
    );
    await keys.provision();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'getOutboxRoot':
          return {'path': root.path, 'storage_scope': 'no_backup_private'};
        case 'acquireDiagnosticOutboxLease':
          acquireCalls++;
          if (acquire != null) return acquire!.future;
          final source = args!['source'] as String;
          if (leases.containsKey(source)) {
            throw PlatformException(code: 'diagnostic_outbox_lease_held');
          }
          leases[source] = 'lease-$source';
          return {'source': source, 'lease_token': leases[source]};
        case 'releaseDiagnosticOutboxLease':
          final source = args!['source'] as String;
          if (failRelease.remove(source)) return {'released': false};
          if (releaseError.remove(source)) {
            throw PlatformException(code: 'diagnostic_outbox_lease_invalid');
          }
          final token = args['lease_token'] as String;
          final released =
              leases[source] == token ||
              (leases[source] == null && lastReleased[source] == token);
          if (released) {
            leases.remove(source);
            lastReleased[source] = token;
          }
          if (releaseLostReply.remove(source)) {
            throw PlatformException(code: 'diagnostic_outbox_lease_invalid');
          }
          if (pendingRelease != null &&
              source == AndroidActivitySource.usageEvents.wireValue) {
            return pendingRelease!.future;
          }
          return {'released': released};
        case 'activateObservation':
          activationCalls++;
          if (failActivation) {
            throw PlatformException(code: 'foreground_start_failed');
          }
          if (activation != null) return activation!.future;
          if (rejectActivation) {
            return {
              ...activationFields,
              'enabled': false,
              'readiness': 'activity_authority_invalid',
              'observation_status': null,
            };
          }
          return {
            ...activationFields,
            'enabled': true,
            'readiness': 'ready',
            'observation_status': current,
          };
        case 'getObservationStatus':
          return current;
        case 'stopObservation':
          stops.add(args!['observation_id'] as String);
          if (pendingStop != null) return pendingStop!.future;
          if (stopUnknown) return {'outcome': 'unknown', 'status': current};
          if (args['observation_id'] != current['observation_id']) {
            return {'outcome': 'target_changed', 'status': current};
          }
          current = observation(
            id: args['observation_id'] as String,
            revision: (current['revision'] as int) + 1,
            state: 'stopped',
          );
          return {'outcome': 'stopped', 'status': current};
        case 'queryUsageEvents':
          queryCalls++;
          if (failQuery) throw PlatformException(code: 'usage_query_failed');
          if (query != null) return query!.future;
          return batch();
        case 'acknowledgeBatch':
          ackCalls++;
          if (ack != null) return ack!.future;
          return true;
        case 'debugInvalidateObservationNotification':
          return {'accepted': true};
        default:
          throw StateError('unexpected ${call.method}');
      }
    });
    final binding = fixtures.CollectorRig();
    collector = AndroidActivityCollector(
      config: AndroidActivityCollectorConfig(
        enabled: true,
        bindings: AndroidActivityCollectorBindings(
          usageEvents: binding.binding(AndroidActivitySource.usageEvents),
          screenState: binding.binding(AndroidActivitySource.screenState),
        ),
        categoryMapping: const {},
      ),
      stopTimeout: const Duration(milliseconds: 40),
      keyRepository: keys,
      platform: platform,
      clockMs: () => 1000000,
    );
  }

  Map<String, Object?> batch() => {
    'source': AndroidActivitySource.usageEvents.wireValue,
    'permission': 'granted',
    'readiness': queryReadiness,
    'signals': [
      {'type': 'usage_category', 'signal_at_ms': 999999, 'category': 'reading'},
    ],
    'screen_signals': <Object>[],
    'query_started_at_ms': 999990,
    'query_finished_at_ms': 1000000,
    'native_received_at_ms': 1000000,
    'counters': <String, int>{},
    'delivery_epoch': 'epoch',
    'delivery_id': 'batch',
    'observation_status': queryForeignId == null
        ? current
        : observation(id: queryForeignId!),
  };

  Future<Map<Object?, Object?>> emitBatch(Map<String, Object?> value) async {
    final done = Completer<Map<Object?, Object?>>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onBatch', value),
      ),
      (reply) {
        try {
          done.complete(
            const StandardMethodCodec().decodeEnvelope(reply!)
                as Map<Object?, Object?>,
          );
        } catch (error, stack) {
          done.completeError(error, stack);
        }
      },
    );
    return done.future;
  }

  Future<void> emitStatus(Map<String, Object?> value) async {
    current = value;
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onObservationStatus', value),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  Future<void> cleanup() async {
    current = observation(revision: 100, state: 'stopped');
    stopUnknown = false;
    failRelease.clear();
    await collector.stop();
    messenger.setMockMethodCallHandler(channel, null);
    if (root.parent.parent.existsSync()) {
      root.parent.parent.deleteSync(recursive: true);
    }
  }
}

Future<void> ticksUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Rig rig;
  setUp(() async {
    rig = Rig();
    await rig.create();
  });
  tearDown(() async {
    await rig.cleanup();
  });

  test(
    'late activation after stop never restores ready and stops exact own target',
    () async {
      rig.activation = Completer<Object?>();
      final init = rig.collector.initialize();
      await ticksUntil(() => rig.activationCalls == 1);
      final stop = rig.collector.stop();
      rig.activation!.complete({
        ...activationFields,
        'enabled': true,
        'readiness': 'ready',
        'observation_status': observation(),
      });
      await init;
      expect((await stop).completed, isTrue);
      expect(rig.collector.status.ready, isFalse);
      expect(rig.stops, ['own']);
      expect(rig.leases, isEmpty);
    },
  );

  test(
    'terminal callback arriving before activation receipt cannot be overwritten',
    () async {
      rig.activation = Completer<Object?>();
      final init = rig.collector.initialize();
      await ticksUntil(() => rig.activationCalls == 1);
      await rig.emitStatus(observation(revision: 2, state: 'stopped'));
      rig.activation!.complete({
        ...activationFields,
        'enabled': true,
        'readiness': 'ready',
        'observation_status': observation(),
      });
      expect((await init).ready, isFalse);
      expect((await rig.collector.stop()).completed, isTrue);
    },
  );

  test(
    'foreign status is visible but never becomes owned stop target',
    () async {
      await rig.collector.initialize();
      await rig.emitStatus(observation(id: 'successor', revision: 5));
      expect(rig.collector.status.ready, isFalse);
      final result = await rig.collector.stop();
      expect(result.completed, isFalse);
      expect(rig.stops, ['own']);
      expect(rig.collector.status.canQuery, isFalse);
      expect(result.sourceReleases.length, 2);
      expect(rig.leases.length, 2);
      expect(rig.collector.usageOutbox, isNotNull);
    },
  );

  test('foreign query cannot allocate or acknowledge', () async {
    await rig.collector.initialize();
    final before = rig.collector.status.usageSequence;
    rig.queryForeignId = 'successor';
    await rig.collector.pollUsage(startMs: 1, endMs: 1000000);
    expect(rig.collector.status.usageSequence, before);
    expect(rig.ackCalls, 0);
  });

  test(
    'query completing after stop cannot allocate or restore ready',
    () async {
      await rig.collector.initialize();
      rig.query = Completer<Object?>();
      final poll = rig.collector.pollUsage(startMs: 1, endMs: 1000000);
      await ticksUntil(() => rig.queryCalls == 1);
      final delayed = rig.batch();
      await rig.collector.stop();
      rig.query!.complete(delayed);
      await poll;
      expect(rig.ackCalls, 0);
      expect(rig.collector.status.ready, isFalse);
      expect(rig.collector.usageOutbox, isNull);
    },
  );

  test(
    'late ack failure after terminal cannot overwrite stop result',
    () async {
      await rig.collector.initialize();
      rig.ack = Completer<Object?>();
      final poll = rig.collector.pollUsage(startMs: 1, endMs: 1000000);
      await ticksUntil(() => rig.ackCalls == 1);
      await rig.collector.stop();
      rig.ack!.completeError(PlatformException(code: 'delivery_ack_rejected'));
      await poll;
      expect(rig.collector.status.fixedCode, 'collector_disabled');
      expect(rig.collector.status.deliveryDiagnostics['ack_failures'], isNull);
    },
  );

  test(
    'unknown stop retains both stores and returns complete source results',
    () async {
      await rig.collector.initialize();
      rig.stopUnknown = true;
      final result = await rig.collector.stop();
      expect(result.completed, isFalse);
      expect(result.sourceReleases.length, 2);
      expect(
        result.sourceReleases.values.every(
          (r) => r.fileClaimHeld && r.processLeaseHeld,
        ),
        isTrue,
      );
      expect(rig.collector.usageOutbox, isNotNull);
    },
  );

  test(
    'external stopped only degrades; explicit stop closes both stores',
    () async {
      await rig.collector.initialize();
      await rig.emitStatus(observation(revision: 2, state: 'stopped'));
      expect(rig.collector.status.ready, isFalse);
      expect(rig.leases.length, 2);
      expect(rig.collector.usageOutbox, isNotNull);
      expect((await rig.collector.stop()).completed, isTrue);
      expect(rig.leases, isEmpty);
    },
  );

  test(
    'H4 owner delete failure preserves exact bytes and other source succeeds',
    () async {
      await rig.collector.initialize();
      final owner = File(
        '${rig.collector.usageOutbox!.directory.path}/owner.json',
      );
      final bytes = owner.readAsBytesSync();
      rig.collector.debugFailNextOwnerDelete(AndroidActivitySource.usageEvents);
      final result = await rig.collector.stop();
      final usage = result.sourceReleases[AndroidActivitySource.usageEvents]!;
      expect(result.completed, isFalse);
      expect(usage.closeCode, 'owner_lock_cleanup_failed');
      expect(usage.ownerLeaseReleased, isTrue);
      expect(usage.processLeaseHeld, isFalse);
      expect(
        result.sourceReleases[AndroidActivitySource.screenState]!.closeCode,
        'closed',
      );
      expect(owner.readAsBytesSync(), bytes);
      final target =
          rig.collector.releaseTargets[AndroidActivitySource.usageEvents]!;
      final lease = await rig.platform.acquireDiagnosticOutboxLease(
        AndroidActivitySource.usageEvents,
      );
      FileActivityOutboxStore.releaseExactOwner(
        directory: owner.parent,
        integrityKey: await rig.keys.readRequired(),
        target: target,
        processLease: lease,
      );
      await rig.platform.releaseDiagnosticOutboxLease(lease);
      rig.collector.confirmReleasedOwner(
        AndroidActivitySource.usageEvents,
        target,
      );
      expect(rig.collector.releaseTargets, isEmpty);
      expect((await rig.collector.stop()).completed, isTrue);
    },
  );

  test(
    'broker release false remains retryable after store retired then clears on retry',
    () async {
      await rig.collector.initialize();
      rig.failRelease.add(AndroidActivitySource.usageEvents.wireValue);
      final first = await rig.collector.stop();
      expect(first.completed, isFalse);
      expect(rig.collector.usageOutbox, isNull);
      expect(
        first
            .sourceReleases[AndroidActivitySource.usageEvents]!
            .processLeaseHeld,
        isTrue,
      );
      final second = await rig.collector.stop();
      expect(second.completed, isTrue);
      expect(
        second.sourceReleases[AndroidActivitySource.usageEvents]!.closeCode,
        'closed',
      );
      expect(rig.leases, isEmpty);
    },
  );

  test('lifecycle running cannot erase failed query readiness', () async {
    await rig.collector.initialize();
    rig.failQuery = true;
    await rig.collector.pollUsage(startMs: 1, endMs: 1000000);
    expect(rig.collector.status.ready, isFalse);
    await rig.emitStatus(observation(revision: 2));
    expect(rig.collector.status.ready, isFalse);
    expect(rig.collector.status.fixedCode, 'usage_query_failed');
    expect(rig.collector.status.canQuery, isTrue);
    rig.failQuery = false;
    await rig.collector.pollUsage(startMs: 1, endMs: 1000000);
    expect(rig.queryCalls, 2);
    expect(rig.collector.status.ready, isTrue);
  });

  test(
    'nonempty preflight releases newly acquired leases without activation',
    () async {
      Directory(
        '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}',
      ).createSync();
      File(
        '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}/state.json',
      ).writeAsStringSync('preserve');
      expect(
        (await rig.collector.initialize()).fixedCode,
        'recovery_authority_required',
      );
      expect(rig.activationCalls, 0);
      expect(rig.leases, isEmpty);
    },
  );

  test(
    'stop during first lease acquisition releases it without second acquire',
    () async {
      rig.acquire = Completer<Object?>();
      final init = rig.collector.initialize();
      await ticksUntil(() => rig.acquireCalls == 1);
      final stop = rig.collector.stop();
      final source = AndroidActivitySource.usageEvents.wireValue;
      rig.leases[source] = 'late';
      rig.acquire!.complete({'source': source, 'lease_token': 'late'});
      await init;
      await stop;
      expect(rig.acquireCalls, 1);
      expect(rig.activationCalls, 0);
      expect(rig.leases, isEmpty);
    },
  );

  test(
    'activation transport failure never closes potentially service-owned stores',
    () async {
      rig.failActivation = true;
      expect((await rig.collector.initialize()).ready, isFalse);
      final result = await rig.collector.stop();
      expect(result.completed, isFalse);
      expect(rig.leases.length, 2);
      expect(rig.collector.usageOutbox!.ownerLeaseReleased, isFalse);
      // No exact activation identity: fixture explicitly releases its own handles.
      rig.collector.usageOutbox!.releaseProcessLeaseForTest();
      rig.collector.screenOutbox!.releaseProcessLeaseForTest();
    },
  );

  test(
    'rejected activation null identity safely releases unused stores',
    () async {
      rig.rejectActivation = true;
      expect(
        (await rig.collector.initialize()).fixedCode,
        'activity_authority_invalid',
      );
      expect(rig.leases, isEmpty);
      expect(rig.collector.usageOutbox, isNull);
    },
  );
  test('active send refusal can retry close after the attempt exits', () async {
    await rig.collector.initialize();
    await rig.collector.pollUsage(startMs: 1, endMs: 1000000);
    final store = rig.collector.usageOutbox!;
    final ticket = store.beginNextAttempt()!;
    final first = await rig.collector.stop();
    expect(first.completed, isFalse);
    expect(
      first.sourceReleases[AndroidActivitySource.usageEvents]!.closeCode,
      'attempt_in_progress',
    );
    expect(store.ownerLeaseReleased, isFalse);
    store.abandonAttempt(ticket);
    expect((await rig.collector.stop()).completed, isTrue);
  });

  test(
    'unanswered activation gives bounded stop unknown and late receipt stays disabled',
    () async {
      rig.activation = Completer<Object?>();
      final init = rig.collector.initialize();
      await ticksUntil(() => rig.activationCalls == 1);
      final result = await rig.collector.stop();
      expect(result.nativeOutcome, AndroidNativeStopOutcome.unknown);
      expect(result.completed, isFalse);
      expect(rig.leases.length, 2);
      rig.activation!.complete({
        ...activationFields,
        'enabled': true,
        'readiness': 'ready',
        'observation_status': observation(),
      });
      await init;
      expect(rig.collector.status.ready, isFalse);
      expect((await rig.collector.stop()).completed, isTrue);
    },
  );

  test(
    'unanswered native stop is bounded and late result cannot close resources',
    () async {
      await rig.collector.initialize();
      rig.pendingStop = Completer<Object?>();
      final first = await rig.collector.stop();
      expect(first.nativeOutcome, AndroidNativeStopOutcome.unknown);
      expect(rig.leases.length, 2);
      rig.pendingStop!.complete({
        'outcome': 'stopped',
        'status': observation(revision: 2, state: 'stopped'),
      });
      await Future<void>.delayed(Duration.zero);
      expect(rig.leases.length, 2);
      rig.pendingStop = null;
      expect((await rig.collector.stop()).completed, isTrue);
    },
  );

  test(
    'new native session cannot reuse an old-session terminal receipt',
    () async {
      await rig.collector.initialize();
      await rig.emitStatus({
        ...observation(id: 'new', revision: 0),
        'session_id': 'new-session',
      });
      rig.current = observation(revision: 5, state: 'stopped');
      final result = await rig.collector.stop();
      expect(result.completed, isFalse);
      expect(rig.leases.length, 2);
      rig.collector.usageOutbox!.releaseProcessLeaseForTest();
      rig.collector.screenOutbox!.releaseProcessLeaseForTest();
    },
  );
  test(
    'foreign and post-stop proactive batches return retry without new sequence',
    () async {
      await rig.collector.initialize();
      final before = rig.collector.status.usageSequence;
      final foreign = {
        ...rig.batch(),
        'observation_status': observation(id: 'foreign'),
      };
      expect((await rig.emitBatch(foreign))['dispositions'], ['retry']);
      expect(rig.collector.status.usageSequence, before);
      final old = rig.batch();
      await rig.collector.stop();
      expect((await rig.emitBatch(old))['dispositions'], ['retry']);
      expect(rig.collector.status.ready, isFalse);
    },
  );

  test('same revision conflicting status cannot keep readiness', () async {
    await rig.collector.initialize();
    await rig.emitStatus({...observation(), 'reason': 'device_locked'});
    expect(rig.collector.status.ready, isFalse);
    expect(rig.collector.status.fixedCode, 'observation_status_invalid');
  });
  test(
    'lost broker release reply retries the same lease and clears failure',
    () async {
      await rig.collector.initialize();
      rig.releaseLostReply.add(AndroidActivitySource.usageEvents.wireValue);
      final first = await rig.collector.stop();
      expect(first.completed, isFalse);
      expect(
        rig.leases,
        isEmpty,
      ); // Native already released; Dart cannot assume it.
      expect(
        first
            .sourceReleases[AndroidActivitySource.usageEvents]!
            .processLeaseHeld,
        isTrue,
      );
      expect((await rig.collector.stop()).completed, isTrue);
      expect(rig.collector.status.fixedCode, 'collector_disabled');
    },
  );
  for (final throwError in [false, true]) {
    test(
      'preflight cleanup ${throwError ? "error" : "false"} returns held lease snapshot and explicit retry retires',
      () async {
        Directory(
          '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}',
        ).createSync();
        File(
          '${rig.root.path}/${AndroidActivitySource.usageEvents.wireValue}/state.json',
        ).writeAsStringSync('preserve');
        final failure = throwError ? rig.releaseError : rig.failRelease;
        failure.add(AndroidActivitySource.usageEvents.wireValue);
        final initial = await rig.collector.initialize();
        expect(initial.fixedCode, 'recovery_authority_required');
        expect(initial.sourceReleases.length, 2);
        expect(
          initial
              .sourceReleases[AndroidActivitySource.usageEvents]!
              .processLeaseHeld,
          isTrue,
        );
        expect(initial.canRetireWithoutObservation, isFalse);
        expect(rig.collector.usageOutbox, isNull);
        final stopped = await rig.collector.stop();
        expect(stopped.noNativeAttempt, isTrue);
        expect(stopped.nativeOutcome, isNull);
        expect(stopped.nativeStatus, isNull);
        expect(stopped.completed, isTrue);
        expect(rig.collector.status.canRetireWithoutObservation, isTrue);
        expect(rig.leases, isEmpty);
      },
    );
  }
  test(
    'lost release response has bounded stop retaining token and safe late completion',
    () async {
      await rig.collector.initialize();
      rig.pendingRelease = Completer<Object?>();
      final first = await rig.collector.stop();
      expect(first.completed, isFalse);
      expect(
        first
            .sourceReleases[AndroidActivitySource.usageEvents]!
            .processLeaseHeld,
        isTrue,
      );
      expect(rig.collector.status.canRetireWithoutObservation, isFalse);
      rig.pendingRelease!.complete({'released': true});
      await Future<void>.delayed(Duration.zero);
      rig.pendingRelease = null;
      expect((await rig.collector.stop()).completed, isTrue);
    },
  );
  test(
    'pending acquire cannot grant no-attempt retirement and its late lease is reclaimed',
    () async {
      rig.acquire = Completer<Object?>();
      final init = rig.collector.initialize();
      await ticksUntil(() => rig.acquireCalls == 1);
      final unknown = await rig.collector.stop();
      expect(unknown.nativeOutcome, AndroidNativeStopOutcome.unknown);
      expect(unknown.noNativeAttempt, isFalse);
      expect(unknown.completed, isFalse);
      expect(rig.collector.status.canRetireWithoutObservation, isFalse);
      final source = AndroidActivitySource.usageEvents.wireValue;
      rig.leases[source] = 'late-preflight';
      rig.acquire!.complete({
        'source': source,
        'lease_token': 'late-preflight',
      });
      final finalStatus = await init;
      expect(finalStatus.canRetireWithoutObservation, isTrue);
      expect(rig.leases, isEmpty);
      expect((await rig.collector.stop()).completed, isTrue);
    },
  );
}
