import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/agent/companion_agent/record_request_matcher.dart';

void main() {
  group('LifeMemoryCapture hard gate', () {
    // The tool gate and the prompt directive must agree, otherwise the model
    // is told to record but the gate rejects it (or worse, the reverse).
    test('shares the matcher with CompanionAgent', () {
      const samples = [
        '你帮我把账记上。',
        '帮我记一下今天的花费。',
        '我今天吃了西塔老太太，花了58块。',
        '我们去了河马，玩得很开心。',
        'save this please',
      ];
      for (final s in samples) {
        expect(
          containsRecordRequest(s),
          CompanionAgent.containsRecordRequestForTesting(s),
          reason: 'gate and directive disagree on: $s',
        );
      }
    });

    test('rejects ordinary chat that a model might over-record', () {
      // These are the shapes that produced unrequested cards: the user is
      // narrating life, not asking for a card.
      expect(containsRecordRequest('明天要去医院复查'), isFalse);
      expect(containsRecordRequest('我最近睡得不太好'), isFalse);
      expect(containsRecordRequest('刚才买了杯咖啡，22块'), isFalse);
      expect(containsRecordRequest('这周三下午有个会'), isFalse);
    });

    test('empty or whitespace-only text is not a record request', () {
      expect(containsRecordRequest(''), isFalse);
      expect(containsRecordRequest('   \n  '), isFalse);
    });

    test('accepts split verb-object phrasing', () {
      expect(containsRecordRequest('把这个记上'), isTrue);
      expect(containsRecordRequest('把刚才那条记上'), isTrue);
      expect(containsRecordRequest('记下来吧'), isTrue);
    });
  });

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
