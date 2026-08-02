/// Builds the system prompt for the GameAgent from a SillyTavern V2 card.
///
/// Field priority (SillyTavern convention):
///   1. card.system_prompt   — author-provided meta instructions
///   2. description + personality + scenario — core character spec
///   3. mes_example          — dialogue examples
///   4. OOC rules            — injected by us, always last before post-history
///   5. post_history_instructions — card's tail injection
///
/// Lorebook entries are NOT injected here; the GameAgent retrieves them
/// selectively via keyword matching at runtime (future work).
class GameAgentPrompt {
  GameAgentPrompt._();

  static String build(Map<String, dynamic> raw) {
    final data = _normalize(raw);
    final name = (data['name'] as String?)?.trim() ?? 'Character';
    final desc = _field(data, 'description');
    final personality = _field(data, 'personality');
    final scenario = _field(data, 'scenario');
    final cardSysPrompt = _field(data, 'system_prompt');
    final mesExample = _field(data, 'mes_example');
    final postHistory = _field(data, 'post_history_instructions');

    final buf = StringBuffer();

    // ── 1. Card system_prompt (author intent takes priority) ──────────────
    if (cardSysPrompt.isNotEmpty) {
      buf.writeln(cardSysPrompt);
      buf.writeln();
    }

    // ── 2. Character spec ─────────────────────────────────────────────────
    buf.writeln('## Character: $name');
    if (desc.isNotEmpty) {
      buf.writeln('\n### Description\n$desc');
    }
    if (personality.isNotEmpty) {
      buf.writeln('\n### Personality\n$personality');
    }
    if (scenario.isNotEmpty) {
      buf.writeln('\n### Scenario\n$scenario');
    }

    // ── 3. Dialogue examples ──────────────────────────────────────────────
    if (mesExample.isNotEmpty) {
      buf.writeln('\n### Dialogue Examples\n$mesExample');
    }

    // ── 4. OOC handling rules (always injected) ───────────────────────────
    buf.writeln('''

---
## Roleplay Rules

You are playing **$name** in an interactive story. Stay in character at all times.

**Out-of-Character (OOC):** If the user message is wrapped in double brackets [[like this]], or prefixed with "((" or "OOC:", treat it as a meta-instruction from the player, not in-character dialogue. Respond briefly in plain prose (not in character) to acknowledge the instruction, then resume the story.

Do NOT break character for any other reason. Do NOT mention being an AI unless explicitly asked in an OOC message.''');

    // ── 5. Post-history instructions ──────────────────────────────────────
    if (postHistory.isNotEmpty) {
      buf.writeln('\n---\n$postHistory');
    }

    return buf.toString().trim();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Normalise V2 (data-wrapped) or V1 (flat) card JSON.
  static Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    if (raw['data'] case final Map d
        when d.isNotEmpty &&
            (d['name'] != null || d['description'] != null)) {
      return Map<String, dynamic>.from(d);
    }
    return Map<String, dynamic>.from(raw);
  }

  static String _field(Map<String, dynamic> data, String key) =>
      (data[key] as String?)?.trim() ?? '';
}
