import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/workbench_ai/artifacts/artifact_contracts.dart';

void main() {
  group('ArtifactBundleExecutor', () {
    test(
      'commits verified objects, domain bindings and a durable receipt',
      () async {
        final fixture = _executableFixture();
        final objects = _FakeObjectStore(fixture.stagedObjects);
        final ledger = _FakeLedger();
        final domain = _FakeDomainRepository(
          stateHash: fixture.plan.batch.expectedStateHash,
        );
        final executor = _executor(objects, ledger, domain);

        final receipt = await executor.execute(fixture.plan);

        expect(receipt.status, OperationReceiptStatus.committed);
        expect(
          receipt.committedOperationIds,
          fixture.plan.batch.operations.map((value) => value.operationId),
        );
        expect(
          receipt.inverseOperations.first.operationId,
          '${fixture.plan.batch.operations.last.operationId}_inverse',
        );
        expect(
          objects.committedRefs,
          fixture.plan.artifacts.map((value) => value.manifest.objectRef),
        );
        expect(objects.stagedObjects, isEmpty);
        expect(domain.commitCalls, 1);
        expect(
          domain.lastPlan!.artifacts.first.binding.cardId,
          'card_artifact_001',
        );
        expect(ledger.journal!.phase, ArtifactCommitPhase.committed);
      },
    );

    test(
      'restart replay returns the original receipt without applying again',
      () async {
        final fixture = _executableFixture();
        final objects = _FakeObjectStore(fixture.stagedObjects);
        final ledger = _FakeLedger();
        final domain = _FakeDomainRepository(
          stateHash: fixture.plan.batch.expectedStateHash,
        );
        final first = await _executor(
          objects,
          ledger,
          domain,
        ).execute(fixture.plan);

        final replay = await _executor(
          objects,
          ledger,
          domain,
        ).execute(fixture.plan);

        expect(replay.toJson(), first.toJson());
        expect(domain.commitCalls, 1);
        expect(objects.commitCalls, fixture.plan.artifacts.length);
      },
    );

    test(
      'hash mismatch creates no binding and cleans controlled staging',
      () async {
        final fixture = _executableFixture();
        final corrupted = Map<String, _StagedBytes>.from(fixture.stagedObjects);
        final firstRef = fixture.plan.artifacts.first.manifest.stagedObjectRef;
        corrupted[firstRef] = _StagedBytes(
          fixture.plan.artifacts.first.manifest.mimeType,
          utf8.encode('corrupted'),
        );
        final objects = _FakeObjectStore(corrupted);
        final ledger = _FakeLedger();
        final domain = _FakeDomainRepository(
          stateHash: fixture.plan.batch.expectedStateHash,
        );

        final receipt = await _executor(
          objects,
          ledger,
          domain,
        ).execute(fixture.plan);

        expect(receipt.status, OperationReceiptStatus.rejected);
        expect(
          receipt.failureCode,
          anyOf('artifact_size_mismatch', 'artifact_hash_mismatch'),
        );
        expect(domain.commitCalls, 0);
        expect(objects.committedRefs, isEmpty);
        expect(objects.stagedObjects, isEmpty);
        expect(ledger.journal!.phase, ArtifactCommitPhase.rolledBack);
      },
    );

    test(
      'conflict hash rejects before final object or product commit',
      () async {
        final fixture = _executableFixture();
        final objects = _FakeObjectStore(fixture.stagedObjects);
        final ledger = _FakeLedger();
        final domain = _FakeDomainRepository(
          stateHash:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        );

        final receipt = await _executor(
          objects,
          ledger,
          domain,
        ).execute(fixture.plan);

        expect(receipt.status, OperationReceiptStatus.rejected);
        expect(receipt.failureCode, 'expected_state_hash_conflict');
        expect(domain.commitCalls, 0);
        expect(objects.committedRefs, isEmpty);
      },
    );

    test(
      'partial domain failure runs declared inverses and delayed GC',
      () async {
        final fixture = _executableFixture();
        final objects = _FakeObjectStore(fixture.stagedObjects);
        final ledger = _FakeLedger();
        final escapedOperation =
            fixture.plan.batch.operations.first.operationId;
        final domain = _FakeDomainRepository(
          stateHash: fixture.plan.batch.expectedStateHash,
          commitError: ArtifactDomainCommitException(
            'domain_partial_failure',
            committedOperationIds: [escapedOperation],
          ),
        );

        final receipt = await _executor(
          objects,
          ledger,
          domain,
        ).execute(fixture.plan);

        expect(receipt.status, OperationReceiptStatus.rolledBack);
        expect(domain.rollbackCalls, 1);
        expect(
          domain.rolledBack.single.operationId,
          '${escapedOperation}_inverse',
        );
        expect(
          objects.garbageCollectionRefs,
          fixture.plan.artifacts.map((value) => value.manifest.objectRef),
        );
        expect(ledger.journal!.boundArtifactIds, isEmpty);
      },
    );

    test(
      'recovery journal survives cleanup failure and resumes after restart',
      () async {
        final fixture = _executableFixture();
        final corrupted = Map<String, _StagedBytes>.from(fixture.stagedObjects);
        final firstRef = fixture.plan.artifacts.first.manifest.stagedObjectRef;
        corrupted[firstRef] = _StagedBytes(
          fixture.plan.artifacts.first.manifest.mimeType,
          utf8.encode('corrupted'),
        );
        final objects = _FakeObjectStore(corrupted)..failDelete = true;
        final ledger = _FakeLedger();
        final domain = _FakeDomainRepository(
          stateHash: fixture.plan.batch.expectedStateHash,
        );

        await expectLater(
          _executor(objects, ledger, domain).execute(fixture.plan),
          throwsA(
            isA<ArtifactExecutionException>().having(
              (value) => value.code,
              'code',
              startsWith('artifact_recovery_pending:'),
            ),
          ),
        );
        expect(ledger.journal!.phase, ArtifactCommitPhase.recoveryRequired);

        objects.failDelete = false;
        final recovered = await _executor(
          objects,
          ledger,
          domain,
        ).execute(fixture.plan);

        expect(recovered.status, OperationReceiptStatus.rejected);
        expect(objects.stagedObjects, isEmpty);
        expect(ledger.journal!.phase, ArtifactCommitPhase.rolledBack);
        expect(domain.commitCalls, 0);
      },
    );

    test(
      'budget rejection happens before touching staging or repositories',
      () async {
        final fixture = _executableFixture();
        final objects = _FakeObjectStore(fixture.stagedObjects);
        final ledger = _FakeLedger();
        final domain = _FakeDomainRepository(
          stateHash: fixture.plan.batch.expectedStateHash,
        );
        final executor = ArtifactBundleExecutor(
          objectStore: objects,
          ledger: ledger,
          domainRepository: domain,
          budget: const ArtifactBudget(maxArtifactCount: 1),
        );

        await expectLater(
          executor.execute(fixture.plan),
          throwsA(
            isA<ArtifactExecutionException>().having(
              (value) => value.code,
              'code',
              contains('artifact_count_exceeded'),
            ),
          ),
        );
        expect(ledger.openCalls, 0);
        expect(objects.openCalls, 0);
        expect(domain.commitCalls, 0);
      },
    );
  });
}

