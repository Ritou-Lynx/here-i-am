/// Memory V3 Lab - memory_cards browser page.
///
/// Lists recently written memory_cards (from real record entry points),
/// tap to open detail, long-press to delete, trailing button to preview.
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/memory_card_detail_screen_v3.dart';
import 'package:memex/ui/memory/widgets/memory_summary_card_v3.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('LabCardsPage');

class LabCardsPage extends StatefulWidget {
  const LabCardsPage({super.key});

  @override
  State<LabCardsPage> createState() => _LabCardsPageState();
}

class _LabCardsPageState extends State<LabCardsPage> {
  List<MemoryCard> _recent = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!RecordOrganizerServiceV3.isInitialized) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _recent = const [];
      });
      return;
    }
    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryCards)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)])
          ..limit(50))
        .get();
    if (!mounted) return;
    setState(() {
      _recent = rows;
      _loading = false;
    });
  }

  Future<void> _deleteCard(MemoryCard card) async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '删除这张卡？',
      content: card.dropletLabel,
      confirmLabel: '删除',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await RecordOrganizerServiceV3.instance.deleteCard(card.id);
      await _load();
    } catch (e, st) {
      _logger.warning('deleteCard failed', e, st);
    }
  }

  void _showDetail(MemoryCard card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryCardDetailScreenV3(
          cardId: card.id,
          queryService: MemoryCardQueryService(AppDatabase.instance),
        ),
      ),
    );
  }

  void _preview(MemoryCard card) {
    final t = context.springRainUi;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Text('卡片预览'),
            const Spacer(),
            Text(
              card.dropletLabel,
              style: TextStyle(fontSize: 13, color: t.textTertiary),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: MemorySummaryCardV3(card: _toViewData(card)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  MemoryCardViewData _toViewData(MemoryCard card) {
    return MemoryCardViewData(
      id: card.id,
      type: card.type,
      title: card.title,
      dropletLabel: card.dropletLabel,
      presentationModule: card.presentationModule,
      retrievalText: card.retrievalText,
      valence: card.valence,
      arousal: card.arousal,
      status: card.status,
      needsFollowUp: MemoryCardViewData.parseNeedsFollowUp(card.needsFollowUp),
      createdAt: card.createdAt,
      updatedAt: card.updatedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆卡片'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          LabBusyLine(visible: _loading),
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.space16,
              t.space12,
              t.space16,
              t.space8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '最近 ${_recent.length} 张 · 来自真实记录入口',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _recent.isEmpty && !_loading
                  ? ListView(
                      children: const [LabEmptyState(message: '（暂无 memory_cards）')],
                    )
                  : ListView.separated(
                      itemCount: _recent.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: t.space16, color: t.divider),
                      itemBuilder: (ctx, i) => _CardTile(
                        card: _recent[i],
                        onTap: () => _showDetail(_recent[i]),
                        onLongPress: () => _deleteCard(_recent[i]),
                        onPreview: () => _preview(_recent[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.onTap,
    required this.onLongPress,
    required this.onPreview,
  });

  final MemoryCard card;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final mood = _moodColor(card.valence, card.arousal);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.space16,
          vertical: t.space12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: EdgeInsets.only(top: 6, right: t.space12),
              decoration: BoxDecoration(color: mood, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.dropletLabel,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(left: t.space4),
                        padding: EdgeInsets.symmetric(
                          horizontal: t.space8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: t.surfaceMuted,
                          borderRadius: BorderRadius.circular(t.radius6),
                        ),
                        child: Text(
                          card.dropletLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: t.space4),
                  Text(
                    card.retrievalText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
                  SizedBox(height: t.space4),
                  Text(
                    '${card.type} · v ${card.valence.toStringAsFixed(2)} '
                    '· a ${card.arousal.toStringAsFixed(2)} · '
                    '${DateTime.fromMillisecondsSinceEpoch(card.updatedAt)}',
                    style: TextStyle(fontSize: 10, color: t.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 18),
              tooltip: '预览卡片',
              onPressed: onPreview,
            ),
          ],
        ),
      ),
    );
  }

  Color _moodColor(double valence, double arousal) {
    const t = SpringRainUiTokens.daylight;
    if (arousal < 0.3) return t.iconMuted;
    if (valence > 0.3) return t.gold;
    if (valence < -0.3) return t.info;
    return t.goldSoft;
  }
}
