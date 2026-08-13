import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-installation connection credentials for the private i core.
///
/// These values must never enter SharedPreferences, config sync or backups.
/// The device token is equivalent to a login credential; the initial cursor
/// and node id also belong to this specific device/core pairing.
class CoreSyncConnection {
  const CoreSyncConnection({
    required this.baseUrl,
    required this.deviceToken,
    required this.initialCursor,
    required this.coreNodeId,
  });

  final String baseUrl;
  final String deviceToken;
  final String initialCursor;
  final String coreNodeId;

  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw const FormatException('核心地址不能为空');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('核心地址格式不正确');
    }
    final isLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      throw const FormatException('远程核心必须使用 HTTPS');
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const FormatException('核心地址不能包含查询参数或片段');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException('核心地址不能包含账号或密码');
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException('请填写核心的根地址，不要附加路径');
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

class CoreSyncConnectionStore {
  CoreSyncConnectionStore._();

  static final CoreSyncConnectionStore instance = CoreSyncConnectionStore._();

  static const _storage = FlutterSecureStorage();

  static const _baseUrlKey = 'i_core_base_url';
  static const _deviceTokenKey = 'i_core_device_token';
  static const _initialCursorKey = 'i_core_initial_cursor';
  static const _coreNodeIdKey = 'i_core_node_id';

  Future<CoreSyncConnection?> read() async {
    final values = await _storage.readAll();
    final baseUrl = values[_baseUrlKey];
    final token = values[_deviceTokenKey];
    final cursor = values[_initialCursorKey];
    final nodeId = values[_coreNodeIdKey];
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        token == null ||
        token.isEmpty ||
        cursor == null ||
        cursor.isEmpty ||
        nodeId == null ||
        nodeId.isEmpty) {
      return null;
    }
    return CoreSyncConnection(
      baseUrl: baseUrl,
      deviceToken: token,
      initialCursor: cursor,
      coreNodeId: nodeId,
    );
  }

  Future<void> save(CoreSyncConnection connection) async {
    await _storage.write(key: _baseUrlKey, value: connection.baseUrl);
    await _storage.write(key: _deviceTokenKey, value: connection.deviceToken);
    await _storage.write(
      key: _initialCursorKey,
      value: connection.initialCursor,
    );
    await _storage.write(key: _coreNodeIdKey, value: connection.coreNodeId);
  }

  Future<void> clear() async {
    await _storage.delete(key: _baseUrlKey);
    await _storage.delete(key: _deviceTokenKey);
    await _storage.delete(key: _initialCursorKey);
    await _storage.delete(key: _coreNodeIdKey);
  }
}
