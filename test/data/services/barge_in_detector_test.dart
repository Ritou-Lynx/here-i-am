import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/barge_in_detector.dart';

void main() {
  group('BargeInDetector', () {
    BargeInDetector makeDetector({
      double duckMs = 240,
      double interruptMs = 520,
      double restoreMs = 160,
    }) {
      return BargeInDetector(
        duckMs: duckMs,
        interruptMs: interruptMs,
        restoreMs: restoreMs,
        prerollMs: 1000,
        speechThresholdRms: 0.001, // accept everything for timing tests
      );
    }

    Float32List voicedFrame(int sampleCount, {double amplitude = 0.5}) {
      final f = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        // Simple sine wave — has low ZCR, high RMS.
        f[i] = (amplitude * 0.7) * math.sin(i * 0.05);
      }
      return f;
    }

    /// A frame shaped like real speech: sine + strong high-frequency noise
    /// (consonant-like, ZCR ~0.3-0.5). Must still be detected as speech —
    /// this is the regression test for the ZCR-veto bug.
    Float32List noisySpeechFrame(int sampleCount, {double amplitude = 0.5}) {
      final f = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        final sine = math.sin(i * 0.05);
        final noise = 0.8 * (math.sin(i * 3.7) + math.sin(i * 5.3)) / 2;
        f[i] = amplitude * (0.5 * sine + 0.5 * noise);
      }
      return f;
    }

    Float32List silentFrame(int sampleCount) {
      return Float32List(sampleCount); // all zeros
    }

    test('duck fires after duckMs of continuous voice', () {
      final det = makeDetector(duckMs: 240, interruptMs: 520);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      // 160 samples = 10ms at 16kHz. 240ms = 24 frames.
      for (var i = 0; i < 24; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(events, contains(BargeInEvent.duck));
      expect(det.isDucked, isTrue);
      det.stop();
    });

    test('interrupt fires after interruptMs of continuous voice', () {
      final det = makeDetector(duckMs: 240, interruptMs: 520);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      // 520ms = 52 frames.
      for (var i = 0; i < 52; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(events, contains(BargeInEvent.duck));
      expect(events, contains(BargeInEvent.interrupt));
      expect(det.isInterrupted, isTrue);
      det.stop();
    });

    test('restore fires on silence after duck (false alarm)', () {
      final det = makeDetector(duckMs: 240, interruptMs: 520, restoreMs: 160);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      // 25 frames = 250ms voice → duck fires.
      for (var i = 0; i < 25; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(events, contains(BargeInEvent.duck));

      // 17 frames = 170ms silence → restore fires.
      for (var i = 0; i < 17; i++) {
        det.push(silentFrame(160), 16000);
      }
      expect(events, contains(BargeInEvent.restore));
      expect(det.isDucked, isFalse);
      det.stop();
    });

    test('no interrupt if voice stops before interruptMs', () {
      final det = makeDetector(duckMs: 240, interruptMs: 520, restoreMs: 160);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      // 25 frames = 250ms voice → duck.
      for (var i = 0; i < 25; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(events, contains(BargeInEvent.duck));

      // 17 frames = 170ms silence → restore (no interrupt).
      for (var i = 0; i < 17; i++) {
        det.push(silentFrame(160), 16000);
      }
      expect(events, contains(BargeInEvent.restore));
      expect(events, isNot(contains(BargeInEvent.interrupt)));
      det.stop();
    });

    test('interrupt provides preroll snapshot', () {
      final det = makeDetector(duckMs: 100, interruptMs: 200);
      det.start(16000);
      Float32List? snapshot;
      det.onEvent = (e, s) {
        if (e == BargeInEvent.interrupt) snapshot = s;
      };

      // Push 250ms of voice to trigger interrupt.
      for (var i = 0; i < 25; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(snapshot, isNotNull);
      expect(snapshot!.length, greaterThan(0));
      det.stop();
    });

    test('no events from silence only', () {
      final det = makeDetector();
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      for (var i = 0; i < 100; i++) {
        det.push(silentFrame(160), 16000);
      }
      expect(events, isEmpty);
      expect(det.isDucked, isFalse);
      expect(det.isInterrupted, isFalse);
      det.stop();
    });

    test('regression: high-ZCR speech-shaped frames still trigger interrupt',
        () {
      // Real speech has high ZCR on consonants (~0.3-0.5). The old
      // implementation vetoed these via zcr <= 0.15, so barge-in never
      // fired. This test pins the fix: RMS is the gate, ZCR only excludes
      // DC offset.
      final det = makeDetector(duckMs: 240, interruptMs: 520);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      for (var i = 0; i < 52; i++) {
        det.push(noisySpeechFrame(160), 16000);
      }
      expect(events, contains(BargeInEvent.duck));
      expect(events, contains(BargeInEvent.interrupt));
      expect(det.isInterrupted, isTrue);
      det.stop();
    });

    test('regression: low-RMS speech-shaped frames do not trigger', () {
      final det = makeDetector(duckMs: 240, interruptMs: 520);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      for (var i = 0; i < 52; i++) {
        det.push(noisySpeechFrame(160, amplitude: 0.0001), 16000);
      }
      expect(events, isEmpty);
      det.stop();
    });

    test('speaker echo calibration rejects echo but accepts near-end speech',
        () {
      final det = BargeInDetector(
        duckMs: 260,
        interruptMs: 650,
        restoreMs: 180,
        prerollMs: 800,
        speechThresholdRms: 0.008,
        echoThresholdMultiplier: 1.6,
      );
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      det.beginEchoCalibration(durationMs: 650);
      // Android playback can begin with quiet decoder/header frames. The
      // calibration must retain the later, real TTS peak instead of averaging
      // it down and then treating the companion's first syllable as a user.
      for (var i = 0; i < 10; i++) {
        det.push(voicedFrame(160, amplitude: 0.001), 16000);
      }
      for (var i = 0; i < 55; i++) {
        det.push(voicedFrame(160, amplitude: 0.03), 16000);
      }
      expect(det.effectiveSpeechThresholdRms, greaterThan(0.008));
      expect(events, isEmpty);

      // Residual TTS echo at the calibrated level must not self-interrupt.
      for (var i = 0; i < 80; i++) {
        det.push(voicedFrame(160, amplitude: 0.03), 16000);
      }
      expect(events, isEmpty);

      // A close near-end voice rises above the echo baseline and interrupts
      // within the natural 650ms window.
      for (var i = 0; i < 65; i++) {
        det.push(voicedFrame(160, amplitude: 0.08), 16000);
      }
      expect(events, contains(BargeInEvent.duck));
      expect(events, contains(BargeInEvent.interrupt));
      det.stop();
    });

    test('resetEvidence clears duck state', () {
      final det = makeDetector(duckMs: 100, interruptMs: 200);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      // 11 frames = 110ms → duck.
      for (var i = 0; i < 11; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(det.isDucked, isTrue);

      det.resetEvidence();
      expect(det.isDucked, isFalse);
      expect(det.isInterrupted, isFalse);
      det.stop();
    });

    test('after interrupt, further frames are ignored', () {
      final det = makeDetector(duckMs: 100, interruptMs: 200);
      det.start(16000);
      final events = <BargeInEvent>[];
      det.onEvent = (e, _) => events.add(e);

      // 21 frames = 210ms → interrupt.
      for (var i = 0; i < 21; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(events.last, BargeInEvent.interrupt);

      // More frames should not produce new events.
      final lenBefore = events.length;
      for (var i = 0; i < 10; i++) {
        det.push(voicedFrame(160), 16000);
      }
      expect(events.length, lenBefore);
      det.stop();
    });
  });

  group('PcmRingBuffer', () {
    test('snapshot returns null when empty', () {
      final buf = PcmRingBuffer(capacityMs: 1000, sampleRate: 16000);
      expect(buf.snapshot(), isNull);
    });

    test('push then snapshot returns data', () {
      final buf = PcmRingBuffer(capacityMs: 1000, sampleRate: 16000);
      final data = Float32List.fromList([0.1, 0.2, 0.3]);
      buf.push(data);
      final snap = buf.snapshot();
      expect(snap, isNotNull);
      expect(snap!.length, 3);
      expect((snap[0] - 0.1).abs(), lessThan(1e-5));
      expect((snap[1] - 0.2).abs(), lessThan(1e-5));
      expect((snap[2] - 0.3).abs(), lessThan(1e-5));
    });

    test('overwrites old data when full', () {
      // capacity = 1000ms * 100Hz / 1000 = 100 samples
      final buf = PcmRingBuffer(capacityMs: 1000, sampleRate: 100);
      // Push 60 samples of 1.0
      buf.push(Float32List.fromList(List.filled(60, 1.0)));
      // Push 60 samples of 2.0 (wraps around, overwrites first 20 of 1.0)
      buf.push(Float32List.fromList(List.filled(60, 2.0)));
      final snap = buf.snapshot();
      expect(snap, isNotNull);
      expect(snap!.length, 100);
    });

    test('clear empties the buffer', () {
      final buf = PcmRingBuffer(capacityMs: 1000, sampleRate: 16000);
      buf.push(Float32List.fromList([0.5]));
      buf.clear();
      expect(buf.snapshot(), isNull);
      expect(buf.length, 0);
    });
  });
}
