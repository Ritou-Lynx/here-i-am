import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/presentation_module.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// Palettes. Existing call sites keep the Rose Mist card; Memory Review opts
// into Spring Rain explicitly so detail and Health do not change prematurely.
// ============================================================================

class _Palette {
  const _Palette({
    required this.ink,
    required this.inkMid,
    required this.inkSoft,
    required this.accent,
    required this.accentSoft,
    required this.hairline,
    required this.glassLine,
    required this.glassFill,
    required this.glassFillSoft,
    required this.cardTint,
    required this.shadow,
    required this.moodExcited,
    required this.moodCalm,
    required this.moodTense,
    required this.moodLow,
    required this.moodNeutral,
    required this.completed,
    required this.cancelInk,
    required this.followUpDot,
  });

  final Color ink;
  final Color inkMid;
  final Color inkSoft;
  final Color accent;
  final Color accentSoft;
  final Color hairline;
  final Color glassLine;
  final Color glassFill;
  final Color glassFillSoft;
  final Color cardTint;
  final Color shadow;
  final Color moodExcited;
  final Color moodCalm;
  final Color moodTense;
  final Color moodLow;
  final Color moodNeutral;
  final Color completed;
  final Color cancelInk;
  final Color followUpDot;

  static const roseMist = _Palette(
    ink: Color(0xFF5F4B4A),
    inkMid: Color(0xFF6F5A59),
    inkSoft: Color(0xFFA8908E),
    accent: Color(0xFFC08E96),
    accentSoft: Color(0xFFE5C7CB),
    hairline: Color(0x2475615F),
    glassLine: Color(0xEBFFFFFF),
    glassFill: Color(0xFFFFFBFA),
    glassFillSoft: Color(0xFFF8F3F2),
    cardTint: Color(0xFFF2E7E7),
    shadow: Color(0x2975615F),
    moodExcited: Color(0xFFE89A8E),
    moodCalm: Color(0xFFE5C7CB),
    moodTense: Color(0xFF9E7A8A),
    moodLow: Color(0xFF6F7A8A),
    moodNeutral: Color(0xFFDCD2CE),
    completed: Color(0xFF6FA87A),
    cancelInk: Color(0xFF7A6664),
    followUpDot: Color(0xFFD8A05A),
  );

  static const springRain = _Palette(
    ink: Color(0xFF252C22),
    inkMid: Color(0xFF465040),
    inkSoft: Color(0xFF70786A),
    accent: Color(0xFF737B46),
    accentSoft: Color(0xFFAAB083),
    hairline: Color(0x24434A3D),
    glassLine: Color(0xCCFFFFFF),
    glassFill: Color(0xE8F8F6F0),
    glassFillSoft: Color(0xE5F0EFE7),
    cardTint: Color(0xE0E4E8DC),
    shadow: Color(0x2E161C15),
    moodExcited: Color(0xFFD7B968),
    moodCalm: Color(0xFFAAB083),
    moodTense: Color(0xFF8B7962),
    moodLow: Color(0xFF657168),
    moodNeutral: Color(0xFFBEC2B4),
    completed: Color(0xFF687B57),
    cancelInk: Color(0xFF746B62),
    followUpDot: Color(0xFFC99E4A),
  );

  static _Palette forVariant(MemorySummaryCardVariant variant) =>
      variant == MemorySummaryCardVariant.springRainReview
          ? springRain
          : roseMist;
}

// ============================================================================
// Mood
// ============================================================================

enum MemoryMood { excited, calm, tense, low, neutral }

extension MemoryMoodColor on MemoryMood {
  Color get color {
    switch (this) {
      case MemoryMood.excited:
        return _Palette.roseMist.moodExcited;
      case MemoryMood.calm:
        return _Palette.roseMist.moodCalm;
      case MemoryMood.tense:
        return _Palette.roseMist.moodTense;
      case MemoryMood.low:
        return _Palette.roseMist.moodLow;
      case MemoryMood.neutral:
        return _Palette.roseMist.moodNeutral;
    }
  }
}

