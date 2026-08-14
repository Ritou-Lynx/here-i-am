import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';

/// Semantic application tokens for the daylight side of "春雨昼眠".
///
/// [HereIamThemeTokens] describes the dark companion world and rain glass.
/// This extension describes ordinary product surfaces: settings, forms,
/// dialogs, status feedback and detail pages. UI code should consume semantic
/// names from this class instead of adding new literal colors.
@immutable
class SpringRainUiTokens extends ThemeExtension<SpringRainUiTokens> {
  const SpringRainUiTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.surfaceSelected,
    required this.glassFill,
    required this.glassStroke,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnAccent,
    required this.icon,
    required this.iconMuted,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.gold,
    required this.goldSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.error,
    required this.errorSoft,
    required this.info,
    required this.infoSoft,
    required this.outline,
    required this.divider,
    required this.focus,
    required this.disabled,
    required this.scrim,
    required this.space2,
    required this.space4,
    required this.space6,
    required this.space8,
    required this.space12,
    required this.space16,
    required this.space20,
    required this.space24,
    required this.space32,
    required this.space40,
    required this.radius6,
    required this.radius10,
    required this.radius14,
    required this.radius18,
    required this.radius24,
    required this.radius28,
    required this.radiusPill,
    required this.controlSmall,
    required this.controlMedium,
    required this.controlLarge,
    required this.iconSmall,
    required this.iconMedium,
    required this.iconLarge,
  });

  // Surfaces.
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color surfaceSelected;
  final Color glassFill;
  final Color glassStroke;

  // Content.
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnAccent;
  final Color icon;
  final Color iconMuted;

  // Brand and interaction.
  final Color accent;
  final Color accentPressed;
  final Color accentSoft;
  final Color gold;
  final Color goldSoft;

  // Status colors always travel with a soft container color.
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color error;
  final Color errorSoft;
  final Color info;
  final Color infoSoft;

  // Borders and overlays.
  final Color outline;
  final Color divider;
  final Color focus;
  final Color disabled;
  final Color scrim;

  // 2 / 4 / 6 / 8 / 12 / 16 / 20 / 24 / 32 / 40 spacing scale.
  final double space2;
  final double space4;
  final double space6;
  final double space8;
  final double space12;
  final double space16;
  final double space20;
  final double space24;
  final double space32;
  final double space40;

  // Shape scale.
  final double radius6;
  final double radius10;
  final double radius14;
  final double radius18;
  final double radius24;
  final double radius28;
  final double radiusPill;

  // Control and icon scale.
  final double controlSmall;
  final double controlMedium;
  final double controlLarge;
  final double iconSmall;
  final double iconMedium;
  final double iconLarge;

  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionNormal = Duration(milliseconds: 220);
  static const Duration motionSlow = Duration(milliseconds: 360);

  // Public constants used by const widgets before a BuildContext exists.
  static const Color daylightCanvas = Color(0xFFF8F6EB);
  static const Color daylightSurface = Color(0xFFFCFAF1);
  static const Color daylightSurfaceRaised = Color(0xFFFFFDF7);
  static const Color daylightSurfaceMuted = Color(0xFFEDE9D8);
  static const Color daylightTextPrimary = Color(0xFF293025);
  static const Color daylightTextSecondary = Color(0xFF74766E);
  static const Color daylightTextTertiary = Color(0xFF999B91);
  static const Color daylightTextOnAccent = Color(0xFFFFFDF5);
  static const Color daylightIcon = Color(0xFF59603C);
  static const Color daylightIconMuted = Color(0xFF8C8F82);
  static const Color daylightAccent = Color(0xFF6E7541);
  static const Color daylightAccentSoft = Color(0xFFE7E8D1);
  static const Color daylightGold = Color(0xFFF2CA70);
  static const Color daylightSuccess = Color(0xFF577254);
  static const Color daylightSuccessSoft = Color(0xFFE3ECDC);
  static const Color daylightWarning = Color(0xFF9A702E);
  static const Color daylightWarningSoft = Color(0xFFF7E8BE);
  static const Color daylightError = Color(0xFF9B5B52);
  static const Color daylightErrorSoft = Color(0xFFF3DFD9);
  static const Color daylightDivider = Color(0x1F5B5843);

  static const SpringRainUiTokens daylight = SpringRainUiTokens(
    canvas: daylightCanvas,
    surface: daylightSurface,
    surfaceRaised: Color(0xFFFFFDF7),
    surfaceMuted: daylightSurfaceMuted,
    surfaceSelected: Color(0xFFE3E5C9),
    glassFill: Color(0xDDF8F6EB),
    glassStroke: Color(0x73FFFFFF),
    textPrimary: daylightTextPrimary,
    textSecondary: daylightTextSecondary,
    textTertiary: daylightTextTertiary,
    textOnAccent: daylightTextOnAccent,
    icon: daylightIcon,
    iconMuted: daylightIconMuted,
    accent: daylightAccent,
    accentPressed: Color(0xFF555D31),
    accentSoft: daylightAccentSoft,
    gold: daylightGold,
    goldSoft: Color(0xFFF7E8BE),
    success: daylightSuccess,
    successSoft: daylightSuccessSoft,
    warning: daylightWarning,
    warningSoft: daylightWarningSoft,
    error: daylightError,
    errorSoft: daylightErrorSoft,
    info: Color(0xFF526E72),
    infoSoft: Color(0xFFDDE9E7),
    outline: Color(0x405B5843),
    divider: daylightDivider,
    focus: Color(0x806E7541),
    disabled: Color(0x6174766E),
    scrim: Color(0x70293025),
    space2: 2,
    space4: 4,
    space6: 6,
    space8: 8,
    space12: 12,
    space16: 16,
    space20: 20,
    space24: 24,
    space32: 32,
    space40: 40,
    radius6: 6,
    radius10: 10,
    radius14: 14,
    radius18: 18,
    radius24: 24,
    radius28: 28,
    radiusPill: 999,
    controlSmall: 36,
    controlMedium: 44,
    controlLarge: 52,
    iconSmall: 16,
    iconMedium: 20,
    iconLarge: 24,
  );

  List<BoxShadow> get shadowLow => const [
        BoxShadow(
          color: Color(0x0D293025),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ];

  List<BoxShadow> get shadowMedium => const [
        BoxShadow(
          color: Color(0x14293025),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];

  @override
  SpringRainUiTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? surfaceSelected,
    Color? glassFill,
    Color? glassStroke,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnAccent,
    Color? icon,
    Color? iconMuted,
    Color? accent,
    Color? accentPressed,
    Color? accentSoft,
    Color? gold,
    Color? goldSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? error,
    Color? errorSoft,
    Color? info,
    Color? infoSoft,
    Color? outline,
    Color? divider,
    Color? focus,
    Color? disabled,
    Color? scrim,
    double? space2,
    double? space4,
    double? space6,
    double? space8,
    double? space12,
    double? space16,
    double? space20,
    double? space24,
    double? space32,
    double? space40,
    double? radius6,
    double? radius10,
    double? radius14,
    double? radius18,
    double? radius24,
    double? radius28,
    double? radiusPill,
    double? controlSmall,
    double? controlMedium,
    double? controlLarge,
    double? iconSmall,
    double? iconMedium,
    double? iconLarge,
  }) {
    return SpringRainUiTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      glassFill: glassFill ?? this.glassFill,
      glassStroke: glassStroke ?? this.glassStroke,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      icon: icon ?? this.icon,
      iconMuted: iconMuted ?? this.iconMuted,
      accent: accent ?? this.accent,
      accentPressed: accentPressed ?? this.accentPressed,
      accentSoft: accentSoft ?? this.accentSoft,
      gold: gold ?? this.gold,
      goldSoft: goldSoft ?? this.goldSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      error: error ?? this.error,
      errorSoft: errorSoft ?? this.errorSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      outline: outline ?? this.outline,
      divider: divider ?? this.divider,
      focus: focus ?? this.focus,
      disabled: disabled ?? this.disabled,
      scrim: scrim ?? this.scrim,
      space2: space2 ?? this.space2,
      space4: space4 ?? this.space4,
      space6: space6 ?? this.space6,
      space8: space8 ?? this.space8,
      space12: space12 ?? this.space12,
      space16: space16 ?? this.space16,
      space20: space20 ?? this.space20,
      space24: space24 ?? this.space24,
      space32: space32 ?? this.space32,
      space40: space40 ?? this.space40,
      radius6: radius6 ?? this.radius6,
      radius10: radius10 ?? this.radius10,
      radius14: radius14 ?? this.radius14,
      radius18: radius18 ?? this.radius18,
      radius24: radius24 ?? this.radius24,
      radius28: radius28 ?? this.radius28,
      radiusPill: radiusPill ?? this.radiusPill,
      controlSmall: controlSmall ?? this.controlSmall,
      controlMedium: controlMedium ?? this.controlMedium,
      controlLarge: controlLarge ?? this.controlLarge,
      iconSmall: iconSmall ?? this.iconSmall,
      iconMedium: iconMedium ?? this.iconMedium,
      iconLarge: iconLarge ?? this.iconLarge,
    );
  }

  @override
  SpringRainUiTokens lerp(
    covariant ThemeExtension<SpringRainUiTokens>? other,
    double t,
  ) {
    if (other is! SpringRainUiTokens) return this;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    return SpringRainUiTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldSoft: Color.lerp(goldSoft, other.goldSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      space2: d(space2, other.space2),
      space4: d(space4, other.space4),
      space6: d(space6, other.space6),
      space8: d(space8, other.space8),
      space12: d(space12, other.space12),
      space16: d(space16, other.space16),
      space20: d(space20, other.space20),
      space24: d(space24, other.space24),
      space32: d(space32, other.space32),
      space40: d(space40, other.space40),
      radius6: d(radius6, other.radius6),
      radius10: d(radius10, other.radius10),
      radius14: d(radius14, other.radius14),
      radius18: d(radius18, other.radius18),
      radius24: d(radius24, other.radius24),
      radius28: d(radius28, other.radius28),
      radiusPill: d(radiusPill, other.radiusPill),
      controlSmall: d(controlSmall, other.controlSmall),
      controlMedium: d(controlMedium, other.controlMedium),
      controlLarge: d(controlLarge, other.controlLarge),
      iconSmall: d(iconSmall, other.iconSmall),
      iconMedium: d(iconMedium, other.iconMedium),
      iconLarge: d(iconLarge, other.iconLarge),
    );
  }
}

