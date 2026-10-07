/// Wire models for the private cross-device i core protocol.
///
/// Keep this file independent from Drift rows. Local integer database IDs are
/// deliberately absent because they are not stable across devices.
library;

import 'dart:convert';

abstract final class CoreSyncProtocol {
  static const version = '0.1';
  static const basePath = '/v1/core';
  static const maxMessageBatch = 100;
}

enum CoreMessageSender {
  user('user'),
  companion('companion'),
  system('system');

  const CoreMessageSender(this.wireValue);
  final String wireValue;

  static CoreMessageSender parse(Object? value) => values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException('Invalid sender: $value'),
      );
}

enum CoreSubmitStatus {
  accepted('accepted'),
  duplicate('duplicate');

  const CoreSubmitStatus(this.wireValue);
  final String wireValue;

  static CoreSubmitStatus parse(Object? value) => values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException('Invalid submit status: $value'),
      );
}

class CoreHealthResponse {
  const CoreHealthResponse({
    required this.ok,
    required this.nodeId,
    required this.role,
    required this.protocolVersion,
    required this.minimumProtocolVersion,
    required this.schemaVersion,
    required this.serverTimeMs,
    this.features = const [],
  });

  final bool ok;
  final String nodeId;
  final String role;
  final String protocolVersion;
  final String minimumProtocolVersion;
  final int schemaVersion;
  final int serverTimeMs;
  final List<String> features;

  bool get isAuthority => ok && role == 'authority';

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'node_id': nodeId,
        'role': role,
        'protocol_version': protocolVersion,
        'minimum_protocol_version': minimumProtocolVersion,
        'schema_version': schemaVersion,
        'server_time_ms': serverTimeMs,
        'features': features,
      };

  factory CoreHealthResponse.fromJson(Map<String, dynamic> json) =>
      CoreHealthResponse(
        ok: _requiredBool(json, 'ok'),
        nodeId: _requiredString(json, 'node_id'),
        role: _requiredString(json, 'role'),
        protocolVersion: _requiredString(json, 'protocol_version'),
        minimumProtocolVersion:
            _requiredString(json, 'minimum_protocol_version'),
        schemaVersion: _requiredInt(json, 'schema_version'),
        serverTimeMs: _requiredInt(json, 'server_time_ms'),
        features: _stringList(json['features'], 'features'),
      );
}

class CoreDevicePairRequest {
  const CoreDevicePairRequest({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.clientVersion,
    required this.pairingCode,
    this.capabilities = const [],
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String clientVersion;
  final String pairingCode;
  final List<String> capabilities;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'display_name': displayName,
        'platform': platform,
        'client_version': clientVersion,
        'pairing_code': pairingCode,
        'capabilities': capabilities,
      };

  factory CoreDevicePairRequest.fromJson(Map<String, dynamic> json) =>
      CoreDevicePairRequest(
        deviceId: _requiredString(json, 'device_id'),
        displayName: _requiredString(json, 'display_name'),
        platform: _requiredString(json, 'platform'),
        clientVersion: _requiredString(json, 'client_version'),
        pairingCode: _requiredString(json, 'pairing_code'),
        capabilities: _stringList(json['capabilities'], 'capabilities'),
      );
}

class CoreDevicePairResponse {
  const CoreDevicePairResponse({
    required this.deviceId,
    required this.deviceToken,
    required this.initialCursor,
    required this.coreNodeId,
    required this.protocolVersion,
    this.domainAccess,
  });

  final String deviceId;
  final String deviceToken;
  final String initialCursor;
  final String coreNodeId;
  final String protocolVersion;
  final CoreDomainAccessGrant? domainAccess;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_token': deviceToken,
        'initial_cursor': initialCursor,
        'core_node_id': coreNodeId,
        'protocol_version': protocolVersion,
        if (domainAccess != null) 'domain_access': domainAccess!.toJson(),
      };

