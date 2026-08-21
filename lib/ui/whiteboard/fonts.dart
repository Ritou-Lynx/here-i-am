/// 白板富文本集中式字体 token。
///
/// 这是白板富文本唯一的字体入口：Widget 层不得再散落字体字符串。
/// 字体分工（与 `docs/design/whiteboard-visual-rules.md` §5.1 一致）：
/// - 中文 → 汇文明朝体；回退系统宋体 / 明朝体。
/// - 英文、数字、时间码、代码 → Cascadia Code；回退系统等宽字体。
///
/// Cascadia Code 2407.24 正式资产已按本 token 的族名注册；汇文明朝体资产
/// 已接入但仍待生产子集化。缺字时继续走下方显式回退链。禁止用霞鹜文楷
///（LXGW WenKai）等其它字体冒充目标字体。
library;

import 'package:flutter/material.dart';

/// 中文目标字体族名（汇文明朝体）。生产资产接入后对应 pubspec 注册名。
const String richTextCjkFamily = 'Huiwen-mincho';

/// 中文回退链：系统宋体 / 明朝体。目标字体缺字形时逐项尝试。
const List<String> richTextCjkFallback = [
  'Noto Serif SC',
  'Source Han Serif SC',
  'Songti SC',
  'SimSun',
];

/// 英文、数字、时间码、代码目标字体族名（Cascadia Code）。
const String richTextCodeFamily = 'Cascadia Code';

/// 英文与代码回退链：具体系统等宽字体 → 汇文明朝体（CJK 注释）→ 系统宋体
/// → 通用 `monospace`。把汇文明朝体放通用 monospace 之前，避免通用等宽字体
/// 提前接管 CJK 字形。
const List<String> richTextCodeFallback = [
  'Cascadia Mono',
  'Consolas',
  'Courier New',
  'Menlo',
  richTextCjkFamily,
  ...richTextCjkFallback,
  'monospace',
];

/// 正文混排完整回退链：具体系统等宽（拉丁/数字）→ 汇文明朝体与系统
/// 衬线（CJK）→ 通用 `monospace`。把汇文明朝体放通用 `monospace` 之前，
/// 避免通用等宽字体提前接管 CJK 字形。`TextStyle.fontFamilyFallback` 是
/// 按字形逐项尝试的列表。
const List<String> _bodyFallbackChain = richTextCodeFallback;

/// 正文（混排）样式：拉丁字符优先 Cascadia Code，CJK 字符进汇文明朝体，
/// 随后回退系统宋体。这是普通正文、标题、引用、列表的默认字体。
TextStyle richTextBodyTextStyle({
  double fontSize = 14,
  double? height,
  Color color = const Color(0xFF293025),
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) =>
    TextStyle(
      fontFamily: richTextCodeFamily,
      fontFamilyFallback: _bodyFallbackChain,
      fontSize: fontSize,
      height: height,
      color: color,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );

/// 代码块与 inline code 样式：Cascadia Code 优先，回退系统等宽；
/// 代码内出现的 CJK 字符（如注释）回退汇文明朝体 / 系统宋体。
TextStyle richTextCodeTextStyle({
  double fontSize = 13,
  double? height,
  Color color = const Color(0xFF293025),
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) =>
    TextStyle(
      fontFamily: richTextCodeFamily,
      fontFamilyFallback: _bodyFallbackChain,
      fontSize: fontSize,
      height: height,
      color: color,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );

/// 白板 UI 文字样式（标题、按钮、状态）：中文使用汇文明朝体，拉丁/数字回退
/// Cascadia Code。这是白板相关 UI（索引、库、导入、研读）的统一入口。
TextStyle whiteboardUiTextStyle({
  double fontSize = 14,
  double? height,
  Color? color,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) =>
    TextStyle(
      fontFamily: richTextCjkFamily,
      fontFamilyFallback: richTextCjkFallback,
      fontSize: fontSize,
      height: height,
      color: color,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );
