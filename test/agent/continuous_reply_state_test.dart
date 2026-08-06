import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/continuous_reply_tool.dart';

void main() {
  group('ContinuousModeState', () {
    test('request/consume round-trips and clamps', () {
      final s = ContinuousModeState.instance;
      s.cancel();

      s.request(5);
      expect(s.consumePending(), 5);
      // Same request is not consumed twice.
      expect(s.consumePending(), isNull);

      // Over-eager counts are clamped to the hard cap.
      s.request(999);
      expect(s.consumePending(), ContinuousModeState.maxRunLength);
      s.cancel();
    });

    test('run is scoped to character', () {
      final s = ContinuousModeState.instance;
      s.cancel();

      s.startRun(characterId: 'a', count: 3);
      expect(s.isActive, isTrue);
      expect(s.isActiveFor('a'), isTrue);
      expect(s.isActiveFor('b'), isFalse);

      // A tick for the wrong character must not consume the run.
      expect(s.tick('b'), isFalse);
      expect(s.isActiveFor('a'), isTrue);
      expect(s.remaining, 3);
      s.cancel();
    });

    test('tick drains the run and clears it at zero', () {
      final s = ContinuousModeState.instance;
      s.cancel();

      s.startRun(characterId: 'a', count: 2);
      expect(s.tick('a'), isTrue);
      expect(s.remaining, 1);
      expect(s.tick('a'), isTrue);
      expect(s.remaining, 0);
      expect(s.isActive, isFalse);
      expect(s.tick('a'), isFalse);
      s.cancel();
    });

    test('stopRun clears the run but keeps a pending request', () {
      final s = ContinuousModeState.instance;
      s.cancel();

      s.request(3);
      s.startRun(characterId: 'a', count: 3);
      s.stopRun();
      expect(s.isActive, isFalse);
      // The pending request belongs to a fresh ask and must survive.
      expect(s.consumePending(), 3);
      s.cancel();
    });

    test('cancel clears both pending and active run', () {
      final s = ContinuousModeState.instance;
      s.request(3);
      s.startRun(characterId: 'a', count: 3);
      s.cancel();
      expect(s.isActive, isFalse);
      expect(s.consumePending(), isNull);
    });
  });
}
