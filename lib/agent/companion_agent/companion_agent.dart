import 'dart:async';
import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/companion_agent/recent_activity_snapshot.dart';
import 'package:memex/agent/context/character_context_assembler.dart';
import 'package:memex/agent/memory/character_context_compressor.dart';

import 'package:memex/agent/skills/companion_agent/companion_agent_skill.dart';
import 'package:memex/agent/state_util.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/toy_control_service.dart'
    show ToyController;
import 'package:memex/db/app_database.dart';
import 'package:memex/agent/agent_system_prompt_helper.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/tavern_macro.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';

/// Companion chat agent implemented with StatefulAgent for architecture parity
/// with other scene agents (e.g., CommentAgent).
class CompanionAgent {
  static final Logger _logger = getLogger('CompanionAgent');

  // ---------------------------------------------------------------------------
  // Time-request detection — prevents the common LLM failure mode where it
  // replies "好的，X分钟后提醒你" in text but never calls reminder_create.
  // ---------------------------------------------------------------------------

  /// Patterns indicating the user is making a time-related request.
  static final List<RegExp> _timeRequestPatterns = [
    RegExp(r'\d+\s*分钟'),
    RegExp(r'\d+\s*小时'),
    RegExp(r'\d+\s*[点时]'), // X点, X点半, X时
    RegExp(r'(提醒|叫|喊|通知|打电话|打给)\s*(我|一下)'),
    RegExp(r'(等|过)\s*\d+\s*(分钟|小时|秒)'),
    RegExp(r'(稍后|等会|等会儿|一会|待会|待会儿|过会|过会儿)'),
    RegExp(r'(马上|立刻|现在)\s*(提醒|叫|打电话)'),
  ];

  static bool _containsTimeRequest(String text) =>
      _timeRequestPatterns.any((p) => p.hasMatch(text));

  /// Patterns indicating the agent's text output contains a time-based promise.
  static final List<RegExp> _timeCommitmentPatterns = [
    RegExp(r'\d+\s*分钟'),
    RegExp(r'\d+\s*小时'),
    RegExp(r'\d+\s*[点时]'),
    RegExp(r'(稍后|等会|等会儿|一会|待会|待会儿|过会|过会儿)'),
    RegExp(r'(提醒你|叫你|喊你|通知你|打电话给你|打给你)'),
    RegExp(r'(马上|立刻|现在)\s*(提醒|叫你|通知)'),
  ];

  static bool _containsTimeCommitment(String text) =>
      _timeCommitmentPatterns.any((p) => p.hasMatch(text));

  /// Returns true if any message in [history] contains a reminder_create call.
  static bool _hasReminderCreateCall(List<LLMMessage> history) =>
      history.any((msg) {
        if (msg is ModelMessage) {
          return msg.functionCalls.any((fc) => fc.name == 'reminder_create');
        }
        return false;
      });

  static const _timeRequestDirective =
      '⛔ SYSTEM DIRECTIVE (enforced — not advice):\n'
      'The user just made a time-based request. You MUST call `reminder_create` '
      'in THIS turn — alongside your text reply.\n'
      'Replying with text that promises a future action ("X分钟后提醒你") '
      'without actually calling `reminder_create` is a HARD ERROR.\n'
      'The user will receive NOTHING unless you create the reminder with the tool.\n'
      'CRITICAL — VOICE CALL REQUESTS: if the user asked for a voice call '
      '("打电话", "call me", "给我打", etc.), you MUST set action="call" '
      'in reminder_create. Without action="call" the system will send a '
      'notification instead of actually calling — a broken experience.\n'
      'If unsure of the exact time, ask — but NEVER promise without scheduling.';

  // ── Image generation request detection & directive ──────────────────────

  static final List<RegExp> _imageRequestPatterns = [
    RegExp(r'(画|生成|做|来|给[我你]|帮[我你]).{0,4}(一张|一个|张图|个图|图片|照片|自拍|画像|插画)'),
    RegExp(r'(发张|发一张|拍张|拍一张|来张|来一张|看看|看一下|看看你|给我看)'),
    RegExp(r'(你长|长什么|你穿|你那边|什么样子|的样子|自拍)'),
    RegExp(r'(帮我画|给我画|画一张|画个|生成一张|生成个|做一张)'),
    RegExp(r'(再拍|拍个|拍一次|拍一下|拍张|拍照片|拍出来|拍给我|拍下来|拍个照)'),
    RegExp(r'(发.*照片|发.*自拍|发.*图片|发.*图)'),
    RegExp(r'(照片|自拍|图片).{0,4}(看看|发|给|来)'),
    RegExp(r'(image|picture|photo|draw|generate).{0,10}(me|for|of)'),
  ];

