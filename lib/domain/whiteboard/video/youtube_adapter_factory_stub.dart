/// Stub factory for the YouTube adapter on non-web platforms.
///
/// Returns a [StubYouTubePlayerAdapter] that declares YouTube capabilities
/// but does not construct a real [WebViewController] (which requires
/// `WebViewPlatform.instance` and is only available on Android). The stub's
/// `isAvailable` is always `false`.
///
/// On Android specifically, callers should construct [YouTubePlayerAdapter]
/// directly (it will work because `WebViewPlatform.instance` is set by the
/// `webview_flutter_android` plugin). This factory is a safe default for
/// platforms that can't run a real WebView.
library;

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

/// A no-op YouTube adapter for platforms without WebView (e.g. Windows/Linux
/// desktop, Dart VM test runner). Declares the YouTube capability matrix
/// values so callers can read `providerId` / `capability` without crashing, but
/// `isAvailable` is `false` and all playback methods are no-ops.
class StubYouTubePlayerAdapter implements PlayerAdapter {
  @override
  String get providerId => 'youtube';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor('youtube');

  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();

  /// Always `false` — this stub cannot play video.
  bool get isAvailable => false;

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<int> currentPositionMs() async => 0;

  @override
  Future<int?> durationMs() async => null;

  @override
  Future<void> seekTo(int positionMs) async {}
}

/// Creates a [PlayerAdapter] for YouTube on non-web platforms.
///
/// Returns [StubYouTubePlayerAdapter], a safe no-op. On Android, callers should
/// construct [YouTubePlayerAdapter] directly.
PlayerAdapter createYouTubeAdapterForPlatform() => StubYouTubePlayerAdapter();