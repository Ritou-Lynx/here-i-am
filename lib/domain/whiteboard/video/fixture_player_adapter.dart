/// A deterministic local player adapter for testing and desktop verification.
///
/// [FixturePlayerAdapter] simulates a real video player with a fixed duration,
/// simulated playback progression, and controllable seek. It emits
/// [PlayerTimeEvent]s via a [StreamController] so the entire sync pipeline
/// can be tested without a real WebView or network connection.
///
/// **Product identity**: this is a TEST / demo provider. It is not a real
/// platform and must never appear in the production provider list
/// ([ProviderCapabilityMatrix.productionProviders]). It declares full
/// capabilities (including `hasTranscript`) so the fixture closed loop is
/// testable, but its declarations do not imply any real-platform support.
library;

import 'dart:async';

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

class FixturePlayerAdapter implements PlayerAdapter {
  final int _durationMs;
  final Duration _tickInterval;
  final int _tickMs;

  bool _isPlaying = false;
  bool _isLoaded = false;
  int _positionMs = 0;
  String? _loadedSourceId;
  Timer? _timer;
  final StreamController<PlayerTimeEvent> _timeController =
      StreamController<PlayerTimeEvent>.broadcast();

  FixturePlayerAdapter({
    int durationMs = 300000,
    Duration tickInterval = const Duration(milliseconds: 100),
    int tickMs = 100,
  })  : _durationMs = durationMs,
        _tickInterval = tickInterval,
        _tickMs = tickMs;

  @override
  String get providerId => 'fixture';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor('fixture');

  @override
  Stream<PlayerTimeEvent> get timeEvents => _timeController.stream;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    _loadedSourceId = sourceId;
    _isLoaded = true;
    _positionMs = 0;
    _timeController.add(PlayerTimeEvent(
      positionMs: 0,
      durationMs: _durationMs,
      at: DateTime.now(),
    ));
  }

  @override
  Future<void> play() async {
    if (!_isLoaded) return;
    _isPlaying = true;
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) {
      if (!_isPlaying) return;
      _positionMs = (_positionMs + _tickMs).clamp(0, _durationMs);
      _timeController.add(PlayerTimeEvent(
        positionMs: _positionMs,
        durationMs: _durationMs,
        at: DateTime.now(),
      ));
      if (_positionMs >= _durationMs) {
        _isPlaying = false;
        _timer?.cancel();
      }
    });
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _timer?.cancel();
  }

  @override
  Future<int> currentPositionMs() async => _positionMs;

  @override
  Future<int?> durationMs() async => _durationMs;

  @override
  Future<void> seekTo(int positionMs) async {
    _positionMs = positionMs.clamp(0, _durationMs);
    _timeController.add(PlayerTimeEvent(
      positionMs: _positionMs,
      durationMs: _durationMs,
      at: DateTime.now(),
    ));
  }

  /// Jumps position forward by [ms] milliseconds (for testing).
  Future<void> advanceBy(int ms) async {
    _positionMs = (_positionMs + ms).clamp(0, _durationMs);
    _timeController.add(PlayerTimeEvent(
      positionMs: _positionMs,
      durationMs: _durationMs,
      at: DateTime.now(),
    ));
  }

  /// Whether the fixture is currently loaded.
  bool get isLoaded => _isLoaded;

  /// Whether the fixture is currently playing.
  bool get isPlaying => _isPlaying;

  /// The loaded source ID, or null.
  String? get loadedSourceId => _loadedSourceId;

  /// Disposes the adapter and closes the stream.
  void dispose() {
    _timer?.cancel();
    _timeController.close();
  }
}