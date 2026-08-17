/// Desktop shell visual tokens — mirrors the web MVP (`desktop/whiteboard_mvp/
/// styles.css`) Lieflat Mono palette using existing [WhiteboardCanvasTokens]
/// and [SpringRainUiTokens] values so desktop and mobile share one source of
/// truth for color semantics.
///
/// These tokens are ONLY for the desktop shell chrome (sidebar, page heads,
/// module cards, board tiles). Canvas internals, rich text editor and video
/// dock keep using their own tokens.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Desktop shell tokens. Const colors mirror web MVP `:root` CSS variables.
class DesktopShellTokens {
  DesktopShellTokens._();

  // Surface (web MVP `--hia-*`)
  static const Color canvas = WhiteboardCanvasTokens.canvas; // #F0EFEB
  static const Color surface = Color(0x28FFFFFF); // --hia-surface
  static const Color surfaceRaised = Color(0xFFF8F7F3); // --hia-surface-raised
  static const Color surfaceSoft = Color(0xFFE5E4DF); // --hia-surface-soft

  // Text
  static const Color textPrimary = WhiteboardCanvasTokens.textPrimary; // #34332F
  static const Color textMuted = WhiteboardCanvasTokens.textSecondary; // #74726C
  static const Color textFaint = WhiteboardCanvasTokens.textFaint; // #999790

  // Divider
  static const Color divider = Color(0x21B5B2A8); // --hia-divider
  static const Color dividerStrong = Color(0xFFD2D1CB); // --hia-divider-strong

  // Palm action
  static const Color green = WhiteboardCanvasTokens.action; // #43593B
  static const Color greenMid = WhiteboardCanvasTokens.actionSecondary; // #77835A
  static const Color greenLight = WhiteboardCanvasTokens.actionSoft; // #ACAD79
  static const Color greenSoft = Color(0x24ACAD79); // --hia-green-soft

  // Gold focus
  static const Color gold = WhiteboardCanvasTokens.focus; // #D4A017
  static const Color goldSoft = Color(0x29D4A017); // --hia-gold-soft

  static const Color dark = WhiteboardCanvasTokens.dark; // #28311F

  // Shape
  static const double radius = 10.0;
  static const double radiusSmall = 8.0;
  static const double radiusPill = 999.0;
  static const double sidebarWidth = 148.0;

  // Typography sizes (web MVP §4)
  static const double pageTitle = 24.0;
  static const double moduleTitle = 15.0;
  static const double content = 14.0;
  static const double meta = 12.0;
  static const double status = 11.0;
  static const double metricValue = 21.0;
  static const double boardTileTitle = 17.0;

  // Elevation
  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x1A34332F),
      blurRadius: 34,
      offset: Offset(0, 14),
    ),
  ];
}