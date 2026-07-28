import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a short, synthesized "call ended" tone (two soft descending beeps)
/// with no bundled audio asset. Used on voice-call hang-up — by either side —
/// so the user hears a natural end-of-call cue instead of the character reading
/// a "user hung up" line aloud.
///
/// The tone is generated as a 16 kHz mono PCM WAV in the system temp dir and
/// played through a throw-away [AudioPlayer]. When [context] is provided the
/// player is routed through it (e.g. media/assistant playback so the cue is
/// heard on the speaker after the VoIP session is torn down).
Future<void> playHangupTone({AudioContext? context}) async {
  AudioPlayer? player;
  try {
    final file = File('${Directory.systemTemp.path}/hereiam_hangup_tone.wav');
    await file.writeAsBytes(_buildHangupToneWav(), flush: true);
    player = AudioPlayer();
    if (context != null) {
      try {
        await player.setAudioContext(context);
      } catch (e) {
        debugPrint('hangup tone setAudioContext failed: $e');
      }
    }
    final toDispose = player;
    // Release the player once the cue finishes, with a timeout fallback so a
    // misbehaving platform can't leak it.
    unawaited(
      player.onPlayerComplete.first
          .timeout(const Duration(seconds: 4), onTimeout: () {})
          .then((_) => toDispose.dispose(), onError: (_) => toDispose.dispose()),
    );
    await player.play(DeviceFileSource(file.path));
  } catch (e) {
    debugPrint('playHangupTone failed: $e');
    await player?.dispose();
  }
}

/// Builds a WAV (16 kHz, mono, 16-bit PCM) containing two soft descending
/// beeps — a recognizable "call ended" cue. Pure synthesis, no asset needed.
Uint8List _buildHangupToneWav() {
  const sampleRate = 16000;
  const amp = 0.35;
  // [frequencyHz, durationSeconds]; frequency 0 = silence gap.
  const segments = <List<double>>[
    [520, 0.18],
    [0, 0.12],
    [400, 0.24],
  ];
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
