import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/agent/companion_agent/sleep_companion_state.dart';

void main() {
  group('buildTimeGapReminder', () {
    final now = DateTime(2026, 8, 2, 23, 30);

    test('returns null for very short gaps', () {
      expect(
        CompanionAgent.buildTimeGapReminder(
            now.subtract(const Duration(seconds: 30)), now),
        isNull,
      );
      expect(
        CompanionAgent.buildTimeGapReminder(
            now.subtract(const Duration(minutes: 1)), now),
        isNull,
      );
    });

    test('formats minutes gap', () {
      final reminder = CompanionAgent.buildTimeGapReminder(
        now.subtract(const Duration(minutes: 5)),
        now,
      );
      expect(reminder, contains('距你上一条消息已过 5 分钟'));
      expect(reminder, contains('现在 23:30'));
    });

    test('formats hour gap', () {
      final reminder = CompanionAgent.buildTimeGapReminder(
        now.subtract(const Duration(hours: 2, minutes: 14)),
        now,
      );
      expect(reminder, contains('已过 2 小时 14 分'));
    });

    test('formats days gap', () {
      final reminder = CompanionAgent.buildTimeGapReminder(
        now.subtract(const Duration(days: 2)),
        now,
      );
      expect(reminder, contains('已过 2 天'));
    });

    test('flags overnight for cross-day gaps', () {
      final lastNight = DateTime(2026, 8, 1, 23, 40);
      final morning = DateTime(2026, 8, 2, 8, 5);
      final reminder = CompanionAgent.buildTimeGapReminder(lastNight, morning);
      expect(reminder, contains('已经过了一夜，是新的一天'));
      expect(reminder, contains('8 小时 25 分'));
    });

    test('negative gap returns null', () {
      expect(
        CompanionAgent.buildTimeGapReminder(
            now.add(const Duration(minutes: 1)), now),
        isNull,
      );
    });
  });

  group('SleepCompanionStateManager phrase detection', () {
    test('sleep enter phrases', () {
      for (final phrase in [
        '我要睡了',
        '睡了',
        '去睡了',
        '睡觉了',
        '晚安',
        '睡了睡了',
        '我躺下了',
        '我要睡了，你也早点睡',
        '准备睡了',
      ]) {
        expect(SleepCompanionStateManager.isSleepEnterPhrase(phrase), isTrue,
            reason: 'should detect: $phrase');
      }
    });

    test('excludes questions and negatives', () {
      for (final phrase in ['睡了吗', '你睡了没', '我还没睡', '睡不着', '你睡了吗']) {
        expect(SleepCompanionStateManager.isSleepEnterPhrase(phrase), isFalse,
            reason: 'should exclude: $phrase');
      }
    });

    test('insomnia phrases', () {
      expect(SleepCompanionStateManager.isInsomniaPhrase('睡不着'), isTrue);
      expect(SleepCompanionStateManager.isInsomniaPhrase('我失眠了'), isTrue);
      expect(SleepCompanionStateManager.isInsomniaPhrase('翻来覆去睡不着'), isTrue);
      expect(SleepCompanionStateManager.isSleepEnterPhrase('我睡不着'), isFalse);
    });

    test('wake phrases', () {
      for (final phrase in ['早上好', '早安', '我醒了', '起床了', '起来了', '睡醒了']) {
        expect(SleepCompanionStateManager.isWakePhrase(phrase), isTrue,
            reason: 'should detect: $phrase');
      }
      expect(SleepCompanionStateManager.isWakePhrase('你醒了吗'), isFalse);
      expect(SleepCompanionStateManager.isWakePhrase('我还没醒'), isFalse);
    });
  });

  group('SleepCompanionStateManager.evaluate', () {
    final now = DateTime(2026, 8, 2, 23, 30);
    final noon = DateTime(2026, 8, 2, 12, 0);

    test('no state and normal message → nothing', () {
      final r = SleepCompanionStateManager.evaluate(
        existing: null,
        userMessage: '今天天气不错',
        now: now,
      );
      expect(r.reminder, isNull);
      expect(r.stateChanged, isFalse);
      expect(r.activeState, isNull);
    });

    test('saying goodnight enters sleep mode', () {
      final r = SleepCompanionStateManager.evaluate(
        existing: null,
        userMessage: '我要睡了',
        now: now,
      );
      expect(r.stateChanged, isTrue);
      expect(r.activeState, isNotNull);
      expect(r.activeState!.insomnia, isFalse);
      expect(r.reminder, contains('哄睡模式'));
      expect(r.reminder, contains('[softly]'));
    });

    test('saying can not sleep enters watch mode', () {
      final r = SleepCompanionStateManager.evaluate(
        existing: null,
        userMessage: '我睡不着',
        now: now,
      );
      expect(r.stateChanged, isTrue);
      expect(r.activeState!.insomnia, isTrue);
      expect(r.reminder, contains('守夜陪伴模式'));
    });

    test('message within 15 min of goodnight → soft window', () {
      final state = SleepCompanionState(
        enteredAt: now.subtract(const Duration(minutes: 5)),
        insomnia: false,
      );
      final r = SleepCompanionStateManager.evaluate(
        existing: state,
        userMessage: '你明天记得叫我',
        now: now,
      );
      expect(r.stateChanged, isFalse);
      expect(r.activeState, same(state));
      expect(r.reminder, contains('还没完全静下来'));
    });

    test('message 30 min later → still awake window', () {
      final state = SleepCompanionState(
        enteredAt: now.subtract(const Duration(minutes: 30)),
        insomnia: false,
      );
      final r = SleepCompanionStateManager.evaluate(
        existing: state,
        userMessage: '还在吗',
        now: now,
      );
      expect(r.reminder, contains('隔了 30 分钟 又开口了'));
    });

    test('message 3 hours later → deep night window', () {
      final state = SleepCompanionState(
        enteredAt: now.subtract(const Duration(hours: 3)),
        insomnia: false,
      );
      final r = SleepCompanionStateManager.evaluate(
        existing: state,
        userMessage: '嗯…',
        now: now,
      );
      expect(r.reminder, contains('深夜'));
      expect(r.stateChanged, isFalse);
    });

    test('overnight → auto exit with new day greeting', () {
      final state = SleepCompanionState(
        enteredAt: DateTime(2026, 8, 1, 23, 50),
        insomnia: false,
      );
      final morning = DateTime(2026, 8, 2, 8, 5);
      final r = SleepCompanionStateManager.evaluate(
        existing: state,
        userMessage: '早',
        now: morning,
      );
      expect(r.reminder, contains('新的一天'));
      expect(r.stateChanged, isTrue);
      expect(r.activeState, isNull);
    });

    test('overnight by date change → auto exit even within 8h', () {
      final state = SleepCompanionState(
        enteredAt: DateTime(2026, 8, 2, 23, 40),
        insomnia: false,
      );
      final nextMorning = DateTime(2026, 8, 3, 7, 0);
      final r = SleepCompanionStateManager.evaluate(
        existing: state,
        userMessage: '早',
        now: nextMorning,
      );
      expect(r.stateChanged, isTrue);
      expect(r.activeState, isNull);
      expect(r.reminder, contains('新的一天'));
    });

    test('wake phrase with existing state → exit with wake reminder', () {
      final state = SleepCompanionState(
        enteredAt: now.subtract(const Duration(hours: 1)),
        insomnia: false,
      );
      final r = SleepCompanionStateManager.evaluate(
        existing: state,
        userMessage: '我醒了',
        now: DateTime(2026, 8, 3, 8, 30),
      );
      expect(r.stateChanged, isTrue);
      expect(r.activeState, isNull);
      expect(r.reminder, contains('醒来问候'));
    });

    test('wake phrase without state → nothing', () {
      final r = SleepCompanionStateManager.evaluate(
        existing: null,
        userMessage: '早上好',
        now: noon,
      );
      expect(r.reminder, isNull);
      expect(r.stateChanged, isFalse);
    });

    test('insomnia watch window uses different tone', () {
      final state = SleepCompanionState(
        enteredAt: now.subtract(const Duration(minutes: 3)),
        insomnia: true,
      );
      final r = SleepCompanionStateManager.evaluate(
        existing: state,
        userMessage: '还在呢',
        now: now,
      );
      expect(r.reminder, contains('守夜陪伴中'));
      expect(r.reminder, isNot(contains('还没完全静下来')));
    });
  });
}
