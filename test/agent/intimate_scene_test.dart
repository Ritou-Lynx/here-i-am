import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/intimate_scene_planner.dart';
import 'package:memex/agent/companion_agent/intimate_scene_state.dart';

void main() {
  group('IntimateScenePhrases', () {
    test('start triggers', () {
      expect(IntimateScenePhrases.matchesStart('我们开始做爱吧'), isTrue);
      expect(IntimateScenePhrases.matchesStart('我们开始吧'), isTrue);
      expect(IntimateScenePhrases.matchesStart('我们来做爱'), isTrue);
      expect(IntimateScenePhrases.matchesStart('开始做爱'), isTrue);
    });

    test('non-triggers do not fire', () {
      expect(IntimateScenePhrases.matchesStart('我们开始打游戏吧'), isFalse);
      expect(IntimateScenePhrases.matchesStart('开始吧'), isFalse);
      expect(IntimateScenePhrases.matchesStart('我们开始做爱吧，今天要激烈一点'),
          isTrue); // start-anchored, long tail still matches
      expect(IntimateScenePhrases.matchesStart('今天天气不错'), isFalse);
      expect(IntimateScenePhrases.matchesStart(''), isFalse);
    });

    test('orgasm signals', () {
      expect(IntimateScenePhrases.matchesOrgasm('我到了'), isTrue);
      expect(IntimateScenePhrases.matchesOrgasm('到了！'), isTrue);
      expect(IntimateScenePhrases.matchesOrgasm('高潮了'), isTrue);
      expect(IntimateScenePhrases.matchesOrgasm('我要去了'), isTrue);
      expect(IntimateScenePhrases.matchesOrgasm('不行了'), isTrue);
    });

    test('orgasm non-signals', () {
      expect(IntimateScenePhrases.matchesOrgasm('我去上班了'), isFalse);
      expect(IntimateScenePhrases.matchesOrgasm('你到了吗'), isFalse);
      expect(IntimateScenePhrases.matchesOrgasm('今天到了公司'), isFalse);
    });
  });

  group('IntimateSceneState', () {
    IntimateScenePlan planWith(List<int> targets) => IntimateScenePlan(
          beats: [
            for (final t in targets)
              IntimateSceneBeat(
                intent: 'beat',
                targetMessageCount: t,
                notes: 'n',
                escalationLevel: 4,
              ),
          ],
        );

    test('start initializes to beat 0 with the first directive', () {
      final s = IntimateSceneState.instance;
      s.end();
      s.start(characterId: 'a', plan: planWith([3, 5]));
      expect(s.isActiveFor('a'), isTrue);
      expect(s.currentBeat!.targetMessageCount, 3);
      final d = s.currentDirective();
      expect(d, contains('场景节拍 1/2'));
      expect(d, contains('第一段'));
      s.end();
    });

    test('turnCompleted advances beat on quota and not before', () {
      final s = IntimateSceneState.instance;
      s.end();
      s.start(characterId: 'a', plan: planWith([2, 4]));
      s.turnCompleted();
      expect(s.currentBeat!.targetMessageCount, 2); // 1/2 written, stays
      s.turnCompleted();
      expect(s.currentBeat!.targetMessageCount, 4); // quota met, advanced
      expect(s.currentDirective(), isNot(contains('第一段')));
      s.end();
    });

    test('aftercare swaps the directive and survives beat position', () {
      final s = IntimateSceneState.instance;
      s.end();
      s.start(characterId: 'a', plan: planWith([2, 2]));
      s.enterAftercare();
      expect(s.phase, IntimateScenePhase.aftercare);
      final d = s.currentDirective();
      expect(d, contains('aftercare'));
      expect(d, contains('不要说"睡吧"'));
      s.end();
    });

    test('end clears everything', () {
      final s = IntimateSceneState.instance;
      s.start(characterId: 'a', plan: planWith([2]));
      s.end();
      expect(s.isActive, isFalse);
      expect(s.isActiveFor('a'), isFalse);
      expect(s.currentDirective(), isEmpty);
      expect(s.currentBeat, isNull);
    });
  });

  group('IntimateSceneBeat.fromJson', () {
    test('clamps out-of-range values', () {
      final beat = IntimateSceneBeat.fromJson({
        'intent': '  x  ',
        'targetMessageCount': 99,
        'escalationLevel': -1,
      });
      expect(beat.intent, 'x');
      expect(beat.targetMessageCount, 10);
      expect(beat.escalationLevel, 0);
    });
  });
}
