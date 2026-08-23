library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'artifact_contract_validation.dart';
import 'content_bundle_plan.dart';
import 'generated_artifact.dart';

/// A single-use, provider-neutral view of an object already placed in the
/// controlled staging area.
class StagedArtifactObject {
  const StagedArtifactObject({required this.mimeType, required this.bytes});

  final String mimeType;
  final Stream<List<int>> bytes;
}

/// Content-addressed storage boundary used by [ArtifactBundleExecutor].
///
/// Implementations must resolve refs below configured roots, make
/// [commitVerified] idempotent (including staging already moved but a matching
/// final object present), and never delete final objects on an error path.
/// Final objects are instead offered to delayed garbage collection.
abstract interface class ArtifactObjectStore {
  Future<StagedArtifactObject> openStaged(String stagedObjectRef);

  Future<void> commitVerified(ArtifactManifest manifest);

  Future<void> deleteStaged(String stagedObjectRef);

  Future<void> scheduleGarbageCollection(String objectRef);
}

/// Durable idempotency and recovery boundary.
///
/// [open] atomically claims an idempotency key for the exact plan, or returns
/// its existing checkpoint/receipt. A key claimed by a different plan must
/// fail closed with [ArtifactIdempotencyConflict]. Journal and receipt saves
/// must be atomic and idempotent; after an uncertain save, the next [open]
/// must expose either the prior or the newly durable value.
abstract interface class ArtifactExecutionLedger {
  Future<ArtifactExecutionRecord> open(ContentBundlePlan plan);

  Future<void> saveJournal(
    DomainOperationBatch batch,
    ArtifactCommitJournal journal,
  );

  Future<void> saveReceipt(
    DomainOperationBatch batch,
    OperationReceipt receipt,
  );
}

class ArtifactExecutionRecord {
  const ArtifactExecutionRecord({this.journal, this.receipt});

  final ArtifactCommitJournal? journal;
  final OperationReceipt? receipt;
}

/// Result of the product transaction. The repository owns the actual Card,
/// Source, Board and binding persistence and must enforce the conflict hash in
/// the same transaction as the operations.
class ArtifactDomainCommitResult {
  const ArtifactDomainCommitResult({
    required this.beforeStateHash,
    required this.afterStateHash,
    required this.committedOperationIds,
  });

  final String beforeStateHash;
  final String afterStateHash;
  final List<String> committedOperationIds;
}

/// Product-domain persistence boundary. It deliberately exposes no Drift or
/// shared Repository type.
abstract interface class ArtifactDomainBatchRepository {
  Future<String> readConflictHash(ContentBundlePlan plan);

  /// Returns the durable result for an already committed exact plan.
  ///
  /// Non-null proves that every domain write and binding committed; null must
  /// prove that none did. An adapter unable to prove either outcome must throw
  /// [ArtifactExecutionPending] instead of returning null.
  Future<ArtifactDomainCommitResult?> lookupCommit(ContentBundlePlan plan);

  /// Atomically applies the declared domain operations and artifact bindings.
  /// Repeating the same exact plan must return the first durable result. That
  /// result must become visible to [lookupCommit] atomically with the writes.
  Future<ArtifactDomainCommitResult> commit(ContentBundlePlan plan);

  /// Applies the supplied inverse operations in order, guarded by repository
  /// state. It must itself be idempotent so recovery can continue after a
  /// process restart.
  Future<void> rollback(
    ContentBundlePlan plan,
    List<DomainOperation> inverseOperations,
  );
}

class ArtifactExecutionException implements Exception {
  const ArtifactExecutionException(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  @override
  String toString() => 'ArtifactExecutionException($code)';
}

class ArtifactIdempotencyConflict extends ArtifactExecutionException {
  const ArtifactIdempotencyConflict() : super('artifact_idempotency_conflict');
}

/// The core cannot prove whether an external side effect happened yet.
/// Pending never triggers rollback, staging deletion, GC or rejection.
class ArtifactExecutionPending extends ArtifactExecutionException {
  const ArtifactExecutionPending(super.code) : super(retryable: true);
}

/// A domain adapter may report operations that escaped an otherwise failed
/// transaction. The executor will immediately run only their declared inverse
/// operations; adapters should normally remain atomic and leave this empty.
class ArtifactDomainCommitException extends ArtifactExecutionException {
  const ArtifactDomainCommitException(
    super.code, {
    super.retryable,
    this.committedOperationIds = const [],
  });

