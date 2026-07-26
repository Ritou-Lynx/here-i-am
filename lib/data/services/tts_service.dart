import 'package:memex/data/services/elevenlabs_tts_service.dart';
import 'package:memex/data/services/minimax_tts_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/utils/user_storage.dart';

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

  static Stream<List<int>> streamTextToSpeech({
    required String text,
    required String voiceId,
  }) {
    return _streamDispatch(text: text, voiceId: voiceId);
  }

  static Stream<List<int>> _streamDispatch({
    required String text,
    required String voiceId,
  }) async* {
    final speechText = PersonaReplySanitizer.spokenTextOnly(text);
    final provider = await UserStorage.getTtsProvider();
    if (provider == 'minimax') {
      yield* MiniMaxTtsService.streamTextToSpeech(
        text: speechText,
        voiceId: voiceId,
      );
    } else {
      yield* ElevenLabsTtsService.streamTextToSpeech(
        text: speechText,
        voiceId: voiceId,
      );
    }
  }

  static Future<void> clearCache() async {
    await ElevenLabsTtsService.clearCache();
    await MiniMaxTtsService.clearCache();
  }
}
