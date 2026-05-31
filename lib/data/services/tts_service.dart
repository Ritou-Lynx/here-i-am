import 'package:memex/data/services/elevenlabs_tts_service.dart';
import 'package:memex/data/services/minimax_tts_service.dart';
import 'package:memex/utils/user_storage.dart';

/// Routes TTS requests to the configured provider (elevenlabs / minimax).
class TtsService {
  static Future<String> textToSpeech({
    required String text,
    required String voiceId,
  }) async {
    final provider = await UserStorage.getTtsProvider();
    if (provider == 'minimax') {
      return MiniMaxTtsService.textToSpeech(text: text, voiceId: voiceId);
    }
    return ElevenLabsTtsService.textToSpeech(text: text, voiceId: voiceId);
  }

  static Future<void> clearCache() async {
    await ElevenLabsTtsService.clearCache();
    await MiniMaxTtsService.clearCache();
  }
}
