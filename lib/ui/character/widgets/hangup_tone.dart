import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Plays a short "call ended" tone (two soft descending beeps).
/// Call while the VoIP audio session is still active so the tone routes
/// through the voice-communication path to the speaker.
Future<void> playHangupTone() async {
  await _playTone(
    fileName: 'hereiam_hangup_tone.wav',
    segments: const [
      [520, 0.18],
      [0, 0.12],
      [400, 0.24],
    ],
    amp: 0.35,
    activateSession: false,
  );
}

/// Plays a short "recording started" beep (single rising tone) so the user
/// gets audible feedback when a headset button press begins recording.
Future<void> playRecordStartTone() async {
  await _playTone(
    fileName: 'hereiam_record_start_tone.wav',
    segments: const [
      [880, 0.10],
    ],
    amp: 0.3,
  );
}

/// Plays a short "recording stopped" beep (single lower tone) so the user
/// gets audible feedback when a headset button press stops recording.
Future<void> playRecordStopTone() async {
  await _playTone(
    fileName: 'hereiam_record_stop_tone.wav',
    segments: const [
      [660, 0.10],
    ],
    amp: 0.3,
  );
}

Future<void> _playTone({
  required String fileName,
  required List<List<double>> segments,
  required double amp,
  bool activateSession = true,
}) async {
  AudioPlayer? player;
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(
      _buildToneWav(segments: segments, amp: amp),
      flush: true,
    );
    player = AudioPlayer(
      handleAudioSessionActivation: activateSession,
      androidApplyAudioAttributes: false,
    );
    await player.setFilePath(file.path);
    await player.play();
    await player.playerStateStream
        .firstWhere((s) => s.processingState == ProcessingState.completed)
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('playTone($fileName) failed: $e');
  } finally {
    await player?.dispose();
  }
}

/// Builds a WAV (16 kHz, mono, 16-bit PCM) from the given tone segments.
/// Each segment is [frequencyHz, durationSeconds]; frequency 0 = silence gap.
Uint8List _buildToneWav({
  required List<List<double>> segments,
  required double amp,
}) {
  const sampleRate = 16000;
  const fadeMs = 12;
  final fadeSamples = (sampleRate * fadeMs / 1000).round();

  final samples = <int>[];
  for (final seg in segments) {
    final freq = seg[0];
    final n = (sampleRate * seg[1]).round();
    for (var i = 0; i < n; i++) {
      double env;
      if (freq <= 0) {
        env = 0.0;
      } else if (i < fadeSamples) {
        env = i / fadeSamples;
      } else if (i > n - fadeSamples) {
        env = (n - i) / fadeSamples;
      } else {
        env = 1.0;
      }
      final v = freq > 0 ? math.sin(2 * math.pi * freq * i / sampleRate) : 0.0;
      final s = (v * amp * env * 32767).round().clamp(-32768, 32767);
      samples.add(s);
    }
  }

  final dataLen = samples.length * 2;
  final buf = ByteData(44 + dataLen);
  _writeAscii(buf, 0, 'RIFF');
  buf.setUint32(4, 36 + dataLen, Endian.little);
  _writeAscii(buf, 8, 'WAVE');
  _writeAscii(buf, 12, 'fmt ');
  buf.setUint32(16, 16, Endian.little);
  buf.setUint16(20, 1, Endian.little);
  buf.setUint16(22, 1, Endian.little);
  buf.setUint32(24, sampleRate, Endian.little);
  buf.setUint32(28, sampleRate * 2, Endian.little);
  buf.setUint16(32, 2, Endian.little);
  buf.setUint16(34, 16, Endian.little);
  _writeAscii(buf, 36, 'data');
  buf.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    buf.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return buf.buffer.asUint8List();
}

void _writeAscii(ByteData buf, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    buf.setUint8(offset + i, s.codeUnitAt(i));
  }
}
