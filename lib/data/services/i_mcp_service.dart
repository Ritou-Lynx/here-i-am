import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/mcp/mcp_client.dart';
import 'package:memex/agent/mcp/mcp_oauth.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/utils/user_storage.dart';

const iMcpRedirectUri = 'http://127.0.0.1:47859/hereiam/i-mcp/callback';
const _iMcpStoragePrefix = 'i_mcp';

/// Whether a refresh failure proves that the saved OAuth grant is unusable.
bool shouldClearIMcpAuthorizationAfterRefreshError(Object error) {
  if (error case DioException(:final response)) {
    final statusCode = response?.statusCode;
    if (statusCode == 400 || statusCode == 401) return true;
    if (_containsRejectedOAuthGrant(response?.data)) return true;
  }

  final description = error.toString().toLowerCase();
  return RegExp(r'http\s+(400|401)\b').hasMatch(description) ||
      RegExp(r'status code of\s+(400|401)\b').hasMatch(description) ||
      _containsRejectedOAuthGrant(description);
}

bool _containsRejectedOAuthGrant(Object? value) {
  if (value is Map) {
    final oauthError = value['error']?.toString().toLowerCase();
    return oauthError == 'invalid_grant' || oauthError == 'invalid_client';
  }
  final description = value?.toString().toLowerCase() ?? '';
  return RegExp(r'\binvalid_(grant|client)\b').hasMatch(description);
}

/// Narrow interface used by the companion tool so tests do not need a real
/// network connection or persisted OAuth credentials.
abstract interface class IMcpQueryService {
  bool get isConnected;

  String? get lastError;

  Future<void> ensureConnected();

  Future<McpToolCallResult> callTool(
    String name, {
    Map<String, dynamic>? arguments,
  });
}

/// Manages the read-only i MCP connection and its OAuth token lifecycle.
class IMcpService implements IMcpQueryService {
  static final _logger = Logger('IMcpService');
  static IMcpService? _instance;

  McpClient? _client;
  bool _initializing = false;
  String? _lastError;

  IMcpService._();

  static IMcpService get instance => _instance ??= IMcpService._();

  @override
  bool get isConnected => _client?.isConnected ?? false;

  @override
  String? get lastError => _lastError;

  Future<String?> storedServerUrl({String? userId}) async {
    userId ??= await UserStorage.getUserId();
    if (userId == null) return null;
    final file = _configurationFile(userId);
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) return null;
      return value['server_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasStoredToken({String? userId}) async {
    userId ??= await UserStorage.getUserId();
    if (userId == null) return false;
    return (await _tokenStorage(userId).load()) != null;
  }

  Future<void> saveAuthorization({
    required String serverUrl,
    required McpOAuthToken token,
    required String clientId,
    required String tokenEndpoint,
    String? userId,
  }) async {
    userId ??= await UserStorage.getUserId();
    if (userId == null) {
      throw const IMcpException('没有可用的用户，无法保存 i MCP 连接');
    }
    final normalizedUrl = normalizeServerUrl(serverUrl);
    final configFile = _configurationFile(userId);
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(jsonEncode({'server_url': normalizedUrl}));
    await _tokenStorage(userId).save(
      token,
      clientId: clientId,
      tokenEndpoint: tokenEndpoint,
    );
  }

