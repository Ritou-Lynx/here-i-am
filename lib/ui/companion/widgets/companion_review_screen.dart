import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/memory/widgets/memory_card_detail_screen_v3.dart';
import 'package:memex/ui/memory/widgets/memory_summary_card_v3.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Memory Review feed — chronological list of V3 [MemoryCardViewData] cards.
///
/// This is a transitional surface. It currently reads directly from the V3
/// [memory_cards] table and renders via [MemorySummaryCardV3]. When the Hall /
/// observation panel is built, the list logic will move there; this widget
/// will become a thin wrapper or be replaced.
///
/// The legacy [TimelineViewModel] parameter is accepted for caller
/// compatibility but is no longer used internally.
class CompanionReviewScreen extends StatefulWidget {
  const CompanionReviewScreen({super.key, this.viewModel});

  /// No longer used — kept for caller compatibility during transition.
  final dynamic viewModel;

  @override
  State<CompanionReviewScreen> createState() => _CompanionReviewScreenState();
}

class _CompanionReviewScreenState extends State<CompanionReviewScreen> {
  static const _accent = Color(0xFF737B46);
  static const _ink = Color(0xFF293025);
  static const _inkSoft = Color(0xFF667061);
  static const _stateSurface = Color(0xE8F7F5EE);

  final _logger = getLogger('CompanionReviewScreen');
  final _scrollController = ScrollController();

  List<MemoryCardViewData> _cards = const [];
  bool _loading = true;
  String? _error;

  MemoryCardQueryService get _query =>
      MemoryCardQueryService(AppDatabase.instance);

  RecordOrganizerServiceV3? get _organizer =>
      RecordOrganizerServiceV3.isInitialized
          ? RecordOrganizerServiceV3.instance
          : null;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final cards = await _query.listRecentCards(limit: 100);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (e, s) {
      _logger.warning('Failed to load V3 cards', e, s);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openDetail(MemoryCardViewData card) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryCardDetailScreenV3(
          cardId: card.id,
          queryService: _query,
          organizerService: _organizer,
        ),
      ),
    );
    // Refresh list on return — card may have been edited.
    await _loadCards();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _cards.isEmpty) {
      return const Center(
        child: _ReviewStateSurface(
          key: ValueKey('memory_review_loading'),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: _accent,
              strokeWidth: 2.2,
            ),
          ),
        ),
      );
    }
    if (_error != null && _cards.isEmpty) {
      return _ReviewStateList(
        key: const ValueKey('memory_review_error'),
        onRefresh: _loadCards,
        child: _ReviewStateSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh_rounded, color: _inkSoft, size: 26),
              const SizedBox(height: 10),
              const Text(
                '暂时没有读到记忆',
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadCards,
                style: TextButton.styleFrom(foregroundColor: _accent),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_cards.isEmpty) {
      return _ReviewStateList(
        key: const ValueKey('memory_review_empty'),
        onRefresh: _loadCards,
        child: _ReviewStateSurface(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.water_drop_outlined,
                color: _accent,
                size: 20,
              ),
              const SizedBox(width: 9),
              Text(
                UserStorage.l10n.nothingHere,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      backgroundColor: const Color(0xFFF7F5EE),
      onRefresh: _loadCards,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        itemCount: _cards.length,
        itemBuilder: (context, index) {
          final card = _cards[index];
          // Anchor the list timestamp on the card's EVENT time (from
          // structuredFields), not updatedAt. A 7/15 lunch edited on 7/16
          // should still show as 7/15 noon in the list — only the detail
          // page's "修改时间" should reflect the edit.
          final eventMs = card.eventTimeMs ?? card.createdAt;
          final displayTime = formatMemoryReviewTimestamp(eventMs);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: MemorySummaryCardV3(
              key: ValueKey('memory_review_card_${card.id}'),
              card: card,
              variant: MemorySummaryCardVariant.springRainReview,
              metaLabel: displayTime,
              categoryLabel: card.typeLabel,
              pressFeedback: true,
              onTap: () => _openDetail(card),
            ),
          );
        },
      ),
    );
  }
}

/// Stable, absolute date label for Memory Review.
///
/// Card content is explicitly anchored to absolute dates by the Record
/// Organizer; the list follows the same rule instead of switching between
/// “今天”, “3天前” and “7/30”. The year is omitted only for the current year.
String formatMemoryReviewTimestamp(
  int msSinceEpoch, {
  DateTime? now,
}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch);
  final current = now ?? DateTime.now();
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final date = dt.year == current.year
      ? '${dt.month}月${dt.day}日'
      : '${dt.year}年${dt.month}月${dt.day}日';
  return '$date $hour:$minute';
}

class _ReviewStateList extends StatelessWidget {
  const _ReviewStateList({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _CompanionReviewScreenState._accent,
      backgroundColor: const Color(0xFFF7F5EE),
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.60,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

class _ReviewStateSurface extends StatelessWidget {
  const _ReviewStateSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: _CompanionReviewScreenState._stateSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xB8FFFFFF), width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24161C15),
            blurRadius: 24,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: child,
    );
  }
}