  factory CoreDevicePairResponse.fromJson(Map<String, dynamic> json) {
    final deviceId = _requiredString(json, 'device_id');
    final coreNodeId = _requiredString(json, 'core_node_id');
    final domainAccess = json['domain_access'] == null
        ? null
        : CoreDomainAccessGrant.fromJson(_requiredMap(json, 'domain_access'));
    if (domainAccess != null &&
        (domainAccess.coreInstanceId != coreNodeId ||
            domainAccess.installationId != deviceId ||
            domainAccess.token == _requiredString(json, 'device_token'))) {
      throw const FormatException('domain_access pairing binding mismatch');
    }
    return CoreDevicePairResponse(
      deviceId: deviceId,
      deviceToken: _requiredString(json, 'device_token'),
      initialCursor: _requiredString(json, 'initial_cursor'),
      coreNodeId: coreNodeId,
      protocolVersion: _requiredString(json, 'protocol_version'),
      domainAccess: domainAccess,
    );
  }
}

class CoreDomainAuthorizationGrant {
  const CoreDomainAuthorizationGrant({
    required this.scheme,
    required this.keyId,
    required this.secret,
  });

  final String scheme;
  final String keyId;
  final String secret;

  Map<String, dynamic> toJson() => {
        'scheme': scheme,
        'key_id': keyId,
        'secret': secret,
      };

  factory CoreDomainAuthorizationGrant.fromJson(Map<String, dynamic> json) {
    final scheme = _requiredString(json, 'scheme');
    final keyId = _requiredString(json, 'key_id');
    final secret = _requiredString(json, 'secret');
    if (scheme != 'hmac-sha256-v1' ||
        !RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(keyId) ||
        _decodeBase64Url(secret).length != 32) {
      throw const FormatException('invalid domain authorization grant');
    }
    return CoreDomainAuthorizationGrant(
        scheme: scheme, keyId: keyId, secret: secret);
  }
}

/// Optional, separately scoped domain credential returned only after the Core
/// owner provisioned this exact device and installation. It is not the chat
/// device token and its presence never changes a domain route or bridge owner.
class CoreDomainAccessGrant {
  const CoreDomainAccessGrant({
    required this.protocolVersion,
    required this.coreInstanceId,
    required this.principalId,
    required this.credentialGeneration,
    required this.installationId,
    required this.policyVersion,
    required this.schemaVersion,
    required this.token,
    required this.scopes,
    required this.authorization,
  });

  final int protocolVersion;
  final String coreInstanceId;
  final String principalId;
  final int credentialGeneration;
  final String installationId;
  final String policyVersion;
  final int schemaVersion;
  final String token;
  final List<String> scopes;
  final CoreDomainAuthorizationGrant authorization;

  Map<String, dynamic> toJson() => {
        'protocol_version': protocolVersion,
        'core_instance_id': coreInstanceId,
        'principal_id': principalId,
        'credential_generation': credentialGeneration,
        'installation_id': installationId,
        'policy_version': policyVersion,
        'schema_version': schemaVersion,
        'token': token,
        'scopes': scopes,
        'authorization': authorization.toJson(),
      };

  factory CoreDomainAccessGrant.fromJson(Map<String, dynamic> json) {
    final value = CoreDomainAccessGrant(
      protocolVersion: _requiredInt(json, 'protocol_version'),
      coreInstanceId: _requiredString(json, 'core_instance_id'),
      principalId: _requiredString(json, 'principal_id'),
      credentialGeneration:
          _requiredNonNegativeInt(json, 'credential_generation'),
      installationId: _requiredString(json, 'installation_id'),
      policyVersion: _requiredString(json, 'policy_version'),
      schemaVersion: _requiredInt(json, 'schema_version'),
      token: _requiredString(json, 'token'),
      scopes: _stringList(json['scopes'], 'scopes'),
      authorization: CoreDomainAuthorizationGrant.fromJson(
          _requiredMap(json, 'authorization')),
    );
    const allowedScopes = {
      'captures:read',
      'captures:create',
      'captures:patch',
      'captures:delete',
      'captures:ack',
      'captures:adopt',
      'captures:owner',
      'plan_items:read',
      'plan_items:status',
      'plan_items:ack',
      'plan_days:read',
      'plan_days:ack',
      'plan_weeks:read',
      'plan_weeks:ack',
    };
    final idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$');
    if (value.protocolVersion != 1 ||
        value.schemaVersion != 1 ||
        value.credentialGeneration < 1 ||
        !idPattern.hasMatch(value.coreInstanceId) ||
        !idPattern.hasMatch(value.principalId) ||
        !idPattern.hasMatch(value.installationId) ||
        value.scopes.isEmpty ||
        value.scopes.toSet().length != value.scopes.length ||
        value.scopes.any((scope) => !allowedScopes.contains(scope))) {
      throw const FormatException('unsupported domain access grant');
    }
    return value;
  }
}

