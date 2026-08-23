library;

import 'dart:convert';

const runtimeSessionBindingSchemaVersion = 1;
const runtimeContractMaxEncodedBytes = 65536;

enum RuntimeProfile {
  companion('companion'),
  workbench('workbench'),
  coding('coding');

  const RuntimeProfile(this.wireName);
  final String wireName;

  static RuntimeProfile parse(Object? value) => switch (value) {
        'companion' => RuntimeProfile.companion,
        'workbench' => RuntimeProfile.workbench,
        'coding' => RuntimeProfile.coding,
        _ => throw FormatException('Unknown runtime profile: $value'),
      };
}

enum RuntimeScopeType {
  surface('surface'),
  board('board'),
  project('project');

  const RuntimeScopeType(this.wireName);
  final String wireName;

  static RuntimeScopeType parse(Object? value) => switch (value) {
        'surface' => RuntimeScopeType.surface,
        'board' => RuntimeScopeType.board,
        'project' => RuntimeScopeType.project,
        _ => throw FormatException('Unknown runtime scope type: $value'),
      };
}

enum RuntimeSessionStatus {
  active('active'),
  idle('idle'),
  interrupted('interrupted'),
  closed('closed'),
  unavailable('unavailable');

  const RuntimeSessionStatus(this.wireName);
  final String wireName;

  static RuntimeSessionStatus parse(Object? value) => switch (value) {
        'active' => RuntimeSessionStatus.active,
        'idle' => RuntimeSessionStatus.idle,
        'interrupted' => RuntimeSessionStatus.interrupted,
        'closed' => RuntimeSessionStatus.closed,
        'unavailable' => RuntimeSessionStatus.unavailable,
        _ => throw FormatException('Unknown runtime session status: $value'),
      };
}

class ProviderMetadata {
  ProviderMetadata._(this.values);

  factory ProviderMetadata([Map<String, Object?> values = const {}]) {
    _validateProviderMetadata(values);
    return ProviderMetadata._(_freezeJsonMap(values));
  }

  factory ProviderMetadata.fromJson(Map<String, dynamic> json) {
    return ProviderMetadata(json.cast<String, Object?>());
  }

  final Map<String, Object?> values;

  Map<String, Object?> toJson() => values;
}

class RuntimeSessionBinding {
  RuntimeSessionBinding._({
    required this.id,
    required this.conversationId,
    required this.provider,
    required this.providerSessionId,
    required this.profile,
    required this.scopeType,
    required this.scopeId,
    required this.status,
    required this.providerMetadata,
    required this.createdAt,
    required this.lastActiveAt,
    this.closedAt,
  });

  factory RuntimeSessionBinding({
    required String id,
    required String conversationId,
    required String provider,
    required String providerSessionId,
    required RuntimeProfile profile,
    required RuntimeScopeType scopeType,
    required String scopeId,
    RuntimeSessionStatus status = RuntimeSessionStatus.active,
    ProviderMetadata? providerMetadata,
    required DateTime createdAt,
    required DateTime lastActiveAt,
    DateTime? closedAt,
  }) {
    _requireStableValue(id, 'id');
    _requireStableValue(conversationId, 'conversationId');
    _requireProviderKey(provider);
    _requireOpaqueProviderId(providerSessionId);
    _requireStableValue(scopeId, 'scopeId');
    final created = createdAt.toUtc();
    final lastActive = lastActiveAt.toUtc();
    final closed = closedAt?.toUtc();
    if (lastActive.isBefore(created)) {
      throw ArgumentError('lastActiveAt cannot be before createdAt');
    }
    if (status == RuntimeSessionStatus.closed) {
      if (closed == null) {
        throw ArgumentError('closed sessions require closedAt');
      }
      if (closed.isBefore(lastActive)) {
        throw ArgumentError('closedAt cannot be before lastActiveAt');
      }
    } else if (closed != null) {
      throw ArgumentError('only closed sessions may have closedAt');
    }
    return RuntimeSessionBinding._(
      id: id,
      conversationId: conversationId,
      provider: provider,
      providerSessionId: providerSessionId,
      profile: profile,
      scopeType: scopeType,
      scopeId: scopeId,
      status: status,
      providerMetadata: providerMetadata ?? ProviderMetadata(),
      createdAt: created,
      lastActiveAt: lastActive,
      closedAt: closed,
    );
  }

