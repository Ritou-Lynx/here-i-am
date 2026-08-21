library;

enum WorkbenchActionStatus {
  running,
  completed,
  failed,
  undone;

  static WorkbenchActionStatus parse(Object? value) => switch (value) {
        'running' => WorkbenchActionStatus.running,
        'completed' => WorkbenchActionStatus.completed,
        'failed' => WorkbenchActionStatus.failed,
        'undone' => WorkbenchActionStatus.undone,
        _ => throw const FormatException('Unknown workbench action status'),
      };
}

class WorkbenchActionProjection {
  WorkbenchActionProjection({
    required this.actionId,
    required this.actionType,
    required this.title,
    required this.status,
    required this.boardId,
    required this.selectedItemCount,
    required this.summary,
    required this.createdAt,
    required this.updatedAt,
    this.groupCount = 0,
    this.edgeCount = 0,
    this.runtimeSessionId,
    this.runtimeTurnId,
    this.operationBatchId,
    this.authorizationId,
    this.userAuthorizationMessageId,
    this.beforeSnapshotHash,
    this.afterSnapshotHash,
    this.undoToken,
    this.errorCode,
    this.tools = const [],
  }) {
    _requireId(actionId, 'actionId');
    _requireId(actionType, 'actionType');
    _requireId(boardId, 'boardId');
    _requireText(title, 'title', 120);
    _requireText(summary, 'summary', 600);
    if (selectedItemCount < 0 || selectedItemCount > 64) {
      throw RangeError.range(selectedItemCount, 0, 64, 'selectedItemCount');
    }
    if (groupCount < 0 || groupCount > 16) {
      throw RangeError.range(groupCount, 0, 16, 'groupCount');
    }
    if (edgeCount < 0 || edgeCount > 32) {
      throw RangeError.range(edgeCount, 0, 32, 'edgeCount');
    }
    if (updatedAt.isBefore(createdAt)) {
      throw ArgumentError('updatedAt cannot precede createdAt');
    }
    for (final value in [
      runtimeSessionId,
      runtimeTurnId,
      operationBatchId,
      authorizationId,
      userAuthorizationMessageId,
      undoToken,
      errorCode,
    ]) {
      if (value != null) _requireId(value, 'optionalId');
    }
    for (final hash in [beforeSnapshotHash, afterSnapshotHash]) {
      if (hash != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw ArgumentError('snapshot hashes must be SHA-256 hex');
      }
    }
    if (tools.length > 16) throw RangeError('tools exceeds 16 entries');
    for (final tool in tools) {
      _requireId(tool, 'tools[]');
    }
  }

  factory WorkbenchActionProjection.fromJson(Map<String, dynamic> json) {
    const keys = {
      'schema_version',
      'action_id',
      'action_type',
      'title',
      'status',
      'board_id',
      'selected_item_count',
      'group_count',
      'edge_count',
      'summary',
      'runtime_session_id',
      'runtime_turn_id',
      'operation_batch_id',
      'authorization_id',
      'user_authorization_message_id',
      'before_snapshot_hash',
      'after_snapshot_hash',
      'undo_token',
      'error_code',
      'tools',
      'created_at',
      'updated_at',
    };
    if (json['schema_version'] != 1 ||
        json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unsupported workbench action projection');
    }
    return WorkbenchActionProjection(
      actionId: _string(json, 'action_id'),
      actionType: _string(json, 'action_type'),
      title: _string(json, 'title'),
      status: WorkbenchActionStatus.parse(json['status']),
      boardId: _string(json, 'board_id'),
      selectedItemCount: _integer(json, 'selected_item_count'),
      groupCount: _integer(json, 'group_count'),
      edgeCount: _integer(json, 'edge_count'),
      summary: _string(json, 'summary'),
      runtimeSessionId: _optionalString(json['runtime_session_id']),
      runtimeTurnId: _optionalString(json['runtime_turn_id']),
      operationBatchId: _optionalString(json['operation_batch_id']),
      authorizationId: _optionalString(json['authorization_id']),
      userAuthorizationMessageId:
          _optionalString(json['user_authorization_message_id']),
      beforeSnapshotHash: _optionalString(json['before_snapshot_hash']),
      afterSnapshotHash: _optionalString(json['after_snapshot_hash']),
      undoToken: _optionalString(json['undo_token']),
      errorCode: _optionalString(json['error_code']),
      tools: _stringList(json['tools']),
      createdAt: DateTime.parse(_string(json, 'created_at')).toUtc(),
      updatedAt: DateTime.parse(_string(json, 'updated_at')).toUtc(),
    );
  }