enum CoreCompanionUploadMode { legacyB3, pr10, disabled }

/// Only legacy B3 enabled+scope grants transcript permission. PR10 mode alone
/// never grants companion authorization: local owner opt-in and Core grant remain separate.
class CoreChatTranscriptCapabilities {
  const CoreChatTranscriptCapabilities.disabled({
    this.uploadMode = CoreCompanionUploadMode.disabled,
  })  : enabled = false,
        fromCreatedAtMs = null,
        characterId = null;

  const CoreChatTranscriptCapabilities.enabled({
    required int this.fromCreatedAtMs,
    required String this.characterId,
  })  : enabled = true,
        uploadMode = CoreCompanionUploadMode.legacyB3;

  final bool enabled;
  final int? fromCreatedAtMs;
  final String? characterId;
  final CoreCompanionUploadMode uploadMode;

  factory CoreChatTranscriptCapabilities.fromJson(Map<String, dynamic> json) {
    final enabled = _requiredBool(json, 'enabled');
    final mode = json['companion_upload_mode'];
    if (mode == 'pr10') {
      return const CoreChatTranscriptCapabilities.disabled(
          uploadMode: CoreCompanionUploadMode.pr10);
    }
    // Missing mode is the deployed B3 contract. Unknown future modes fail closed.
    if ((mode != null && mode != 'legacy_b3') || !enabled) {
      return const CoreChatTranscriptCapabilities.disabled();
    }
    final cutoff = _requiredNonNegativeInt(json, 'from_created_at_ms');
    if (cutoff == 0) {
      throw const FormatException('from_created_at_ms must be positive');
    }
    return CoreChatTranscriptCapabilities.enabled(
        fromCreatedAtMs: cutoff,
        characterId: _requiredString(json, 'character_id'));
  }
}

class CoreAssetRef {
  const CoreAssetRef({
    required this.assetId,
    required this.mimeType,
    required this.sha256,
    required this.byteLength,
    this.fileName,
  });

  final String assetId;
  final String mimeType;
  final String sha256;
  final int byteLength;
  final String? fileName;

  Map<String, dynamic> toJson() => {
        'asset_id': assetId,
        'mime_type': mimeType,
        'sha256': sha256,
        'byte_length': byteLength,
        if (fileName != null) 'file_name': fileName,
      };

  factory CoreAssetRef.fromJson(Map<String, dynamic> json) => CoreAssetRef(
        assetId: _requiredString(json, 'asset_id'),
        mimeType: _requiredString(json, 'mime_type'),
        sha256: _requiredString(json, 'sha256'),
        byteLength: _requiredNonNegativeInt(json, 'byte_length'),
        fileName: _optionalString(json, 'file_name'),
      );
}

class CoreChatMessageWire {
  const CoreChatMessageWire({
    required this.syncId,
    required this.originDeviceId,
    required this.originSequence,
    required this.characterId,
    required this.sender,
    required this.content,
    required this.createdAtMs,
    this.messageType = 'chat',
    this.assetRefs = const [],
    this.addenda = const [],
  });

