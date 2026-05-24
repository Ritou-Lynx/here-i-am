import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:memex/data/services/asr/asr_client.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/utils/logger.dart';

/// Alibaba Cloud Intelligent Speech Interaction (NLS) — one-shot file
/// recognition over REST.
///
/// Flow:
///   1. Exchange AccessKey/Secret for a short-lived `X-NLS-Token`
///      (cached in memory until ~10 min before expiry).
///   2. POST raw audio bytes to the gateway with the token + AppKey + format
///      query params; parse the JSON response.
///
/// Audio must be 16kHz mono WAV PCM (recorded by `record` package with
/// `AudioEncoder.wav`).
class AlibabaAsrClient implements AsrClient {
  static final Logger _logger = getLogger('AlibabaAsrClient');

  // Shanghai region endpoints (free tier + best Chinese coverage).
  static const String _metaEndpoint = 'https://nls-meta.cn-shanghai.aliyuncs.com/';
  static const String _gatewayEndpoint =
      'https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr';

  final AsrConfig config;

  String? _token;
  DateTime? _tokenExpiresAt;

  AlibabaAsrClient(this.config);

  @override
  Future<String> recognize(File audioFile) async {
    if (!audioFile.existsSync()) {
      throw AsrException('Audio file not found: ${audioFile.path}');
    }
    final bytes = await audioFile.readAsBytes();
    if (bytes.isEmpty) {
      throw AsrException('Audio file is empty');
    }

    final token = await _ensureToken();

    final uri = Uri.parse(_gatewayEndpoint).replace(queryParameters: {
      'appkey': config.appKey,
      'format': 'wav',
      'sample_rate': '16000',
      'enable_punctuation_prediction': 'true',
      'enable_inverse_text_normalization': 'true',
    });

    _logger.info('NLS recognize: ${bytes.length} bytes → $uri');

    final resp = await http.post(
      uri,
      headers: {
        'X-NLS-Token': token,
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (resp.statusCode != 200) {
      throw AsrException(
          'NLS HTTP ${resp.statusCode}: ${_safeBody(resp.body)}');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw AsrException('NLS returned non-JSON body: ${_safeBody(resp.body)}', e);
    }

    final status = body['status'];
    if (status != 20000000) {
      throw AsrException(
          'NLS status=$status message=${body['message']} taskId=${body['task_id']}');
    }

    final result = body['result'] as String? ?? '';
    _logger.info('NLS recognized: "${result.length > 80 ? '${result.substring(0, 80)}...' : result}"');
    return result;
  }

  /// Returns a valid token, refreshing if missing or about to expire.
  Future<String> _ensureToken() async {
    final now = DateTime.now();
    if (_token != null &&
        _tokenExpiresAt != null &&
        _tokenExpiresAt!.isAfter(now.add(const Duration(minutes: 10)))) {
      return _token!;
    }
    final (token, expiresAt) = await _createToken();
    _token = token;
    _tokenExpiresAt = expiresAt;
    return token;
  }

  /// Calls the NLS meta endpoint with an RPC-style signed GET.
  ///
  /// Reference: https://help.aliyun.com/zh/isi/getting-started/obtain-an-access-token
  Future<(String, DateTime)> _createToken() async {
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
    _logger.info('NLS token request → $_metaEndpoint');

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
      throw AsrException('NLS token response malformed: ${_safeBody(resp.body)}');
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      (expireTime as num).toInt() * 1000,
      isUtc: true,
    ).toLocal();
    _logger.info('NLS token acquired, expires=$expiresAt');
    return (id, expiresAt);
  }

  static String _safeBody(String body) =>
      body.length > 500 ? '${body.substring(0, 500)}...' : body;

  static String _nonce() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _isoUtcNow() {
    // Aliyun expects ISO8601 UTC like 2024-01-02T03:04:05Z
    final n = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}T${two(n.hour)}:${two(n.minute)}:${two(n.second)}Z';
  }

  /// Aliyun RPC-style signature.
  ///
  /// 1. Sort params lexicographically by key.
  /// 2. URL-encode each key and value (Aliyun's special variant: keep `_-~.`,
  ///    encode space as %20, encode `*` as %2A, leave `~` as `~`).
  /// 3. Join as `k1=v1&k2=v2`.
  /// 4. StringToSign = `METHOD&%2F&` + URL-encoded(step 3).
  /// 5. HMAC-SHA1 with key = `<AccessKeySecret>&`, base64-encode.
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

  /// Aliyun's URL-encoding variant (RFC 3986, with `*` encoded).
  static String _aliyunEncode(String s) {
    return Uri.encodeComponent(s)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }
}
