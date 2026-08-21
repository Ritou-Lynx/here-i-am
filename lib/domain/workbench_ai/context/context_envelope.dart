library;

import '../runtime/runtime_session_binding.dart';

const contextEnvelopeSchemaVersion = 1;

/// Hard product limits. A caller may request a smaller [ContextBudget], but
/// never expand a turn beyond these values.
abstract final class ContextEnvelopeLimits {
  static const maxRecentMessages = 20;
  static const maxObjectReferences = 64;
  static const maxRecallSnippets = 12;
  static const maxTurnInstructionCharacters = 4096;
  static const maxRecentChatCharacters = 32000;
  static const maxSurfaceCharacters = 16000;
  static const maxRecallCharacters = 16000;
  static const maxContentItemCharacters = 4096;
  static const maxEnvelopeBytes = 65536;
  static const maxIdentifierCharacters = 256;
}

enum ContextTrust {
  userInstruction('user_instruction'),
  userAuthoredContent('user_authored_content'),
  untrustedContent('untrusted_content');

  const ContextTrust(this.wireName);
  final String wireName;

  static ContextTrust parse(Object? value) => switch (value) {
        'user_instruction' => ContextTrust.userInstruction,
        'user_authored_content' => ContextTrust.userAuthoredContent,
        'untrusted_content' => ContextTrust.untrustedContent,
        _ => throw FormatException('Unknown context trust value: $value'),
      };
}

enum ContextMessageRole {
  user('user'),
  assistant('assistant');

  const ContextMessageRole(this.wireName);
  final String wireName;

  static ContextMessageRole parse(Object? value) => switch (value) {
        'user' => ContextMessageRole.user,
        'assistant' => ContextMessageRole.assistant,
        _ => throw FormatException('Unknown context message role: $value'),
      };
}

class ContextText {
  ContextText._({required this.text, required this.trust});

  factory ContextText({required String text, required ContextTrust trust}) {
    _requireText(text, 'text', ContextEnvelopeLimits.maxContentItemCharacters);
    return ContextText._(text: text, trust: trust);
  }

  factory ContextText.fromJson(Map<String, dynamic> json) {
    _expectKeys(json, const {'text', 'trust'}, 'ContextText');
    return ContextText(
      text: _requireString(json['text'], 'text'),
      trust: ContextTrust.parse(json['trust']),
    );
  }

  final String text;
  final ContextTrust trust;

  Map<String, dynamic> toJson() => {'text': text, 'trust': trust.wireName};
}

class ContextChatMessage {
  ContextChatMessage._({
    required this.messageId,
    required this.role,
    required this.content,
    required this.occurredAt,
  });

  factory ContextChatMessage({
    required String messageId,
    required ContextMessageRole role,
    required ContextText content,
    required DateTime occurredAt,
  }) {
    _requireIdentifier(messageId, 'messageId');
    final expectedTrust = role == ContextMessageRole.user
        ? ContextTrust.userAuthoredContent
        : ContextTrust.untrustedContent;
    if (content.trust != expectedTrust) {
      throw ArgumentError(
        '${role.wireName} chat content must be marked '
        '${expectedTrust.wireName}',
      );
    }
    return ContextChatMessage._(
      messageId: messageId,
      role: role,
      content: content,
      occurredAt: occurredAt.toUtc(),
    );
  }

  factory ContextChatMessage.fromJson(Map<String, dynamic> json) {
    _expectKeys(
        json,
        const {
          'message_id',
          'role',
          'content',
          'occurred_at',
        },
        'ContextChatMessage');
    return ContextChatMessage(
      messageId: _requireString(json['message_id'], 'message_id'),
      role: ContextMessageRole.parse(json['role']),
      content: ContextText.fromJson(_requireMap(json['content'], 'content')),
      occurredAt: _requireDateTime(json['occurred_at'], 'occurred_at'),
    );
  }

  final String messageId;
  final ContextMessageRole role;
  final ContextText content;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'role': role.wireName,
        'content': content.toJson(),
        'occurred_at': occurredAt.toIso8601String(),
      };
}

