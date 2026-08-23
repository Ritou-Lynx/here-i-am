/// Desktop-only Lieflat Palm semantic tokens.
///
/// The desktop workbench deliberately owns a scoped theme instead of changing
/// the app-wide Spring Rain theme used by the mobile companion surfaces.
library;

import 'package:flutter/material.dart';

import '../whiteboard/fonts.dart';

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
    final transparentSurface = tokens.surface.withValues(alpha: 0);
    final scheme = ColorScheme.light(
      primary: tokens.action,
      onPrimary: tokens.canvas,
      primaryContainer: tokens.actionSoft,
      onPrimaryContainer: tokens.dark,
      secondary: tokens.actionSecondary,
      onSecondary: tokens.canvas,
      secondaryContainer: tokens.surfaceRaised,
      onSecondaryContainer: tokens.textPrimary,
      tertiary: tokens.focus,
      onTertiary: tokens.dark,
      tertiaryContainer: tokens.surfaceRaised,
      onTertiaryContainer: tokens.textPrimary,
      error: tokens.error,
      onError: tokens.canvas,
      errorContainer: tokens.error.withValues(alpha: 0.12),
      onErrorContainer: tokens.error,
      surface: tokens.canvas,
      onSurface: tokens.textPrimary,
      surfaceContainerHighest: tokens.surfaceRaised,
      onSurfaceVariant: tokens.textMuted,
      outline: tokens.textFaint,
      outlineVariant: tokens.divider,
      shadow: tokens.dark,
      scrim: tokens.dark.withValues(alpha: 0.48),
      inverseSurface: tokens.dark,
      onInverseSurface: tokens.canvas,
      inversePrimary: tokens.actionSoft,
      surfaceTint: transparentSurface,
    );
    final dialogTitleStyle = whiteboardUiTextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: tokens.textPrimary,
    );
    final dialogContentStyle = whiteboardUiTextStyle(
      fontSize: 14,
      height: 1.45,
      color: tokens.textMuted,
    );
    final buttonTextStyle = whiteboardUiTextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: tokens.divider),
    );
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: tokens.canvas,
        canvasColor: tokens.canvas,
        cardColor: tokens.surfaceRaised,
        dividerColor: tokens.divider,
        disabledColor: tokens.textFaint,
        focusColor: tokens.focus.withValues(alpha: 0.18),
        hoverColor: tokens.action.withValues(alpha: 0.08),
        highlightColor: tokens.actionSoft.withValues(alpha: 0.24),
        splashColor: tokens.actionSoft.withValues(alpha: 0.18),
        colorScheme: scheme,
        iconTheme: IconThemeData(color: tokens.textMuted),
        dividerTheme: DividerThemeData(color: tokens.divider, thickness: 1),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: tokens.dark,
          contentTextStyle: whiteboardUiTextStyle(
            fontSize: 14,
            color: tokens.canvas,
          ),
          actionTextColor: tokens.actionSoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: tokens.surfaceRaised,
          labelStyle: whiteboardUiTextStyle(color: tokens.textMuted),
          hintStyle: whiteboardUiTextStyle(color: tokens.textFaint),
          helperStyle: whiteboardUiTextStyle(color: tokens.textMuted),
          errorStyle: whiteboardUiTextStyle(color: tokens.error),
          prefixIconColor: tokens.textMuted,
          suffixIconColor: tokens.textMuted,
          border: inputBorder,
          enabledBorder: inputBorder,
          disabledBorder: inputBorder.copyWith(
            borderSide: BorderSide(
              color: tokens.divider.withValues(alpha: 0.56),
            ),
          ),
          focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: tokens.action, width: 1.5),
          ),
          errorBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: tokens.error),
          ),
          focusedErrorBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: tokens.error, width: 1.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? tokens.textFaint
                  : tokens.action;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.pressed)
                  ? tokens.actionSoft.withValues(alpha: 0.22)
                  : transparentSurface;
            }),
            overlayColor: WidgetStatePropertyAll(
              tokens.actionSoft.withValues(alpha: 0.18),
            ),
            side: WidgetStateProperty.resolveWith((states) {
              return BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? tokens.divider
                    : tokens.actionSecondary,
              );
            }),
            textStyle: WidgetStatePropertyAll(buttonTextStyle),
            iconColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? tokens.textFaint
                  : tokens.action;
            }),
            shape: WidgetStatePropertyAll(buttonShape),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? tokens.textMuted
                  : tokens.canvas;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? tokens.divider
                  : tokens.action;
            }),
            overlayColor: WidgetStatePropertyAll(
              tokens.actionSoft.withValues(alpha: 0.24),
            ),
            textStyle: WidgetStatePropertyAll(buttonTextStyle),
            iconColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? tokens.textMuted
                  : tokens.canvas;
            }),
            shape: WidgetStatePropertyAll(buttonShape),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? tokens.textFaint
                  : tokens.action;
            }),
            overlayColor: WidgetStatePropertyAll(
              tokens.actionSoft.withValues(alpha: 0.18),
            ),
            textStyle: WidgetStatePropertyAll(buttonTextStyle),
            iconColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? tokens.textFaint
                  : tokens.action;
            }),
            shape: WidgetStatePropertyAll(buttonShape),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return tokens.textFaint;
              }
              if (states.contains(WidgetState.selected)) {
                return tokens.canvas;
              }
              return tokens.textMuted;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? tokens.action
                  : transparentSurface;
            }),
            overlayColor: WidgetStatePropertyAll(
              tokens.actionSoft.withValues(alpha: 0.2),
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          elevation: 0,
          backgroundColor: tokens.surfaceRaised,
          surfaceTintColor: transparentSurface,
          titleTextStyle: dialogTitleStyle,
          contentTextStyle: dialogContentStyle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: tokens.divider),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          elevation: 0,
          color: tokens.surfaceRaised,
          surfaceTintColor: transparentSurface,
          textStyle: whiteboardUiTextStyle(color: tokens.textPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: tokens.divider),
          ),
        ),
        extensions: [
          ...base.extensions.values.where(
            (extension) => extension is! DesktopWorkspaceTokens,
          ),
          tokens,
        ],
      ),
      child: child,
    );
  }
}
