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
    this.undoReceipt,
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
  final Map<String, dynamic>? undoReceipt;

  Map<String, dynamic> toUndoReceiptEnvelope({
    required WhiteboardSnapshot beforeSnapshot,
  }) =>
      {
        ...toUndoReceiptJson(),
        'before_snapshot': beforeSnapshot.toJson(),
      };

  factory WhiteboardAiWriteReceipt.fromJson(Map<String, dynamic> json) {
    const keys = {
      'schema_version',
      'status',
      'operation_batch_id',
      'runtime_turn_id',
      'board_id',
      'summary',
      'authorization_id',
      'user_authorization_message_id',
      'before_snapshot_hash',
      'after_snapshot_hash',
      'undo_token',
      'operations',
      'issues',
      'occurred_at',
      'undo_receipt',
    };
    if (json['schema_version'] != 1 ||
        json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unsupported write receipt schema');
    }
    return WhiteboardAiWriteReceipt(
      status: _receiptStatus(json['status']),
      operationBatchId: _string(json, 'operation_batch_id'),
      runtimeTurnId: _string(json, 'runtime_turn_id'),
      boardId: _string(json, 'board_id'),
      summary: _string(json, 'summary'),
      authorizationId: _optionalString(json['authorization_id']),
      userAuthorizationMessageId:
          _optionalString(json['user_authorization_message_id']),
      beforeSnapshotHash: _optionalString(json['before_snapshot_hash']),
      afterSnapshotHash: _optionalString(json['after_snapshot_hash']),
      undoToken: _optionalString(json['undo_token']),
      operations: _operations(json['operations']),
      issues: _issues(json['issues']),
      occurredAt: DateTime.parse(_string(json, 'occurred_at')).toUtc(),
      undoReceipt: _optionalMap(json['undo_receipt']),
    );
  }

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
        if (undoReceipt != null) 'undo_receipt': undoReceipt,
      };

  Map<String, dynamic> toUndoReceiptJson() => {
        'schema_version': 1,
        'status': status.wireName,
        'operation_batch_id': operationBatchId,
        'runtime_turn_id': runtimeTurnId,
        'board_id': boardId,
        'summary': summary,
        if (authorizationId != null) 'authorization_id': authorizationId,
        if (userAuthorizationMessageId != null)
          'user_authorization_message_id': userAuthorizationMessageId,
        if (beforeSnapshotHash != null) 'before_snapshot_hash': beforeSnapshotHash,
        if (afterSnapshotHash != null) 'after_snapshot_hash': afterSnapshotHash,
        if (undoToken != null) 'undo_token': undoToken,
        if (issues.isNotEmpty) 'issues': issues.map((value) => value.toJson()).toList(),
        'operations': operations.map((value) => value.toJson()).toList(),
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      };
}

WhiteboardAiWriteStatus _receiptStatus(Object? value) => switch (value) {
      'invalid_request' => WhiteboardAiWriteStatus.invalidRequest,
      'applied' => WhiteboardAiWriteStatus.applied,
      'denied' => WhiteboardAiWriteStatus.denied,
      'conflict' => WhiteboardAiWriteStatus.conflict,
      'undone' => WhiteboardAiWriteStatus.undone,
      _ => throw const FormatException('Unknown write receipt status'),
    };

String _string(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return result;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid optional string');
  }
  return value;
}

List<WhiteboardOperation> _operations(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => WhiteboardOperation.fromJson(_asMap(item)))
      .toList(growable: false);
}

List<WhiteboardAiWriteIssue> _issues(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item is Map
          ? WhiteboardAiWriteIssue(item['code']?.toString() ?? '')
          : throw const FormatException('Issue must be object'))
      .toList(growable: false);
}

Map<String, dynamic>? _optionalMap(Object? value) {
  if (value == null) return null;
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected object map');
  return Map<String, dynamic>.from(value);
}
