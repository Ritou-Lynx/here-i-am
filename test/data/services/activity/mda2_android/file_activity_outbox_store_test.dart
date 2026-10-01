import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// Direct SDK-only verification mirrors these files without package resolution.
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/file_activity_outbox_store.dart';

Matcher hasActivityCode(String code) =>
    isA<AndroidActivityException>().having((error) => error.code, 'code', code);

const _allowedUsage = {
  'app.category_active',
  'probe.permission_changed',
  'probe.error',
  'probe.heartbeat',
};
const _allowedScreen = {
  'screen.interactive',
  'screen.non_interactive',
  'session.unlocked',
  'probe.error',
  'probe.heartbeat',
};

final class DurableRig {
  DurableRig({
    this.source = AndroidActivitySource.screenState,
    this.capacity = 8,
    this.now = 2000000,
    this.faultInjector,
    this.ownerDeletionForTest,
  });

  final AndroidActivitySource source;
  final int capacity;
  int now;
  final ActivityOutboxFaultInjector? faultInjector;
  final ActivityOutboxOwnerDeletionForTest? ownerDeletionForTest;
  final key = List<int>.generate(32, (index) => index + 1);
  late final Directory root;
  final audit = <String>[];

  Future<void> initialize() async {
    root = await Directory.systemTemp.createTemp('mda2_a2_outbox_');
  }

  SyntheticProbeBinding binding({String? probeId}) => SyntheticProbeBinding(
    deviceId: 'synthetic-android',
    probeId:
        probeId ??
        (source == AndroidActivitySource.usageEvents
            ? 'synthetic-usage'
            : 'synthetic-screen'),
    serverIssuedPrefix: List.filled(
      22,
      source == AndroidActivitySource.usageEvents ? 'U' : 'S',
    ).join(),
    source: source,
    reportIntervalMs: 30000,
    expirySloMs: 300000,
    coverageMode: 'discrete_best_effort',
    allowedKinds: source == AndroidActivitySource.usageEvents
        ? _allowedUsage
        : _allowedScreen,
    capabilities: source == AndroidActivitySource.usageEvents
        ? {'usage_events', 'probe_error.collection_failed'}
        : {'probe_error.collection_failed'},
  );

  HmacActivityAgeProofProvider provider() =>
      HmacActivityAgeProofProvider(integrityKey: key);

  FileActivityOutboxStore create() => FileActivityOutboxStore.create(
    directory: root,
    binding: binding(),
    capacity: capacity,
    integrityKey: key,
    ageProofProvider: provider(),
    clockMs: () => now,
    audit: (code, _) => audit.add(code),
    faultInjector: faultInjector,
    ownerDeletionForTest: ownerDeletionForTest,
  );

  FileActivityOutboxStore open({
    ActivityOutboxRecoveryAuthority? recoveryAuthority,
    String? probeId,
    ActivityOutboxRecoveryCriticalSectionHook? recoveryCriticalSectionHook,
    int Function()? clockMs,
  }) => FileActivityOutboxStore.open(
    directory: root,
    binding: binding(probeId: probeId),
    capacity: capacity,
    integrityKey: key,
    ageProofProvider: provider(),
    clockMs: clockMs ?? () => now,
    recoveryAuthority: recoveryAuthority,
    recoveryCriticalSectionHook: recoveryCriticalSectionHook,
    ownerDeletionForTest: ownerDeletionForTest,
    audit: (code, _) => audit.add(code),
  );

  FileActivityOutboxStore recover() {
    final inspection = FileActivityOutboxStore.inspectRecovery(
      directory: root,
      integrityKey: key,
    );
    return open(
      recoveryAuthority: ActivityOutboxRecoveryAuthority.fromInspection(
        inspection,
      ),
    );
  }

