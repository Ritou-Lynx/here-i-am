/// Desktop whiteboard workbench home.
///
/// Desktop and phone keep independent page surfaces. The home only exposes
/// the native whiteboard loop and never routes into phone-only life spaces.
library;

import 'package:flutter/material.dart';

import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

import '../view_models/desktop_home_view_model.dart';

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

/// The desktop home currently owns two real work loops: return to a recent
/// board, or organise a card that has not been placed on any board yet.
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
        final primaryDesktop = width >= 920 && constraints.maxHeight >= 560;
        final columns = width >= 620 ? 2 : 1;
        const gap = 12.0;
        final moduleWidth = (width - gap * (columns - 1)) / columns;
        const moduleHeight = 320.0;
        return GridView(
          key: const ValueKey('workbench_module_grid'),
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
    this.trailing,
    this.onTap,
    required this.child,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: whiteboardUiTextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
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
      trailing: const _StatusTag(text: '工作面'),
      onTap: items.isEmpty ? onOpenBoards : null,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (items.isEmpty)
            const _EmptyHint('还没有白板 · 点击前往白板索引新建')
          else
            for (final board in items)
              _ModuleRow(
                title: board.title,
                subtitle: board.subtitle,
                onTap: () => onOpenBoard(board.boardId),
              ),
          const SizedBox(height: 8),
          _ModuleRow(
            title: '查看全部白板',
            subtitle: '新建、搜索或继续整理',
            tag: '打开',
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
      title: '待上板卡片',
      trailing: _StatusTag(text: '${cards.length} 张'),
      onTap: onTap,
      child: cards.isEmpty
          ? const _EmptyHint('暂无待上板卡片 · 点击打开卡片库')
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
                const SizedBox(height: 4),
                const _SectionLabel('在卡片库中筛选后放入任意白板'),
              ],
            ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.title,
    required this.subtitle,
    this.tag,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
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
                        fontSize: 14,
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: whiteboardUiTextStyle(
                        fontSize: 12,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                _StatusTag(text: tag!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Text(
      text,
      style: whiteboardUiTextStyle(
        fontSize: 12,
        color: tokens.textFaint,
        height: 1.4,
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.divider.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: whiteboardUiTextStyle(
          fontSize: 11,
          color: tokens.textMuted,
          height: 1.35,
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
