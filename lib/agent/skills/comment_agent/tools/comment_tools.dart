// ignore_for_file: non_constant_identifier_names

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:uuid/uuid.dart';
import 'package:memex/utils/logger.dart';

class CommentToolFactory {
  final String userId;
  final String cardId;
  final String? characterId;
  final String? forcedReplyToId;
  final void Function()? onCommentSaved;

  CommentToolFactory({
    required this.userId,
    required this.cardId,
    this.characterId,
    this.forcedReplyToId,
    this.onCommentSaved,
  });

  Tool buildSaveCommentTool() {
    final fixedReplyTarget = _normalizedReplyToId(forcedReplyToId);
    return Tool(
      name: 'SaveComment',
      description: fixedReplyTarget == null
          ? 'Saves your comment to the current raw input or reply.'
          : 'Saves your comment as a reply to the current user comment. '
              'The reply_to_id parameter is fixed by the system for this task.',
      parameters: {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': 'The content of your comment.',
          },
          'reply_to_id': {
            'type': 'string',
            'description':
                'Optional. The ID of the comment you are replying to. Leave empty for a top-level comment.',
          },
        },
        'required': ['content'],
      },
      executable: (String content, String? reply_to_id) async {
        if (content.trim().isEmpty) {
          return "Error: Comment content cannot be empty.";
        }

        try {
          final fileSystemService = FileSystemService.instance;
          final commentId = const Uuid().v4();
          final now = DateTime.now();
          final resolvedReplyToId =
              fixedReplyTarget ?? _normalizedReplyToId(reply_to_id);
          CardComment? savedComment;

          final updatedCardData = await fileSystemService.updateCardFile(
            userId,
            cardId,
            (card) {
              final duplicateReply = resolvedReplyToId != null &&
                  card.comments.any((c) =>
                      c.isAi &&
                      c.characterId == characterId &&
                      c.replyToId == resolvedReplyToId);
              if (duplicateReply) {
                return card;
              }

              final newComment = CardComment(
                id: commentId,
                content: content,
                isAi: true,
                timestamp: now.millisecondsSinceEpoch ~/ 1000,
                characterId: characterId,
                replyToId: resolvedReplyToId,
              );
              savedComment = newComment;
              return card.copyWith(comments: [...card.comments, newComment]);
            },
          );

          if (updatedCardData == null) {
            return "Error: Card not found: $cardId";
          }

          if (savedComment == null) {
            _notifyCommentSaved();
            return AgentToolResult(
              content: TextPart("A reply from this character already exists."),
              stopFlag: true,
            );
          }

          _notifyCommentSaved();

          // Log event
          try {
            final cardPath = fileSystemService.getCardPath(userId, cardId);
            final workspacePath = fileSystemService.getWorkspacePath(userId);
            final relativePath = fileSystemService.toRelativePath(
              cardPath,
              rootPath: workspacePath,
            );
            await fileSystemService.eventLogService.logFileModified(
              userId: userId,
              filePath: relativePath,
              description: 'AI comment added to card via tool',
              metadata: {
                'card_id': cardId,
                'comment_id': savedComment!.id,
                'character_id': characterId,
                'content': savedComment!.content,
              },
            );
          } catch (e) {
            getLogger('CommentTool').warning('Failed to log event: $e');
          }

          return AgentToolResult(
            content: TextPart("Comment saved successfully."),
            stopFlag: true,
          );
        } catch (e) {
          return "Error saving comment: $e";
        }
      },
    );
  }

  static String? _normalizedReplyToId(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _notifyCommentSaved() {
    try {
      onCommentSaved?.call();
    } catch (e) {
      getLogger('CommentTool').warning('Failed to notify comment save: $e');
    }
  }
}