class ContextObjectReference {
  ContextObjectReference._({
    required this.objectType,
    required this.objectId,
    required this.selected,
    this.summary,
  });

  factory ContextObjectReference({
    required String objectType,
    required String objectId,
    bool selected = false,
    ContextText? summary,
  }) {
    _requireIdentifier(objectType, 'objectType');
    _requireIdentifier(objectId, 'objectId');
    if (summary != null && summary.trust != ContextTrust.untrustedContent) {
      throw ArgumentError('Object summaries must be marked untrusted_content');
    }
    return ContextObjectReference._(
      objectType: objectType,
      objectId: objectId,
      selected: selected,
      summary: summary,
    );
  }

  factory ContextObjectReference.fromJson(Map<String, dynamic> json) {
    _expectKeys(
        json,
        const {
          'object_type',
          'object_id',
          'selected',
          'summary',
        },
        'ContextObjectReference');
    return ContextObjectReference(
      objectType: _requireString(json['object_type'], 'object_type'),
      objectId: _requireString(json['object_id'], 'object_id'),
      selected: json['selected'] as bool? ?? false,
      summary: json['summary'] == null
          ? null
          : ContextText.fromJson(_requireMap(json['summary'], 'summary')),
    );
  }

  final String objectType;
  final String objectId;
  final bool selected;
  final ContextText? summary;

  Map<String, dynamic> toJson() => {
        'object_type': objectType,
        'object_id': objectId,
        'selected': selected,
        if (summary != null) 'summary': summary!.toJson(),
      };
}

class ContextSurface {
  ContextSurface._({
    required this.surfaceType,
    required this.surfaceId,
    required this.objectReferences,
    this.workspaceRef,
  });

  factory ContextSurface({
    required String surfaceType,
    required String surfaceId,
    List<ContextObjectReference> objectReferences = const [],
    String? workspaceRef,
  }) {
    _requireIdentifier(surfaceType, 'surfaceType');
    _requireIdentifier(surfaceId, 'surfaceId');
    if (workspaceRef != null) {
      _requireWorkspaceRef(workspaceRef);
    }
    if (objectReferences.length > ContextEnvelopeLimits.maxObjectReferences) {
      throw ArgumentError(
        'objectReferences exceeds hard limit '
        '${ContextEnvelopeLimits.maxObjectReferences}',
      );
    }
    return ContextSurface._(
      surfaceType: surfaceType,
      surfaceId: surfaceId,
      objectReferences: List.unmodifiable(objectReferences),
      workspaceRef: workspaceRef,
    );
  }

  factory ContextSurface.fromJson(Map<String, dynamic> json) {
    _expectKeys(
        json,
        const {
          'surface_type',
          'surface_id',
          'object_references',
          'workspace_ref',
        },
        'ContextSurface');
    return ContextSurface(
      surfaceType: _requireString(json['surface_type'], 'surface_type'),
      surfaceId: _requireString(json['surface_id'], 'surface_id'),
      objectReferences:
          _requireList(json['object_references'], 'object_references')
              .map((value) {
        return ContextObjectReference.fromJson(
          _requireMap(value, 'object_references[]'),
        );
      }).toList(growable: false),
      workspaceRef: json['workspace_ref'] as String?,
    );
  }

  final String surfaceType;
  final String surfaceId;
  final List<ContextObjectReference> objectReferences;

  /// Stable product-owned reference, never an absolute filesystem path.
  final String? workspaceRef;

  Map<String, dynamic> toJson() => {
        'surface_type': surfaceType,
        'surface_id': surfaceId,
        'object_references':
            objectReferences.map((reference) => reference.toJson()).toList(),
        if (workspaceRef != null) 'workspace_ref': workspaceRef,
      };
}

class ContextRecallSnippet {
  ContextRecallSnippet._({
    required this.recallId,
    required this.sourceType,
    required this.sourceId,
    required this.content,
    required this.retrievedAt,
  });

