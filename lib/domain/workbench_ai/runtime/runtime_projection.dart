library;

const runtimeTurnProjectionSchemaVersion = 1;

enum RuntimeTurnStatus {
  queued('queued'),
  running('running'),
  waitingApproval('waiting_approval'),
  waitingInput('waiting_input'),
  completed('completed'),
  failed('failed'),
  interrupted('interrupted');

  const RuntimeTurnStatus(this.wireName);
  final String wireName;

  bool get isTerminal => switch (this) {
        RuntimeTurnStatus.completed ||
        RuntimeTurnStatus.failed ||
        RuntimeTurnStatus.interrupted =>
          true,
        _ => false,
      };

  static RuntimeTurnStatus parse(Object? value) => switch (value) {
        'queued' => RuntimeTurnStatus.queued,
        'running' => RuntimeTurnStatus.running,
        'waiting_approval' => RuntimeTurnStatus.waitingApproval,
        'waiting_input' => RuntimeTurnStatus.waitingInput,
        'completed' => RuntimeTurnStatus.completed,
        'failed' => RuntimeTurnStatus.failed,
        'interrupted' => RuntimeTurnStatus.interrupted,
        _ => throw FormatException('Unknown runtime turn status: $value'),
      };
}

enum RuntimeErrorCategory {
  authentication('authentication'),
  capability('capability'),
  rateLimit('rate_limit'),
  permission('permission'),
  providerUnavailable('provider_unavailable'),
  timeout('timeout'),
  invalidRequest('invalid_request'),
  internal('internal'),
  unknown('unknown');

  const RuntimeErrorCategory(this.wireName);
  final String wireName;

  static RuntimeErrorCategory parse(Object? value) => switch (value) {
        'authentication' => RuntimeErrorCategory.authentication,
        'capability' => RuntimeErrorCategory.capability,
        'rate_limit' => RuntimeErrorCategory.rateLimit,
        'permission' => RuntimeErrorCategory.permission,
        'provider_unavailable' => RuntimeErrorCategory.providerUnavailable,
        'timeout' => RuntimeErrorCategory.timeout,
        'invalid_request' => RuntimeErrorCategory.invalidRequest,
        'internal' => RuntimeErrorCategory.internal,
        'unknown' => RuntimeErrorCategory.unknown,
        _ => throw FormatException('Unknown runtime error category: $value'),
      };
}

class RuntimeErrorProjection {
  RuntimeErrorProjection._({
    required this.code,
    required this.category,
    required this.message,
    required this.retryable,
    this.evidenceRef,
  });

  factory RuntimeErrorProjection({
    required String code,
    required RuntimeErrorCategory category,
    required String message,
    required bool retryable,
    String? evidenceRef,
  }) {
    _requireProjectionId(code, 'code');
    _requireProjectionText(message, 'message', 1024);
    if (evidenceRef != null) {
      _requireProjectionId(evidenceRef, 'evidenceRef');
    }
    return RuntimeErrorProjection._(
      code: code,
      category: category,
      message: message,
      retryable: retryable,
      evidenceRef: evidenceRef,
    );
  }

  factory RuntimeErrorProjection.fromJson(Map<String, dynamic> json) {
    _expectProjectionKeys(
        json,
        const {
          'code',
          'category',
          'message',
          'retryable',
          'evidence_ref',
        },
        'RuntimeErrorProjection');
    final retryable = json['retryable'];
    if (retryable is! bool) {
      throw const FormatException('retryable must be a boolean');
    }
    return RuntimeErrorProjection(
      code: _projectionString(json['code'], 'code'),
      category: RuntimeErrorCategory.parse(json['category']),
      message: _projectionString(json['message'], 'message'),
      retryable: retryable,
      evidenceRef: json['evidence_ref'] as String?,
    );
  }

  /// Stable product error code, never a provider-private status or stack trace.
  final String code;
  final RuntimeErrorCategory category;
  final String message;
  final bool retryable;

  /// Reference to protected details held outside the product projection.
  final String? evidenceRef;

  Map<String, dynamic> toJson() => {
        'code': code,
        'category': category.wireName,
        'message': message,
        'retryable': retryable,
        if (evidenceRef != null) 'evidence_ref': evidenceRef,
      };
}

enum RuntimeApprovalStatus {
  pending('pending'),
  approved('approved'),
  denied('denied'),
  expired('expired'),
  cancelled('cancelled');

  const RuntimeApprovalStatus(this.wireName);
  final String wireName;

  bool get isTerminal => this != RuntimeApprovalStatus.pending;

