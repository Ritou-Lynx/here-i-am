import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/gpt_live/gpt_live_idle_watch.dart';

void main() {
  final start = DateTime(2026, 11, 8, 10);

  test('未到静音时间不触发', () {
    final watch = GptLiveIdleWatch(idleMinutes: 5, lastTranscriptAt: start);
    expect(
      watch.evaluate(start.add(const Duration(minutes: 4, seconds: 59))),
      GptLiveIdleAction.none,
    );
  });

  test('到静音时间提示一次', () {
    final watch = GptLiveIdleWatch(idleMinutes: 5, lastTranscriptAt: start);
    expect(
      watch.evaluate(start.add(const Duration(minutes: 5))),
      GptLiveIdleAction.prompt,
    );
    expect(
      watch.evaluate(start.add(const Duration(minutes: 5, seconds: 1))),
      GptLiveIdleAction.none,
    );
  });

  test('提示后有转写增量会重置', () {
    final watch = GptLiveIdleWatch(idleMinutes: 5, lastTranscriptAt: start);
    final promptedAt = start.add(const Duration(minutes: 5));
    expect(watch.evaluate(promptedAt), GptLiveIdleAction.prompt);
    watch.recordTranscript(promptedAt.add(const Duration(seconds: 10)));
    expect(
      watch.evaluate(promptedAt.add(const Duration(seconds: 30))),
      GptLiveIdleAction.none,
    );
  });

  test('提示后 20 秒挂断', () {
    final watch = GptLiveIdleWatch(idleMinutes: 5, lastTranscriptAt: start);
    final promptedAt = start.add(const Duration(minutes: 5));
    expect(watch.evaluate(promptedAt), GptLiveIdleAction.prompt);
    expect(
      watch.evaluate(promptedAt.add(const Duration(seconds: 20))),
      GptLiveIdleAction.hangup,
    );
  });

  test('N 为 0 永不触发', () {
    final watch = GptLiveIdleWatch(idleMinutes: 0, lastTranscriptAt: start);
    expect(
      watch.evaluate(start.add(const Duration(days: 1))),
      GptLiveIdleAction.none,
    );
  });
}
