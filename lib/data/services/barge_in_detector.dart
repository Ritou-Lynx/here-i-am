import 'dart:math' as math;
import 'dart:typed_data';

/// Events emitted by [BargeInDetector].
enum BargeInEvent { duck, interrupt, restore }

/// Two-stage barge-in detector with PCM ring-buffer preroll.
///
/// Cove GPT-Live design:
/// - **duck** (~240ms continuous voice): lower TTS volume so the user can
///   hear themselves think, but don't stop playback yet.
/// - **interrupt** (~520ms continuous voice): confirm the user really wants
///   to speak. Fire [BargeInEvent.interrupt] with the preroll snapshot.
/// - **restore** (~160ms silence after a duck): the short burst was a cough
///   or table bump, not real speech. Restore TTS volume.
///
/// The [prerollMs] ring buffer (~1000ms) captures audio *before* the interrupt
/// is confirmed. When interrupt fires, the snapshot contains the user's
/// opening words —灌回 the new turn's recorder so the first word isn't lost.
///
/// Speech detection uses RMS as the primary gate, with ZCR only excluding
/// DC offset / flat signals. This keeps real speech (which spans a wide
/// ZCR range) from being vetoed, while the platform AEC handles echo.
class BargeInDetector {
  BargeInDetector({
    this.duckMs = 240,
    this.interruptMs = 520,
    this.restoreMs = 160,
    this.prerollMs = 1000,
    this.speechThresholdRms = 0.005,
  });

  /// Continuous voice duration to trigger duck (lower TTS volume).
  final double duckMs;

  /// Continuous voice duration to trigger interrupt (stop TTS, start new turn).
  final double interruptMs;

  /// Continuous silence after a duck to restore TTS volume.
  final double restoreMs;

  /// Preroll ring buffer duration in milliseconds.
  final double prerollMs;

  /// RMS threshold for speech detection (0-1, ~-46dB for 16-bit).
  /// Primary gate — real user speech is loud; the platform AEC removes
  /// most TTS echo. Cove reference: rms >= 0.004.
  final double speechThresholdRms;

  bool _ducked = false;
  bool _interrupted = false;
  double _voicedMs = 0;
  double _silentMs = 0;
  PcmRingBuffer? _preroll;

  /// Callback for duck/interrupt/restore events.
  void Function(BargeInEvent event, Float32List? prerollSnapshot)? onEvent;

  /// Whether the detector has triggered a duck (volume lowered).
  bool get isDucked => _ducked;

  /// Whether the detector has triggered an interrupt (TTS should stop).
  bool get isInterrupted => _interrupted;

  /// Start the detector. Allocates the preroll ring buffer.
  void start(int sampleRate) {
    _preroll = PcmRingBuffer(
      capacityMs: prerollMs,
      sampleRate: sampleRate,
    );
    _ducked = false;
    _interrupted = false;
    _voicedMs = 0;
    _silentMs = 0;
  }

  /// Stop the detector and release the preroll buffer.
  void stop() {
    _preroll = null;
    _ducked = false;
    _interrupted = false;
    _voicedMs = 0;
    _silentMs = 0;
  }

  /// Reset for a new detection cycle (e.g. after an interrupt has been handled).
  void resetEvidence() {
    _voicedMs = 0;
    _silentMs = 0;
    _ducked = false;
    _interrupted = false;
  }

  /// Feed a PCM frame and return any event that fires.
  ///
  /// [frame] is Float32 PCM samples (mono, normalized -1.0 to 1.0).
  /// [sampleRate] is the sample rate of the audio.
  BargeInEvent? push(Float32List frame, int sampleRate) {
    if (_interrupted) return null;
    final preroll = _preroll;
    if (preroll != null) {
      preroll.push(frame);
    }

    final frameMs = frame.length / sampleRate * 1000;
    final isSpeech = _isLikelyUserSpeech(frame);

    if (isSpeech) {
      _voicedMs += frameMs;
      _silentMs = 0;

      if (!_ducked && _voicedMs >= duckMs) {
        _ducked = true;
        onEvent?.call(BargeInEvent.duck, null);
        return BargeInEvent.duck;
      }

      if (_voicedMs >= interruptMs) {
        _interrupted = true;
        final snapshot = preroll?.snapshot();
        onEvent?.call(BargeInEvent.interrupt, snapshot);
        return BargeInEvent.interrupt;
      }
    } else {
      _silentMs += frameMs;

      if (_ducked && !_interrupted && _silentMs >= restoreMs) {
        // Short burst was not sustained — restore volume.
        _ducked = false;
        _voicedMs = 0;
        _silentMs = 0;
        onEvent?.call(BargeInEvent.restore, null);
        return BargeInEvent.restore;
      }
    }
    return null;
  }

  /// Simple speech detection: RMS above threshold is the primary gate.
  ///
  /// ZCR is NOT used to veto voice — human speech spans a wide ZCR range
  /// (vowels ~0.01-0.1, consonants ~0.2-0.4), so a narrow ZCR ceiling
  /// wrongly rejects most real speech frames. ZCR is only used to exclude
  /// DC offset / flat signals (zcr ≈ 0), where RMS can be misleadingly
  /// high. The platform AEC handles most echo; this just catches real
  /// user speech during TTS.
  bool _isLikelyUserSpeech(Float32List frame) {
    if (frame.isEmpty) return false;

    double sumSq = 0;
    int crossings = 0;
    double prevSample = 0;

    for (var i = 0; i < frame.length; i++) {
      final s = frame[i];
      sumSq += s * s;
      if (i > 0 && (s >= 0) != (prevSample >= 0)) {
        crossings++;
      }
      prevSample = s;
    }

    final rms = math.sqrt(sumSq / frame.length);
    final zcr = crossings / frame.length;

    if (rms < speechThresholdRms) return false;
    // Exclude DC offset / flat signals (zcr ≈ 0). Any real content
    // (voice or noise) crosses zero at least occasionally.
    return zcr > 0.005;
  }
}

/// Fixed-capacity PCM ring buffer for preroll capture.
///
/// Stores the last [capacityMs] of audio so that when an interrupt is
/// confirmed, the user's opening words (which arrived *before* the
/// detection threshold was reached) are available to feed into the new
/// turn's recorder.
class PcmRingBuffer {
  PcmRingBuffer({
    required this.capacityMs,
    required this.sampleRate,
  }) : _capacity = (capacityMs / 1000 * sampleRate).round() {
    _buffer = Float32List(_capacity);
  }

  final double capacityMs;
  final int sampleRate;
  final int _capacity;

  late Float32List _buffer;
  int _writePos = 0;
  int _written = 0;

  /// Push a frame into the ring buffer.
  void push(Float32List frame) {
    for (var i = 0; i < frame.length; i++) {
      _buffer[_writePos] = frame[i];
      _writePos = (_writePos + 1) % _capacity;
      if (_written < _capacity) _written++;
    }
  }

  /// Take a snapshot of the current buffer contents (oldest first).
  /// Returns null if no audio has been pushed.
  Float32List? snapshot() {
    if (_written == 0) return null;
    final result = Float32List(_written);
    final start = (_writePos - _written + _capacity) % _capacity;
    for (var i = 0; i < _written; i++) {
      result[i] = _buffer[(start + i) % _capacity];
    }
    return result;
  }

  /// Clear the buffer.
  void clear() {
    _writePos = 0;
    _written = 0;
  }

  /// Number of samples currently in the buffer.
  int get length => _written;
}