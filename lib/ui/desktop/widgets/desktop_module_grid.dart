/// Desktop workbench module grid — spine-contract §3.2 首页模块网格。
///
/// 首屏在一个常见桌面窗口高度内读懂全貌：模块网格（默认 4 列 × 2 行），
/// 每个模块都提供真实数据或诚实空态，并有可执行去向，不放
/// 没有后续行为的装饰按钮（visual-rules §8.1）。
library;

import 'package:flutter/material.dart';

import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

import '../view_models/desktop_home_view_model.dart';

/// 模块网格回调集合：桌面壳把真实路由 / 动作接进来。
class WorkbenchModuleCallbacks {
  const WorkbenchModuleCallbacks({
    required this.onOpenObservation,
    required this.onOpenSchedule,
    required this.onOpenBoard,
    required this.onOpenBoards,
    required this.onOpenTaskCenter,
    required this.onOpenCardLibrary,
    required this.onOpenReading,
    required this.onOpenMemoryCenter,
    required this.onContinueChat,
  });

  /// 林埃观察 → 生活空间（洞察观察面）。
  final VoidCallback onOpenObservation;

  /// 日程与待办 → 日历。
  final VoidCallback onOpenSchedule;

  /// 继续工作 → 某张白板画布（boardId）。
  final void Function(String boardId) onOpenBoard;

  /// 继续工作空态 → 白板索引。
  final VoidCallback onOpenBoards;

  /// 后台任务 / 活跃任务 → 任务中心。
  final VoidCallback onOpenTaskCenter;

  /// 待整理卡片 / 继续阅读 → 卡片库。
  final VoidCallback onOpenCardLibrary;

  /// 继续阅读 → 统一阅读空间。
  final VoidCallback onOpenReading;

  /// 记忆回顾 / 今日总结 → 记忆中心。
  final VoidCallback onOpenMemoryCenter;

  /// 今日总结 → 展开林埃悬浮对话。
  final VoidCallback onContinueChat;
}

/// 模块网格（响应式列数，桌面首屏默认 4 列 × 2 行）。
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
        final columns = primaryDesktop
            ? 4
            : width >= 620
                ? 2
                : 1;
        // 1280×720 与 1440×900 都固定为 4 列 × 2 行首屏。
        const gap = 12.0;
        final moduleWidth = (width - gap * (columns - 1)) / columns;
        final rowCount = (8 / columns).ceil();
        final moduleHeight = primaryDesktop
            ? (constraints.maxHeight - gap * (rowCount - 1)) / rowCount
            : 310.0;
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
            _ObservationModule(
              key: const ValueKey('module_observation'),
              data: data,
              onTap: callbacks.onOpenObservation,
            ),
            _ScheduleModule(
              key: const ValueKey('module_schedule'),
              cards: data.scheduleCards,
              overview: data.scheduleOverview,
              onTap: callbacks.onOpenSchedule,
            ),
            _TodaySummaryModule(
              key: const ValueKey('module_today_summary'),
              todayCount: data.todayRecordCount,
              followUpCount: data.followUpCount,
              onTap: callbacks.onOpenMemoryCenter,
              onContinueChat: callbacks.onContinueChat,
            ),
            _ContinueWorkModule(
              key: const ValueKey('module_continue_work'),
              items: data.continueWork,
              onOpenBoard: callbacks.onOpenBoard,
              onOpenBoards: callbacks.onOpenBoards,
              onOpenTaskCenter: callbacks.onOpenTaskCenter,
            ),
            _PendingCardsModule(
              key: const ValueKey('module_pending_cards'),
              cards: data.pendingCards,
              onTap: callbacks.onOpenCardLibrary,
            ),
            _ContinueReadingModule(
              key: const ValueKey('module_continue_reading'),
              onTap: callbacks.onOpenReading,
            ),
            _MemoryReviewModule(
              key: const ValueKey('module_memory_review'),
              cards: data.recentMemoryCards,
              onTap: callbacks.onOpenMemoryCenter,
            ),
            _BackgroundTasksModule(
              key: const ValueKey('module_background_tasks'),
              counts: data.taskStatusCounts,
              activeCount: data.activeTaskCount,
              onTap: callbacks.onOpenTaskCenter,
            ),
          ],
        );
      },
    );
  }
}

// ── 模块壳 ───────────────────────────────────────────────────────────────────

/// 统一模块容器：surface 承载、10 圆角、16 内距、15/600 模块标题。
/// 一个模块只使用一种抬升手段（无阴影），内容区可被内部列表消化。
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: whiteboardUiTextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
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

/// 模块内的节标题（12px 次级文字）。
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
        color: tokens.textMuted,
        height: 1.4,
      ),
    );
  }
}

