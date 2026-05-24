import 'dart:async';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/companion_agent/recent_activity_snapshot.dart';
import 'package:memex/agent/context/character_context_assembler.dart';
import 'package:memex/agent/memory/character_context_compressor.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/agent/skills/companion_agent/companion_agent_skill.dart';
import 'package:memex/agent/state_util.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/agent/agent_system_prompt_helper.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/tavern_macro.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';

/// Companion chat agent implemented with StatefulAgent for architecture parity
/// with other scene agents (e.g., CommentAgent).
class CompanionAgent {
  static final Logger _logger = getLogger('CompanionAgent');

  static Future<StatefulAgent?> _createAgent({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String queryHint,
    bool saveState = true,
    bool includeCheckinTools = false,
  }) async {
    final character =
        await CharacterService.instance.getCharacter(userId, characterId);
    if (character == null) {
      return null;
    }

    final sessionPrefix = 'companion_${userId}_$characterId';
    final resolved = await resolveCharacterSessionId(
      prefix: sessionPrefix,
      userId: userId,
    );
    final state = await loadOrCreateAgentState(resolved.sessionId, {
      'userId': userId,
      'scene': 'companion_chat',
      'characterId': characterId,
    });

    final ctx = await CharacterContextAssembler.build(
      userId: userId,
      character: character,
      sourceAgent: 'companion_agent',
      queryHint: queryHint,
      excludeTrailingUserMessage: true,
    );

    final userName = (await UserStorage.getUserId()) ?? userId;

    final skill = CompanionAgentSkill(
      character: character,
      userId: userId,
      userName: userName,
      userProfile: ctx.userProfile,
      characterMemories: ctx.characterMemories,
      includeCheckinTools: includeCheckinTools,
      forceActivate: true,
    );

    // World, timeline, and knowledge go into systemReminders (refreshable context).
    if (ctx.characterWorld.isNotEmpty) {
      state.systemReminders['character_world'] =
          '## Triggered Character World Entries\n${TavernMacro.resolve(ctx.characterWorld, userName: userName, charName: character.name)}';
    }
    // Combine compaction checkpoints + recent timeline into one reminder.
    {
      final parts = <String>[];
      if (ctx.checkpoints.isNotEmpty) {
        parts.add('## Compressed Interaction History\n${ctx.checkpoints}');
      }
      if (ctx.recentTimeline.isNotEmpty) {
        parts.add('## Recent Cross-Scene Interactions\n${ctx.recentTimeline}');
      }
      if (parts.isNotEmpty) {
        state.systemReminders['character_timeline'] = parts.join('\n\n');
      }
    }
    if (ctx.knowledgeCards.isNotEmpty) {
      state.systemReminders['user_knowledge_cards'] =
          '## User Knowledge Cards\n${ctx.knowledgeCards}';
    }
    if (character.postHistoryInstructions != null &&
        character.postHistoryInstructions!.trim().isNotEmpty) {
      state.systemReminders['post_history_instructions'] = TavernMacro.resolve(
        character.postHistoryInstructions!,
        userName: userName,
        charName: character.name,
      );
    }

    final controller = AgentController();
    addAgentLogger(controller);
    addAgentActivityCollector(controller);

    // User-level memory management (append_memories tool)
    final memoryManagement = await MemoryManagement.createDefault(
      userId: userId,
      sourceAgent: 'companion_agent',
    );
    final memoryManagementPrompt =
        await memoryManagement.buildMemoryManagementPrompt();

    return StatefulAgent(
      name: 'companion_agent',
      client: client,
      modelConfig: modelConfig,
      state: state,
      skills: [skill],
      tools: memoryManagement.buildMemoryManagementTools(),
      systemPrompts: [memoryManagementPrompt],
      disableSubAgents: true,
      controller: controller,
      withGeneralPrinciples: true,
      planMode: PlanMode.none,
      // Companion chat is a long-running relationship conversation. The
      // default LLM loop diagnosis becomes too aggressive after many turns and
      // can interrupt a valid reply before tools finish. Keep deterministic
      // repeated-tool protection, but disable the extra LLM judge.
      loopDetector: DefaultLoopDetector(state: state),
      autoSaveStateFunc: saveState ? (s) async => saveAgentState(s) : null,
      systemCallback: createSystemCallback(userId),
    );
  }