  final List<String> committedOperationIds;
}

typedef ArtifactClock = DateTime Function();

/// Minimal executor for staging verification, content-addressed commit,
/// product binding, durable receipt, rollback, recovery and idempotent replay.
class ArtifactBundleExecutor {
  ArtifactBundleExecutor({
    required ArtifactObjectStore objectStore,
    required ArtifactExecutionLedger ledger,
    required ArtifactDomainBatchRepository domainRepository,
    ArtifactBudget budget = const ArtifactBudget(),
    ArtifactClock? clock,
  })  : _objectStore = objectStore,
        _ledger = ledger,
        _domainRepository = domainRepository,
        _budget = budget,
        _clock = clock ?? DateTime.now;

  final ArtifactObjectStore _objectStore;
  final ArtifactExecutionLedger _ledger;
  final ArtifactDomainBatchRepository _domainRepository;
  final ArtifactBudget _budget;
  final ArtifactClock _clock;

  Future<OperationReceipt> execute(ContentBundlePlan plan) async {
    final issues = validateContentBundlePlan(plan, budget: _budget);
    if (issues.isNotEmpty) {
      throw ArtifactExecutionException(
        'artifact_contract_invalid:${issues.first.code}',
      );
    }

    final record = await _ledger.open(plan);
    if (record.receipt != null) {
      await _deleteStaging(plan.artifacts);
      return record.receipt!;
    }
    final stagedIds = plan.artifacts
        .map((artifact) => artifact.manifest.artifactId)
        .toList(growable: false);
    var journal = record.journal ??
        ArtifactCommitJournal(
          batchId: plan.batch.batchId,
          phase: ArtifactCommitPhase.planned,
        );
    if (record.journal == null) {
      await _saveJournal(plan, journal);
    }

    while (true) {
      switch (journal.phase) {
        case ArtifactCommitPhase.planned:
          journal = ArtifactCommitJournal(
            batchId: plan.batch.batchId,
            phase: ArtifactCommitPhase.staged,
            stagedArtifactIds: stagedIds,
          );
          await _saveJournal(plan, journal);
          continue;
        case ArtifactCommitPhase.staged:
          try {
            await _verifyAll(plan.artifacts);
          } on ArtifactExecutionException catch (error) {
            return _failAndRecover(
              plan,
              code: error.code,
              stagedArtifactIds: stagedIds,
              retryable: error.retryable,
            );
          } on Exception {
            throw const ArtifactExecutionPending('staging_read_pending');
          }
          journal = ArtifactCommitJournal(
            batchId: plan.batch.batchId,
            phase: ArtifactCommitPhase.hashesVerified,
            stagedArtifactIds: stagedIds,
            verifiedArtifactIds: stagedIds,
          );
          await _saveJournal(plan, journal);
          continue;
        case ArtifactCommitPhase.hashesVerified:
          final resumed = await _resumeVerified(plan, journal);
          if (resumed.receipt != null) return resumed.receipt!;
          journal = resumed.journal!;
          continue;
        case ArtifactCommitPhase.committed:
          return _resumeCommitted(plan);
        case ArtifactCommitPhase.recoveryRequired:
          return _recover(plan, journal);
        case ArtifactCommitPhase.rolledBack:
          throw const ArtifactExecutionPending(
            'rolled_back_journal_without_receipt',
          );
      }
    }
  }

  Future<ArtifactExecutionRecord> _resumeVerified(
    ContentBundlePlan plan,
    ArtifactCommitJournal journal,
  ) async {
    ArtifactDomainCommitResult? result;
    try {
      result = await _domainRepository.lookupCommit(plan);
    } on ArtifactExecutionPending {
      rethrow;
    } on Exception {
      throw const ArtifactExecutionPending('domain_lookup_pending');
    }

    String? beforeHash;
    if (result == null) {
      try {
        beforeHash = await _domainRepository.readConflictHash(plan);
      } on Exception {
        throw const ArtifactExecutionPending('conflict_hash_pending');
      }
      if (beforeHash != plan.batch.expectedStateHash) {
        return ArtifactExecutionRecord(
          receipt: await _failAndRecover(
            plan,
            code: 'expected_state_hash_conflict',
            stagedArtifactIds: journal.stagedArtifactIds,
            retryable: false,
            beforeStateHash: beforeHash,
          ),
        );
      }
    }

    try {
      for (final artifact in plan.artifacts) {
        // If a previous process already moved staging, the store verifies the
        // matching final object and succeeds without writing it again.
        await _objectStore.commitVerified(artifact.manifest);
      }
    } on Exception {
      throw const ArtifactExecutionPending('object_commit_pending');
    }

    if (result == null) {
      try {
        result = await _domainRepository.commit(plan);
      } on ArtifactDomainCommitException catch (error) {
        return ArtifactExecutionRecord(
          receipt: await _failAndRecover(
            plan,
            code: error.code,
            stagedArtifactIds: journal.stagedArtifactIds,
            inverseOperations: _inverseForCommitted(
              plan.batch.operations,
              error.committedOperationIds,
            ),
            retryable: error.retryable,
            beforeStateHash: beforeHash,
          ),
        );
      } on ArtifactExecutionPending {
        rethrow;
      } on Exception {
        throw const ArtifactExecutionPending('domain_commit_outcome_pending');
      }
    }

    _validateDomainResult(plan, result);
    final committed = ArtifactCommitJournal(
      batchId: plan.batch.batchId,
      phase: ArtifactCommitPhase.committed,
      stagedArtifactIds: journal.stagedArtifactIds,
      verifiedArtifactIds: journal.verifiedArtifactIds,
      boundArtifactIds: journal.verifiedArtifactIds,
    );
    await _saveJournal(plan, committed);
    return ArtifactExecutionRecord(journal: committed);
  }