  static String normalizeServerUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.path != '/mcp' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('地址必须是 https://…/mcp，且不能带查询或片段');
    }
    return uri.toString();
  }

  @override
  Future<void> ensureConnected({String? userId}) async {
    if (isConnected || _initializing) return;
    _initializing = true;
    _lastError = null;
    try {
      userId ??= await UserStorage.getUserId();
      if (userId == null) {
        _lastError = '还没连接 i MCP，请到设置里连接';
        return;
      }
      final serverUrl = await storedServerUrl(userId: userId);
      final storage = _tokenStorage(userId);
      var token = await storage.load();
      if (serverUrl == null || token == null) {
        _lastError = '还没连接 i MCP，请到设置里连接';
        return;
      }

      if (token.isExpired) {
        token = await _refreshToken(
          userId: userId,
          serverUrl: serverUrl,
          token: token,
        );
        if (token == null) return;
      }

      try {
        await _connect(serverUrl, token.accessToken);
      } catch (error) {
        if (!_isUnauthorized(error)) rethrow;
        final refreshed = await _refreshToken(
          userId: userId,
          serverUrl: serverUrl,
          token: token,
        );
        if (refreshed == null) return;
        await _connect(serverUrl, refreshed.accessToken);
      }
    } catch (error) {
      _lastError = 'i MCP 连接失败：$error';
      _logger.warning(_lastError!);
      await _dropClient();
    } finally {
      _initializing = false;
    }
  }

  @override
  Future<McpToolCallResult> callTool(
    String name, {
    Map<String, dynamic>? arguments,
  }) async {
    await ensureConnected();
    var client = _client;
    if (client == null || !client.isConnected) {
      throw IMcpException(_lastError ?? '还没连接 i MCP，请到设置里连接');
    }
    try {
      return await client.callTool(name, arguments: arguments);
    } catch (error) {
      if (!_isUnauthorized(error)) rethrow;
      final userId = await UserStorage.getUserId();
      final serverUrl = await storedServerUrl(userId: userId);
      final token = userId == null ? null : await _tokenStorage(userId).load();
      if (userId == null || serverUrl == null || token == null) rethrow;
      final refreshed = await _refreshToken(
        userId: userId,
        serverUrl: serverUrl,
        token: token,
      );
      if (refreshed == null) {
        throw IMcpException(_lastError ?? 'i MCP 授权已失效，请到设置里重新连接');
      }
      await _connect(serverUrl, refreshed.accessToken);
      client = _client!;
      return client.callTool(name, arguments: arguments);
    }
  }

  Future<McpToolsListResult> listTools() async {
    await ensureConnected();
    final client = _client;
    if (client == null || !client.isConnected) {
      throw IMcpException(_lastError ?? '还没连接 i MCP，请到设置里连接');
    }
    return client.listTools();
  }

  Future<void> disconnect({String? userId}) async {
    userId ??= await UserStorage.getUserId();
    await _dropClient();
    if (userId != null) {
      await _tokenStorage(userId).delete();
      final configFile = _configurationFile(userId);
      if (await configFile.exists()) await configFile.delete();
    }
    _lastError = null;
  }

  Future<void> _connect(String serverUrl, String accessToken) async {
    await _dropClient();
    final client = McpClient(serverUrl: serverUrl, accessToken: accessToken);
    try {
      await client.initialize();
      _client = client;
      _lastError = null;
    } catch (_) {
      await client.disconnect();
      rethrow;
    }
  }

  Future<McpOAuthToken?> _refreshToken({
    required String userId,
    required String serverUrl,
    required McpOAuthToken token,
  }) async {
    final storage = _tokenStorage(userId);
    final meta = await storage.loadRefreshMeta();
    if (token.refreshToken == null || meta == null) {
      await _clearExpiredAuthorization(storage);
      return null;
    }
    try {
      final refreshed = await McpOAuth(serverUrl: serverUrl).refreshToken(
        metadata: McpOAuthMetadata(tokenEndpoint: meta.tokenEndpoint),
        refreshToken: token.refreshToken!,
        clientId: meta.clientId,
      );
      await storage.save(
        refreshed,
        clientId: meta.clientId,
        tokenEndpoint: meta.tokenEndpoint,
      );
      return refreshed;
    } catch (error) {
      _logger.warning('i MCP token refresh failed: $error');
      if (shouldClearIMcpAuthorizationAfterRefreshError(error)) {
        await _clearExpiredAuthorization(storage);
      } else {
        _lastError = '暂时连不上 i MCP（家里电脑可能离线），稍后再试';
      }
      return null;
    }
  }

  Future<void> _clearExpiredAuthorization(McpTokenStorage storage) async {
    await storage.delete();
    await _dropClient();
    _lastError = 'i MCP 授权已失效，请到设置里重新连接';
  }

  Future<void> _dropClient() async {
    await _client?.disconnect();
    _client = null;
  }

  bool _isUnauthorized(Object error) =>
      error.toString().contains('HTTP 401') ||
      error.toString().contains('status code of 401');

  McpTokenStorage _tokenStorage(String userId) =>
      McpTokenStorage(userId: userId, serviceId: _iMcpStoragePrefix);

  File _configurationFile(String userId) {
    final directory =
        '${FileSystemService.instance.getUserSettingsPath(userId)}/mcp';
    return File('$directory/${_iMcpStoragePrefix}_connection.json');
  }
}

class IMcpException implements Exception {
  final String message;
  const IMcpException(this.message);

  @override
  String toString() => message;
}