ArtifactBundleExecutor _executor(
  _FakeObjectStore objects,
  _FakeLedger ledger,
  _FakeDomainRepository domain,
) =>
    ArtifactBundleExecutor(
      objectStore: objects,
      ledger: ledger,
      domainRepository: domain,
      clock: () => DateTime.utc(2026, 8, 23, 12),
    );

class _ExecutableFixture {
  const _ExecutableFixture(this.plan, this.stagedObjects);

  final ContentBundlePlan plan;
  final Map<String, _StagedBytes> stagedObjects;
}

_ExecutableFixture _executableFixture() {
  final json = jsonDecode(
    File(
      'test/domain/workbench_ai/artifacts/fixtures/normal_content_bundle.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;
  final staged = <String, _StagedBytes>{};
  final artifacts = (json['artifacts'] as List).cast<Map<String, dynamic>>();
  for (var index = 0; index < artifacts.length; index++) {
    final manifest = artifacts[index]['manifest'] as Map<String, dynamic>;
    final bytes = utf8.encode('artifact-$index-provider-neutral-bytes');
    final hash = sha256.convert(bytes).toString();
    final extension = index == 0 ? 'html' : 'zip';
    final objectRef = 'objects/test/$hash.$extension';
    manifest['size_bytes'] = bytes.length;
    manifest['sha256'] = hash;
    manifest['object_ref'] = objectRef;
    staged[manifest['staged_object_ref'] as String] = _StagedBytes(
      manifest['mime_type'] as String,
      bytes,
    );
    if (index == 0) {
      final source = (json['sources'] as List).single as Map;
      final version = (json['source_versions'] as List).single as Map;
      source['content_hash'] = hash;
      source['object_ref'] = objectRef;
      version['content_hash'] = hash;
      version['object_ref'] = objectRef;
    } else {
      final runtime = (json['html_runtime_bundles'] as List).single as Map;
      runtime['runtime_sha256'] = hash;
      runtime['runtime_object_ref'] = objectRef;
    }
  }
  return _ExecutableFixture(ContentBundlePlan.fromJson(json), staged);
}

class _StagedBytes {
  const _StagedBytes(this.mimeType, this.bytes);

  final String mimeType;
  final List<int> bytes;
}

class _FakeObjectStore implements ArtifactObjectStore {
  _FakeObjectStore(Map<String, _StagedBytes> stagedObjects)
      : stagedObjects = Map.from(stagedObjects);

  final Map<String, _StagedBytes> stagedObjects;
  final List<String> committedRefs = [];
  final List<String> garbageCollectionRefs = [];
  bool failDelete = false;
  int openCalls = 0;
  int commitCalls = 0;

  @override
  Future<StagedArtifactObject> openStaged(String stagedObjectRef) async {
    openCalls++;
    final staged = stagedObjects[stagedObjectRef];
    if (staged == null) throw StateError('missing staged object');
    return StagedArtifactObject(
      mimeType: staged.mimeType,
      bytes: Stream.value(staged.bytes),
    );
  }

  @override
  Future<void> commitVerified(ArtifactManifest manifest) async {
    commitCalls++;
    if (!committedRefs.contains(manifest.objectRef)) {
      committedRefs.add(manifest.objectRef);
    }
  }

  @override
  Future<void> deleteStaged(String stagedObjectRef) async {
    if (failDelete) throw StateError('cleanup unavailable');
    stagedObjects.remove(stagedObjectRef);
  }

  @override
  Future<void> scheduleGarbageCollection(String objectRef) async {
    if (!garbageCollectionRefs.contains(objectRef)) {
      garbageCollectionRefs.add(objectRef);
    }
  }
}

class _FakeLedger implements ArtifactExecutionLedger {
  ContentBundlePlan? claimedPlan;
  ArtifactCommitJournal? journal;
  OperationReceipt? receipt;
  int openCalls = 0;

  @override
  Future<ArtifactExecutionRecord> open(ContentBundlePlan plan) async {
    openCalls++;
    if (claimedPlan != null &&
        jsonEncode(claimedPlan!.toJson()) != jsonEncode(plan.toJson())) {
      throw const ArtifactIdempotencyConflict();
    }
    claimedPlan ??= plan;
    return ArtifactExecutionRecord(journal: journal, receipt: receipt);
  }

  @override
  Future<void> saveJournal(
    DomainOperationBatch batch,
    ArtifactCommitJournal value,
  ) async {
    journal = value;
  }

  @override
  Future<void> saveReceipt(
    DomainOperationBatch batch,
    OperationReceipt value,
  ) async {
    receipt = value;
  }
}

class _FakeDomainRepository implements ArtifactDomainBatchRepository {
  _FakeDomainRepository({required this.stateHash, this.commitError});

  final String stateHash;
  final ArtifactDomainCommitException? commitError;
  int commitCalls = 0;
  int rollbackCalls = 0;
  ContentBundlePlan? lastPlan;
  List<DomainOperation> rolledBack = [];

  @override
  Future<String> readConflictHash(ContentBundlePlan plan) async => stateHash;

  @override
  Future<ArtifactDomainCommitResult> commit(ContentBundlePlan plan) async {
    commitCalls++;
    lastPlan = plan;
    if (commitError != null) throw commitError!;
    return ArtifactDomainCommitResult(
      beforeStateHash: stateHash,
      afterStateHash:
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      committedOperationIds:
          plan.batch.operations.map((value) => value.operationId).toList(),
    );
  }

  @override
  Future<void> rollback(
    ContentBundlePlan plan,
    List<DomainOperation> inverseOperations,
  ) async {
    rollbackCalls++;
    rolledBack = List.from(inverseOperations);
  }
}
