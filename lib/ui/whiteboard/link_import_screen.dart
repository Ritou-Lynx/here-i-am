/// Link import screen — W3 production body.
///
/// Route: `/import` (registered by the W6 integration base; router.dart /
/// routes.dart are NOT touched — this file only replaces the placeholder
/// body).
///
/// Flow: paste URL → safe fetch via [LinkIngestionService] (SSRF-protected,
/// DNS-pinned transport) → the `IngestionResult` is presented honestly in
/// one of four states (ok / failed / needsAuth / unsupported) → the user
/// **explicitly** taps "存入卡片库" to create the Card — the fetch itself
/// never writes a Card.
///
/// Restart recovery: recent imports are re-read from the file-backed
/// `IngestionStore` on every open; re-importing an already-known URL is
/// idempotent (no duplicate Card, no silent copy).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'package:memex/data/whiteboard/ingestion/ingestion_store.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Entry point for ordinary link ingestion.
///
/// [service] / [storeDirResolver] are injectable for tests; production uses
/// the default file-backed store under the app support directory.
class LinkImportScreen extends StatefulWidget {
  final LinkIngestionService? service;
  final Future<Directory> Function()? storeDirResolver;

  const LinkImportScreen({super.key, this.service, this.storeDirResolver});

  @override
  State<LinkImportScreen> createState() => _LinkImportScreenState();
}

class _RecentImport {
  final CardContract card;
  final String canonicalUrl;
  final String? provider;
  final int versionCount;
  final DateTime createdAt;

  const _RecentImport({
    required this.card,
    required this.canonicalUrl,
    this.provider,
    required this.versionCount,
    required this.createdAt,
  });
}

class _LinkImportScreenState extends State<LinkImportScreen> {
  final TextEditingController _urlController = TextEditingController();

  LinkIngestionService? _service;
  String? _storeError;
  bool _fetching = false;
  bool _cardBusy = false;
  String? _inputError;

  LinkIngestionOutcome? _outcome;
  CardContract? _existingCard;
  bool _cardSaved = false;

