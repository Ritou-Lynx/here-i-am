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

Matcher hasCode(String code) =>
    isA<AndroidActivityException>().having((error) => error.code, 'code', code);

final class MemoryIntegrityStorage implements ActivityIntegrityStorage {
  String? value;
  var writes = 0;
  var deletes = 0;
  var failRead = false;
  var failWrite = false;
  var failDelete = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('private read failure');
    return value;
  }

  @override
  Future<void> write(String key, String newValue) async {
    if (failWrite) throw StateError('private write failure');
    writes++;
    value = newValue;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('private delete failure');
    deletes++;
    value = null;
  }
}

final class FakeActivitySignalPlatform
    implements AndroidActivitySignalPlatform, AndroidActivityDeliveryPlatform {
  FakeActivitySignalPlatform(this.root);

  AndroidNativeBatchHandler? batchHandler;
  bool failAck = false;
  @override
  void setBatchHandler(AndroidNativeBatchHandler? handler) =>
      batchHandler = handler;
  @override
  Future<void> acknowledgeBatch(
      AndroidNativeUsageBatch batch, List<String> outcomes) async {
    if (failAck) throw const AndroidActivityException('delivery_ack_rejected');
  }

  AndroidPrivateOutboxRoot root;
  AndroidNativeSignalHandler? handler;
  AndroidNativeUsageBatch batch = const AndroidNativeUsageBatch(
    permission: UsageAccess.denied,
    readiness: 'usage_permission_denied',
    signals: [],
    counters: {},
  );
  AndroidActivityException? queryError;
  var rootCalls = 0;
  var activationCalls = 0;
  var queryCalls = 0;
  var deactivationCalls = 0;
  bool? activationEnabled;
  bool? activationIntegrityReady;
  Set<AndroidActivitySource>? activationSources;
  Map<String, String>? activationMapping;

  @override
  void setSignalHandler(AndroidNativeSignalHandler? value) => handler = value;

  @override
  Future<AndroidPrivateOutboxRoot> getOutboxRoot() async {
    rootCalls++;
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
    activationEnabled = enabled;
    activationIntegrityReady = integrityAuthorityReady;
    activationSources = boundSources;
    activationMapping = categoryMapping;
    return const AndroidNativeActivation(enabled: true, readiness: 'ready');
  }

  @override
  Future<AndroidNativeUsageBatch> queryUsageEvents({
    required int startMs,
    required int endMs,
  }) async {
    queryCalls++;
    final error = queryError;
    if (error != null) throw error;
    return batch;
  }

  @override
  Future<void> deactivate() async {
    deactivationCalls++;
  }

  Future<void> emitScreen(Map<String, Object?> signal) async {
    await handler?.call(signal);
  }
}

final class CollectorRig {
  CollectorRig({
    this.enabled = true,
    this.includeUsageBinding = true,
    this.includeScreenBinding = true,
    this.storageScope = 'no_backup_private',
  });

  final bool enabled;
  final bool includeUsageBinding;
  final bool includeScreenBinding;
  final String storageScope;
  int now = 1000000;
  late final Directory scratch;
  late final Directory noBackupRoot;
  late final MemoryIntegrityStorage storage;
  late final ActivityIntegrityKeyRepository keys;
  late final FakeActivitySignalPlatform platform;
  late final AndroidActivityCollector collector;
  final audit = <String>[];

  Future<void> initialize({bool provisionKey = true}) async {
    scratch = await Directory.systemTemp.createTemp('mda2_a3_collector_');
    noBackupRoot = Directory(
      '${scratch.path}${Platform.pathSeparator}no_backup${Platform.pathSeparator}mda2_activity',
    );
    storage = MemoryIntegrityStorage();
    keys = ActivityIntegrityKeyRepository(
      storage: storage,
      randomBytes: (length) => List<int>.generate(length, (index) => index),
    );
    if (provisionKey) await keys.provision();
    platform = FakeActivitySignalPlatform(
      AndroidPrivateOutboxRoot(
        path: noBackupRoot.path,
        storageScope: storageScope,
      ),
    );
    collector = AndroidActivityCollector(
      config: AndroidActivityCollectorConfig(
        enabled: enabled,
        bindings: AndroidActivityCollectorBindings(
          usageEvents: includeUsageBinding
              ? binding(AndroidActivitySource.usageEvents)
              : null,
          screenState: includeScreenBinding
              ? binding(AndroidActivitySource.screenState)
              : null,
        ),
        categoryMapping: const {
          'private.chat.identifier': 'chat',
          'private.reader.identifier': 'reading',
        },
        capacityPerSource: 16,
        ttlMs: 300000,
      ),
      keyRepository: keys,
      platform: platform,
      clockMs: () => now,
      audit: (code, _) => audit.add(code),
    );
  }

