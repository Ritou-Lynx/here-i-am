import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/ordered_tts_queue.dart';
import 'package:memex/domain/models/voice_turn_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp;

  File createTempAudioFile(String name) {
    final file = File('${tempDir.path}/test_tts_$name.mp3');
    file.writeAsBytesSync([0xFF, 0xE3, 0x18, 0xC4, 0x00, 0x00, 0x00, 0x00]);
    return file;
  }

  /// No-op playback injector: does nothing, returns immediately. The queue
  /// still manages ordering, identity, and cleanup.
  Future<void> noopPlayer(TtsSegment seg, VoiceTurnIdentity active) async {}

  group('OrderedTtsQueue identity protocol', () {
    test('rejects segment with stale identity', () {
      const activeId = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_02',
        turnSequence: 2,
        generationId: 'gen_02_a',
      );
      const staleId = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      final queue = OrderedTtsQueue(
        identity: activeId,
        playSegment: noopPlayer,
      );
      final file = createTempAudioFile('stale');

      final result = queue.push(TtsSegment(
        identity: staleId,
        seq: 0,
        file: file,
        text: 'stale',
      ));

      expect(result, TtsQueuePushResult.staleIdentity);
      expect(file.existsSync(), isFalse);
      queue.dispose();
    });

    test('rejects segment after cancel', () async {
      const id = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      final queue = OrderedTtsQueue(
        identity: id,
        playSegment: noopPlayer,
      );
      await queue.cancel();

      final file = createTempAudioFile('cancelled');
      final result = queue.push(TtsSegment(
        identity: id,
        seq: 0,
        file: file,
        text: 'cancelled',
      ));

      expect(result, TtsQueuePushResult.cancelled);
      queue.dispose();
    });

    test('rejects duplicate seq', () async {
      const id = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      // Use a blocking player so the first segment stays in-flight.
      final blocker = Completer<void>();
      Future<void> blockingPlayer(TtsSegment seg, VoiceTurnIdentity a) async {
        await blocker.future;
      }

      final queue = OrderedTtsQueue(
        identity: id,
        playSegment: blockingPlayer,
      );
      final file1 = createTempAudioFile('dup1');
      queue.push(TtsSegment(identity: id, seq: 0, file: file1, text: 'first'));

      await Future.delayed(const Duration(milliseconds: 50));

      final file2 = createTempAudioFile('dup2');
      final result = queue.push(TtsSegment(
        identity: id,
        seq: 0,
        file: file2,
        text: 'second',
      ));

      expect(result, TtsQueuePushResult.duplicate);
      blocker.complete();
      await Future.delayed(const Duration(milliseconds: 50));
      queue.dispose();
    });
  });

  group('OrderedTtsQueue seq ordering', () {
    test('pendingCount tracks buffered segments', () async {
      const id = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      // Use a player that blocks so segments stay pending.
      final played = <int>[];
      final blocker = Completer<void>();
      Future<void> blockingPlayer(TtsSegment seg, VoiceTurnIdentity a) async {
        played.add(seg.seq);
        await blocker.future;
      }

      final queue = OrderedTtsQueue(
        identity: id,
        playSegment: blockingPlayer,
      );

      // Push seq=1 before seq=0 (out of order). seq=0 must play first.
      final file1 = createTempAudioFile('seq1');
      queue.push(TtsSegment(identity: id, seq: 1, file: file1, text: 'second'));

      await Future.delayed(const Duration(milliseconds: 50));

      final file0 = createTempAudioFile('seq0');
      queue.push(TtsSegment(identity: id, seq: 0, file: file0, text: 'first'));

      await Future.delayed(const Duration(milliseconds: 50));

      // seq=0 should be playing (blocked), seq=1 should be pending.
      expect(played, [0]);
      expect(queue.pendingCount, 1);

      blocker.complete();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(played, [0, 1]);

      queue.dispose();
    });
  });

  group('OrderedTtsQueue lifecycle', () {
    test('isCancelled starts false and becomes true after cancel', () async {
      const id = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      final queue = OrderedTtsQueue(
        identity: id,
        playSegment: noopPlayer,
      );
      expect(queue.isCancelled, isFalse);
      await queue.cancel();
      expect(queue.isCancelled, isTrue);
      queue.dispose();
    });

    test('onQueueDrained fires when queue is empty and markDone is called',
        () async {
      const id = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      var drained = false;
      final queue = OrderedTtsQueue(
        identity: id,
        playSegment: noopPlayer,
      );
      queue.onQueueDrained = () => drained = true;

      final file = createTempAudioFile('drain');
      queue.push(TtsSegment(identity: id, seq: 0, file: file, text: 'test'));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(queue.pendingCount, 0);
      expect(queue.isPlaying, isFalse);

      queue.markDone();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(drained, isTrue);

      queue.dispose();
    });
  });
}