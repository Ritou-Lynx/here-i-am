import 'package:flutter/material.dart';

/// Chat-only visual tokens for the 春雨昼眠 (Spring Rain Daydream) skin.
///
/// Intentionally separate from [HereIamThemeTokens]: that [ThemeExtension]
/// describes the global world surface and still drives the legacy rose-mist
/// layers + the settings theme preview. This class describes only the Chat
/// conversation look (typography / spacing / anchors / glass / background tint)
/// that the 春雨昼眠 direction defines. [PersonaChatScreen] reads this const
/// directly, so the new look is scoped to Chat and never leaks into other
/// pages — and the global extension is left untouched (no new skin instance,
/// no skins-list change).
///
/// Source of truth: docs/design/春雨昼眠主题UI设计原型.md §22 and the lab
/// defaults in docs/design/lab/tokens.js. These are design-time constants and
/// are NOT runtime-interpolated (no lerp / copyWith needed).
@immutable
class SpringRainChatTokens {
  const SpringRainChatTokens({
    required this.background,
    required this.backgroundSoft,
    required this.glassFillSoft,
    required this.brightness,
    required this.pageMargin,
    required this.iIndent,
    required this.lineHeight,
    required this.blockGap,
    required this.turnGap,
    required this.timeGap,
    required this.timeAlpha,
    required this.fontFamily,
    required this.userColor,
    required this.userWeight,
    required this.userSize,
    required this.userLetterSpacing,
    required this.iColor,
    required this.iWeight,
    required this.iSize,
    required this.actionColor,
    required this.actionSize,
    required this.iAnchorBar,
    required this.iAnchorAlpha,
    required this.userAnchorBar,
    required this.glassBlur,
    required this.glassFill,
    required this.glassStroke,
    required this.fadeStrength,
    required this.fadeRatio,
    required this.textShadow,
  });

  /// Self-contained background tint so Chat need not read global tokens.
  final Color background;

  /// World-surface fields still referenced by the Chat background stack and the
  /// markdown code-block style; mirrored here so Chat stays self-contained.
  final Color backgroundSoft;
  final Color glassFillSoft;
  final Brightness brightness;

  // layout
  final double pageMargin;
  final double iIndent;
  final double lineHeight;

  // rhythm (treats the message wall as grouped breathing, see spec §4 / §8)
  final double blockGap;
  final double turnGap;
  final double timeGap;

  // time marker
  final double timeAlpha;

  /// Chinese body family. Only applied once the LXGW WenKai ttf is bundled in
  /// assets/fonts + registered in pubspec; otherwise Flutter falls back safely.
  final String fontFamily;

  // user message
  final Color userColor;
  final FontWeight userWeight;
  final double userSize;
  final double userLetterSpacing;

  // i message
  final Color iColor;
  final FontWeight iWeight;
  final double iSize;

  // action / stage direction
  final Color actionColor;
  final double actionSize;

  // conversation anchors (default: i = solid bar per turn, user = none)
  final bool iAnchorBar;
  final double iAnchorAlpha;
  final bool userAnchorBar;

  // glass input bar
  final double glassBlur;
  final Color glassFill;
  final Color glassStroke;

  // scroll fade + text legibility shadow
  final double fadeStrength;
  final double fadeRatio;
  final double textShadow;

  static const SpringRainChatTokens springRainDaydream = SpringRainChatTokens(
    background: Color(0xFF0C0F0D),
    backgroundSoft: Color(0xFF080A09),
    glassFillSoft: Color(0x08FFFFFF),
    brightness: Brightness.dark,
    pageMargin: 22,
    iIndent: 21,
    lineHeight: 1.52,
    blockGap: 6,
    turnGap: 20,
    timeGap: 27,
    timeAlpha: 0.80,
    fontFamily: 'LXGW WenKai',
    userColor: Color(0xFFA3A866),
    userWeight: FontWeight.w600,
    userSize: 16,
    userLetterSpacing: 0.3,
    iColor: Color(0xF5F5EEE0),
    iWeight: FontWeight.w700,
    iSize: 17,
    actionColor: Color(0xFFF2CA70),
    actionSize: 14.5,
    iAnchorBar: true,
    iAnchorAlpha: 0.35,
    userAnchorBar: false,
    glassBlur: 2,
    glassFill: Color(0x0FFFFFFF),
    glassStroke: Color(0x2EFFFFFF),
    fadeStrength: 0.45,
    fadeRatio: 0.45,
    textShadow: 0.5,
  );
}
