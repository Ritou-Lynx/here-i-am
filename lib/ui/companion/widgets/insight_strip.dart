/// Insight Strip — reusable widget that displays Life Insights for a domain
/// at the top of an observation panel.
///
/// Each insight renders as a left-chart / right-text card with a type-specific
/// visualization:
/// - trend      → directional sparkline with arrow
/// - streak     → big count + dot row
/// - baseline   → min-max range bar
/// - anomaly    → contrast bars with outlier highlight
/// - pattern    → 7-day dot heatmap
/// - projection → solid line + dashed projection
///
/// The visual language follows the Spring Rain Daydream palette: dark glass
/// containers on the rain-glass background, warm-ivory text, moss accent,
/// warm-gold highlight.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/db/app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — aligned with HereIamThemeTokens springRainDaydream
// ─────────────────────────────────────────────────────────────────────────────
const _inkPrimary = Color(0xFFF5EEE0); // warm ivory
const _inkSecondary = Color(0xCCEDE6D5);
const _inkMuted = Color(0x85E6DFCE);
const _accent = Color(0xFFA3A866); // moss
const _accentSoft = Color(0xFF878C56);
const _highlight = Color(0xFFF2CA70); // warm gold
const _warn = Color(0xFFE0A05A);

const _glassFill = Color(0x14FFFFFF);
const _glassFillSoft = Color(0x0AFFFFFF);
const _glassStroke = Color(0x2EFFFFFF);

const _chartW = 112.0;
const _chartH = 56.0;

class InsightStrip extends StatefulWidget {
  const InsightStrip({
    super.key,
    required this.domain,
    this.maxItems = 3,
    this.onRefresh,
  });

  final String domain;
  final int maxItems;
  final Future<void> Function()? onRefresh;

  @override
  State<InsightStrip> createState() => _InsightStripState();
}

class _InsightStripState extends State<InsightStrip> {
  List<LifeInsight> _insights = [];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    if (!LifeInsightService.isInitialized) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final insights = await LifeInsightService.instance
          .getLatestByDomain(widget.domain, limit: widget.maxItems);
      if (mounted) {
        setState(() {
          _insights = insights;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    if (widget.onRefresh != null) {
      try {
        await widget.onRefresh!();
      } catch (_) {}
    }
    if (LifeInsightService.isInitialized) {
      try {
        final insights = await LifeInsightService.instance
            .getLatestByDomain(widget.domain, limit: widget.maxItems);
        if (mounted) {
          setState(() => _insights = insights);
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: _glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _glassStroke, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_outlined, size: 15, color: _accent),
        const SizedBox(width: 6),
        const Text(
          '洞察',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _accent,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        if (_refreshing)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _accent,
            ),
          )
        else
          GestureDetector(
            onTap: _loading ? null : _refresh,
            child: const Icon(Icons.refresh_rounded,
                size: 16, color: _inkMuted),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _insights.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerLine(widthFactor: 0.85),
          const SizedBox(height: 10),
          _shimmerLine(widthFactor: 0.55),
        ],
      );
    }
    if (_insights.isEmpty) {
      return Text(
        _emptyHintForDomain(widget.domain),
        style: const TextStyle(fontSize: 13, height: 1.55, color: _inkMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _insights.length; i++) ...[
          if (i > 0) _divider(),
          _buildInsightItem(_insights[i]),
        ],
      ],
    );
  }

  Widget _divider() => Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        height: 0.6,
        color: _glassStroke,
      );

