import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/voice_call_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late VoiceCallHealth health;
  var clock = DateTime(2026, 11, 1, 20, 30);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    health = VoiceCallHealth.instance;
    health.now = () => clock;
    await health.clear();
  });

  test('records turns and turbo outcomes on the current session', () async {
    await health.begin(provider: 'home_turbo');
    await health.recordTurn({
      'model_first_text_ms': 900,
      'tts_first_audio_ms': 400,
      'first_sound_ms': 1500,
      'formal_first_sound_ms': -1,
    });
    await health.recordTurn({'model_first_text_ms': 1100});
    await health.recordTurn({'model_first_text_ms': 700});
    await health.recordTurbo(TurboOutcome.ok, totalMs: 600);
    await health.recordTurbo(TurboOutcome.failed);
    await health.recordTurbo(TurboOutcome.skipped);
    await health.setHealth('可用');

    final sessions = await health.load();
    expect(sessions, hasLength(1));
    final s = sessions.single;
    expect(s.turns, 3);
    expect(s.median('model_first_text_ms'), 900);
    expect(s.median('formal_first_sound_ms'), isNull);
    expect(s.turboOk, 1);
    expect(s.turboFailed, 1);
    expect(s.turboSkipped, 1);
    expect(s.summaryLine, contains('轮数 3'));
    expect(s.summaryLine, contains('成功 1 / 失败 1 / 跳过 1'));
    expect(s.summaryLine, contains('开场体检 可用'));
  });

  test('keeps only the most recent sessions, newest first', () async {
    for (var i = 0; i < VoiceCallHealth.maxSessions + 5; i++) {
      clock = clock.add(const Duration(minutes: 1));
      await health.begin(provider: 'minimax');
      await health.recordTurn({'model_first_text_ms': i});
    }
    final sessions = await health.load();
    expect(sessions, hasLength(VoiceCallHealth.maxSessions));
    expect(sessions.first.median('model_first_text_ms'),
        VoiceCallHealth.maxSessions + 4);
  });

  test('nothing is recorded before a session begins', () async {
    await health.recordTurn({'model_first_text_ms': 1});
    await health.recordTurbo(TurboOutcome.ok, totalMs: 1);
    expect(await health.load(), isEmpty);
  });

  test('copy text has one line per session without turbo fields for others',
      () async {
    await health.begin(provider: 'minimax');
    final text = VoiceCallHealth.formatForCopy(await health.load());
    expect(text.split('\n'), hasLength(1));
    expect(text, isNot(contains('电脑声音')));
  });
}