/// Map valence (-1..1) + arousal (0..1) to a discrete mood.
/// Either null → neutral.
MemoryMood resolveMood({double? valence, double? arousal}) {
  if (valence == null || arousal == null) return MemoryMood.neutral;
  final v = valence.clamp(-1.0, 1.0);
  final a = arousal.clamp(0.0, 1.0);

  if (v.abs() < 0.18 && a < 0.45) return MemoryMood.neutral;

  if (v >= 0) {
    return a >= 0.55 ? MemoryMood.excited : MemoryMood.calm;
  } else {
    return a >= 0.55 ? MemoryMood.tense : MemoryMood.low;
  }
}

// ============================================================================
// Public widget
// ============================================================================

enum MemorySummaryCardVariant { roseMist, springRainReview }

class MemorySummaryCardV3 extends StatelessWidget {
  const MemorySummaryCardV3({
    super.key,
    required this.card,
    this.onTap,
    this.variant = MemorySummaryCardVariant.roseMist,
    this.metaLabel,
    this.categoryLabel,
    this.pressFeedback = false,
  });

  final MemoryCardViewData card;
  final VoidCallback? onTap;
  final MemorySummaryCardVariant variant;
  final String? metaLabel;
  final String? categoryLabel;
  final bool pressFeedback;

  @override
  Widget build(BuildContext context) {
    final presentation = PresentationModule.tryParse(card.presentationModule);
    final palette = _Palette.forVariant(variant);
    final showStatus =
        card.isTaskLike && card.hasStatus && card.status != 'active';

    return _PressableCard(
      onTap: onTap,
      enabled: pressFeedback,
      child: _CardShell(
        palette: palette,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (metaLabel != null || categoryLabel != null) ...[
                  _CardMetaRow(
                    palette: palette,
                    metaLabel: metaLabel,
                    categoryLabel: categoryLabel,
                  ),
                  const SizedBox(height: 14),
                ],
                if (showStatus || presentation?.statusLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (presentation?.statusLabel != null)
                          _PresentationStatusPill(
                            palette: palette,
                            text: presentation!.statusLabel!,
                          ),
                        if (showStatus)
                          _StatusPill(
                            palette: palette,
                            text: card.statusLabel!,
                            kind: card.status == 'completed'
                                ? _StatusPillKind.completed
                                : _StatusPillKind.cancelled,
                          ),
                      ],
                    ),
                  ),
                V3CardBlocks(
                  presentation: presentation,
                  dropletLabel: card.dropletLabel,
                  fallbackText: card.retrievalText,
                  variant: variant,
                ),
                const SizedBox(height: 18),
              ],
            ),
            if (card.hasFollowUp)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.followUpDot,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PressableCard extends StatefulWidget {
  const _PressableCard({
    required this.child,
    required this.onTap,
    required this.enabled,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

class _CardMetaRow extends StatelessWidget {
  const _CardMetaRow({
    required this.palette,
    required this.metaLabel,
    required this.categoryLabel,
  });

  final _Palette palette;
  final String? metaLabel;
  final String? categoryLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (metaLabel != null)
          Expanded(
            child: Text(
              metaLabel!,
              style: TextStyle(
                color: palette.inkSoft,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          )
        else
          const Spacer(),
        if (categoryLabel != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              categoryLabel!,
              style: TextStyle(
                color: palette.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// Shell
// ============================================================================

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.palette,
    required this.child,
  });

  final _Palette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.glassLine, width: 1),
          gradient: LinearGradient(
            begin: const Alignment(-0.4, -0.7),
            end: Alignment.bottomRight,
            colors: [
              palette.glassFill,
              palette.glassFillSoft,
              palette.cardTint,
            ],
            stops: const [0.0, 0.58, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
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

// ============================================================================
// Status pill
// ============================================================================

enum _StatusPillKind { completed, cancelled }

class _PresentationStatusPill extends StatelessWidget {
  const _PresentationStatusPill({
    required this.palette,
    required this.text,
  });

  final _Palette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.accent,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.palette,
    required this.text,
    required this.kind,
  });

  final _Palette palette;
  final String text;
  final _StatusPillKind kind;

  @override
  Widget build(BuildContext context) {
    final color = kind == _StatusPillKind.completed
        ? palette.completed
        : palette.cancelInk;
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

// ============================================================================
// Block container
// ============================================================================

/// Reusable block renderer. Shared between summary card and detail view.
class V3CardBlocks extends StatelessWidget {
  const V3CardBlocks({
    super.key,
    required this.presentation,
    this.dropletLabel = '',
    required this.fallbackText,
    this.variant = MemorySummaryCardVariant.roseMist,
  });

  final PresentationModule? presentation;
  final String dropletLabel;
  final String? fallbackText;
  final MemorySummaryCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.forVariant(variant);
    final children = <Widget>[];

    final visibleTitle = presentation?.title ?? dropletLabel;
    if (visibleTitle.isNotEmpty) {
      children.add(_TitleBlock(visibleTitle, palette));
    }

    if (presentation?.subjectRef != null) {
      children.add(_SubjectRef(presentation!.subjectRef!, palette));
    }

    final blocks = presentation?.blocks ?? const <MemoryBlock>[];
    if (blocks.isEmpty && fallbackText != null) {
      children.add(_TextBlockView(TextBlock(text: fallbackText!), palette));
    } else {
      for (final b in blocks) {
        children.add(_buildBlock(b, palette));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _withGap(children, 12),
    );
  }

  Widget _buildBlock(MemoryBlock block, _Palette palette) {
    if (block is TextBlock) return _TextBlockView(block, palette);
    if (block is QuoteBlock) return _QuoteBlockView(block, palette);
    if (block is NumberBlock) return _NumberBlockView(block, palette);
    if (block is TableBlock) return _TableBlockView(block, palette);
    if (block is SparklineBlock) return _SparklineView(block, palette);
    if (block is MediaBlock) return _MediaBlockView(block, palette);
    if (block is LinkAttachmentBlock) return _LinkBlockView(block, palette);
    if (block is ProgressBarBlock) {
      return _ProgressBarBlockView(block, palette);
    }
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

// ============================================================================
// Block renderers
// ============================================================================

class _TitleBlock extends StatelessWidget {
  const _TitleBlock(this.text, this.palette);
  final String text;
  final _Palette palette;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: palette.inkMid,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      );
}

class _SubjectRef extends StatelessWidget {
  const _SubjectRef(this.text, this.palette);
  final String text;
  final _Palette palette;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Text(
          text,
          style: TextStyle(
            color: palette.inkSoft,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _TextBlockView extends StatelessWidget {
  const _TextBlockView(this.block, this.palette);
  final TextBlock block;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    if (block.emphases.isEmpty) {
      return Text(
        block.text,
        style: TextStyle(
          color: palette.ink.withValues(alpha: 0.96),
          fontSize: 14.5,
          height: 1.78,
          letterSpacing: 0.15,
        ),
      );
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: palette.ink.withValues(alpha: 0.96),
          fontSize: 14.5,
          height: 1.78,
          letterSpacing: 0.15,
        ),
        children: _splitWithEmphasis(block.text, block.emphases, palette),
      ),
    );
  }

  static List<TextSpan> _splitWithEmphasis(
    String text,
    List<String> emphases,
    _Palette palette,
  ) {
    if (emphases.isEmpty) return [TextSpan(text: text)];
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
          color: palette.ink,
          background: Paint()
            ..color = palette.accentSoft.withValues(alpha: 0.42),
        ),
      ));
      remaining = remaining.substring(bestIdx + bestMatch.length);
    }
    return spans;
  }
}

class _QuoteBlockView extends StatelessWidget {
  const _QuoteBlockView(this.block, this.palette);
  final QuoteBlock block;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: palette.accent.withValues(alpha: 0.55),
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
              color: palette.ink,
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
                color: palette.inkSoft,
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
  const _NumberBlockView(this.block, this.palette);
  final NumberBlock block;
  final _Palette palette;

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
                  color: palette.ink,
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (block.unit != null)
                TextSpan(
                  text: '  ${block.unit}',
                  style: TextStyle(
                    color: palette.inkSoft,
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
                  color: palette.ink.withValues(alpha: 0.78),
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
  const _TableBlockView(this.block, this.palette);
  final TableBlock block;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: palette.hairline),
        for (final row in block.rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: palette.hairline),
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
                      color: palette.inkSoft,
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
                      color: palette.inkMid,
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
  const _SparklineView(this.block, this.palette);
  final SparklineBlock block;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 28,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(block.points, palette),
          ),
        ),
        if (block.caption != null) ...[
          const SizedBox(height: 4),
          Text(
            block.caption!,
            style: TextStyle(
              color: palette.inkSoft,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.points, this.palette);
  final List<double> points;
  final _Palette palette;

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
      Paint()..color = palette.accent.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final last = points.last;
    final lastX = size.width;
    final lastY = size.height - 4 - ((last - minV) / range) * (size.height - 8);
    canvas.drawCircle(
      Offset(lastX - 2, lastY),
      2.8,
      Paint()..color = palette.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.palette != palette || !_listEq(oldDelegate.points, points);

  static bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _MediaBlockView extends StatelessWidget {
  const _MediaBlockView(this.block, this.palette);
  final MediaBlock block;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: block.kind == 'image'
                ? _buildMediaImage(block.assetPath)
                : _mediaPlaceholder(kind: block.kind),
          ),
        ),
        if (block.caption != null) ...[
          const SizedBox(height: 7),
          Text(
            block.caption!,
            style: TextStyle(
              color: palette.inkSoft,
              fontSize: 11.5,
              height: 1.45,
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
        return Image.memory(
          file.readAsBytesSync(),
          fit: BoxFit.cover,
          errorBuilder: (_, e, st) {
            debugPrint('[V3Card] Image.memory error: $e');
            return _mediaPlaceholder(kind: 'image');
          },
        );
      }
    } catch (e, st) {
      debugPrint('[V3Card] media exception: $e\n$st');
    }
    return _mediaPlaceholder(kind: 'image');
  }

  Widget _mediaPlaceholder({required String kind}) {
    final (icon, label) = switch (kind) {
      'audio' => (Icons.graphic_eq_rounded, '音频'),
      'video' => (Icons.play_arrow_rounded, '视频'),
      _ => (Icons.image_outlined, '图片'),
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.glassFillSoft,
            palette.cardTint,
            palette.accentSoft.withValues(alpha: 0.72),
          ],
          stops: const [0.0, 0.38, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.inkMid, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: palette.inkMid,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkBlockView extends StatelessWidget {
  const _LinkBlockView(this.block, this.palette);
  final LinkAttachmentBlock block;
  final _Palette palette;

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
    final color = _brandColors[source] ?? palette.accent;
    final label = _brandLabels[source] ?? 'W';
    return InkWell(
      onTap: () => _openUrl(block.url),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        constraints: const BoxConstraints(minHeight: 42),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.38),
          border: Border.all(color: palette.ink.withValues(alpha: 0.10)),
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
                  color: palette.inkMid,
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
                  color: palette.accent.withValues(alpha: 0.24),
                ),
              ),
              child: Text(
                '打开',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ProgressBarBlockView extends StatelessWidget {
  const _ProgressBarBlockView(this.block, this.palette);
  final ProgressBarBlock block;
  final _Palette palette;

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final unit = block.unit ?? '';
    final isRatio = unit.isEmpty && block.max == 1;
    final valueText = isRatio
        ? '${(block.fraction * 100).round()}%'
        : '${_fmtNum(block.value)}/${_fmtNum(block.max)}'
            '${unit.isEmpty ? '' : ' $unit'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.label != null) ...[
          Text(
            block.label!,
            style: TextStyle(
              color: palette.inkMid,
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
                Container(
                  color: palette.accentSoft.withValues(alpha: 0.45),
                ),
                FractionallySizedBox(
                  widthFactor: block.fraction,
                  child: Container(color: palette.accent),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          valueText,
          style: TextStyle(
            color: palette.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
