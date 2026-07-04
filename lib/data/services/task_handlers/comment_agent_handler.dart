import 'package:logging/logging.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/repositories/post_comment.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/utils/time_context.dart';

final _logger = Logger('CommentAgentHandler');

Future<void> handleCommentAgentImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final factId = payload['fact_id'] as String?;
  _logger.info(
    'Comment Agent auto-comments are disabled; skipping fact ${factId ?? "(unknown)"}.',
  );
}

/// Handler for process_ai_reply task
Future<void> handleProcessAiReplyImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final cardId = payload['card_id'] as String;
  final content = payload['content'] as String;
  final commentId = payload['comment_id'] as String?;
  final replyToId = payload['reply_to_id'] as String?;
  final inputDateTime = tryParseUnixSeconds(payload['created_at_ts']);
  final locationContextReminder =
      payload['location_context_reminder'] as String?;

  _logger.info(
    'HandleProcessAiReply: Processing AI reply for card $cardId, user $userId',
  );

  // If the user replied to a specific comment, resolve the target character
  String? targetCharacterId;
  if (replyToId != null) {
    try {
      final cardData = await FileSystemService.instance.readCardFile(
        userId,
        cardId,
      );
      if (cardData != null) {
        for (final c in cardData.comments) {
          if (c.id == replyToId && c.isAi && c.characterId != null) {
            targetCharacterId = c.characterId;
            _logger.info(
              'User replied to comment $replyToId, routing to character $targetCharacterId',
            );
            break;
          }
        }
      }
    } catch (e) {
      _logger.warning('Failed to resolve reply target character: $e');
    }
  }

  if (commentId != null &&
      targetCharacterId != null &&
      await _hasExistingAiReply(
        userId: userId,
        cardId: cardId,
        userCommentId: commentId,
        characterId: targetCharacterId,
      )) {
    _logger.info(
      'AI reply already exists for user comment $commentId from character '
      '$targetCharacterId; skipping duplicate task ${context.taskId}',
    );
    return;
  }

  try {
    await processAICommentReply(
      cardId: cardId,
      userId: userId,
      userContent: content,
      userCommentId: commentId,
      characterId: targetCharacterId,
      inputDateTime: inputDateTime,
      locationContextReminder: locationContextReminder,
      withMemoryManagement: true,
    );
  } catch (e, stack) {
    _logger.severe('HandleProcessAiReply failed: $e', e, stack);
    rethrowIfNonRetryable(e);
  }
}

Future<bool> _hasExistingAiReply({
  required String userId,
  required String cardId,
  required String userCommentId,
  required String characterId,
}) async {
  final cardData = await FileSystemService.instance.readCardFile(
    userId,
    cardId,
  );
  if (cardData == null) return false;

  return cardData.comments.any(
    (c) =>
        c.isAi && c.characterId == characterId && c.replyToId == userCommentId,
  );
}
