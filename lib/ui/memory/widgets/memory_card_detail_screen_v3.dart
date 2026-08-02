/// Full detail view for a single V3 Memory Card.
///
/// Displays: type + status, content blocks, source evidence, entity links,
/// related cards, operation history, and emotion coordinates.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/presentation_module.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

import 'package:memex/data/services/current_context_service.dart';

import 'memory_summary_card_v3.dart';

class MemoryCardDetailScreenV3 extends StatefulWidget {
  const MemoryCardDetailScreenV3({
    super.key,
    required this.cardId,
    this.queryService,
    this.organizerService,
  });

  final String cardId;
  final MemoryCardQueryService? queryService;
  final RecordOrganizerServiceV3? organizerService;

  @override
  State<MemoryCardDetailScreenV3> createState() =>
      _MemoryCardDetailScreenV3State();
}

class _MemoryCardDetailScreenV3State extends State<MemoryCardDetailScreenV3> {
  MemoryCardDetail? _detail;
  bool _loading = true;
  String? _error;

  // Collapse state
  bool _sourceExpanded = true;
  bool _operationsExpanded = false;
  bool _emotionExpanded = false;
  bool _imageDescExpanded = false;

  MemoryCardQueryService get _query =>
      widget.queryService ??
      (throw StateError(
          'MemoryCardQueryService not provided to MemoryCardDetailScreenV3'));

  RecordOrganizerServiceV3? get _organizer =>
      widget.organizerService ??
      (RecordOrganizerServiceV3.isInitialized
          ? RecordOrganizerServiceV3.instance
          : null);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    CurrentContextService.pop(widget.cardId);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await _query.getCardDetail(widget.cardId);
      if (mounted) {
        CurrentContextService.push(CurrentPageContext(
          type: CurrentContextType.memoryCard,
          id: widget.cardId,
          title: detail.card.title,
        ));
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _deleteCard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记忆卡'),
        content: const Text('删除后不可恢复。确定删除这条记忆？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || _organizer == null) return;

    await _organizer!.deleteCard(widget.cardId);
    if (mounted) Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Extract the `[图片内容：...]` suffix from [retrievalText], or null.
  static String? _extractImageAnalysis(String text) {
    final match = RegExp(r'\n\[图片内容：(.+)\]$').firstMatch(text.trim());
    return match?.group(1);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SpringRainUiScope(child: Builder(builder: _buildPage));
  }

  Widget _buildPage(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('加载中…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错误')),
        body: Center(child: Text(_error!)),
      );
    }

    final detail = _detail!;
    final card = detail.card;
    final presentation = PresentationModule.tryParse(card.presentationModule);