/// Material component mapping for ordinary Here I Am pages.
abstract final class SpringRainUiTheme {
  SpringRainUiTheme._();

  static ThemeData build(
    ThemeData base, {
    SpringRainUiTokens tokens = SpringRainUiTokens.daylight,
  }) {
    final scheme = ColorScheme.light(
      primary: tokens.accent,
      onPrimary: tokens.textOnAccent,
      primaryContainer: tokens.accentSoft,
      onPrimaryContainer: tokens.textPrimary,
      secondary: tokens.gold,
      onSecondary: tokens.textPrimary,
      secondaryContainer: tokens.goldSoft,
      onSecondaryContainer: tokens.textPrimary,
      tertiary: tokens.info,
      onTertiary: tokens.textOnAccent,
      error: tokens.error,
      onError: tokens.textOnAccent,
      errorContainer: tokens.errorSoft,
      onErrorContainer: tokens.error,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      outline: tokens.outline,
      outlineVariant: tokens.divider,
      shadow: const Color(0xFF293025),
      scrim: tokens.scrim,
    );
    final text = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      headlineMedium: GoogleFonts.inter(
        color: tokens.textPrimary,
        fontSize: 24,
        height: 1.28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.inter(
        color: tokens.textPrimary,
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.inter(
        color: tokens.textPrimary,
        fontSize: 15.5,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.inter(
        color: tokens.textSecondary,
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.inter(
        color: tokens.textPrimary,
        fontSize: 16,
        height: 1.55,
      ),
      bodyMedium: GoogleFonts.inter(
        color: tokens.textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.inter(
        color: tokens.textTertiary,
        fontSize: 12,
        height: 1.45,
      ),
      labelLarge: GoogleFonts.inter(
        color: tokens.textPrimary,
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: GoogleFonts.inter(
        color: tokens.textSecondary,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radius14),
      borderSide: BorderSide(color: tokens.outline),
    );

    return base.copyWith(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      textTheme: text,
      iconTheme: IconThemeData(color: tokens.icon, size: tokens.iconMedium),
      dividerColor: tokens.divider,
      splashColor: tokens.accent.withValues(alpha: 0.08),
      highlightColor: tokens.accent.withValues(alpha: 0.05),
      focusColor: tokens.focus,
      disabledColor: tokens.disabled,
      extensions: <ThemeExtension<dynamic>>[
        HereIamThemeTokens.springRainDaydream,
        tokens,
      ],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: tokens.icon, size: tokens.iconMedium),
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius18),
          side: BorderSide(color: tokens.divider),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: tokens.space16),
        iconColor: tokens.icon,
        textColor: tokens.textPrimary,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
        minTileHeight: 60,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceRaised,
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.space16,
          vertical: tokens.space12,
        ),
        labelStyle: text.bodyMedium,
        hintStyle: text.bodyMedium?.copyWith(color: tokens.textTertiary),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: tokens.error),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: tokens.accent, width: 1.4),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: tokens.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: tokens.error, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, tokens.controlMedium),
          padding: EdgeInsets.symmetric(horizontal: tokens.space20),
          backgroundColor: tokens.accent,
          foregroundColor: tokens.textOnAccent,
          disabledBackgroundColor: tokens.disabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius14),
          ),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, tokens.controlMedium),
          padding: EdgeInsets.symmetric(horizontal: tokens.space20),
          foregroundColor: tokens.accent,
          side: BorderSide(color: tokens.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.icon,
          backgroundColor: Colors.transparent,
          highlightColor: tokens.accentSoft,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceMuted,
        selectedColor: tokens.accentSoft,
        disabledColor: tokens.disabled,
        side: BorderSide(color: tokens.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusPill),
        ),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: tokens.accent),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space8,
          vertical: tokens.space4,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.textOnAccent
              : tokens.surfaceRaised;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.all(tokens.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(tokens.textOnAccent),
        side: BorderSide(color: tokens.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius6),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.iconMuted;
        }),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius24),
          side: BorderSide(color: tokens.divider),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: tokens.surfaceRaised,
        modalBackgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.radius28),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: tokens.textPrimary,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: tokens.textOnAccent,
        ),
        actionTextColor: const Color(0xFFF2CA70),
        insetPadding: EdgeInsets.fromLTRB(
          tokens.space16,
          0,
          tokens.space16,
          tokens.space16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius14),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.divider,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accent,
        linearTrackColor: tokens.surfaceMuted,
        circularTrackColor: tokens.surfaceMuted,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        textStyle: text.bodyMedium?.copyWith(color: tokens.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius14),
          side: BorderSide(color: tokens.divider),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.textPrimary,
          borderRadius: BorderRadius.circular(tokens.radius10),
        ),
        textStyle: text.bodySmall?.copyWith(color: tokens.textOnAccent),
      ),
    );
  }
}

/// Applies the full daylight token system to a nested route.
class SpringRainUiScope extends StatelessWidget {
  const SpringRainUiScope({
    required this.child,
    super.key,
    this.tokens = SpringRainUiTokens.daylight,
  });

  final Widget child;
  final SpringRainUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SpringRainUiTheme.build(Theme.of(context), tokens: tokens),
      child: child,
    );
  }
}

extension SpringRainUiLookup on BuildContext {
  SpringRainUiTokens get springRainUi {
    return Theme.of(this).extension<SpringRainUiTokens>() ??
        SpringRainUiTokens.daylight;
  }
}