  AndroidActivityEvent enqueueScreen(FileActivityOutboxStore store) =>
      store.enqueue(
        kind: 'session.unlocked',
        atMs: now,
        ttlMs: 300000,
        confidence: 'high',
      );

  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

void main() {
  test(
    'create commits fixed bytes before returning and reopens same lineage',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final first = rig.create();
      final event = rig.enqueueScreen(first);
      final bytes = event.json;
      first.close();

      final restored = rig.open();
      expect(restored.restored, isTrue);
      expect(restored.lastAllocatedSequence, 1);
      expect(restored.durableRecords.single.event.json, bytes);
      expect(
        restored.durableRecords.single.delivery,
        DurableDeliveryState.neverSent,
      );
      final normalizer = AndroidActivityNormalizer(
        outbox: restored,
        clockMs: () => rig.now,
        ttlMs: 300000,
      );
      expect(normalizer.status.coverage, AndroidCoverage.gap);
      rig.now++;
      final gap = normalizer.markCollectionGap();
      expect(gap.originSequence, 2);
      expect(restored.durableRecords.first.event.json, bytes);
      restored.close();
    },
  );

  for (final point in ActivityOutboxFaultPoint.values) {
    test('allocate recovery is complete at interruption $point', () async {
      var armed = false;
      final rig = DurableRig(
        faultInjector: (seen) {
          if (armed && seen == point) {
            throw StateError('synthetic interruption');
          }
        },
      );
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      armed = true;
      expect(
        () => rig.enqueueScreen(store),
        throwsA(hasActivityCode('transaction_interrupted')),
      );
      final restored = rig.recover();
      expect(
        restored.lastAllocatedSequence,
        point == ActivityOutboxFaultPoint.afterJournal ? 0 : 1,
      );
      expect(restored.durableRecords.length, restored.lastAllocatedSequence);
      restored.close();
    });
  }

  for (final point in ActivityOutboxFaultPoint.values) {
    test(
      'receipt commit recovery is complete at interruption $point',
      () async {
        var armed = false;
        final rig = DurableRig(
          faultInjector: (seen) {
            if (armed && seen == point) {
              throw StateError('synthetic receipt interruption');
            }
          },
        );
        await rig.initialize();
        addTearDown(rig.dispose);
        final store = rig.create();
        final event = rig.enqueueScreen(store);
        final ticket = store.beginNextAttempt()!;
        armed = true;
        expect(
          () => store.settleAttempt(
            ticket,
            ActivityCoreReceipt(
              eventId: event.eventId,
              kind: ActivityCoreReceiptKind.accepted,
            ),
          ),
          throwsA(hasActivityCode('transaction_interrupted')),
        );
        final restored = rig.recover();
        expect(
          restored.durableRecords.single.delivery,
          point == ActivityOutboxFaultPoint.afterJournal
              ? DurableDeliveryState.attemptedUnknown
              : DurableDeliveryState.accepted,
        );
        restored.close();
      },
    );
  }

