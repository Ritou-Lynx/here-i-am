/// Compact, whiteboard-native charts for the desktop workbench home.
///
/// The geometry follows the Lieflat Palm visual grammar but is implemented
/// locally from product data. No Lieflat template code or SVG is copied.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/ui/core/charts/palm_chart.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/view_models/desktop_home_view_model.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class DesktopCardActivityChart extends StatelessWidget {
  const DesktopCardActivityChart({
    super.key,
    required this.points,
  });

  final List<DesktopCountPoint> points;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    if (points.isEmpty || points.every((point) => point.value == 0)) {
      return const DesktopChartEmpty('近 30 天还没有新卡片');
    }
    final maxValue = points.fold<int>(
      0,
      (current, point) => math.max(current, point.value),
    );
    final peakIndex = points.lastIndexWhere(
      (point) => point.value == maxValue,
    );
    final columns = <Widget>[];
    for (var column = 0; column < 5; column++) {
      columns.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < 6; row++) ...[
              _HeatCell(
                value: points[column * 6 + row].value,
                maxValue: maxValue,
                highlighted: column * 6 + row == peakIndex,
              ),
              if (row != 5) const SizedBox(height: 4),
            ],
          ],
        ),
      );
    }
    final total = points.fold<int>(0, (sum, point) => sum + point.value);
    return Semantics(
      label: '近三十天新增卡片 $total 张，单日最高 $maxValue 张',
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < columns.length; index++) ...[
                columns[index],
                if (index != columns.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
                style: whiteboardUiTextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              Text(
                '新增卡片',
                style: whiteboardUiTextStyle(
                  fontSize: 12,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '峰值 $maxValue / 天',
                style: whiteboardUiTextStyle(
                  fontSize: 11,
                  color: tokens.textFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.value,
    required this.maxValue,
    required this.highlighted,
  });

  final int value;
  final int maxValue;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final ratio = maxValue == 0 ? 0.0 : value / maxValue;
    final color = value == 0
        ? tokens.divider.withValues(alpha: 0.34)
        : highlighted
            ? tokens.focus
            : ratio > 0.66
                ? tokens.action
                : ratio > 0.33
                    ? tokens.actionSecondary
                    : tokens.actionSoft;
    return Tooltip(
      message: '$value 张',
      child: Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class DesktopCardCompositionChart extends StatelessWidget {
  const DesktopCardCompositionChart({
    super.key,
    required this.kindCounts,
    required this.mediaCounts,
  });

  final Map<CardKind, int> kindCounts;
  final Map<SourceMediaType, int> mediaCounts;

  @override
  Widget build(BuildContext context) {
    if (kindCounts.values.fold<int>(0, (a, b) => a + b) == 0) {
      return const DesktopChartEmpty('还没有可统计的卡片');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompositionRow<CardKind>(
          label: '卡片角色',
          values: kindCounts,
          labelFor: _cardKindLabel,
        ),
        const SizedBox(height: 14),
        if (mediaCounts.isEmpty)
          const DesktopChartEmpty('来源卡建立后显示媒介构成', compact: true)
        else
          _CompositionRow<SourceMediaType>(
            label: '来源媒介',
            values: mediaCounts,
            labelFor: _mediaTypeLabel,
          ),
      ],
    );
  }
}

class _CompositionRow<T> extends StatelessWidget {
  const _CompositionRow({
    required this.label,
    required this.values,
    required this.labelFor,
  });

  final String label;
  final Map<T, int> values;
  final String Function(T value) labelFor;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final entries = values.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final palette = [
      tokens.action,
      tokens.actionSecondary,
      tokens.actionSoft,
      tokens.textMuted,
      tokens.textFaint,
    ];
    final cells = <Color>[];
    for (var index = 0; index < 24; index++) {
      final target = ((index + 0.5) / 24) * total;
      var cumulative = 0;
      var colorIndex = 0;
      for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        cumulative += entries[entryIndex].value;
        if (target <= cumulative) {
          colorIndex = entryIndex;
          break;
        }
      }
      cells.add(palette[colorIndex % palette.length]);
    }
    return Semantics(
      label:
          '$label，共 $total 项，${entries.map((e) => '${labelFor(e.key)} ${e.value}').join('，')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: whiteboardUiTextStyle(
                  fontSize: 12,
                  color: tokens.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                entries.take(3).map((entry) {
                  return '${labelFor(entry.key)} ${entry.value}';
                }).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: whiteboardUiTextStyle(
                  fontSize: 11,
                  color: tokens.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final color in cells)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DesktopPlacementChart extends StatelessWidget {
  const DesktopPlacementChart({
    super.key,
    required this.placed,
    required this.unplaced,
  });

  final int placed;
  final int unplaced;

  @override
  Widget build(BuildContext context) {
    final total = placed + unplaced;
    if (total == 0) return const DesktopChartEmpty('还没有卡片');
    final placedRatio = placed / total;
    return Semantics(
      label: '已上板 $placed 张，待整理 $unplaced 张',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Rung(
            label: '已上板',
            value: placed,
            ratio: placedRatio,
            active: true,
          ),
          const SizedBox(height: 14),
          _Rung(
            label: '待整理',
            value: unplaced,
            ratio: 1 - placedRatio,
            active: false,
          ),
        ],
      ),
    );
  }
}

class _Rung extends StatelessWidget {
  const _Rung({
    required this.label,
    required this.value,
    required this.ratio,
    required this.active,
  });

  final String label;
  final int value;
  final double ratio;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: whiteboardUiTextStyle(
              fontSize: 12,
              color: tokens.textMuted,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: tokens.divider.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    height: 7,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      color: active ? tokens.action : tokens.actionSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: whiteboardUiTextStyle(
              fontSize: 12,
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class DesktopBoardGrowthChart extends StatelessWidget {
  const DesktopBoardGrowthChart({
    super.key,
    required this.points,
  });

  final List<DesktopCountPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty || points.every((point) => point.value == 0)) {
      return const DesktopChartEmpty('创建白板后显示六周增长');
    }
    return PalmChart(
      key: const ValueKey('desktop_board_growth_palm_chart'),
      type: PalmChartType.trend,
      height: 104,
      borderRadius: 6,
      points: [
        for (final point in points)
          PalmChartPoint(
            date: point.label,
            rawValue: '${point.value} 张',
            value: point.value.toDouble(),
          ),
      ],
    );
  }
}

class DesktopChartEmpty extends StatelessWidget {
  const DesktopChartEmpty(this.message, {super.key, this.compact = false});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        message,
        style: whiteboardUiTextStyle(
          fontSize: compact ? 11 : 12,
          height: 1.45,
          color: compact ? tokens.textFaint : tokens.textMuted,
        ),
      ),
    );
  }
}

String _cardKindLabel(CardKind kind) {
  return switch (kind) {
    CardKind.source => '来源',
    CardKind.note => '文字',
    CardKind.annotation => '批注',
    CardKind.taskArtifact => '产物',
    CardKind.reference => '引用',
  };
}

String _mediaTypeLabel(SourceMediaType type) {
  return switch (type) {
    SourceMediaType.text => '文本',
    SourceMediaType.book => '书籍',
    SourceMediaType.pdf => 'PDF',
    SourceMediaType.image => '图片',
    SourceMediaType.web => '网页',
    SourceMediaType.video => '视频',
    SourceMediaType.audio => '音频',
    SourceMediaType.file => '文件',
  };
}
