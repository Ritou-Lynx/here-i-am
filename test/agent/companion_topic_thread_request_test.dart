import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/topic_thread_request_router.dart';

void main() {
  group('Topic Thread append request detection', () {
    test('recognizes write-back phrasing', () {
      expect(
        TopicThreadRequestRouter.isAppendRequest(
          '整理到这个话题里',
        ),
        isTrue,
      );
      expect(
        TopicThreadRequestRouter.isAppendRequest(
          '把刚才的讨论并入原话题',
        ),
        isTrue,
      );
      expect(
        TopicThreadRequestRouter.isAppendRequest(
          '补进秋招话题吧',
        ),
        isTrue,
      );
    });

    test('does not treat ordinary topic discussion as write-back', () {
      expect(
        TopicThreadRequestRouter.isAppendRequest(
          '接着聊秋招这个话题',
        ),
        isFalse,
      );
      expect(
        TopicThreadRequestRouter.isAppendRequest(
          '我最近在准备秋招',
        ),
        isFalse,
      );
    });
  });
}