  SyntheticProbeBinding binding(AndroidActivitySource source) =>
      SyntheticProbeBinding(
        deviceId: 'synthetic-android',
        probeId: source == AndroidActivitySource.usageEvents
            ? 'synthetic-usage'
            : 'synthetic-screen',
        serverIssuedPrefix: List.filled(
          22,
          source == AndroidActivitySource.usageEvents ? 'U' : 'S',
        ).join(),
        source: source,
        reportIntervalMs: 30000,
        expirySloMs: 300000,
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

  Future<void> dispose() async {
    await collector.dispose();
    if (scratch.existsSync()) await scratch.delete(recursive: true);
  }
}

// Explicit transient-capacity fake around the existing sequence authority.
// The production file store has no capacity-release API; that case remains retry.
final class TransientCapacityOutbox implements ActivityOutboxStore {
  TransientCapacityOutbox(this.inner);
  final MemoryActivityOutbox inner;
  bool unavailable = true;
  @override SyntheticProbeBinding get binding => inner.binding;
  @override int get capacity => inner.capacity;
  @override int get lastAllocatedSequence => inner.lastAllocatedSequence;
  @override int? get lastSignalAt => inner.lastSignalAt;
  @override bool get lineageBlocked => inner.lineageBlocked;
  @override bool get restored => inner.restored;
  @override bool get collectorAttached => inner.collectorAttached;
  @override set collectorAttached(bool value) => inner.collectorAttached = value;
  @override SyntheticCoreContact get lastContact => inner.lastContact;
  @override void assertOwned() => inner.assertOwned();
  @override void acknowledgeRestartGap() => inner.acknowledgeRestartGap();
  @override AndroidActivityEvent enqueue({required String kind, required int atMs, required int ttlMs, required String confidence, Map<String,Object?> payload = const {}}) {
    if (unavailable) throw const AndroidActivityException('outbox_full');
    return inner.enqueue(kind:kind, atMs:atMs, ttlMs:ttlMs, confidence:confidence, payload:payload);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AndroidNativeUsageBatch deliveryBatch(
          String id, List<Map<String, Object?>> screen,
          {Map<String, int> counters = const {}}) =>
      AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: const [],
        screenSignals: screen,
        deliveryEpoch: 'epoch-a',
        deliveryId: id,
        counters: counters,
      );

  test('real MethodChannel proactive batch returns epoch-bound durable dispositions', () async {
    const channel = MethodChannel('a3f_r1_proactive_receipt');
    final platform = MethodChannelAndroidActivitySignalPlatform(channel: channel);
    platform.setBatchHandler((batch) async {
      expect(batch.deliveryEpoch, 'epoch-a');
      expect(batch.deliveryId, '1');
      expect(batch.screenSignals.single['signal_at_ms'], 1000);
      return ['accepted'];
    });
    addTearDown(()=>platform.setBatchHandler(null));
    final receipt = Completer<Object?>();
    ServicesBinding.instance.channelBuffers.push(channel.name, const StandardMethodCodec().encodeMethodCall(const MethodCall('onBatch', {
      'source':'android_usage_events','permission':'granted','readiness':'ready',
      'signals': [], 'screen_signals':[{'type':'user_present','signal_at_ms':1000}],
      'query_started_at_ms':1001,'query_finished_at_ms':1002,'native_received_at_ms':1003,
      'counters':{'expired_before_acceptance':2},'delivery_epoch':'epoch-a','delivery_id':'1',
      'observation_status': {'version':1,'session_id':'session','observation_id':'own','revision':1,'state':'running','enabled':true,'reason':'ready'},
    })), (reply) { receipt.complete(const StandardMethodCodec().decodeEnvelope(reply!)); });
    expect(await receipt.future, {'delivery_epoch':'epoch-a','delivery_id':'1','dispositions':['accepted']});
  });

