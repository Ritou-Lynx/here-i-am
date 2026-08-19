import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/built_in_tools/ai_finance_tools.dart';
import 'package:memex/agent/built_in_tools/ai_shopping_tools.dart';
import 'package:memex/agent/built_in_tools/checkin_tool.dart';
import 'package:memex/agent/built_in_tools/continuous_reply_tool.dart';
import 'package:memex/agent/built_in_tools/coros_mcp_tool.dart';
import 'package:memex/agent/built_in_tools/delegate_task_tool.dart';
import 'package:memex/agent/built_in_tools/dev_session_tool.dart';
import 'package:memex/agent/built_in_tools/device_app_blocker_tool.dart';
import 'package:memex/agent/built_in_tools/file_tools.dart';
import 'package:memex/agent/built_in_tools/get_current_location_tool.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/built_in_tools/mobility_route_tool.dart';
import 'package:memex/agent/built_in_tools/phone_usage_tool.dart';
import 'package:memex/agent/built_in_tools/reading_content_tool.dart';
import 'package:memex/agent/built_in_tools/toy_control_tool.dart';
import 'package:memex/agent/built_in_tools/transit_companion_tools.dart';
import 'package:memex/agent/built_in_tools/weather_risk_tool.dart';
import 'package:memex/agent/built_in_tools/web_search_tool.dart';
import 'package:memex/agent/built_in_tools/generate_image_tool.dart';
import 'package:memex/agent/built_in_tools/send_sticker_tool.dart';
import 'package:memex/agent/built_in_tools/memory_v3_delete_card_tool.dart';
import 'package:memex/agent/built_in_tools/memory_v3_query_tool.dart';
import 'package:memex/agent/built_in_tools/memory_v3_update_card_tool.dart';
import 'package:memex/agent/built_in_tools/project_memory_query_tool.dart';
import 'package:memex/agent/built_in_tools/topic_thread_tool.dart';
import 'package:memex/agent/security/file_permission_manager.dart';
import 'package:memex/agent/skills/comment_agent/tools/comment_tools.dart';
import 'package:memex/agent/skills/companion_agent/tools/action_message_tools.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/reading/reading_fetch_coordinator.dart';
import 'package:memex/data/services/remote_task_service.dart';
import 'package:memex/data/services/toy_control_service.dart'
    show ToyController;
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/db/app_database.dart';

class CharacterToolsFactory {
  CharacterToolsFactory._();

