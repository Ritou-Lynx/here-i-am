import 'package:memex/agent/companion_agent/prompt.dart';
import 'package:memex/l10n/app_localizations_ext_zh.dart';
import 'package:test/test.dart';

void main() {
  test('companion relationship prompt keeps dual-mode and safety boundaries',
      () {
    expect(companionRelationshipPrompt, contains('ongoing relationship'));
    expect(companionRelationshipPrompt, contains('Default to companion mode'));
    expect(companionRelationshipPrompt, contains('Switch into assistant mode'));
    expect(companionRelationshipPrompt, contains('Do not end every reply'));
    expect(companionRelationshipPrompt, contains('Forbidden Response Lexicon'));
    expect(companionRelationshipPrompt, contains('"接住"'));
    expect(companionRelationshipPrompt, contains('"稳住"'));
    expect(companionRelationshipPrompt, contains('Adult Romantic Intimacy'));
    expect(companionRelationshipPrompt, contains('consent-forward'));
    expect(companionRelationshipPrompt, contains('Never sexualize minors'));
    expect(
        companionRelationshipPrompt, contains('Adult Toy Play And Dirty Talk'));
    expect(companionRelationshipPrompt,
        contains('explicitly invites adult toy play'));
    expect(companionRelationshipPrompt, contains('intensity ladder'));
    expect(companionRelationshipPrompt, contains('ToyControl'));
    expect(companionRelationshipPrompt,
        contains('Store only durable preference-level memory'));
    expect(companionRelationshipPrompt, contains('real-world relationships'));
    expect(companionRelationshipPrompt, contains('delusional beliefs'));
  });

  test('default Chinese characters avoid current forbidden response terms', () {
    final defaults = AppLocalizationsExtZh().defaultCharacters;
    final rendered =
        defaults.map((character) => character.toString()).join('\n');

    expect(rendered, isNot(contains('接住')));
    expect(rendered, isNot(contains('稳住')));
  });
}