    return Scaffold(
        appBar: AppBar(
          title: Text(card.dropletLabel),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _deleteCard,
            ),
          ],
        ),
        body: Builder(builder: (context) {
          final imageAnalysis = _extractImageAnalysis(card.retrievalText);
          final cleanFallback = imageAnalysis != null
              ? card.retrievalText.replaceFirst(imageAnalysis, '').trim()
              : card.retrievalText;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Type + status
                _TypeStatusRow(card: card),
                const SizedBox(height: 20),

                // 2. Content blocks
                V3CardBlocks(
                  presentation: presentation,
                  dropletLabel: card.dropletLabel,
                  fallbackText: cleanFallback,
                ),
                if (imageAnalysis != null) ...[
                  const SizedBox(height: 16),
                  _CollapsibleSection(
                    title: '图片描述',
                    expanded: _imageDescExpanded,
                    onToggle: () => setState(
                        () => _imageDescExpanded = !_imageDescExpanded),
                    child: _ImageDescription(text: imageAnalysis),
                  ),
                ],
                const SizedBox(height: 24),

                // 3. Source evidence
                if (detail.source != null) ...[
                  _CollapsibleSection(
                    title: '来源证据',
                    expanded: _sourceExpanded,
                    onToggle: () =>
                        setState(() => _sourceExpanded = !_sourceExpanded),
                    child: _SourceEvidence(
                      source: detail.source!,
                      assets: detail.assets,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. Entity links
                if (detail.entityLinks.isNotEmpty) ...[
                  _SectionLabel('关联人物/事物'),
                  const SizedBox(height: 8),
                  _EntityLinks(links: detail.entityLinks),
                  const SizedBox(height: 16),
                ],

                // 5. Related cards
                if (detail.relations.isNotEmpty) ...[
                  _SectionLabel('关联卡片'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: detail.relations.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (ctx, i) => SizedBox(
                        width: 240,
                        child: MemorySummaryCardV3(card: detail.relations[i]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 6. Operation history
                if (detail.operations.isNotEmpty) ...[
                  _CollapsibleSection(
                    title: '操作历史',
                    expanded: _operationsExpanded,
                    onToggle: () => setState(
                        () => _operationsExpanded = !_operationsExpanded),
                    child: _OperationHistory(operations: detail.operations),
                  ),
                  const SizedBox(height: 16),
                ],

                // 7. Emotion coordinates
                _CollapsibleSection(
                  title: '情绪坐标',
                  expanded: _emotionExpanded,
                  onToggle: () =>
                      setState(() => _emotionExpanded = !_emotionExpanded),
                  child: _EmotionCoords(
                      valence: card.valence, arousal: card.arousal),
                ),
              ],
            ),
          );
        }));
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _TypeStatusRow extends StatelessWidget {
  const _TypeStatusRow({required this.card});
  final MemoryCardViewData card;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: tokens.accentSoft.withValues(alpha: 0.30),
          ),
          child: Text(
            card.typeLabel,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (card.isTaskLike && card.hasStatus && card.status != 'active') ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: card.status == 'completed'
                  ? const Color(0xFF6FA87A).withValues(alpha: 0.20)
                  : const Color(0xFF7A6664).withValues(alpha: 0.16),
            ),
            child: Text(
              card.statusLabel!,
              style: TextStyle(
                color: card.status == 'completed'
                    ? const Color(0xFF4A7A54)
                    : const Color(0xFF7A6664),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Text(
      text,
      style: TextStyle(
        color: tokens.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: tokens.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) child,
      ],
    );
  }
}

// ---- Source evidence ----

class _SourceEvidence extends StatelessWidget {
  const _SourceEvidence({required this.source, this.assets = const []});
  final MemoryCardSourceData source;
  final List<CardAssetData> assets;

  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    final imageAssets = assets.where((a) => a.isImage).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: tokens.surfaceMuted.withValues(alpha: 0.72),
        border: Border.all(color: tokens.textTertiary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // rawInput
          if (source.rawInput.isNotEmpty) ...[
            Text(
              source.rawInput,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Source images — full-width, one per row, 16:10 aspect
          if (imageAssets.isNotEmpty) ...[
            for (final asset in imageAssets) ...[
              _buildSourceImage(asset.storagePath),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 2),
          ],
          // recordedAt
          Row(
            children: [
              Icon(Icons.access_time, size: 13, color: tokens.textTertiary),
              const SizedBox(width: 6),
              Text(
                '记录于 ${_fmtTime(source.recordedAt)}',
                style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          // recordedPlace
          if (source.recordedPlace != null &&
              source.recordedPlace!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 13, color: tokens.textTertiary),
                const SizedBox(width: 6),
                Text(
                  source.recordedPlace!,
                  style: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceImage(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty) {
      return const SizedBox.shrink();
    }
    try {
      final absPath = FileSystemService.instance.toAbsolutePath(storagePath);
      final file = File(absPath);
      if (!file.existsSync()) return const SizedBox.shrink();

      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Image.memory(
            file.readAsBytesSync(),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

// ---- Entity links ----

class _EntityLinks extends StatelessWidget {
  const _EntityLinks({required this.links});
  final List<EntityLinkData> links;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final link in links)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: tokens.accentSoft.withValues(alpha: 0.18),
              border: Border.all(
                color: tokens.accentSoft.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              '${link.entityName} · ${_relationLabel(link.relation)}',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  String _relationLabel(String rel) {
    switch (rel) {
      case 'mentioned':
        return '提及';
      case 'about':
        return '关于';
      case 'with':
        return '一起';
      case 'caused_by':
        return '起因';
      case 'located_at':
        return '位于';
      default:
        return rel;
    }
  }
}

// ---- Operation history ----

class _OperationHistory extends StatelessWidget {
  const _OperationHistory({required this.operations});
  final List<OperationData> operations;

  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }

  String _opLabel(String op) {
    switch (op) {
      case 'create':
        return '创建';
      case 'update':
        return '更新';
      case 'delete':
        return '删除';
      case 'restore':
        return '恢复';
      case 'correct':
        return '修正';
      case 'merge':
        return '合并';
      case 'split':
        return '拆分';
      case 'derive':
        return '派生';
      default:
        return op;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final op in operations)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    _opLabel(op.operationType),
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _fmtTime(op.createdAt),
                    style: TextStyle(
                      color: tokens.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- Emotion coordinates ----

class _EmotionCoords extends StatelessWidget {
  const _EmotionCoords({
    required this.valence,
    required this.arousal,
  });

  final double valence;
  final double arousal;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: tokens.surfaceMuted.withValues(alpha: 0.72),
        border: Border.all(color: tokens.textTertiary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoordRow(
            label: '愉悦度',
            value: valence,
            valueText: valence.toStringAsFixed(2),
            barColor: valence >= 0
                ? const Color(0xFFE89A8E)
                : const Color(0xFF6F7A8A),
          ),
          const SizedBox(height: 10),
          _CoordRow(
            label: '唤醒度',
            value: arousal,
            valueText: arousal.toStringAsFixed(2),
            barColor: const Color(0xFFB57A2E),
          ),
        ],
      ),
    );
  }
}

class _CoordRow extends StatelessWidget {
  const _CoordRow({
    required this.label,
    required this.value,
    required this.valueText,
    required this.barColor,
  });

  final String label;
  final double value;
  final String valueText;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    // valence clamped [-1,1], arousal [0,1]
    final fraction = value.clamp(-1.0, 1.0);
    // Map [-1,1] or [0,1] to [0,1] for visual bar
    final barFraction = ((fraction + 1.0) / 2.0).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(
                    color: barColor.withValues(alpha: 0.15),
                  ),
                  FractionallySizedBox(
                    widthFactor: barFraction,
                    child: Container(color: barColor),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Image description ----

class _ImageDescription extends StatelessWidget {
  const _ImageDescription({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: tokens.surfaceMuted.withValues(alpha: 0.72),
        border: Border.all(color: tokens.textTertiary.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 13.5,
          height: 1.6,
        ),
      ),
    );
  }
}
