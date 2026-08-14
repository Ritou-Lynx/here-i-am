/// Platform-routed factory for the YouTube player adapter.
///
/// Uses conditional imports to return the correct implementation:
/// - On Flutter Web: [WebYouTubePlayerAdapter] (drives the IFrame API via
///   `dart:js_interop`).
/// - On other platforms: [YouTubePlayerAdapter] (webview_flutter on Android,
///   no-op stub elsewhere).
///
/// This file exists so that the `dart:js_interop`-dependent Web adapter is
/// only compiled when targeting the web platform. Importing it from native
/// tests will pull in the stub implementation instead.
library;

import '../player_adapter.dart';
import 'youtube_adapter_factory_stub.dart'
    if (dart.library.js_interop) 'youtube_adapter_factory_web.dart';

/// Creates a [PlayerAdapter] for YouTube on the current platform.
///
/// - On Flutter Web: returns a [WebYouTubePlayerAdapter] driving the IFrame API.
/// - On Android: returns a [YouTubePlayerAdapter] using `webview_flutter`.
/// - On other platforms: returns a [YouTubePlayerAdapter] stub (always
///   `isAvailable == false`).
PlayerAdapter createYouTubeAdapter() => createYouTubeAdapterForPlatform();