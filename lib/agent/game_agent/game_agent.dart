import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/game_agent/prompt.dart';
import 'package:memex/agent/game_agent/turtle_soup_prompt.dart';
import 'package:memex/agent/state_util.dart';
import 'package:memex/data/services/game/turtle_soup_catalog.dart';
import 'package:memex/db/app_database.dart';

final _log = Logger('GameAgent');

/// The GameAgent drives interactive game sessions.
///
/// Currently supports gameType = 'card_roleplay' (SillyTavern-style character
/// cards). Future game types will extend this service with different prompt
/// builders for each game type.
///
/// Isolation contract (enforced here):
///   • Context = game definition config + this session's messages only.
///   • No User-truth tools, no Memory V3 tools, no companion tools.
///   • No AgentState persistence — history lives in [GameMessages] managed
///     by [GameSessionService].
///
/// OOC (Out Of Character) messages:
///   User messages with [isOoc] = true are wrapped in [[double brackets]]
///   before being sent to the model. The prompt instructs the model to treat
///   bracketed messages as meta-instructions and respond out-of-character.
class GameAgent {
  GameAgent._();

  /// Stream one reply turn.
  ///
  /// [history]     — all existing [GameMessage] rows for this session, in
  ///                 chronological order. The caller must have already
  ///                 persisted the new user message to the DB; it is passed
  ///                 separately as [userMessage] so the agent knows what to
  ///                 reply to.
  /// [userMessage] — the new user message content (not yet in [history]).
  /// [isOoc]       — wrap [userMessage] in OOC brackets before sending.
  ///
  /// The stream emits the full assistant reply as a single chunk (non-
  /// streaming LLM call, same pattern as [CompanionAgent.chat]).
  static Stream<String> chat({
    required LLMClient client,
    required ModelConfig modelConfig,
    required GameSession session,
    required List<GameMessage> history,
    required String userMessage,
    bool isOoc = false,
  }) async* {
    // ── Build a fresh ephemeral AgentState from game history ──────────────
    // Use a unique, non-persistent session ID so no state is written to disk.
    final ephemeralId =
        'game_${session.id}_${DateTime.now().microsecondsSinceEpoch}';
    final state = await loadOrCreateAgentState(ephemeralId, {
      'scene': 'game',
      'gameSessionId': session.id,
    });

    // Replay game history into the agent state's message list.
    // Skip system rows (save_markers) — they are DB metadata, not LLM turns.
    for (final msg in history) {
      if (msg.role == 'system') continue;
      final content = (msg.messageType == 'ooc' && msg.role == 'user')
          ? '[[OOC: ${msg.content}]]'
          : msg.content;
      if (msg.role == 'user') {
        state.history.messages.add(UserMessage.text(content));
      } else {
        state.history.messages
            .add(ModelMessage(model: 'game_history', textOutput: content));
      }
    }

    // ── Build system prompt from definition snapshot ────────────────────────
    // For gameType != 'card_roleplay', a different prompt builder will be used.
    final definitionData = _parseDefinition(session.definitionSnapshotJson);
    final systemPrompt = _buildPrompt(session.gameType, definitionData);

    // ── Create isolated StatefulAgent (no tools, no auto-save) ────────────
    final agent = StatefulAgent(
      name: 'game_agent',
      client: client,
      modelConfig: modelConfig,
      state: state,
      skills: const [],
      tools: const [],
      systemPrompts: [systemPrompt],
      disableSubAgents: true,
      withGeneralPrinciples: false,
      planMode: PlanMode.none,
      autoSaveStateFunc: null, // never persist to disk
    );

    // ── Run one turn ──────────────────────────────────────────────────────
    final sendContent = isOoc ? '[[OOC: $userMessage]]' : userMessage;
    _log.fine('GameAgent: running turn for session ${session.id}');

    try {
      final resultHistory = await agent.run(
        [UserMessage.text(sendContent)],
        useStream: false,
      );

      // Extract the assistant's reply text (same scan as CompanionAgent).
      String reply = '';
      for (final msg in resultHistory.reversed) {
        if (msg is ModelMessage) {
          final t = msg.textOutput ?? '';
          if (t.trim().isNotEmpty) {
            reply = t;
            break;
          }
        }
      }

      if (reply.isNotEmpty) {
        yield session.gameType == 'turtle_soup'
            ? TurtleSoupPrompt.normalizeVerdict(reply)
            : reply;
      } else {
        _log.warning('GameAgent: empty reply for session ${session.id}');
      }
    } catch (e, st) {
      _log.severe('GameAgent: error during run', e, st);
      rethrow;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _parseDefinition(String definitionSnapshotJson) {
    try {
      final obj = jsonDecode(definitionSnapshotJson);
      if (obj is Map) return Map<String, dynamic>.from(obj);
    } catch (_) {}
    return const {};
  }

  /// Dispatch to the appropriate prompt builder based on gameType.
  /// Future game types will add their own prompt builders here.
  static String _buildPrompt(String gameType, Map<String, dynamic> definitionData) {
    switch (gameType) {
      case 'card_roleplay':
        return GameAgentPrompt.build(definitionData);
      case 'turtle_soup':
        return TurtleSoupPrompt.build(
          TurtleSoupPuzzle.fromJson(definitionData),
        );
      default:
        // Fallback: return raw definition or a generic prompt.
        return 'You are in a game session. ${definitionData['description'] ?? ''}';
    }
  }
}