  static RuntimeApprovalStatus parse(Object? value) => switch (value) {
        'pending' => RuntimeApprovalStatus.pending,
        'approved' => RuntimeApprovalStatus.approved,
        'denied' => RuntimeApprovalStatus.denied,
        'expired' => RuntimeApprovalStatus.expired,
        'cancelled' => RuntimeApprovalStatus.cancelled,
        _ => throw FormatException('Unknown runtime approval status: $value'),
      };
}

enum RuntimeApprovalRisk {
  low('low'),
  elevated('elevated'),
  high('high');

  const RuntimeApprovalRisk(this.wireName);
  final String wireName;

  static RuntimeApprovalRisk parse(Object? value) => switch (value) {
        'low' => RuntimeApprovalRisk.low,
        'elevated' => RuntimeApprovalRisk.elevated,
        'high' => RuntimeApprovalRisk.high,
        _ => throw FormatException('Unknown runtime approval risk: $value'),
      };
}

enum RuntimeApprovalDecisionSource {
  user('user'),
  turnAuthorization('turn_authorization'),
  policy('policy');

  const RuntimeApprovalDecisionSource(this.wireName);
  final String wireName;

  static RuntimeApprovalDecisionSource parse(Object? value) => switch (value) {
        'user' => RuntimeApprovalDecisionSource.user,
        'turn_authorization' => RuntimeApprovalDecisionSource.turnAuthorization,
        'policy' => RuntimeApprovalDecisionSource.policy,
        _ => throw FormatException('Unknown approval decision source: $value'),
      };
}

class RuntimeApprovalProjection {
  RuntimeApprovalProjection._({
    required this.approvalId,
    required this.risk,
    required this.title,
    required this.summary,
    required this.status,
    required this.requestedAt,
    this.resolvedAt,
    this.decisionSource,
    this.authorizationMessageId,
  });

  factory RuntimeApprovalProjection.pending({
    required String approvalId,
    required RuntimeApprovalRisk risk,
    required String title,
    required String summary,
    required DateTime requestedAt,
  }) {
    return RuntimeApprovalProjection._validated(
      approvalId: approvalId,
      risk: risk,
      title: title,
      summary: summary,
      status: RuntimeApprovalStatus.pending,
      requestedAt: requestedAt,
    );
  }

  factory RuntimeApprovalProjection._validated({
    required String approvalId,
    required RuntimeApprovalRisk risk,
    required String title,
    required String summary,
    required RuntimeApprovalStatus status,
    required DateTime requestedAt,
    DateTime? resolvedAt,
    RuntimeApprovalDecisionSource? decisionSource,
    String? authorizationMessageId,
  }) {
    _requireProjectionId(approvalId, 'approvalId');
    _requireProjectionText(title, 'title', 160);
    _requireProjectionText(summary, 'summary', 1024);
    if (authorizationMessageId != null) {
      _requireProjectionId(authorizationMessageId, 'authorizationMessageId');
    }
    final requested = requestedAt.toUtc();
    final resolved = resolvedAt?.toUtc();
    if (status == RuntimeApprovalStatus.pending) {
      if (resolved != null ||
          decisionSource != null ||
          authorizationMessageId != null) {
        throw ArgumentError('pending approval cannot contain a decision');
      }
    } else {
      if (resolved == null || decisionSource == null) {
        throw ArgumentError(
          'resolved approval requires time and decision source',
        );
      }
      if (resolved.isBefore(requested)) {
        throw ArgumentError('resolvedAt cannot be before requestedAt');
      }
      if (status == RuntimeApprovalStatus.approved &&
          risk == RuntimeApprovalRisk.high &&
          decisionSource != RuntimeApprovalDecisionSource.user) {
        throw ArgumentError(
          'high-risk approval requires an explicit user decision',
        );
      }
      if (status == RuntimeApprovalStatus.approved &&
          decisionSource == RuntimeApprovalDecisionSource.user &&
          authorizationMessageId == null) {
        throw ArgumentError(
          'user approval requires an authorization message reference',
        );
      }
    }
    return RuntimeApprovalProjection._(
      approvalId: approvalId,
      risk: risk,
      title: title,
      summary: summary,
      status: status,
      requestedAt: requested,
      resolvedAt: resolved,
      decisionSource: decisionSource,
      authorizationMessageId: authorizationMessageId,
    );
  }