  factory ContextRecallSnippet({
    required String recallId,
    required String sourceType,
    required String sourceId,
    required ContextText content,
    required DateTime retrievedAt,
  }) {
    _requireIdentifier(recallId, 'recallId');
    _requireIdentifier(sourceType, 'sourceType');
    _requireIdentifier(sourceId, 'sourceId');
    if (content.trust != ContextTrust.untrustedContent) {
      throw ArgumentError('Recall content must be marked untrusted_content');
    }
    return ContextRecallSnippet._(
      recallId: recallId,
      sourceType: sourceType,
      sourceId: sourceId,
      content: content,
      retrievedAt: retrievedAt.toUtc(),
    );
  }

  factory ContextRecallSnippet.fromJson(Map<String, dynamic> json) {
    _expectKeys(
        json,
        const {
          'recall_id',
          'source_type',
          'source_id',
          'content',
          'retrieved_at',
        },
        'ContextRecallSnippet');
    return ContextRecallSnippet(
      recallId: _requireString(json['recall_id'], 'recall_id'),
      sourceType: _requireString(json['source_type'], 'source_type'),
      sourceId: _requireString(json['source_id'], 'source_id'),
      content: ContextText.fromJson(_requireMap(json['content'], 'content')),
      retrievedAt: _requireDateTime(json['retrieved_at'], 'retrieved_at'),
    );
  }

  final String recallId;
  final String sourceType;
  final String sourceId;
  final ContextText content;
  final DateTime retrievedAt;

  Map<String, dynamic> toJson() => {
        'recall_id': recallId,
        'source_type': sourceType,
        'source_id': sourceId,
        'content': content.toJson(),
        'retrieved_at': retrievedAt.toIso8601String(),
      };
}

class ContextBudget {
  ContextBudget._({
    required this.maxRecentMessages,
    required this.maxObjectReferences,
    required this.maxRecallSnippets,
    required this.maxTurnInstructionCharacters,
    required this.maxRecentChatCharacters,
    required this.maxSurfaceCharacters,
    required this.maxRecallCharacters,
    required this.maxEnvelopeBytes,
  });

  factory ContextBudget({
    int maxRecentMessages = ContextEnvelopeLimits.maxRecentMessages,
    int maxObjectReferences = ContextEnvelopeLimits.maxObjectReferences,
    int maxRecallSnippets = ContextEnvelopeLimits.maxRecallSnippets,
    int maxTurnInstructionCharacters = 4096,
    int maxRecentChatCharacters = 16000,
    int maxSurfaceCharacters = 8000,
    int maxRecallCharacters = 8000,
    int maxEnvelopeBytes = ContextEnvelopeLimits.maxEnvelopeBytes,
  }) {
    _requireBudget(
      maxRecentMessages,
      ContextEnvelopeLimits.maxRecentMessages,
      'maxRecentMessages',
    );
    _requireBudget(
      maxObjectReferences,
      ContextEnvelopeLimits.maxObjectReferences,
      'maxObjectReferences',
    );
    _requireBudget(
      maxRecallSnippets,
      ContextEnvelopeLimits.maxRecallSnippets,
      'maxRecallSnippets',
    );
    _requireBudget(
      maxTurnInstructionCharacters,
      ContextEnvelopeLimits.maxTurnInstructionCharacters,
      'maxTurnInstructionCharacters',
    );
    _requireBudget(
      maxRecentChatCharacters,
      ContextEnvelopeLimits.maxRecentChatCharacters,
      'maxRecentChatCharacters',
    );
    _requireBudget(
      maxSurfaceCharacters,
      ContextEnvelopeLimits.maxSurfaceCharacters,
      'maxSurfaceCharacters',
    );
    _requireBudget(
      maxRecallCharacters,
      ContextEnvelopeLimits.maxRecallCharacters,
      'maxRecallCharacters',
    );
    _requireBudget(
      maxEnvelopeBytes,
      ContextEnvelopeLimits.maxEnvelopeBytes,
      'maxEnvelopeBytes',
    );
    return ContextBudget._(
      maxRecentMessages: maxRecentMessages,
      maxObjectReferences: maxObjectReferences,
      maxRecallSnippets: maxRecallSnippets,
      maxTurnInstructionCharacters: maxTurnInstructionCharacters,
      maxRecentChatCharacters: maxRecentChatCharacters,
      maxSurfaceCharacters: maxSurfaceCharacters,
      maxRecallCharacters: maxRecallCharacters,
      maxEnvelopeBytes: maxEnvelopeBytes,
    );
  }

