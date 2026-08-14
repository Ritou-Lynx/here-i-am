/// Palm charts — reusable editorial mini-charts for life-space observation
/// panels and anywhere else a small data viz is needed.
///
/// Visual grammar borrows from Lieflat Charts "椰林绿 Palm": warm paper base,
/// deep-green data ink, cocoa hairline guide rails, one amber hero element per
/// chart, and real-unit value annotations. Charts are self-contained and carry
/// no Memex domain coupling — feed them any [PalmChartPoint] list.
library;

import 'package:flutter/material.dart';

/// The six chart shapes used by Life Insights, plus a [placeholder] safety
/// net for unknown/empty data.
enum PalmChartType {
  trend,
  streak,
  baseline,
  anomaly,
  pattern,
  projection,
  placeholder,
}

/// A single plotted record: a date/label, the real-unit string, and the parsed
/// numeric value used for geometry.
class PalmChartPoint {
  const PalmChartPoint({
    required this.date,
    required this.rawValue,
    this.value,
  });

  final String date;
  final String rawValue;
  final double? value;
}

/// Palm palette, parameterized so other surfaces can reuse the exact Lieflat
/// colors or provide their own without touching chart geometry.
@immutable
class PalmChartPalette {
  const PalmChartPalette({
    required this.paper,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.grid,
    required this.data,
    required this.bead,
    required this.faintData,
    required this.hero,
    required this.ramp,
  });

  /// 纸底 — chart surface.
  final Color paper;

  /// 浓咖 — values / axis labels.
  final Color ink;

  /// 咖 60% — secondary labels.
  final Color inkMuted;

  /// 咖 32% — helper labels.
  final Color inkFaint;

  /// 咖 16% — hairline guide rails / grid.
  final Color grid;

  /// 深绿 — main data.
  final Color data;

  /// 豆绿 — secondary units (beads).
  final Color bead;

  /// 橄榄 — low-value / placeholder.
  final Color faintData;

  /// 琥珀 — the single emphasis element per chart.
  final Color hero;

  /// 绿→黄序数梯 — heat / pattern intensity.
  final List<Color> ramp;

  /// Lieflat Charts "椰林绿 Palm" as shipped in color-presets.js.
  static const PalmChartPalette lieflatPalm = PalmChartPalette(
    paper: Color(0xFFF0EFEB),
    ink: Color(0xFF58402E),
    inkMuted: Color(0x9958402E),
    inkFaint: Color(0x5258402E),
    grid: Color(0x2958402E),
    data: Color(0xFF43593B),
    bead: Color(0xFF77835A),
    faintData: Color(0xFFACAD79),
    hero: Color(0xFFD4A017),
    ramp: [
      Color(0xFF43593B),
      Color(0xFF5A7049),
      Color(0xFF77835A),
      Color(0xFF929960),
      Color(0xFFACAD79),
      Color(0xFFD4A017),
    ],
  );
}

/// A single Palm mini-chart on an opaque paper inset.
///
/// Use [containerKey] when the surrounding surface needs a stable widget key
/// for tests or animations.
class PalmChart extends StatelessWidget {
  const PalmChart({
    super.key,
    required this.type,
    required this.points,
    this.height = 116,
    this.borderRadius = 13,
    this.palette = PalmChartPalette.lieflatPalm,
    this.containerKey,
  });

