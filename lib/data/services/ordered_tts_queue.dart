import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:memex/domain/models/voice_turn_identity.dart';
import 'package:memex/utils/logger.dart';

/// A single TTS audio segment tagged with identity and sequence number.
@immutable
class TtsSegment {
  const TtsSegment({
    required this.identity,
    required this.seq,
    required this.file,
    required this.text,
  });

  final VoiceTurnIdentity identity;
  final int seq;
  final File file;
  final String text;
}

/// Result of pushing a segment to [OrderedTtsQueue].
enum TtsQueuePushResult { accepted, staleIdentity, cancelled, duplicate }

/// Ordered playback queue for TTS segments.
///
/// Guarantees:
/// - Segments are played strictly in ascending [seq] order, even if they
///   arrive out of order (e.g. seq=1 before seq=0 due to network jitter).
/// - A segment whose [VoiceTurnIdentity] does not match [this.identity] is
///   silently discarded (stale generation from a previous turn).
/// - [cancel] immediately stops the current playback and drops all pending
///   segments. After cancel, any further [push] calls return
///   [TtsQueuePushResult.cancelled].
/// - A stale [AudioPlayer.play()] Promise (from before a cancel) cannot
///   mutate queue state via a non-reusable playback claim.
///
/// This is the Dart/just_audio equivalent of Cove's OrderedTTSQueue +
/// playback claim protocol.
class OrderedTtsQueue {
  OrderedTtsQueue({
    required this.identity,
    this.voiceMode = false,
    this.playSegment,
  });

  final VoiceTurnIdentity identity;
  final bool voiceMode;

  /// Injectable playback function. When null (default), segments are played
  /// via [AudioPlayer]. When provided (e.g. in tests), the caller controls
  /// playback entirely — the queue only manages ordering and identity.
  final Future<void> Function(TtsSegment segment, VoiceTurnIdentity active)?
      playSegment;

  static final _log = getLogger('OrderedTtsQueue');

  final Map<int, TtsSegment> _pending = {};
  int _nextSeq = 0;
  int _playingSeq = -1;
  bool _cancelled = false;
  bool _playing = false;
  bool _disposed = false;

  AudioPlayer? _player;
  Completer<void>? _playCompleter;

  /// Called when a segment starts playing. Useful for syncing subtitles.
  void Function(TtsSegment segment)? onSegmentStart;

  /// Called when all queued segments up to the current point have finished
  /// playing. Fires once when the queue drains (no more pending segments and
  /// the LLM stream is done).
  void Function()? onQueueDrained;

  /// Whether the queue is currently playing a segment.
  bool get isPlaying => _playing;

  /// Whether the queue has been cancelled.
  bool get isCancelled => _cancelled;

  /// Number of segments still waiting to be played.
  int get pendingCount => _pending.length;

  /// Mark that no more segments will arrive (LLM stream finished). After this,
  /// [onQueueDrained] fires when the last segment finishes playing.
  void markDone() {
    _drainIfComplete();
  }

  /// Push a synthesized segment into the queue.
  ///
  /// Returns [TtsQueuePushResult.accepted] if the segment was enqueued or
  /// played. Returns [TtsQueuePushResult.staleIdentity] if the segment's
  /// identity doesn't match [this.identity] (stale generation). Returns
  /// [TtsQueuePushResult.cancelled] if [cancel] was called. Returns
  /// [TtsQueuePushResult.duplicate] if a segment with the same seq was
  /// already enqueued.
  TtsQueuePushResult push(TtsSegment segment) {
    if (_disposed || _cancelled) return TtsQueuePushResult.cancelled;
    if (!segment.identity.isCurrent(identity)) {
      _log.fine('Rejecting stale segment ${segment.identity} '
          '(active: $identity) seq=${segment.seq}');
      _cleanFile(segment.file);
      return TtsQueuePushResult.staleIdentity;
    }
    if (_pending.containsKey(segment.seq) || segment.seq == _playingSeq) {
      _log.warning('Duplicate seq=${segment.seq}, ignoring');
      _cleanFile(segment.file);
      return TtsQueuePushResult.duplicate;
    }
    _pending[segment.seq] = segment;
    _log.fine('Pushed seq=${segment.seq}, pending=${_pending.length}, '
        'nextSeq=$_nextSeq');
    unawaited(_drain());
    return TtsQueuePushResult.accepted;
  }