  final String syncId;
  final String originDeviceId;
  final int originSequence;
  final String characterId;
  final CoreMessageSender sender;
  final String content;
  final int createdAtMs;
  final String messageType;
  final List<CoreAssetRef> assetRefs;
  final List<Map<String, dynamic>> addenda;

  Map<String, dynamic> toJson() => {
        'sync_id': syncId,
        'origin_device_id': originDeviceId,
        'origin_sequence': originSequence,
        'character_id': characterId,
        'sender': sender.wireValue,
        'content': content,
        'created_at_ms': createdAtMs,
        'message_type': messageType,
        'asset_refs': assetRefs.map((item) => item.toJson()).toList(),
        'addenda': addenda,
      };

  factory CoreChatMessageWire.fromJson(Map<String, dynamic> json) =>
      CoreChatMessageWire(
        syncId: _requiredString(json, 'sync_id'),
        originDeviceId: _requiredString(json, 'origin_device_id'),
        originSequence: _requiredNonNegativeInt(json, 'origin_sequence'),
        characterId: _requiredString(json, 'character_id'),
        sender: CoreMessageSender.parse(json['sender']),
        content: _requiredString(json, 'content', allowEmpty: true),
        createdAtMs: _requiredNonNegativeInt(json, 'created_at_ms'),
        messageType: _requiredString(json, 'message_type'),
        assetRefs: _mapList(json['asset_refs'], 'asset_refs')
            .map(CoreAssetRef.fromJson)
            .toList(),
        addenda: _mapList(json['addenda'], 'addenda'),
      );
}

class CoreChatSubmitRequest {
  CoreChatSubmitRequest({required this.deviceId, required this.messages}) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
    }
    if (messages.isEmpty ||
        messages.length > CoreSyncProtocol.maxMessageBatch) {
      throw ArgumentError.value(
        messages.length,
        'messages',
        'must contain 1-${CoreSyncProtocol.maxMessageBatch} items',
      );
    }
    for (final message in messages) {
      if (message.originDeviceId != deviceId) {
        throw ArgumentError.value(
          message.originDeviceId,
          'messages.originDeviceId',
          'must match request deviceId',
        );
      }
    }
  }

  final String deviceId;
  final List<CoreChatMessageWire> messages;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'messages': messages.map((item) => item.toJson()).toList(),
      };

  factory CoreChatSubmitRequest.fromJson(Map<String, dynamic> json) =>
      CoreChatSubmitRequest(
        deviceId: _requiredString(json, 'device_id'),
        messages: _mapList(json['messages'], 'messages')
            .map(CoreChatMessageWire.fromJson)
            .toList(),
      );
}

class CoreChatSubmitResult {
  const CoreChatSubmitResult({
    required this.syncId,
    required this.status,
    required this.serverSequence,
  });

  final String syncId;
  final CoreSubmitStatus status;
  final int serverSequence;

  Map<String, dynamic> toJson() => {
        'sync_id': syncId,
        'status': status.wireValue,
        'server_sequence': serverSequence,
      };

  factory CoreChatSubmitResult.fromJson(Map<String, dynamic> json) =>
      CoreChatSubmitResult(
        syncId: _requiredString(json, 'sync_id'),
        status: CoreSubmitStatus.parse(json['status']),
        serverSequence: _requiredNonNegativeInt(json, 'server_sequence'),
      );
}

class CoreChatSubmitResponse {
  const CoreChatSubmitResponse({required this.results});

  final List<CoreChatSubmitResult> results;

  Map<String, dynamic> toJson() => {
        'results': results.map((item) => item.toJson()).toList(),
      };

  factory CoreChatSubmitResponse.fromJson(Map<String, dynamic> json) =>
      CoreChatSubmitResponse(
        results: _mapList(json['results'], 'results')
            .map(CoreChatSubmitResult.fromJson)
            .toList(),
      );
}

class CoreChangeEvent {
  const CoreChangeEvent({
    required this.eventId,
    required this.serverSequence,
    required this.kind,
    required this.entityId,
    required this.occurredAtMs,
    required this.payload,
  });

