import 'workbench_conversation_coordinator.dart';
import 'workbench_desktop_user_message_store.dart';

typedef PersonaDesktopConversationConnector
    = Future<WorkbenchConversationResult> Function({
  required WorkbenchConversationCoordinator coordinator,
  required String conversationId,
  required String characterId,
  required String userText,
  required int userMessageId,
  WorkbenchReplyDelta? onDelta,
});

Future<WorkbenchConversationResult> connectPersonaDesktopConversation({
  required WorkbenchConversationCoordinator coordinator,
  required String conversationId,
  required String characterId,
  required String userText,
  required int userMessageId,
  WorkbenchReplyDelta? onDelta,
}) =>
    coordinator.send(
      conversationId: conversationId,
      characterId: characterId,
      userText: userText,
      userMessageId: userMessageId,
      onDelta: onDelta,
    );

/// Persist the user's original input before Runtime sees the turn. Queue
/// authority is derived from that input and conversation; whiteboard authority
/// additionally binds the persisted row id inside the coordinator.
Future<WorkbenchConversationResult> sendPersonaDesktopConversationEntry({
  required WorkbenchDesktopUserMessageStore chatService,
  required WorkbenchConversationCoordinator coordinator,
  required String conversationId,
  required String characterId,
  required String userText,
  PersonaDesktopConversationConnector connector =
      connectPersonaDesktopConversation,
  Future<void> Function(int messageId)? afterPersist,
  WorkbenchReplyDelta? onDelta,
}) async {
  final userMessageId = await chatService.addUserMessage(
    characterId,
    userText,
    appendTimeline: false,
  );
  await afterPersist?.call(userMessageId);
  return connector(
    coordinator: coordinator,
    conversationId: conversationId,
    characterId: characterId,
    userText: userText,
    userMessageId: userMessageId,
    onDelta: onDelta,
  );
}
