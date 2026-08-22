import 'package:flutter/material.dart';

/// Centralized color constants.
///
/// Values now mirror the 春雨昼眠 (Spring Rain Daydream) daylight token
/// system defined in [SpringRainUiTokens]. Existing code that references
/// [AppColors] will automatically adopt the new palette without per-call-
/// site changes. New code should prefer `context.springRainUi` directly.
class AppColors {
  const AppColors._();

  // Brand — moss green accent (was indigo 0xFF5B6CFF)
  static const Color primary = Color(0xFF6E7541);

  // Backgrounds — warm ivory canvas (was cool grey 0xFFF7F8FA)
  static const Color background = Color(0xFFF8F6EB);
  static const Color cardBackground = Color(0xFFFCFAF1);
  static const Color iconBgLight = Color(0xFFE7E8D1);

  // Text — warm dark greens (was cool dark greys)
  static const Color textPrimary = Color(0xFF293025);
  static const Color textSecondary = Color(0xFF74766E);
  static const Color textTertiary = Color(0xFF999B91);

  // Navigation
  static const Color tabActive = Color(0xFF293025);
  static const Color tabInactive = Color(0xFF999B91);
  static const Color tagActiveBg = Color(0xFF6E7541);

  // Semantic
  static const Color success = Color(0xFF577254);
  static const Color warning = Color(0xFF9A702E);
  static const Color danger = Color(0xFF9B5B52);

  // Shadows (as Color values — use with BoxShadow)
  static const Color shadowLight = Color(0x0D293025); // 5% warm ink
  static const Color shadowCard = Color(0x0D293025); // card shadow

  // Here I Am companion theme: 暮雨玫瑰 / Dusky Rose Rain.
  static const Color companionBg = Color(0xFF241319);
  static const Color companionSurface = Color(0xFF4D222B);
  static const Color companionSurfaceSoft = Color(0xFF2A151B);
  static const Color companionSurfaceDeep = Color(0xFF5E4047);
  static const Color companionText = Color(0xFFF0D5D7);
  static const Color companionTextMuted = Color(0xB8EBD1C4);
  static const Color companionAccent = Color(0xFFE6D1D3);
  static const Color companionAccentSoft = Color(0xFFCDB6BA);

  // Avatar gradient — moss green (was indigo ramp)
  static const List<Color> avatarGradient = [
    Color(0xFF6E7541),
    Color(0xFF717843),
    Color(0xFF747B45),
    Color(0xFF777E47),
    Color(0xFF7A8149),
    Color(0xFF7D844B),
    Color(0xFF80874D),
    Color(0xFF838A4F),
    Color(0xFF868D51),
    Color(0xFF899053),
    Color(0xFF8C9355),
    Color(0xFF8F9657),
  ];

  static const List<double> avatarGradientStops = [
    0.0,
    0.0909,
    0.1818,
    0.2727,
    0.3636,
    0.4545,
    0.5455,
    0.6364,
    0.7273,
    0.8182,
    0.9091,
    1.0,
  ];
}