  test('transient capacity rejection lifts without changing subscription or occurrence', () {
    final rig = CollectorRig();
    final box = TransientCapacityOutbox(MemoryActivityOutbox.forSyntheticPairing(rig.binding(AndroidActivitySource.screenState)));
    var now = 1000;
    final normalizer = AndroidActivityNormalizer(outbox:box, clockMs:()=>now, ttlMs:300000);
    now = 1100;
    const signal = <String,Object?>{'type':'screen_interactive','signal_at_ms':1050};
    expect(()=>normalizer.acceptDeliverySignal(signal), throwsA(hasCode('outbox_full')));
    expect(box.lastAllocatedSequence, 0);
    box.unavailable = false;
    now = 1200;
    expect(normalizer.deliveryRejectionAt(1050), isNull);
    final event = normalizer.acceptDeliverySignal(signal)!;
    expect(event.signalAtMs, 1050);
    expect(event.originSequence, 1);
    expect(box.lastAllocatedSequence, 1);
  });

  test('proactive batch durable acceptance lost ACK repeats no sequence',
      () async {
    final rig = CollectorRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.collector.initialize();
    rig.now += 10;
    final batch = deliveryBatch('1', [
      {'type': 'screen_interactive', 'signal_at_ms': rig.now}
    ]);
    expect(await rig.platform.batchHandler!(batch), ['accepted']);
    expect(rig.collector.status.screenSequence, 1);
    rig.now += 10;
    expect(await rig.platform.batchHandler!(batch), ['accepted']);
    expect(rig.collector.status.screenSequence, 1);
    rig.platform.batch = batch;
    rig.platform.failAck = true;
    await rig.collector.pollUsage(startMs: rig.now - 20, endMs: rig.now + 1);
    expect(rig.collector.status.deliveryDiagnostics['ack_failures'], 1);
    expect(rig.collector.status.screenSequence, 1);
  });

  test(
      'late older occurrence reports omission without freezing clock or editing time',
      () async {
    final rig = CollectorRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.collector.initialize();
    rig.now += 100;
    await rig.platform.batchHandler!(deliveryBatch('1', [
      {'type': 'user_present', 'signal_at_ms': rig.now}
    ]));
    expect(
        await rig.platform.batchHandler!(deliveryBatch('2', [
          {'type': 'screen_interactive', 'signal_at_ms': rig.now - 50}
        ])),
        ['late_out_of_order']);
    expect(rig.collector.screenOutbox!.lineageBlocked, isFalse);
    expect(rig.collector.status.screen!.coverage, AndroidCoverage.gap);
    rig.now += 10;
    await rig.platform.batchHandler!(deliveryBatch('3', [
      {'type': 'screen_interactive', 'signal_at_ms': rig.now}
    ]));
    expect(rig.collector.status.screen!.coverage, AndroidCoverage.fresh);
    expect(rig.collector.status.deliveryDiagnostics['late_out_of_order'], 1);
    expect(rig.collector.status.screenSequence, 2);
  });

  test(
      'two expired screens and valid unlock keep explicit omissions and original occurrence',
      () async {
    final rig = CollectorRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.collector.initialize();
    final opened = rig.now;
    rig.now += 600000;
    final batch = deliveryBatch('1', [
      {'type': 'screen_non_interactive', 'signal_at_ms': opened + 100},
      {'type': 'screen_interactive', 'signal_at_ms': opened + 101},
      {'type': 'user_present', 'signal_at_ms': rig.now - 1000},
    ]);
    expect(await rig.platform.batchHandler!(batch),
        ['expired_before_acceptance', 'expired_before_acceptance', 'accepted']);
    expect(rig.collector.status.screenSequence, 1);
    expect(rig.collector.screenOutbox!.durableRecords.single.event.signalAtMs,
        rig.now - 1000);
    expect(
        rig.collector.status.deliveryDiagnostics['expired_before_acceptance'],
        2);
    await rig.platform.batchHandler!(batch);
    expect(
        rig.collector.status.deliveryDiagnostics['expired_before_acceptance'],
        2);
  });

