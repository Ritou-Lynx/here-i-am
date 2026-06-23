import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/domain/models/presentation_module.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';

/// Rose Mist Memory Card color adapter.
///
/// Memory Review currently lives on a light observation surface, so the
/// summary card uses the daytime Rose Mist material even when chat is using a
/// night skin. Otherwise dark theme tokens turn the card into a low-contrast
/// grey-purple fog block on a light page.
class RoseMistPalette {
  const RoseMistPalette._();

  static const HereIamThemeTokens _tokens = HereIamThemeTokens.roseMistDay;

  static Color get ink => _tokens.textPrimary;
  static Color get inkMid => _tokens.textSecondary;
  static Color get inkSoft => _tokens.textMuted;

  static Color get rose => _tokens.accent;
  static Color get roseSoft => _tokens.accentSoft;
  static Color get roseDeep => _tokens.surfaceDeep;

  static Color get hairline => const Color(0xFF75615F).withValues(alpha: 0.14);
  static Color get glassLine => Colors.white.withValues(alpha: 0.92);
  static Color get glassFill => const Color(0xFFFFFBFA);
  static Color get glassFillSoft => const Color(0xFFF8F3F2);
  static Color get cardTint => const Color(0xFFF2E7E7);
  static Color get shadow => const Color(0xFF75615F).withValues(alpha: 0.16);

  // Mood colors remain semantic and intentionally independent of skin.
  static const moodExcited = Color(0xFFE89A8E);
  static const moodCalm = Color(0xFFE5C7CB);
  static const moodTense = Color(0xFF9E7A8A);
  static const moodLow = Color(0xFF6F7A8A);
  static const moodNeutral = Color(0xFFDCD2CE);

  static const warn = Color(0xFFD8A05A);
  static const warnInk = Color(0xFFB57A2E);
  static const cancelInk = Color(0xFF7A6664);
}

/// 5 档情绪，从 valence/arousal 派生。
enum MemoryMood { excited, calm, tense, low, neutral }

extension MemoryMoodColor on MemoryMood {
  Color get color {
    switch (this) {
      case MemoryMood.excited:
        return RoseMistPalette.moodExcited;
      case MemoryMood.calm:
        return RoseMistPalette.moodCalm;
      case MemoryMood.tense:
        return RoseMistPalette.moodTense;
      case MemoryMood.low:
        return RoseMistPalette.moodLow;
      case MemoryMood.neutral:
        return RoseMistPalette.moodNeutral;
    }
  }
}

/// Map valence (-1..1) + arousal (0..1) to a discrete mood.
/// 任何一个为 null 都退化为 neutral。
/// [confidence] 低于 0.35 时也退化为 neutral —— 弱信号不强行定位。
/// 用户已 override 视为最高置信，跳过门槛。
MemoryMood resolveMood({
  double? valence,
  double? arousal,
  double? confidence,
  bool overridden = false,
}) {
  if (valence == null || arousal == null) return MemoryMood.neutral;
  if (!overridden && confidence != null && confidence < 0.35) {
    return MemoryMood.neutral;
  }
  final v = valence.clamp(-1.0, 1.0);
  final a = arousal.clamp(0.0, 1.0);

  if (v.abs() < 0.18 && a < 0.45) return MemoryMood.neutral;

  if (v >= 0) {
    return a >= 0.55 ? MemoryMood.excited : MemoryMood.calm;
  } else {
    return a >= 0.55 ? MemoryMood.tense : MemoryMood.low;
  }
}

class MemorySummaryCard extends StatelessWidget {
  const MemorySummaryCard({
    super.key,
    required this.entity,
    this.onTap,
  });

