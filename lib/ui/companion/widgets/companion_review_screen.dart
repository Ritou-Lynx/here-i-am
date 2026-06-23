import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_card_constants.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/core/cards/native_card_factory.dart';
import 'package:memex/ui/core/widgets/html_webview_card.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

import 'memory_summary_card.dart';
import 'shared_life_entity_detail_screen.dart';

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
  List<SharedLifeEntitySnapshot> _sharedLifeEntities = const [];

  SharedLifeMemoryService? get _sharedLifeMemory =>
      SharedLifeMemoryService.isInitialized
          ? SharedLifeMemoryService.instance
          : null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearBottom);
    EventBusService.instance.addHandler(
      EventBusMessageType.conversationCaptureRemembered,
      _onConversationRemembered,
    );
    unawaited(_loadSharedLifeEntities());
  }

  @override
  void dispose() {
    EventBusService.instance.removeHandler(
      EventBusMessageType.conversationCaptureRemembered,
      _onConversationRemembered,
    );
    _scrollController.removeListener(_loadMoreNearBottom);
    _scrollController.dispose();
    super.dispose();
  }

  void _onConversationRemembered(EventBusMessage _) {
    unawaited(_loadSharedLifeEntities());
  }

  Future<void> _loadSharedLifeEntities() async {
    final service = _sharedLifeMemory;
    if (service == null) return;
    final entities = await service.listEntities(limit: 80);
    if (!mounted) return;
    setState(() => _sharedLifeEntities = entities);
  }

  /// Converts a shared-life entity into a standard [TimelineCardModel] so it
  /// renders through the same [NativeCardFactory] pipeline as every other card.
  static TimelineCardModel _entityToCard(SharedLifeEntitySnapshot entity) {
    final summary = entity.state['summary'] as String? ?? '';
    final content = entity.state['content'] as String? ?? '';
    final text = [summary, content]
        .where((s) => s.isNotEmpty)
        .join('\n\n');

    return TimelineCardModel(
      id: 'entity:${entity.id}',
      title: entity.title,
      timestamp: DateTime.fromMicrosecondsSinceEpoch(entity.updatedAt),
      tags: entity.tags,
      // "active" means the entity is a valid record.
      status: entity.status == 'active' ? 'completed' : entity.status,
      uiConfigs: [
        UiConfig(
          templateId: _entityTemplateId(entity.entityType),
          data: {
            if (text.isNotEmpty) 'content': text,
            if (entity.state['time'] != null) 'time': entity.state['time'],
            if (entity.state['place'] != null) 'place': entity.state['place'],
          },
        ),
      ],
      html: null,
    );
  }

  static String _entityTemplateId(String entityType) {
    return switch (entityType) {
      'event' => 'event',
      'task' => 'task',
      'plan' => 'event',
      'schedule' => 'event',
      _ => 'compact',
    };
  }

  Future<void> _refresh(TimelineViewModel vm) async {
    await Future.wait([
      vm.refresh(),
      _loadSharedLifeEntities(),
    ]);
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
          backgroundColor: Colors.transparent,
          body: _buildBody(vm),
        );
      },
    );
  }

  Widget _buildBody(TimelineViewModel vm) {
    final cards = companionReviewCards(vm.cards);
    final items = companionReviewFeedItems(cards, _sharedLifeEntities);
    if ((vm.isLoading || vm.load.running) && items.isEmpty) {
      return const Center(child: AgentLogoLoading());
    }
    if (vm.errorMessage != null && items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refresh(vm),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Center(
                child: Text(
                  vm.errorMessage!,
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refresh(vm),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Center(
                child: Text(
                  UserStorage.l10n.nothingHere,
                  style: TextStyle(
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
    final entityById = {
      for (final e in _sharedLifeEntities) e.id: e,
    };
    return RefreshIndicator(
      onRefresh: () => _refresh(vm),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        itemCount: items.length + (vm.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final card = items[index];
          final isEntity = card.id.startsWith('entity:');
          final entityId =
              isEntity ? card.id.substring('entity:'.length) : null;
          final entity = entityId != null ? entityById[entityId] : null;

          Future<void> openDetail() async {
            if (isEntity && entityId != null) {
              final service = _sharedLifeMemory;
              if (service == null) return;
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SharedLifeEntityDetailScreen(
                    entityId: entityId,
                    service: service,
                  ),
                ),
              );
              await _loadSharedLifeEntities();
              return;
            }
            final changed = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TimelineCardDetailScreen(cardId: card.id),
              ),
            );
            if (changed == true) await _refresh(vm);
          }

          if (entity != null) {
            return _EntityReviewItem(
              entity: entity,
              displayTime: card.displayTime(UserStorage.l10n),
              onTap: openDetail,
            );
          }
          return CompanionReviewCard(card: card, onTap: openDetail);
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
              style: TextStyle(
                color: AppColors.textTertiary,
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

class _EntityReviewItem extends StatelessWidget {
  const _EntityReviewItem({
    required this.entity,
    required this.displayTime,
    required this.onTap,
  });

  final SharedLifeEntitySnapshot entity;
  final String displayTime;
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
              displayTime,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          MemorySummaryCard(entity: entity, onTap: onTap),
        ],
      ),
    );
  }
}

@visibleForTesting
List<TimelineCardModel> companionReviewCards(List<TimelineCardModel> cards) {
  return cards
      .where((card) => card.id != scheduleBriefingCardId)
      .toList(growable: false);
}

@visibleForTesting
List<TimelineCardModel> companionReviewFeedItems(
  List<TimelineCardModel> cards,
  List<SharedLifeEntitySnapshot> sharedLifeEntities,
) {
  final allCards = [
    ...cards,
    ...sharedLifeEntities.map(_CompanionReviewScreenState._entityToCard),
  ];
  allCards.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return allCards;
}