  test(
      'same millisecond kinds each durable once and diagnostics-only batches surface loss',
      () async {
    final rig = CollectorRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.collector.initialize();
    rig.now += 1;
    final batch = deliveryBatch(
        '1',
        ['screen_interactive', 'screen_non_interactive', 'user_present']
            .map((type) =>
                <String, Object?>{'type': type, 'signal_at_ms': rig.now})
            .toList());
    expect(await rig.platform.batchHandler!(batch),
        ['accepted', 'accepted', 'accepted']);
    expect(rig.collector.status.screenSequence, 3);
    await rig.platform.batchHandler!(
        deliveryBatch('', [], counters: {'expired_before_acceptance': 2}));
    expect(
        rig.collector.status
            .deliveryDiagnostics['native_expired_before_acceptance'],
        2);
    expect(rig.collector.status.screen!.coverage, AndroidCoverage.gap);
  });

  test(
      'durable enqueue failure stays retry after accepted prefix and cannot double allocate',
      () async {
    final rig = CollectorRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    await rig.collector.initialize();
    rig.now += 1;
    final batch = deliveryBatch(
        '1',
        List.generate(
            17,
            (i) => <String, Object?>{
                  'type': 'screen_interactive',
                  'signal_at_ms': rig.now + i
                }));
    rig.now += 17;
    final first = await rig.platform.batchHandler!(batch);
    expect(first.take(16), everyElement('accepted'));
    expect(first.last, 'retry');
    expect(rig.collector.status.screenSequence, 16);
    final retry = await rig.platform.batchHandler!(batch);
    expect(retry.last, 'retry');
    expect(rig.collector.status.screenSequence, 16);
  });

  group('dedicated integrity authority', () {
    test(
      'explicit provision generates once and reuses the same 32 bytes',
      () async {
        final storage = MemoryIntegrityStorage();
        final repository = ActivityIntegrityKeyRepository(
          storage: storage,
          randomBytes: (length) => List<int>.generate(length, (index) => index),
        );
        final first = await repository.provision();
        final second = await repository.provision();
        final loaded = await repository.readRequired();
        expect(first, hasLength(32));
        expect(second, first);
        expect(loaded, first);
        expect(storage.writes, 1);
        expect(storage.value, isNot(contains('token')));
      },
    );

    test(
      'missing corrupt unavailable and cleared authorities fail closed',
      () async {
        final storage = MemoryIntegrityStorage();
        final repository = ActivityIntegrityKeyRepository(storage: storage);
        await expectLater(
          repository.readRequired(),
          throwsA(hasCode('integrity_key_missing')),
        );
        storage.value = 'corrupt';
        await expectLater(
          repository.readRequired(),
          throwsA(hasCode('integrity_key_invalid')),
        );
        storage.failRead = true;
        await expectLater(
          repository.readRequired(),
          throwsA(hasCode('integrity_key_unavailable')),
        );
        storage.failRead = false;
        storage.value = null;
        await repository.provision();
        await repository.clear();
        expect(storage.deletes, 1);
        await expectLater(
          repository.readRequired(),
          throwsA(hasCode('integrity_key_missing')),
        );
      },
    );

    test('storage write and clear failures expose fixed codes', () async {
      final writeStorage = MemoryIntegrityStorage()..failWrite = true;
      await expectLater(
        ActivityIntegrityKeyRepository(storage: writeStorage).provision(),
        throwsA(hasCode('integrity_key_write_failed')),
      );
      final clearStorage = MemoryIntegrityStorage()..failDelete = true;
      await expectLater(
        ActivityIntegrityKeyRepository(storage: clearStorage).clear(),
        throwsA(hasCode('integrity_key_clear_failed')),
      );
    });
  });

  test('collector configuration defaults to disabled', () {
    const config = AndroidActivityCollectorConfig(
      bindings: AndroidActivityCollectorBindings(
        usageEvents: null,
        screenState: null,
      ),
      categoryMapping: {},
    );
    expect(config.enabled, isFalse);
  });

  test(
    'collector is disabled by default configuration without native effects',
    () async {
      final rig = CollectorRig(enabled: false);
      await rig.initialize();
      addTearDown(rig.dispose);
      final status = await rig.collector.initialize();
      expect(status.ready, isFalse);
      expect(status.fixedCode, 'collector_disabled');
      expect(status.usageSequence, 0);
      expect(status.screenSequence, 0);
      expect(rig.platform.rootCalls, 0);
      expect(rig.platform.activationCalls, 0);
      expect(rig.noBackupRoot.existsSync(), isFalse);
    },
  );

  for (final missing in ['binding', 'key']) {
    test(
      'missing $missing fails closed before receiver query or sequence',
      () async {
        final rig = CollectorRig(includeScreenBinding: missing != 'binding');
        await rig.initialize(provisionKey: missing != 'key');
        addTearDown(rig.dispose);
        final status = await rig.collector.initialize();
        expect(status.ready, isFalse);
        expect(
          status.fixedCode,
          missing == 'key' ? 'integrity_key_missing' : 'source_binding_missing',
        );
        expect(rig.platform.rootCalls, 0);
        expect(rig.platform.activationCalls, 0);
        expect(rig.platform.queryCalls, 0);
        expect(status.usageSequence, 0);
        expect(status.screenSequence, 0);
        expect(rig.noBackupRoot.existsSync(), isFalse);
      },
    );
  }

  test(
    'two sources use private independent directories and sequences',
    () async {
      final rig = CollectorRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      expect((await rig.collector.initialize()).ready, isTrue);
      expect(rig.platform.activationEnabled, isTrue);
      expect(rig.platform.activationIntegrityReady, isTrue);
      expect(
        rig.platform.activationSources,
        AndroidActivitySource.values.toSet(),
      );

      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: [
          {
            'type': 'usage_category',
            'signal_at_ms': rig.now,
            'category': 'reading',
          },
        ],
        counters: const {'query_failures': 0},
      );
      await rig.collector.pollUsage(startMs: rig.now - 100, endMs: rig.now + 1);
      await rig.platform.emitScreen({
        'type': 'user_present',
        'signal_at_ms': rig.now,
      });

      final status = rig.collector.status;
      expect(status.usageSequence, 2); // permission readiness + one activity
      expect(status.screenSequence, 1);
      expect(
        rig.collector.usageOutbox!.directory.path,
        contains('android_usage_events'),
      );
      expect(
        rig.collector.screenOutbox!.directory.path,
        contains('android_screen_state'),
      );
      expect(
        rig.collector.usageOutbox!.directory.path,
        isNot(rig.collector.screenOutbox!.directory.path),
      );
      expect(rig.platform.root.storageScope, 'no_backup_private');

      final persisted = rig.noBackupRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(persisted, isNot(contains('private.reader.identifier')));
      expect(persisted, isNot(contains('appName')));
      expect(persisted, isNot(contains('UsageEvents')));
      expect(persisted, isNot(contains('token')));
    },
  );

  test(
    'non no-backup root fails before native activation and allocation',
    () async {
      final rig = CollectorRig(storageScope: 'backup_eligible');
      await rig.initialize();
      addTearDown(rig.dispose);
      final status = await rig.collector.initialize();
      expect(status.fixedCode, 'private_outbox_root_invalid');
      expect(status.ready, isFalse);
      expect(rig.platform.activationCalls, 0);
      expect(status.usageSequence, 0);
      expect(status.screenSequence, 0);
    },
  );

  for (final source in AndroidActivitySource.values) {
    test(
      'dispose releases a frozen ${source.wireValue} owner for an exact successor',
      () async {
        final rig = CollectorRig();
        await rig.initialize();
        addTearDown(rig.dispose);
        expect((await rig.collector.initialize()).ready, isTrue);
        final store = source == AndroidActivitySource.usageEvents
            ? rig.collector.usageOutbox!
            : rig.collector.screenOutbox!;
        final ownerFile = File(
          '${store.directory.path}${Platform.pathSeparator}owner.json',
        );
        expect(
          () => store.enqueue(
            kind: 'not.allowed',
            atMs: rig.now,
            ttlMs: 300000,
            confidence: 'synthetic',
          ),
          throwsA(hasCode('scope_denied')),
        );
        expect(store.frozenCode, 'scope_denied');
        expect(store.lineageBlocked, isTrue);
        expect(ownerFile.existsSync(), isTrue);

        await rig.collector.dispose();

        expect(ownerFile.existsSync(), isFalse);
        final key = await rig.keys.readRequired();
        final successor = FileActivityOutboxStore.open(
          directory: store.directory,
          binding: rig.binding(source),
          capacity: 16,
          integrityKey: key,
          ageProofProvider: HmacActivityAgeProofProvider(integrityKey: key),
          clockMs: () => rig.now,
          audit: (code, _) => rig.audit.add(code),
        );
        expect(successor.bindingDigest, store.bindingDigest);
        expect(successor.frozenCode, 'scope_denied');
        expect(successor.lineageBlocked, isTrue);
        expect(ownerFile.existsSync(), isTrue);
        successor.close();
        expect(ownerFile.existsSync(), isFalse);
        expect(rig.audit, contains('outbox_closed'));
      },
    );
  }