  Future<OperationReceipt> _resumeCommitted(ContentBundlePlan plan) async {
    ArtifactDomainCommitResult? result;
    try {
      result = await _domainRepository.lookupCommit(plan);
    } on ArtifactExecutionPending {
      rethrow;
    } on Exception {
      throw const ArtifactExecutionPending('domain_lookup_pending');
    }
    if (result == null) {
      throw const ArtifactExecutionPending(
        'committed_journal_without_domain_result',
      );
    }
    _validateDomainResult(plan, result);
    final receipt = _committedReceipt(plan, result);
    try {
      await _ledger.saveReceipt(plan.batch, receipt);
    } on Exception {
      throw const ArtifactExecutionPending('receipt_persist_pending');
    }
    await _deleteStaging(plan.artifacts);
    return receipt;
  }

  void _validateDomainResult(
    ContentBundlePlan plan,
    ArtifactDomainCommitResult result,
  ) {
    final expectedOperationIds = plan.batch.operations.map(
      (operation) => operation.operationId,
    );
    if (result.beforeStateHash != plan.batch.expectedStateHash ||
        !_sameIds(result.committedOperationIds, expectedOperationIds)) {
      throw const ArtifactExecutionPending('domain_commit_result_invalid');
    }
  }

  OperationReceipt _committedReceipt(
    ContentBundlePlan plan,
    ArtifactDomainCommitResult result,
  ) =>
      OperationReceipt(
        receiptId: _receiptId(plan.batch.batchId),
        batchId: plan.batch.batchId,
        idempotencyKey: plan.batch.idempotencyKey,
        status: OperationReceiptStatus.committed,
        beforeStateHash: result.beforeStateHash,
        afterStateHash: result.afterStateHash,
        committedOperationIds: List.unmodifiable(result.committedOperationIds),
        inverseOperations: _inverseOperations(plan.batch.operations),
        occurredAt: _clock().toUtc(),
      );

  Future<void> _verifyAll(List<GeneratedArtifact> artifacts) async {
    for (final artifact in artifacts) {
      final manifest = artifact.manifest;
      final staged = await _objectStore.openStaged(manifest.stagedObjectRef);
      if (staged.mimeType != manifest.mimeType) {
        throw const ArtifactExecutionException('artifact_mime_mismatch');
      }
      final digestSink = _SingleDigestSink();
      final hashSink = sha256.startChunkedConversion(digestSink);
      var sizeBytes = 0;
      await for (final chunk in staged.bytes) {
        sizeBytes += chunk.length;
        if (sizeBytes > _budget.maxArtifactBytes ||
            sizeBytes > manifest.sizeBytes) {
          hashSink.close();
          throw const ArtifactExecutionException('artifact_size_mismatch');
        }
        hashSink.add(chunk);
      }
      hashSink.close();
      if (sizeBytes != manifest.sizeBytes) {
        throw const ArtifactExecutionException('artifact_size_mismatch');
      }
      if (digestSink.value.toString() != manifest.sha256) {
        throw const ArtifactExecutionException('artifact_hash_mismatch');
      }
    }
  }

  Future<OperationReceipt> _failAndRecover(
    ContentBundlePlan plan, {
    required String code,
    required List<String> stagedArtifactIds,
    required bool retryable,
    List<DomainOperation> inverseOperations = const [],
    String? beforeStateHash,
  }) async {
    final recovery = FailureRecoveryPlan(
      stagedObjectRefsToDelete: plan.artifacts
          .map((artifact) => artifact.manifest.stagedObjectRef)
          .toList(growable: false),
      inverseOperations: inverseOperations,
      retryable: retryable,
    );
    final journal = ArtifactCommitJournal(
      batchId: plan.batch.batchId,
      phase: ArtifactCommitPhase.recoveryRequired,
      stagedArtifactIds: stagedArtifactIds,
      verifiedArtifactIds: const [],
      boundArtifactIds: const [],
      failureCode: code,
      recovery: recovery,
    );
    await _saveJournal(plan, journal);
    return _recover(plan, journal, beforeStateHash: beforeStateHash);
  }

