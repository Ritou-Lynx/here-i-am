/// Bidirectional synchronization between playback position and subtitle cues.
///
/// [PlayerSyncController] listens to [PlayerAdapter.timeEvents] and computes
/// the currently active cue index. The UI observes [activeCueIndex] for
/// reverse highlighting (playback → subtitle highlight).
///
/// When the user clicks a cue, [seekToCue] drives the player adapter's
/// [PlayerAdapter.seekTo] (subtitle click → playback seek).
library;

import 'dart:async';

import '../player_adapter.dart';

/// Controller for bidirectional playback ↔ subtitle synchronization.
class PlayerSyncController {
  final PlayerAdapter adapter;
  final TimedTextTrack track;

  StreamSubscription<PlayerTimeEvent>? _sub;
  int _activeCueIndex = -1;
  int _positionMs = 0;
  int _durationMs = 0;
  bool _isSeeking = false;

  final void Function(int cueIndex)? onActiveCueChanged;
  final void Function(int positionMs)? onPositionChanged;
  final void Function(int durationMs)? onDurationChanged;

  PlayerSyncController({
    required this.adapter,
    required this.track,
    this.onActiveCueChanged,
    this.onPositionChanged,
    this.onDurationChanged,
  });

  /// The currently active cue index, or -1 if none.
  int get activeCueIndex => _activeCueIndex;

  /// Current playback position in ms.
  int get positionMs => _positionMs;

  /// Total duration in ms (0 if unknown).
  int get durationMs => _durationMs;

  /// Whether a seek operation is in progress.
  bool get isSeeking => _isSeeking;

  /// Starts listening to player time events.
  void start() {
    _sub = adapter.timeEvents.listen(_handleTimeEvent);
  }

  /// Stops listening and cleans up.
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _handleTimeEvent(PlayerTimeEvent event) {
    _positionMs = event.positionMs;
    if (event.durationMs != null && event.durationMs! > 0) {
      _durationMs = event.durationMs!;
      onDurationChanged?.call(_durationMs);
    }
    onPositionChanged?.call(_positionMs);

    if (_isSeeking) return;

    final newIdx = _findActiveCue(event.positionMs);
    if (newIdx != _activeCueIndex) {
      _activeCueIndex = newIdx;
      onActiveCueChanged?.call(newIdx);
    }
  }

  /// Finds the cue index that contains [positionMs], or the nearest cue
  /// if within a small gap tolerance.
  int _findActiveCue(int positionMs) {
    final cues = track.cues;
    if (cues.isEmpty) return -1;

    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      if (positionMs >= cue.startMs && positionMs <= cue.endMs) {
        return i;
      }
    }

    // If we're before the first cue or after the last, no active cue.
    return -1;
  }

  /// Seeks the player to the start of cue at [cueIndex].
  Future<void> seekToCue(int cueIndex) async {
    if (cueIndex < 0 || cueIndex >= track.cues.length) return;
    final cue = track.cues[cueIndex];
    _isSeeking = true;
    _activeCueIndex = cueIndex;
    onActiveCueChanged?.call(cueIndex);
    try {
      await adapter.seekTo(cue.startMs);
    } finally {
      _isSeeking = false;
    }
  }

  /// Seeks the player to a specific timestamp in ms.
  Future<void> seekToPosition(int ms) async {
    _isSeeking = true;
    try {
      await adapter.seekTo(ms);
      _positionMs = ms;
      onPositionChanged?.call(ms);
      final newIdx = _findActiveCue(ms);
      if (newIdx != _activeCueIndex) {
        _activeCueIndex = newIdx;
        onActiveCueChanged?.call(newIdx);
      }
    } finally {
      _isSeeking = false;
    }
  }

  /// Disposes the controller.
  void dispose() {
    stop();
  }
}