import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/agent_system_prompt_helper.dart';
import 'package:memex/agent/built_in_tools/file_tools.dart';
import 'package:memex/agent/built_in_tools/search_event_logs_tool.dart';
import 'package:memex/agent/common_tools.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/agent/security/file_permission_manager.dart';
import 'package:memex/agent/state_util.dart';
import 'package:memex/agent/skills/ask_clarification/ask_clarification_skill.dart';
import 'package:memex/agent/skills/manage_pkm/pkm_skill.dart';
import 'package:memex/agent/skills/manage_system_action/system_action_skill.dart';
import 'package:memex/agent/skills/manage_timeline_card/timeline_card_skill.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final Logger _logger = getLogger('CompanionDelegation');

const _cardOpsDirective = '''
## Delegation Directive — Card Operations

You are processing a card/PKM operation delegated by a companion character.
The user wants to **modify, create, archive, or organize records**.

Your tools allow you to create and edit timeline cards, organize PKM structure,
and manage system actions. Use them freely.

**Rules:**
- Execute the request directly. Do not ask for clarification.
- Cards you create or modify will appear in the user's Review tab.
- Summarize what you did in 1-3 sentences in Chinese.
- Reference fact_ids of any cards you touched.
- If you cannot complete the request, explain why.
''';

const _insightDirective = '''
## Delegation Directive — Insight Generation

You are generating a one-shot analysis or summary. The user asked the companion
a question that requires looking at their data and producing insights.

**Critical: your output is TEXT ONLY — it appears in the chat, NOT in the
Review tab. Do NOT create card files, do NOT save to disk.**

Your tools are read-only: search, read, and analyze existing records. Use them
to gather relevant data, then produce a well-structured Markdown summary as your
final text response.

**Rules:**
- Search and read relevant records to answer the user's question.
- Produce a clear, well-organized Markdown response directly in your text output.
- Use Chinese. Include specific numbers, dates, or fact_ids where relevant.
- Do NOT use any write tools or skills — your response IS the final output.
- If you don't have enough data to answer, explain what's missing.
''';

const _queryDirective = '''
## Delegation Directive — Information Query

You are answering a factual question. The user wants to **find or verify
information** in their existing records.

Your tools are read-only: search and read. Find the relevant information and
answer concisely.

**Rules:**
- Search and read relevant records.
- Answer the question directly in 1-3 sentences in Chinese.
- Include specific fact_ids, dates, or file paths where you found the info.
- Do NOT modify anything — this is read-only.
- If you cannot find the answer, say so clearly.
''';

