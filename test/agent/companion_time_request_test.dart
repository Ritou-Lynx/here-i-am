import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';

void main() {
  group('CompanionAgent time request detection', () {
    test('keeps deadline bets as chat context', () {
      expect(
        CompanionAgent.containsTimeRequestForTesting(
          '我今天 10 点要到公司，但是现在已经 9 点 44 了，我们来打个赌，看我能不能准时到公司。',
        ),
        isFalse,
      );
    });

    test('does not turn bare future events into reminders', () {
      expect(
        CompanionAgent.containsTimeRequestForTesting('我下午三点开会，先陪我聊两句。'),
        isFalse,
      );
      expect(
        CompanionAgent.containsTimeRequestForTesting('我明天要面试，有点紧张。'),
        isFalse,
      );
    });

    test('detects explicit scheduled reminder or check-in requests', () {
      expect(
        CompanionAgent.containsTimeRequestForTesting('10点提醒我看有没有迟到。'),
        isTrue,
      );
      expect(
        CompanionAgent.containsTimeRequestForTesting('十分钟后叫我出门。'),
        isTrue,
      );
      expect(
        CompanionAgent.containsTimeRequestForTesting('到10点的时候问我到没到公司。'),
        isTrue,
      );
      expect(
        CompanionAgent.containsTimeRequestForTesting('call me in 30 minutes'),
        isTrue,
      );
    });

    test('only treats explicit future action promises as time commitments', () {
      expect(
        CompanionAgent.containsTimeCommitmentForTesting('你还有16分钟，我押你能到。'),
        isFalse,
      );
      expect(
        CompanionAgent.containsTimeCommitmentForTesting('我会在10点提醒你有没有迟到。'),
        isTrue,
      );
      expect(
        CompanionAgent.containsTimeCommitmentForTesting('10点我来问你到没到。'),
        isTrue,
      );
    });
  });
}