  factory RuntimeSessionBinding.fromJson(Map<String, dynamic> json) {
    _expectRuntimeKeys(
        json,
        const {
          'schema_version',
          'id',
          'conversation_id',
          'provider',
          'provider_session_id',
          'profile',
          'scope_type',
          'scope_id',
          'status',
          'provider_metadata',
          'created_at',
          'last_active_at',
          'closed_at',
        },
        'RuntimeSessionBinding');
    _requireRuntimeVersion(json, runtimeSessionBindingSchemaVersion);
    return RuntimeSessionBinding(
      id: _runtimeString(json['id'], 'id'),
      conversationId: _runtimeString(
        json['conversation_id'],
        'conversation_id',
      ),
      provider: _runtimeString(json['provider'], 'provider'),
      providerSessionId: _runtimeString(
        json['provider_session_id'],
        'provider_session_id',
      ),
      profile: RuntimeProfile.parse(json['profile']),
      scopeType: RuntimeScopeType.parse(json['scope_type']),
      scopeId: _runtimeString(json['scope_id'], 'scope_id'),
      status: RuntimeSessionStatus.parse(json['status']),
      providerMetadata: ProviderMetadata.fromJson(
        _runtimeMap(json['provider_metadata'], 'provider_metadata'),
      ),
      createdAt: _runtimeDate(json['created_at'], 'created_at'),
      lastActiveAt: _runtimeDate(json['last_active_at'], 'last_active_at'),
      closedAt: json['closed_at'] == null
          ? null
          : _runtimeDate(json['closed_at'], 'closed_at'),
    );
  }

  final String id;

  /// Product conversation continuity. It is never derived from provider state.
  final String conversationId;
  final String provider;

  /// Opaque runtime-owned identifier. No product code may parse its format.
  final String providerSessionId;
  final RuntimeProfile profile;
  final RuntimeScopeType scopeType;
  final String scopeId;
  final RuntimeSessionStatus status;
  final ProviderMetadata providerMetadata;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final DateTime? closedAt;

  bool canTransitionTo(RuntimeSessionStatus next) {
    if (next == status) return true;
    return switch (status) {
      RuntimeSessionStatus.active => next != RuntimeSessionStatus.active,
      RuntimeSessionStatus.idle => next == RuntimeSessionStatus.active ||
          next == RuntimeSessionStatus.interrupted ||
          next == RuntimeSessionStatus.closed ||
          next == RuntimeSessionStatus.unavailable,
      RuntimeSessionStatus.interrupted => next == RuntimeSessionStatus.active ||
          next == RuntimeSessionStatus.closed ||
          next == RuntimeSessionStatus.unavailable,
      RuntimeSessionStatus.unavailable => next == RuntimeSessionStatus.active ||
          next == RuntimeSessionStatus.idle ||
          next == RuntimeSessionStatus.closed,
      RuntimeSessionStatus.closed => false,
    };
  }

