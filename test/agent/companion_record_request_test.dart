import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';

void main() {
  group('CompanionAgent record request detection', () {
    test('detects explicit record/记账 requests', () {
      expect(
        CompanionAgent.containsRecordRequestForTesting('你帮我把账记上。'),
        isTrue,
      );
      expect(
        CompanionAgent.containsRecordRequestForTesting('帮我记一下今天的花费。'),
        isTrue,
      );
      expect(
        CompanionAgent.containsRecordRequestForTesting('记一下'),
        isTrue,
      );
      expect(
        CompanionAgent.containsRecordRequestForTesting('帮我记账'),
        isTrue,
      );
      expect(
        CompanionAgent.containsRecordRequestForTesting('save this please'),
        isTrue,
      );
    });

    test('does not treat ordinary mentions of facts as record requests', () {
      expect(
        CompanionAgent.containsRecordRequestForTesting('我今天吃了西塔老太太，花了58块。'),
        isFalse,
      );
      expect(
        CompanionAgent.containsRecordRequestForTesting('我们去了河马，玩得很开心。'),
        isFalse,
      );
    });

    test('detects claims that a record was saved', () {
      expect(
        CompanionAgent.containsRecordCommitmentForTesting('记上了，而且提示我已保存至记录，可前往 review 查看。'),
        isTrue,
      );
      expect(
        CompanionAgent.containsRecordCommitmentForTesting('好的，已经记好了！'),
        isTrue,
      );
      expect(
        CompanionAgent.containsRecordCommitmentForTesting('已保存至记录，可前往 Review 查看'),
        isTrue,
      );
    });

    test('does not flag ordinary chat replies as record commitments', () {
      expect(
        CompanionAgent.containsRecordCommitmentForTesting('今天天气不错，你吃饭了吗？'),
        isFalse,
      );
      expect(
        CompanionAgent.containsRecordCommitmentForTesting('好呀，我们等会儿再聊这个。'),
        isFalse,
      );
    });
  });
}
