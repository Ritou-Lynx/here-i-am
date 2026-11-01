import 'package:memex/data/services/elevenlabs_tts_service.dart';
import 'package:memex/data/services/home_turbo_tts_service.dart';
import 'package:memex/data/services/minimax_tts_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/utils/user_storage.dart';

class TtsService {
  /// 家里电脑上的林埃英文声音（tools/linai_tts）。失败时这一句改用 MiniMax，
  /// voiceId 传的是 MiniMax 的 voice id（见 UserStorage.getActiveTtsVoiceId）。
  static const homeTurboProvider = 'home_turbo';

  static Future<String> textToSpeech({
    required String text,
    required String voiceId,
  }) async {
    final speechText = PersonaReplySanitizer.spokenTextOnly(text);
    final provider = await UserStorage.getTtsProvider();
    if (provider == homeTurboProvider) {
      final path = await HomeTurboTtsService.trySynthesizeToFile(speechText);
      if (path != null) return path;
      return MiniMaxTtsService.textToSpeech(text: speechText, voiceId: voiceId);
    }
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
    if (provider == homeTurboProvider) {
      final audio = await HomeTurboTtsService.trySynthesize(speechText);
      if (audio != null) {
        yield audio;
        return;
      }
      yield* MiniMaxTtsService.streamTextToSpeech(
        text: speechText,
        voiceId: voiceId,
      );
    } else if (provider == 'minimax') {
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
    await HomeTurboTtsService.clearCache();
  }

  /// 语音会话（通话、耳机键、聊天语音模式）开始时调用：当前是家里电脑声音就先体检，
  /// 不可用则整段会话直接用 MiniMax。不阻塞调用方。
  static Future<void> prepareForVoiceSession() async {
    final provider = await UserStorage.getTtsProvider();
    if (provider != homeTurboProvider) return;
    await HomeTurboTtsService.prepareForSession();
  }
}
