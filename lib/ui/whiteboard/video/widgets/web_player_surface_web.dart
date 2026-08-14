/// Web YouTube player surface — renders the YouTube IFrame via
/// `HtmlElementView`.
///
/// On Flutter Web, [WebYouTubePlayerAdapter] embeds a `YT.Player` in a
/// platform view identified by `viewTypeId`. This widget surfaces that view.
library;

import 'package:flutter/widgets.dart';

import 'package:memex/domain/whiteboard/video/web_youtube_player_adapter.dart';

/// Returns the Web YouTube IFrame surface if [adapter] is a ready
/// [WebYouTubePlayerAdapter], otherwise `null`.
Widget? buildWebYouTubeSurface(dynamic adapter) {
  if (adapter is WebYouTubePlayerAdapter && adapter.isAvailable) {
    return HtmlElementView(viewType: adapter.viewTypeId);
  }
  return null;
}