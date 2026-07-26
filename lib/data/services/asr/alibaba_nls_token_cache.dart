import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/asr/asr_client.dart';
import 'package:memex/utils/logger.dart';

/// Shared NLS access-token cache used by both file recognition and streaming
/// ASR. The token is valid for ~72h and cached until 10 min before expiry.
class AlibabaNlsTokenCache {
  AlibabaNlsTokenCache._();

  static final Logger _logger = getLogger('AlibabaNlsTokenCache');

  static const String _metaEndpoint =
      'https://nls-meta.cn-shanghai.aliyuncs.com/';

  static String? _token;
  static DateTime? _expiresAt;

  static Future<String> ensureToken(AsrConfig config) async {
    final now = DateTime.now();
    if (_token != null &&
        _expiresAt != null &&
        _expiresAt!.isAfter(now.add(const Duration(minutes: 10)))) {
      return _token!;
    }
    final (token, expiresAt) = await _createToken(config);
    _token = token;
    _expiresAt = expiresAt;
    return _token!;
  }

  static void invalidate() {
    _token = null;
    _expiresAt = null;
  }

  static Future<(String, DateTime)> _createToken(AsrConfig config) async {
    final params = <String, String>{
      'AccessKeyId': config.accessKeyId,
      'Action': 'CreateToken',
      'Format': 'JSON',
      'RegionId': 'cn-shanghai',
      'SignatureMethod': 'HMAC-SHA1',
      'SignatureNonce': _nonce(),
      'SignatureVersion': '1.0',
      'Timestamp': _isoUtcNow(),
      'Version': '2019-02-28',
    };

    final signature = _aliyunRpcSignature(
      method: 'GET',
      params: params,
      accessKeySecret: config.accessKeySecret,
    );
    params['Signature'] = signature;

    final uri = Uri.parse(_metaEndpoint).replace(queryParameters: params);
    _logger.info('NLS token request -> $_metaEndpoint');

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw AsrException(
          'NLS token HTTP ${resp.statusCode}: ${_safeBody(resp.body)}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final tokenObj = body['Token'] as Map<String, dynamic>?;
    if (tokenObj == null) {
      throw AsrException(
          'NLS token response missing Token field: ${_safeBody(resp.body)}');
    }
    final id = tokenObj['Id'] as String?;
    final expireTime = tokenObj['ExpireTime'];
    if (id == null || expireTime == null) {
      throw AsrException(
          'NLS token response malformed: ${_safeBody(resp.body)}');
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      (expireTime as num).toInt() * 1000,
      isUtc: true,
    ).toLocal();
    _logger.info('NLS token acquired, expires=$expiresAt');
    return (id, expiresAt);
  }

  static String safeBody(String body) => _safeBody(body);

  static String _safeBody(String body) =>
      body.length > 500 ? '${body.substring(0, 500)}...' : body;

  static String _nonce() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _isoUtcNow() {
    final n = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}T${two(n.hour)}:${two(n.minute)}:${two(n.second)}Z';
  }

  static String _aliyunRpcSignature({
    required String method,
    required Map<String, String> params,
    required String accessKeySecret,
  }) {
    final sortedKeys = params.keys.toList()..sort();
    final canonical = sortedKeys
        .map((k) => '${_aliyunEncode(k)}=${_aliyunEncode(params[k]!)}')
        .join('&');
    final stringToSign =
        '$method&${_aliyunEncode('/')}&${_aliyunEncode(canonical)}';
    final hmac = Hmac(sha1, utf8.encode('$accessKeySecret&'));
    final digest = hmac.convert(utf8.encode(stringToSign));
    return base64.encode(digest.bytes);
  }

  static String _aliyunEncode(String s) {
    return Uri.encodeComponent(s)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }
}
