import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class ElevenLabsTtsService {
  static const _baseUrl = 'https://api.elevenlabs.io';
  static const _modelId = 'eleven_v3';
  static final _log = getLogger('ElevenLabsTts');

  /// Generate speech for [text] using [voiceId]. Returns path to local audio file.
  /// Caches results by text+voiceId hash so repeated requests hit disk.
  /// Throws [Exception] with a descriptive message on failure.
  static Future<String> textToSpeech({
    required String text,
    required String voiceId,
  }) async {
    if (text.trim().isEmpty) throw Exception('Text is empty');
    final speechText = _prepareTextForSpeech(text);

    final apiKey = await UserStorage.getElevenLabsApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('ElevenLabs API Key 未配置，请在 Settings 中设置');
    }

    final cacheKey = _cacheKey(speechText, voiceId);
    final cachePath = await _cachePath(cacheKey);

    if (await File(cachePath).exists()) {
      _log.fine('TTS cache hit: $cacheKey');
      return cachePath;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/v1/text-to-speech/$voiceId'),
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': speechText,
        'model_id': _modelId,
        'voice_settings': {
          // Stability low (Creative end) lets pitch/pace/breath vary naturally
          // per the voice-test plan v1 + ELevenlabs-TTS.md guidance.
          // Style high to carry emotional intensity. Speaker boost keeps the
          // voice anchored to the base timbre without over-rigid cloning.
          'stability': 0.25,
          'similarity_boost': 0.75,
          'style': 0.84,
          'use_speaker_boost': true,
        },
      }),
    );

    if (response.statusCode == 200) {
      final file = File(cachePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      _log.info(
          'TTS generated: $cacheKey (${response.bodyBytes.length} bytes)');
      return cachePath;
    } else {
      String detail;
      try {
        final body = jsonDecode(response.body);
        detail = body['detail']?['message'] ?? response.body;
      } catch (_) {
        detail = response.body;
      }
      throw Exception('API 错误 ${response.statusCode}: $detail');
    }
  }

  static String _prepareTextForSpeech(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return normalized;

    // Eleven v3 understands pause audio tags rather than SSML <break>. A small
    // lead-in and sentence pause prevents Chinese onsets from being swallowed
    // at generation/playback boundaries.
    final withSentencePauses = normalized.replaceAllMapped(
      RegExp(r'([。！？!?；;])\s*'),
      (match) => '${match.group(1)} [short pause] ',
    );

    // If the text already opens with a TTS audio tag (e.g. [softly]),
    // prepending [short pause] would stack two tags and dilute the opening
    // emotion. Let the character's opening tag lead.
    if (RegExp(r'^\s*\[[^\]]+\]').hasMatch(withSentencePauses)) {
      return withSentencePauses.trim();
    }
    return '[short pause] $withSentencePauses'.trim();
  }

  static String _cacheKey(String text, String voiceId) {
    final bytes = utf8.encode('$_modelId:$voiceId:$text');
    return sha256.convert(bytes).toString();
  }

  static Future<String> _cachePath(String cacheKey) async {
    final dir = await FileSystemService.getAppSupportDir();
    return '${dir.path}/tts_cache/$cacheKey.mp3';
  }

  /// Remove all cached TTS audio files.
  static Future<void> clearCache() async {
    final dir = await FileSystemService.getAppSupportDir();
    final cacheDir = Directory('${dir.path}/tts_cache');
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      _log.info('TTS cache cleared');
    }
  }
}
