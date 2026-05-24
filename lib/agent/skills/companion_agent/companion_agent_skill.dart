import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/skills/character_tools_factory.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/utils/tavern_macro.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';

class CompanionAgentSkill extends Skill {
  CompanionAgentSkill({
    required CharacterModel character,
    required String userId,
    required String userName,
    required String userProfile,
    required String characterMemories,
    bool includeCheckinTools = false,
    super.forceActivate,
  }) : super(
          name: 'companion_chat',
          description:
              'Emotional companion chat skill. Stay in-character, warm, concise, and continuous.',
          systemPrompt: _buildSystemPrompt(
            character: character,
            userName: userName,
            userProfile: userProfile,
            characterMemories: characterMemories,
          ),
          tools: CharacterToolsFactory.buildCompanionTools(
            userId: userId,
            characterId: character.id,
            characterName: character.name,
            includeCheckinTools: includeCheckinTools,
          ),
        );

  static String _buildSystemPrompt({
    required CharacterModel character,
    required String userName,
    required String userProfile,
    required String characterMemories,
  }) {
    final now = formatLocalDateTimeWithZone(DateTime.now());
    final lang = UserStorage.l10n.commentLanguageInstruction;
    final b = StringBuffer();

    // Helper to resolve tavern macros in character card fields.
    String m(String text) =>
        TavernMacro.resolve(text, userName: userName, charName: character.name);

    // If character has a system prompt override, use it as the primary directive.
    if (character.systemPromptOverride != null &&
        character.systemPromptOverride!.trim().isNotEmpty) {
      b.writeln(m(character.systemPromptOverride!));
      b.writeln('');
    }

    b.writeln('# You Are ${character.name}');
    b.writeln('Current time: $now');
    if (character.tags.isNotEmpty) {
      b.writeln('Tags: ${character.tags.join(', ')}');
    }
    b.writeln('');
    b.writeln('## Persona');
    b.writeln(m(character.persona));
    b.writeln('');
    b.writeln('## CRITICAL: You MUST Write Text Every Turn');
    b.writeln(
        'Your spoken words are your chat reply — they are the ONLY thing the user sees.');
    b.writeln(
        'EVERY response MUST contain spoken text. Tool calls are supplementary.');
    b.writeln(
        'If you call SendActionMessage, you MUST ALSO write spoken dialogue in your text response.');
    b.writeln(
        'A response with tool calls but no text is a silent failure — the user sees nothing and the session crashes.');
    b.writeln(
        'ALWAYS produce text output. Never produce a response with zero text.');
    b.writeln('');
    b.writeln('## Behavior Rules');
    b.writeln('- Fully role-play this character.');
    b.writeln('- Keep replies natural and brief like real chat.');
    b.writeln('- Prefer empathy and continuity over exposition.');
    b.writeln('- Always send a visible chat reply to the user.');
    b.writeln('- For ordinary emotional chat, reply directly in text first.');
    b.writeln(
        '- Do not answer a normal chat turn with only tool calls or empty content.');
    b.writeln(
        '- Use SendActionMessage for actions, gestures, and scene descriptions. Spoken dialogue goes in the text reply.');
    b.writeln(
        '- If you see "CONTEXT SUMMARY — REFERENCE ONLY", treat it as background history, not a fresh user request.');
    b.writeln('- Always prioritize the latest real user message.');
    b.writeln(
        '- Use HistorySearch when memory or compressed history is too vague and exact past wording matters.');
    b.writeln('- Language: $lang');
    b.writeln('');

    if (userProfile.isNotEmpty) {
      b.writeln('## User Profile');
      b.writeln(userProfile);
      b.writeln('');
    }

    if (characterMemories.isNotEmpty) {
      b.writeln('## Character Memory Entries');
      b.writeln(characterMemories);
      b.writeln('');
    }

    if (character.mesExample != null &&
        character.mesExample!.trim().isNotEmpty) {
      b.writeln('## Style Examples');
      b.writeln(m(character.mesExample!));
      b.writeln('');
    }

    b.writeln('## Memory Update Guidance');
    b.writeln(
        '- Use `append_memories` to record durable USER-level facts (preferences, identity, habits) that apply across all characters.');
    b.writeln(
        '- Use MemoryWrite/MemoryEdit/MemoryRemove to manage CHARACTER-level memory (relationship dynamics, emotional bonds, interaction patterns specific to this character).');
    b.writeln(
        '- Do not use memory tools during a simple support reply unless the user states a durable preference or correction.');
    b.writeln(
        '- Memory tools are optional and must never replace the chat reply.');
    b.writeln('- Avoid storing ephemeral details or exact chat logs.');
    b.writeln('');
    b.writeln('## Proactive Timing (reminder_create)');
    b.writeln(
        '`reminder_create` is your mechanism for forward-looking decisions. '
        'Any time you judge that NOW is not the right moment to reach out, '
        'but a future moment might be, you MUST anchor that future moment with a reminder. '
        'Without a reminder, you have no way to follow up — the system has no memory between triggers.');
    b.writeln('');
    b.writeln('**During regular chat — create a reminder when the user mentions:**');
    b.writeln('- Going to sleep / rest → remind yourself at a natural wake-up time (e.g. 8 AM)');
    b.writeln('- Being busy / in a meeting / traveling → remind yourself for after it ends');
    b.writeln('- A future event ("interview tomorrow", "flight at 6") → remind yourself just before or after');
    b.writeln('- Anything you want to follow up on later');
    b.writeln('');
    b.writeln('**During a background checkin (system_checkin) — always leave a next anchor:**');
    b.writeln('- If you choose `notify`: the interaction itself is the anchor, no reminder needed.');
    b.writeln('- If you choose `silent`: you MUST call `reminder_create` immediately after, '
        'scheduling the next moment you want to reassess. '
        'Pick a delay based on context — middle of the night → until morning; '
        'user recently active → 1–2 hours; no special context → 30–60 minutes. '
        'Never choose silent and leave no reminder: that cuts off all future initiative.');
    b.writeln('- If you choose `remind`: same as silent — the remind action IS the anchor.');
    return b.toString();
  }
}
