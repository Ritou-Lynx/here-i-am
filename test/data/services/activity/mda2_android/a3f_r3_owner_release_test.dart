import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/activity_outbox_process_lease.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/file_activity_outbox_store.dart';
import 'file_activity_outbox_store_test.dart' show DurableRig, hasActivityCode;

final class TestProcessLease implements ActivityOutboxProcessLease {
  TestProcessLease(this.source, {this.beforeClaim});
  final void Function()? beforeClaim;
  @override
  final String source;
  @override
  bool isHeld = true;
  Object? claimant;
  bool claimReleased = false;
  int claims = 0;
  @override
  bool get hasFileClaim => claimant != null && !claimReleased;
  @override
  void claimFileAccess(Object value, String requestedSource) {
    beforeClaim?.call();
    if (!isHeld || source != requestedSource) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    if (claimant != null) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    claims++;
    claimant = value;
  }

  @override
  void verifyFileAccess(Object value, String requestedSource) {
    if (!isHeld ||
        claimReleased ||
        !identical(value, claimant) ||
        requestedSource != source) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
  }

  @override
  void releaseFileAccess(Object value) {
    verifyFileAccess(value, source);
    claimReleased = true;
  }
}

Map<String, List<int>> bytes(Directory root) => {
      for (final entity in root.listSync().whereType<File>().where(
            (file) =>
                !file.path.endsWith('${Platform.pathSeparator}owner.gate'),
          ))
        entity.path.split(Platform.pathSeparator).last:
            entity.readAsBytesSync(),
    };

FileActivityOutboxStore create(DurableRig rig, TestProcessLease lease,
        {void Function()? beforeOwnerDeleteForTesting}) =>
    FileActivityOutboxStore.create(
      directory: rig.root,
      binding: rig.binding(),
      capacity: rig.capacity,
      integrityKey: rig.key,
      ageProofProvider: rig.provider(),
      clockMs: () => rig.now,
      processLease: lease,
      ownerDeletionForTest: rig.ownerDeletionForTest,
      beforeOwnerDeleteForTesting: beforeOwnerDeleteForTesting,
    );