  test('second owner and stale lock need exact recovery authority', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final first = rig.create();
    expect(rig.open, throwsA(hasActivityCode('recovery_authority_required')));
    final inspection = FileActivityOutboxStore.inspectRecovery(
      directory: rig.root,
      integrityKey: rig.key,
    );
    final wrong = ActivityOutboxRecoveryAuthority(
      source: inspection.source,
      bindingDigest: inspection.bindingDigest,
      expectedOwnerId: 'wrong-owner',
      expectedAnchorGeneration: inspection.anchorGeneration,
      expectedAnchorDigest: inspection.anchorDigest,
    );
    expect(
      () => rig.open(recoveryAuthority: wrong),
      throwsA(hasActivityCode('recovery_authority_invalid')),
    );
    final exact = ActivityOutboxRecoveryAuthority.fromInspection(inspection);
    expect(
      () => rig.open(recoveryAuthority: exact),
      throwsA(hasActivityCode('owner_still_active')),
    );
    first.releaseProcessLeaseForTest();
    final recovered = rig.open(recoveryAuthority: exact);
    expect(
      () => rig.enqueueScreen(first),
      throwsA(hasActivityCode('sequence_authority_required')),
    );
    recovered.close();
  });

  test(
    'two stale recoverers yield one winner and old authority cannot delete it',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final stale = rig.create();
      rig.enqueueScreen(stale);
      final oldInspection = FileActivityOutboxStore.inspectRecovery(
        directory: rig.root,
        integrityKey: rig.key,
      );
      final oldAuthority = ActivityOutboxRecoveryAuthority.fromInspection(
        oldInspection,
      );
      stale.releaseProcessLeaseForTest();

      var losingAttempts = 0;
      final winner = rig.open(
        recoveryAuthority: oldAuthority,
        recoveryCriticalSectionHook: () {
          expect(() {
            losingAttempts++;
            rig.open(recoveryAuthority: oldAuthority);
          }, throwsA(hasActivityCode('owner_still_active')));
        },
      );
      expect(losingAttempts, 1);
      final ownerFile = File(
        '${rig.root.path}${Platform.pathSeparator}owner.json',
      );
      final winnerOwnerBytes = ownerFile.readAsBytesSync();

      winner.releaseProcessLeaseForTest();
      expect(
        () => rig.open(recoveryAuthority: oldAuthority),
        throwsA(hasActivityCode('recovery_authority_invalid')),
      );
      expect(ownerFile.readAsBytesSync(), winnerOwnerBytes);

      final winnerInspection = FileActivityOutboxStore.inspectRecovery(
        directory: rig.root,
        integrityKey: rig.key,
      );
      final finalOwner = rig.open(
        recoveryAuthority: ActivityOutboxRecoveryAuthority.fromInspection(
          winnerInspection,
        ),
      );
      finalOwner.close();
    },
  );

  test(
    'close deletion failure releases gate and exact authority can recover',
    () async {
      var failDeletion = true;
      final rig = DurableRig(
        ownerDeletionForTest: (ownerFile) {
          if (failDeletion) {
            failDeletion = false;
            throw StateError('synthetic owner deletion failure');
          }
          ownerFile.deleteSync();
        },
      );
      await rig.initialize();
      addTearDown(rig.dispose);
      final old = rig.create();
      rig.enqueueScreen(old);
      final ownerFile = File(
        '${rig.root.path}${Platform.pathSeparator}owner.json',
      );
      final retainedOwnerBytes = ownerFile.readAsBytesSync();

      expect(old.close, throwsA(hasActivityCode('owner_lock_cleanup_failed')));
      expect(ownerFile.readAsBytesSync(), retainedOwnerBytes);
      expect(
        () => rig.enqueueScreen(old),
        throwsA(hasActivityCode('sequence_authority_required')),
      );

      final retainedInspection = FileActivityOutboxStore.inspectRecovery(
        directory: rig.root,
        integrityKey: rig.key,
      );
      final recovered = rig.open(
        recoveryAuthority: ActivityOutboxRecoveryAuthority.fromInspection(
          retainedInspection,
        ),
      );
      expect(recovered.lastAllocatedSequence, 1);
      recovered.close();
    },
  );

  test(
    'open cleanup deletion failure releases gate for exact replacement owner',
    () async {
      var failDeletion = true;
      final rig = DurableRig(
        ownerDeletionForTest: (ownerFile) {
          if (failDeletion) {
            failDeletion = false;
            throw StateError('synthetic owner deletion failure');
          }
          ownerFile.deleteSync();
        },
      );
      await rig.initialize();
      addTearDown(rig.dispose);
      final stale = rig.create();
      rig.enqueueScreen(stale);
      final staleInspection = FileActivityOutboxStore.inspectRecovery(
        directory: rig.root,
        integrityKey: rig.key,
      );
      stale.releaseProcessLeaseForTest();

      expect(
        () => rig.open(
          recoveryAuthority: ActivityOutboxRecoveryAuthority.fromInspection(
            staleInspection,
          ),
          clockMs: () => throw StateError('synthetic open failure'),
        ),
        throwsA(hasActivityCode('owner_lock_cleanup_failed')),
      );

      final replacementInspection = FileActivityOutboxStore.inspectRecovery(
        directory: rig.root,
        integrityKey: rig.key,
      );
      expect(replacementInspection.ownerId, isNot(staleInspection.ownerId));
      final recovered = rig.open(
        recoveryAuthority: ActivityOutboxRecoveryAuthority.fromInspection(
          replacementInspection,
        ),
      );
      expect(recovered.lastAllocatedSequence, 1);
      recovered.close();
    },
  );

  test('lost lock freezes the old owner without allocating', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final store = rig.create();
    rig.enqueueScreen(store);
    store.releaseProcessLeaseForTest();
    File('${rig.root.path}${Platform.pathSeparator}owner.json').deleteSync();
    expect(
      () => rig.enqueueScreen(store),
      throwsA(hasActivityCode('sequence_authority_required')),
    );
    expect(store.lastAllocatedSequence, 1);
  });

  test('old owner late receipt cannot settle after takeover', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final old = rig.create();
    final event = rig.enqueueScreen(old);
    rig.now++;
    rig.enqueueScreen(old);
    final ticket = old.beginNextAttempt()!;
    old.releaseProcessLeaseForTest();
    final replacement = rig.recover();
    expect(
      () => old.settleAttempt(
        ticket,
        ActivityCoreReceipt(
          eventId: event.eventId,
          kind: ActivityCoreReceiptKind.accepted,
        ),
      ),
      throwsA(hasActivityCode('sequence_authority_required')),
    );
    final retry = replacement.beginNextAttempt()!;
    expect(utf8.decode(retry.fixedWireBytes), event.json);
    expect(replacement.durableRecords.first.attempts, 2);
    replacement.abandonAttempt(retry);
    replacement.close();
  });

  test(
    'ambiguous send persists attempted_unknown and never mutates bytes',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final event = rig.enqueueScreen(store);
      await DurableActivityOutboxSender(store).flush((bytes) async {
        expect(utf8.decode(bytes), event.json);
        throw StateError('PRIVATE_TRANSPORT_DETAIL');
      });
      expect(
        store.durableRecords.single.delivery,
        DurableDeliveryState.attemptedUnknown,
      );
      expect(store.durableRecords.single.attempts, 1);
      expect(rig.audit, contains('transport_ambiguous'));
      expect(rig.audit.join(), isNot(contains('PRIVATE_TRANSPORT_DETAIL')));
      store.close();
      final restored = rig.open();
      expect(
        restored.durableRecords.single.delivery,
        DurableDeliveryState.attemptedUnknown,
      );
      expect(restored.durableRecords.single.event.json, event.json);
      restored.close();
    },
  );

  test(
    'accepted, duplicate, retryable, and terminal receipts stay distinct',
    () async {
      final rig = DurableRig(capacity: 4);
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      for (var index = 0; index < 4; index++) {
        rig.now++;
        rig.enqueueScreen(store);
      }
      var call = 0;
      await store.flush((bytes) async {
        call++;
        final event = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        return ActivityCoreReceipt(
          eventId: event['event_id'] as String,
          kind: call == 1
              ? ActivityCoreReceiptKind.accepted
              : ActivityCoreReceiptKind.retryable,
        );
      });
      expect(store.durableRecords.map((record) => record.delivery), [
        DurableDeliveryState.accepted,
        DurableDeliveryState.attemptedUnknown,
        DurableDeliveryState.neverSent,
        DurableDeliveryState.neverSent,
      ]);
      await store.flush((bytes) async {
        final event = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final sequence = event['origin_sequence'] as int;
        return ActivityCoreReceipt(
          eventId: event['event_id'] as String,
          kind: sequence == 2
              ? ActivityCoreReceiptKind.duplicate
              : ActivityCoreReceiptKind.terminalRejected,
          rejection: sequence == 2 ? null : ActivityRejection.ttlExpired,
        );
      });
      expect(store.durableRecords[1].delivery, DurableDeliveryState.duplicate);
      expect(
        store.durableRecords[2].delivery,
        DurableDeliveryState.terminalRejected,
      );
      expect(store.durableRecords[3].delivery, DurableDeliveryState.neverSent);
      expect(store.durableRecords[3].attempts, 0);
      expect(store.frozenCode, ActivityRejection.ttlExpired.coreCode);
      store.close();
      final restored = rig.open();
      expect(
        restored.durableRecords[0].delivery,
        DurableDeliveryState.accepted,
      );
      expect(
        restored.durableRecords[1].delivery,
        DurableDeliveryState.duplicate,
      );
      expect(
        restored.durableRecords[2].delivery,
        DurableDeliveryState.terminalRejected,
      );
      expect(restored.durableRecords[3].attempts, 0);
      expect(restored.frozenCode, ActivityRejection.ttlExpired.coreCode);
      restored.close();
    },
  );

  test('invalid and repeated receipts cannot acknowledge an attempt', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final store = rig.create();
    rig.enqueueScreen(store);
    final ticket = store.beginNextAttempt()!;
    expect(
      store.settleAttempt(
        ticket,
        const ActivityCoreReceipt(
          eventId: 'wrong',
          kind: ActivityCoreReceiptKind.accepted,
        ),
      ),
      isFalse,
    );
    expect(
      store.durableRecords.single.delivery,
      DurableDeliveryState.attemptedUnknown,
    );
    expect(
      () => store.settleAttempt(
        ticket,
        ActivityCoreReceipt(
          eventId: ticket.eventId,
          kind: ActivityCoreReceiptKind.accepted,
        ),
      ),
      throwsA(hasActivityCode('stale_attempt_receipt')),
    );
    store.close();
  });

  test(
    'freeze settles only actual inflight receipt and leaves later record untouched',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final first = rig.enqueueScreen(store);
      rig.now++;
      rig.enqueueScreen(store);
      final reply = Completer<ActivityCoreReceipt>();
      var sends = 0;
      final flushing = store.flush((_) {
        sends++;
        return reply.future;
      });
      store.freeze('permission_revoked');
      reply.complete(
        ActivityCoreReceipt(
          eventId: first.eventId,
          kind: ActivityCoreReceiptKind.accepted,
        ),
      );
      await flushing;
      expect(sends, 1);
      expect(
        store.durableRecords.first.delivery,
        DurableDeliveryState.accepted,
      );
      expect(
        store.durableRecords.last.delivery,
        DurableDeliveryState.neverSent,
      );
      expect(store.durableRecords.last.attempts, 0);
      await store.flush((_) async => throw StateError('must not send'));
      store.close();
    },
  );

  test(
    'capacity rejects before sequence allocation and exposes a gap',
    () async {
      final rig = DurableRig(capacity: 1);
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      rig.enqueueScreen(store);
      rig.now++;
      expect(
        () => rig.enqueueScreen(store),
        throwsA(hasActivityCode('outbox_full')),
      );
      expect(store.lastAllocatedSequence, 1);
      expect(store.gapCode, 'outbox_full');
      store.close();
    },
  );

  test(
    '24-hour proof boundary is admitted and one millisecond older is rejected',
    () async {
      final rig = DurableRig(now: 86400000 + 1000);
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final provider = rig.provider();
      final exactSignal = rig.now - 86400000;
      final exactProof = provider.issue(
        source: rig.source,
        bindingDigest: store.bindingDigest,
        signalAtMs: exactSignal,
        observedAtMs: rig.now,
      );
      store.enqueueWithAgeProof(
        kind: 'session.unlocked',
        atMs: exactSignal,
        ttlMs: 300000,
        confidence: 'high',
        ageProof: exactProof,
      );
      var sends = 0;
      await store.flush((bytes) async {
        sends++;
        return ActivityCoreReceipt(
          eventId:
              (jsonDecode(utf8.decode(bytes)) as Map)['event_id'] as String,
          kind: ActivityCoreReceiptKind.accepted,
        );
      });
      expect(sends, 1);
      store.close();

      final olderRig = DurableRig(now: rig.now);
      await olderRig.initialize();
      addTearDown(olderRig.dispose);
      final olderStore = olderRig.create();
      final olderSignal = olderRig.now - 86400001;
      final olderProof = olderRig.provider().issue(
        source: olderRig.source,
        bindingDigest: olderStore.bindingDigest,
        signalAtMs: olderSignal,
        observedAtMs: olderRig.now,
      );
      expect(
        () => olderStore.enqueueWithAgeProof(
          kind: 'session.unlocked',
          atMs: olderSignal,
          ttlMs: 300000,
          confidence: 'high',
          ageProof: olderProof,
        ),
        throwsA(hasActivityCode('age_proof_invalid')),
      );
      expect(olderStore.lastAllocatedSequence, 0);
      olderStore.close();
    },
  );

  test('enqueue signs and verifies against one clock observation', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    var tickingNow = rig.now;
    final store = FileActivityOutboxStore.create(
      directory: rig.root,
      binding: rig.binding(),
      capacity: rig.capacity,
      integrityKey: rig.key,
      ageProofProvider: rig.provider(),
      clockMs: () => tickingNow++,
      audit: (code, _) => rig.audit.add(code),
    );

    final signalAtMs = tickingNow;
    final event = store.enqueue(
      kind: 'session.unlocked',
      atMs: signalAtMs,
      ttlMs: 300000,
      confidence: 'high',
    );

    expect(event.originSequence, 1);
    expect(store.lastAllocatedSequence, 1);
    store.close();
  });

  test(
    'forged age, source, and binding proofs fail before sequence allocation',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final valid = rig.provider().issue(
        source: rig.source,
        bindingDigest: store.bindingDigest,
        signalAtMs: rig.now,
        observedAtMs: rig.now,
      );
      final forged = ActivityAgeProof(
        source: AndroidActivitySource.usageEvents,
        bindingDigest: valid.bindingDigest,
        signalAtMs: valid.signalAtMs,
        observedAtMs: valid.observedAtMs,
        maxAgeMs: valid.maxAgeMs,
        mac: valid.mac,
      );
      expect(
        () => store.enqueueWithAgeProof(
          kind: 'session.unlocked',
          atMs: rig.now,
          ttlMs: 300000,
          confidence: 'high',
          ageProof: forged,
        ),
        throwsA(hasActivityCode('age_proof_invalid')),
      );
      expect(store.lastAllocatedSequence, 0);
      store.close();
    },
  );

  test('raw release deadline blocks all later transmission', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final store = rig.create();
    rig.enqueueScreen(store);
    rig.now += 86400001;
    var sends = 0;
    await store.flush((_) async {
      sends++;
      throw StateError('must not send');
    });
    expect(sends, 0);
    expect(store.frozenCode, 'raw_release_deadline_expired');
    expect(
      store.durableRecords.single.delivery,
      DurableDeliveryState.neverSent,
    );
    store.close();
  });

  test('wall-clock rollback is durably frozen', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final store = rig.create();
    rig.enqueueScreen(store);
    rig.now--;
    expect(
      () => rig.enqueueScreen(store),
      throwsA(hasActivityCode('clock_uncertain')),
    );
    expect(store.frozenCode, 'clock_regression');
    store.close();
    final restored = rig.open();
    expect(restored.frozenCode, 'clock_regression');
    restored.close();
  });

  test(
    'permission revoke and recovery retain conservative normalizer state',
    () async {
      final rig = DurableRig(source: AndroidActivitySource.usageEvents);
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final collector = AndroidActivityNormalizer(
        outbox: store,
        clockMs: () => rig.now,
        ttlMs: 300000,
      );
      collector.acceptSynthetic({
        'type': 'usage_permission',
        'state': 'granted',
      });
      collector.acceptSynthetic({
        'type': 'usage_category',
        'category': 'reading',
        'signal_at_ms': rig.now,
      });
      rig.now++;
      collector.acceptSynthetic({
        'type': 'usage_permission',
        'state': 'revoked',
      });
      expect(collector.status.permission, UsageAccess.revoked);
      store.close();
      final restored = rig.open();
      final afterRestart = AndroidActivityNormalizer(
        outbox: restored,
        clockMs: () => rig.now,
        ttlMs: 300000,
      );
      expect(afterRestart.status.permission, UsageAccess.unknown);
      expect(afterRestart.status.coverage, AndroidCoverage.gap);
      rig.now++;
      afterRestart.markCollectionGap();
      restored.close();
    },
  );

  test('missing, truncated, and unknown-version state fail closed', () async {
    for (final mutation in ['missing', 'truncated', 'unknown_version']) {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      rig.enqueueScreen(store);
      store.close();
      final state = File('${rig.root.path}${Platform.pathSeparator}state.json');
      if (mutation == 'missing') {
        state.deleteSync();
      } else if (mutation == 'truncated') {
        state.writeAsStringSync('{"format_version":1');
      } else {
        final envelope =
            jsonDecode(state.readAsStringSync()) as Map<String, dynamic>;
        envelope['format_version'] = 99;
        state.writeAsStringSync(jsonEncode(envelope));
      }
      expect(
        rig.open,
        throwsA(
          isA<AndroidActivityException>().having(
            (error) => error.code,
            'code',
            mutation == 'unknown_version'
                ? 'outbox_version_unsupported'
                : 'outbox_corrupt',
          ),
        ),
      );
    }
  });

  test(
    'rollback snapshot is rejected when trusted anchor remains newer',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      rig.enqueueScreen(store);
      final stateFile = File(
        '${rig.root.path}${Platform.pathSeparator}state.json',
      );
      final oldState = stateFile.readAsBytesSync();
      rig.now++;
      rig.enqueueScreen(store);
      store.close();
      stateFile.writeAsBytesSync(oldState, flush: true);
      expect(rig.open, throwsA(hasActivityCode('outbox_rollback_detected')));
    },
  );

  test('binding replacement and source store exchange fail closed', () async {
    final first = DurableRig();
    final second = DurableRig(source: AndroidActivitySource.usageEvents);
    await first.initialize();
    await second.initialize();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final screen = first.create();
    first.enqueueScreen(screen);
    screen.close();
    expect(
      () => first.open(probeId: 'different-probe'),
      throwsA(hasActivityCode('source_binding_mismatch')),
    );
    final usage = second.create();
    usage.enqueue(
      kind: 'probe.heartbeat',
      atMs: second.now,
      ttlMs: 300000,
      confidence: 'low',
    );
    usage.close();
    for (final name in ['state.json', 'anchor.json']) {
      File(
        '${second.root.path}${Platform.pathSeparator}$name',
      ).copySync('${first.root.path}${Platform.pathSeparator}$name');
    }
    expect(first.open, throwsA(hasActivityCode('source_binding_mismatch')));
  });

  test(
    'usage and screen sources keep independent lineage and sequence one',
    () async {
      final screenRig = DurableRig();
      final usageRig = DurableRig(source: AndroidActivitySource.usageEvents);
      await screenRig.initialize();
      await usageRig.initialize();
      addTearDown(screenRig.dispose);
      addTearDown(usageRig.dispose);
      final screen = screenRig.create();
      final usage = usageRig.create();
      final screenEvent = screenRig.enqueueScreen(screen);
      final usageEvent = usage.enqueue(
        kind: 'probe.heartbeat',
        atMs: usageRig.now,
        ttlMs: 300000,
        confidence: 'low',
      );
      expect(screenEvent.originSequence, 1);
      expect(usageEvent.originSequence, 1);
      expect(screenEvent.eventId, isNot(usageEvent.eventId));
      expect(screenEvent.toJson()['source'], 'android_screen_state');
      expect(usageEvent.toJson()['source'], 'android_usage_events');
      screen.close();
      usage.close();
    },
  );

  test('wrong integrity key and damaged MAC do not recover', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final store = rig.create();
    rig.enqueueScreen(store);
    store.close();
    expect(
      () => FileActivityOutboxStore.open(
        directory: rig.root,
        binding: rig.binding(),
        capacity: rig.capacity,
        integrityKey: List<int>.filled(32, 9),
        ageProofProvider: HmacActivityAgeProofProvider(
          integrityKey: List<int>.filled(32, 9),
        ),
        clockMs: () => rig.now,
      ),
      throwsA(hasActivityCode('outbox_corrupt')),
    );
  });

  test(
    'privacy-negative inputs, files, sender, and audit contain no private value',
    () async {
      final rig = DurableRig(source: AndroidActivitySource.usageEvents);
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final collector = AndroidActivityNormalizer(
        outbox: store,
        clockMs: () => rig.now,
        ttlMs: 300000,
      );
      collector.acceptSynthetic({
        'type': 'usage_permission',
        'state': 'granted',
      });
      const marker = 'PRIVATE_SYNTHETIC_VALUE';
      for (final field in [
        'package_name',
        'app_name',
        'message_body',
        'location',
        'ble_raw_packet',
        'heart_rate',
        'received_at_ms',
        'payload_extension',
      ]) {
        expect(
          () => collector.acceptSynthetic({
            'type': 'usage_category',
            'category': 'reading',
            'signal_at_ms': rig.now,
            field: marker,
          }),
          throwsA(hasActivityCode('unknown_or_missing_signal_field')),
        );
      }
      collector.acceptSynthetic({
        'type': 'usage_category',
        'category': 'reading',
        'signal_at_ms': rig.now,
      });
      await store.flush((Uint8List bytes) async {
        final wire = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        expect(wire.keys, isNot(contains('received_at_ms')));
        expect(utf8.decode(bytes), isNot(contains(marker)));
        return ActivityCoreReceipt(
          eventId: wire['event_id'] as String,
          kind: ActivityCoreReceiptKind.accepted,
        );
      });
      store.close();
      final persisted = rig.root
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.readAsStringSync())
          .join();
      expect(persisted, isNot(contains(marker)));
      expect(rig.audit.join(), isNot(contains(marker)));
    },
  );

  test(
    'TTL boundary keeps immutable attempted bytes for Core reconciliation',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final event = store.enqueue(
        kind: 'session.unlocked',
        atMs: rig.now,
        ttlMs: 100,
        confidence: 'high',
      );
      rig.now += 100;
      expect(event.isPastTtl(rig.now), isFalse);
      await store.flush(
        (bytes) async => ActivityCoreReceipt(
          eventId:
              (jsonDecode(utf8.decode(bytes)) as Map)['event_id'] as String,
          kind: ActivityCoreReceiptKind.retryable,
        ),
      );
      rig.now++;
      expect(event.isPastTtl(rig.now), isTrue);
      await store.flush((bytes) async {
        expect(utf8.decode(bytes), event.json);
        return ActivityCoreReceipt(
          eventId: event.eventId,
          kind: ActivityCoreReceiptKind.duplicate,
        );
      });
      expect(
        store.durableRecords.single.delivery,
        DurableDeliveryState.duplicate,
      );
      store.close();
    },
  );
}
