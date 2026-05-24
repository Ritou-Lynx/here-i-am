import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/built_in_tools/checkin_tool.dart';
import 'package:memex/agent/built_in_tools/file_tools.dart';
import 'package:memex/agent/security/file_permission_manager.dart';
import 'package:memex/agent/skills/comment_agent/tools/comment_tools.dart';
import 'package:memex/agent/skills/comment_agent/tools/memory_tools.dart';
import 'package:memex/agent/skills/companion_agent/tools/action_message_tools.dart';

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
    bool includeCheckinTools = false,
  }) {
    final memoryFactory = MemoryToolFactory(
      userId: userId,
      defaultCharacterId: characterId,
    );
    final actionFactory = ActionMessageToolFactory(characterId: characterId);
    final tools = [
      memoryFactory.buildMemoryReadTool(),
      memoryFactory.buildMemoryWriteTool(),
      memoryFactory.buildMemoryEditTool(),
      memoryFactory.buildMemoryRemoveTool(),
      memoryFactory.buildHistorySearchTool(),
      actionFactory.buildSendActionMessageTool(),
      buildReminderTool(),
    ];
    if (includeCheckinTools) {
      tools.add(buildSystemCheckinTool(
          characterId: characterId, characterName: characterName));
      tools.add(buildSetSystemMessageStatusTool());
    }
    return tools;
  }

  static List<Tool> buildCommentTools({
    required String userId,
    required String workingDirectory,
    required String factId,
    String? characterId,
    String? forcedReplyToId,
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
