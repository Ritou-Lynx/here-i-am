import 'dart:convert';
import 'dart:io';

import 'package:memex/agent/mcp/mcp_oauth.dart';
import 'package:memex/data/services/file_system_service.dart';

/// Persists MCP OAuth tokens to the user's settings directory.
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

  Future<void> save(McpOAuthToken token) async {
    final file = File(_path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(token.toJson()));
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
