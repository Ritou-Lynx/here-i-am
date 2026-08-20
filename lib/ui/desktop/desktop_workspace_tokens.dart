/// Desktop-only Lieflat Palm semantic tokens.
///
/// The desktop workbench deliberately owns a scoped theme instead of changing
/// the app-wide Spring Rain theme used by the mobile companion surfaces.
library;

import 'package:flutter/material.dart';

@immutable
class DesktopWorkspaceTokens extends ThemeExtension<DesktopWorkspaceTokens> {
  const DesktopWorkspaceTokens({
    required this.canvas,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.divider,
    required this.surface,
    required this.surfaceRaised,
    required this.action,
    required this.actionSecondary,
    required this.actionSoft,
    required this.focus,
    required this.dark,
    required this.error,
  });

  /// Frozen desktop palette from whiteboard-component-spec v0.2.
  static const lieflatPalm = DesktopWorkspaceTokens(
    canvas: Color(0xFFF0EFEB),
    textPrimary: Color(0xFF34332F),
    textMuted: Color(0xFF74726C),
    textFaint: Color(0xFF999790),
    divider: Color(0x2134332F),
    surface: Color(0x47FFFFFF),
    surfaceRaised: Color(0xF4FFFDF7),
    action: Color(0xFF43593B),
    actionSecondary: Color(0xFF77835A),
    actionSoft: Color(0xFFACAD79),
    focus: Color(0xFFD4A017),
    dark: Color(0xFF28311F),
    error: Color(0xFF9B5B52),
  );

  static const double sidebarExpandedWidth = 148;
  static const double sidebarHandleWidth = 34;
  static const double pageHorizontalPadding = 24;

  final Color canvas;
  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;
  final Color divider;
  final Color surface;
  final Color surfaceRaised;
  final Color action;
  final Color actionSecondary;
  final Color actionSoft;
  final Color focus;
  final Color dark;
  final Color error;

  static DesktopWorkspaceTokens of(BuildContext context) =>
      Theme.of(context).extension<DesktopWorkspaceTokens>() ?? lieflatPalm;

  @override
  DesktopWorkspaceTokens copyWith({
    Color? canvas,
    Color? textPrimary,
    Color? textMuted,
    Color? textFaint,
    Color? divider,
    Color? surface,
    Color? surfaceRaised,
    Color? action,
    Color? actionSecondary,
    Color? actionSoft,
    Color? focus,
    Color? dark,
    Color? error,
  }) {
    return DesktopWorkspaceTokens(
      canvas: canvas ?? this.canvas,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      divider: divider ?? this.divider,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      action: action ?? this.action,
      actionSecondary: actionSecondary ?? this.actionSecondary,
      actionSoft: actionSoft ?? this.actionSoft,
      focus: focus ?? this.focus,
      dark: dark ?? this.dark,
      error: error ?? this.error,
    );
  }

  @override
  DesktopWorkspaceTokens lerp(
    covariant DesktopWorkspaceTokens? other,
    double t,
  ) {
    if (other is! DesktopWorkspaceTokens) return this;
    return DesktopWorkspaceTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      action: Color.lerp(action, other.action, t)!,
      actionSecondary: Color.lerp(actionSecondary, other.actionSecondary, t)!,
      actionSoft: Color.lerp(actionSoft, other.actionSoft, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      dark: Color.lerp(dark, other.dark, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

/// Installs the desktop palette below this point without mutating the app-wide
/// mobile theme.
class DesktopWorkspaceTheme extends StatelessWidget {
  const DesktopWorkspaceTheme({
    super.key,
    required this.child,
    this.tokens = DesktopWorkspaceTokens.lieflatPalm,
  });

  final Widget child;
  final DesktopWorkspaceTokens tokens;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: tokens.canvas,
        canvasColor: tokens.canvas,
        colorScheme: base.colorScheme.copyWith(
          surface: tokens.canvas,
          primary: tokens.action,
          onPrimary: tokens.canvas,
          error: tokens.error,
        ),
        extensions: [
          ...base.extensions.values
              .where((extension) => extension is! DesktopWorkspaceTokens),
          tokens,
        ],
      ),
      child: child,
    );
  }
}