  /// Build tools for the companion chat agent.
  ///
  /// [includeCheckinTools] should be true only when there are pending system
  /// checkin triggers to process. When false, `system_checkin` and
  /// `set_system_message_status` are excluded so the LLM cannot call them
  /// during normal user-facing chat turns.
  static List<Tool> buildCompanionTools({
    required String userId,
    required String characterId,
    String? characterName,
    int? currentUserMessageId,
    bool includeCheckinTools = false,
    ToyController? toyControlService,
    InitiateCallPolicy? initiateCallPolicy,
    List<String>? turnImageAnalyses,
  }) {
    final actionFactory = ActionMessageToolFactory(characterId: characterId);
    final financeService = AiFinanceService(db: AppDatabase.instance);
    final remoteTaskService = RemoteTaskService(db: AppDatabase.instance);
    final tools = [
      actionFactory.buildSendActionMessageTool(),
      buildReminderTool(characterId: characterId, characterName: characterName),
      buildDelegateTaskTool(
        userId: userId,
        characterId: characterId,
        characterName: characterName ?? 'Companion',
      ),
      buildDevSessionStartOrContinueTool(
        characterId: characterId,
        characterName: characterName ?? 'Companion',
      ),
      buildAiFinanceRecordTool(
          characterId: characterId, service: financeService),
      buildAiFinanceQueryTool(
          characterId: characterId, service: financeService),
      buildAiFinanceRewardTool(
          characterId: characterId, service: financeService),
      buildAiFinancePenaltyTool(
          characterId: characterId, service: financeService),
      buildAiFinanceTransferTool(
          characterId: characterId, service: financeService),
      buildAiFinanceCorrectTool(
          characterId: characterId, service: financeService),
      buildAiFinanceDeleteTool(
          characterId: characterId, service: financeService),
      buildCorosMcpTool(),
      buildPhoneUsageQueryTool(),
      buildWebSearchTool(),
      buildGenerateImageTool(characterId: characterId),
      buildSendStickerTool(characterId: characterId),
      // Autonomous shopping tools (budget gate enforced in service, not just prompt)
      buildShoppingBudgetTool(characterId: characterId),
      buildShoppingSearchTool(),
      buildShoppingPlaceOrderTool(
        characterId: characterId,
        characterName: characterName,
        remoteTaskService: remoteTaskService,
      ),
      buildShoppingPushPaymentTool(characterId: characterId),
      buildShoppingHistoryTool(characterId: characterId),
      buildShoppingStatusSyncTool(
        characterId: characterId,
        remoteTaskService: remoteTaskService,
      ),
      buildDeviceAppBlockerTool(),
      buildGetCurrentLocationTool(),
      buildWeatherOutingRiskTool(),
      buildNearbyPlaceSearchTool(),
      buildMobilityRoutePlanTool(),
      ...buildTransitCompanionTools(characterId: characterId),
      buildContinuousReplyTool(),
    ];
    if (toyControlService != null) {
      tools.add(buildToyControlTool(service: toyControlService));
    }
    if (RecordOrganizerServiceV3.isInitialized) {
      tools.add(_buildLifeMemoryCaptureTool(
          currentUserMessageId: currentUserMessageId,
          turnImageAnalyses: turnImageAnalyses));
      tools.add(
          buildMemoryV3QueryTool(currentUserMessageId: currentUserMessageId));
      tools.add(buildMemoryV3UpdateCardTool());
      tools.add(buildMemoryV3DeleteCardTool());
      tools.add(buildProjectMemoryQueryTool(
          currentUserMessageId: currentUserMessageId));
    }
    if (AppDatabase.isInitialized) {
      tools.add(buildTopicThreadCreateTool());
      tools.add(buildTopicThreadRecallTool(
        characterId: characterId,
        currentUserMessageId: currentUserMessageId,
      ));
      tools.add(buildTopicThreadAppendSessionTool(
        characterId: characterId,
        characterName: characterName ?? '林埃',
        currentUserMessageId: currentUserMessageId,
      ));
    }
    if (SharedLifeMemoryService.isInitialized &&
        !RecordOrganizerServiceV3.isInitialized) {
      final sharedLifeMemory = SharedLifeMemoryService.instance;
      // Legacy LifeMemoryQuery — only when V3 is NOT active.
      tools.add(_buildLifeMemoryQueryTool(service: sharedLifeMemory));
      if (ReadingFetchCoordinator.isInitialized) {
        tools.add(buildLoadReadingContentTool(
          sharedLifeMemory: sharedLifeMemory,
          fetchCoordinator: ReadingFetchCoordinator.instance,
        ));
      }
    }
    if (includeCheckinTools) {
      tools.add(buildSystemCheckinTool(
          characterId: characterId, characterName: characterName));
      tools.add(buildSetSystemMessageStatusTool());
      tools.add(buildInitiateCallTool(
        characterId: characterId,
        beforeQueue: initiateCallPolicy,
      ));
    }
    return tools;
  }

  static List<Tool> buildCommentTools({
    required String userId,
    required String workingDirectory,
    required String factId,
    String? characterId,
    String? forcedReplyToId,
    void Function()? onCommentSaved,
    bool includeSaveCommentTool = true,
    bool includeFileTools = true,
  }) {
    final tools = <Tool>[];

    if (includeFileTools) {
      final permissionManager = FilePermissionManager(userId, [
        PermissionRule(rootPath: workingDirectory, access: FileAccessType.read),
      ]);
      final fileFactory = FileToolFactory(
        permissionManager: permissionManager,
        workingDirectory: workingDirectory,
      );
      tools.add(fileFactory.buildReadTool());
      tools.add(fileFactory.buildGrepTool());
    }

    if (includeSaveCommentTool) {
      final commentFactory = CommentToolFactory(
        userId: userId,
        cardId: factId,
        characterId: characterId,
        forcedReplyToId: forcedReplyToId,
        onCommentSaved: onCommentSaved,
      );
      tools.add(commentFactory.buildSaveCommentTool());
    }

    return tools;
  }

