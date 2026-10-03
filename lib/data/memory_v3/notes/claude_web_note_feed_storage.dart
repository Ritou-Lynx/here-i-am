import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ClaudeWebNoteFeedConfig {
  const ClaudeWebNoteFeedConfig({
    required this.baseUrl,
    required this.token,
    this.cursor = 0,
  });
  final String baseUrl;
  final String token;
  final int cursor;

  static String normalizeBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final loopback = uri?.host == 'localhost' ||
        uri?.host == '127.0.0.1' ||
        uri?.host == '::1';
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
      throw const FormatException('请填写 Tailscale HTTPS 根地址');
    }
    return uri.replace(path: '').toString();
  }
}

/// Per-installation secrets and cursor; never enters preferences/config sync.
/// One secure-storage value avoids partially written URL/token/cursor tuples.
class ClaudeWebNoteFeedStorage {
  ClaudeWebNoteFeedStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secureStorage;
  static const storageKey = 'claude_web_note_feed_v1';

  Future<ClaudeWebNoteFeedConfig?> readConfig() async {
    final raw = await _secureStorage.read(key: storageKey);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final token = data['token'];
    if (token is! String || token.trim().isEmpty) return null;
    final cursor = data['cursor'];
    if (cursor is! int || cursor < 0) throw const FormatException('记录游标无效');
    return ClaudeWebNoteFeedConfig(
      baseUrl: ClaudeWebNoteFeedConfig.normalizeBaseUrl(
        data['base_url'] as String,
      ),
      token: token,
      cursor: cursor,
    );
  }

  Future<void> saveConfig({
    required String baseUrl,
    required String token,
  }) async {
    final url = ClaudeWebNoteFeedConfig.normalizeBaseUrl(baseUrl);
    final secret = token.trim();
    if (secret.isEmpty || RegExp(r'\s').hasMatch(secret)) {
      throw const FormatException('请填写有效手机令牌');
    }
    final previous = await readConfig();
    await _write(
      ClaudeWebNoteFeedConfig(
        baseUrl: url,
        token: secret,
        cursor: previous?.baseUrl == url ? previous!.cursor : 0,
      ),
    );
  }

  Future<void> saveCursor({
    required String baseUrl,
    required int cursor,
  }) async {
    final config = await readConfig();
    if (config == null || config.baseUrl != baseUrl || cursor < config.cursor) {
      throw StateError('记录连接已改变，请重新同步');
    }
    await _write(
      ClaudeWebNoteFeedConfig(
        baseUrl: config.baseUrl,
        token: config.token,
        cursor: cursor,
      ),
    );
  }

  Future<void> clearConfig() => _secureStorage.delete(key: storageKey);
  Future<void> _write(ClaudeWebNoteFeedConfig config) => _secureStorage.write(
        key: storageKey,
        value: jsonEncode({
          'base_url': config.baseUrl,
          'token': config.token,
          'cursor': config.cursor,
        }),
      );
}
