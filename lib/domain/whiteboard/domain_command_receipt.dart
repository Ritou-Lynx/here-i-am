library;

import 'domain_command.dart';

enum WhiteboardDomainCommandStatus {
  applied,
  denied,
  invalidRequest,
  unavailable,
  conflict,
  undone;

  String get wireName => switch (this) {
    WhiteboardDomainCommandStatus.invalidRequest => 'invalid_request',
    _ => name,
  };

  static WhiteboardDomainCommandStatus parse(Object? value) => switch (value) {
    'applied' => WhiteboardDomainCommandStatus.applied,
    'denied' => WhiteboardDomainCommandStatus.denied,
    'invalid_request' => WhiteboardDomainCommandStatus.invalidRequest,
    'unavailable' => WhiteboardDomainCommandStatus.unavailable,
    'conflict' => WhiteboardDomainCommandStatus.conflict,
    'undone' => WhiteboardDomainCommandStatus.undone,
    _ => throw const FormatException('Unknown domain command status'),
  };
}

class WhiteboardDomainCommandIssue {
  const WhiteboardDomainCommandIssue(this.code, [this.detail]);

  factory WhiteboardDomainCommandIssue.fromJson(Map<String, dynamic> json) =>
      WhiteboardDomainCommandIssue(
        json['code'] as String,
        json['detail'] as String?,
      );

  final String code;
  final String? detail;

  Map<String, dynamic> toJson() => {
    'code': code,
    if (detail != null) 'detail': detail,
  };
}

class WhiteboardDomainUndoReceipt {
  const WhiteboardDomainUndoReceipt({
    required this.undoToken,
    required this.operationBatchId,
    required this.boardId,
    required this.afterSnapshotHash,
    required this.inverseSteps,
  });

  factory WhiteboardDomainUndoReceipt.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 || json['inverse_steps'] is! List) {
      throw const FormatException('Unsupported domain undo receipt');
    }
    return WhiteboardDomainUndoReceipt(
      undoToken: json['undo_token'] as String,
      operationBatchId: json['operation_batch_id'] as String,
      boardId: json['board_id'] as String,
      afterSnapshotHash: json['after_snapshot_hash'] as String,
      inverseSteps: (json['inverse_steps'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(growable: false),
    );
  }

  final String undoToken;
  final String operationBatchId;
  final String boardId;
  final String afterSnapshotHash;
  final List<Map<String, dynamic>> inverseSteps;

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'undo_token': undoToken,
    'operation_batch_id': operationBatchId,
    'board_id': boardId,
    'after_snapshot_hash': afterSnapshotHash,
    'inverse_steps': inverseSteps,
  };
}

class WhiteboardDomainCommandReceipt {
  const WhiteboardDomainCommandReceipt({
    required this.status,
    required this.operationBatchId,
    required this.boardId,
    required this.commandIds,
    required this.summary,
    required this.occurredAt,
    this.authorizationId,
    this.beforeSnapshotHash,
    this.afterSnapshotHash,
    this.undoReceipt,
    this.issues = const [],
  });

  factory WhiteboardDomainCommandReceipt.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1) {
      throw const FormatException('Unsupported domain command receipt');
    }
    final commandIds = json['command_ids'];
    final issues = json['issues'];
    if (commandIds is! List || issues is! List) {
      throw const FormatException('Invalid domain command receipt');
    }
    return WhiteboardDomainCommandReceipt(
      status: WhiteboardDomainCommandStatus.parse(json['status']),
      operationBatchId: json['operation_batch_id'] as String,
      boardId: json['board_id'] as String,
      commandIds: commandIds.cast<String>(),
      summary: json['summary'] as String,
      occurredAt: DateTime.parse(json['occurred_at'] as String).toUtc(),
      authorizationId: json['authorization_id'] as String?,
      beforeSnapshotHash: json['before_snapshot_hash'] as String?,
      afterSnapshotHash: json['after_snapshot_hash'] as String?,
      undoReceipt: json['undo_receipt'] == null
          ? null
          : WhiteboardDomainUndoReceipt.fromJson(
              Map<String, dynamic>.from(json['undo_receipt'] as Map),
            ),
      issues: issues
          .map(
            (value) => WhiteboardDomainCommandIssue.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final WhiteboardDomainCommandStatus status;
  final String operationBatchId;
  final String boardId;
  final List<String> commandIds;
  final String summary;
  final DateTime occurredAt;
  final String? authorizationId;
  final String? beforeSnapshotHash;
  final String? afterSnapshotHash;
  final WhiteboardDomainUndoReceipt? undoReceipt;
  final List<WhiteboardDomainCommandIssue> issues;

  bool get succeeded =>
      status == WhiteboardDomainCommandStatus.applied ||
      status == WhiteboardDomainCommandStatus.undone;

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'status': status.wireName,
    'operation_batch_id': operationBatchId,
    'board_id': boardId,
    'command_ids': commandIds,
    'summary': summary,
    if (authorizationId != null) 'authorization_id': authorizationId,
    if (beforeSnapshotHash != null) 'before_snapshot_hash': beforeSnapshotHash,
    if (afterSnapshotHash != null) 'after_snapshot_hash': afterSnapshotHash,
    if (undoReceipt != null) 'undo_receipt': undoReceipt!.toJson(),
    'issues': issues.map((issue) => issue.toJson()).toList(),
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };
}

class WhiteboardDomainExecutionRequest {
  const WhiteboardDomainExecutionRequest({
    required this.batch,
    required this.authorizationId,
    required this.actorTurnId,
    required this.actor,
  });

  final WhiteboardDomainCommandBatch batch;
  final String authorizationId;
  final String actorTurnId;
  final WhiteboardDomainCommandActor actor;
}

enum WhiteboardDomainCommandActor { user, i }