  factory RuntimeApprovalProjection.fromJson(Map<String, dynamic> json) {
    _expectProjectionKeys(
        json,
        const {
          'approval_id',
          'risk',
          'title',
          'summary',
          'status',
          'requested_at',
          'resolved_at',
          'decision_source',
          'authorization_message_id',
        },
        'RuntimeApprovalProjection');
    return RuntimeApprovalProjection._validated(
      approvalId: _projectionString(json['approval_id'], 'approval_id'),
      risk: RuntimeApprovalRisk.parse(json['risk']),
      title: _projectionString(json['title'], 'title'),
      summary: _projectionString(json['summary'], 'summary'),
      status: RuntimeApprovalStatus.parse(json['status']),
      requestedAt: _projectionDate(json['requested_at'], 'requested_at'),
      resolvedAt: json['resolved_at'] == null
          ? null
          : _projectionDate(json['resolved_at'], 'resolved_at'),
      decisionSource: json['decision_source'] == null
          ? null
          : RuntimeApprovalDecisionSource.parse(json['decision_source']),
      authorizationMessageId: json['authorization_message_id'] as String?,
    );
  }

  final String approvalId;
  final RuntimeApprovalRisk risk;
  final String title;
  final String summary;
  final RuntimeApprovalStatus status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final RuntimeApprovalDecisionSource? decisionSource;

  /// Stable product chat message reference; raw authorization text is omitted.
  final String? authorizationMessageId;

  RuntimeApprovalProjection resolve({
    required RuntimeApprovalStatus decision,
    required RuntimeApprovalDecisionSource source,
    required DateTime at,
    String? authorizationMessageId,
  }) {
    if (status != RuntimeApprovalStatus.pending || !decision.isTerminal) {
      throw StateError(
        'Illegal approval transition: ${status.wireName} -> ${decision.wireName}',
      );
    }
    return RuntimeApprovalProjection._validated(
      approvalId: approvalId,
      risk: risk,
      title: title,
      summary: summary,
      status: decision,
      requestedAt: requestedAt,
      resolvedAt: at,
      decisionSource: source,
      authorizationMessageId: authorizationMessageId,
    );
  }

  Map<String, dynamic> toJson() => {
        'approval_id': approvalId,
        'risk': risk.wireName,
        'title': title,
        'summary': summary,
        'status': status.wireName,
        'requested_at': requestedAt.toIso8601String(),
        if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
        if (decisionSource != null) 'decision_source': decisionSource!.wireName,
        if (authorizationMessageId != null)
          'authorization_message_id': authorizationMessageId,
      };
}

class RuntimeTurnProjection {
  RuntimeTurnProjection._({
    required this.turnId,
    required this.runtimeSessionId,
    required this.userMessageId,
    required this.contextManifestRef,
    required this.contextManifestHash,
    required this.status,
    required this.displayMessage,
    required this.createdAt,
    required this.updatedAt,
    this.providerTurnId,
    this.resultSummary,
    this.error,
    this.approval,
    this.startedAt,
    this.completedAt,
  });

