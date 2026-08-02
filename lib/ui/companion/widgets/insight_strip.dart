/// Insight Strip — reusable widget that displays Life Insights for a domain
/// at the top of an observation panel.
///
/// Reads from [LifeInsightService] and shows the latest insights as a
/// compact card with emoji + narrative text.
library;

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

class InsightStrip extends StatefulWidget {
  const InsightStrip({
    super.key,
    required this.domain,
    this.maxItems = 3,
  });

  /// Which domain to show insights for: 'health' | 'finance' | 'schedule' | 'reading'
  final String domain;

  /// Max number of insight lines to show.
  final int maxItems;

  @override
  State<InsightStrip> createState() => _InsightStripState();
}

class _InsightStripState extends State<InsightStrip> {
  List<LifeInsight> _insights = [];
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
    if (_loading || _insights.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD0E3F7),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined, size: 16,
                  color: Color(0xFF4A90D9)),
              const SizedBox(width: 6),
              const Text(
                '洞察',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4A90D9),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _loadInsights,
                child: const Icon(Icons.refresh_rounded,
                    size: 14, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._insights.map((ins) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeEmoji(ins.insightType),
                      style: const TextStyle(fontSize: 14),
                    ),
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
              )),
        ],
      ),
    );
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