  final SharedLifeEntitySnapshot entity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final presentation = PresentationModule.tryParse(entity.presentationJson);
    final mood = resolveMood(
      valence: entity.effectiveValence,
      arousal: entity.effectiveArousal,
      confidence: entity.emotionConfidence,
      overridden: entity.emotionOverridden,
    );
    final isCancelled = entity.status == 'cancelled';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _CardShell(
        moodColor: mood.color,
        muted: isCancelled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCancelled || presentation?.statusLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StatusPill(
                  text: isCancelled ? '已取消' : presentation!.statusLabel!,
                  cancelled: isCancelled,
                ),
              ),
            _Blocks(
              presentation: presentation,
              fallbackTitle: entity.title,
              fallbackText: _fallbackText(entity),
            ),
            const SizedBox(height: 16),
            _Foot(tags: entity.tags, onTap: onTap),
          ],
        ),
      ),
    );
  }

  static String? _fallbackText(SharedLifeEntitySnapshot entity) {
    final summary = entity.state['summary'] as String? ?? '';
    final content = entity.state['content'] as String? ?? '';
    final text = [summary, content].where((s) => s.isNotEmpty).join('\n\n');
    return text.isEmpty ? null : text;
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.moodColor,
    required this.muted,
    required this.child,
  });

  final Color moodColor;
  final bool muted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: RoseMistPalette.glassLine, width: 1),
          gradient: LinearGradient(
            begin: const Alignment(-0.4, -0.7),
            end: Alignment.bottomRight,
            colors: [
              RoseMistPalette.glassFill,
              RoseMistPalette.glassFillSoft,
              RoseMistPalette.cardTint,
            ],
            stops: const [0.0, 0.58, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: RoseMistPalette.shadow,
              blurRadius: 46,
              offset: const Offset(0, 20),
              spreadRadius: -10,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.62),
              blurRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.cancelled});

  final String text;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final color =
        cancelled ? RoseMistPalette.cancelInk : RoseMistPalette.warnInk;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Blocks extends StatelessWidget {
  const _Blocks({
    required this.presentation,
    required this.fallbackTitle,
    required this.fallbackText,
  });

  final PresentationModule? presentation;
  final String fallbackTitle;
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Title — 优先 presentation.title，没有就用 entity.title
    final title = presentation?.title ?? fallbackTitle;
    if (title.isNotEmpty && _shouldShowTitle(presentation)) {
      children.add(_TitleBlock(title));
    }

    if (presentation?.subjectRef != null) {
      children.add(_SubjectRef(presentation!.subjectRef!));
    }

    final blocks = presentation?.blocks ?? const <MemoryBlock>[];
    if (blocks.isEmpty && fallbackText != null) {
      // 旧记录没有 presentation 时，退化为单一 TextBlock 渲染 summary/content
      children.add(_TextBlockView(TextBlock(text: fallbackText!)));
    } else {
      for (final b in blocks) {
        children.add(_buildBlock(b));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _withGap(children, 12),
    );
  }

  bool _shouldShowTitle(PresentationModule? p) {
    // 如果设计上首块是 quote，把 entity.title 当成大标题反而生硬。
    // presentation 自己显式 title 时无条件展示；否则只在没 quote 首块时展示。
    if (p?.title != null) return true;
    final first = p?.blocks.firstOrNull;
    if (first is QuoteBlock) return false;
    return true;
  }

  Widget _buildBlock(MemoryBlock block) {
    if (block is TextBlock) return _TextBlockView(block);
    if (block is QuoteBlock) return _QuoteBlockView(block);
    if (block is NumberBlock) return _NumberBlockView(block);
    if (block is TableBlock) return _TableBlockView(block);
    if (block is SparklineBlock) return _SparklineView(block);
    if (block is MediaBlock) return _MediaBlockView(block);
    if (block is LinkAttachmentBlock) return _LinkBlockView(block);
    if (block is ProgressBarBlock) return _ProgressBarBlockView(block);
    return const SizedBox.shrink();
  }
}

List<Widget> _withGap(List<Widget> items, double gap) {
  if (items.isEmpty) return items;
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) out.add(SizedBox(height: gap));
    out.add(items[i]);
  }
  return out;
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: RoseMistPalette.inkMid,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      );
}

