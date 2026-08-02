import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/life_insight_scheduler.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/companion/view_models/schedule_view_model.dart';
import 'package:memex/ui/companion/widgets/insight_strip.dart';
import 'package:memex/ui/memory/widgets/memory_card_detail_screen_v3.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:provider/provider.dart';

/// Schedule observation panel — aggregated todo / schedule / plan view.
///
/// Reads active task-like Memory Cards and groups them by time urgency
/// (overdue → today → tomorrow → this week → later → unscheduled).
/// Follows the spring-rain visual language used across the Life Space.
class CompanionSchedulePanel extends StatelessWidget {
  const CompanionSchedulePanel({super.key});

  static const _accent = Color(0xFF737B46);
  static const _ink = Color(0xFF293025);
  static const _inkSoft = Color(0xFF667061);
  static const _onRain = Color(0xFFF5EEE0);
  static const _surface = Color(0xE8F7F5EE);
  static const _overdueAccent = Color(0xFFD09B31);
  static const _overdueHighlight = Color(0xFFF2CA70);

  @override
  Widget build(BuildContext context) {
    return Consumer<ScheduleViewModel>(
      builder: (context, vm, _) {
        if (vm.load.running && !vm.hasAnyCards) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: _accent,
                strokeWidth: 2.2,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: _accent,
          backgroundColor: const Color(0xFFF7F5EE),
          onRefresh: () => vm.load.execute(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
            children: [
              InsightStrip(
                domain: 'schedule',
                onRefresh: () => LifeInsightScheduler(db: AppDatabase.instance)
                    .forceRunWeeklyAnalysis(),
              ),
              _ViewSwitcher(vm: vm),
              const SizedBox(height: 14),
              if (vm.displayMode == ScheduleDisplayMode.todo) ...[
                if (!vm.hasAnyCards) _emptyCard('暂无待办日程'),
                if (vm.hasAnyCards) _buildOverviewBadges(vm),
                if (vm.hasAnyCards) const SizedBox(height: 14),
                for (final section in vm.sections) ...[
                  _SectionHeader(
                    label: section.label,
                    count: section.cards.length,
                    isOverdue: section.bucket == ScheduleBucket.overdue,
                  ),
                  const SizedBox(height: 8),
                  for (final card in section.cards)
                    _ScheduleCardTile(
                      card: card,
                      isOverdue: section.bucket == ScheduleBucket.overdue,
                      onTap: () => _openDetail(context, card),
                      onToggle: () => vm.toggleComplete.execute(card.id),
                    ),
                  const SizedBox(height: 16),
                ],
                _CompletedSection(vm: vm, onOpen: _openDetail),
              ] else
                _CalendarView(vm: vm, onOpen: _openDetail),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyCard(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xB8FFFFFF), width: 0.8),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _inkSoft, fontSize: 14)),
      );

  Widget _buildOverviewBadges(ScheduleViewModel vm) {
    final overdue = vm.overview['overdue'] ?? 0;
    final today = vm.overview['today'] ?? 0;
    final upcoming = vm.overview['upcoming'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xB8FFFFFF), width: 0.8),
      ),
      child: Row(
        children: [
          if (overdue > 0) ...[
            _Badge(
              label: '$overdue 过期',
              color: _overdueAccent,
            ),
            const SizedBox(width: 10),
          ],
          _Badge(label: '$today 今天', color: _accent),
          const SizedBox(width: 10),
          _Badge(label: '$upcoming 待办', color: _inkSoft),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, MemoryCardViewData card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryCardDetailScreenV3(
          cardId: card.id,
          queryService: MemoryCardQueryService(AppDatabase.instance),
          organizerService: RecordOrganizerServiceV3.isInitialized
              ? RecordOrganizerServiceV3.instance
              : null,
        ),
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.vm});
  final ScheduleViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: CompanionSchedulePanel._surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xB8FFFFFF), width: .8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item('待办', ScheduleDisplayMode.todo),
            _item('日历', ScheduleDisplayMode.calendar),
          ],
        ),
      ),
    );
  }

  Widget _item(String label, ScheduleDisplayMode mode) {
    final selected = vm.displayMode == mode;
    return InkWell(
      onTap: () => vm.setDisplayMode(mode),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDDE1CB) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected
                  ? CompanionSchedulePanel._ink
                  : CompanionSchedulePanel._inkSoft,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            )),
      ),
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({required this.vm, required this.onOpen});
  final ScheduleViewModel vm;
  final void Function(BuildContext, MemoryCardViewData) onOpen;

  @override
  Widget build(BuildContext context) {
    final month = vm.visibleMonth;
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = leading + days;
    final rows = (cells / 7).ceil();
    final selectedCards = vm.cardsForDate(vm.selectedDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          decoration: BoxDecoration(
            color: CompanionSchedulePanel._surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xB8FFFFFF), width: .8),
          ),
          child: Column(
            children: [
              Row(children: [
                IconButton(
                    onPressed: () => vm.changeMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                    child: Text('${month.year}年${month.month}月',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: CompanionSchedulePanel._ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600))),
                IconButton(
                    onPressed: () => vm.changeMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded)),
              ]),
              Row(children: [
                for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11,
                              color: CompanionSchedulePanel._inkSoft))),
              ]),
              const SizedBox(height: 6),
              for (var row = 0; row < rows; row++)
                Row(children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(child: _dayCell(leading, days, row * 7 + col)),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('${vm.selectedDate.month}月${vm.selectedDate.day}日',
            style: const TextStyle(
                color: CompanionSchedulePanel._onRain,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black45, blurRadius: 4)])),
        const SizedBox(height: 8),
        if (selectedCards.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: CompanionSchedulePanel._surface,
                borderRadius: BorderRadius.circular(14)),
            child: const Text('这一天没有安排',
                textAlign: TextAlign.center,
                style: TextStyle(color: CompanionSchedulePanel._inkSoft)),
          )
        else
          for (final card in selectedCards)
            _ScheduleCardTile(
              card: card,
              isOverdue: _isOverdue(card),
              onTap: () => onOpen(context, card),
              onToggle: () => vm.toggleComplete.execute(card.id),
            ),
        if (vm.unscheduledCount > 0) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => vm.setDisplayMode(ScheduleDisplayMode.todo),
            icon: const Icon(Icons.schedule_rounded, size: 17),
            label: Text('另有 ${vm.unscheduledCount} 项未安排时间，回到待办处理'),
            style: TextButton.styleFrom(
                foregroundColor: CompanionSchedulePanel._onRain),
          ),
        ],
      ],
    );
  }

  Widget _dayCell(int leading, int days, int index) {
    final day = index - leading + 1;
    if (day < 1 || day > days) return const SizedBox(height: 46);
    final date = DateTime(vm.visibleMonth.year, vm.visibleMonth.month, day);
    final selected = _sameDay(date, vm.selectedDate);
    final today = _sameDay(date, DateTime.now());
    final hasCards = vm.hasCardsOnDate(date);
    return InkWell(
      onTap: () => vm.selectDate(date),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 46,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF737B46) : Colors.transparent,
              shape: BoxShape.circle,
              border: today && !selected
                  ? Border.all(color: const Color(0xFF737B46))
                  : null,
            ),
            child: Text('$day',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        selected ? Colors.white : CompanionSchedulePanel._ink)),
          ),
          Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasCards
                      ? CompanionSchedulePanel._overdueHighlight
                      : Colors.transparent)),
        ]),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isOverdue(MemoryCardViewData card) {
    final ms = card.eventTimeMs;
    if (ms == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime.fromMillisecondsSinceEpoch(ms).isBefore(today);
  }
}

