import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/home_turbo_tts_service.dart';

void main() {
  test('home voice guide asks for English and lists only Turbo tags', () {
    const guide = CompanionAgent.homeTurboVoiceGuide;
    expect(guide, contains('English'));
    expect(HomeTurboTtsService.hasCjk(guide), isFalse);
    final tags = RegExp(r'`\[([a-z ]+)\]')
        .allMatches(guide)
        .map((m) => m.group(1)!)
        .toSet();
    const turboTags = {
      'laugh',
      'chuckle',
      'sigh',
      'gasp',
      'cough',
      'clear throat',
      'crying',
      'sniff',
      'groan',
      'shush',
      'whispering',
      'happy',
      'angry',
      'sarcastic',
      'surprised',
      'fear',
      'dramatic',
    };
    expect(tags, isNotEmpty);
    expect(tags.difference(turboTags), isEmpty);
  });
}
