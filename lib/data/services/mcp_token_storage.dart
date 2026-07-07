import 'dart:convert';
import 'dart:io';

import 'package:memex/agent/mcp/mcp_oauth.dart';
import 'package:memex/data/services/file_system_service.dart';

/// Persists MCP OAuth tokens + refresh metadata to the user's settings
/// directory, so [CorosMcpService] can automatically refresh expired tokens.
class McpTokenStorage {
  final String userId;
  final String serviceId;

  McpTokenStorage({required this.userId, this.serviceId = 'coros'});

  String get _path {
    final dir =
        '${FileSystemService.instance.getUserSettingsPath(userId)}/mcp';
    return '$dir/${serviceId}_token.json';
  }

  Future<McpOAuthToken?> load() async {
    final file = File(_path);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return McpOAuthToken.fromStoredJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Load extra fields needed for token refresh.
  Future<_TokenRefreshMeta?> loadRefreshMeta() async {
    final file = File(_path);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final clientId = json['_client_id'] as String?;
      final tokenEndpoint = json['_token_endpoint'] as String?;
      if (clientId == null || tokenEndpoint == null) return null;
      return _TokenRefreshMeta(
        clientId: clientId,
        tokenEndpoint: tokenEndpoint,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(McpOAuthToken token,
      {String? clientId, String? tokenEndpoint}) async {
    final file = File(_path);
    await file.parent.create(recursive: true);
    final map = token.toJson();
    if (clientId != null) map['_client_id'] = clientId;
    if (tokenEndpoint != null) map['_token_endpoint'] = tokenEndpoint;
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(map));
  }

  Future<void> delete() async {
    final file = File(_path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> hasToken() async {
    final token = await load();
    return token != null && !token.isExpired;
  }
}

class _TokenRefreshMeta {
  final String clientId;
  final String tokenEndpoint;
  const _TokenRefreshMeta(
      {required this.clientId, required this.tokenEndpoint});
}
