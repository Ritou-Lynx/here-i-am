/// Insight Strip — reusable widget that displays Life Insights for a domain
/// at the top of an observation panel.
///
/// Three states:
/// - loading: subtle shimmer placeholder (the bar is always present)
/// - empty: visible bar with a quiet "observing" hint
/// - populated: sparkline chart (from dataPoints) + emoji + narrative text
///
/// The refresh button re-queries the latest insights AND (when the callback is
/// provided) triggers a fresh LifeInsight analysis, so new data can appear.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// Reusable sparkline painter for insight data points.
class InsightSparkline extends StatelessWidget {
  const InsightSparkline({
    super.key,
    required this.values,
    this.height = 36,
    this.color = const Color(0xFF737B46),
  });

  final List<double> values;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _InsightSparklinePainter(values, color),
      ),
    );
  }
}

class _InsightSparklinePainter extends CustomPainter {
  _InsightSparklinePainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minV = points.reduce((a, b) => a < b ? a : b);
    final maxV = points.reduce((a, b) => a > b ? a : b);
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
      Paint()..color = color.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final last = points.last;
    final lastX = size.width;
    final lastY =
        size.height - 4 - ((last - minV) / range) * (size.height - 8);
    canvas.drawCircle(
      Offset(lastX - 2, lastY),
      2.8,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _InsightSparklinePainter oldDelegate) =>
      oldDelegate.color != color || !_listEq(oldDelegate.points, points);

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class InsightStrip extends StatefulWidget {
  const InsightStrip({
    super.key,
    required this.domain,
    this.maxItems = 3,
    this.onRefresh,
  });

  /// Which domain to show insights for: 'health' | 'finance' | 'schedule' | 'reading'
  final String domain;

  /// Max number of insight lines to show.
  final int maxItems;

  /// Optional callback to trigger a fresh LifeInsight analysis when the
  /// refresh button is pressed. If null, refresh only re-queries the DB.
  final Future<void> Function()? onRefresh;

  @override
  State<InsightStrip> createState() => _InsightStripState();
}

class _InsightStripState extends State<InsightStrip> {
  // Spring-rain palette (matches Schedule panel / Life Space).
  static const _accent = Color(0xFF737B46);
  static const _inkSoft = Color(0xFF667061);
  static const _surface = Color(0xE8F7F5EE);
  static const _edge = Color(0x33737B46);

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

  /// Refresh: optionally trigger a new analysis, then re-query the DB.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    // 1. Trigger a fresh analysis if a callback is provided (fire the new
    //    analysis, then give it a beat to write before re-querying).
    if (widget.onRefresh != null) {
      try {
        await widget.onRefresh!();
      } catch (_) {}
    }

    // 2. Re-query the latest insights from the DB.
    if (LifeInsightService.isInitialized) {
      try {
        final insights = await LifeInsightService.instance
            .getLatestByDomain(widget.domain, limit: widget.maxItems);
        if (mounted) {
          setState(() {
            _insights = insights;
          });
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _edge, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 10),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.insights_outlined, size: 16, color: _accent),
        const SizedBox(width: 6),
        const Text(
          '洞察',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _accent,
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
                size: 16, color: _inkSoft),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _insights.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerLine(widthFactor: 0.9),
          const SizedBox(height: 8),
          _shimmerLine(widthFactor: 0.6),
        ],
      );
    }

    if (_insights.isEmpty) {
      return Text(
        _emptyHintForDomain(widget.domain),
        style: const TextStyle(fontSize: 13, height: 1.5, color: _inkSoft),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final ins in _insights) _buildInsightItem(ins),
      ],
    );
  }

  Widget _buildInsightItem(LifeInsight ins) {
    // Parse data points for charting. Values may be numeric strings
    // ("320", "6.2") or time strings ("00:45") or with units ("6.2h").
    final chartValues = _extractChartValues(ins.dataPointsJson);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_typeEmoji(ins.insightType),
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ins.narrative,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (chartValues.isNotEmpty) ...[
            const SizedBox(height: 8),
            InsightSparkline(values: chartValues),
          ],
        ],
      ),
    );
  }

  Widget _shimmerLine({required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: _edge,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  /// Parse the insight's dataPointsJson into numeric chart values.
  ///
  /// dataPointsJson format: [{"date":"2026-07-20","value":"00:45"},...]
  /// Handles: plain numbers ("320"), decimals ("6.2"), units ("6.2h"),
  /// and clock times ("00:45" → minutes past midnight, so trends in sleep
  /// time render sensibly).
  List<double> _extractChartValues(String json) {
    if (json.isEmpty) return const [];
    List<Map<String, dynamic>> points;
    try {
      final decoded = const JsonDecoder().convert(json);
      if (decoded is! List) return const [];
      points = decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
    if (points.isEmpty) return const [];

    final values = <double>[];
    for (final p in points) {
      final raw = p['value'];
      if (raw == null) continue;
      final s = raw.toString().trim();
      if (s.isEmpty) continue;

      // Clock time "HH:MM" → minutes since midnight.
      final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
      if (timeMatch != null) {
        final h = int.tryParse(timeMatch.group(1)!);
        final m = int.tryParse(timeMatch.group(2)!);
        if (h != null && m != null) {
          values.add((h * 60 + m).toDouble());
          continue;
        }
      }

      // Number with optional unit suffix ("6.2h", "3200 元", "52%").
      final numMatch = RegExp(r'-?\d+\.?\d*').firstMatch(s);
      if (numMatch != null) {
        final v = double.tryParse(numMatch.group(0)!);
        if (v != null) values.add(v);
      }
    }

    return values;
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

  String _typeEmoji(String insightType) {
    switch (insightType) {
      case 'trend':
        return '📈';
      case 'pattern':
        return '🔁';
      case 'streak':
        return '🔥';
      case 'baseline':
        return '📊';
      case 'anomaly':
        return '⚠️';
      case 'projection':
        return '🔮';
      default:
        return '💡';
    }
  }
}