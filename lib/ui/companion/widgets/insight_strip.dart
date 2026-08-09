/// Insight Strip — reusable widget that displays Life Insights for a domain
/// at the top of an observation panel.
///
/// The newest insight is presented as an editorial lead: conclusion first,
/// optional evidence below. Remaining insights stay compact until selected.
/// Visual evidence adapts to the available data:
/// - 2+ numeric points → full-width chart
/// - 1 numeric point   → single-value evidence block
/// - no numeric points → narrative only (never an empty chart)
///
/// Type-specific charts:
/// - trend      → directional sparkline with arrow
/// - streak     → big count + dot row
/// - baseline   → min-max range bar
/// - anomaly    → contrast bars with outlier highlight
/// - pattern    → 7-day dot heatmap
/// - projection → solid line + dashed projection
///
/// The lead uses an opaque mist-paper surface and the chart uses an opaque
/// deep-moss surface so both remain legible over the rain-glass background.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';

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

const _glassStroke = Color(0x2EFFFFFF);

const _chartH = 116.0;

class InsightStrip extends StatefulWidget {
  const InsightStrip({
    super.key,
    required this.domain,
    this.maxItems = 3,
    this.onRefresh,
    this.initialInsights,
  });

  final String domain;
  final int maxItems;
  final Future<void> Function()? onRefresh;

  @visibleForTesting
  final List<LifeInsight>? initialInsights;

  @override
  State<InsightStrip> createState() => _InsightStripState();
}