  factory ContextBudget.fromJson(Map<String, dynamic> json) {
    _expectKeys(
        json,
        const {
          'max_recent_messages',
          'max_object_references',
          'max_recall_snippets',
          'max_turn_instruction_characters',
          'max_recent_chat_characters',
          'max_surface_characters',
          'max_recall_characters',
          'max_envelope_bytes',
        },
        'ContextBudget');
    return ContextBudget(
      maxRecentMessages: _requireInt(
        json['max_recent_messages'],
        'max_recent_messages',
      ),
      maxObjectReferences: _requireInt(
        json['max_object_references'],
        'max_object_references',
      ),
      maxRecallSnippets: _requireInt(
        json['max_recall_snippets'],
        'max_recall_snippets',
      ),
      maxTurnInstructionCharacters: _requireInt(
        json['max_turn_instruction_characters'],
        'max_turn_instruction_characters',
      ),
      maxRecentChatCharacters: _requireInt(
        json['max_recent_chat_characters'],
        'max_recent_chat_characters',
      ),
      maxSurfaceCharacters: _requireInt(
        json['max_surface_characters'],
        'max_surface_characters',
      ),
      maxRecallCharacters: _requireInt(
        json['max_recall_characters'],
        'max_recall_characters',
      ),
      maxEnvelopeBytes: _requireInt(
        json['max_envelope_bytes'],
        'max_envelope_bytes',
      ),
    );
  }

  final int maxRecentMessages;
  final int maxObjectReferences;
  final int maxRecallSnippets;
  final int maxTurnInstructionCharacters;
  final int maxRecentChatCharacters;
  final int maxSurfaceCharacters;
  final int maxRecallCharacters;
  final int maxEnvelopeBytes;

  Map<String, dynamic> toJson() => {
        'max_recent_messages': maxRecentMessages,
        'max_object_references': maxObjectReferences,
        'max_recall_snippets': maxRecallSnippets,
        'max_turn_instruction_characters': maxTurnInstructionCharacters,
        'max_recent_chat_characters': maxRecentChatCharacters,
        'max_surface_characters': maxSurfaceCharacters,
        'max_recall_characters': maxRecallCharacters,
        'max_envelope_bytes': maxEnvelopeBytes,
      };
}

class ContextEnvelope {
  ContextEnvelope._({
    required this.conversationId,
    required this.identityPromptVersionRef,
    required this.toolsetVersion,
    required this.permissionProfileId,
    required this.runtimeProfile,
    required this.turnInstruction,
    required this.recentMessages,
    required this.surface,
    required this.recallSnippets,
    required this.budget,
    required this.createdAt,
  });

  factory ContextEnvelope({
    required String conversationId,
    required String identityPromptVersionRef,
    required String toolsetVersion,
    required String permissionProfileId,
    required RuntimeProfile runtimeProfile,
    required ContextText turnInstruction,
    List<ContextChatMessage> recentMessages = const [],
    required ContextSurface surface,
    List<ContextRecallSnippet> recallSnippets = const [],
    ContextBudget? budget,
    required DateTime createdAt,
  }) {
    _requireIdentifier(conversationId, 'conversationId');
    _requireIdentifier(identityPromptVersionRef, 'identityPromptVersionRef');
    _requireIdentifier(toolsetVersion, 'toolsetVersion');
    _requireIdentifier(permissionProfileId, 'permissionProfileId');
    if (turnInstruction.trust != ContextTrust.userInstruction) {
      throw ArgumentError('turnInstruction must be marked user_instruction');
    }
    final created = createdAt.toUtc();
    final effectiveBudget = budget ?? ContextBudget();
    _validateBudgetUse(
      turnInstruction: turnInstruction,
      recentMessages: recentMessages,
      surface: surface,
      recallSnippets: recallSnippets,
      budget: effectiveBudget,
    );
    _validateTemporalIntegrity(
      recentMessages: recentMessages,
      recallSnippets: recallSnippets,
      createdAt: created,
    );
    return ContextEnvelope._(
      conversationId: conversationId,
      identityPromptVersionRef: identityPromptVersionRef,
      toolsetVersion: toolsetVersion,
      permissionProfileId: permissionProfileId,
      runtimeProfile: runtimeProfile,
      turnInstruction: turnInstruction,
      recentMessages: List.unmodifiable(recentMessages),
      surface: surface,
      recallSnippets: List.unmodifiable(recallSnippets),
      budget: effectiveBudget,
      createdAt: created,
    );
  }

