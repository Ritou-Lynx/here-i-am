import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/memex_skill_host_agent/memex_skill_host_agent.dart';
import 'package:memex/agent/pure_skill_host_agent/pure_skill_host_agent.dart';
import 'package:memex/agent/super_agent/super_agent.dart';
import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/domain/models/custom_agent_config.dart';
import 'package:memex/domain/models/location_context_config.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/utils/token_usage_utils.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'package:memex/data/model/chat_events.dart';

export 'package:memex/data/model/chat_events.dart';

// --- Chat Service ---

class ChatService {
  static final ChatService _instance = ChatService._internal();
  static ChatService get instance => _instance;
  ChatService._internal();

  final Logger _logger = getLogger('ChatService');
  final FileSystemService _fileService = FileSystemService.instance;
  final Uuid _uuid = const Uuid();

  /// Send a message and get a stream of events.
  ///
  /// When [isQuickQuery] is true, the agent operates in read-only mode
  /// (filtered tools/skills), but the session is still persisted normally.
  Stream<ChatEvent> sendMessage(
    String message, {
    String? sessionId,
    String? agentName = 'memex_agent',
    String? scene = 'assistant',
    String? sceneId,
    List<Map<String, String>>? refs,
    bool isQuickQuery = false,
  }) async* {
    _logger.info(
      'sendMessage: sessionId=$sessionId, message=$message, refs=${refs?.length}',
    );

    final userId = await UserStorage.getUserId();
    if (userId == null) {
      yield ChatErrorEvent('User not logged in');
      return;
    }

    String finalSessionId = sessionId ?? '';

    // 1. Session Management
    try {
      if (finalSessionId.isEmpty) {
        finalSessionId = await _createSession(
            userId,
            agentName,
            [
              {'type': 'text', 'text': message},
            ],
            isQuickQuery: isQuickQuery);
      }

      // Notify UI of the active session ID immediately
      yield ChatSessionCreatedEvent(finalSessionId);

      // Save User Message
      await _addMessageToSession(
        userId,
        finalSessionId,
        'user',
        [
          {'type': 'text', 'text': message},
        ],
        refs: refs,
        isQuickQuery: isQuickQuery,
      );

      // Log chat event
      try {
        await _fileService.eventLogService.logEvent(
          userId: userId,
          eventType: 'user_chat',
          description: 'User sent message to agent',
          metadata: {
            'agent_name': agentName ?? 'memex_agent',
            'scene': scene ?? 'assistant',
            'scene_id': sceneId,
            'session_id': finalSessionId,
            'message': message,
            'has_refs': refs != null && refs.isNotEmpty,
            'is_quick_query': isQuickQuery,
          },
        );
      } catch (e) {
        // Event logging failure should not break chat
      }
    } catch (e) {
      _logger.severe('Failed to manage session', e);
      yield ChatErrorEvent('Failed to initialize session: $e');
      return;
    }

    // 2. Initialize Agent
    StatefulAgent? agent;
    AgentController? controller;
    SkillSyncResult? skillSync;

    try {
      // Load all custom agent configs once; used for agent detection and
      // capability injection into memex_agent's system prompt.
      final allCustomConfigs =
          await CustomAgentConfigService.instance.loadAll(userId);

      // Resolve custom agent config by agentName — works for both new sessions
      // (no sessionId yet) and existing sessions.  Built-in agent names like
      // 'memex_agent' or 'knowledge_insight_agent' won't match any custom
      // config, so customAgentCfg stays null and we fall through to SuperAgent.
      CustomAgentConfig? customAgentCfg =
          (agentName != null && agentName.isNotEmpty)
              ? allCustomConfigs
                  .where((c) => c.agentName == agentName)
                  .firstOrNull
              : null;

      final agentIdForLLM =
          customAgentCfg?.llmConfigKey ?? AgentDefinitions.chatAgent;
      final resources = await UserStorage.getAgentLLMResources(
        agentIdForLLM,
        defaultClientKey:
            customAgentCfg?.llmConfigKey ?? LLMConfig.defaultClientKey,
      );
      final client = resources.client;
      final modelConfig = resources.modelConfig;

      // Load State
      final stateDirPath = await _fileService.getAgentStateDirectory(userId);
      final stateDir = Directory(stateDirPath);
      final storage = FileStateStorage(stateDir);
      final state = await storage.loadOrCreate(finalSessionId, {
        'userId': userId,
        'scene': scene,
        'sceneId': sceneId,
      });

      controller = AgentController();

      if (customAgentCfg != null) {
        // Recreate the same agent type used by custom_agent_task_handler.
        final skillDir = _fileService.resolveSkillPath(
          userId,
          customAgentCfg.skillDirectoryPath,
        );
        final workingDirAbs = await _fileService.resolveWorkingDirectory(
          userId,
          customAgentCfg.workingDirectory,
        );

        // Sync skill directory into workingDirectory if it's outside,
        // so file tools (Read, LS, etc.) can access skill files.
        skillSync = await _fileService.syncSkillsIfNeeded(
          skillAbsPath: skillDir,
          workingDirAbsPath: workingDirAbs,
        );

        switch (customAgentCfg.hostAgentType) {
          case HostAgentType.pure:
            agent = await PureSkillHostAgent.createAgent(
              client: client,
              modelConfig: modelConfig,
              userId: userId,
              name: agentName ?? 'custom_agent',
              state: state,
              skillDirectoryPath: skillSync.effectivePath,
              workingDirectory: workingDirAbs,
              controller: controller,
              additionalSystemPrompt: customAgentCfg.systemPrompt,
            );
            break;
          case HostAgentType.memex:
            agent = await MemexSkillHostAgent.createAgent(
              client: client,
              modelConfig: modelConfig,
              userId: userId,
              name: agentName ?? 'custom_agent',
              state: state,
              skillDirectoryPath: skillSync.effectivePath,
              workingDirectory: workingDirAbs,
              controller: controller,
              additionalSystemPrompt: customAgentCfg.systemPrompt,
            );
            break;
        }
      } else {
        // Default: use SuperAgent for normal chat sessions.
        var additionalSystemPrompt = """## Comprehensive Correction Principles
When the user disputes content you generated (such as Cards, PKM entries, or Asset Analysis Results) and provides correction suggestions, you must perform a **comprehensive** correction.
-   **Do not modify only a single dimension** (e.g., do not just modify the card body or just the asset analysis).
-   **You must check and synchronously correct all related content** to ensure overall consistency.
-   **Example**: If the user corrects the description of an image, you must not only update the image analysis result (`.analysis.txt`) but also check if the Card body (`Cards/...`) or related PKM entries that reference this image need to be updated synchronously.

## Interaction Guidelines
- **Ask Clarifying Questions**: You are engaging in a direct dialogue. If the user's request is unclear, explicitly ask for clarification instead of guessing.
- **Professional Tone**: You are communicating directly with the knowledge base owner. Maintain a formal, concise, and professional tone.
- **Know Your Limits**: If a task cannot be accomplished with your current skills and tools, explicitly decline the request with an explanation.

## Important
- **Language**: ${UserStorage.l10n.chatLanguageInstruction}
""";

        // Inject WeRead capability if the user has configured the WeRead agent.
        // This lets memex_agent answer reading/book questions directly via http_fetch.
        final wereadCfg =
            allCustomConfigs.where((c) => c.agentName == 'weread').firstOrNull;
        if (wereadCfg != null) {
          final sp = wereadCfg.systemPrompt ?? '';
          final keyMatch = RegExp(r'wrk-[A-Za-z0-9]+').firstMatch(sp);
          if (keyMatch != null) {
            final apiKey = keyMatch.group(0)!;
            additionalSystemPrompt += """

## 微信读书 (WeRead) 集成
用户已配置微信读书。当用户询问阅读记录、书架、在读书籍、读书笔记、阅读时长等问题时，使用 http_fetch 工具直接查询微信读书 API，无需用户再次确认：
- URL: https://i.weread.qq.com/api/agent/gateway
- Method: POST
- Headers: {"Authorization": "Bearer $apiKey", "Content-Type": "application/json"}
- 书架列表：{"api_name": "/shelf/sync", "skill_version": "1.0.3"}
- 搜索书籍：{"api_name": "/store/search", "keyword": "关键词", "scope": 10, "skill_version": "1.0.3"}
- 书籍信息：{"api_name": "/book/info", "bookId": "书籍ID", "skill_version": "1.0.3"}
- 阅读进度：{"api_name": "/book/getprogress", "bookId": "书籍ID", "skill_version": "1.0.3"}
""";
          }
        }

        final forceActiveSkills = <String>[];
        if (scene == 'assistant_timeline_card_detail') {
          forceActiveSkills.add('manage_timeline_card');
          forceActiveSkills.add('manage_pkm');
        } else if (scene == 'insight_card_chat') {
          forceActiveSkills.add('update_knowledge_insight');
        }

        agent = await SuperAgent.createAgent(
          client: client,
          modelConfig: modelConfig,
          userId: userId,
          name: agentName ?? 'memex_agent',
          state: state,
          controller: controller,
          disableSubAgents: false,
          forceActiveSkills: forceActiveSkills,
          quickQuery: isQuickQuery,
          additionalSystemPrompt: additionalSystemPrompt,
        );
      }
    } catch (e) {
      _logger.severe('Failed to initialize agent', e);
      yield ChatErrorEvent('Failed to initialize agent: $e');
      return;
    }

    // 3. Setup Listeners & Run
    final streamController = StreamController<ChatEvent>();

    // Forward events from agent controller to stream
    _setupControllerListeners(
      controller,
      streamController,
      userId,
      finalSessionId,
    );

    // Build scene context reminder
    String sceneContext = "";
    switch (scene) {
      case 'assistant_timeline_card_detail':
        sceneContext =
            "The user is currently viewing a **Timeline Card Detail Page**. They may want to edit, analyze, or discuss this specific card.";
        break;
      case 'update_knowledge_insight':
      case 'insight_card_chat':
        sceneContext =
            "The user is currently on the **Knowledge Insights Page**. They may want to update insights, discuss existing insight cards, or generate new knowledge summaries.";
        break;
      default:
        sceneContext = "";
    }

    List<LLMMessage> userMessages = [];
    CurrentLocationContext? locationContext;
    String? locationContextReminder;
    try {
      locationContext =
          await LocationContextService.instance.getCurrentContext();
      locationContextReminder = locationContext.toAgentSystemReminderContent();
    } catch (e) {
      _logger.warning('Failed to decorate chat with location context: $e');
    }

    // Build combined system reminder content
    if (sceneContext.isNotEmpty ||
        locationContextReminder != null ||
        (refs != null && refs.isNotEmpty)) {
      final StringBuffer reminderContent = StringBuffer();
      reminderContent.write('<system-reminder>\n');

      // Add scene context if available
      if (sceneContext.isNotEmpty) {
        reminderContent.write(sceneContext);
        reminderContent.write('\n');
      }

      if (locationContextReminder != null) {
        if (sceneContext.isNotEmpty) {
          reminderContent.write('\n');
        }
        reminderContent.write(locationContextReminder);
        reminderContent.write('\n');
      }

      // Add refs context if available
      if (refs != null && refs.isNotEmpty) {
        if (sceneContext.isNotEmpty || locationContextReminder != null) {
          reminderContent.write('\n');
        }
        final refsString = refs
            .map(
              (r) =>
                  'Title: ${r['title']}\nType: ${r['type'] ?? 'unknown'}\nContent: ${r['content']}',
            )
            .join('\n\n');
        reminderContent.write(
          'The user has referenced the following content. Use this context to answer the user query:\n',
        );
        reminderContent.write(refsString);
        reminderContent.write('\n');
      }

      reminderContent.write('</system-reminder>');

      userMessages.addAll([
        UserMessage.text(reminderContent.toString()),
        ModelMessage(
          model: "mocked",
          textOutput: "Understood, I will keep this context in mind.",
        ),
      ]);
    }

    // Drain pending system checkin triggers and reminders
    final checkinContext = await _drainPendingSystemTriggers();
    if (checkinContext.isNotEmpty) {
      userMessages.addAll([
        UserMessage.text(checkinContext),
        ModelMessage(
          model: "mocked",
          textOutput:
              "I'll process these system triggers and decide what to do.",
        ),
      ]);
    }

    userMessages.add(
      UserMessage([
        TextPart(buildCurrentTimeReminder(DateTime.now())),
        TextPart(message),
      ]),
    );

    // We don't await the result here, we rely on AgentStoppedEvent to handle completion
    agent.run(userMessages).whenComplete(() async {
      // Sync skill changes back to the original directory if we made a copy.
      if (skillSync != null) {
        try {
          await _fileService.syncSkillsBack(skillSync);
        } catch (e) {
          _logger.warning('Failed to sync skills back: $e');
        }
      }
    }).catchError((e) async {
      // Reset stuck processing triggers so they don't get lost
      try {
        await _recoverStuckProcessingTriggers();
      } catch (_) {}
      // This catchError is for synchronous errors during startup or unhandled async errors
      _logger.severe('Agent run failed (catchError)', e);
      if (!streamController.isClosed) {
        streamController.add(ChatErrorEvent(e.toString()));
        streamController.close();
      }
      return <LLMMessage>[];
    });

    yield* streamController.stream;
  }

