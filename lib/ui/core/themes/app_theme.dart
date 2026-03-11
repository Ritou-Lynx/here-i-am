// Copyright 2024 The Memex team. All rights reserved.
// Compass-aligned: ui/core/themes/

import 'package:flutter/material.dart';

/// Application theme (Compass-aligned: centralised in ui/core/themes).
abstract final class AppTheme {
  AppTheme._();

  /// Slate-100
  static const Color scaffoldBackgroundLight = Color(0xFFF1F5F9);

  /// Indigo seed
  static const Color seedColor = Color(0xFF6366F1);

  static ThemeData get lightTheme => ThemeData(
        scaffoldBackgroundColor: scaffoldBackgroundLight,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      );

  static ThemeData get darkTheme => ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      );
}
