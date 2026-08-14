/// Whiteboard canvas visual tokens — reuses the frozen visual rules.
///
/// These tokens map to the semantic roles defined in
/// `docs/design/whiteboard-visual-rules.md` and
/// `docs/design/whiteboard-component-spec.md`.
///
/// W1 does NOT create a new color system — it provides concrete values
/// for the canvas surface, pending full integration with
/// `SpringRainUiTokens` by W0.
library;

import 'package:flutter/material.dart';

class WhiteboardCanvasTokens {
  WhiteboardCanvasTokens._();

  // Surface
  static const Color canvas = Color(0xFFF0EFEB);
  static const Color cardSurface = Color(0x28FFFFFF);
  static const Color cardSurfaceSelected = Color(0xE3E5C9FF);
  static const Color cardBorder = Color(0x21B5B2A8);
  static const Color cardBorderSelected = Color(0xFF6E7541);

  // Text
  static const Color textPrimary = Color(0xFF34332F);
  static const Color textSecondary = Color(0xFF74726C);
  static const Color textFaint = Color(0xFF999790);

  // Action
  static const Color action = Color(0xFF43593B);
  static const Color actionSecondary = Color(0xFF77835A);
  static const Color actionSoft = Color(0xFFACAD79);
  static const Color focus = Color(0xFFD4A017);
  static const Color dark = Color(0xFF28311F);

  // Divider / outline
  static const Color divider = Color(0x21B5B2A8);
  static const Color edge = Color(0xFF77835A);
  static const Color edgeSelected = Color(0xFF43593B);
  static const Color edgeLabel = Color(0xFF74726C);

  // Orphaned card (dangling card reference)
  static const Color orphanedBorder = Color(0xFF9B5B52);
  static const Color orphanedSurface = Color(0x1A9B5B52);

  // Group
  static const Color groupRect = Color(0x14ACAD79);
  static const Color groupBorder = Color(0x4DACAD79);
  static const Color groupLabel = Color(0xFF74726C);

  // Selection box (marquee)
  static const Color selectionBox = Color(0x4D6E7541);
  static const Color selectionBoxBorder = Color(0xFF6E7541);

  // Geometry
  static const double cardRadius = 10.0;
  static const double groupRadius = 14.0;
  static const double cardBorderWidth = 1.0;
  static const double cardBorderWidthSelected = 2.0;
  static const double edgeWidth = 1.5;
  static const double edgeWidthSelected = 2.5;

  // Typography
  static const double titleSize = 14.0;
  static const double bodySize = 14.0;
  static const double metaSize = 12.0;
  static const double statusSize = 11.0;
  static const double groupTitleSize = 15.0;
}