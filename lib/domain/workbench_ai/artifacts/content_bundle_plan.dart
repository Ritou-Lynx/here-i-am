library;

import '../../whiteboard/board.dart';
import '../../whiteboard/card_contract.dart';
import '../../whiteboard/source_content.dart';
import '../../whiteboard/whiteboard_ids.dart';
import 'generated_artifact.dart';
import 'html_artifact_contract.dart';

enum DomainOperationKind { create, update, bind, promote, retract, delete }

class DomainOperation {
  const DomainOperation({
    required this.operationId,
    required this.kind,
    required this.entityType,
    required this.entityId,
    this.payload = const {},
    this.inverse,
  });

  final String operationId;
  final DomainOperationKind kind;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? inverse;

  factory DomainOperation.fromJson(Map<String, dynamic> json) =>
      DomainOperation(
        operationId: StableId(json['operation_id']).value,
        kind: DomainOperationKind.values.byName(json['kind'] as String),
        entityType: json['entity_type'] as String,
        entityId: StableId(json['entity_id']).value,
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        inverse: json['inverse'] == null
            ? null
            : Map<String, dynamic>.from(json['inverse'] as Map),
      );

  Map<String, dynamic> toJson() => {
        'operation_id': operationId,
        'kind': kind.name,
        'entity_type': entityType,
        'entity_id': entityId,
        if (payload.isNotEmpty) 'payload': payload,
        if (inverse != null) 'inverse': inverse,
      };
}

class DomainOperationBatch {
  const DomainOperationBatch({
    required this.batchId,
    required this.authorizationId,
    required this.runtimeTurnId,
    required this.idempotencyKey,
    required this.expectedStateHash,
    required this.operations,
  });

  final String batchId;
  final String authorizationId;
  final String runtimeTurnId;
  final String idempotencyKey;
  final String expectedStateHash;
  final List<DomainOperation> operations;

  factory DomainOperationBatch.fromJson(
    Map<String, dynamic> json,
  ) =>
      DomainOperationBatch(
        batchId: StableId(json['batch_id']).value,
        authorizationId: StableId(json['authorization_id']).value,
        runtimeTurnId: StableId(json['runtime_turn_id']).value,
        idempotencyKey: json['idempotency_key'] as String,
        expectedStateHash: json['expected_state_hash'] as String,
        operations: (json['operations'] as List<dynamic>)
            .map(
              (value) => DomainOperation.fromJson(
                  Map<String, dynamic>.from(value as Map)),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'authorization_id': authorizationId,
        'runtime_turn_id': runtimeTurnId,
        'idempotency_key': idempotencyKey,
        'expected_state_hash': expectedStateHash,
        'operations': operations.map((value) => value.toJson()).toList(),
      };
}

enum OperationReceiptStatus {
  committed,
  replayed,
  rejected,
  rolledBack,
  recoveryRequired;

  String get wireName => switch (this) {
        rolledBack => 'rolled_back',
        recoveryRequired => 'recovery_required',
        _ => name,
      };

  static OperationReceiptStatus fromWire(String value) => switch (value) {
        'committed' => committed,
        'replayed' => replayed,
        'rejected' => rejected,
        'rolled_back' => rolledBack,
        'recovery_required' => recoveryRequired,
        _ => throw ArgumentError('Unknown operation receipt status: $value'),
      };
}

/// Durable result keyed by the same idempotency key as its operation batch.
/// A replay returns the original receipt instead of applying writes again.
class OperationReceipt {
  const OperationReceipt({
    required this.receiptId,
    required this.batchId,
    required this.idempotencyKey,
    required this.status,
    required this.beforeStateHash,
    this.afterStateHash,
    this.committedOperationIds = const [],
    this.inverseOperations = const [],
    this.failureCode,
    required this.occurredAt,
  });

  final String receiptId;
  final String batchId;
  final String idempotencyKey;
  final OperationReceiptStatus status;
  final String beforeStateHash;
  final String? afterStateHash;
  final List<String> committedOperationIds;
  final List<DomainOperation> inverseOperations;
  final String? failureCode;
  final DateTime occurredAt;

