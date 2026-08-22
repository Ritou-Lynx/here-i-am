// Copyright 2024 The Memex team. All rights reserved.
// Compass-aligned: ui/core/themes/

import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

/// Application theme (Compass-aligned: centralised in ui/core/themes).
///
/// The global [MaterialApp] theme is now driven by [SpringRainUiTheme.build]
/// so every route — even those without an explicit [SpringRainUiScope] —
/// inherits the 春雨昼眠 daylight token system instead of the legacy
/// indigo-seeded Material palette.
abstract final class AppTheme {
  AppTheme._();

  static const Color scaffoldBackgroundLight = AppColors.background;

  static ThemeData get lightTheme => lightThemeFor(HereIamThemeTokens.current);

  static ThemeData lightThemeFor([
    HereIamThemeTokens tokens = HereIamThemeTokens.current,
  ]) {
    final base = ThemeData(
      useMaterial3: true,
      extensions: [tokens],
    );
    return SpringRainUiTheme.build(
      base,
      tokens: SpringRainUiTokens.daylight,
    );
  }

  static ThemeData get darkTheme => darkThemeFor(HereIamThemeTokens.current);

  static ThemeData darkThemeFor([
    HereIamThemeTokens tokens = HereIamThemeTokens.current,
  ]) {
    final base = ThemeData(
      useMaterial3: true,
      extensions: [tokens],
    );
    return SpringRainUiTheme.build(
      base,
      tokens: SpringRainUiTokens.daylight,
    );
  }
}
