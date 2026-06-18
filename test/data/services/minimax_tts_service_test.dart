import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/minimax_tts_service.dart';

void main() {
  group('MiniMaxTtsService.prepareTextForSpeech', () {
    test('adds MiniMax pauses without mutating the source text', () {
      const source = '\u55ef\uff0c\u6211\u77e5\u9053\u4e86\u3002'
          '\u4eca\u5929\u5148\u8fd9\u6837\u5427\uff0c'
          '\u597d\u5417\uff1f';

      final speechText = MiniMaxTtsService.prepareTextForSpeech(source);

      expect(
        source,
        '\u55ef\uff0c\u6211\u77e5\u9053\u4e86\u3002'
        '\u4eca\u5929\u5148\u8fd9\u6837\u5427\uff0c'
        '\u597d\u5417\uff1f',
      );
      expect(speechText, startsWith('<#0.20#> '));
      expect(speechText, contains('<#0.24#>'));
      expect(speechText, contains('<#0.42#>'));
      expect(speechText, contains(source.substring(0, 1)));
    });

    test('strips subtitle-only mood markup from the reading script', () {
      const source = '[gentle] \u4f60\u597d\u3010\u5c0f\u58f0\u3011'
          '\uff08\u5fc3\u91cc\u6d3b\u52a8\uff09... '
          '\u6211\u5728\u3002';

      final speechText = MiniMaxTtsService.prepareTextForSpeech(source);

      expect(speechText, isNot(contains('[gentle]')));
      expect(speechText, isNot(contains('\u5c0f\u58f0')));
      expect(speechText, isNot(contains('\u5fc3\u91cc\u6d3b\u52a8')));
      expect(speechText, contains('<#0.45#>'));
      expect(speechText, contains('\u4f60\u597d'));
      expect(speechText, contains('\u6211\u5728'));
    });

    test('uses low and slow settings for strict command scenes', () {
      const source = 'Stop. Put the phone down. I am not asking.';

      final script = MiniMaxTtsService.buildSpeechScript(source);

      expect(script.scene, MiniMaxTtsScene.strictCommand);
      expect(script.speed, 0.82);
      expect(script.vol, 1.0);
      expect(script.pitch, -4);
      expect(script.text, isNot(contains('(laughs)')));
      expect(script.text, isNot(contains('(sniffs)')));
      expect(script.text, contains('<#0.35#>'));
    });

    test('adds one sound event and fragile settings for vulnerable scenes', () {
      const source = "(sniffs) I waited so long. (sniffs) Don't laugh at me.";

      final script = MiniMaxTtsService.buildSpeechScript(source);

      expect(script.scene, MiniMaxTtsScene.vulnerable);
      expect(script.speed, 0.70);
      expect(script.vol, 0.82);
      expect(script.pitch, 2);
      expect(RegExp(r'\(sniffs\)').allMatches(script.text), hasLength(1));
      expect(script.text, contains('<#0.50#>'));
    });

    test('uses breath and low volume for flirt scenes', () {
      const source = 'Come closer. Just one more time.';

      final script = MiniMaxTtsService.buildSpeechScript(source);

      expect(script.scene, MiniMaxTtsScene.flirt);
      expect(script.speed, 0.76);
      expect(script.vol, 0.78);
      expect(script.pitch, 1);
      expect(script.text, startsWith('<#0.20#> (breath)'));
      expect(script.text, contains('<#0.45#>'));
    });
  });
}
