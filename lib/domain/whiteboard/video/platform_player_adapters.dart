/// Bilibili and Xiaohongshu player adapter stubs.
///
/// These platforms do not provide official, public, controllable embeddable
/// players with readable time APIs. They are declared as "link-only" mode:
/// the user sees a link card that opens the platform's own app/website.
///
/// The adapters exist to:
/// 1. Honestly declare [PlayerCapability] — the UI reads this and does NOT
///    pretend the platform is fully supported.
/// 2. Provide a future extension point if Bilibili publishes an official
///    IFrame-like API.
///
/// See [ProviderCapabilityMatrix] for the evidence basis.
library;

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

/// Bilibili adapter — link-only mode.
///
/// Bilibili has an embeddable player (player.bilibili.com/player.html) but
/// does not expose an official JS API for getCurrentTime / getDuration /
/// seekTo. Without these, the playback-study workflow cannot function.
/// The adapter declares [canEmbedPlayer] = true but the rest as false.
class BilibiliPlayerAdapter implements PlayerAdapter {
  @override
  String get providerId => 'bilibili';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor('bilibili');

  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    // Link-only mode: no actual player load.
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<int> currentPositionMs() async => 0;

  @override
  Future<int?> durationMs() async => null;

  @override
  Future<void> seekTo(int positionMs) async {
    // Not supported — platform does not expose seek control.
  }

  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();
}

/// Xiaohongshu adapter — link-only mode.
///
/// Xiaohongshu does not provide an official web embed player. Short videos
/// are consumed within the Xiaohongshu app. This adapter is a stub that
/// declares no playback capabilities.
class XiaohongshuPlayerAdapter implements PlayerAdapter {
  @override
  String get providerId => 'xiaohongshu';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor('xiaohongshu');

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

  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();
}