/// 模块内的可点击条目行。
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.title, this.subtitle, this.tag, this.onTap});

  final String title;
  final String? subtitle;
  final String? tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: whiteboardUiTextStyle(
                            fontSize: 14,
                            color: tokens.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 6),
                        _StatusTag(text: tag!),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: whiteboardUiTextStyle(
                        fontSize: 12,
                        color: tokens.textFaint,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: tokens.textFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 11px 状态标签（灰阶，不用色块）。
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

/// 模块内空态（12px 弱文字）。
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

// ── 林埃观察 ─────────────────────────────────────────────────────────────────

/// 林埃观察：真实计数小图 + 诚实接入说明。整卡可点 → 生活空间。
class _ObservationModule extends StatelessWidget {
  const _ObservationModule({
    super.key,
    required this.data,
    required this.onTap,
  });

  final DesktopHomeData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final overview = data.scheduleOverview;
    final tokens = DesktopWorkspaceTokens.of(context);
    return WorkbenchModuleCard(
      title: '林埃观察',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatBlock(label: '白板', value: data.boards.length),
              _StatBlock(label: '活跃任务', value: data.activeTaskCount),
              _StatBlock(label: '待整理', value: data.pendingCards.length),
            ],
          ),
          const SizedBox(height: 12),
          const _SectionLabel('今日待办'),
          const SizedBox(height: 4),
          Text(
            '逾期 ${overview['overdue'] ?? 0} · 今日 ${overview['today'] ?? 0} · '
            '未排期 ${overview['unscheduled'] ?? 0}',
            style: whiteboardUiTextStyle(
              fontSize: 14,
              color: tokens.textPrimary,
              height: 1.4,
            ),
          ),
          const Spacer(),
          const _SectionLabel('洞察判断由观察面板接入 · 点击前往'),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: whiteboardUiTextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
              height: 1.2,
            ),
          ),
          Text(
            label,
            style: whiteboardUiTextStyle(
              fontSize: 12,
              color: tokens.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 日程与待办 ───────────────────────────────────────────────────────────────

class _ScheduleModule extends StatelessWidget {
  const _ScheduleModule({
    super.key,
    required this.cards,
    required this.overview,
    required this.onTap,
  });

  final List<MemoryCardViewData> cards;
  final Map<String, int> overview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return WorkbenchModuleCard(
      title: '日程与待办',
      trailing: const _StatusTag(text: '可完成'),
      onTap: onTap,
      child: cards.isEmpty
          ? const _EmptyHint('暂无待办与日程 · 点击前往日历')
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _ModuleRow(
                  title: cards.first.title,
                  subtitle: _dueLabel(cards.first, now),
                  tag: '最近到期',
                  onTap: onTap,
                ),
                for (final card in cards.skip(1).take(3))
                  _ModuleRow(
                    title: card.title,
                    subtitle: _dueLabel(card, now),
                    onTap: onTap,
                  ),
                const SizedBox(height: 4),
                _SectionLabel(
                  '逾期 ${overview['overdue'] ?? 0} · 今日 ${overview['today'] ?? 0} · '
                  '未排期 ${overview['unscheduled'] ?? 0}',
                ),
              ],
            ),
    );
  }
}

String _dueLabel(MemoryCardViewData card, DateTime now) {
  final ms = card.structuredEventTimeMs;
  if (ms == null) return '未排期 · ${_relativeDay(card.createdAt)}';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final hm = '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
  if (day.isBefore(today)) return '已逾期 · $hm';
  if (day == today) return '今天 $hm';
  return '${dt.month} 月 ${dt.day} 日 $hm';
}

// ── 今日总结 ─────────────────────────────────────────────────────────────────

class _TodaySummaryModule extends StatelessWidget {
  const _TodaySummaryModule({
    super.key,
    required this.todayCount,
    required this.followUpCount,
    required this.onTap,
    required this.onContinueChat,
  });