  factory OperationReceipt.fromJson(Map<String, dynamic> json) =>
      OperationReceipt(
        receiptId: StableId(json['receipt_id']).value,
        batchId: StableId(json['batch_id']).value,
        idempotencyKey: json['idempotency_key'] as String,
        status: OperationReceiptStatus.fromWire(json['status'] as String),
        beforeStateHash: json['before_state_hash'] as String,
        afterStateHash: json['after_state_hash'] as String?,
        committedOperationIds:
            (json['committed_operation_ids'] as List<dynamic>? ?? const [])
                .cast(),
        inverseOperations:
            (json['inverse_operations'] as List<dynamic>? ?? const [])
                .map((value) => DomainOperation.fromJson(
                      Map<String, dynamic>.from(value as Map),
                    ))
                .toList(),
        failureCode: json['failure_code'] as String?,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'receipt_id': receiptId,
        'batch_id': batchId,
        'idempotency_key': idempotencyKey,
        'status': status.wireName,
        'before_state_hash': beforeStateHash,
        if (afterStateHash != null) 'after_state_hash': afterStateHash,
        'committed_operation_ids': committedOperationIds,
        'inverse_operations':
            inverseOperations.map((value) => value.toJson()).toList(),
        if (failureCode != null) 'failure_code': failureCode,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      };
}

enum ArtifactCommitPhase {
  planned,
  staged,
  hashesVerified,
  committed,
  rolledBack,
  recoveryRequired;

  static ArtifactCommitPhase fromWire(String value) => switch (value) {
        'planned' => planned,
        'staged' => staged,
        'hashes_verified' => hashesVerified,
        'committed' => committed,
        'rolled_back' => rolledBack,
        'recovery_required' => recoveryRequired,
        _ => throw ArgumentError('Unknown artifact commit phase: $value'),
      };

  String get wireName => switch (this) {
        hashesVerified => 'hashes_verified',
        rolledBack => 'rolled_back',
        recoveryRequired => 'recovery_required',
        _ => name,
      };
}

class FailureRecoveryPlan {
  const FailureRecoveryPlan({
    required this.stagedObjectRefsToDelete,
    required this.inverseOperations,
    required this.retryable,
  });

  final List<String> stagedObjectRefsToDelete;
  final List<DomainOperation> inverseOperations;
  final bool retryable;

  factory FailureRecoveryPlan.fromJson(
    Map<String, dynamic> json,
  ) =>
      FailureRecoveryPlan(
        stagedObjectRefsToDelete:
            (json['staged_object_refs_to_delete'] as List<dynamic>).cast(),
        inverseOperations: (json['inverse_operations'] as List<dynamic>)
            .map(
              (value) => DomainOperation.fromJson(
                  Map<String, dynamic>.from(value as Map)),
            )
            .toList(),
        retryable: json['retryable'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'staged_object_refs_to_delete': stagedObjectRefsToDelete,
        'inverse_operations':
            inverseOperations.map((value) => value.toJson()).toList(),
        'retryable': retryable,
      };
}

/// Persisted commit journal for staging -> verification -> atomic binding.
class ArtifactCommitJournal {
  const ArtifactCommitJournal({
    required this.batchId,
    required this.phase,
    this.stagedArtifactIds = const [],
    this.verifiedArtifactIds = const [],
    this.boundArtifactIds = const [],
    this.failureCode,
    this.recovery,
  });

  final String batchId;
  final ArtifactCommitPhase phase;
  final List<String> stagedArtifactIds;
  final List<String> verifiedArtifactIds;
  final List<String> boundArtifactIds;
  final String? failureCode;
  final FailureRecoveryPlan? recovery;