  test(
    'permission revocation clears freshness and ignores supplied old activity',
    () async {
      final rig = CollectorRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.collector.initialize();
      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: [
          {
            'type': 'usage_category',
            'signal_at_ms': rig.now,
            'category': 'chat',
          },
        ],
        counters: const {},
      );
      await rig.collector.pollUsage(startMs: rig.now - 1, endMs: rig.now + 1);
      final before = rig.collector.status.usageSequence;
      rig.now += 10;
      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.revoked,
        readiness: 'usage_permission_revoked',
        signals: [
          {
            'type': 'usage_category',
            'signal_at_ms': rig.now - 10,
            'category': 'chat',
          },
        ],
        counters: const {},
      );
      final status = await rig.collector.pollUsage(
        startMs: rig.now - 20,
        endMs: rig.now + 1,
      );
      expect(status.usage?.permission, UsageAccess.revoked);
      expect(status.usage?.coverage, AndroidCoverage.permissionUnavailable);
      expect(status.usage?.lastObservationAtMs, isNull);
      expect(status.usageSequence, before + 1); // only permission diagnostic
    },
  );

  test(
    'duplicates are suppressed and out-of-order or future signals allocate nothing',
    () async {
      final rig = CollectorRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.collector.initialize();
      final signal = {
        'type': 'usage_category',
        'signal_at_ms': rig.now,
        'category': 'reading',
      };
      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: [signal, Map<String, Object?>.from(signal)],
        counters: const {},
      );
      await rig.collector.pollUsage(startMs: rig.now - 1, endMs: rig.now + 1);
      expect(rig.collector.status.usageSequence, 2);

      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: [
          {
            'type': 'usage_category',
            'signal_at_ms': rig.now - 1,
            'category': 'work',
          },
        ],
        counters: const {},
      );
      await rig.collector.pollUsage(startMs: rig.now - 2, endMs: rig.now + 1);
      expect(rig.collector.status.usageSequence, 2);
      expect(rig.collector.status.fixedCode, 'ready');

      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: [
          {
            'type': 'usage_category',
            'signal_at_ms': rig.now + 1,
            'category': 'work',
          },
        ],
        counters: const {},
      );
      await rig.collector.pollUsage(startMs: rig.now, endMs: rig.now + 2);
      expect(rig.collector.status.usageSequence, 2);
      expect(rig.collector.status.fixedCode, 'clock_uncertain');
    },
  );

  test(
    'fixed native query failure becomes a gap without private exception text',
    () async {
      final rig = CollectorRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.collector.initialize();
      rig.platform.queryError = const AndroidActivityException(
        'usage_query_failed',
      );
      final status = await rig.collector.pollUsage(
        startMs: rig.now - 1,
        endMs: rig.now + 1,
      );
      expect(status.fixedCode, 'usage_query_failed');
      expect(status.usage?.coverage, AndroidCoverage.gap);
      expect(status.usageSequence, 1);
      expect(rig.audit, contains('usage_query_failed'));
      expect(rig.audit.join(), isNot(contains('private')));
    },
  );

  test(
    'MethodChannel boundary rejects native private fields without echo',
    () async {
      const channel = MethodChannel('mda2_activity_signal_private_field_test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        return {
          'source': 'android_usage_events',
          'permission': 'granted',
          'readiness': 'ready',
          'signals': [
            {
              'type': 'usage_category',
              'signal_at_ms': 1000,
              'category': 'chat',
              'packageName': 'private.chat.identifier',
            },
          ],
          'screen_signals': const [],
          'query_started_at_ms': 1000,
          'query_finished_at_ms': 1000,
          'native_received_at_ms': 1000,
          'counters': {'query_failures': 0, 'dropped_events': 0},
          'observation_status': {'version':1,'session_id':'session','observation_id':'own','revision':1,'state':'running','enabled':true,'reason':'ready'},
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
      );
      Object? failure;
      try {
        await platform.queryUsageEvents(startMs: 0, endMs: 1001);
      } catch (error) {
        failure = error;
      }
      expect(failure, hasCode('native_result_invalid'));
      expect(failure.toString(), isNot(contains('private.chat.identifier')));
    },
  );

  test(
    'native activation receives readiness facts but no key or binding secret',
    () async {
      const channel = MethodChannel('mda2_activity_signal_activation_test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<Object?, Object?>? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = Map<Object?, Object?>.from(call.arguments as Map);
        return {'enabled': true, 'readiness': 'ready'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
      );
      await platform.activate(
        enabled: true,
        integrityAuthorityReady: true,
        boundSources: AndroidActivitySource.values.toSet(),
        categoryMapping: const {'private.chat.identifier': 'chat'},
      );
      expect(captured?.keys.toSet(), {
        'enabled',
        'integrity_authority_ready',
        'bound_sources',
        'category_mapping',
      });
      expect(captured.toString(), isNot(contains('integrity_key')));
      expect(captured.toString(), isNot(contains('UUUUUUUUUUUUUUUUUUUUUU')));
    },
  );

  test(
    'sealed native screen signals retain occurrence time separate from query and ingest clocks',
    () async {
      final rig = CollectorRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      await rig.collector.initialize();
      rig.platform.batch = AndroidNativeUsageBatch(
        permission: UsageAccess.granted,
        readiness: 'ready',
        signals: const [],
        screenSignals: [
          {'type': 'user_present', 'signal_at_ms': rig.now},
        ],
        queryStartedAtMs: rig.now + 10,
        queryFinishedAtMs: rig.now + 11,
        nativeReceivedAtMs: rig.now + 12,
        dartIngestAtMs: rig.now + 13,
        counters: const {'query_failures': 0, 'dropped_events': 0},
      );
      final status = await rig.collector.pollUsage(
        startMs: rig.now - 1,
        endMs: rig.now + 1,
      );
      final wire =
          rig.collector.screenOutbox!.durableRecords.single.event.toJson();
      expect(wire['kind'], 'session.unlocked');
      expect(wire['signal_at_ms'], rig.now);
      expect(status.queryStartedAtMs, rig.now + 10);
      expect(status.queryFinishedAtMs, rig.now + 11);
      expect(status.nativeReceivedAtMs, rig.now + 12);
      expect(status.dartIngestAtMs, rig.now + 13);
    },
  );

  test(
    'MethodChannel keeps four clocks distinct and rejects raw identity',
    () async {
      const channel = MethodChannel('mda2_activity_signal_timing_test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        return {
          'source': 'android_usage_events',
          'permission': 'granted',
          'readiness': 'ready',
          'signals': const [],
          'screen_signals': const [
            {'type': 'screen_non_interactive', 'signal_at_ms': 2201},
          ],
          'query_started_at_ms': 2210,
          'query_finished_at_ms': 2211,
          'native_received_at_ms': 2212,
          'counters': {'query_failures': 0, 'dropped_events': 0},
          'observation_status': {'version':1,'session_id':'session','observation_id':'own','revision':1,'state':'running','enabled':true,'reason':'ready'},
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final batch = await MethodChannelAndroidActivitySignalPlatform(
        channel: channel,
      ).queryUsageEvents(startMs: 2000, endMs: 2300);
      expect(batch.screenSignals.single['signal_at_ms'], 2201);
      expect(batch.queryStartedAtMs, 2210);
      expect(batch.queryFinishedAtMs, 2211);
      expect(batch.nativeReceivedAtMs, 2212);
      expect(batch.dartIngestAtMs, greaterThanOrEqualTo(2212));
      expect(batch.screenSignals.toString(), isNot(contains('package')));
      expect(batch.screenSignals.toString(), isNot(contains('appName')));
    },
  );
}
