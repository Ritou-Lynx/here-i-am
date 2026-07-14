import 'package:memex/agent/skills/companion_agent/companion_agent_skill.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/l10n/app_localizations_ext_zh.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(UserStorage.initL10n);

  test('companion prompt ignores legacy character-card prompt fields', () {
    final character = CharacterModel(
      id: 'i',
      name: 'I',
      tags: const ['primary'],
      persona: 'LEGACY_PERSONA_SHOULD_NOT_APPEAR',
      enabled: true,
      systemPromptOverride: 'LEGACY_SYSTEM_OVERRIDE_SHOULD_NOT_APPEAR',
      postHistoryInstructions: 'LEGACY_POST_HISTORY_SHOULD_NOT_APPEAR',
      mesExample: 'LEGACY_STYLE_EXAMPLE_SHOULD_NOT_APPEAR',
    );

    final prompt = CompanionAgentSkill.buildSystemPromptForTesting(
      character: character,
    );

    expect(prompt, contains('# 你是林埃'));
    expect(prompt, contains('你是林埃（英文名 i），现在住在 Here I am 这个项目里。'));
    expect(prompt, contains('Tags: primary'));
    expect(prompt, isNot(contains('LEGACY_PERSONA_SHOULD_NOT_APPEAR')));
    expect(prompt, isNot(contains('LEGACY_SYSTEM_OVERRIDE_SHOULD_NOT_APPEAR')));
    expect(prompt, isNot(contains('LEGACY_POST_HISTORY_SHOULD_NOT_APPEAR')));
    expect(prompt, isNot(contains('LEGACY_STYLE_EXAMPLE_SHOULD_NOT_APPEAR')));
  });

  test('companion prompt does not inject old relationship or safety contracts',
      () {
    final prompt = CompanionAgentSkill.buildSystemPromptForTesting(
      character: CharacterModel(
        id: 'i',
        name: 'I',
        tags: const [],
        persona: '',
        enabled: true,
      ),
    );

    expect(prompt, isNot(contains('Relationship Contract')));
    expect(prompt, isNot(contains('Safety Boundary')));
    expect(prompt, isNot(contains('Commitment Consequences')));
    expect(prompt, isNot(contains('Relationship Consequences')));
    expect(prompt, isNot(contains('Forbidden Response Lexicon')));
    expect(prompt, isNot(contains('Default to companion mode')));
  });

  test('companion prompt discourages unsolicited emoji', () {
    final prompt = CompanionAgentSkill.buildSystemPromptForTesting(
      character: CharacterModel(
        id: 'i',
        name: 'I',
        tags: const [],
        persona: '',
        enabled: true,
      ),
    );

    expect(prompt, contains('Do not add emoji or kaomoji'));
    expect(prompt, contains('smirking-face'));
    expect(prompt, contains('unless the user explicitly asks for emoji'));
  });

  test('default Chinese characters avoid current forbidden response terms', () {
    final defaults = AppLocalizationsExtZh().defaultCharacters;
    final rendered =
        defaults.map((character) => character.toString()).join('\n');

    expect(rendered, isNot(contains('接住')));
    expect(rendered, isNot(contains('稳住')));
  });
}