  final int todayCount;
  final int followUpCount;
  final VoidCallback onTap;
  final VoidCallback onContinueChat;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return WorkbenchModuleCard(
      title: '今日总结',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今天已记录 $todayCount 条，待确认 $followUpCount 条。',
            style: whiteboardUiTextStyle(
              fontSize: 14,
              color: tokens.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          const _SectionLabel('点击查看今日 User-truth 与候选确认'),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onContinueChat,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.action,
                    side: BorderSide(color: tokens.divider),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    '继续对话',
                    style: whiteboardUiTextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 继续工作 ─────────────────────────────────────────────────────────────────

/// 继续工作：最近白板 + 活跃任务房间（spine-contract §3.2 必达模块）。
class _ContinueWorkModule extends StatelessWidget {
  const _ContinueWorkModule({
    super.key,
    required this.items,
    required this.onOpenBoard,
    required this.onOpenBoards,
    required this.onOpenTaskCenter,
  });

  final List<ContinueWorkItem> items;
  final void Function(String boardId) onOpenBoard;
  final VoidCallback onOpenBoards;
  final VoidCallback onOpenTaskCenter;

  @override
  Widget build(BuildContext context) {
    final boards = items.where((i) => i.isBoard).toList();
    final tasks = items.where((i) => !i.isBoard).toList();
    return WorkbenchModuleCard(
      title: '继续工作',
      trailing: const _StatusTag(text: '最近'),
      onTap: items.isEmpty ? onOpenBoards : null,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _SectionLabel('最近白板'),
          if (boards.isEmpty)
            const _EmptyHint('还没有白板 · 点击前往白板索引新建')
          else
            for (final board in boards)
              _ModuleRow(
                title: board.title,
                subtitle: board.subtitle,
                onTap: () => onOpenBoard(board.boardId),
              ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 6),
            const _SectionLabel('活跃任务'),
            for (final task in tasks)
              _ModuleRow(
                title: task.title,
                subtitle: task.subtitle,
                onTap: onOpenTaskCenter,
              ),
          ],
        ],
      ),
    );
  }
}

// ── 继续阅读 ─────────────────────────────────────────────────────────────────

/// 继续阅读：尚未接入统一进度查询时只呈现诚实空态，不造演示内容。
class _ContinueReadingModule extends StatelessWidget {
  const _ContinueReadingModule({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WorkbenchModuleCard(
      title: '继续阅读',
      onTap: onTap,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EmptyHint('暂无可续接的阅读进度'),
          Spacer(),
          _SectionLabel('点击前往统一阅读空间'),
        ],
      ),
    );
  }
}

// ── 待整理卡片 ───────────────────────────────────────────────────────────────

/// 待整理卡片：未被任何白板引用的最近卡片（真实数据，必达模块）。
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
      trailing: _StatusTag(text: '${cards.length} 张'),
      onTap: onTap,
      child: cards.isEmpty
          ? const _EmptyHint('暂无待整理卡片 · 点击前往卡片库')
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
                const _SectionLabel('等待分类或放入白板 · 点击前往卡片库'),
              ],
            ),
    );
  }
}

// ── 记忆回顾 ─────────────────────────────────────────────────────────────────

class _MemoryReviewModule extends StatelessWidget {
  const _MemoryReviewModule({
    super.key,
    required this.cards,
    required this.onTap,
  });

  final List<MemoryCardViewData> cards;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WorkbenchModuleCard(
      title: '记忆回顾',
      trailing: _StatusTag(text: '${cards.length} 条'),
      onTap: onTap,
      child: cards.isEmpty
          ? const _EmptyHint('还没有记忆卡片 · 点击前往记忆中心')
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final card in cards)
                  _ModuleRow(
                    title: card.dropletLabel.isEmpty
                        ? card.title
                        : '${card.dropletLabel} · ${card.title}',
                    subtitle: _relativeDay(card.updatedAt),
                    onTap: onTap,
                  ),
                const SizedBox(height: 4),
                const _SectionLabel('最近新增与修订 · 点击前往记忆中心'),
              ],
            ),
    );
  }
}

// ── 后台任务 ─────────────────────────────────────────────────────────────────

class _BackgroundTasksModule extends StatelessWidget {
  const _BackgroundTasksModule({
    super.key,
    required this.counts,
    required this.activeCount,
    required this.onTap,
  });

  final Map<TaskStatus, int> counts;
  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    int countOf(TaskStatus s) => counts[s] ?? 0;
    final total = counts.values.fold(0, (a, b) => a + b);
    return WorkbenchModuleCard(
      title: '后台任务',
      trailing: _StatusTag(text: '$total 项'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatBlock(label: '运行中', value: countOf(TaskStatus.running)),
              _StatBlock(
                label: '等待决定',
                value: countOf(TaskStatus.waitingForUser),
              ),
              _StatBlock(label: '失败', value: countOf(TaskStatus.failed)),
              _StatBlock(label: '已完成', value: countOf(TaskStatus.completed)),
            ],
          ),
          const Spacer(),
          _SectionLabel(
            activeCount > 0
                ? '$activeCount 个活跃任务 · 点击前往任务中心'
                : '暂无活跃任务 · 点击前往任务中心',
          ),
        ],
      ),
    );
  }
}

// ── 时间工具 ─────────────────────────────────────────────────────────────────

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
