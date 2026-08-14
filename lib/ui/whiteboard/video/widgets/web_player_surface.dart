/// Stub for the Web YouTube player surface on non-web platforms.
///
/// Returns `null` — the player panel falls through to the native WebView or
/// fixture surface. On web, the conditional import resolves to
/// `web_player_surface_web.dart` which renders the IFrame via
/// `HtmlElementView`.
library;

import 'package:flutter/widgets.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';

/// Returns the Web YouTube IFrame surface, or `null` on non-web platforms.
Widget? buildWebYouTubeSurface(PlayerAdapter adapter) => null;