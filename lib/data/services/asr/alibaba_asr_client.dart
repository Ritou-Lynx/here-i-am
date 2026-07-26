import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:memex/data/services/asr/alibaba_nls_token_cache.dart';
import 'package:memex/data/services/asr/asr_client.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/utils/logger.dart';

/// Alibaba Cloud Intelligent Speech Interaction (NLS) - one-shot file
/// recognition over REST.
///
/// Flow:
///   1. Obtain a short-lived `X-NLS-Token` via [AlibabaNlsTokenCache] (shared
///      with the streaming ASR client, cached until ~10 min before expiry).
///   2. POST raw audio bytes to the gateway with the token + AppKey + format
///      query params; parse the JSON response.
///
/// Audio must be 16kHz mono WAV PCM (recorded by `record` package with
/// `AudioEncoder.wav`).
class AlibabaAsrClient implements AsrClient {
  static final Logger _logger = getLogger('AlibabaAsrClient');

  static const String _gatewayEndpoint =
      'https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr';

  final AsrConfig config;

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

    final token = await AlibabaNlsTokenCache.ensureToken(config);

    final uri = Uri.parse(_gatewayEndpoint).replace(queryParameters: {
      'appkey': config.appKey,
      'format': 'wav',
      'sample_rate': '16000',
      'enable_punctuation_prediction': 'true',
      'enable_inverse_text_normalization': 'true',
    });

    _logger.info('NLS recognize: ${bytes.length} bytes -> $uri');

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
          'NLS HTTP ${resp.statusCode}: ${AlibabaNlsTokenCache.safeBody(resp.body)}');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw AsrException(
          'NLS returned non-JSON body: ${AlibabaNlsTokenCache.safeBody(resp.body)}',
          e);
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
}