  /// Resets any processing triggers back to pending so they are not lost.
  Future<void> _recoverStuckProcessingTriggers() async {
    try {
      await CheckinService.instance.recoverStuckProcessing();
    } catch (e) {
      _logger.warning('Failed to recover stuck triggers: $e');
    }
  }

  /// Drains pending system triggers (checkins and due reminders) and formats
  /// them as a <system-reminder type="checkin"> block for the agent.
  Future<String> _drainPendingSystemTriggers() async {
    try {
      _logger.info('_drainPendingSystemTriggers: querying...');
      final pending = await CheckinService.instance.drainPending();
      _logger.info('_drainPendingSystemTriggers: found ${pending.length} pending');
      if (pending.isEmpty) return '';

      // Mark all as processing (turn gate)
      for (final row in pending) {
        await CheckinService.instance.markStatus(row.id, 'processing');
      }

      final buf = StringBuffer();
      buf.writeln('<system-reminder type="checkin">');
      buf.writeln('SYSTEM ACTION MODE: internal triggers are pending.');
      buf.writeln('You have ${pending.length} system trigger(s).');
      buf.writeln(
          'Review each trigger, then call system_checkin to process and decide:');
      buf.writeln('  silent, notify, or remind.');
      buf.writeln('After processing all triggers, call set_system_message_status.');
      buf.writeln();

      for (final row in pending) {
        buf.writeln(
            '[${row.triggerType.toUpperCase()}] (id: ${row.id}) ${row.body}');
        if (row.context != null) {
          buf.writeln('  Context: ${row.context}');
        }
        buf.writeln();
      }
      buf.writeln('</system-reminder>');

      return buf.toString();
    } catch (e) {
      _logger.warning('Failed to drain system triggers: $e');
      return '';
    }
  }

