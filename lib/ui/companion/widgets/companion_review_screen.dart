import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/system_card_constants.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/core/cards/native_card_factory.dart';
import 'package:memex/ui/core/widgets/html_webview_card.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';

/// Clean chronological review feed for the companion-first app.
///
/// The legacy timeline header, agent shortcuts, avatars, insight tabs, and tag
/// filters intentionally stay out of this surface.
class CompanionReviewScreen extends StatefulWidget {
  const CompanionReviewScreen({
    super.key,
    required this.viewModel,
  });

  final TimelineViewModel viewModel;

  @override
  State<CompanionReviewScreen> createState() => _CompanionReviewScreenState();
}

class _CompanionReviewScreenState extends State<CompanionReviewScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearBottom);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_loadMoreNearBottom);
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreNearBottom() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      widget.viewModel.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.viewModel,
        widget.viewModel.load,
      ]),
      builder: (context, _) {
        final vm = widget.viewModel;
        return Scaffold(
          backgroundColor: const Color(0xFFF6F5F2),
          body: SafeArea(
            child: Column(
              children: [
                _ReviewHeader(
                  onBack: () => Navigator.pop(context),
                  onRefresh: vm.refresh,
                ),
                Expanded(child: _buildBody(vm)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(TimelineViewModel vm) {
    final cards = companionReviewCards(vm.cards);
    if ((vm.isLoading || vm.load.running) && vm.cards.isEmpty) {
      return const Center(child: AgentLogoLoading());
    }
    if (vm.errorMessage != null) {
      return RefreshIndicator(
        onRefresh: vm.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Center(
                child: Text(
                  vm.errorMessage!,
                  style: const TextStyle(color: Color(0xFF7C8490)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (cards.isEmpty) {
      return RefreshIndicator(
        onRefresh: vm.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Center(
                child: Text(
                  UserStorage.l10n.nothingHere,
                  style: const TextStyle(
                    color: Color(0xFF7C8490),
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
      onRefresh: vm.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        itemCount: cards.length + (vm.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= cards.length) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final card = cards[index];
          return CompanionReviewCard(
            card: card,
            onTap: () async {
              final changed = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TimelineCardDetailScreen(cardId: card.id),
                ),
              );
              if (changed == true) await vm.refresh();
            },
          );
        },
      ),
    );
  }
}

@visibleForTesting
class CompanionReviewCard extends StatelessWidget {
  const CompanionReviewCard({
    super.key,
    required this.card,
    required this.onTap,
  });

  final TimelineCardModel card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 9),
            child: Text(
              card.displayTime(UserStorage.l10n),
              style: const TextStyle(
                color: Color(0xFF8B9098),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: _buildCardContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent() {
    if (card.html != null && card.html!.isNotEmpty) {
      return HtmlWebViewCard(
        html: card.html!,
        config: const HtmlWebViewConfig.timeline(),
        onContentTap: onTap,
      );
    }
    if (card.uiConfigs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: card.uiConfigs.asMap().entries.map((entry) {
        final config = entry.value;
        if (config.templateId == 'legacy_html') {
          final html = config.data['html'] as String?;
          if (html == null || html.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: EdgeInsets.only(
              bottom: entry.key == card.uiConfigs.length - 1 ? 0 : 8,
            ),
            child: HtmlWebViewCard(
              html: html,
              config: const HtmlWebViewConfig.timeline(),
              onContentTap: onTap,
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.only(
            bottom: entry.key == card.uiConfigs.length - 1 ? 0 : 8,
          ),
          child: NativeCardFactory.build(
            status: card.status,
            templateId: config.templateId,
            data: config.data,
            title: card.title ?? '',
            tags: card.tags,
            onTap: onTap,
            cardId: card.id,
            configIndex: entry.key,
            overrideTitle: entry.key == 0,
            failureReason: card.failureReason,
            onUpdate: (cardId, configIndex, data) {
              MemexRouter().updateCardUiConfig(cardId, configIndex, data);
            },
          ),
        );
      }).toList(),
    );
  }
}

@visibleForTesting
List<TimelineCardModel> companionReviewCards(List<TimelineCardModel> cards) {
  return cards
      .where((card) => card.id != scheduleBriefingCardId)
      .toList(growable: false);
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.onBack,
    required this.onRefresh,
  });

  final VoidCallback onBack;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              UserStorage.l10n.bottomNavTimeline,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}