class _SubjectRef extends StatelessWidget {
  const _SubjectRef(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Text(
          text,
          style: TextStyle(
            color: RoseMistPalette.inkSoft,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _TextBlockView extends StatelessWidget {
  const _TextBlockView(this.block);
  final TextBlock block;

  @override
  Widget build(BuildContext context) {
    if (block.emphases.isEmpty) {
      return Text(
        block.text,
        style: TextStyle(
          color: RoseMistPalette.ink.withValues(alpha: 0.96),
          fontSize: 14.5,
          height: 1.78,
          letterSpacing: 0.15,
        ),
      );
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: RoseMistPalette.ink.withValues(alpha: 0.96),
          fontSize: 14.5,
          height: 1.78,
          letterSpacing: 0.15,
        ),
        children: _splitWithEmphasis(block.text, block.emphases),
      ),
    );
  }

  static List<TextSpan> _splitWithEmphasis(String text, List<String> emphases) {
    if (emphases.isEmpty) return [TextSpan(text: text)];
    // 简单线性扫描：找到每个 emphasis 子串，按顺序切片。
    final spans = <TextSpan>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      int? bestIdx;
      String? bestMatch;
      for (final e in emphases) {
        if (e.isEmpty) continue;
        final i = remaining.indexOf(e);
        if (i >= 0 && (bestIdx == null || i < bestIdx)) {
          bestIdx = i;
          bestMatch = e;
        }
      }
      if (bestIdx == null || bestMatch == null) {
        spans.add(TextSpan(text: remaining));
        break;
      }
      if (bestIdx > 0) {
        spans.add(TextSpan(text: remaining.substring(0, bestIdx)));
      }
      spans.add(TextSpan(
        text: bestMatch,
        style: TextStyle(
          color: RoseMistPalette.ink,
          background: Paint()
            ..color = RoseMistPalette.roseSoft.withValues(alpha: 0.42),
        ),
      ));
      remaining = remaining.substring(bestIdx + bestMatch.length);
    }
    return spans;
  }
}

class _QuoteBlockView extends StatelessWidget {
  const _QuoteBlockView(this.block);
  final QuoteBlock block;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: RoseMistPalette.rose.withValues(alpha: 0.55),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${block.text}"',
            style: TextStyle(
              color: RoseMistPalette.ink,
              fontSize: 17,
              height: 1.72,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (block.context != null) ...[
            const SizedBox(height: 8),
            Text(
              block.context!,
              style: TextStyle(
                color: RoseMistPalette.inkSoft,
                fontSize: 12,
                height: 1.65,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NumberBlockView extends StatelessWidget {
  const _NumberBlockView(this.block);
  final NumberBlock block;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: block.value,
                style: TextStyle(
                  color: RoseMistPalette.ink,
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (block.unit != null)
                TextSpan(
                  text: '  ${block.unit}',
                  style: TextStyle(
                    color: RoseMistPalette.inkSoft,
                    fontSize: 13,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
        ),
        if (block.note != null) ...[
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                block.note!,
                style: TextStyle(
                  color: RoseMistPalette.ink.withValues(alpha: 0.78),
                  fontSize: 13.5,
                  height: 1.62,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TableBlockView extends StatelessWidget {
  const _TableBlockView(this.block);
  final TableBlock block;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: RoseMistPalette.hairline),
        for (final row in block.rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: RoseMistPalette.hairline),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    row.label,
                    style: TextStyle(
                      color: RoseMistPalette.inkSoft,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    row.value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: RoseMistPalette.inkMid,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SparklineView extends StatelessWidget {
  const _SparklineView(this.block);
  final SparklineBlock block;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 28,
          width: double.infinity,
          child: CustomPaint(painter: _SparklinePainter(block.points)),
        ),
        if (block.caption != null) ...[
          const SizedBox(height: 4),
          Text(
            block.caption!,
            style: TextStyle(
              color: RoseMistPalette.inkSoft,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.points);
  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minV = points.reduce(math.min);
    final maxV = points.reduce(math.max);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);

    final path = Path();
    final fill = Path();
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final x = (i / (n - 1)) * size.width;
      final y =
          size.height - 4 - ((points[i] - minV) / range) * (size.height - 8);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()..color = RoseMistPalette.rose.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = RoseMistPalette.rose
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // last point dot
    final last = points.last;
    final lastX = size.width;
    final lastY = size.height - 4 - ((last - minV) / range) * (size.height - 8);
    canvas.drawCircle(
      Offset(lastX - 2, lastY),
      2.8,
      Paint()..color = RoseMistPalette.rose,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      !_listEq(oldDelegate.points, points);

  static bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _MediaBlockView extends StatelessWidget {
  const _MediaBlockView(this.block);
  final MediaBlock block;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: _buildMediaImage(block.assetPath),
          ),
        ),
        if (block.caption != null) ...[
          const SizedBox(height: 8),
          Text(
            block.caption!,
            style: TextStyle(
              color: RoseMistPalette.inkSoft,
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMediaImage(String assetPath) {
    try {
      final absPath = FileSystemService.instance.toAbsolutePath(assetPath);
      final file = File(absPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _mediaPlaceholder(),
        );
      }
    } catch (_) {}
    return _mediaPlaceholder();
  }

  Widget _mediaPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCDB8C8), Color(0xFFD9B5AF), Color(0xFF8FA7A0)],
          stops: [0.0, 0.38, 1.0],
        ),
      ),
    );
  }
}

class _LinkBlockView extends StatelessWidget {
  const _LinkBlockView(this.block);
  final LinkAttachmentBlock block;

  static const _brandColors = {
    'xhs': Color(0xFFFE2C55),
    'wechat': Color(0xFF07C160),
    'dianping': Color(0xFFF4A91E),
  };

  static const _brandLabels = {
    'xhs': '红',
    'wechat': '微',
    'dianping': '点',
    'web': 'W',
  };

  @override
  Widget build(BuildContext context) {
    final source = block.source ?? 'web';
    final color = _brandColors[source] ?? RoseMistPalette.rose;
    final label = _brandLabels[source] ?? 'W';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      constraints: const BoxConstraints(minHeight: 42),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.38),
        border: Border.all(color: RoseMistPalette.ink.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: color,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              block.title ?? block.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: RoseMistPalette.inkMid,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: 0.22),
              border: Border.all(
                color: RoseMistPalette.rose.withValues(alpha: 0.24),
              ),
            ),
            child: Text(
              '打开',
              style: TextStyle(
                color: RoseMistPalette.rose,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Foot extends StatelessWidget {
  const _Foot({required this.tags, required this.onTap});

  final List<String> tags;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 11,
            runSpacing: 4,
            children: [
              for (final tag in tags.take(3))
                Text(
                  tag,
                  style: TextStyle(
                    color: RoseMistPalette.roseDeep.withValues(alpha: 0.78),
                    fontSize: 10.5,
                    letterSpacing: 1.05,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: RoseMistPalette.rose,
            ),
            child: const Text(
              '聊聊',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressBarBlockView extends StatelessWidget {
  const _ProgressBarBlockView(this.block);
  final ProgressBarBlock block;

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final unit = block.unit ?? '';
    final valueText = '${_fmtNum(block.value)}/${_fmtNum(block.max)}'
        '${unit.isEmpty ? '' : ' $unit'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.label != null) ...[
          Text(
            block.label!,
            style: TextStyle(
              color: RoseMistPalette.inkMid,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: RoseMistPalette.roseSoft.withValues(alpha: 0.45)),
                FractionallySizedBox(
                  widthFactor: block.fraction,
                  child: Container(color: RoseMistPalette.rose),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          valueText,
          style: TextStyle(
            color: RoseMistPalette.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
