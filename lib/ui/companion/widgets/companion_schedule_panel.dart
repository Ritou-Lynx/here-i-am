import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/ui/companion/view_models/schedule_view_model.dart';
import 'package:memex/ui/memory/widgets/memory_card_detail_screen_v3.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
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
  static const _surface = Color(0xE8F7F5EE);
  static const _overdueAccent = Color(0xFFB85C38);

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

        if (!vm.hasAnyCards) {
          return _buildEmpty(context, vm);
        }

        return RefreshIndicator(
          color: _accent,
          backgroundColor: const Color(0xFFF7F5EE),
          onRefresh: () => vm.load.execute(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
            children: [
              _buildOverviewBadges(vm),
              const SizedBox(height: 14),
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
              if (vm.completedCards.isNotEmpty) ...[
                _SectionHeader(
                  label: '已完成',
                  count: vm.completedCards.length,
                  isOverdue: false,
                ),
                const SizedBox(height: 8),
                for (final card in vm.completedCards)
                  _ScheduleCardTile(
                    card: card,
                    isOverdue: false,
                    onTap: () => _openDetail(context, card),
                    onToggle: () => vm.toggleComplete.execute(card.id),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context, ScheduleViewModel vm) {
    return RefreshIndicator(
      color: _accent,
      backgroundColor: const Color(0xFFF7F5EE),
      onRefresh: () => vm.load.execute(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: const Color(0xB8FFFFFF), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available_rounded,
                        color: _accent, size: 20),
                    const SizedBox(width: 9),
                    Text(
                      '暂无待办日程',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
                  ? CompanionSchedulePanel._overdueAccent
                  : CompanionSchedulePanel._accent,
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
                  ? CompanionSchedulePanel._overdueAccent
                  : CompanionSchedulePanel._inkSoft,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              color: CompanionSchedulePanel._inkSoft.withValues(alpha: 0.7),
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
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _summaryText(card),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
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

    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      return '$hour:$minute';
    }
    return '${dt.month}/${dt.day} $hour:$minute';
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
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
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