  final PalmChartType type;
  final List<PalmChartPoint> points;
  final double height;
  final double borderRadius;
  final PalmChartPalette palette;
  final Key? containerKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: containerKey,
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: palette.paper,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.grid, width: 0.7),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          painter: _PalmChartPainter(type, points, palette),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PalmChartPainter extends CustomPainter {
  _PalmChartPainter(this.type, this.points, this.p);

  final PalmChartType type;
  final List<PalmChartPoint> points;
  final PalmChartPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case PalmChartType.trend:
        _drawTrend(canvas, size);
        break;
      case PalmChartType.streak:
        _drawStreak(canvas, size);
        break;
      case PalmChartType.baseline:
        _drawBaseline(canvas, size);
        break;
      case PalmChartType.anomaly:
        _drawAnomaly(canvas, size);
        break;
      case PalmChartType.pattern:
        _drawPattern(canvas, size);
        break;
      case PalmChartType.projection:
        _drawProjection(canvas, size);
        break;
      case PalmChartType.placeholder:
        _drawPlaceholder(canvas, size);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PalmChartPainter old) =>
      old.type != type ||
      old.points.length != points.length ||
      !_sameValues(old.points, points);

  bool _sameValues(List<PalmChartPoint> a, List<PalmChartPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].rawValue != b[i].rawValue) {
        return false;
      }
    }
    return true;
  }

  // ── helpers ──
  List<PalmChartPoint> get _numericPoints =>
      points.where((p) => p.value != null).toList(growable: false);

  List<double> _numericValues() =>
      _numericPoints.map((p) => p.value!).toList(growable: false);

  (double, double, double) _range(List<double> vals) {
    if (vals.isEmpty) return (0, 1, 1);
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);
    return (minV, maxV, range);
  }

  int? _peakIndex(List<double> vals) {
    if (vals.isEmpty) return null;
    var idx = 0;
    for (var i = 1; i < vals.length; i++) {
      if (vals[i] > vals[idx]) idx = i;
    }
    return idx;
  }

  /// Put a value annotation near (x, y), flipping below when the top would
  /// clip, so labels stay inside the chart surface.
  double _labelY(double y, double height) => (y - 8) >= 7 ? y - 8 : y + 12;

  // ── trend: hairline line chart with real-unit annotations ──
  void _drawTrend(Canvas canvas, Size size) {
    final pts = _numericPoints;
    if (pts.length < 2) return _drawPlaceholder(canvas, size);
    final vals = pts.map((pt) => pt.value!).toList();
    final (minV, maxV, range) = _range(vals);

    const padX = 14.0;
    final baselineY = size.height - 20;
    const x0 = padX;
    final x1 = size.width - padX;
    const plotTop = 8.0;
    final plotH = baselineY - plotTop;
    final n = pts.length;
    final w = x1 - x0;

    double xAt(int i) => x0 + (i / (n - 1)) * w;
    double yAt(double v) => plotTop + plotH - ((v - minV) / range) * plotH;

    // Guide rails: baseline + vertical tick per record
    canvas.drawLine(Offset(x0, baselineY), Offset(x1, baselineY),
        Paint()..color = p.grid..strokeWidth = 0.9);
    final tickPaint = Paint()..color = p.grid;
    for (var i = 0; i < n; i++) {
      final x = xAt(i);
      canvas.drawLine(
          Offset(x, baselineY), Offset(x, baselineY - 4.5),
          tickPaint..strokeWidth = 0.7);
    }

    // Area fill — a whisper of the line, not paint
    final fill = Path()
      ..moveTo(xAt(0), baselineY)
      ..lineTo(xAt(0), yAt(pts[0].value!));
    for (var i = 1; i < n; i++) {
      fill.lineTo(xAt(i), yAt(pts[i].value!));
    }
    fill.lineTo(xAt(n - 1), baselineY);
    fill.close();
    canvas.drawPath(fill, Paint()..color = p.data.withValues(alpha: 0.10));

    // Data line
    final line = Path();
    for (var i = 0; i < n; i++) {
      final x = xAt(i);
      final y = yAt(pts[i].value!);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = p.data
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots + value annotations: hero on first / last / peak only
    final heroIndexes = <int>{0, n - 1};
    final peak = _peakIndex(vals);
    if (peak != null) heroIndexes.add(peak);
    for (var i = 0; i < n; i++) {
      final isHero = heroIndexes.contains(i);
      final x = xAt(i);
      final y = yAt(pts[i].value!);
      canvas.drawCircle(
        Offset(x, y),
        isHero ? 4.2 : 2.8,
        Paint()..color = isHero ? p.hero : p.data,
      );
      if (isHero) {
        _drawMiniText(
          canvas,
          pts[i].rawValue,
          Offset(x, _labelY(y, size.height)),
          color: p.ink,
          fontWeight: FontWeight.w800,
        );
      }
    }

    // Account-book date row
    final firstDate = pts.first.date;
    final lastDate = pts.last.date;
    if (firstDate == lastDate) {
      if (firstDate.isNotEmpty) {
        _drawMiniText(canvas, firstDate, Offset(x0, baselineY + 5),
            color: p.inkMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4);
      }
    } else {
      if (firstDate.isNotEmpty) {
        _drawMiniText(canvas, firstDate, Offset(x0, baselineY + 5),
            color: p.inkMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4);
      }
      if (lastDate.isNotEmpty) {
        _drawMiniText(canvas, lastDate, Offset(x1 - 20, baselineY + 5),
            align: TextAlign.right,
            color: p.inkMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4);
      }
    }
  }

  // ── streak: big count + unit bead row (one bead = one record) ──
  void _drawStreak(Canvas canvas, Size size) {
    final vals = _numericValues();
    final count = vals.length;
    if (count == 0) return _drawPlaceholder(canvas, size);

    final dotCount = count.clamp(0, 30);
    final big = count.toString();

    final tp = TextPainter(
      text: TextSpan(
        text: big,
        style: TextStyle(
          color: p.hero,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, 16));

    _drawMiniText(
      canvas,
      '连续 $count 条记录',
      Offset((size.width - 48) / 2, 50),
      color: p.inkMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      maxWidth: 80,
    );

    if (dotCount == 0) return;
    const dotSize = 4.6;
    const spacing = 3.4;
    final totalW = dotCount * dotSize + (dotCount - 1) * spacing;
    final startX = (size.width - totalW) / 2 + dotSize / 2;
    final y = size.height - 14;
    for (var i = 0; i < dotCount; i++) {
      final isLast = i == dotCount - 1;
      canvas.drawCircle(
        Offset(startX + i * (dotSize + spacing), y),
        dotSize / 2,
        Paint()..color = isLast ? p.hero : p.bead,
      );
    }
  }

  // ── baseline: min–max range capsule + latest marker ──
  void _drawBaseline(Canvas canvas, Size size) {
    final pts = _numericPoints;
    if (pts.isEmpty) return _drawPlaceholder(canvas, size);
    final vals = pts.map((pt) => pt.value!).toList();
    final (minV, maxV, range) = _range(vals);

    const padX = 14.0;
    const x0 = padX;
    final x1 = size.width - padX;
    final barY = size.height / 2 - 3;
    const barH = 6.0;

    // Track
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x0, barY, x1 - x0, barH),
        const Radius.circular(3),
      ),
      Paint()..color = p.grid,
    );

    // Range capsule
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x0, barY, x1 - x0, barH),
        const Radius.circular(3),
      ),
      Paint()..color = p.data.withValues(alpha: 0.30),
    );

    // End caps + labels
    canvas.drawCircle(
        Offset(x0, barY + barH / 2), 4, Paint()..color = p.data);
    canvas.drawCircle(
        Offset(x1, barY + barH / 2), 4, Paint()..color = p.data);
    _drawMiniText(canvas, _formatValue(minV), Offset(x0 - 2, barY + barH + 5),
        color: p.ink, fontWeight: FontWeight.w800);
    _drawMiniText(canvas, _formatValue(maxV),
        Offset(x1 - 24, barY + barH + 5),
        align: TextAlign.right, color: p.ink, fontWeight: FontWeight.w800);

    // Latest value marker — the one hero element
    final last = pts.last;
    final lx = x0 + ((last.value! - minV) / range) * (x1 - x0);
    final ly = barY + barH / 2;
    canvas.drawCircle(Offset(lx, ly), 4.6, Paint()..color = p.hero);
    _drawMiniText(
      canvas,
      '最新 ${last.rawValue}',
      Offset(lx - 24, _labelY(barY, size.height)),
      color: p.ink,
      fontWeight: FontWeight.w800,
      maxWidth: 60,
    );
  }

  // ── anomaly: chunky bars, outlier gets the amber ──
  void _drawAnomaly(Canvas canvas, Size size) {
    final pts = _numericPoints;
    if (pts.length < 2) return _drawPlaceholder(canvas, size);
    final vals = pts.map((pt) => pt.value!).toList();
    final (minV, maxV, range) = _range(vals);
    final avg = vals.reduce((a, b) => a + b) / vals.length;

    const padX = 10.0;
    final baselineY = size.height - 14;
    const plotTop = 10.0;
    final plotH = baselineY - plotTop;
    final n = vals.length;
    final w = size.width - padX * 2;
    final barW = (w / n) * 0.5;
    final gap = (w - barW * n) / (n - 1).clamp(1, n);

    // Hairline baseline
    canvas.drawLine(
        Offset(padX, baselineY), Offset(padX + w, baselineY),
        Paint()..color = p.grid..strokeWidth = 0.9);

    // Mean rail
    final meanY = plotTop + plotH - ((avg - minV) / range) * plotH;
    final meanPaint = Paint()
      ..color = p.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    var mx = padX;
    while (mx < padX + w) {
      canvas.drawLine(
          Offset(mx, meanY),
          Offset((mx + 3).clamp(0, padX + w).toDouble(), meanY), meanPaint);
      mx += 6;
    }

    for (var i = 0; i < n; i++) {
      final isOutlier = (vals[i] - avg).abs() > range * 0.55;
      final bh = ((vals[i] - minV) / range) * plotH;
      final x = padX + i * (barW + gap);
      final y = baselineY - bh.clamp(2.0, plotH);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, baselineY - y),
        const Radius.circular(2),
      );
      canvas.drawRRect(
          r, Paint()..color = isOutlier ? p.hero : p.data);
      if (isOutlier) {
        _drawMiniText(
          canvas,
          pts[i].rawValue,
          Offset(x + barW / 2 - 12, _labelY(y, size.height)),
          color: p.ink,
          fontWeight: FontWeight.w800,
          maxWidth: 56,
        );
      }
    }
  }

  // ── pattern: 7-day heat cells on the green→amber ramp ──
  void _drawPattern(Canvas canvas, Size size) {
    final pts = _numericPoints;
    if (pts.isEmpty) return _drawPlaceholder(canvas, size);
    final vals = pts.map((pt) => pt.value!).toList();
    final (minV, maxV, range) = _range(vals);

    final days = vals.length.clamp(0, 7);
    if (days == 0) return;
    const padX = 10.0;
    final w = size.width - padX * 2;
    final cellW = w / 7;
    const cellH = 26.0;
    final cellTop = size.height / 2 - cellH / 2;

    for (var i = 0; i < days; i++) {
      final intensity = range < 0.001 ? 0.5 : (vals[i] - minV) / range;
      final rampIdx = (intensity * (p.ramp.length - 1)).round().clamp(
          0, p.ramp.length - 1);
      final cx = padX + i * cellW + cellW / 2;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - cellW * 0.32, cellTop, cellW * 0.64, cellH),
        const Radius.circular(3),
      );
      canvas.drawRRect(r, Paint()..color = p.ramp[rampIdx]);

      final label = pts[i].date.isNotEmpty ? pts[i].date : '${i + 1}';
      _drawMiniText(
        canvas,
        label,
        Offset(cx - 12, cellTop + cellH + 4),
        color: p.inkFaint,
        fontWeight: FontWeight.w600,
        maxWidth: 30,
      );
    }
  }

  // ── projection: solid data + dashed amber forecast ──
  void _drawProjection(Canvas canvas, Size size) {
    final pts = _numericPoints;
    if (pts.length < 2) return _drawPlaceholder(canvas, size);
    final vals = pts.map((pt) => pt.value!).toList();
    final (minV, maxV, range) = _range(vals);

    const padX = 10.0;
    final baselineY = size.height - 12;
    const plotTop = 8.0;
    final plotH = baselineY - plotTop;
    final n = vals.length;
    final w = size.width - padX * 2;

    final solidN = (n * 0.6).round().clamp(1, n - 1);
    final projN = n - solidN;

    double xAt(int i) => padX + (i / (n - 1)) * w;
    double yAt(double v) => plotTop + plotH - ((v - minV) / range) * plotH;

    // Baseline rail
    canvas.drawLine(
        Offset(padX, baselineY), Offset(padX + w, baselineY),
        Paint()..color = p.grid..strokeWidth = 0.9);

    // Solid part
    final solid = Path();
    for (var i = 0; i <= solidN; i++) {
      final x = xAt(i);
      final y = yAt(vals[i]);
      if (i == 0) {
        solid.moveTo(x, y);
      } else {
        solid.lineTo(x, y);
      }
    }
    canvas.drawPath(
      solid,
      Paint()
        ..color = p.data
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dashed projection
    if (projN > 0) {
      final dashPaint = Paint()
        ..color = p.hero
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      final startX = xAt(solidN);
      final startY = yAt(vals[solidN]);
      final endX = xAt(n - 1);
      final endY = yAt(vals[n - 1]);
      const dashLen = 3.5;
      const gapLen = 3.0;
      final totalLen = (Offset(endX, endY) - Offset(startX, startY)).distance;
      if (totalLen > 0) {
        final dx = (endX - startX) / totalLen;
        final dy = (endY - startY) / totalLen;
        var dist = 0.0;
        while (dist < totalLen) {
          final s = dist;
          final e = (dist + dashLen).clamp(0.0, totalLen);
          canvas.drawLine(
            Offset(startX + dx * s, startY + dy * s),
            Offset(startX + dx * e, startY + dy * e),
            dashPaint,
          );
          dist += dashLen + gapLen;
        }
      }
      // Forecast end — hero dot + real-unit annotation
      canvas.drawCircle(Offset(endX, endY), 3.8, Paint()..color = p.hero);
      _drawMiniText(
        canvas,
        pts.last.rawValue,
        Offset(endX - 14, _labelY(endY, size.height)),
        color: p.hero,
        fontWeight: FontWeight.w800,
        maxWidth: 56,
      );
    } else {
      canvas.drawCircle(
          Offset(xAt(n - 1), yAt(vals.last)), 3.8, Paint()..color = p.hero);
    }
  }

  // ── placeholder: small dot grid ──
  void _drawPlaceholder(Canvas canvas, Size size) {
    const pad = 12.0;
    const cols = 4;
    const rows = 2;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final dx = w / (cols - 1);
    final dy = h / (rows - 1);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(pad + c * dx, pad + r * dy),
          1.8,
          Paint()..color = p.faintData.withValues(alpha: 0.5),
        );
      }
    }
  }

  void _drawMiniText(
    Canvas canvas,
    String text,
    Offset offset, {
    TextAlign align = TextAlign.left,
    Color color = const Color(0x9958402E),
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = 0,
    double maxWidth = 48,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  String _formatValue(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}
