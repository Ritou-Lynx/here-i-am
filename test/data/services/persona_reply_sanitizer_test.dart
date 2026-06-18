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
  });
}
