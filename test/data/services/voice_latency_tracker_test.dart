import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/voice_latency_tracker.dart';

void main() {
  group('VoiceLatencyTracker', () {
    test('toMap has expected keys', () {
      final t = VoiceLatencyTracker(turnId: 'turn_01');
      t.markTurnStart();
      t.markEndpoint();
      t.markAsrComplete();
      t.markModelRequest();
      t.markModelFirstText();
      t.markTtsFirstAudio();
      t.markFormalFirstSound();

      final m = t.toMap();
      expect(m['event'], 'voice_latency');
      expect(m['turn_id'], 'turn_01');
      expect(m.containsKey('endpoint_ms'), isTrue);
      expect(m.containsKey('asr_ms'), isTrue);
      expect(m.containsKey('model_first_text_ms'), isTrue);
      expect(m.containsKey('tts_first_audio_ms'), isTrue);
      expect(m.containsKey('formal_first_sound_ms'), isTrue);
    });

    test('unmarked stages return -1', () {
      final t = VoiceLatencyTracker(turnId: 'turn_02');
      final m = t.toMap();
      expect(m['endpoint_ms'], -1);
      expect(m['model_first_text_ms'], -1);
      expect(m['formal_first_sound_ms'], -1);
    });

    test('elapsed is non-negative when marks are in order', () async {
      final t = VoiceLatencyTracker(turnId: 'turn_03');
      t.markTurnStart();
      await Future.delayed(const Duration(milliseconds: 10));
      t.markAsrComplete();
      await Future.delayed(const Duration(milliseconds: 5));
      t.markModelRequest();
      await Future.delayed(const Duration(milliseconds: 20));
      t.markModelFirstText();

      final m = t.toMap();
      expect(m['asr_ms'] as int, greaterThanOrEqualTo(4));
      expect(m['model_first_text_ms'] as int, greaterThanOrEqualTo(18));
    });

    test('first_sound_ms prefers cue over formal when earlier', () async {
      final t = VoiceLatencyTracker(turnId: 'turn_04');
      t.markTurnStart();
      await Future.delayed(const Duration(milliseconds: 50));
      t.markCueFirstSound();
      await Future.delayed(const Duration(milliseconds: 100));
      t.markFormalFirstSound();

      final m = t.toMap();
      // first_sound should be the cue time (~50ms), not formal (~150ms).
      expect(m['first_sound_ms'] as int, lessThan(100));
    });

    test('first_sound_ms uses formal when no cue', () async {
      final t = VoiceLatencyTracker(turnId: 'turn_05');
      t.markTurnStart();
      await Future.delayed(const Duration(milliseconds: 80));
      t.markFormalFirstSound();

      final m = t.toMap();
      expect(m['first_sound_ms'] as int, greaterThanOrEqualTo(70));
    });

    test('callSessionId and backends included when provided', () {
      final t = VoiceLatencyTracker(
        turnId: 'turn_06',
        callSessionId: 'call_01',
        asrBackend: 'nls',
        ttsTransport: 'websocket',
      );
      final m = t.toMap();
      expect(m['call_session_id'], 'call_01');
      expect(m['asr_backend'], 'nls');
      expect(m['tts_transport'], 'websocket');
    });

    test('log does not throw', () {
      final t = VoiceLatencyTracker(turnId: 'turn_07');
      t.markTurnStart();
      t.markAsrComplete();
      t.markModelRequest();
      t.markModelFirstText();
      // Should not throw.
      t.log();
    });
  });
}