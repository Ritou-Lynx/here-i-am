library;

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

enum WhiteboardAiWriteStatus {
  applied,
  denied,
  invalidRequest,
  unavailable,
  conflict,
  undone;

  String get wireName => switch (this) {
        WhiteboardAiWriteStatus.invalidRequest => 'invalid_request',
        _ => name,
      };
}

class WhiteboardAiGroupPlan {
  const WhiteboardAiGroupPlan({
    required this.name,
    required this.itemIds,
  });

  final String name;
  final List<String> itemIds;

  Map<String, dynamic> toJson() => {
        'name': name,
        'item_ids': itemIds,
      };
}

class WhiteboardAiEdgePlan {
  const WhiteboardAiEdgePlan({
    required this.fromItemId,
    required this.toItemId,
    this.direction = EdgeDirection.undirected,
    this.semanticType,
    this.label,
  });

  final String fromItemId;
  final String toItemId;
  final EdgeDirection direction;
  final String? semanticType;
  final String? label;

  Map<String, dynamic> toJson() => {
        'from_item_id': fromItemId,
        'to_item_id': toItemId,
        'direction': direction.name,
        if (semanticType != null) 'semantic_type': semanticType,
        if (label != null) 'label': label,
      };
}

class WhiteboardAiGroupAndConnectRequest {
  const WhiteboardAiGroupAndConnectRequest({
    required this.operationBatchId,
    required this.authorizationId,
    required this.runtimeTurnId,
    required this.boardId,
    this.groups = const [],
    this.edges = const [],
  });

  final String operationBatchId;
  final String authorizationId;
  final String runtimeTurnId;
  final String boardId;
  final List<WhiteboardAiGroupPlan> groups;
  final List<WhiteboardAiEdgePlan> edges;

  Map<String, dynamic> toJson() => {
        'operation_batch_id': operationBatchId,
        'authorization_id': authorizationId,
        'runtime_turn_id': runtimeTurnId,
        'board_id': boardId,
        'groups': groups.map((value) => value.toJson()).toList(),
        'edges': edges.map((value) => value.toJson()).toList(),
      };
}

class WhiteboardAiUndoRequest {
  const WhiteboardAiUndoRequest({
    required this.undoToken,
    required this.runtimeTurnId,
  });

  final String undoToken;
  final String runtimeTurnId;
}

class WhiteboardAiWriteIssue {
  const WhiteboardAiWriteIssue(this.code, [this.detail]);

  final String code;
  final String? detail;

  Map<String, dynamic> toJson() => {
        'code': code,
        if (detail != null) 'detail': detail,
      };
}

class WhiteboardAiWriteReceipt {
  const WhiteboardAiWriteReceipt({
    required this.status,
    required this.operationBatchId,
    required this.runtimeTurnId,
    required this.boardId,
    required this.summary,
    this.authorizationId,
    this.userAuthorizationMessageId,
    this.beforeSnapshotHash,
    this.afterSnapshotHash,
    this.undoToken,
    this.operations = const [],
    this.issues = const [],
    required this.occurredAt,
  });

  final WhiteboardAiWriteStatus status;
  final String operationBatchId;
  final String runtimeTurnId;
  final String boardId;
  final String summary;
  final String? authorizationId;
  final String? userAuthorizationMessageId;
  final String? beforeSnapshotHash;
  final String? afterSnapshotHash;
  final String? undoToken;
  final List<WhiteboardOperation> operations;
  final List<WhiteboardAiWriteIssue> issues;
  final DateTime occurredAt;

  bool get succeeded =>
      status == WhiteboardAiWriteStatus.applied ||
      status == WhiteboardAiWriteStatus.undone;

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'status': status.wireName,
        'operation_batch_id': operationBatchId,
        'runtime_turn_id': runtimeTurnId,
        'board_id': boardId,
        'summary': summary,
        if (authorizationId != null) 'authorization_id': authorizationId,
        if (userAuthorizationMessageId != null)
          'user_authorization_message_id': userAuthorizationMessageId,
        if (beforeSnapshotHash != null)
          'before_snapshot_hash': beforeSnapshotHash,
        if (afterSnapshotHash != null) 'after_snapshot_hash': afterSnapshotHash,
        if (undoToken != null) 'undo_token': undoToken,
        'operations': operations.map((value) => value.toJson()).toList(),
        if (issues.isNotEmpty)
          'issues': issues.map((value) => value.toJson()).toList(),
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      };
}
