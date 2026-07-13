import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';

void main() {
  group('PersonaReplySanitizer', () {
    test('splits leading roleplay action from spoken text', () {
      const source = '*\u5979\u8f7b\u8f7b\u504f\u8fc7\u5934,'
          '\u770b\u7740\u4f60\u3002* \u6211\u5728\u5462\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(2));
      expect(segments[0].type, PersonaReplySegmentType.action);
      expect(
        segments[0].text,
        '*\u5979\u8f7b\u8f7b\u504f\u8fc7\u5934,'
        '\u770b\u7740\u4f60\u3002*',
      );
      expect(segments[1].type, PersonaReplySegmentType.chat);
      expect(segments[1].text, '\u6211\u5728\u5462\u3002');
    });

    test('keeps non-action emphasis in spoken text', () {
      const source = '*\u771f\u7684* '
          '\u4e0d\u9700\u8981\u73b0\u5728\u5c31\u6491\u4f4f\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(1));
      expect(segments.single.type, PersonaReplySegmentType.chat);
      expect(segments.single.text, source);
    });

    test('splits action and speech without whitespace between them', () {
      const source = '*she smiles softly*I am here.';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(2));
      expect(segments[0].type, PersonaReplySegmentType.action);
      expect(segments[0].text, '*she smiles softly*');
      expect(segments[1].type, PersonaReplySegmentType.chat);
      expect(segments[1].text, 'I am here.');
    });

    test('splits inline roleplay action out of a chat line', () {
      const source = '\u6211\u5728\u8fd9\u91cc\u3002'
          '*\u5979\u4f4e\u5934\u7b11\u4e86\u4e00\u4e0b*'
          '\u522b\u6015\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(3));
      expect(segments[0].type, PersonaReplySegmentType.chat);
      expect(segments[0].text, '\u6211\u5728\u8fd9\u91cc\u3002');
      expect(segments[1].type, PersonaReplySegmentType.action);
      expect(
        segments[1].text,
        '*\u5979\u4f4e\u5934\u7b11\u4e86\u4e00\u4e0b*',
      );
      expect(segments[2].type, PersonaReplySegmentType.chat);
      expect(segments[2].text, '\u522b\u6015\u3002');
    });

    test('keeps inline non-action emphasis inside chat text', () {
      const source = '\u6211 *\u771f\u7684* \u5728\u8fd9\u91cc\u3002';

      final segments = PersonaReplySanitizer.splitVisibleReply(source);

      expect(segments, hasLength(1));
      expect(segments.single.type, PersonaReplySegmentType.chat);
      expect(segments.single.text, source);
    });

    test('splits chat text into message-sized bubbles', () {
      const source = '\u6211\u5728\u8fd9\u91cc\u3002'
          '\u522b\u6015\uff0c\u6211\u4e0d\u4f1a\u8d70\u3002';

      final bubbles = PersonaReplySanitizer.splitChatIntoBubbles(source);

      expect(bubbles, [
        '\u6211\u5728\u8fd9\u91cc\u3002',
        '\u522b\u6015\uff0c\u6211\u4e0d\u4f1a\u8d70\u3002',
      ]);
    });

    test('keeps markdown links in one bubble', () {
      const source =
          'Read [the note](https://example.com). Then tell me what you think.';

      final bubbles = PersonaReplySanitizer.splitChatIntoBubbles(source);

      expect(bubbles, [source]);
    });

    test('caps bubble count without crushing English spacing', () {
      const source = 'First. Second. Third.';

      final bubbles = PersonaReplySanitizer.splitChatIntoBubbles(
        source,
        maxBubbles: 2,
      );

      expect(bubbles, ['First.', 'Second. Third.']);
    });

    test('spokenTextOnly removes action and leaked thinking blocks', () {
      const source = '''
<thinking>The user is upset. I should comfort them.</thinking>
*she leans closer and lowers her voice*
I am here.
''';

      final spoken = PersonaReplySanitizer.spokenTextOnly(source);

      expect(spoken, 'I am here.');
    });

    test('spokenTextOnly returns empty for action-only text', () {
      const source = '*she nods quietly*';

      final spoken = PersonaReplySanitizer.spokenTextOnly(source);

      expect(spoken, isEmpty);
    });

    test('strips English response planning leaked as visible text', () {
      const source = '''
The user's frustrated because their mentor's supervisor just handed them a task when they were planning to rest. I should acknowledge that frustration without being patronizing, then figure out whether it is urgent.
*sighs softly*
Tell me what the task is first.
''';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, '*sighs softly*\nTell me what the task is first.');
    });

    test('strips Chinese identity and response planning leaks', () {
      const source = '''
我意识到用户是林埃和梨糖之间的对话，我需要用中文以林埃的身份自然地回应。
她刚才提到吃完饭在走路，对自己的UI设计即将成型感到兴奋，我应该表现出对她进展的真诚关注。
*坐直了一点。*
哦？说来听听。
''';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, '*坐直了一点。*\n哦？说来听听。');
    });

    test('keeps ordinary first-person character dialogue', () {
      const source = '我应该早点告诉你的。现在先说说是什么任务？';

      final cleaned = PersonaReplySanitizer.stripLeakedReasoning(source);

      expect(cleaned, source);
    });
  });
}