  /// Cancel all playback and drop pending segments.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _log.info('cancel: pending=${_pending.length}, playing=$_playing');
    _pending.clear();
    await _stopPlayer();
  }

  /// Permanently dispose the queue and release the audio player.
  Future<void> dispose() async {
    _disposed = true;
    _pending.clear();
    await _stopPlayer();
  }

  Future<void> _drain() async {
    if (_playing || _cancelled || _disposed) return;
    while (!_cancelled && !_disposed && _pending.containsKey(_nextSeq)) {
      final segment = _pending.remove(_nextSeq)!;
      _playingSeq = _nextSeq;
      _nextSeq++;
      await _playSegment(segment);
      _playingSeq = -1;
      if (_cancelled || _disposed) return;
    }
    _drainIfComplete();
  }

  void _drainIfComplete() {
    if (!_playing && _pending.isEmpty && !_cancelled && !_disposed) {
      onQueueDrained?.call();
    }
  }

  Future<void> _playSegment(TtsSegment segment) async {
    if (_cancelled || _disposed) {
      _cleanFile(segment.file);
      return;
    }
    if (!await segment.file.exists() || segment.file.lengthSync() == 0) {
      _log.warning('Segment file missing or empty: ${segment.file.path}');
      _cleanFile(segment.file);
      return;
    }

    _playing = true;
    onSegmentStart?.call(segment);

    // Injectable playback path (tests or custom players).
    final injector = playSegment;
    if (injector != null) {
      try {
        await injector(segment, identity);
      } catch (e) {
        _log.warning('Segment ${segment.seq} playback failed: $e');
      } finally {
        _cleanFile(segment.file);
        _playing = false;
      }
      return;
    }

    // Default just_audio playback path.
    final claim = _PlaybackClaim(
      identity: identity,
      seq: segment.seq,
      nonce: DateTime.now().microsecondsSinceEpoch,
    );

    final player = AudioPlayer();
    if (voiceMode) {
      try {
        await player.setAndroidAudioAttributes(
          AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
        );
      } catch (e) {
        _log.warning('set audio attributes failed: $e');
      }
    }
    _player = player;
    _playCompleter = Completer<void>();

    try {
      await player.setFilePath(segment.file.path);
      if (_cancelled || _disposed || !claim.isValidFor(identity)) {
        _log.fine('Segment ${segment.seq} cancelled before play');
        return;
      }
      final sub = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (!claim.isValidFor(identity)) return;
          if (!_playCompleter!.isCompleted) _playCompleter!.complete();
        }
      });
      await player.play();
      await _playCompleter!.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => _log.warning('Segment ${segment.seq} playback timed out'),
      );
      await sub.cancel();
    } catch (e) {
      _log.warning('Segment ${segment.seq} playback failed: $e');
    } finally {
      await player.dispose();
      _player = null;
      _playCompleter = null;
      _cleanFile(segment.file);
      _playing = false;
    }
  }

  Future<void> _stopPlayer() async {
    final player = _player;
    final completer = _playCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
      _player = null;
    }
    _playing = false;
  }

  void _cleanFile(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

/// Non-reusable playback claim. Prevents stale `AudioPlayer.play()` promises
/// from mutating queue state after a cancel or generation switch.
class _PlaybackClaim {
  _PlaybackClaim({
    required this.identity,
    required this.seq,
    required this.nonce,
  });

  final VoiceTurnIdentity identity;
  final int seq;
  final int nonce;

  bool isValidFor(VoiceTurnIdentity? active) {
    if (active == null) return false;
    return identity.isCurrent(active);
  }
}