Future<void> handleCompanionDelegation(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final description = payload['description'] as String? ?? '';
  final extraContext = payload['context'] as String?;
  final characterId = payload['character_id'] as String? ?? '';
  final taskCategory = payload['task_category'] as String? ?? 'card_ops';

  _logger.info('Handling delegation [$taskCategory]: "$description"');

  try {
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.cardAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );

    final client = resources.client;
    final modelConfig = resources.modelConfig;
    final fileService = FileSystemService.instance;
    final workingDirectory = fileService.getWorkspacePath(userId);

    final isReadOnly = taskCategory != 'card_ops';
    final access = isReadOnly ? FileAccessType.read : FileAccessType.write;

    final permissionManager = FilePermissionManager(userId, [
      PermissionRule(rootPath: workingDirectory, access: access),
    ]);

    final fileToolFactory = FileToolFactory(
      permissionManager: permissionManager,
      workingDirectory: workingDirectory,
    );

    final tools = <Tool>[
      fileToolFactory.buildLSTool(),
      fileToolFactory.buildGlobTool(),
      fileToolFactory.buildGrepTool(),
      fileToolFactory.buildReadTool(),
      fileToolFactory.buildBatchReadTool(),
      buildSearchEventLogsTool(),
      getCurrentTimeTool,
      getPkmOverviewTool,
    ];

    if (!isReadOnly) {
      tools.addAll([
        fileToolFactory.buildWriteTool(),
        fileToolFactory.buildMoveTool(),
        fileToolFactory.buildRemoveTool(),
        fileToolFactory.buildEditTool(),
      ]);
    }

    final memoryManagement = await MemoryManagement.createDefault(
      userId: userId,
      sourceAgent: 'companion_delegation',
    );
    final memoryPrompt = await memoryManagement.buildMemoryPrompt();
    final memoryTools = memoryManagement.buildMemoryManagementTools();
    tools.addAll(memoryTools);

    final controller = AgentController();
    addAgentLogger(controller);
    addAgentActivityCollector(controller);

    final sessionId =
        'companion_delegation_${userId}_${context.taskId}_${DateTime.now().microsecondsSinceEpoch}';
    final state = await loadOrCreateAgentState(sessionId, {
      'userId': userId,
      'agentName': 'companion_delegation',
      'scene': 'companion_delegation',
      'sceneId': context.taskId,
    });
    state.systemReminders['user_memory'] = memoryPrompt;

    // Build category-specific skills and directive.
    final List<Skill> skills;
    final String directive;

    switch (taskCategory) {
      case 'card_ops':
        skills = [
          TimelineCardSkill(stopAfterSuccessSaveCard: true),
          PkmSkill(workingDirectory: '/PKM'),
          SystemActionSkill(),
          AskClarificationSkill(),
        ];
        directive = _cardOpsDirective;
        break;
      case 'insight':
        skills = [];
        directive = _insightDirective;
        break;
      case 'query':
        skills = [];
        directive = _queryDirective;
        break;
      default:
        skills = [];
        directive = _queryDirective;
    }

    final userInstruction = StringBuffer();
    userInstruction.writeln('## User Request (via Companion)');
    userInstruction.writeln(description);
    if (extraContext != null && extraContext.isNotEmpty) {
      userInstruction.writeln();
      userInstruction.writeln('### Additional Context');
      userInstruction.writeln(extraContext);
    }

    final agent = StatefulAgent(
      name: 'companion_delegation',
      client: client,
      modelConfig: modelConfig,
      state: state,
      compressor: LLMBasedContextCompressor(
        client: client,
        modelConfig: modelConfig,
        totalTokenThreshold: 64000,
        keepRecentMessageSize: 10,
      ),
      tools: tools,
      skills: skills,
      systemPrompts: [directive, memoryPrompt],
      disableSubAgents: true,
      controller: controller,
      withGeneralPrinciples: true,
      planMode: PlanMode.auto,
      autoSaveStateFunc: (_) async {},
      systemCallback: createSystemCallback(userId),
    );

    await agent.run([
      UserMessage.text(userInstruction.toString()),
    ], useStream: false);

    // Extract the last model text from the run history.
    var agentOutput = '';
    final messages = state.history.messages;
    if (taskCategory == 'card_ops' &&
        !_hasSuccessfulToolCall(messages, 'save_timeline_card')) {
      throw StateError(
        'Card operation finished without saving a timeline card.',
      );
    }
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg is ModelMessage && msg.textOutput != null) {
        agentOutput = msg.textOutput!;
        break;
      }
    }
    final summary = agentOutput.isNotEmpty ? agentOutput : '操作已完成。';

    await LocalTaskExecutor.instance.updateTaskResult(
      context.taskId,
      jsonEncode({
        'summary': summary,
        'task_category': taskCategory,
        'character_id': characterId,
      }),
    );

    final catLabel = taskCategory == 'card_ops'
        ? '整理完成'
        : taskCategory == 'insight'
            ? '洞察已生成'
            : '查询完成';
    if (AgentActivityService.isInitialized) {
      await AgentActivityService.instance.pushMessage(
        type: AgentActivityType.agent_stop,
        title: catLabel,
        content: summary,
        agentName: 'companion_delegation',
        agentId: characterId,
        userId: userId,
      );
    }

    if (characterId.isNotEmpty) {
      final suffix =
          taskCategory == 'card_ops' ? '\n\n（已保存至记录，可前往 Review 查看）' : '';
      await PersonaChatService.instance.addCharacterMessage(
        characterId,
        '$summary$suffix',
        timestamp: DateTime.now(),
        isRead: false,
      );
    }

    EventBusService.instance.emitEvent(
      PersonaChatMessageAddedMessage(characterId: characterId),
    );

    _logger.info('Delegation complete [$taskCategory]: "$description"');
  } catch (e, stack) {
    _logger.severe(
        'Delegation failed [$taskCategory]: "$description"', e, stack);

    if (characterId.isNotEmpty) {
      try {
        await PersonaChatService.instance.addCharacterMessage(
          characterId,
          '抱歉，「$description」处理失败了，请稍后重试。',
          timestamp: DateTime.now(),
          isRead: false,
        );
      } catch (_) {}
    }

    rethrow;
  }
}

bool _hasSuccessfulToolCall(List<LLMMessage> messages, String toolName) {
  for (final msg in messages) {
    if (msg is! FunctionExecutionResultMessage) continue;
    for (final result in msg.results) {
      if (!result.isError && result.name == toolName) return true;
    }
  }
  return false;
}

Future<void> handleCompanionDelegationFailure(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
  Object error,
  StackTrace? stackTrace,
) async {
  _logger.severe('Delegation permanently failed', error, stackTrace);

  final characterId = payload['character_id'] as String? ?? '';
  final description = payload['description'] as String? ?? '';

  if (characterId.isNotEmpty) {
    try {
      await PersonaChatService.instance.addCharacterMessage(
        characterId,
        '抱歉，「$description」处理失败了，请稍后重试。',
        timestamp: DateTime.now(),
        isRead: false,
      );
    } catch (_) {}
  }
}
