import 'dart:async';

import 'package:memex/data/repositories/post_comment.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:test/test.dart';

void main() {
  group('waitForCommentAgentCompletion', () {
    test('finishes after a saved comment even if agent shutdown hangs',
        () async {
      final agentRun = Completer<void>();
      final commentSaved = Completer<void>()..complete();

      await waitForCommentAgentCompletion(
        agentRun: agentRun.future,
        commentSaved: commentSaved.future,
        stopGracePeriod: const Duration(milliseconds: 1),
        maxRunDuration: const Duration(seconds: 1),
      );
    });

    test('propagates an agent failure before any durable save', () async {
      final commentSaved = Completer<void>();

      await expectLater(
        waitForCommentAgentCompletion(
          agentRun: Future<void>.error(StateError('agent failed')),
          commentSaved: commentSaved.future,
          stopGracePeriod: const Duration(milliseconds: 1),
          maxRunDuration: const Duration(seconds: 1),
        ),
        throwsStateError,
      );
    });
  });

  group('hasNewMatchingAiComment', () {
    const existing = CardComment(
      id: 'existing-ai',
      content: 'Existing reply',
      isAi: true,
      timestamp: 1,
      characterId: 'char-a',
      replyToId: 'user-comment',
    );
    const added = CardComment(
      id: 'new-ai',
      content: 'New reply',
      isAi: true,
      timestamp: 2,
      characterId: 'char-a',
      replyToId: 'user-comment',
    );

    test('accepts a newly saved reply from the expected character', () {
      expect(
        hasNewMatchingAiComment(
          comments: const [existing, added],
          previousCommentIds: const {'existing-ai'},
          characterId: 'char-a',
          replyToId: 'user-comment',
        ),
        isTrue,
      );
    });

    test('rejects a text-only run that did not save a new comment', () {
      expect(
        hasNewMatchingAiComment(
          comments: const [existing],
          previousCommentIds: const {'existing-ai'},
          characterId: 'char-a',
          replyToId: 'user-comment',
        ),
        isFalse,
      );
    });

    test('rejects a reply saved for the wrong user comment', () {
      expect(
        hasNewMatchingAiComment(
          comments: const [existing, added],
          previousCommentIds: const {'existing-ai'},
          characterId: 'char-a',
          replyToId: 'different-user-comment',
        ),
        isFalse,
      );
    });
  });
}
