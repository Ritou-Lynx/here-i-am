/// Web factory for the YouTube adapter.
///
/// Returns a [WebYouTubePlayerAdapter] that drives the YouTube IFrame Player
/// API via `dart:js_interop`.
library;

import '../player_adapter.dart';
import 'web_youtube_player_adapter.dart';

/// Creates a [PlayerAdapter] for YouTube on Flutter Web.
PlayerAdapter createYouTubeAdapterForPlatform() => WebYouTubePlayerAdapter();