  factory ArtifactCommitJournal.fromJson(Map<String, dynamic> json) =>
      ArtifactCommitJournal(
        batchId: StableId(json['batch_id']).value,
        phase: ArtifactCommitPhase.fromWire(json['phase'] as String),
        stagedArtifactIds:
            (json['staged_artifact_ids'] as List<dynamic>? ?? const []).cast(),
        verifiedArtifactIds:
            (json['verified_artifact_ids'] as List<dynamic>? ?? const [])
                .cast(),
        boundArtifactIds:
            (json['bound_artifact_ids'] as List<dynamic>? ?? const []).cast(),
        failureCode: json['failure_code'] as String?,
        recovery: json['recovery'] == null
            ? null
            : FailureRecoveryPlan.fromJson(
                Map<String, dynamic>.from(json['recovery'] as Map),
              ),
      );

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'phase': phase.wireName,
        'staged_artifact_ids': stagedArtifactIds,
        'verified_artifact_ids': verifiedArtifactIds,
        'bound_artifact_ids': boundArtifactIds,
        if (failureCode != null) 'failure_code': failureCode,
        if (recovery != null) 'recovery': recovery!.toJson(),
      };
}

class ContentBundlePlan {
  const ContentBundlePlan({
    required this.schemaVersion,
    required this.bundleId,
    required this.batch,
    this.artifacts = const [],
    this.htmlRuntimeBundles = const [],
    this.sources = const [],
    this.sourceVersions = const [],
    this.cards = const [],
    this.boards = const [],
    this.boardItems = const [],
    this.groups = const [],
    this.groupMembers = const [],
    this.edges = const [],
    this.promotions = const [],
  });

  final int schemaVersion;
  final String bundleId;
  final DomainOperationBatch batch;
  final List<GeneratedArtifact> artifacts;
  final List<HtmlRuntimeBundle> htmlRuntimeBundles;
  final List<SourceContent> sources;
  final List<SourceVersion> sourceVersions;
  final List<CardContract> cards;
  final List<Board> boards;
  final List<BoardItem> boardItems;
  final List<BoardGroup> groups;
  final List<GroupMember> groupMembers;
  final List<BoardEdge> edges;
  final List<TaskArtifactPromotion> promotions;

  factory ContentBundlePlan.fromJson(Map<String, dynamic> json) {
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) parser) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((value) => parser(Map<String, dynamic>.from(value as Map)))
            .toList();

    return ContentBundlePlan(
      schemaVersion: (json['schema_version'] as num).toInt(),
      bundleId: StableId(json['bundle_id']).value,
      batch: DomainOperationBatch.fromJson(
        Map<String, dynamic>.from(json['batch'] as Map),
      ),
      artifacts: parse('artifacts', GeneratedArtifact.fromJson),
      htmlRuntimeBundles: parse(
        'html_runtime_bundles',
        HtmlRuntimeBundle.fromJson,
      ),
      sources: parse('sources', SourceContent.fromJson),
      sourceVersions: parse('source_versions', SourceVersion.fromJson),
      cards: parse('cards', CardContract.fromJson),
      boards: parse('boards', Board.fromJson),
      boardItems: parse('board_items', BoardItem.fromJson),
      groups: parse('groups', BoardGroup.fromJson),
      groupMembers: parse('group_members', GroupMember.fromJson),
      edges: parse('edges', BoardEdge.fromJson),
      promotions: parse('promotions', TaskArtifactPromotion.fromJson),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'bundle_id': bundleId,
        'batch': batch.toJson(),
        'artifacts': artifacts.map((value) => value.toJson()).toList(),
        'html_runtime_bundles':
            htmlRuntimeBundles.map((value) => value.toJson()).toList(),
        'sources': sources.map((value) => value.toJson()).toList(),
        'source_versions':
            sourceVersions.map((value) => value.toJson()).toList(),
        'cards': cards.map((value) => value.toJson()).toList(),
        'boards': boards.map((value) => value.toJson()).toList(),
        'board_items': boardItems.map((value) => value.toJson()).toList(),
        'groups': groups.map((value) => value.toJson()).toList(),
        'group_members': groupMembers.map((value) => value.toJson()).toList(),
        'edges': edges.map((value) => value.toJson()).toList(),
        'promotions': promotions.map((value) => value.toJson()).toList(),
      };
}