  Widget _buildInsightItem(LifeInsight ins) {
    final points = _parsePoints(ins.dataPointsJson);
    final viz = _InsightViz(type: ins.insightType, points: points);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: type-specific visualization
        Container(
          width: _chartW,
          height: _chartH,
          margin: const EdgeInsets.only(top: 18),
          decoration: BoxDecoration(
            color: _glassFillSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CustomPaint(
              painter: _InsightPainter(viz),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right: type pill + narrative
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _typePill(ins.insightType, ins.confidence),
              const SizedBox(height: 6),
              Text(
                ins.narrative,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: _inkPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typePill(String type, double confidence) {
    final (label, color) = _typePillSpec(type);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 0.6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (confidence >= 0.7) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.circle_rounded,
            size: 5,
            color: color.withValues(alpha: 0.6),
          ),
        ],
      ],
    );
  }

  (String, Color) _typePillSpec(String type) {
    switch (type) {
      case 'trend':
        return ('趋势', _accent);
      case 'pattern':
        return ('模式', _highlight);
      case 'streak':
        return ('连续', _highlight);
      case 'baseline':
        return ('基线', _accentSoft);
      case 'anomaly':
        return ('异常', _warn);
      case 'projection':
        return ('预测', _inkSecondary);
      default:
        return ('观察', _accentSoft);
    }
  }

  Widget _shimmerLine({required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: _glassStroke,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  String _emptyHintForDomain(String domain) {
    switch (domain) {
      case 'health':
        return '林埃正在观察你的睡眠、运动和身体数据，积累够了会在这里告诉你趋势。';
      case 'finance':
        return '林埃正在留意你的收支节奏，有模式可说时会在这里提醒你。';
      case 'schedule':
        return '林埃正在看你的日程和待办，发现拖延或冲突时会在这里说一声。';
      case 'reading':
        return '林埃正在跟踪你的阅读进度，积累够了会在这里给你反馈。';
      default:
        return '林埃正在观察，有发现时会在这里告诉你。';
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Data point parsing
  // ──────────────────────────────────────────────────────────────────────

  List<_DataPoint> _parsePoints(String json) {
    if (json.isEmpty) return const [];
    try {
      final decoded = const JsonDecoder().convert(json);
      if (decoded is! List) return const [];
      final pts = <_DataPoint>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final date = raw['date']?.toString() ?? '';
        final valueStr = raw['value']?.toString().trim() ?? '';
        final numVal = _parseNumericValue(valueStr);
        pts.add(_DataPoint(date: date, rawValue: valueStr, value: numVal));
      }
      return pts;
    } catch (_) {
      return const [];
    }
  }

  double? _parseNumericValue(String s) {
    if (s.isEmpty) return null;
    // Clock time "HH:MM" → minutes since midnight
    final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (timeMatch != null) {
      final h = int.tryParse(timeMatch.group(1)!);
      final m = int.tryParse(timeMatch.group(2)!);
      if (h != null && m != null) return (h * 60 + m).toDouble();
    }
    // Number with optional unit suffix
    final numMatch = RegExp(r'-?\d+\.?\d*').firstMatch(s);
    if (numMatch != null) {
      return double.tryParse(numMatch.group(0)!);
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Viz model + painter
// ─────────────────────────────────────────────────────────────────────────────

class _DataPoint {
  final String date;
  final String rawValue;
  final double? value;
  _DataPoint({required this.date, required this.rawValue, required this.value});
}

class _InsightViz {
  final String type;
  final List<_DataPoint> points;
  _InsightViz({required this.type, required this.points});
}

class _InsightPainter extends CustomPainter {
  _InsightPainter(this.viz);
  final _InsightViz viz;

  @override
  void paint(Canvas canvas, Size size) {
    switch (viz.type) {
      case 'trend':
        _drawTrend(canvas, size);
        break;
      case 'streak':
        _drawStreak(canvas, size);
        break;
      case 'baseline':
        _drawBaseline(canvas, size);
        break;
      case 'anomaly':
        _drawAnomaly(canvas, size);
        break;
      case 'pattern':
        _drawPattern(canvas, size);
        break;
      case 'projection':
        _drawProjection(canvas, size);
        break;
      default:
        _drawDefault(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _InsightPainter old) =>
      old.viz.type != viz.type ||
      old.viz.points.length != viz.points.length;

  // ── helpers ──
  List<double> _numericValues() =>
      viz.points.map((p) => p.value).whereType<double>().toList(growable: false);

  (double, double, double) _range(List<double> vals) {
    if (vals.isEmpty) return (0, 1, 1);
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);
    return (minV, maxV, range);
  }

  // ── trend: directional sparkline + arrow ──
  void _drawTrend(Canvas canvas, Size size) {
    final vals = _numericValues();
    if (vals.length < 2) return _drawDefault(canvas, size);
    final (minV, maxV, range) = _range(vals);
    const pad = 6.0;
    final w = size.width - pad * 2 - 12; // leave room for arrow
    final h = size.height - pad * 2;

    final path = Path();
    final fill = Path();
    final n = vals.length;
    for (var i = 0; i < n; i++) {
      final x = pad + (i / (n - 1)) * w;
      final y = pad + h - ((vals[i] - minV) / range) * h;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(pad + w, size.height);
    fill.close();

    canvas.drawPath(
        fill, Paint()..color = _accent.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Last dot
    final lastX = pad + w;
    final lastY = pad + h - ((vals.last - minV) / range) * h;
    canvas.drawCircle(
        Offset(lastX, lastY), 2.6, Paint()..color = _accent);

    // Direction arrow
    final up = vals.last >= vals.first;
    final ax = size.width - 4;
    final ay = up ? pad + 2 : size.height - pad - 2;
    final arrowPaint = Paint()
      ..color = (up ? _highlight : _warn)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final arrow = Path();
    if (up) {
      arrow.moveTo(ax - 4, ay + 4);
      arrow.lineTo(ax, ay);
      arrow.lineTo(ax - 4, ay - 1);
    } else {
      arrow.moveTo(ax - 4, ay - 4);
      arrow.lineTo(ax, ay);
      arrow.lineTo(ax - 4, ay + 1);
    }
    canvas.drawPath(arrow, arrowPaint);
  }

  // ── streak: big count + dot row ──
  void _drawStreak(Canvas canvas, Size size) {
    final vals = _numericValues();
    final count = vals.length;
    if (count == 0) return _drawDefault(canvas, size);

    // Try to extract streak count from narrative? We use data point count
    // as a proxy, capped at 30 dots.
    final dotCount = count.clamp(0, 30);
    final big = count.toString();

    final tp = TextPainter(
      text: TextSpan(
        text: big,
        style: const TextStyle(
          color: _highlight,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, 4),
    );

    // Dot row below
    if (dotCount == 0) return;
    const dotSize = 3.0;
    const spacing = 2.0;
    final totalW = dotCount * dotSize + (dotCount - 1) * spacing;
    final startX = (size.width - totalW) / 2;
    final y = size.height - 8;
    for (var i = 0; i < dotCount; i++) {
      canvas.drawCircle(
        Offset(startX + i * (dotSize + spacing) + dotSize / 2, y),
        dotSize / 2,
        Paint()..color = _highlight.withValues(alpha: 0.85),
      );
    }
  }

  // ── baseline: min-max range bar ──
  void _drawBaseline(Canvas canvas, Size size) {
    final vals = _numericValues();
    if (vals.isEmpty) return _drawDefault(canvas, size);
    final (minV, maxV, _) = _range(vals);

    const padX = 14.0;
    final barY = size.height / 2 - 2;
    const barH = 6.0;

    // Track
    final trackR = RRect.fromRectAndRadius(
      Rect.fromLTWH(padX, barY, size.width - padX * 2, barH),
      const Radius.circular(3),
    );
    canvas.drawRRect(
        trackR, Paint()..color = _accentSoft.withValues(alpha: 0.25));

    // Range fill
    final rangeR = RRect.fromRectAndRadius(
      Rect.fromLTWH(padX, barY, size.width - padX * 2, barH),
      const Radius.circular(3),
    );
    canvas.drawRRect(rangeR, Paint()..color = _accent.withValues(alpha: 0.5));

    // Min/Max end caps
    for (final x in [padX, size.width - padX]) {
      canvas.drawCircle(
        Offset(x, barY + barH / 2),
        4,
        Paint()..color = _accent,
      );
    }

    // Labels
    _drawMiniText(canvas, _formatValue(minV), Offset(padX - 2, barY + barH + 4),
        align: TextAlign.left, color: _inkSecondary);
    _drawMiniText(
        canvas, _formatValue(maxV),
        Offset(size.width - padX - 20, barY + barH + 4),
        align: TextAlign.right, color: _inkSecondary);
  }

  // ── anomaly: contrast bars with outlier highlight ──
  void _drawAnomaly(Canvas canvas, Size size) {
    final vals = _numericValues();
    if (vals.length < 2) return _drawDefault(canvas, size);
    final (minV, maxV, range) = _range(vals);
    final avg = vals.reduce((a, b) => a + b) / vals.length;

    const padX = 8.0;
    const padY = 8.0;
    final w = size.width - padX * 2;
    final h = size.height - padY * 2;
    final n = vals.length;
    final barW = (w / n) * 0.62;
    final gap = (w - barW * n) / (n - 1).clamp(1, n);

    for (var i = 0; i < n; i++) {
      final bh = ((vals[i] - minV) / range) * h;
      final x = padX + i * (barW + gap);
      final y = padY + h - bh;
      final isOutlier = (vals[i] - avg).abs() > range * 0.55;
      final color = isOutlier ? _warn : _accent.withValues(alpha: 0.6);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, bh),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(r, Paint()..color = color);
    }
  }

  // ── pattern: 7-day dot heatmap ──
  void _drawPattern(Canvas canvas, Size size) {
    final vals = _numericValues();
    if (vals.isEmpty) return _drawDefault(canvas, size);
    final (minV, maxV, range) = _range(vals);

    final days = vals.length.clamp(0, 7);
    if (days == 0) return;
    const padX = 10.0;
    const padY = 10.0;
    final w = size.width - padX * 2;
    final cellW = w / 7;
    final cellH = (size.height - padY * 2) / 2;
    final dotR = (cellW < cellH ? cellW : cellH) * 0.32;

    for (var i = 0; i < days; i++) {
      final intensity = range < 0.001 ? 0.5 : (vals[i] - minV) / range;
      final cx = padX + i * cellW + cellW / 2;
      final cy = size.height / 2;
      canvas.drawCircle(
        Offset(cx, cy),
        dotR,
        Paint()..color = _highlight.withValues(alpha: 0.25 + intensity * 0.6),
      );
    }
  }

  // ── projection: solid + dashed extension ──
  void _drawProjection(Canvas canvas, Size size) {
    final vals = _numericValues();
    if (vals.length < 2) return _drawDefault(canvas, size);
    final (minV, maxV, range) = _range(vals);
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final n = vals.length;

    // Split: use last 60% as solid, project forward 40% dashed
    final solidN = (n * 0.6).round().clamp(1, n - 1);
    final projN = n - solidN;

    double xAt(int i) => pad + (i / (n - 1)) * w;
    double yAt(double v) => pad + h - ((v - minV) / range) * h;

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
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dashed projection
    if (projN > 0) {
      final dashPaint = Paint()
        ..color = _highlight.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;

      final startX = xAt(solidN);
      final startY = yAt(vals[solidN]);
      final endX = xAt(n - 1);
      final endY = yAt(vals[n - 1]);
      const dashLen = 3.0;
      const gapLen = 2.5;
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
      // End dot
      canvas.drawCircle(
          Offset(endX, endY), 2.6, Paint()..color = _highlight);
    } else {
      // All solid, just dot the end
      canvas.drawCircle(
          Offset(xAt(n - 1), yAt(vals.last)), 2.6, Paint()..color = _accent);
    }
  }

  // ── default: small dot grid placeholder ──
  void _drawDefault(Canvas canvas, Size size) {
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
          Paint()..color = _accentSoft.withValues(alpha: 0.4),
        );
      }
    }
  }

  void _drawMiniText(Canvas canvas, String text, Offset offset,
      {TextAlign align = TextAlign.left, Color color = _inkSecondary}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40);
    tp.paint(canvas, offset);
  }

  String _formatValue(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}