  Future<OperationReceipt> _recover(
    ContentBundlePlan plan,
    ArtifactCommitJournal journal, {
    String? beforeStateHash,
  }) async {
    final recovery = journal.recovery!;
    try {
      if (recovery.inverseOperations.isNotEmpty) {
        await _domainRepository.rollback(plan, recovery.inverseOperations);
      }
      // Delayed GC must be reference-aware, so offering every declared final
      // ref is safe and also makes recovery complete after a process restart
      // where the executor no longer knows which renames finished.
      for (final objectRef in plan.artifacts.map(
        (artifact) => artifact.manifest.objectRef,
      )) {
        await _objectStore.scheduleGarbageCollection(objectRef);
      }
      for (final stagedRef in recovery.stagedObjectRefsToDelete) {
        await _objectStore.deleteStaged(stagedRef);
      }
    } catch (_) {
      throw ArtifactExecutionException(
        'artifact_recovery_pending:${journal.failureCode}',
        retryable: true,
      );
    }

    final status = recovery.inverseOperations.isEmpty
        ? OperationReceiptStatus.rejected
        : OperationReceiptStatus.rolledBack;
    final receipt = OperationReceipt(
      receiptId: _receiptId(plan.batch.batchId),
      batchId: plan.batch.batchId,
      idempotencyKey: plan.batch.idempotencyKey,
      status: status,
      beforeStateHash: beforeStateHash ?? plan.batch.expectedStateHash,
      committedOperationIds: const [],
      inverseOperations: recovery.inverseOperations,
      failureCode: journal.failureCode,
      occurredAt: _clock().toUtc(),
    );
    try {
      await _ledger.saveReceipt(plan.batch, receipt);
    } on Exception {
      throw const ArtifactExecutionPending('receipt_persist_pending');
    }
    await _saveJournal(
      plan,
      ArtifactCommitJournal(
        batchId: plan.batch.batchId,
        phase: ArtifactCommitPhase.rolledBack,
        stagedArtifactIds: journal.stagedArtifactIds,
        verifiedArtifactIds: journal.verifiedArtifactIds,
        boundArtifactIds: const [],
        failureCode: journal.failureCode,
      ),
    );
    return receipt;
  }

  Future<void> _saveJournal(
    ContentBundlePlan plan,
    ArtifactCommitJournal journal,
  ) async {
    final issues = validateCommitJournal(journal);
    if (issues.isNotEmpty) {
      throw StateError('Invalid executor journal: ${issues.first.code}');
    }
    try {
      await _ledger.saveJournal(plan.batch, journal);
    } on Exception {
      throw const ArtifactExecutionPending('journal_persist_pending');
    }
  }

  Future<void> _deleteStaging(List<GeneratedArtifact> artifacts) async {
    for (final artifact in artifacts) {
      try {
        await _objectStore.deleteStaged(artifact.manifest.stagedObjectRef);
      } catch (_) {
        // A committed receipt is authoritative. Staging cleanup is safe to
        // retry independently and must never turn a commit into a failure.
      }
    }
  }
}

List<DomainOperation> _inverseOperations(
  Iterable<DomainOperation> operations,
) =>
    operations.toList().reversed.map(_toInverseOperation).toList();

List<DomainOperation> _inverseForCommitted(
  Iterable<DomainOperation> operations,
  Iterable<String> committedOperationIds,
) {
  final committed = committedOperationIds.toSet();
  return operations
      .where((operation) => committed.contains(operation.operationId))
      .toList()
      .reversed
      .map(_toInverseOperation)
      .toList();
}

DomainOperation _toInverseOperation(DomainOperation operation) {
  final inverse = operation.inverse!;
  return DomainOperation(
    operationId: '${operation.operationId}_inverse',
    kind: inverse.kind,
    entityType: inverse.entityType,
    entityId: inverse.entityId,
    payload: inverse.payload,
  );
}

bool _sameIds(Iterable<String> left, Iterable<String> right) {
  final leftList = left.toList();
  final rightList = right.toList();
  return leftList.length == rightList.length &&
      leftList.toSet().containsAll(rightList);
}

String _receiptId(String batchId) {
  final bytes = utf8.encode(batchId);
  return 'receipt_${sha256.convert(bytes).toString().substring(0, 24)}';
}

class _SingleDigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value ?? (throw StateError('Digest not completed'));

  @override
  void add(Digest data) {
    if (_value != null) throw StateError('Digest emitted more than once');
    _value = data;
  }

  @override
  void close() {}
}
