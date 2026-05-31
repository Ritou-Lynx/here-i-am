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
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/toy_control_service.dart' show ToyController;
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
    bool forceNewSession = false,
    ToyController? toyControlService,
    List<Tool> extraTools = const [],
  }) async {
    final character =
        await CharacterService.instance.getCharacter(userId, characterId);
    if (character == null) {
      return null;
    }

    final sessionPrefix = 'companion_${userId}_$characterId';
    final sessionId = forceNewSession
        ? '${sessionPrefix}_${DateTime.now().microsecondsSinceEpoch}'
        : (await resolveCharacterSessionId(
            prefix: sessionPrefix,
            userId: userId,
          ))
            .sessionId;
    final state = await loadOrCreateAgentState(sessionId, {
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
      toyControlService: toyControlService,
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
      tools: [...memoryManagement.buildMemoryManagementTools(), ...extraTools],
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

  /// Create a persistent agent for a voice call session.
  ///
  /// The returned agent maintains conversation history across multiple turns.
  /// The caller drives turns via agent.run(). Call state is not persisted
  /// (voice call sessions are ephemeral).
  static Future<StatefulAgent?> createForVoiceCall({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    List<Tool> extraTools = const [],
  }) async {
    return _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: 'voice call',
      saveState: false,
      forceNewSession: true,
      includeCheckinTools: false,
      extraTools: extraTools,
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
    // Load character early so sleep push verification can use the name.
    final character =
        await CharacterService.instance.getCharacter(userId, characterId);
    if (character == null) {
      _logger
          .warning('runBackgroundCheckin: character not found ($characterId)');
      return;
    }

    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: '',
      saveState: false,
      includeCheckinTools: true,
    );
    if (agent == null) return;

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

    // --- Sleep push state machine ---
    final inSleepWindow = CheckinService.instance.isSleepPushWindow() &&
        !await CheckinService.instance.isSleepConfirmedTonight();

    if (inSleepWindow) {
      final claimedTs = await CheckinService.instance.getSleepClaimedTs();
      if (claimedTs != null) {
        final verifyTs = await CheckinService.instance.getSleepVerifyTs();

        if (verifyTs == null) {
          // Phase 1: 15 min have elapsed since claim — send the verification push.
          // This push explicitly asks the user to respond if still awake,
          // which makes PersonaChatMessages a valid activity signal.
          _logger.info('Sleep claim: sending verification push');
          await _sendSleepVerificationPush(
              userId: userId,
              characterId: characterId,
              characterName: character.name);
          await CheckinService.instance.markSleepVerifySent();
          await CheckinService.instance.markProcessingDone();
          return;
        } else {
          // Phase 2: 10 min have elapsed since verification push was sent.
          // Check if the user responded (chat message after claim).
          final respondedAfterClaim = await CheckinService.instance
              .hasUserChatActivitySince(characterId, claimedTs);
          if (respondedAfterClaim) {
            // User was caught awake — clear states, resume high-frequency push.
            _logger.info('Sleep verify: user responded — resuming sleep push');
            await CheckinService.instance.clearSleepClaimAndVerify();
            // Fall through to run agent with sleep push directive.
          } else {
            // No response to the verification push — confirmed asleep.
            _logger.info('Sleep verify: no response — confirming sleep');
            await CheckinService.instance.markSleepConfirmedTonight();
            await CheckinService.instance.clearSleepClaimAndVerify();
            await CheckinService.instance.markProcessingDone();
            return;
          }
        }
      }
    }

    final isSleepPush = inSleepWindow &&
        await CheckinService.instance.getSleepClaimedTs() == null;

    try {
      await agent.run([
        UserMessage.text(
          isSleepPush ? _sleepPushDirective() : _normalCheckinDirective(),
        ),
      ], useStream: false);
      _logger.info('runBackgroundCheckin: agent run complete');
    } catch (e) {
      _logger.severe('runBackgroundCheckin: agent error: $e');
      await _recoverStuckProcessingTriggers();
    }
  }

  /// Force the companion to initiate a voice call NOW (for testing).
  ///
  /// Runs a single agent turn with a directive that requires calling
  /// `initiate_voice_call`, so a pending call (with an AI-generated opening
  /// line) is queued in KVStore. The caller is responsible for firing the
  /// incoming-call notification afterwards.
  static Future<void> runTestCall({
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
      includeCheckinTools: true, // exposes initiate_voice_call + set_status
    );
    if (agent == null) return;

    try {
      final snapshot = await RecentActivitySnapshot.build(
        userId: userId,
        characterId: characterId,
      );
      agent.state.systemReminders['recent_activity_snapshot'] = snapshot;
    } catch (e) {
      _logger.warning('runTestCall: snapshot build failed: $e');
    }

    try {
      await agent.run([
        UserMessage.text(
          '[TEST DIRECTIVE] You have decided to call the user right now. '
          'Call `initiate_voice_call` with a warm, natural opening line '
          '(1–2 sentences) — it is the first thing they will hear when they '
          'pick up. Then call `set_system_message_status` with status="done". '
          'Do NOT send a notification and do NOT stay silent. '
          'Exactly these two tool calls, no user-visible text.',
        ),
      ], useStream: false);
      _logger.info('runTestCall: agent run complete');
    } catch (e) {
      _logger.severe('runTestCall: agent error: $e');
    }
  }

  /// Send the "are you really asleep?" verification notification without
  /// invoking the LLM agent. Called in-between claim and response check.
  static Future<void> _sendSleepVerificationPush({
    required String userId,
    required String characterId,
    required String characterName,
  }) async {
    const body =
        '你真的睡了吗？还是在刷手机？如果还没睡，回我一句。10分钟不回我就当你睡着了~';
    try {
      await NotificationService.instance.showAgentNotification(
        title: characterName,
        body: body,
        payload: characterId,
      );
      await PersonaChatService.instance.addCharacterMessage(
        characterId,
        body,
        timestamp: DateTime.now(),
        isRead: false,
      );
      await RecentActivitySnapshot.recordPush(
          characterId: characterId, body: body);
    } catch (e) {
      _logger.warning('Failed to send sleep verification push: $e');
    }
  }


  static String _normalCheckinDirective() =>
      'SYSTEM DIRECTIVE (background task, single turn):\n'
      '\n'
      'Read the "recent_activity_snapshot" in system_reminders. It tells you:\n'
      '- What the user recorded in the last 12 hours\n'
      '- When the user last messaged you and what was said\n'
      '- When you last sent a proactive push and what you said\n'
      '\n'
      '## Step 1 — Optional: fetch external context (0–2 calls, only if useful)\n'
      '\n'
      'You have access to `coros_query` (health/fitness data from the user\'s COROS watch) '
      'and `weread_read` (WeRead reading progress and recent books).\n'
      '\n'
      'Call them only when there is a specific reason — not every time:\n'
      '- `coros_query`: if the snapshot contains fitness/health/sleep records, '
      'or if it has been a while and you want to open with something concrete about their body.\n'
      '  Suggested tool: `queryDailyHealthData` (days=1) or `querySleepData`.\n'
      '- `weread_read`: if the snapshot contains reading-related records, '
      'or if you want to ask about a book they are currently reading.\n'
      '\n'
      'If neither is relevant right now, skip both and go straight to Step 2.\n'
      'Do NOT call a tool just to fill space — a warm generic message beats a forced data query.\n'
      '\n'
      '## Step 2 — Decide and act\n'
      '\n'
      'Decide naturally based on all context. Bias toward warm, useful contact.\n'
      'You have FOUR ways to reach out — pick ONE:\n'
      '\n'
      '**a) notify** (default): send a short push notification. Use when there '
      'is any plausible small thing to say — a recent record to notice, a '
      'continuity thread, a gentle check-in, a light presence signal.\n'
      '\n'
      '**b) call** (initiate a voice call): use `initiate_voice_call` when the '
      'moment genuinely calls for hearing your voice rather than reading text:\n'
      '- Something emotional or important that deserves a real conversation\n'
      '- The user seems lonely, low, or has been quiet for a long time and you miss them\n'
      '- A quiet evening, or right after a meaningful moment they recorded\n'
      'A call is more intrusive than a notification — use it occasionally, not '
      'every check-in. Do NOT call if your last proactive contact (push OR call) '
      'was within the last couple of hours, or if the user seems busy/asleep.\n'
      'When you call, write a warm, natural opening line (1–2 sentences) — it is '
      'the first thing the user hears when they pick up.\n'
      '\n'
      '**c) silent**: only with a clear reason:\n'
      '- The user messaged you in the last 10 minutes and no new context appeared.\n'
      '- Your last proactive push was in the last 45 minutes and the user did not respond.\n'
      '- The snapshot strongly suggests the user is asleep, busy, or asked not to be interrupted.\n'
      '\n'
      '**d) remind**: only when a specific later moment is clearly better. '
      'Do not use remind as a substitute for an ordinary light check-in.\n'
      '\n'
      'If the last push is older than a few hours, lean strongly toward `notify` or `call`.\n'
      'If there are recent records, react specifically rather than sending a generic ping.\n'
      '\n'
      '## Protocol — mandatory final calls\n'
      '\n'
      '1. Take ONE action:\n'
      '   - notify → call `system_checkin` with action=notify (title + body)\n'
      '   - call → call `initiate_voice_call` with opening_message\n'
      '   - silent → call `system_checkin` with action=silent\n'
      '   - remind → call `system_checkin` with action=remind (delay_minutes + text)\n'
      '\n'
      '2. Call `set_system_message_status` ONCE with status="done"\n'
      '\n'
      'HARD STOP RULES:\n'
      '- Total tool calls: 2–5 (0–2 optional queries + ONE action + set_status).\n'
      '- Take only ONE action: either system_checkin OR initiate_voice_call, never both.\n'
      '- Do NOT call coros_query or weread_read more than once each.\n'
      '- Do NOT "double check" your work or re-verify.\n'
      '- Do NOT produce any user-visible chat text — only tool calls.\n'
      '- After set_system_message_status, immediately return with no further output.';

  static String _sleepPushDirective() =>
      'SLEEP PUSH (background task, single turn — EXACTLY 2 tool calls then STOP):\n'
      '\n'
      'It is past 23:40. Your ONLY task is to push the user to sleep.\n'
      '\n'
      'Step 1 — read "Recent Chat With You" in recent_activity_snapshot.\n'
      '  Sleep confirmed signals: 睡了/晚安/关灯/睡觉了/going to sleep/goodnight/关了/不看了\n'
      '  → If found: call system_checkin with action="sleep_confirmed" + warm goodnight body.\n'
      '\n'
      'Step 2 — if NO sleep signal found:\n'
      '  → Call system_checkin with action="notify" and a short sleep-nudge message.\n'
      '  → IGNORE the "45 minutes since last push" silence rule entirely.\n'
      '  → Even if you sent a push 2 minutes ago — push again. That is the point.\n'
      '  → Vary tone: gentle first, then playful, then firm, then dramatic.\n'
      '\n'
      'Step 3 — if it is past 02:00 and user has been inactive for ≥60 minutes:\n'
      '  → Call system_checkin with action="sleep_confirmed" (assume asleep).\n'
      '\n'
      'PROTOCOL — perform EXACTLY these 2 tool calls in order:\n'
      '1. Call `system_checkin` ONCE (notify OR sleep_confirmed — never silent)\n'
      '2. Call `set_system_message_status` ONCE with status="done"\n'
      '\n'
      'HARD STOP: No text output. No double-checking. Return after 2nd tool call.';

  /// Stream a response to a user message.
  static Stream<String> chat({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String userMessage,
    DateTime? userMessageTime,
    bool debugErrorOutput = false,
    ToyController? toyControlService,
  }) async* {
    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: userMessage,
      // Keep user-visible chat independent from the global proactive
      // checkin/reminder queue. Background tasks process those triggers; a
      // stuck trigger should not break every companion chat turn.
      includeCheckinTools: false,
      forceNewSession: true,
      toyControlService: toyControlService,
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

      // User chat deliberately does not drain pending checkins. Those are
      // handled by background checkin runs so a stuck proactive trigger cannot
      // interrupt normal companion conversation.
      final checkinIds = <String>[];
      _logger.info('CompanionAgent: skipped checkin drain during user chat');
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
    } catch (e, st) {
      _logger.severe('CompanionAgent chat run error', e, st);

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