  /// V3 tool: Agent calls this when user explicitly asks to record something.
  /// The tool passes raw text to [RecordOrganizerServiceV3.organizeAndPersist]
  /// which handles structuring via its own LLM pass.
  ///
  /// [turnImageAnalyses] is the list of image-analysis texts from the current
  /// turn's attachments. When non-empty, they are appended to the LLM-supplied
  /// `text` as an `[Image analysis: ...]` block so the downstream Record
  /// Organizer can see exactly what was in the image — without relying on the
  /// companion LLM to faithfully transcribe it into the `text` parameter.
  static Tool _buildLifeMemoryCaptureTool({
    int? currentUserMessageId,
    List<String>? turnImageAnalyses,
  }) {
    return Tool(
      name: 'LifeMemoryCapture',
      description:
          'Save a user-confirmed fact/event as a User-truth Memory Card. '
          'ONLY call when the user explicitly asks to record/save/remember. '
          'Phrases: "记一下"、"帮我记"、"记录一下"、"保存一下"、"存一下"、'
          '"加到记录里"、"记住这个"、"帮我记账".\n'
          '\n'
          'CRITICAL — NO FABRICATION:\n'
          'The `text` field must contain ONLY what the user actually said or '
          'what is visible in an image they attached. Never infer, guess, or '
          'add details the user did not provide. If the user said "买了安睡裤 '
          '8.5元" and attached a screenshot, you may include facts visible in '
          'the screenshot (merchant name, product name, price). But you MUST '
          'NOT invent product names, store names, or amounts that are neither '
          'in the user\'s words nor in an attached image. When unsure whether '
          'a detail is from the user or your own inference, omit it.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': 'A self-contained Chinese description of what to record. '
                'Include ONLY facts the user stated or that are visible in an '
                'attached image. Do NOT synthesize, infer, or fabricate. '
                'If you saw an [Image analysis: ...] block in this turn, you '
                'may include facts from it, but keep them factual — do not '
                'embellish. Example: user said "帮我记一下" with an attached '
                'receipt screenshot showing "关东煮 5元, 茶叶蛋 4元" → pass '
                '"早上买早餐：关东煮5元，茶叶蛋4元，共9元". '
                'NEVER pass "惠邻百佳超市" or a product brand the user did not '
                'say unless it is literally visible in the attached image.',
          },
        },
        'required': ['text'],
      },
      parameterMode: ToolParameterMode.object,
      executable: (Map<String, dynamic> args) async {
        try {
          final text = args['text'] as String?;
          if (text == null || text.trim().isEmpty) {
            return jsonEncode({'success': false, 'error': 'empty text'});
          }
          var rawInput = text;
          if (turnImageAnalyses != null && turnImageAnalyses.isNotEmpty) {
            final analysisBlock =
                turnImageAnalyses.where((a) => a.trim().isNotEmpty).join(' | ');
            if (analysisBlock.isNotEmpty) {
              rawInput = '$text\n[图片内容：$analysisBlock]';
            }
          }
          final resources = await UserStorage.getAgentLLMResources(
            AgentDefinitions.recordOrganizerAgent,
            defaultClientKey: LLMConfig.defaultClientKey,
          );
          // Resolve stable sync_id for the triggering chat message so the
          // Memory Card source row is dual-written with a cross-device ref.
          String? syncId;
          final messageId = currentUserMessageId;
          if (messageId != null) {
            final row = await (AppDatabase.instance.select(
                    AppDatabase.instance.personaChatMessages)
                  ..where((t) => t.id.equals(messageId)))
                .getSingleOrNull();
            syncId = row?.syncId;
            if (syncId != null && syncId.isEmpty) syncId = null;
          }
          final result =
              await RecordOrganizerServiceV3.instance.organizeAndPersist(
            client: resources.client,
            modelConfig: resources.modelConfig,
            source: RecordSource(
              sourceKind: 'chat_message',
              rawInput: rawInput,
              sourceRef: currentUserMessageId?.toString(),
              sourceSyncId: syncId,
            ),
          );
          return jsonEncode({
            'success': !result.isEmpty,
            'card_count': result.cardIds.length,
          });
        } catch (e) {
          return jsonEncode({'success': false, 'error': e.toString()});
        }
      },
    );
  }

  /// Keep the v2 query tool for read-only lookup. Write tools are superseded by
  /// [_buildLifeMemoryCaptureTool].
  static Tool _buildLifeMemoryQueryTool({
    required SharedLifeMemoryService service,
  }) {
    return Tool(
      name: 'LifeMemoryQuery',
      description: 'Query existing shared life records. Use this to check for '
          'existing records before creating new ones, or to find context relevant '
          'to the ongoing conversation.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Natural language query to find matching records.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results to return. Default 5, max 20.',
          },
        },
        'required': ['query'],
      },
      parameterMode: ToolParameterMode.object,
      executable: (Map<String, dynamic> args) async {
        try {
          final query = args['query'] as String? ?? '';
          final limit = (args['limit'] as int?) ?? 5;
          final entities = await service.queryRelevantEntities(
            query,
            limit: limit.clamp(1, 20),
          );
          return jsonEncode({
            'results': entities
                .map((e) => {
                      'id': e.id,
                      'title': e.title,
                      'type': e.entityType,
                      'status': e.status,
                    })
                .toList(),
          });
        } catch (e) {
          return jsonEncode({'error': e.toString()});
        }
      },
    );
  }
}