  final String actionId;
  final String actionType;
  final String title;
  final WorkbenchActionStatus status;
  final String boardId;
  final int selectedItemCount;
  final int groupCount;
  final int edgeCount;
  final String summary;
  final String? runtimeSessionId;
  final String? runtimeTurnId;
  final String? operationBatchId;
  final String? authorizationId;
  final String? userAuthorizationMessageId;
  final String? beforeSnapshotHash;
  final String? afterSnapshotHash;
  final String? undoToken;
  final String? errorCode;
  final List<String> tools;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal => status != WorkbenchActionStatus.running;

  WorkbenchActionProjection copyWith({
    WorkbenchActionStatus? status,
    String? summary,
    int? groupCount,
    int? edgeCount,
    String? runtimeSessionId,
    String? runtimeTurnId,
    String? operationBatchId,
    String? authorizationId,
    String? userAuthorizationMessageId,
    String? beforeSnapshotHash,
    String? afterSnapshotHash,
    String? undoToken,
    String? errorCode,
    List<String>? tools,
    DateTime? updatedAt,
  }) {
    return WorkbenchActionProjection(
      actionId: actionId,
      actionType: actionType,
      title: title,
      status: status ?? this.status,
      boardId: boardId,
      selectedItemCount: selectedItemCount,
      groupCount: groupCount ?? this.groupCount,
      edgeCount: edgeCount ?? this.edgeCount,
      summary: summary ?? this.summary,
      runtimeSessionId: runtimeSessionId ?? this.runtimeSessionId,
      runtimeTurnId: runtimeTurnId ?? this.runtimeTurnId,
      operationBatchId: operationBatchId ?? this.operationBatchId,
      authorizationId: authorizationId ?? this.authorizationId,
      userAuthorizationMessageId:
          userAuthorizationMessageId ?? this.userAuthorizationMessageId,
      beforeSnapshotHash: beforeSnapshotHash ?? this.beforeSnapshotHash,
      afterSnapshotHash: afterSnapshotHash ?? this.afterSnapshotHash,
      undoToken: undoToken ?? this.undoToken,
      errorCode: errorCode ?? this.errorCode,
      tools: tools ?? this.tools,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'action_id': actionId,
        'action_type': actionType,
        'title': title,
        'status': status.name,
        'board_id': boardId,
        'selected_item_count': selectedItemCount,
        'group_count': groupCount,
        'edge_count': edgeCount,
        'summary': summary,
        if (runtimeSessionId != null) 'runtime_session_id': runtimeSessionId,
        if (runtimeTurnId != null) 'runtime_turn_id': runtimeTurnId,
        if (operationBatchId != null) 'operation_batch_id': operationBatchId,
        if (authorizationId != null) 'authorization_id': authorizationId,
        if (userAuthorizationMessageId != null)
          'user_authorization_message_id': userAuthorizationMessageId,
        if (beforeSnapshotHash != null)
          'before_snapshot_hash': beforeSnapshotHash,
        if (afterSnapshotHash != null) 'after_snapshot_hash': afterSnapshotHash,
        if (undoToken != null) 'undo_token': undoToken,
        if (errorCode != null) 'error_code': errorCode,
        'tools': tools,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('tools must be a string list');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

void _requireId(String value, String field) {
  if (value.isEmpty ||
      value.length > 256 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value)) {
    throw ArgumentError('$field must be a portable stable id');
  }
}

void _requireText(String value, String field, int maxRunes) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.runes.length > maxRunes) {
    throw ArgumentError('$field must be non-empty and bounded');
  }
}