  RuntimeSessionBinding transitionTo(
    RuntimeSessionStatus next, {
    required DateTime at,
  }) {
    if (!canTransitionTo(next)) {
      throw StateError(
        'Illegal runtime session transition: '
        '${status.wireName} -> ${next.wireName}',
      );
    }
    final transitionAt = at.toUtc();
    if (transitionAt.isBefore(lastActiveAt)) {
      throw ArgumentError('transition time cannot be before lastActiveAt');
    }
    if (next == status) return this;
    return RuntimeSessionBinding(
      id: id,
      conversationId: conversationId,
      provider: provider,
      providerSessionId: providerSessionId,
      profile: profile,
      scopeType: scopeType,
      scopeId: scopeId,
      status: next,
      providerMetadata: providerMetadata,
      createdAt: createdAt,
      lastActiveAt: transitionAt,
      closedAt: next == RuntimeSessionStatus.closed ? transitionAt : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': runtimeSessionBindingSchemaVersion,
        'id': id,
        'conversation_id': conversationId,
        'provider': provider,
        'provider_session_id': providerSessionId,
        'profile': profile.wireName,
        'scope_type': scopeType.wireName,
        'scope_id': scopeId,
        'status': status.wireName,
        'provider_metadata': providerMetadata.toJson(),
        'created_at': createdAt.toIso8601String(),
        'last_active_at': lastActiveAt.toIso8601String(),
        if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
      };
}

void _requireProviderKey(String value) {
  if (!RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(value)) {
    throw ArgumentError('provider must be a portable lowercase provider key');
  }
}

void _requireOpaqueProviderId(String value) {
  if (value.trim().isEmpty || value.length > 2048) {
    throw ArgumentError(
      'providerSessionId must be non-blank and at most 2048 characters',
    );
  }
}

void _requireStableValue(String value, String field) {
  if (value.trim().isEmpty || value.length > 256) {
    throw ArgumentError('$field must be non-blank and at most 256 characters');
  }
}

const _sensitiveProviderMetadataTokens = <String>{
  'password',
  'passphrase',
  'secret',
  'authorization',
  'cookie',
  'credential',
  'credentials',
  'email',
  'prompt',
};

const _sensitiveTokenQualifiers = <String>{
  'access',
  'refresh',
  'auth',
  'bearer',
  'identity',
  'id',
  'session',
  'csrf',
};

void _validateProviderMetadata(Map<String, Object?> values) {
  void visit(Object? value, int depth) {
    if (depth > 4) {
      throw ArgumentError('provider metadata is nested too deeply');
    }
    if (value == null || value is bool || value is num) return;
    if (value is String) {
      if (value.length > 1024) {
        throw ArgumentError('provider metadata string exceeds 1024 characters');
      }
      return;
    }
    if (value is List<Object?>) {
      if (value.length > 64) {
        throw ArgumentError('provider metadata list exceeds 64 items');
      }
      for (final item in value) {
        visit(item, depth + 1);
      }
      return;
    }
    if (value is Map<String, Object?>) {
      for (final entry in value.entries) {
        if (_isSensitiveProviderMetadataKey(entry.key)) {
          throw ArgumentError(
            'provider metadata must not contain private field ${entry.key}',
          );
        }
        visit(entry.value, depth + 1);
      }
      return;
    }
    throw ArgumentError('provider metadata must contain only JSON values');
  }

  visit(values, 0);
  if (utf8.encode(jsonEncode(values)).length > 8192) {
    throw ArgumentError('provider metadata exceeds 8192 bytes');
  }
}

bool _isSensitiveProviderMetadataKey(String key) {
  final withAcronymBoundaries = key.replaceAllMapped(
    RegExp(r'([A-Z]+)([A-Z][a-z])'),
    (match) => '${match[1]} ${match[2]}',
  );
  final withCamelBoundaries = withAcronymBoundaries.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );
  final normalized = withCamelBoundaries
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  final tokens = normalized.isEmpty ? const <String>[] : normalized.split(' ');
  final tokenSet = tokens.toSet();
  if (tokenSet.intersection(_sensitiveProviderMetadataTokens).isNotEmpty) {
    return true;
  }

  bool hasAdjacent(String first, String second) {
    for (var index = 0; index < tokens.length - 1; index++) {
      if (tokens[index] == first && tokens[index + 1] == second) return true;
    }
    return false;
  }

  if (hasAdjacent('api', 'key') ||
      hasAdjacent('raw', 'log') ||
      hasAdjacent('stack', 'trace') ||
      hasAdjacent('full', 'diff') ||
      hasAdjacent('message', 'content')) {
    return true;
  }
  if (tokenSet.contains('token') &&
      tokenSet.intersection(_sensitiveTokenQualifiers).isNotEmpty) {
    return true;
  }

  final compact = tokens.join();
  return compact.contains('accesstoken') ||
      compact.contains('refreshtoken') ||
      compact.contains('authtoken') ||
      compact.contains('bearertoken') ||
      compact.contains('apikey') ||
      compact.contains('authorizationheader') ||
      compact.contains('useremail');
}

Map<String, Object?> _freezeJsonMap(Map<String, Object?> source) {
  Object? freeze(Object? value) {
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.unmodifiable(
        value.map((key, item) => MapEntry(key, freeze(item))),
      );
    }
    if (value is List<Object?>) {
      return List<Object?>.unmodifiable(value.map(freeze));
    }
    return value;
  }

  return freeze(source)! as Map<String, Object?>;
}

void _requireRuntimeVersion(Map<String, dynamic> json, int supported) {
  final version = json['schema_version'];
  if (version is! int || version != supported) {
    throw FormatException(
      'Unsupported runtime contract schema version: $version',
    );
  }
}

String _runtimeString(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

DateTime _runtimeDate(Object? value, String field) {
  final raw = _runtimeString(value, field);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('$field must be an ISO-8601 date');
  return parsed;
}

Map<String, dynamic> _runtimeMap(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

void _expectRuntimeKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  String type,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('$type contains unsupported fields: $unknown');
  }
}
