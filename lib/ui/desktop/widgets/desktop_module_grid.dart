/// Compact, data-backed modules on the desktop whiteboard workbench home.
library;

import 'package:flutter/material.dart';

import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/view_models/desktop_home_view_model.dart';
import 'package:memex/ui/desktop/widgets/desktop_home_charts.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class WorkbenchModuleCallbacks {
  const WorkbenchModuleCallbacks({
    required this.onOpenBoard,
    required this.onOpenBoards,
    required this.onOpenCardLibrary,
  });

  final void Function(String boardId) onOpenBoard;
  final VoidCallback onOpenBoards;
  final VoidCallback onOpenCardLibrary;
}

/// Six compact modules fit in two rows on a normal desktop viewport. The
/// charts are projections of repository data, never illustrative samples.
class WorkbenchModuleGrid extends StatelessWidget {
  const WorkbenchModuleGrid({
    super.key,
    required this.data,
    required this.callbacks,
  });

  final DesktopHomeData data;
  final WorkbenchModuleCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final primaryDesktop = width >= 960 && constraints.maxHeight >= 540;
        final columns = primaryDesktop ? 3 : (width >= 620 ? 2 : 1);
        const gap = 12.0;
        final moduleWidth = (width - gap * (columns - 1)) / columns;
        final rows = (6 / columns).ceil();
        final availableHeight = constraints.maxHeight - gap * (rows - 1);
        final moduleHeight = primaryDesktop
            ? availableHeight / rows
            : (constraints.maxHeight >= 520 ? 252.0 : 224.0);

        return GridView(
          key: const ValueKey('workbench_module_grid'),
          padding: EdgeInsets.zero,
          physics: primaryDesktop
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: moduleWidth / moduleHeight,
          ),
          children: [
            WorkbenchModuleCard(
              key: const ValueKey('module_card_activity'),
              title: _activityTitle(data.stats),
              meta: '近 30 天',
              onTap: callbacks.onOpenCardLibrary,
              child: DesktopCardActivityChart(
                points: data.stats.dailyCardCreates,
              ),
            ),
            WorkbenchModuleCard(
              key: const ValueKey('module_card_composition'),
              title: _compositionTitle(data.stats),
              meta: '${data.stats.totalCards} 张',
              onTap: callbacks.onOpenCardLibrary,
              child: DesktopCardCompositionChart(
                kindCounts: data.stats.cardKindCounts,
                mediaCounts: data.stats.sourceMediaCounts,
              ),
            ),
            WorkbenchModuleCard(
              key: const ValueKey('module_card_placement'),
              title: _placementTitle(data.stats),
              meta: '${data.stats.totalCards} 张',
              onTap: callbacks.onOpenCardLibrary,
              child: DesktopPlacementChart(
                placed: data.stats.placedCards,
                unplaced: data.stats.unplacedCards,
              ),
            ),
            WorkbenchModuleCard(
              key: const ValueKey('module_board_growth'),
              title: _boardTitle(data.stats),
              meta: '${data.boards.length} 个最近白板',
              onTap: callbacks.onOpenBoards,
              child: DesktopBoardGrowthChart(points: data.stats.boardGrowth),
            ),
            _ContinueWorkModule(
              key: const ValueKey('module_continue_work'),
              items: data.continueWork,
              onOpenBoard: callbacks.onOpenBoard,
              onOpenBoards: callbacks.onOpenBoards,
            ),
            _PendingCardsModule(
              key: const ValueKey('module_pending_cards'),
              cards: data.pendingCards,
              onTap: callbacks.onOpenCardLibrary,
            ),
          ],
        );
      },
    );
  }
}

class WorkbenchModuleCard extends StatelessWidget {
  const WorkbenchModuleCard({
    super.key,
    required this.title,
    this.meta,
    this.onTap,
    required this.child,
  });

  final String title;
  final String? meta;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: whiteboardUiTextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  if (meta != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      meta!,
                      style: whiteboardUiTextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueWorkModule extends StatelessWidget {
  const _ContinueWorkModule({
    super.key,
    required this.items,
    required this.onOpenBoard,
    required this.onOpenBoards,
  });

  final List<ContinueWorkItem> items;
  final void Function(String boardId) onOpenBoard;
  final VoidCallback onOpenBoards;

  @override
  Widget build(BuildContext context) {
    return WorkbenchModuleCard(
      title: '最近白板',
      meta: '${items.length} 个',
      onTap: items.isEmpty ? onOpenBoards : null,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (items.isEmpty)
            const _EmptyHint('还没有白板 · 前往白板索引新建')
          else
            for (final board in items)
              _ModuleRow(
                title: board.title,
                subtitle: board.subtitle,
                onTap: () => onOpenBoard(board.boardId),
              ),
          _ModuleRow(
            title: '查看全部白板',
            subtitle: '新建、搜索或继续整理',
            onTap: onOpenBoards,
          ),
        ],
      ),
    );
  }
}

class _PendingCardsModule extends StatelessWidget {
  const _PendingCardsModule({
    super.key,
    required this.cards,
    required this.onTap,
  });

  final List<MemoryCardViewData> cards;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WorkbenchModuleCard(
      title: '待整理卡片',
      meta: '${cards.length} 张',
      onTap: onTap,
      child: cards.isEmpty
          ? const _EmptyHint('暂无待整理卡片 · 打开卡片库查看全部')
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final card in cards)
                  _ModuleRow(
                    title: card.dropletLabel.isEmpty
                        ? card.title
                        : '${card.dropletLabel} · ${card.title}',
                    subtitle: '${_relativeDay(card.createdAt)} 记录',
                    onTap: onTap,
                  ),
              ],
            ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: whiteboardUiTextStyle(
                        fontSize: 13,
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: whiteboardUiTextStyle(
                        fontSize: 11,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: tokens.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: whiteboardUiTextStyle(
          fontSize: 12,
          color: tokens.textFaint,
          height: 1.4,
        ),
      ),
    );
  }
}

String _activityTitle(DesktopHomeStats stats) {
  if (stats.cardsCreatedLast30Days == 0) return '近 30 天尚无新增卡片';
  return '近 30 天新增 ${stats.cardsCreatedLast30Days} 张';
}

String _compositionTitle(DesktopHomeStats stats) {
  if (stats.totalCards == 0) return '卡片构成等待记录';
  final entries = stats.cardKindCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return '${_cardKindLabel(entries.first.key)}卡片最多';
}

String _placementTitle(DesktopHomeStats stats) {
  if (stats.totalCards == 0) return '卡片尚未进入白板';
  return '${stats.placedCards} 张已上板 · ${stats.unplacedCards} 张待整理';
}

String _boardTitle(DesktopHomeStats stats) {
  if (stats.boardGrowth.isEmpty || stats.boardGrowth.last.value == 0) {
    return '白板等待建立';
  }
  return '${stats.boardsTouchedLast30Days} 个白板近月有活动';
}

String _cardKindLabel(CardKind kind) => switch (kind) {
      CardKind.note => '文字',
      CardKind.annotation => '批注',
      CardKind.source => '来源',
      CardKind.reference => '引用',
      CardKind.taskArtifact => '产物',
    };

String _relativeDay(int msSinceEpoch) {
  final local = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch).toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff < 30) return '$diff 天前';
  return '${local.month} 月 ${local.day} 日';
}
