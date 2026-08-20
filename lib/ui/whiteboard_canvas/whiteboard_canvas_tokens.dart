/// Whiteboard canvas visual roles derived from the M0 desktop workspace theme.
///
/// The canvas keeps a small adapter because it needs domain-specific roles such
/// as edge, group, and marquee colours. Their source of truth remains
/// [DesktopWorkspaceTokens]; this file does not define another desktop palette.
library;

import 'package:flutter/material.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';

@immutable
class WhiteboardCanvasColors {
  const WhiteboardCanvasColors(this.workspace);

  final DesktopWorkspaceTokens workspace;

  Color get canvas => workspace.canvas;
  Color get cardSurface => workspace.surface;

  /// Compatibility face for the existing selected-card visual contract.
  ///
  /// Selection state continues to be determined by the ViewModel and rendered
  /// with the action border/focus ring. This colour never determines selection.
  Color get cardSurfaceSelected => WhiteboardCanvasTokens.cardSurfaceSelected;
  Color get cardBorder => workspace.divider;
  Color get cardBorderSelected => workspace.action;
  Color get panelSurface => workspace.surfaceRaised;

  Color get textPrimary => workspace.textPrimary;
  Color get textSecondary => workspace.textMuted;
  Color get textFaint => workspace.textFaint;

  Color get action => workspace.action;
  Color get actionSecondary => workspace.actionSecondary;
  Color get actionSoft => workspace.actionSoft;
  Color get focus => workspace.focus;
  Color get dark => workspace.dark;

  Color get divider => workspace.divider;
  Color get edge => workspace.actionSecondary;
  Color get edgeSelected => workspace.action;
  Color get edgeLabel => workspace.textMuted;

  Color get orphanedBorder => workspace.error;
  Color get orphanedSurface => workspace.error.withValues(alpha: 0.10);

  Color get groupRect => workspace.actionSoft.withValues(alpha: 0.08);
  Color get groupBorder => workspace.actionSoft.withValues(alpha: 0.30);
  Color get groupLabel => workspace.textMuted;

  Color get selectionBox => workspace.action.withValues(alpha: 0.18);
  Color get selectionBoxBorder => workspace.action;
  Color get selectionFocus => workspace.action.withValues(alpha: 0.14);
  Color get gridDot => workspace.textMuted.withValues(alpha: 0.13);
  Color get floatingShadow => workspace.textPrimary.withValues(alpha: 0.14);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WhiteboardCanvasColors && other.workspace == workspace;

  @override
  int get hashCode => workspace.hashCode;
}

class WhiteboardCanvasTokens {
  WhiteboardCanvasTokens._();

  static WhiteboardCanvasColors of(BuildContext context) =>
      WhiteboardCanvasColors(DesktopWorkspaceTokens.of(context));

  // Compatibility constants used by the route-level loading/error shell. They
  // mirror the M0 fallback palette; the interactive canvas reads from context.
  static const Color canvas = Color(0xFFF0EFEB);
  static const Color cardSurface = Color(0x47FFFFFF);

  /// Correct AARRGGBB mapping for the selected face: opaque `#E3E5C9`.
  static const int cardSurfaceSelectedArgb = 0xFFE3E5C9;
  static const Color cardSurfaceSelected = Color(cardSurfaceSelectedArgb);
  static const Color cardBorder = Color(0x2134332F);
  static const Color cardBorderSelected = Color(0xFF43593B);
  static const Color panelSurface = Color(0xF4FFFDF7);

  static const Color textPrimary = Color(0xFF34332F);
  static const Color textSecondary = Color(0xFF74726C);
  static const Color textFaint = Color(0xFF999790);

  static const Color action = Color(0xFF43593B);
  static const Color actionSecondary = Color(0xFF77835A);
  static const Color actionSoft = Color(0xFFACAD79);
  static const Color focus = Color(0xFFD4A017);
  static const Color dark = Color(0xFF28311F);

  static const Color divider = Color(0x2134332F);
  static const Color edge = Color(0xFF77835A);
  static const Color edgeSelected = Color(0xFF43593B);
  static const Color edgeLabel = Color(0xFF74726C);

  static const Color orphanedBorder = Color(0xFF9B5B52);
  static const Color orphanedSurface = Color(0x1A9B5B52);

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