  void _setupControllerListeners(
    AgentController controller,
    StreamController<ChatEvent> stream,
    String userId,
    String sessionId,
  ) {
    // 1. Lifecycle Events
    // 1. Lifecycle Events
    controller.on((AgentStartedEvent event) {
      _logger.info('Agent started');
      stream.add(ChatAgentStartedEvent());
    });

    controller.on((AgentStoppedEvent event) async {
      _logger.info('Agent stopped');

      // Calculate usage stats
      int totalPrompt = 0;
      int totalCompletion = 0;
      int totalCached = 0;
      int totalEffectivePrompt = 0;
      int totalCachedForRate = 0;
      int totalTokens = 0;
      double totalCost = 0.0;
      // Within a single agent turn all calls share the same client.
      bool? turnCacheSemantics;

      for (final msg in event.modelMessages) {
        final u = msg.usage;
        if (u == null) {
          continue;
        }

        final p = u.promptTokens;
        final c = u.completionTokens;
        final ca = u.cachedToken;
        final sem = TokenUsageUtils.cachedTokensIncludedInPrompt(
          client: event.agent.client,
          originalUsage: u.originalUsage,
        );
        turnCacheSemantics ??= sem;
        final effP = TokenUsageUtils.effectivePromptTokensOrNull(
          promptTokens: p,
          cachedTokens: ca,
          cachedTokensIncludedInPrompt: sem,
        );

        totalPrompt += p;
        totalCompletion += c;
        totalCached += ca;
        if (effP != null) {
          totalEffectivePrompt += effP;
          totalCachedForRate += ca;
        }
        totalTokens += u.totalTokens;

        // Calculate cost
        final cost = TokenUsageUtils.calculateCost(
          model: msg.model,
          promptTokens: p,
          completionTokens: c,
          cachedTokens: ca,
          thoughtTokens: u.thoughtToken,
          cachedTokensIncludedInPrompt: sem,
        )['total']!;
        totalCost += cost;
      }

      if (event.error != null) {
        // Reset stuck processing triggers so they can be retried next turn
        _recoverStuckProcessingTriggers();
        if (!stream.isClosed) {
          stream.add(ChatAgentStoppedEvent());
          stream.add(ChatErrorEvent(event.error.toString()));
          stream.close();
        }
        return;
      }

      // Handle success / final result
      String response = "Sorry, I couldn't generate a response.";
      if (event.modelMessages.isNotEmpty) {
        final lastMsg = event.modelMessages.last;
        if (lastMsg.textOutput != null) {
          response = lastMsg.textOutput!;
        }
      }

      // Save AI response with usage stats
      final sessionTotalUsage = await _addMessageToSession(
        userId,
        sessionId,
        'ai',
        [
          {'type': 'text', 'text': response},
        ],
        usage: {
          'prompt_tokens': totalPrompt,
          'completion_tokens': totalCompletion,
          'cached_tokens': totalCached,
          if (turnCacheSemantics != null)
            'cache_tokens_included_in_prompt': turnCacheSemantics,
          'total_tokens': totalTokens,
          'total_cost': totalCost,
        },
      );

      // Emit Token Usage (Cumulative if available, else current turn)
      if (sessionTotalUsage != null) {
        stream.add(
          ChatTokenUsageEvent(
            promptTokens: sessionTotalUsage['prompt_tokens'] as int? ?? 0,
            completionTokens:
                sessionTotalUsage['completion_tokens'] as int? ?? 0,
            cachedTokens: sessionTotalUsage['cached_tokens'] as int? ?? 0,
            effectivePromptTokens: totalEffectivePrompt,
            cachedTokensForRate: totalCachedForRate,
            totalTokens: sessionTotalUsage['total_tokens'] as int? ?? 0,
            estimatedCost: sessionTotalUsage['total_cost'] as double? ?? 0.0,
          ),
        );
      } else if (totalTokens > 0) {
        // Fallback to single turn usage
        stream.add(
          ChatTokenUsageEvent(
            promptTokens: totalPrompt,
            completionTokens: totalCompletion,
            cachedTokens: totalCached,
            effectivePromptTokens: totalEffectivePrompt,
            cachedTokensForRate: totalCachedForRate,
            totalTokens: totalTokens,
            estimatedCost: totalCost,
          ),
        );
      }

      if (!stream.isClosed) {
        // Send a final empty chunk to mark isDone=true without duplicating text
        stream.add(ChatResponseChunkEvent('', isDone: true));
        stream.add(ChatAgentStoppedEvent());
        stream.close();
      }
    });

    // 2. Planning Events
    controller.on((PlanChangedEvent event) {
      String getStatusEmoji(String status) {
        switch (status.toLowerCase()) {
          case 'completed':
          case 'success':
          case 'done':
            return '✅';
          case 'active':
          case 'running':
          case 'inprogress':
            return '👉';
          case 'failed':
          case 'error':
            return '❌';
          case 'pending':
          default:
            return '⏳'; // Or ⬜
        }
      }

      final planText = event.plan.steps.map((t) {
        final emoji = getStatusEmoji(t.status.name);
        return '$emoji ${t.description}';
      }).join('\n\n');
      stream.add(ChatThoughtChunkEvent("Plan Updated:\n$planText"));
    });

    // 3. Thoughts & Chunks
    controller.on((LLMChunkEvent event) {
      if (event.response.thought != null &&
          event.response.thought!.isNotEmpty) {
        stream.add(ChatThoughtChunkEvent(event.response.thought!));
      }

      if (event.response.textOutput != null &&
          event.response.textOutput!.isNotEmpty) {
        stream.add(ChatResponseChunkEvent(event.response.textOutput!));
      }
    });

    // 4. Tool Call
    controller.on((BeforeToolCallEvent event) {
      stream.add(
        ChatToolCallEvent(
          event.functionCall.name,
          event.functionCall.arguments.toString(),
        ),
      );
    });

    // 5. Tool Result
    // 5. Tool Result
    controller.on((AfterToolCallEvent event) {
      // Format result for display
      final dynamic content = event.result.content;
      String resultPreview;

      if (content is List) {
        resultPreview = content.map((e) {
          if (e is TextPart) return e.text;
          return e.toString();
        }).join('\n');
      } else if (content is TextPart) {
        resultPreview = content.text;
      } else {
        resultPreview = content.toString();
      }

      if (resultPreview.length > 300) {
        resultPreview = '${resultPreview.substring(0, 300)}...';
      }
      stream.add(
        ChatToolResultEvent(
          event.result.name,
          resultPreview,
          isError: event.result.isError,
        ),
      );
    });
  }

