/// Card library screen — the single card library with rich-text search.
///
/// Route: `/cards`. Searches the plain-text projections of saved rich text
/// documents ([RichTextSearchIndex]): the query matches what the user can
/// see in the editor — text, list markers, quote prefixes, media alt/caption
/// — because the projection is computed by `RichTextDocument.toPlainText()`.
/// Tapping a hit opens the card editor via the frozen `/cards/:cardId` route.
///
/// The card library is self-contained: it resolves the same production
/// storage directory as `CardRichTextEditorScreen` (app support dir /
/// `whiteboard/rich_text`) and never touches Drift, the router table, or the
/// canvas.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:memex/domain/whiteboard/rich_text_search.dart';
import 'package:memex/routing/routes.dart';
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
      // Card documents are small local JSON files; search is synchronous.
      final index = await _indexFuture;
      final hits = index.search(query);
      if (!mounted) return;
      setState(() => _hits = hits);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        title: const Text('卡片库'),
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
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_queryController.text.trim().isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            SizedBox(height: 12),
            Text(
              '输入关键词搜索卡片内容',
              style: TextStyle(
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
      return const Center(
        child: Text(
          '没有匹配的卡片',
          style: TextStyle(
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