void main() {
  test(
      'H4 pre-deletion hook preserves bytes and releases actual FD and file claim',
      () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final lease = TestProcessLease(rig.source.wireValue);
    var injections = 0;
    final store = create(rig, lease, beforeOwnerDeleteForTesting: () {
      injections++;
      throw const AndroidActivityException('owner_lock_cleanup_failed');
    });
    rig.enqueueScreen(store);
    final target = store.inspectOwnReleaseTarget();
    final before = bytes(rig.root);
    expect(() => store.close(),
        throwsA(hasActivityCode('owner_lock_cleanup_failed')));
    expect(injections, 1);
    expect(bytes(rig.root), before);
    expect(store.ownerLeaseReleased, isTrue);
    expect(lease.hasFileClaim, isFalse);
    expect(() => rig.enqueueScreen(store),
        throwsA(hasActivityCode('sequence_authority_required')));
    lease.isHeld = false;
    expect(
        FileActivityOutboxStore.releaseExactOwner(
            directory: rig.root,
            integrityKey: rig.key,
            target: target,
            processLease: TestProcessLease(rig.source.wireValue)),
        ActivityOutboxOwnerReleaseOutcome.released);
    expect(bytes(rig.root), Map.of(before)..remove('owner.json'));
  });
  test(
    'failed normal close freezes target and releases gate without changing data',
    () async {
      final rig = DurableRig(
        ownerDeletionForTest: (_) => throw const FileSystemException(),
      );
      await rig.initialize();
      addTearDown(rig.dispose);
      final lease = TestProcessLease(rig.source.wireValue);
      final store = create(rig, lease);
      rig.enqueueScreen(store);
      final target = store.inspectOwnReleaseTarget();
      final before = bytes(rig.root);
      expect(
        () => store.close(),
        throwsA(hasActivityCode('owner_lock_cleanup_failed')),
      );
      expect(store.ownerLeaseReleased, isTrue);
      expect(lease.hasFileClaim, isFalse);
      expect(bytes(rig.root), before);
      expect(
        () => store.close(),
        throwsA(hasActivityCode('sequence_authority_required')),
      );
      expect(
        () => rig.enqueueScreen(store),
        throwsA(hasActivityCode('sequence_authority_required')),
      );
      expect(
        () => FileActivityOutboxStore.releaseExactOwner(
          directory: rig.root,
          integrityKey: rig.key,
          target: target,
          processLease: lease,
        ),
        throwsA(hasActivityCode('diagnostic_outbox_lease_invalid')),
      );
      expect(bytes(rig.root), before);
      lease.isHeld = false; // Native release proven; recovery gets a new lease.
      final firstRecovery = TestProcessLease(rig.source.wireValue);
      expect(
        FileActivityOutboxStore.releaseExactOwner(
          directory: rig.root,
          integrityKey: rig.key,
          target: target,
          processLease: firstRecovery,
        ),
        ActivityOutboxOwnerReleaseOutcome.released,
      );
      expect(bytes(rig.root), Map.of(before)..remove('owner.json'));
      firstRecovery.isHeld = false;
      final repeatRecovery = TestProcessLease(rig.source.wireValue);
      expect(
        FileActivityOutboxStore.releaseExactOwner(
          directory: rig.root,
          integrityKey: rig.key,
          target: target,
          processLease: repeatRecovery,
        ),
        ActivityOutboxOwnerReleaseOutcome.targetAbsent,
      );
      expect(bytes(rig.root), Map.of(before)..remove('owner.json'));
      expect(lease.hasFileClaim, isFalse);
    },
  );

  test(
    'live claim rejects before opening a second gate and original owner keeps writing',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final lease = TestProcessLease(rig.source.wireValue);
      final store = create(rig, lease);
      final target = store.inspectOwnReleaseTarget();
      final before = bytes(rig.root);
      expect(
        () => FileActivityOutboxStore.releaseExactOwner(
          directory: rig.root,
          integrityKey: rig.key,
          target: target,
          processLease: lease,
        ),
        throwsA(hasActivityCode('diagnostic_outbox_lease_invalid')),
      );
      expect(lease.claims, 1);
      expect(bytes(rig.root), before);
      rig.enqueueScreen(store);
      expect(store.lastAllocatedSequence, 1);
      store.close();
    },
  );

  test(
    'real OS gate rejects a competing independent file claim',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final target = store.inspectOwnReleaseTarget();
      final before = bytes(rig.root);
      final lease = TestProcessLease(rig.source.wireValue);
      expect(
        () => FileActivityOutboxStore.releaseExactOwner(
          directory: rig.root,
          integrityKey: rig.key,
          target: target,
          processLease: lease,
        ),
        throwsA(hasActivityCode('owner_still_active')),
      );
      expect(lease.hasFileClaim, isFalse);
      expect(bytes(rig.root), before);
      store.close();
    },
    skip: !Platform.isWindows
        ? 'Windows same-process file lock test; Android safety uses native broker'
        : false,
  );

  test(
    'inspection and release preserve journal bytes and reject recovery',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final target = store.inspectOwnReleaseTarget();
      store.releaseProcessLeaseForTest();
      File(
        '${rig.root.path}/journal.json',
      ).writeAsStringSync('unrecovered bytes');
      final before = bytes(rig.root);
      expect(
        () => FileActivityOutboxStore.inspectReleaseTarget(
          directory: rig.root,
          integrityKey: rig.key,
          binding: rig.binding(),
        ),
        throwsA(hasActivityCode('owner_release_journal_present')),
      );
      expect(
        () => FileActivityOutboxStore.releaseExactOwner(
          directory: rig.root,
          integrityKey: rig.key,
          target: target,
          processLease: TestProcessLease(rig.source.wireValue),
        ),
        throwsA(hasActivityCode('owner_release_journal_present')),
      );
      expect(bytes(rig.root), before);
    },
  );

  test('successor owner is never removed by an old target', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final first = rig.create();
    final target = first.inspectOwnReleaseTarget();
    first.releaseProcessLeaseForTest();
    final successor = rig.recover();
    successor.releaseProcessLeaseForTest();
    final before = bytes(rig.root);
    expect(
      () => FileActivityOutboxStore.releaseExactOwner(
        directory: rig.root,
        integrityKey: rig.key,
        target: target,
        processLease: TestProcessLease(rig.source.wireValue),
      ),
      throwsA(hasActivityCode('owner_release_target_changed')),
    );
    expect(bytes(rig.root), before);
  });

  test(
    'gate critical section rechecks exact bytes immediately before deletion',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final target = store.inspectOwnReleaseTarget();
      store.releaseProcessLeaseForTest();
      final owner = File('${rig.root.path}/owner.json');
      final before = owner.readAsBytesSync();
      final changed = [...before, 32];
      expect(
        () => FileActivityOutboxStore.releaseExactOwner(
          directory: rig.root,
          integrityKey: rig.key,
          target: target,
          processLease: TestProcessLease(rig.source.wireValue),
          recoveryCriticalSectionHook: () => owner.writeAsBytesSync(changed),
        ),
        throwsA(hasActivityCode('owner_release_target_changed')),
      );
      expect(owner.readAsBytesSync(), changed);
    },
  );

  test(
    'wrong binding and wrong integrity key fail without changing bytes',
    () async {
      final rig = DurableRig();
      await rig.initialize();
      addTearDown(rig.dispose);
      final store = rig.create();
      final before = bytes(rig.root);
      expect(
        () => FileActivityOutboxStore.inspectReleaseTarget(
          directory: rig.root,
          integrityKey: rig.key,
          binding: rig.binding(probeId: 'wrong'),
        ),
        throwsA(hasActivityCode('source_binding_mismatch')),
      );
      expect(
        () => FileActivityOutboxStore.inspectReleaseTarget(
          directory: rig.root,
          integrityKey: List.filled(32, 8),
          binding: rig.binding(),
        ),
        throwsA(hasActivityCode('outbox_anchor_invalid')),
      );
      expect(bytes(rig.root), before);
      store.close();
    },
  );

  test('unknown structure refuses exact release and preserves files', () async {
    final rig = DurableRig();
    await rig.initialize();
    addTearDown(rig.dispose);
    final store = rig.create();
    final target = store.inspectOwnReleaseTarget();
    store.releaseProcessLeaseForTest();
    File('${rig.root.path}/unknown').writeAsStringSync('keep');
    final before = bytes(rig.root);
    expect(
      () => FileActivityOutboxStore.releaseExactOwner(
        directory: rig.root,
        integrityKey: rig.key,
        target: target,
        processLease: TestProcessLease(rig.source.wireValue),
      ),
      throwsA(hasActivityCode('owner_release_path_invalid')),
    );
    expect(bytes(rig.root), before);
  });
}