  factory ContextEnvelope.fromJson(Map<String, dynamic> json) {
    _expectKeys(
        json,
        const {
          'schema_version',
          'conversation_id',
          'identity_prompt_version_ref',
          'toolset_version',
          'permission_profile_id',
          'runtime_profile',
          'turn_instruction',
          'recent_messages',
          'surface',
          'recall_snippets',
          'budget',
          'created_at',
        },
        'ContextEnvelope');
    final version = _requireInt(json['schema_version'], 'schema_version');
    if (version != contextEnvelopeSchemaVersion) {
      throw FormatException(
        'Unsupported ContextEnvelope schema version: $version',
      );
    }
    return ContextEnvelope(
      conversationId: _requireString(
        json['conversation_id'],
        'conversation_id',
      ),
      identityPromptVersionRef: _requireString(
        json['identity_prompt_version_ref'],
        'identity_prompt_version_ref',
      ),
      toolsetVersion: _requireString(
        json['toolset_version'],
        'toolset_version',
      ),
      permissionProfileId: _requireString(
        json['permission_profile_id'],
        'permission_profile_id',
      ),
      runtimeProfile: RuntimeProfile.parse(json['runtime_profile']),
      turnInstruction: ContextText.fromJson(
        _requireMap(json['turn_instruction'], 'turn_instruction'),
      ),
      recentMessages:
          _requireList(json['recent_messages'], 'recent_messages').map((value) {
        return ContextChatMessage.fromJson(
          _requireMap(value, 'recent_messages[]'),
        );
      }).toList(growable: false),
      surface: ContextSurface.fromJson(_requireMap(json['surface'], 'surface')),
      recallSnippets:
          _requireList(json['recall_snippets'], 'recall_snippets').map((value) {
        return ContextRecallSnippet.fromJson(
          _requireMap(value, 'recall_snippets[]'),
        );
      }).toList(growable: false),
      budget: ContextBudget.fromJson(_requireMap(json['budget'], 'budget')),
      createdAt: _requireDateTime(json['created_at'], 'created_at'),
    );
  }

  final String conversationId;
  final String identityPromptVersionRef;
  final String toolsetVersion;
  final String permissionProfileId;
  final RuntimeProfile runtimeProfile;
  final ContextText turnInstruction;
  final List<ContextChatMessage> recentMessages;
  final ContextSurface surface;
  final List<ContextRecallSnippet> recallSnippets;
  final ContextBudget budget;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'schema_version': contextEnvelopeSchemaVersion,
        'conversation_id': conversationId,
        'identity_prompt_version_ref': identityPromptVersionRef,
        'toolset_version': toolsetVersion,
        'permission_profile_id': permissionProfileId,
        'runtime_profile': runtimeProfile.wireName,
        'turn_instruction': turnInstruction.toJson(),
        'recent_messages':
            recentMessages.map((message) => message.toJson()).toList(),
        'surface': surface.toJson(),
        'recall_snippets':
            recallSnippets.map((snippet) => snippet.toJson()).toList(),
        'budget': budget.toJson(),
        'created_at': createdAt.toIso8601String(),
      };
}

