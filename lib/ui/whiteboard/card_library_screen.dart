/// Card library screen — the single card library with rich-text search.
///
/// Route: `/cards`. Searches the plain-text projections of saved rich text
/// documents ([RichTextSearchIndex]): the query matches what the user can
/// see in the editor — text, list markers, quote prefixes, media alt/caption
/// — because the projection is computed by `RichTextDocument.toPlainText()`.
/// Tapping a hit opens the card editor via the frozen `/cards/:cardId` route.
///
/// On desktop the screen renders a search bar + filter chips + a card grid
/// inside [DesktopShell]; on mobile it renders the original list layout so
/// the mobile app is unchanged.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:memex/domain/whiteboard/rich_text_search.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_page_head.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_shell.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_shell_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// The unique card library: search saved card rich text by plain-text
/// projection, then open the card editor.
class CardLibraryScreen extends StatefulWidget {
  /// Optional injected index (tests); defaults to the production directory.
  final RichTextSearchIndex? index;

  const CardLibraryScreen({super.key, this.index});

  /// Resolves the production search index: app support dir /
  /// `whiteboard/rich_text`. Falls back to a temp dir when the platform
  /// channel is unavailable (headless / widget tests).
  static Future<RichTextSearchIndex> resolveIndex() async {
    Directory dir;
    try {
      final support = await getApplicationSupportDirectory();
      dir = Directory(p.join(support.path, 'whiteboard', 'rich_text'));
    } catch (_) {
      dir = Directory(
          p.join(Directory.systemTemp.path, 'hereiam_whiteboard_rich_text'));
    }
    return RichTextSearchIndex(dir);
  }

  @override
  State<CardLibraryScreen> createState() => _CardLibraryScreenState();
}

class _CardLibraryScreenState extends State<CardLibraryScreen> {
  late final Future<RichTextSearchIndex> _indexFuture =
      widget.index != null ? Future.value(widget.index) : _resolveIndex();
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  List<RichTextSearchHit> _hits = const [];

  static Future<RichTextSearchIndex> _resolveIndex() =>
      CardLibraryScreen.resolveIndex();

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final query = raw.trim();
      if (!mounted) return;
      if (query.isEmpty) {
        setState(() => _hits = const []);
        return;
      }
      final index = await _indexFuture;
      final hits = index.search(query);
      if (!mounted) return;
      setState(() => _hits = hits);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform()) {
      return _buildDesktop();
    }
    return _buildMobile();
  }

  // ── Desktop: search + grid inside DesktopShell ──────────────────────────

  Widget _buildDesktop() {
    return DesktopShell(
      activeRoute: AppRoutes.cardLibrary,
      child: _DesktopCardLibraryPage(
        queryController: _queryController,
        onQueryChanged: _onQueryChanged,
        hits: _hits,
        onOpenCard: (cardId) => context.go(AppRoutes.cardEditPath(cardId)),
        snippet: _snippet,
      ),
    );
  }

  // ── Mobile: original list layout (unchanged) ────────────────────────────

  Widget _buildMobile() {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          tooltip: '返回首页',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text('卡片库'),
        titleTextStyle: whiteboardUiTextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _queryController,
              onChanged: _onQueryChanged,
              style: richTextBodyTextStyle(),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索卡片内容…',
                hintStyle: richTextBodyTextStyle(
                  fontSize: 14,
                  color: WhiteboardCanvasTokens.textFaint,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: WhiteboardCanvasTokens.textFaint,
                ),
                filled: true,
                fillColor: WhiteboardCanvasTokens.cardSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: WhiteboardCanvasTokens.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: WhiteboardCanvasTokens.cardBorder),
                ),
              ),
            ),
          ),
          Expanded(child: _buildMobileResults()),
        ],
      ),
    );
  }

  Widget _buildMobileResults() {
    if (_queryController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.collections_bookmark_outlined,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              '输入关键词搜索卡片内容',
              style: whiteboardUiTextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的卡片',
          style: whiteboardUiTextStyle(
            color: WhiteboardCanvasTokens.textFaint,
            fontSize: 13,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final hit = _hits[index];
        return Material(
          color: WhiteboardCanvasTokens.cardSurface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go(AppRoutes.cardEditPath(hit.cardId)),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title,
                    style: richTextBodyTextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _snippet(hit),
                    style: richTextBodyTextStyle(
                      fontSize: 12,
                      color: WhiteboardCanvasTokens.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// A compact snippet around the first non-empty line for preview.
  String _snippet(RichTextSearchHit hit) {
    final lines = hit.plainText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.isEmpty ? hit.cardId : lines.take(3).join(' · ');
  }
}

/// Desktop card library page — search box + results grid inside the shell.
class _DesktopCardLibraryPage extends StatelessWidget {
  const _DesktopCardLibraryPage({
    required this.queryController,
    required this.onQueryChanged,
    required this.hits,
    required this.onOpenCard,
    required this.snippet,
  });

  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final List<RichTextSearchHit> hits;
  final ValueChanged<String> onOpenCard;
  final String Function(RichTextSearchHit) snippet;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesktopShellTokens.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(54, 26, 28, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DesktopPageHead(
              title: '卡片库',
              kicker: '一个库，按内容搜索',
              actions: [
                _DesktopSearchBox(
                  controller: queryController,
                  onChanged: onQueryChanged,
                ),
              ],
            ),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (queryController.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.collections_bookmark_outlined,
                color: DesktopShellTokens.textFaint,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                '输入关键词搜索卡片内容',
                style: TextStyle(
                  fontSize: DesktopShellTokens.content,
                  color: DesktopShellTokens.textFaint,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Text(
            '没有匹配的卡片',
            style: TextStyle(
              fontSize: DesktopShellTokens.content,
              color: DesktopShellTokens.textFaint,
            ),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: hits
          .map((hit) => _DesktopCardTile(
                hit: hit,
                snippet: snippet(hit),
                onTap: () => onOpenCard(hit.cardId),
              ))
          .toList(),
    );
  }
}

/// A search box styled like `.hia-search-box`.
class _DesktopSearchBox extends StatelessWidget {
  const _DesktopSearchBox({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: DesktopShellTokens.surfaceRaised,
        border: Border.all(color: DesktopShellTokens.divider),
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          const Icon(
            Icons.search,
            size: 18,
            color: DesktopShellTokens.textFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                fontSize: DesktopShellTokens.content,
                color: DesktopShellTokens.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '搜索标题、正文、来源或标签',
                hintStyle: TextStyle(
                  fontSize: DesktopShellTokens.content,
                  color: DesktopShellTokens.textFaint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card tile in the desktop grid — mirrors `.hia-library-card.is-text`.
class _DesktopCardTile extends StatelessWidget {
  const _DesktopCardTile({
    required this.hit,
    required this.snippet,
    required this.onTap,
  });

  final RichTextSearchHit hit;
  final String snippet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DesktopShellTokens.surface,
      borderRadius: BorderRadius.circular(DesktopShellTokens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesktopShellTokens.radius),
        onTap: onTap,
        child: Container(
          width: 240,
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: DesktopShellTokens.moduleTitle,
                  fontWeight: FontWeight.w500,
                  color: DesktopShellTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: DesktopShellTokens.content,
                  height: 1.6,
                  color: DesktopShellTokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hit.cardId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: DesktopShellTokens.status,
                  color: DesktopShellTokens.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}