  // --- Session Helpers (Recreated from chat.dart to be independent) ---

  Future<String> _createSession(
    String userId,
    String? agentName,
    List<Map<String, dynamic>> initialContent, {
    bool isQuickQuery = false,
  }) async {
    final uuidStr = _uuid.v4();
    final sessionId = agentName != null && agentName.isNotEmpty
        ? '${agentName}_$uuidStr'
        : uuidStr;
    final now = DateTime.now();

    String? title;
    for (final item in initialContent) {
      if (item['type'] == 'text' && item['text'] != null) {
        final text = item['text'] as String;
        title = text.length > 50 ? text.substring(0, 50) : text;
        break;
      }
    }

    final sessionData = {
      'session_id': sessionId,
      'agent_name': agentName,
      'title': title ?? 'New Chat',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'is_quick_query': isQuickQuery,
      'messages': <dynamic>[],
    };

    final sessionFile = _getSessionFilePath(userId, sessionId);
    final parentDir = sessionFile.parent;
    await parentDir.create(recursive: true);

    await _fileService.writeYamlFile(sessionFile.path, sessionData);
    return sessionId;
  }

  Future<Map<String, dynamic>?> _addMessageToSession(
    String userId,
    String sessionId,
    String role,
    List<Map<String, dynamic>> content, {
    Map<String, dynamic>? usage,
    List<Map<String, String>>? refs,
    bool? isQuickQuery,
  }) async {
    final sessionFile = _getSessionFilePath(userId, sessionId);
    if (!await sessionFile.exists()) return null;

    final fileContent = await sessionFile.readAsString();
    final doc = loadYaml(fileContent);
    final sessionData = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;

    final messageDict = {
      'role': role,
      'content': content,
      if (usage != null) 'usage': usage,
      if (refs != null) 'refs': refs,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final messages = (sessionData['messages'] as List<dynamic>? ?? [])
      ..add(messageDict);
    sessionData['messages'] = messages;

    // Update cumulative session usage
    if (usage != null) {
      final currentTotal =
          sessionData['total_usage'] as Map<String, dynamic>? ??
              {
                'prompt_tokens': 0,
                'completion_tokens': 0,
                'cached_tokens': 0,
                'total_tokens': 0,
                'total_cost': 0.0,
              };

      sessionData['total_usage'] = {
        'prompt_tokens': (currentTotal['prompt_tokens'] as int? ?? 0) +
            (usage['prompt_tokens'] as int? ?? 0),
        'completion_tokens': (currentTotal['completion_tokens'] as int? ?? 0) +
            (usage['completion_tokens'] as int? ?? 0),
        'cached_tokens': (currentTotal['cached_tokens'] as int? ?? 0) +
            (usage['cached_tokens'] as int? ?? 0),
        'total_tokens': (currentTotal['total_tokens'] as int? ?? 0) +
            (usage['total_tokens'] as int? ?? 0),
        'total_cost': (currentTotal['total_cost'] as double? ?? 0.0) +
            (usage['total_cost'] as double? ?? 0.0),
      };
    }

    // Update session-level mode flag so history can restore it
    if (isQuickQuery != null) {
      sessionData['is_quick_query'] = isQuickQuery;
    }

    sessionData['updated_at'] = DateTime.now().toIso8601String();

    await _fileService.writeYamlFile(sessionFile.path, sessionData);
    return sessionData['total_usage'] as Map<String, dynamic>?;
  }

  File _getSessionFilePath(String userId, String sessionId) {
    final sessionsPath = _fileService.getChatSessionsPath(userId);
    return File(p.join(sessionsPath, '$sessionId.yaml'));
  }
}
