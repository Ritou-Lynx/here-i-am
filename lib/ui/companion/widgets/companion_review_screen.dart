import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
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
      return const Center(child: AgentLogoLoading());
    }
    if (_error != null && _cards.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCards,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_cards.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCards,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Center(
                child: Text(
                  UserStorage.l10n.nothingHere,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCards,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        itemCount: _cards.length,
        itemBuilder: (context, index) {
          final card = _cards[index];
          final displayTime = _formatDisplayTime(card.updatedAt);
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 9),
                  child: Text(
                    displayTime,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                MemorySummaryCardV3(
                  card: card,
                  onTap: () => _openDetail(card),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Format ms-since-epoch timestamp to a user-facing date/time string.
  String _formatDisplayTime(int msSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cardDate = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(cardDate).inDays;

    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute';

    if (diff == 0) return '今天 $time';
    if (diff == 1) return '昨天 $time';
    if (diff < 7) return '$diff天前 $time';
    return '${dt.month}/${dt.day} $time';
  }
}