class _InsightStripState extends State<InsightStrip> {
  List<LifeInsight> _insights = [];
  String? _featuredInsightId;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    final initialInsights = widget.initialInsights;
    if (initialInsights != null) {
      _insights = initialInsights;
      _featuredInsightId =
          initialInsights.isEmpty ? null : initialInsights.first.id;
      _loading = false;
    } else {
      _loadInsights();
    }
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
          if (insights.isEmpty ||
              !insights.any((insight) => insight.id == _featuredInsightId)) {
            _featuredInsightId = insights.isEmpty ? null : insights.first.id;
          }
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
          setState(() {
            _insights = insights;
            if (insights.isEmpty ||
                !insights.any((insight) => insight.id == _featuredInsightId)) {
              _featuredInsightId = insights.isEmpty ? null : insights.first.id;
            }
          });
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'i 的观察',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                  letterSpacing: 0.5,
                ),
              ),
              if (_insights.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  _insights.length == 1 ? '最近有一件事值得留意' : '最近有几件事值得留意',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _inkPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_refreshing)
          const SizedBox(
            width: 32,
            height: 32,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _accent,
              ),
            ),
          )
        else
          IconButton(
            onPressed: _loading ? null : _refresh,
            tooltip: '刷新洞察',
            visualDensity: VisualDensity.compact,
            iconSize: 17,
            color: _inkMuted,
            icon: const Icon(Icons.refresh_rounded),
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
        _buildLeadInsight(_featuredInsight),
        if (_compactInsights.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildCompactInsights(),
        ],
      ],
    );
  }

  LifeInsight get _featuredInsight => _insights.firstWhere(
        (insight) => insight.id == _featuredInsightId,
        orElse: () => _insights.first,
      );

  List<LifeInsight> get _compactInsights => _insights
      .where((insight) => insight.id != _featuredInsight.id)
      .toList(growable: false);

  Widget _buildLeadInsight(LifeInsight ins) {
    final tokens = context.hereIamTheme;
    final points = _parsePoints(ins.dataPointsJson);
    final viz = _InsightViz(type: ins.insightType, points: points);
    final mode = _visualMode(points);
    final paper = Color.alphaBlend(
      tokens.accent.withValues(alpha: 0.10),
      tokens.textPrimary,
    );
    final paperInk = tokens.background;

    return Container(
      key: const ValueKey('insight_lead_card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _leadMeta(ins),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: paperInk.withValues(alpha: 0.60),
                  letterSpacing: 0.25,
                ),
              ),
              const Spacer(),
              Text(
                _updatedLabel(ins.updatedAt),
                style: TextStyle(
                  fontSize: 11,
                  color: paperInk.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            ins.narrative,
            style: TextStyle(
              fontSize: 16,
              height: 1.55,
              fontWeight: FontWeight.w600,
              color: paperInk.withValues(alpha: 0.92),
            ),
          ),
          if (mode == _InsightVisualMode.chart) ...[
            const SizedBox(height: 13),
            Semantics(
              label:
                  '${_typeLabel(ins.insightType)}图表，${_evidenceLabel(points)}',
              image: true,
              child: Container(
                key: const ValueKey('insight_chart'),
                width: double.infinity,
                height: _chartH,
                decoration: BoxDecoration(
                  color: tokens.surfaceDeep,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: tokens.glassStroke,
                    width: 0.7,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: CustomPaint(
                    painter: _InsightPainter(viz),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ] else if (mode == _InsightVisualMode.metric) ...[
            const SizedBox(height: 13),
            _buildSingleValueEvidence(points, tokens),
          ],
          const SizedBox(height: 11),
          Text(
            _evidenceLabel(points),
            style: TextStyle(
              fontSize: 11.5,
              color: paperInk.withValues(alpha: 0.52),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleValueEvidence(
    List<_DataPoint> points,
    HereIamThemeTokens tokens,
  ) {
    final point = points.lastWhere((item) => item.value != null);
    return Container(
      key: const ValueKey('insight_metric'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: tokens.surfaceDeep,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              point.rawValue,
              style: TextStyle(
                fontSize: 26,
                height: 1,
                fontWeight: FontWeight.w700,
                color: tokens.highlight,
              ),
            ),
          ),
          if (point.date.isNotEmpty)
            Text(
              point.date,
              style: TextStyle(fontSize: 11, color: tokens.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactInsights() {
    final tokens = context.hereIamTheme;
    final compactInsights = _compactInsights;
    return Material(
      key: const ValueKey('insight_compact_list'),
      color: tokens.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < compactInsights.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 0.6, color: tokens.glassStroke),
            InkWell(
              onTap: () => setState(
                () => _featuredInsightId = compactInsights[i].id,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        _typeLabel(compactInsights[i].insightType),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        compactInsights[i].narrative,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: tokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _InsightVisualMode _visualMode(List<_DataPoint> points) {
    final numericCount = points.where((point) => point.value != null).length;
    if (numericCount >= 2) return _InsightVisualMode.chart;
    if (numericCount == 1) return _InsightVisualMode.metric;
    return _InsightVisualMode.narrative;
  }

  String _leadMeta(LifeInsight insight) {
    final period = switch (insight.period) {
      'daily' => '今天',
      'weekly' => '近 7 天',
      'monthly' => '近 30 天',
      _ => '近期',
    };
    return '$period · ${_typeLabel(insight.insightType)}';
  }

  String _updatedLabel(int timestamp) {
    final updated = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (updated.year == now.year &&
        updated.month == now.month &&
        updated.day == now.day) {
      return '更新于今天';
    }
    return '${updated.month}月${updated.day}日更新';
  }

  String _evidenceLabel(List<_DataPoint> points) {
    final numericCount = points.where((point) => point.value != null).length;
    if (numericCount >= 2) {
      return '${points.length} 条记录 · $numericCount 个有效数据点';
    }
    if (numericCount == 1) return '来自 1 条有效数值记录';
    if (points.isNotEmpty) return '基于 ${points.length} 条已记录内容';
    return '基于已记录内容';
  }

  String _typeLabel(String type) {
    return switch (type) {
      'trend' => '趋势',
      'pattern' => '模式',
      'streak' => '连续',
      'baseline' => '基线',
      'anomaly' => '异常',
      'projection' => '预测',
      _ => '观察',
    };
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

enum _InsightVisualMode { chart, metric, narrative }

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
      old.viz.points.length != viz.points.length ||
      !_sameValues(old.viz.points, viz.points);

  bool _sameValues(List<_DataPoint> a, List<_DataPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].rawValue != b[i].rawValue) {
        return false;
      }
    }
    return true;
  }

  // ── helpers ──
  List<double> _numericValues() => viz.points
      .map((p) => p.value)
      .whereType<double>()
      .toList(growable: false);

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
    const pad = 14.0;
    final w = size.width - pad * 2 - 14; // leave room for arrow
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

    canvas.drawPath(fill, Paint()..color = _accent.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Last dot
    final lastX = pad + w;
    final lastY = pad + h - ((vals.last - minV) / range) * h;
    canvas.drawCircle(Offset(lastX, lastY), 3.6, Paint()..color = _highlight);

    // Direction arrow
    final up = vals.last >= vals.first;
    final ax = size.width - 10;
    final ay = up ? pad + 2 : size.height - pad - 2;
    final arrowPaint = Paint()
      ..color = (up ? _highlight : _warn)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
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
    _drawMiniText(canvas, _formatValue(maxV),
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
      canvas.drawCircle(Offset(endX, endY), 2.6, Paint()..color = _highlight);
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
