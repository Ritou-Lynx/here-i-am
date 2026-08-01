import 'package:flutter/foundation.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

/// Time-bucket grouping for the Schedule panel.
enum ScheduleBucket {
  overdue,
  today,
  tomorrow,
  thisWeek,
  later,
  unscheduled,
  completed,
}

/// One section in the schedule list.
class ScheduleSection {
  const ScheduleSection({
    required this.bucket,
    required this.label,
    required this.cards,
  });

  final ScheduleBucket bucket;
  final String label;
  final List<MemoryCardViewData> cards;

  bool get isEmpty => cards.isEmpty;
}

/// ViewModel for the Schedule observation panel.
///
/// Reads active task / schedule / plan cards from Memory V3 and groups them
/// into time-bucketed sections (overdue → today → tomorrow → this week →
/// later → unscheduled). Completed items are hidden by default but can be
/// toggled.
class ScheduleViewModel extends ChangeNotifier {
  ScheduleViewModel({required MemoryCardQueryService queryService})
      : _query = queryService {
    load = Command0<void>(_load);
    toggleComplete = Command1<void, String>(_toggleComplete);
  }

  final MemoryCardQueryService _query;

  late final Command0<void> load;
  late final Command1<void, String> toggleComplete;

  /// Grouped sections for the current filter state.
  List<ScheduleSection> sections = const [];

  /// Summary counts for the header badge row.
  Map<String, int> overview = const {};

  /// Whether to show completed/cancelled cards in a collapsed section.
  bool showCompleted = false;

  /// Cards that have been completed or cancelled (shown when [showCompleted]).
  List<MemoryCardViewData> completedCards = const [];

  bool get hasAnyCards =>
      sections.any((s) => s.cards.isNotEmpty) || completedCards.isNotEmpty;

  Future<Result<void>> _load() => runResultVoid(_refresh);

  Future<Result<void>> _toggleComplete(String cardId) {
    return runResultVoid(() async {
      final organizer = RecordOrganizerServiceV3.isInitialized
          ? RecordOrganizerServiceV3.instance
          : null;
      if (organizer == null) return;

      // Find the card in current sections to determine its current status.
      final allCards = [
        ...sections.expand((s) => s.cards),
        ...completedCards,
      ];
      final card = allCards.where((c) => c.id == cardId).firstOrNull;
      if (card == null) return;

      final newStatus =
          (card.status == 'completed' || card.status == 'cancelled')
              ? 'active'
              : 'completed';

      await organizer.updateCard(cardId, status: newStatus);
      await _refresh();
    });
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      _query.listScheduleCards(includeCompleted: false),
      _query.getScheduleOverview(),
      if (showCompleted)
        _query.listScheduleCards(includeCompleted: true)
      else
        Future.value(<MemoryCardViewData>[]),
    ]);

    final activeCards = results[0] as List<MemoryCardViewData>;
    overview = results[1] as Map<String, int>;

    if (showCompleted) {
      final allCards = results[2] as List<MemoryCardViewData>;
      completedCards = allCards
          .where((c) => c.status == 'completed' || c.status == 'cancelled')
          .toList();
    } else {
      completedCards = const [];
    }

    sections = _groupByBucket(activeCards);
    notifyListeners();
  }

  void setShowCompleted(bool value) {
    if (showCompleted == value) return;
    showCompleted = value;
    load.execute();
  }

  // ---------------------------------------------------------------------------
  // Grouping logic
  // ---------------------------------------------------------------------------

  List<ScheduleSection> _groupByBucket(List<MemoryCardViewData> cards) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final tomorrowEnd = todayStart.add(const Duration(days: 2));
    final weekEnd = todayStart.add(const Duration(days: 7));

    final buckets = <ScheduleBucket, List<MemoryCardViewData>>{
      ScheduleBucket.overdue: [],
      ScheduleBucket.today: [],
      ScheduleBucket.tomorrow: [],
      ScheduleBucket.thisWeek: [],
      ScheduleBucket.later: [],
      ScheduleBucket.unscheduled: [],
    };

    for (final card in cards) {
      final ms = card.eventTimeMs;
      if (ms == null) {
        buckets[ScheduleBucket.unscheduled]!.add(card);
        continue;
      }
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      if (dt.isBefore(todayStart)) {
        buckets[ScheduleBucket.overdue]!.add(card);
      } else if (dt.isBefore(todayEnd)) {
        buckets[ScheduleBucket.today]!.add(card);
      } else if (dt.isBefore(tomorrowEnd)) {
        buckets[ScheduleBucket.tomorrow]!.add(card);
      } else if (dt.isBefore(weekEnd)) {
        buckets[ScheduleBucket.thisWeek]!.add(card);
      } else {
        buckets[ScheduleBucket.later]!.add(card);
      }
    }

    const labels = {
      ScheduleBucket.overdue: '已过期',
      ScheduleBucket.today: '今天',
      ScheduleBucket.tomorrow: '明天',
      ScheduleBucket.thisWeek: '本周',
      ScheduleBucket.later: '之后',
      ScheduleBucket.unscheduled: '未安排时间',
    };

    return [
      for (final entry in buckets.entries)
        if (entry.value.isNotEmpty)
          ScheduleSection(
            bucket: entry.key,
            label: labels[entry.key] ?? '',
            cards: entry.value,
          ),
    ];
  }

  @override
  void dispose() {
    load.dispose();
    toggleComplete.dispose();
    super.dispose();
  }
}
