import 'dart:ui';

import 'package:flutter/material.dart';

/// Product-level visual tokens for Here I Am skins.
///
/// These tokens are intentionally separate from Material's [ColorScheme]:
/// Material colors describe platform widgets, while these describe the
/// companion world surface: mist, glass, rain, text, and emotional accents.
@immutable
class HereIamThemeTokens extends ThemeExtension<HereIamThemeTokens> {
  const HereIamThemeTokens({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.brightness,
    required this.background,
    required this.backgroundSoft,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceDeep,
    required this.accent,
    required this.accentSoft,
    required this.highlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.glassFill,
    required this.glassFillSoft,
    required this.glassStroke,
    required this.glassEdge,
    required this.rainBead,
    required this.rainOpacity,
    required this.rainMicroOpacity,
    required this.rainStreakOpacity,
    required this.mistOpacity,
    required this.cardRadius,
    required this.innerRadius,
  });

  final String id;
  final String nameZh;
  final String nameEn;
  final Brightness brightness;

  final Color background;
  final Color backgroundSoft;
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceDeep;
  final Color accent;
  final Color accentSoft;
  final Color highlight;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color glassFill;
  final Color glassFillSoft;
  final Color glassStroke;
  final Color glassEdge;

  final Color rainBead;
  final double rainOpacity;
  final double rainMicroOpacity;
  final double rainStreakOpacity;
  final double mistOpacity;

  final double cardRadius;
  final double innerRadius;

  /// Current default: Rose Mist's night-facing product skin.
  static const HereIamThemeTokens current = duskyRoseRain;

  /// 暮雨玫瑰 / Dusky Rose Rain.
  static const HereIamThemeTokens duskyRoseRain = HereIamThemeTokens(
    id: 'duskyRoseRain',
    nameZh: '暮雨玫瑰',
    nameEn: 'Dusky Rose Rain',
    brightness: Brightness.dark,
    background: Color(0xFF241319),
    backgroundSoft: Color(0xFF120B0E),
    surface: Color(0xFF4D222B),
    surfaceSoft: Color(0xFF2A151B),
    surfaceDeep: Color(0xFF5E4047),
    accent: Color(0xFFE6D1D3),
    accentSoft: Color(0xFFCDB6BA),
    highlight: Color(0xFFCDB6BA),
    textPrimary: Color(0xFFF0D5D7),
    textSecondary: Color(0xB8EBD1C4),
    textMuted: Color(0x85E6CABE),
    glassFill: Color(0x0FFFFFFF),
    glassFillSoft: Color(0x05FFFFFF),
    glassStroke: Color(0x47EECDBF),
    glassEdge: Color(0x52FFECE2),
    rainBead: Color(0xCCFFECDD),
    rainOpacity: 0.42,
    rainMicroOpacity: 0.22,
    rainStreakOpacity: 0.38,
    mistOpacity: 0.62,
    cardRadius: 26,
    innerRadius: 19,
  );

  /// 玫瑰雾 / Rose Mist.
  ///
  /// The original daytime direction remains as a switchable skin.
  static const HereIamThemeTokens roseMistDay = HereIamThemeTokens(
    id: 'roseMistDay',
    nameZh: '玫瑰雾',
    nameEn: 'Rose Mist Day',
    brightness: Brightness.light,
    background: Color(0xFFF6F0EF),
    backgroundSoft: Color(0xFFF8F3F2),
    surface: Color(0xFFF8F3F2),
    surfaceSoft: Color(0xFFF1E8E8),
    surfaceDeep: Color(0xFFCDA0A6),
    accent: Color(0xFFC08E96),
    accentSoft: Color(0xFFE5C7CB),
    highlight: Color(0xFFD9B0B4),
    textPrimary: Color(0xFF5F4B4A),
    textSecondary: Color(0xFF6F5A59),
    textMuted: Color(0xFFA8908E),
    glassFill: Color(0x7DFFFFFF),
    glassFillSoft: Color(0x5CFFFFFF),
    glassStroke: Color(0x8FFFFFFF),
    glassEdge: Color(0x85FFFFFF),
    rainBead: Color(0x73FFFFFF),
    rainOpacity: 0.08,
    rainMicroOpacity: 0.05,
    rainStreakOpacity: 0.04,
    mistOpacity: 0.42,
    cardRadius: 26,
    innerRadius: 19,
  );