  factory RuntimeTurnProjection({
    required String turnId,
    required String runtimeSessionId,
    required String userMessageId,
    required String contextManifestRef,
    required String contextManifestHash,
    String? providerTurnId,
    RuntimeTurnStatus status = RuntimeTurnStatus.queued,
    required String displayMessage,
    String? resultSummary,
    RuntimeErrorProjection? error,
    RuntimeApprovalProjection? approval,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    _requireProjectionId(turnId, 'turnId');
    _requireProjectionId(runtimeSessionId, 'runtimeSessionId');
    _requireProjectionId(userMessageId, 'userMessageId');
    _requireProjectionId(contextManifestRef, 'contextManifestRef');
    _requireSha256(contextManifestHash, 'contextManifestHash');
    if (providerTurnId != null) _requireOpaqueTurnId(providerTurnId);
    _requireProjectionText(displayMessage, 'displayMessage', 1024);
    if (resultSummary != null) {
      _requireProjectionText(resultSummary, 'resultSummary', 4096);
      if (!status.isTerminal) {
        throw ArgumentError('resultSummary is only valid for terminal turns');
      }
    }
    final created = createdAt.toUtc();
    final updated = updatedAt.toUtc();
    final started = startedAt?.toUtc();
    final completed = completedAt?.toUtc();
    if (updated.isBefore(created)) {
      throw ArgumentError('updatedAt cannot be before createdAt');
    }
    if (status == RuntimeTurnStatus.queued) {
      if (started != null) {
        throw ArgumentError('queued turn cannot have startedAt');
      }
    } else if (started == null) {
      throw ArgumentError('non-queued turn requires startedAt');
    }
    if (started != null && started.isBefore(created)) {
      throw ArgumentError('startedAt cannot be before createdAt');
    }
    if (started != null && updated.isBefore(started)) {
      throw ArgumentError('updatedAt cannot be before startedAt');
    }
    if (status.isTerminal) {
      if (completed == null) {
        throw ArgumentError('terminal turn requires completedAt');
      }
      if (started != null && completed.isBefore(started)) {
        throw ArgumentError('completedAt cannot be before startedAt');
      }
      if (updated.isBefore(completed)) {
        throw ArgumentError('updatedAt cannot be before completedAt');
      }
    } else if (completed != null) {
      throw ArgumentError('non-terminal turn cannot have completedAt');
    }
    if (status == RuntimeTurnStatus.failed) {
      if (error == null) throw ArgumentError('failed turn requires an error');
    } else if (error != null) {
      throw ArgumentError('only failed turn may contain an error');
    }
    if (status == RuntimeTurnStatus.waitingApproval) {
      if (approval == null ||
          approval.status != RuntimeApprovalStatus.pending) {
        throw ArgumentError('waiting_approval requires a pending approval');
      }
    } else if (approval?.status == RuntimeApprovalStatus.pending) {
      throw ArgumentError('pending approval requires waiting_approval status');
    }
    return RuntimeTurnProjection._(
      turnId: turnId,
      runtimeSessionId: runtimeSessionId,
      userMessageId: userMessageId,
      contextManifestRef: contextManifestRef,
      contextManifestHash: contextManifestHash,
      providerTurnId: providerTurnId,
      status: status,
      displayMessage: displayMessage,
      resultSummary: resultSummary,
      error: error,
      approval: approval,
      createdAt: created,
      updatedAt: updated,
      startedAt: started,
      completedAt: completed,
    );
  }

  factory RuntimeTurnProjection.fromJson(Map<String, dynamic> json) {
    _expectProjectionKeys(
        json,
        const {
          'schema_version',
          'turn_id',
          'runtime_session_id',
          'user_message_id',
          'context_manifest_ref',
          'context_manifest_hash',
          'provider_turn_id',
          'status',
          'display_message',
          'result_summary',
          'error',
          'approval',
          'created_at',
          'updated_at',
          'started_at',
          'completed_at',
        },
        'RuntimeTurnProjection');
    final version = json['schema_version'];
    if (version is! int || version != runtimeTurnProjectionSchemaVersion) {
      throw FormatException(
        'Unsupported RuntimeTurnProjection schema version: $version',
      );
    }
    return RuntimeTurnProjection(
      turnId: _projectionString(json['turn_id'], 'turn_id'),
      runtimeSessionId: _projectionString(
        json['runtime_session_id'],
        'runtime_session_id',
      ),
      userMessageId: _projectionString(
        json['user_message_id'],
        'user_message_id',
      ),
      contextManifestRef: _projectionString(
        json['context_manifest_ref'],
        'context_manifest_ref',
      ),
      contextManifestHash: _projectionString(
        json['context_manifest_hash'],
        'context_manifest_hash',
      ),
      providerTurnId: json['provider_turn_id'] as String?,
      status: RuntimeTurnStatus.parse(json['status']),
      displayMessage: _projectionString(
        json['display_message'],
        'display_message',
      ),
      resultSummary: json['result_summary'] == null
          ? null
          : _projectionString(json['result_summary'], 'result_summary'),
      error: json['error'] == null
          ? null
          : RuntimeErrorProjection.fromJson(
              _projectionMap(json['error'], 'error'),
            ),
      approval: json['approval'] == null
          ? null
          : RuntimeApprovalProjection.fromJson(
              _projectionMap(json['approval'], 'approval'),
            ),
      createdAt: _projectionDate(json['created_at'], 'created_at'),
      updatedAt: _projectionDate(json['updated_at'], 'updated_at'),
      startedAt: json['started_at'] == null
          ? null
          : _projectionDate(json['started_at'], 'started_at'),
      completedAt: json['completed_at'] == null
          ? null
          : _projectionDate(json['completed_at'], 'completed_at'),
    );
  }

  final String turnId;
  final String runtimeSessionId;

  /// Product chat message that initiated the turn.
  final String userMessageId;

  /// Stable receipt reference and SHA-256 of the context manifest. The full
  /// assembled prompt is deliberately not copied into this projection.
  final String contextManifestRef;
  final String contextManifestHash;

  /// Opaque provider identifier. Product state never infers meaning from it.
  final String? providerTurnId;
  final RuntimeTurnStatus status;

  /// Short live status copy; it is not the final result.
  final String displayMessage;

  /// Optional terminal result summary, separate from progress copy.
  final String? resultSummary;
  final RuntimeErrorProjection? error;
  final RuntimeApprovalProjection? approval;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool canTransitionTo(RuntimeTurnStatus next) => switch (status) {
        RuntimeTurnStatus.queued => next == RuntimeTurnStatus.running ||
            next == RuntimeTurnStatus.failed ||
            next == RuntimeTurnStatus.interrupted,
        RuntimeTurnStatus.running =>
          next == RuntimeTurnStatus.waitingApproval ||
              next == RuntimeTurnStatus.waitingInput ||
              next == RuntimeTurnStatus.completed ||
              next == RuntimeTurnStatus.failed ||
              next == RuntimeTurnStatus.interrupted,
        RuntimeTurnStatus.waitingApproval ||
        RuntimeTurnStatus.waitingInput =>
          next == RuntimeTurnStatus.running ||
              next == RuntimeTurnStatus.failed ||
              next == RuntimeTurnStatus.interrupted,
        RuntimeTurnStatus.completed ||
        RuntimeTurnStatus.failed ||
        RuntimeTurnStatus.interrupted =>
          false,
      };

  RuntimeTurnProjection transitionTo(
    RuntimeTurnStatus next, {
    required DateTime at,
    required String displayMessage,
    String? providerTurnId,
    String? resultSummary,
    RuntimeErrorProjection? error,
    RuntimeApprovalProjection? approval,
  }) {
    if (!canTransitionTo(next)) {
      throw StateError(
        'Illegal runtime turn transition: '
        '${status.wireName} -> ${next.wireName}',
      );
    }
    if (status == RuntimeTurnStatus.waitingApproval &&
        (approval == null ||
            !approval.status.isTerminal ||
            approval.approvalId != this.approval!.approvalId)) {
      throw StateError(
        'The pending approval must be resolved before leaving it',
      );
    }
    final transitionAt = at.toUtc();
    if (transitionAt.isBefore(updatedAt)) {
      throw ArgumentError('transition time cannot be before updatedAt');
    }
    final effectiveStartedAt = startedAt ?? transitionAt;
    return RuntimeTurnProjection(
      turnId: turnId,
      runtimeSessionId: runtimeSessionId,
      userMessageId: userMessageId,
      contextManifestRef: contextManifestRef,
      contextManifestHash: contextManifestHash,
      providerTurnId: providerTurnId ?? this.providerTurnId,
      status: next,
      displayMessage: displayMessage,
      resultSummary: resultSummary,
      error: error,
      approval: approval,
      createdAt: createdAt,
      updatedAt: transitionAt,
      startedAt: effectiveStartedAt,
      completedAt: next.isTerminal ? transitionAt : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': runtimeTurnProjectionSchemaVersion,
        'turn_id': turnId,
        'runtime_session_id': runtimeSessionId,
        'user_message_id': userMessageId,
        'context_manifest_ref': contextManifestRef,
        'context_manifest_hash': contextManifestHash,
        if (providerTurnId != null) 'provider_turn_id': providerTurnId,
        'status': status.wireName,
        'display_message': displayMessage,
        if (resultSummary != null) 'result_summary': resultSummary,
        if (error != null) 'error': error!.toJson(),
        if (approval != null) 'approval': approval!.toJson(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      };
}

void _requireProjectionId(String value, String field) {
  if (value.trim().isEmpty || value.length > 256) {
    throw ArgumentError('$field must be non-blank and at most 256 characters');
  }
}

void _requireSha256(String value, String field) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw ArgumentError('$field must be a lowercase SHA-256 hex digest');
  }
}

void _requireOpaqueTurnId(String value) {
  if (value.trim().isEmpty || value.length > 2048) {
    throw ArgumentError(
      'providerTurnId must be non-blank and at most 2048 characters',
    );
  }
}

void _requireProjectionText(String value, String field, int maxCharacters) {
  if (value.trim().isEmpty || value.length > maxCharacters) {
    throw ArgumentError(
      '$field must be non-blank and at most $maxCharacters characters',
    );
  }
}

String _projectionString(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

DateTime _projectionDate(Object? value, String field) {
  final raw = _projectionString(value, field);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('$field must be an ISO-8601 date');
  return parsed;
}

Map<String, dynamic> _projectionMap(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

void _expectProjectionKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  String type,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('$type contains unsupported fields: $unknown');
  }
}
