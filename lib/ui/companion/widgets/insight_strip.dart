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
/// Charts are rendered by the shared [PalmChart] component (Lieflat "椰林绿
/// Palm" grammar): trend → hairline line; streak → count + beads; baseline →
/// range capsule; anomaly → chunky bars; pattern → heat cells; projection →
/// solid + dashed forecast.
///
/// The lead uses an opaque mist-paper surface; the chart sits on an opaque
/// warm-paper inset so both remain legible over the rain-glass background.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/charts/palm_chart.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — header/card copy stays on HereIamThemeTokens springRainDaydream.
// Chart surfaces + drawings live in PalmChartPalette.lieflatPalm.
// ─────────────────────────────────────────────────────────────────────────────
const _inkPrimary = Color(0xFFF5EEE0); // warm ivory
const _inkMuted = Color(0x85E6DFCE);
const _accent = Color(0xFFA3A866); // moss
const _glassStroke = Color(0x2EFFFFFF);

const _chartH = 116.0;

/// How the lead evidence should be presented based on available numeric data.
enum _InsightVisualMode { chart, metric, narrative }

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
              child: PalmChart(
                containerKey: const ValueKey('insight_chart'),
                type: _chartType(ins.insightType),
                points: points,
                height: _chartH,
              ),
            ),
          ] else if (mode == _InsightVisualMode.metric) ...[
            const SizedBox(height: 13),
            _buildSingleValueEvidence(points),
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

  Widget _buildSingleValueEvidence(List<PalmChartPoint> points) {
    const palette = PalmChartPalette.lieflatPalm;
    final point = points.lastWhere((item) => item.value != null);
    return Container(
      key: const ValueKey('insight_metric'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: palette.paper,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.grid, width: 0.7),
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
                fontWeight: FontWeight.w800,
                color: PalmChartPalette.lieflatPalm.hero,
              ),
            ),
          ),
          if (point.date.isNotEmpty)
            Text(
              point.date,
              style: TextStyle(
                fontSize: 11,
                color: PalmChartPalette.lieflatPalm.inkMuted,
                fontWeight: FontWeight.w600,
              ),
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

  _InsightVisualMode _visualMode(List<PalmChartPoint> points) {
    final numericCount = points.where((point) => point.value != null).length;
    if (numericCount >= 2) return _InsightVisualMode.chart;
    if (numericCount == 1) return _InsightVisualMode.metric;
    return _InsightVisualMode.narrative;
  }

  PalmChartType _chartType(String type) {
    return switch (type) {
      'trend' => PalmChartType.trend,
      'streak' => PalmChartType.streak,
      'baseline' => PalmChartType.baseline,
      'anomaly' => PalmChartType.anomaly,
      'pattern' => PalmChartType.pattern,
      'projection' => PalmChartType.projection,
      _ => PalmChartType.placeholder,
    };
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

  String _evidenceLabel(List<PalmChartPoint> points) {
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

  List<PalmChartPoint> _parsePoints(String json) {
    if (json.isEmpty) return const [];
    try {
      final decoded = const JsonDecoder().convert(json);
      if (decoded is! List) return const [];
      final pts = <PalmChartPoint>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final date = raw['date']?.toString() ?? '';
        final valueStr = raw['value']?.toString().trim() ?? '';
        final numVal = _parseNumericValue(valueStr);
        pts.add(PalmChartPoint(
            date: date, rawValue: valueStr, value: numVal));
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
