import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/built_in_tools/ai_finance_tools.dart';
import 'package:memex/agent/built_in_tools/ai_shopping_tools.dart';
import 'package:memex/agent/built_in_tools/checkin_tool.dart';
import 'package:memex/agent/built_in_tools/coros_mcp_tool.dart';
import 'package:memex/agent/built_in_tools/delegate_task_tool.dart';
import 'package:memex/agent/built_in_tools/dev_session_tool.dart';
import 'package:memex/agent/built_in_tools/device_app_blocker_tool.dart';
import 'package:memex/agent/built_in_tools/file_tools.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/built_in_tools/phone_usage_tool.dart';
import 'package:memex/agent/built_in_tools/reading_content_tool.dart';
import 'package:memex/agent/built_in_tools/shared_life_memory_tools.dart';
import 'package:memex/agent/built_in_tools/toy_control_tool.dart';
import 'package:memex/agent/built_in_tools/transit_companion_tools.dart';
import 'package:memex/agent/built_in_tools/user_knowledge_query_tool.dart';
import 'package:memex/agent/built_in_tools/web_search_tool.dart';
import 'package:memex/agent/built_in_tools/weread_tool.dart';
import 'package:memex/agent/security/file_permission_manager.dart';
import 'package:memex/agent/skills/comment_agent/tools/comment_tools.dart';
import 'package:memex/agent/skills/comment_agent/tools/memory_tools.dart';
import 'package:memex/agent/skills/companion_agent/tools/action_message_tools.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/data/services/conversation_capture_service.dart';
import 'package:memex/data/services/reading/reading_fetch_coordinator.dart';
import 'package:memex/data/services/remote_task_service.dart';
import 'package:memex/data/services/toy_control_service.dart'
    show ToyController;
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
  }) {
    final memoryFactory = MemoryToolFactory(
      userId: userId,
      defaultCharacterId: characterId,
    );
    final actionFactory = ActionMessageToolFactory(characterId: characterId);
    final financeService = AiFinanceService(db: AppDatabase.instance);
    final remoteTaskService = RemoteTaskService(db: AppDatabase.instance);
    final tools = [
      memoryFactory.buildMemoryReadTool(),
      memoryFactory.buildMemoryWriteTool(),
      memoryFactory.buildMemoryEditTool(),
      memoryFactory.buildMemoryRemoveTool(),
      memoryFactory.buildHistorySearchTool(),
      buildUserKnowledgeQueryTool(userId: userId),
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
      buildCorosMcpTool(),
      buildWereadTool(userId: userId),
      buildPhoneUsageQueryTool(),
      buildWebSearchTool(),
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
      ...buildTransitCompanionTools(characterId: characterId),
    ];
    if (toyControlService != null) {
      tools.add(buildToyControlTool(service: toyControlService));
    }
    if (ConversationCaptureService.isInitialized) {
      tools.addAll(
        buildSharedLifeMemoryTools(
          service: ConversationCaptureService.instance.sharedLifeMemory,
          sourceCharacterId: characterId,
          userId: userId,
          sourceMessageId: currentUserMessageId,
        ),
      );
      if (ReadingFetchCoordinator.isInitialized) {
        tools.add(buildLoadReadingContentTool(
          sharedLifeMemory:
              ConversationCaptureService.instance.sharedLifeMemory,
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

    if (characterId != null) {
      final memoryFactory = MemoryToolFactory(
        userId: userId,
        defaultCharacterId: characterId,
      );
      tools.add(memoryFactory.buildMemoryReadTool());
      tools.add(memoryFactory.buildMemoryWriteTool());
      tools.add(memoryFactory.buildMemoryEditTool());
      tools.add(memoryFactory.buildMemoryRemoveTool());
      tools.add(memoryFactory.buildHistorySearchTool());
    }

    return tools;
  }
}