  final String eventId;
  final int serverSequence;

  /// Kept as String so old clients can ignore future event kinds while still
  /// advancing their opaque cursor.
  final String kind;
  final String entityId;
  final int occurredAtMs;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'server_sequence': serverSequence,
        'kind': kind,
        'entity_id': entityId,
        'occurred_at_ms': occurredAtMs,
        'payload': payload,
      };

  factory CoreChangeEvent.fromJson(Map<String, dynamic> json) =>
      CoreChangeEvent(
        eventId: _requiredString(json, 'event_id'),
        serverSequence: _requiredNonNegativeInt(json, 'server_sequence'),
        kind: _requiredString(json, 'kind'),
        entityId: _requiredString(json, 'entity_id'),
        occurredAtMs: _requiredNonNegativeInt(json, 'occurred_at_ms'),
        payload: _requiredMap(json, 'payload'),
      );
}

class CoreChangePage {
  const CoreChangePage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<CoreChangeEvent> events;
  final String nextCursor;
  final bool hasMore;

  Map<String, dynamic> toJson() => {
        'events': events.map((item) => item.toJson()).toList(),
        'next_cursor': nextCursor,
        'has_more': hasMore,
      };

  factory CoreChangePage.fromJson(Map<String, dynamic> json) => CoreChangePage(
        events: _mapList(json['events'], 'events')
            .map(CoreChangeEvent.fromJson)
            .toList(),
        nextCursor: _requiredString(json, 'next_cursor'),
        hasMore: _requiredBool(json, 'has_more'),
      );
}

class CoreCursorAckRequest {
  const CoreCursorAckRequest({required this.deviceId, required this.cursor});

  final String deviceId;
  final String cursor;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'cursor': cursor,
      };

  factory CoreCursorAckRequest.fromJson(Map<String, dynamic> json) =>
      CoreCursorAckRequest(
        deviceId: _requiredString(json, 'device_id'),
        cursor: _requiredString(json, 'cursor'),
      );
}

class CoreApiErrorBody {
  const CoreApiErrorBody({
    required this.code,
    required this.message,
    required this.retryable,
    this.details = const {},
  });

  final String code;
  final String message;
  final bool retryable;
  final Map<String, dynamic> details;

  Map<String, dynamic> toJson() => {
        'error': {
          'code': code,
          'message': message,
          'retryable': retryable,
          'details': details,
        },
      };

  factory CoreApiErrorBody.fromJson(Map<String, dynamic> json) {
    final error = _requiredMap(json, 'error');
    return CoreApiErrorBody(
      code: _requiredString(error, 'code'),
      message: _requiredString(error, 'message'),
      retryable: _requiredBool(error, 'retryable'),
      details:
          error['details'] == null ? const {} : _requiredMap(error, 'details'),
    );
  }
}

String _requiredString(
  Map<String, dynamic> json,
  String field, {
  bool allowEmpty = false,
}) {
  final value = json[field];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException(
        '$field must be a${allowEmpty ? '' : ' non-empty'} string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! num || value.toInt() != value) {
    throw FormatException('$field must be an integer');
  }
  return value.toInt();
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String field) {
  final value = _requiredInt(json, field);
  if (value < 0) throw FormatException('$field must be non-negative');
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! bool) throw FormatException('$field must be a boolean');
  return value;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! Map) throw FormatException('$field must be an object');
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _mapList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! Map)) {
    throw FormatException('$field must be an array of objects');
  }
  return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}

List<String> _stringList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$field must be an array of strings');
  }
  return value.cast<String>();
}

List<int> _decodeBase64Url(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw const FormatException('invalid base64url');
  }
  final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  try {
    final decoded = base64Url.decode(padded);
    if (base64UrlEncode(decoded).replaceAll('=', '') != value) {
      throw const FormatException('invalid base64url');
    }
    return decoded;
  } on FormatException {
    throw const FormatException('invalid base64url');
  }
}