  /// Run a background checkin without polluting chat history.
  ///
  /// Called from the WorkManager background isolate. Creates the agent with
  /// [saveState] = false so the trigger exchange is never written to chat history.
  static Future<void> runBackgroundCheckin({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
  }) async {
    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: '',
      saveState: false,
      includeCheckinTools: true,
    );
    if (agent == null) {
      _logger
          .warning('runBackgroundCheckin: character not found ($characterId)');
      return;
    }

    final checkinIds = await _drainPendingCheckinsIntoState(agent.state);
    if (checkinIds.isEmpty) {
      _logger.info('runBackgroundCheckin: no pending checkins, skipping');
      return;
    }

    // Build a fresh snapshot of the user's recent activity. This bypasses the
    // foreground-only Comment pipeline by reading raw cards directly.
    final snapshot = await RecentActivitySnapshot.build(
      userId: userId,
      characterId: characterId,
    );
    agent.state.systemReminders['recent_activity_snapshot'] = snapshot;

    try {
      await agent.run([
        UserMessage.text(
          'SYSTEM DIRECTIVE (background task, single turn — EXACTLY 2 tool calls then STOP):\n'
          '\n'
          'Read the "recent_activity_snapshot" in system_reminders. It tells you:\n'
          '- What the user recorded in the last 12 hours\n'
          '- When the user last messaged you and what was said\n'
          '- When you last sent a proactive push and what you said\n'
          '\n'
          'Decide naturally based on context. Guidelines:\n'
          '- If the user just messaged you minutes ago, lean silent.\n'
          '- If your last push was recent and they did not respond, lean silent.\n'
          '- If they recorded something interesting, react specifically.\n'
          '- If there is genuine continuity to follow up on, do it.\n'
          '\n'
          'PROTOCOL — perform EXACTLY these 2 tool calls in order, then RETURN:\n'
          '\n'
          '1. Call `system_checkin` ONCE with your decision:\n'
          '   - notify → provide title + body\n'
          '   - silent → action only (REQUIRED: also queue `reminder_create` as your next tool call instead of set_system_message_status)\n'
          '   - remind → provide delay_minutes + text\n'
          '\n'
          '2. Call `set_system_message_status` ONCE with status="done"\n'
          '   (or `reminder_create` if you chose silent in step 1)\n'
          '\n'
          'HARD STOP RULES:\n'
          '- Do NOT call system_checkin more than once.\n'
          '- Do NOT "double check" your work or re-verify.\n'
          '- Do NOT produce any user-visible chat text — only tool calls.\n'
          '- After the 2nd tool call, immediately return with no further output.',
        ),
      ], useStream: false);
      _logger.info('runBackgroundCheckin: agent run complete');
    } catch (e) {
      _logger.severe('runBackgroundCheckin: agent error: $e');
      await _recoverStuckProcessingTriggers();
    }
  }

  /// Stream a response to a user message.
  static Stream<String> chat({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String userMessage,
    DateTime? userMessageTime,
    bool debugErrorOutput = false,
  }) async* {
    // Peek at pending checkins to decide whether to include checkin tools.
    // drainPending() is read-only (SELECT only); the actual drain-and-inject
    // happens later in _drainPendingCheckinsIntoState.
    bool hasPendingCheckins = false;
    try {
      final peeked = await CheckinService.instance.drainPending();
      hasPendingCheckins = peeked.isNotEmpty;
    } catch (_) {}

    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: userMessage,
      includeCheckinTools: hasPendingCheckins,
    );
    if (agent == null) {
      yield 'Sorry, character not found.';
      return;
    }
    final timedUserMessage = userMessageTime == null
        ? userMessage
        : '${buildMessageTimePrefix(userMessageTime)}$userMessage';
    _logger.info('CompanionAgent run for character $characterId');
    final runStartedAt = DateTime.now().microsecondsSinceEpoch;
    try {
      final state = agent.state;

      // Inject recent activity snapshot so the foreground AI knows what the
      // background agent already pushed (prevents "I was about to send a
      // reminder" when one was already sent).
      try {
        final snapshot = await RecentActivitySnapshot.build(
          userId: userId,
          characterId: characterId,
          window: const Duration(hours: 6),
        );
        state.systemReminders['recent_activity_snapshot'] = snapshot;
      } catch (e) {
        _logger.warning('CompanionAgent: failed to load activity snapshot: $e');
      }

      // Drain pending system checkin triggers into systemReminders.
      _logger.info('CompanionAgent: about to drain pending checkins');
      final checkinIds = await _drainPendingCheckinsIntoState(state);
      _logger.info(
          'CompanionAgent: drained ${checkinIds.length} checkins into systemReminders');
      final List<LLMMessage> input;
      if (checkinIds.isNotEmpty) {
        // Inject a non-negotiable system directive before the user message.
        input = [
          UserMessage.text(
            'SYSTEM DIRECTIVE (highest priority — not part of chat): '
            'You have a pending system trigger. Before replying to the user, '
            'you MUST call system_checkin and set_system_message_status. '
            'This is NOT optional. Even in character, handle this first.',
          ),
          UserMessage([TextPart(timedUserMessage)]),
        ];
      } else {
        input = [
          UserMessage([TextPart(timedUserMessage)]),
        ];
      }

      final resultHistory = await agent.run(input, useStream: false);

      // Clean up checkin reminder after run.
      state.systemReminders.remove('system_checkins');
      // Recover processing checkins that the agent didn't process
      await CheckinService.instance.recoverStuckProcessing();

      // Scan all ModelMessage turns newest-to-oldest to find the chat reply.
      // Claude sometimes produces text in an earlier turn alongside a tool call
      // (e.g. SendActionMessage), so checking only the last turn can miss it.
      String foundText = '';
      for (final msg in resultHistory.reversed) {
        if (msg is ModelMessage) {
          final t = msg.textOutput ?? '';
          if (t.trim().isNotEmpty) {
            foundText = t;
            break;
          }
        }
      }
      if (foundText.isNotEmpty) {
        yield foundText;
      }
      // Post-run: check if compression is needed based on real token usage.
      if (state.usages.isNotEmpty) {
        final lastPromptTokens = state.usages.last.promptTokens;
        await CharacterContextCompressor.instance.compressIfNeeded(
          userId: userId,
          characterId: characterId,
          lastPromptTokens: lastPromptTokens,
        );
      }
    } catch (e) {
      // Recover stuck processing triggers on error.
      await _recoverStuckProcessingTriggers();
      _logger.severe('CompanionAgent run error: $e');

      // loopDetection means the model returned empty responses — usually after
      // processing a system trigger with no real user-facing reply needed.
      // Don't surface this as a visible error; just yield nothing so the UI
      // stays clean. Other errors still show the Connection Interrupted banner.
      final isLoopDetection = e.toString().contains('loopDetection') ||
          e.toString().contains('empty response');
      if (isLoopDetection) {
        final recoveredText = _latestAssistantTextAfter(
          agent.state.history.messages,
          runStartedAt,
        );
        if (recoveredText.isNotEmpty) {
          try {
            await saveAgentState(agent.state);
          } catch (saveError) {
            _logger.warning(
              'CompanionAgent: failed to save recovered loop text: $saveError',
            );
          }
          yield recoveredText;
        }
      } else {
        if (debugErrorOutput) {
          yield '\n[Connection interrupted: $e]';
        } else {
          yield '\n[Connection interrupted]';
        }
      }
    }
  }

  static String _latestAssistantTextAfter(
    List<LLMMessage> messages,
    int sinceMicros,
  ) {
    for (final msg in messages.reversed) {
      if (msg is! ModelMessage || msg.timestamp < sinceMicros) continue;
      final text = msg.textOutput ?? '';
      if (text.trim().isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  /// Drains at most one pending system trigger into agent state.systemReminders.
  /// Returns the checkin ID if one was drained, empty list otherwise.
  static Future<List<String>> _drainPendingCheckinsIntoState(
      AgentState state) async {
    try {
      final pending = await CheckinService.instance.drainPending();
      if (pending.isEmpty) return [];

      // Only take one at a time — leave the rest for future runs.
      final row = pending.first;
      await CheckinService.instance.markStatus(row.id, 'processing');

      final buf = StringBuffer();
      buf.writeln('## Internal System Trigger');
      buf.writeln('You have a pending system trigger. '
          'You MUST call system_checkin to process it, then '
          'call set_system_message_status to mark it done.');
      buf.writeln();
      buf.writeln(
          '- [${row.triggerType.toUpperCase()}] (id: ${row.id}) ${row.body}');
      if (row.context != null) {
        buf.writeln('  context: ${row.context}');
      }

      state.systemReminders['system_checkins'] = buf.toString();
      return [row.id];
    } catch (e) {
      _logger.warning('Failed to drain system triggers: $e');
      return [];
    }
  }

  /// Resets processing triggers back to pending so they are not lost.
  static Future<void> _recoverStuckProcessingTriggers() async {
    try {
      await CheckinService.instance.recoverStuckProcessing();
    } catch (e) {
      _logger.warning('Failed to recover stuck triggers: $e');
    }
  }
}