class _CompletedSection extends StatelessWidget {
  const _CompletedSection({required this.vm, required this.onOpen});
  final ScheduleViewModel vm;
  final void Function(BuildContext, MemoryCardViewData) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => vm.setShowCompleted(!vm.showCompleted),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(children: [
            const Text('已完成',
                style: TextStyle(
                    color: CompanionSchedulePanel._onRain,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)])),
            const Spacer(),
            Icon(
                vm.showCompleted
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: CompanionSchedulePanel._onRain),
          ]),
        ),
      ),
      if (vm.showCompleted)
        for (final card in vm.completedCards)
          _ScheduleCardTile(
            card: card,
            isOverdue: false,
            onTap: () => onOpen(context, card),
            onToggle: () => vm.toggleComplete.execute(card.id),
          ),
    ]);
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.isOverdue,
  });

  final String label;
  final int count;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: isOverdue
                  ? CompanionSchedulePanel._overdueHighlight
                  : CompanionSchedulePanel._onRain,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isOverdue
                  ? CompanionSchedulePanel._overdueHighlight
                  : CompanionSchedulePanel._onRain,
              shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              color: CompanionSchedulePanel._onRain.withValues(alpha: 0.78),
              shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCardTile extends StatelessWidget {
  const _ScheduleCardTile({
    required this.card,
    required this.isOverdue,
    required this.onTap,
    required this.onToggle,
  });

  final MemoryCardViewData card;
  final bool isOverdue;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isCompleted =
        card.status == 'completed' || card.status == 'cancelled';
    final timeLabel = _formatTime(card);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
            decoration: BoxDecoration(
              color: CompanionSchedulePanel._surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isOverdue
                    ? CompanionSchedulePanel._overdueAccent
                        .withValues(alpha: 0.4)
                    : const Color(0xB8FFFFFF),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                // Completion toggle
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCompleted
                            ? CompanionSchedulePanel._accent
                            : CompanionSchedulePanel._inkSoft
                                .withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      color: isCompleted
                          ? CompanionSchedulePanel._accent
                          : Colors.transparent,
                    ),
                    child: isCompleted
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 11),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.dropletLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isCompleted
                              ? CompanionSchedulePanel._inkSoft
                              : CompanionSchedulePanel._ink,
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _summaryText(card),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: CompanionSchedulePanel._inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Time + type badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (timeLabel != null)
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: isOverdue
                              ? CompanionSchedulePanel._overdueAccent
                              : CompanionSchedulePanel._inkSoft,
                          fontWeight: isOverdue ? FontWeight.w600 : null,
                        ),
                      ),
                    const SizedBox(height: 4),
                    _TypeChip(type: card.type),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summaryText(MemoryCardViewData card) {
    // Prefer retrievalText (natural language), trim to reasonable length.
    final text = card.retrievalText;
    if (text.length <= 60) return text;
    return '${text.substring(0, 57)}…';
  }

  String? _formatTime(MemoryCardViewData card) {
    final ms = card.eventTimeMs;
    if (ms == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();

    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');

    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '$hour:$minute';
    }
    return '${dt.month}月${dt.day}日 $hour:$minute';
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'task' => ('任务', const Color(0xFF5B7B5E)),
      'schedule' => ('日程', const Color(0xFF5B6B8B)),
      'plan' => ('计划', const Color(0xFF8B7B5B)),
      _ => (type, CompanionSchedulePanel._inkSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
