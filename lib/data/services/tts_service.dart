import 'package:memex/data/services/elevenlabs_tts_service.dart';
import 'package:memex/data/services/minimax_tts_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/utils/user_storage.dart';

/// Routes TTS requests to the configured provider (elevenlabs / minimax).
class TtsService {
  static Future<String> textToSpeech({
    required String text,
    required String voiceId,
  }) async {
    final speechText = PersonaReplySanitizer.spokenTextOnly(text);
    final provider = await UserStorage.getTtsProvider();
    if (provider == 'minimax') {
      return MiniMaxTtsService.textToSpeech(
        text: speechText,
        voiceId: voiceId,
      );
    }
    return ElevenLabsTtsService.textToSpeech(
        text: speechText, voiceId: voiceId);
  }

  static Future<void> clearCache() async {
    await ElevenLabsTtsService.clearCache();
    await MiniMaxTtsService.clearCache();
  }
}
