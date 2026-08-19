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
  bool _draining = false;
  bool _done = false;
  bool _drainNotified = false;
  bool _disposed = false;

  AudioPlayer? _player;
  Completer<void>? _playCompleter;
  Completer<void>? _drainedCompleter;
  double _playbackVolume = 1;

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

  /// Change the volume of both the active and subsequent segments.
  Future<void> setVolume(double volume) async {
    _playbackVolume = volume.clamp(0.0, 1.0).toDouble();
    final player = _player;
    if (player != null) {
      await player.setVolume(_playbackVolume);
    }
  }

  /// Mark that no more segments will arrive (LLM stream finished). After this,
  /// [onQueueDrained] fires when the last segment finishes playing.
  void markDone() {
    _done = true;
    _drainIfComplete();
  }

  /// Completes only after [markDone] and after the drain coroutine has
  /// actually released the last segment.
  Future<void> waitUntilDrained() {
    if (_isFullyDrained) return Future.value();
    return (_drainedCompleter ??= Completer<void>()).future;
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
    _ensureDrain();
    return TtsQueuePushResult.accepted;
  }

  /// Cancel all playback and drop pending segments.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _log.info('cancel: pending=${_pending.length}, playing=$_playing');
    _pending.clear();
    _completeDrainWaiter();
    await _stopPlayer();
  }

  /// Permanently dispose the queue and release the audio player.
  Future<void> dispose() async {
    _disposed = true;
    _pending.clear();
    _completeDrainWaiter();
    await _stopPlayer();
  }

  Future<void> _drain() async {
    try {
      while (!_cancelled && !_disposed && _pending.containsKey(_nextSeq)) {
        final segment = _pending.remove(_nextSeq)!;
        _playingSeq = _nextSeq;
        _nextSeq++;
        await _playSegment(segment);
        _playingSeq = -1;
        if (_cancelled || _disposed) return;
      }
    } finally {
      _draining = false;
      _drainIfComplete();
    }
  }

  void _ensureDrain() {
    if (_draining || _cancelled || _disposed) return;
    _draining = true;
    unawaited(_drain());
  }

  bool get _isFullyDrained =>
      _done && !_draining && !_playing && _pending.isEmpty;

  void _drainIfComplete() {
    if (_isFullyDrained && !_cancelled && !_disposed && !_drainNotified) {
      _drainNotified = true;
      final completer = _drainedCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      onQueueDrained?.call();
    }
  }

  void _completeDrainWaiter() {
    final completer = _drainedCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
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

    // Injectable playback path (tests or custom players).
    final injector = playSegment;
    if (injector != null) {
      try {
        onSegmentStart?.call(segment);
        await injector(segment, identity);
      } catch (e) {
        _log.warning('Segment ${segment.seq} playback failed: $e');
      } finally {
        _cleanFile(segment.file);
        _playing = false;
      }
      return;
    }

    // Default just_audio playback path. Reuse one player for the whole queue.
    // Creating and disposing a native player for every sentence tears down
    // and recreates Android's voice-communication AudioTrack at each boundary;
    // on Samsung that can briefly start the next clip, cut its first syllable,
    // then restart it. A stable player keeps the call audio track continuous.
    final claim = _PlaybackClaim(
      identity: identity,
      seq: segment.seq,
      nonce: DateTime.now().microsecondsSinceEpoch,
    );
    final player = await _ensurePlayer();
    if (player == null) {
      _cleanFile(segment.file);
      _playing = false;
      return;
    }
    final playCompleter = Completer<void>();
    _playCompleter = playCompleter;
    StreamSubscription<PlayerState>? sub;
    var playbackFailed = false;

    try {
      await player.setFilePath(segment.file.path);
      await player.setVolume(_playbackVolume);
      if (_cancelled || _disposed || !claim.isValidFor(identity)) {
        _log.fine('Segment ${segment.seq} cancelled before play');
        return;
      }
      sub = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (!claim.isValidFor(identity)) return;
          if (!playCompleter.isCompleted) playCompleter.complete();
        }
      });
      onSegmentStart?.call(segment);
      await player.play();
      await playCompleter.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () =>
            _log.warning('Segment ${segment.seq} playback timed out'),
      );
    } catch (e) {
      playbackFailed = true;
      _log.warning('Segment ${segment.seq} playback failed: $e');
    } finally {
      await sub?.cancel();
      if (identical(_playCompleter, playCompleter)) {
        _playCompleter = null;
      }
      // Keep a healthy player alive for the next sentence. cancel()/dispose()
      // may already own it; only a genuine playback failure retires it here.
      if (playbackFailed && identical(_player, player)) {
        _player = null;
        await player.dispose();
      }
      _cleanFile(segment.file);
      _playing = false;
    }
  }

  Future<AudioPlayer?> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;

    // The VoIP call session owns the process-wide audio session. These flags
    // prevent just_audio from reconfiguring focus and route between sentences.
    final player = AudioPlayer(
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    );
    _player = player;
    if (voiceMode) {
      try {
        await player.setAndroidAudioAttributes(
          const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
        );
      } catch (e) {
        _log.warning('set audio attributes failed: $e');
      }
    }

    if (_cancelled || _disposed || !identical(_player, player)) {
      if (identical(_player, player)) _player = null;
      try {
        await player.dispose();
      } catch (_) {}
      return null;
    }
    return player;
  }

  Future<void> _stopPlayer() async {
    final player = _player;
    final completer = _playCompleter;
    // Release ownership synchronously. _playSegment's finally block can run
    // as soon as the completer/stop resolves and must see that this cleanup
    // path owns the platform player.
    _player = null;
    _playCompleter = null;
    _playing = false;
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
    }
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