  static bool _containsImageRequest(String text) =>
      _imageRequestPatterns.any((p) => p.hasMatch(text));

  static const _imageRequestDirective =
      '⛔ SYSTEM DIRECTIVE (enforced — not advice):\n'
      'The user just asked to SEE something visually — a photo, picture, '
      'selfie, drawing, or image. You MUST call `generate_image` in THIS turn '
      'alongside your text reply.\n'
      'Text-roleplaying a photo ("发了！看吧👀") without calling the tool '
      'is a HARD ERROR. The user will see NOTHING unless you actually call '
      '`generate_image`.\n'
      'Write a short text reply first (e.g. "好的，我生成一下～"), then '
      'call `generate_image` with a detailed Chinese prompt describing the '
      'image the user wants to see.';

  // ---------------------------------------------------------------------------

  static Future<StatefulAgent?> _createAgent({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String queryHint,
    int? currentUserMessageId,
    bool saveState = true,
    bool includeCheckinTools = false,
    bool forceNewSession = false,
    ToyController? toyControlService,
    Future<String?> Function()? initiateCallPolicy,
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
      currentUserMessageId: currentUserMessageId,
      includeCheckinTools: includeCheckinTools,
      toyControlService: toyControlService,
      initiateCallPolicy: initiateCallPolicy,
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
    if (SharedLifeMemoryService.isInitialized && queryHint.trim().isNotEmpty) {
      try {
        final entities = await SharedLifeMemoryService.instance
            .queryRelevantEntities(queryHint, limit: 8);
        if (entities.isNotEmpty) {
          state.systemReminders['shared_life_entities'] =
              '## Relevant Shared Life Records\n'
              'This is a narrow current-state preview. Use `LifeMemoryQuery` '
              'before answering when exact retrieval matters.\n'
              'Note: entries with `entity_type` of `reading_item` are articles '
              'the user saved from share intents (小红书 / 微信公众号 / web links). '
              'Only mention them when the current conversation naturally '
              'brushes against their topic — do NOT remind the user to read '
              'them unprompted, do NOT track or surface "unread counts". '
              'Treat them as things you happen to remember, not as a todo list. '
              'When the user wants to discuss or hear about a specific saved '
              'article, call `LoadReadingContent` with its entity_id to load '
              'the full body before replying. Discuss in your own voice — '
              'connect to things the user has said, share your take, ask '
              'questions where natural. Do NOT produce bullet-point '
              'corporate summaries or "key takeaways" lists.\n'
              '${entities.map((entity) => jsonEncode(entity.toJson())).join('\n')}';
        } else {
          state.systemReminders.remove('shared_life_entities');
        }
      } catch (e) {
        _logger.warning('Failed to load shared life context: $e');
      }
    } else {
      state.systemReminders.remove('shared_life_entities');
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

    return StatefulAgent(
      name: 'companion_agent',
      client: client,
      modelConfig: modelConfig,
      state: state,
      skills: [skill],
      tools: extraTools,
      systemPrompts: const [],
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

    final pendingTrigger = await _drainPendingCheckinsIntoState(agent.state);
    if (pendingTrigger == null) {
      _logger.info('runBackgroundCheckin: no pending checkins, skipping');
      return;
    }
    final trigger = pendingTrigger;

    if (trigger.triggerType == 'checkin' && trigger.body.trim().isNotEmpty) {
      final activeSince = DateTime.now()
              .subtract(const Duration(minutes: 10))
              .millisecondsSinceEpoch ~/
          1000;
      final recentlyChatting = await CheckinService.instance
          .hasUserChatActivitySince(characterId, activeSince);
      if (recentlyChatting) {
        _logger.info(
          'runBackgroundCheckin: recent user chat, completing checkin silently',
        );
        await CheckinService.instance.markProcessingDone();
        return;
      }
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
        UserMessage.text(_directiveForTrigger(trigger)),
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

  static String _directiveForTrigger(SystemMessageQueueData trigger) {
    if (_isScheduledVoiceCall(trigger)) {
      return _scheduledVoiceCallDirective(trigger.body);
    }
    return _normalCheckinDirective();
  }

  static bool _isScheduledVoiceCall(SystemMessageQueueData trigger) {
    if (trigger.triggerType != 'reminder' || trigger.context == null) {
      return false;
    }
    try {
      final context = jsonDecode(trigger.context!);
      return context is Map<String, dynamic> && context['action'] == 'call';
    } catch (e) {
      _logger.warning(
        'Ignoring malformed reminder context for ${trigger.id}: $e',
      );
      return false;
    }
  }

  static String _scheduledVoiceCallDirective(String reminderText) =>
      'SYSTEM DIRECTIVE (scheduled user commitment, single turn):\n'
      '\n'
      'The user explicitly requested a voice call at this time. Call them now.\n'
      'Reminder: $reminderText\n'
      '\n'
      'PROTOCOL - perform EXACTLY these 2 tool calls in order:\n'
      '1. Call `initiate_voice_call` with a warm, natural opening_message.\n'
      '2. Call `set_system_message_status` ONCE with status="done".\n'
      '\n'
      'Do NOT notify, stay silent, reschedule, or produce user-visible text. '
      'This is a user-requested timed commitment, not a discretionary checkin.';

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
      '  ⚠️ Sleep date semantics: sleep data is keyed by WAKE-UP date. '
      '"昨晚的睡眠" (last night\'s sleep) → query TODAY. '
      'If today has no data, DO NOT fall back to yesterday — that is the wrong night. '
      'Tell the user to sync their watch.\n'
      '- `weread_read`: if the snapshot contains reading-related records, '
      'or if you want to ask about a book they are currently reading.\n'
      '\n'
      'If neither is relevant right now, skip both and go straight to Step 2.\n'
      'Do NOT call a tool just to fill space — a warm generic message beats a forced data query.\n'
      '\n'
      '## Step 2 — Decide and act\n'
      '\n'
      'Decide naturally based on all context. Bias toward warm, useful contact.\n'
      'If Recent Chat With You shows an ongoing exchange, game, roleplay, or '
      'question-answer thread, preserve continuity. Prefer silent when the '
      'user may still be engaged. If you do notify, it must clearly continue '
      'that thread rather than switching topics.\n'
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
      '- Total tool calls: 2-6 (0-2 optional queries + optional device_app_blocker_control + ONE communication action + set_status).\n'
      '- Take only ONE action: either system_checkin OR initiate_voice_call, never both.\n'
      '- Do NOT call coros_query or weread_read more than once each.\n'
      '- Do NOT "double check" your work or re-verify.\n'
      '- Do NOT produce any user-visible chat text — only tool calls.\n'
      '- After set_system_message_status, immediately return with no further output.';

  /// Stream a response to a user message.
  static Stream<String> chat({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String userMessage,
    List<ImagePart>? images,
    int? userMessageId,
    DateTime? userMessageTime,
    bool debugErrorOutput = false,
    bool voiceMode = false,
    bool continuousModeInput = false,
    ToyController? toyControlService,
    List<Tool> extraTools = const [],
  }) async* {
    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      queryHint: userMessage,
      currentUserMessageId: userMessageId,
      // Include call and reminder tools so users can request immediate calls
      // or schedule calls for later ("call me now" / "call me in 30 minutes").
      // Background checkin tasks process their own queued triggers separately.
      includeCheckinTools: true,
      forceNewSession: true,
      toyControlService: toyControlService,
      extraTools: extraTools,
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

      // Explicitly signal text-chat mode. Without this, the LLM can drift into
      // voice-call behavior when recent chat history contains call-related
      // context (declined calls, call transcripts, proactive pushes, etc.).
      state.systemReminders['chat_mode'] = '## TEXT CHAT MODE (active)\n'
          'You are in a TEXT CHAT. The user is typing, NOT calling you.\n'
          '- Speak naturally in text. Do NOT use voice-call language.\n'
          '- Do NOT use `initiate_voice_call` unless the user explicitly asks '
          'you to call them right now ("call me", "打给我").\n'
          '- "（📞 ...）" messages in chat history are past records — they do '
          'NOT mean you are currently on a call.';

      if (voiceMode) {
        state.systemReminders['chat_mode'] = '## CHAT VOICE MODE (active)\n'
            'The user is in the chat screen, using voice interaction. '
            'Your replies are still saved as normal chat messages and spoken '
            'aloud via TTS.\n'
            '- Speak naturally for voice: short, warm, conversational.\n'
            '- Do NOT use action text, markdown, or parenthetical thoughts.\n'
            '- Do NOT call `initiate_voice_call`; the user is already in '
            'voice mode inside chat.\n'
            '- If the user asks to hang up/end the call, or you naturally '
            'decide to end the voice conversation, say a brief spoken goodbye '
            'and call `end_voice_mode` in the same turn.';
      }

      if (continuousModeInput) {
        state.systemReminders['continuous_mode'] =
            '## CONTINUOUS MODE (active)\n'
            'The user wants you to keep narrating without waiting for their '
            'input. Do NOT ask questions. Do NOT wait for user input. Just '
            'continue the scene naturally. Write the next part of the story '
            'or roleplay directly.\n'
            'Treat "[继续叙述]" as a signal to advance the scene — do not '
            'acknowledge it as a message. Do not greet or restart.\n'
            'Keep responses vivid and varied. Advance time, introduce new '
            'details, drive the scene forward. Do not loop or repeat. Do not '
            'end the scene prematurely.\n'
            'Do NOT call `request_continuous_replies` again — you are already '
            'in continuous mode.';
      }

      // User chat deliberately does not drain pending checkins. Those are
      // handled by background checkin runs so a stuck proactive trigger cannot
      // interrupt normal companion conversation.
      final checkinIds = <String>[];
      _logger.info('CompanionAgent: skipped checkin drain during user chat');

      // Detect time-based user requests and inject a high-priority directive
      // before the agent runs. This prevents the common failure mode where the
      // LLM replies "好的，X分钟后提醒你" but never calls reminder_create.
      final hasTimeRequest = _containsTimeRequest(userMessage);
      if (hasTimeRequest) {
        state.systemReminders['time_request_directive'] = _timeRequestDirective;
      }

      // Detect image generation requests and inject a hard directive.
      // MiniMax models tend to roleplay sending photos in text instead of
      // actually calling the tool — this directive makes it non-optional.
      final hasImageRequest = _containsImageRequest(userMessage);
      debugPrint(
          '[ImageGen] _containsImageRequest("${userMessage.length > 40 ? userMessage.substring(0, 40) : userMessage}...") = $hasImageRequest');
      if (hasImageRequest) {
        state.systemReminders['image_request_directive'] =
            _imageRequestDirective;
        debugPrint(
            '[ImageGen] Injected image_request_directive into systemReminders');
      }

      final List<UserContentPart> userParts = [TextPart(timedUserMessage)];
      if (images != null && images.isNotEmpty) {
        userParts.addAll(images);
      }

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
          UserMessage(userParts),
        ];
      } else {
        input = [
          UserMessage(userParts),
        ];
      }

      // Keep companion chat on the stable non-streaming path. Some compatible
      // providers expose reasoning as visible text during streaming, and chunk
      // semantics differ across clients (delta vs cumulative), which can leak
      // thought text or persist only the final few characters.
      final resultHistory = await agent.run(input, useStream: false);

      // Clean up transient directives after run.
      state.systemReminders.remove('system_checkins');
      state.systemReminders.remove('time_request_directive');

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

      // Post-processing: if the agent made a time commitment in text but
      // didn't call reminder_create, run a silent correction turn so the
      // reminder is actually created. This is the safety net for when the
      // pre-processing directive isn't enough.
      final madeTimeCommitment =
          foundText.isNotEmpty && _containsTimeCommitment(foundText);
      final calledReminderCreate = _hasReminderCreateCall(resultHistory);
      if (madeTimeCommitment && !calledReminderCreate) {
        _logger.severe(
          'AGENT DID NOT CALL reminder_create despite time commitment. '
          'User: "${userMessage.length > 80 ? '${userMessage.substring(0, 80)}…' : userMessage}". '
          'Agent: "${foundText.length > 80 ? '${foundText.substring(0, 80)}…' : foundText}". '
          'Running silent correction turn.',
        );
        try {
          await agent.run([
            UserMessage.text(
              '⛔ CORRECTION (silent — user does not see this):\n'
              'Your previous reply said: "$foundText"\n'
              'But you did NOT call `reminder_create`. The reminder was NOT created.\n\n'
              'The user\'s original request was: "$userMessage"\n\n'
              'You MUST call `reminder_create` NOW with the correct delay_minutes '
              'or due_at based on that request.\n\n'
              'IMPORTANT: Only call the tool. Do NOT produce any user-visible '
              'text or chat reply. This is a silent system correction.',
            ),
          ], useStream: false);
          _logger.info('Correction turn complete — reminder should now exist');
        } catch (e) {
          _logger.severe('Correction turn failed: $e');
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
  /// Returns the system trigger if one was drained, null otherwise.
  static Future<SystemMessageQueueData?> _drainPendingCheckinsIntoState(
      AgentState state) async {
    try {
      final pending = await CheckinService.instance.drainPending();
      if (pending.isEmpty) return null;

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
      return row;
    } catch (e) {
      _logger.warning('Failed to drain system triggers: $e');
      return null;
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