  List<_RecentImport> _recent = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final LinkIngestionService service;
    try {
      service = widget.service ?? await _createService();
    } catch (e) {
      if (!mounted) return;
      setState(() => _storeError = '存储不可用：$e');
      return;
    }
    if (!mounted) return;
    setState(() => _service = service);
    await _loadRecent();
  }

  Future<LinkIngestionService> _createService() async {
    final Directory dir;
    if (widget.storeDirResolver != null) {
      dir = await widget.storeDirResolver!();
    } else {
      final support = await getApplicationSupportDirectory();
      dir = Directory('${support.path}/whiteboard/ingestion');
    }
    return LinkIngestionService(store: IngestionStore(dir));
  }

  Future<void> _loadRecent() async {
    final service = _service;
    if (service == null) return;
    final cards = await service.listCards();
    final recent = <_RecentImport>[];
    for (final card in cards) {
      final record = card.sourceId != null
          ? await service.getSource(card.sourceId!)
          : null;
      recent.add(_RecentImport(
        card: card,
        canonicalUrl:
            record?.source.metadata['canonical_url'] as String? ?? '',
        provider: record?.source.provider,
        versionCount: record?.versions.length ?? 1,
        createdAt: card.createdAt,
      ));
    }
    recent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  // -----------------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------------

  Future<void> _fetch() async {
    final service = _service;
    if (service == null || _fetching) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _inputError = '请输入要导入的链接');
      return;
    }
    setState(() {
      _fetching = true;
      _inputError = null;
      _outcome = null;
      _existingCard = null;
      _cardSaved = false;
    });
    try {
      // Fetch only — the Card is created explicitly by the user later.
      final outcome = await service.ingestUrl(url, createCard: false);
      CardContract? existing;
      final sourceId = outcome.result.source?.sourceId;
      if (sourceId != null) {
        final record = await service.getSource(sourceId);
        existing = record?.card;
      }
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _existingCard = existing;
        _fetching = false;
      });
      await _loadRecent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _inputError = '抓取失败：$e';
      });
    }
  }

  Future<void> _saveCard() async {
    final service = _service;
    final outcome = _outcome;
    if (service == null || outcome == null || _cardBusy) return;
    setState(() => _cardBusy = true);
    try {
      final finalOutcome = await service.ingestUrl(
        outcome.result.canonicalUrl,
        createCard: true,
      );
      if (!mounted) return;
      setState(() {
        _outcome = finalOutcome;
        _existingCard = null;
        _cardSaved = true;
        _cardBusy = false;
      });
      await _loadRecent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cardBusy = false;
        _inputError = '存入卡片库失败：$e';
      });
    }
  }

  void _openCardLibrary() {
    context.go(AppRoutes.cardLibrary);
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          tooltip: '返回首页',
          onPressed: () => context.go('/'),
        ),
        title: const Text('导入链接'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          if (_storeError != null) _buildStoreError(),
          _buildInputRow(),
          if (_inputError != null) _buildInputError(),
          if (_fetching) _buildFetching(),
          if (_outcome != null) _buildOutcome(_outcome!),
          const SizedBox(height: 24),
          _buildRecent(),
        ],
      ),
    );
  }

  Widget _buildStoreError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WhiteboardCanvasTokens.orphanedSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WhiteboardCanvasTokens.orphanedBorder),
      ),
      child: Text(
        _storeError!,
        style: const TextStyle(
          color: WhiteboardCanvasTokens.orphanedBorder,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildInputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlController,
            enabled: _service != null && !_fetching,
            onSubmitted: (_) => _fetch(),
            style: const TextStyle(
              color: WhiteboardCanvasTokens.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: '粘贴链接，例如 https://example.com/article',
              hintStyle: const TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 13,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: WhiteboardCanvasTokens.divider,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: WhiteboardCanvasTokens.divider,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: (_service == null || _fetching) ? null : _fetch,
          style: FilledButton.styleFrom(
            backgroundColor: WhiteboardCanvasTokens.action,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: const Text('抓取'),
        ),
      ],
    );
  }

  Widget _buildInputError() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        _inputError!,
        style: const TextStyle(
          color: WhiteboardCanvasTokens.orphanedBorder,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildFetching() {
    return const Padding(
      padding: EdgeInsets.only(top: 24),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: WhiteboardCanvasTokens.action,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildOutcome(LinkIngestionOutcome outcome) {
    final result = outcome.result;
    switch (result.status) {
      case IngestionStatus.ok:
        return _buildOkOutcome(outcome, result);
      case IngestionStatus.failed:
        return _buildStatusCard(
          icon: Icons.error_outline,
          iconColor: WhiteboardCanvasTokens.orphanedBorder,
          title: '抓取失败',
          message: result.errorMessage ?? '未知错误',
          url: result.canonicalUrl,
        );
      case IngestionStatus.needsAuth:
        return _buildStatusCard(
          icon: Icons.lock_outline,
          iconColor: WhiteboardCanvasTokens.focus,
          title: '需要登录或已被拒绝',
          message: result.errorMessage ?? '站点要求登录',
          url: result.canonicalUrl,
        );
      case IngestionStatus.partial:
        return _buildStatusCard(
          icon: Icons.warning_amber_rounded,
          iconColor: WhiteboardCanvasTokens.focus,
          title: '内容不完整',
          message: result.errorMessage ?? '只拿到部分内容',
          url: result.canonicalUrl,
        );
      case IngestionStatus.unsupported:
        return _buildStatusCard(
          icon: Icons.warning_amber_rounded,
          iconColor: WhiteboardCanvasTokens.focus,
          title: '暂不支持此链接',
          message: result.errorMessage ?? '普通链接抓取不支持该类型',
          url: result.canonicalUrl,
        );
    }
  }

  Widget _buildOkOutcome(
    LinkIngestionOutcome outcome,
    IngestionResult result,
  ) {
    final source = result.source!;
    final title = source.title;
    final description = result.metadata['description'] as String?;
    final excerpt = result.metadata['body_excerpt'] as String?;
    final imageCount = (result.metadata['image_urls'] as List?)?.length ?? 0;
    final savedCard = outcome.card ?? _existingCard;

    final Widget actionArea;
    if (savedCard != null || _cardSaved) {
      final card = savedCard ?? outcome.card;
      final updated = outcome.cardUpdated;
      actionArea = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: WhiteboardCanvasTokens.action,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                updated ? '卡片已更新（内容有新版本）' : '已在卡片库',
                style: const TextStyle(
                  color: WhiteboardCanvasTokens.action,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (card != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                card.cardId,
                style: const TextStyle(
                  color: WhiteboardCanvasTokens.textFaint,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openCardLibrary,
            icon: const Icon(Icons.library_books_outlined, size: 16),
            label: const Text('打开卡片库'),
            style: OutlinedButton.styleFrom(
              foregroundColor: WhiteboardCanvasTokens.action,
              side: const BorderSide(color: WhiteboardCanvasTokens.action),
            ),
          ),
        ],
      );
    } else {
      actionArea = FilledButton.icon(
        onPressed: _cardBusy ? null : _saveCard,
        icon: const Icon(Icons.save_outlined, size: 16),
        label: Text(_cardBusy ? '正在存入…' : '存入卡片库'),
        style: FilledButton.styleFrom(
          backgroundColor: WhiteboardCanvasTokens.action,
          foregroundColor: Colors.white,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WhiteboardCanvasTokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: WhiteboardCanvasTokens.action,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '抓取成功',
                  style: TextStyle(
                    color: WhiteboardCanvasTokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _providerChip(source.provider),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: WhiteboardCanvasTokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result.canonicalUrl,
            style: const TextStyle(
              color: WhiteboardCanvasTokens.textFaint,
              fontSize: 12,
            ),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (excerpt != null && excerpt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              excerpt,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            [
              if (result.hasBody) '正文',
              if (imageCount > 0) '$imageCount 张图片',
              if (source.mimeType != null) source.mimeType!,
            ].join(' · '),
            style: const TextStyle(
              color: WhiteboardCanvasTokens.textFaint,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          actionArea,
        ],
      ),
    );
  }

  Widget _providerChip(String? provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: WhiteboardCanvasTokens.actionSoft.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        provider ?? 'web',
        style: const TextStyle(
          color: WhiteboardCanvasTokens.actionSecondary,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String url,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WhiteboardCanvasTokens.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WhiteboardCanvasTokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    color: WhiteboardCanvasTokens.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  url,
                  style: const TextStyle(
                    color: WhiteboardCanvasTokens.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '最近导入',
          style: TextStyle(
            color: WhiteboardCanvasTokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_recent.isEmpty)
          const Text(
            '还没有导入记录。抓取结果确认后，点击「存入卡片库」才会创建卡片。',
            style: TextStyle(
              color: WhiteboardCanvasTokens.textFaint,
              fontSize: 12,
              height: 1.5,
            ),
          )
        else
          ..._recent.map(_buildRecentTile),
      ],
    );
  }

  Widget _buildRecentTile(_RecentImport item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WhiteboardCanvasTokens.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.link_outlined,
            color: WhiteboardCanvasTokens.textFaint,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WhiteboardCanvasTokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.canonicalUrl.isNotEmpty)
                  Text(
                    item.canonicalUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WhiteboardCanvasTokens.textFaint,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_formatDate(item.createdAt)} · ${item.versionCount} 版',
            style: const TextStyle(
              color: WhiteboardCanvasTokens.textFaint,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