  /// 春雨昼眠 / Spring Rain Daydream — the current main UI direction.
  ///
  /// Palette is grounded in docs/design/春雨昼眠主题UI设计原型.md §22 and the
  /// chat tokens: near-black green surface, warm-ivory text, moss-green accent
  /// (ADR-13 user color), warm-gold highlight, and dew-glass panels.
  ///
  /// Intentionally NOT in [skins] yet: the global Material theme
  /// (AppTheme.lightThemeFor) still hardcodes light scaffold/appbar colors and
  /// does not follow these tokens, so exposing this as a globally switchable
  /// skin would render other pages half-styled. Non-chat pages that adopt the
  /// direction read this const directly (the same way Chat reads
  /// SpringRainChatTokens) until AppTheme learns to follow the tokens.
  static const HereIamThemeTokens springRainDaydream = HereIamThemeTokens(
    id: 'springRainDaydream',
    nameZh: '春雨昼眠',
    nameEn: 'Spring Rain Daydream',
    brightness: Brightness.dark,
    background: Color(0xFF0C0F0D),
    backgroundSoft: Color(0xFF080A09),
    surface: Color(0xFF161A12),
    surfaceSoft: Color(0xFF11150E),
    surfaceDeep: Color(0xFF222918),
    accent: Color(0xFFA3A866),
    accentSoft: Color(0xFF878C56),
    highlight: Color(0xFFF2CA70),
    textPrimary: Color(0xFFF5EEE0),
    textSecondary: Color(0xCCEDE6D5),
    textMuted: Color(0x85E6DFCE),
    glassFill: Color(0x0FFFFFFF),
    glassFillSoft: Color(0x08FFFFFF),
    glassStroke: Color(0x2EFFFFFF),
    glassEdge: Color(0x3DFFFFFF),
    rainBead: Color(0xCCF5EEE0),
    rainOpacity: 0.40,
    rainMicroOpacity: 0.20,
    rainStreakOpacity: 0.36,
    mistOpacity: 0.55,
    cardRadius: 20,
    innerRadius: 14,
  );

  static const List<HereIamThemeTokens> skins = [
    duskyRoseRain,
    roseMistDay,
  ];

  static HereIamThemeTokens byId(String id) {
    return skins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => current,
    );
  }

  @override
  HereIamThemeTokens copyWith({
    String? id,
    String? nameZh,
    String? nameEn,
    Brightness? brightness,
    Color? background,
    Color? backgroundSoft,
    Color? surface,
    Color? surfaceSoft,
    Color? surfaceDeep,
    Color? accent,
    Color? accentSoft,
    Color? highlight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? glassFill,
    Color? glassFillSoft,
    Color? glassStroke,
    Color? glassEdge,
    Color? rainBead,
    double? rainOpacity,
    double? rainMicroOpacity,
    double? rainStreakOpacity,
    double? mistOpacity,
    double? cardRadius,
    double? innerRadius,
  }) {
    return HereIamThemeTokens(
      id: id ?? this.id,
      nameZh: nameZh ?? this.nameZh,
      nameEn: nameEn ?? this.nameEn,
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      backgroundSoft: backgroundSoft ?? this.backgroundSoft,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceDeep: surfaceDeep ?? this.surfaceDeep,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      highlight: highlight ?? this.highlight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      glassFill: glassFill ?? this.glassFill,
      glassFillSoft: glassFillSoft ?? this.glassFillSoft,
      glassStroke: glassStroke ?? this.glassStroke,
      glassEdge: glassEdge ?? this.glassEdge,
      rainBead: rainBead ?? this.rainBead,
      rainOpacity: rainOpacity ?? this.rainOpacity,
      rainMicroOpacity: rainMicroOpacity ?? this.rainMicroOpacity,
      rainStreakOpacity: rainStreakOpacity ?? this.rainStreakOpacity,
      mistOpacity: mistOpacity ?? this.mistOpacity,
      cardRadius: cardRadius ?? this.cardRadius,
      innerRadius: innerRadius ?? this.innerRadius,
    );
  }

  @override
  HereIamThemeTokens lerp(
    ThemeExtension<HereIamThemeTokens>? other,
    double t,
  ) {
    if (other is! HereIamThemeTokens) return this;
    return HereIamThemeTokens(
      id: t < 0.5 ? id : other.id,
      nameZh: t < 0.5 ? nameZh : other.nameZh,
      nameEn: t < 0.5 ? nameEn : other.nameEn,
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      backgroundSoft: Color.lerp(backgroundSoft, other.backgroundSoft, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      surfaceDeep: Color.lerp(surfaceDeep, other.surfaceDeep, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassFillSoft: Color.lerp(glassFillSoft, other.glassFillSoft, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
      glassEdge: Color.lerp(glassEdge, other.glassEdge, t)!,
      rainBead: Color.lerp(rainBead, other.rainBead, t)!,
      rainOpacity: lerpDouble(rainOpacity, other.rainOpacity, t)!,
      rainMicroOpacity:
          lerpDouble(rainMicroOpacity, other.rainMicroOpacity, t)!,
      rainStreakOpacity:
          lerpDouble(rainStreakOpacity, other.rainStreakOpacity, t)!,
      mistOpacity: lerpDouble(mistOpacity, other.mistOpacity, t)!,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      innerRadius: lerpDouble(innerRadius, other.innerRadius, t)!,
    );
  }
}

extension HereIamThemeLookup on BuildContext {
  HereIamThemeTokens get hereIamTheme {
    return Theme.of(this).extension<HereIamThemeTokens>() ??
        HereIamThemeRuntime.current;
  }
}

abstract final class HereIamThemeRuntime {
  static HereIamThemeTokens current = HereIamThemeTokens.current;
}