void _validateTemporalIntegrity({
  required List<ContextChatMessage> recentMessages,
  required List<ContextRecallSnippet> recallSnippets,
  required DateTime createdAt,
}) {
  final messageIds = <String>{};
  DateTime? previousMessageAt;
  for (final message in recentMessages) {
    if (!messageIds.add(message.messageId)) {
      throw ArgumentError(
        'recentMessages contains duplicate messageId ${message.messageId}',
      );
    }
    if (previousMessageAt != null &&
        message.occurredAt.isBefore(previousMessageAt)) {
      throw ArgumentError('recentMessages must be ordered by occurredAt');
    }
    if (message.occurredAt.isAfter(createdAt)) {
      throw ArgumentError('recentMessages cannot contain future messages');
    }
    previousMessageAt = message.occurredAt;
  }
  for (final snippet in recallSnippets) {
    if (snippet.retrievedAt.isAfter(createdAt)) {
      throw ArgumentError('recallSnippets cannot be retrieved in the future');
    }
  }
}

void _validateBudgetUse({
  required ContextText turnInstruction,
  required List<ContextChatMessage> recentMessages,
  required ContextSurface surface,
  required List<ContextRecallSnippet> recallSnippets,
  required ContextBudget budget,
}) {
  if (recentMessages.length > budget.maxRecentMessages) {
    throw ArgumentError('recentMessages exceeds its declared budget');
  }
  if (surface.objectReferences.length > budget.maxObjectReferences) {
    throw ArgumentError('objectReferences exceeds its declared budget');
  }
  if (recallSnippets.length > budget.maxRecallSnippets) {
    throw ArgumentError('recallSnippets exceeds its declared budget');
  }
  if (turnInstruction.text.length > budget.maxTurnInstructionCharacters) {
    throw ArgumentError('turnInstruction exceeds its declared budget');
  }
  final recentCharacters = recentMessages.fold<int>(
    0,
    (sum, message) => sum + message.content.text.length,
  );
  if (recentCharacters > budget.maxRecentChatCharacters) {
    throw ArgumentError('recentMessages exceeds its character budget');
  }
  final surfaceCharacters = surface.objectReferences.fold<int>(
    0,
    (sum, reference) => sum + (reference.summary?.text.length ?? 0),
  );
  if (surfaceCharacters > budget.maxSurfaceCharacters) {
    throw ArgumentError('surface summaries exceed their character budget');
  }
  final recallCharacters = recallSnippets.fold<int>(
    0,
    (sum, snippet) => sum + snippet.content.text.length,
  );
  if (recallCharacters > budget.maxRecallCharacters) {
    throw ArgumentError('recall snippets exceed their character budget');
  }
}

void _requireBudget(int value, int hardLimit, String field) {
  if (value <= 0 || value > hardLimit) {
    throw ArgumentError('$field must be between 1 and $hardLimit');
  }
}

void _requireIdentifier(String value, String field) {
  _requireText(value, field, ContextEnvelopeLimits.maxIdentifierCharacters);
}

void _requireWorkspaceRef(String value) {
  _requireIdentifier(value, 'workspaceRef');
  final isAbsoluteWindowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
  final isAbsolutePosixPath = value.startsWith('/');
  final isNetworkPath = value.startsWith(r'\\');
  if (isAbsoluteWindowsPath || isAbsolutePosixPath || isNetworkPath) {
    throw ArgumentError(
      'workspaceRef must be a stable reference, not an absolute path',
    );
  }
}

void _requireText(String value, String field, int maxCharacters) {
  if (value.trim().isEmpty || value.length > maxCharacters) {
    throw ArgumentError(
      '$field must be non-blank and at most $maxCharacters characters',
    );
  }
}

String _requireString(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

int _requireInt(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer');
  return value;
}

DateTime _requireDateTime(Object? value, String field) {
  final raw = _requireString(value, field);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('$field must be an ISO-8601 date');
  return parsed;
}

Map<String, dynamic> _requireMap(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

List<dynamic> _requireList(Object? value, String field) {
  if (value is! List<dynamic>) throw FormatException('$field must be a list');
  return value;
}

void _expectKeys(Map<String, dynamic> json, Set<String> allowed, String type) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('$type contains unsupported fields: $unknown');
  }
}
