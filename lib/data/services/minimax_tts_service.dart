import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class MiniMaxTtsService {
  static const _baseUrl = 'https://api.minimax.chat';
  static const _model = 'speech-2.8-hd';
  static final _log = getLogger('MiniMaxTts');

  /// Generate speech for [text] using [voiceId]. Returns path to local audio file.
  /// Caches results by text+voiceId hash. Throws [Exception] on failure.
  static Future<String> textToSpeech({
    required String text,
    required String voiceId,
  }) async {
    if (text.trim().isEmpty) throw Exception('Text is empty');

    final apiKey = await UserStorage.getMiniMaxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('MiniMax API Key 未配置，请在 Settings 中设置');
    }
    final groupId = await UserStorage.getMiniMaxGroupId();
    if (groupId == null || groupId.isEmpty) {
      throw Exception('MiniMax Group ID 未配置，请在 Settings 中设置');
    }

    final cacheKey = _cacheKey(text, voiceId);
    final cachePath = await _cachePath(cacheKey);

    if (await File(cachePath).exists()) {
      _log.fine('TTS cache hit: $cacheKey');
      return cachePath;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/v1/t2a_v2?GroupId=$groupId'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'text': text,
        'stream': false,
        'voice_setting': {
          'voice_id': voiceId,
          'speed': 1.0,
          'vol': 1.0,
          'pitch': 0,
        },
        'audio_setting': {
          'sample_rate': 32000,
          'bitrate': 128000,
          'format': 'mp3',
          'channel': 1,
        },
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final statusCode = body['base_resp']?['status_code'];
      if (statusCode != 0) {
        final msg = body['base_resp']?['status_msg'] ?? 'unknown error';
        throw Exception('MiniMax API 错误: $msg');
      }
      // audio field is hex-encoded MP3
      final audioHex = body['data']?['audio'] as String?;
      if (audioHex == null || audioHex.isEmpty) {
        throw Exception('未收到音频数据');
      }
      final audioBytes = _hexDecode(audioHex);
      final file = File(cachePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(audioBytes);
      _log.info('TTS generated: $cacheKey (${audioBytes.length} bytes)');
      return cachePath;
    } else {
      String detail;
      try {
        final body = jsonDecode(response.body);
        detail = body['base_resp']?['status_msg'] ?? response.body;
      } catch (_) {
        detail = response.body;
      }
      throw Exception('API 错误 ${response.statusCode}: $detail');
    }
  }

  static List<int> _hexDecode(String hex) {
    final result = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static String _cacheKey(String text, String voiceId) {
    final bytes = utf8.encode('$_model:$voiceId:$text');
    return sha256.convert(bytes).toString();
  }

  static Future<String> _cachePath(String cacheKey) async {
    final dir = await FileSystemService.getAppSupportDir();
    return '${dir.path}/tts_cache_minimax/$cacheKey.mp3';
  }

  static Future<void> clearCache() async {
    final dir = await FileSystemService.getAppSupportDir();
    final cacheDir = Directory('${dir.path}/tts_cache_minimax');
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      _log.info('TTS cache cleared');
    }
  }
}
