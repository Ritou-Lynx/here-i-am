/// Card library screen — a Repository-backed view of the single card truth.
///
/// Route: `/cards`. Production queries [UnifiedCardRepository], whose body
/// projection includes rich-text visible text. [RichTextSearchIndex] remains
/// only as a compatibility injection seam for focused legacy widget tests.
/// Tapping a hit opens the card editor via the frozen `/cards/:cardId` route.
///
/// The card library never scans rich-text folders as production truth.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/domain/whiteboard/rich_text_search.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// The unique card library: search saved card rich text by plain-text
/// projection, then open the card editor.
class CardLibraryScreen extends StatefulWidget {
  /// Optional injected index (tests); defaults to the production directory.
  final RichTextSearchIndex? index;
  final UnifiedCardRepository? repository;

  const CardLibraryScreen({super.key, this.index, this.repository});

  static Future<UnifiedCardRepository> resolveRepository() async {
    return WhiteboardDataBootstrap.productionRepository();
  }

  @override
  State<CardLibraryScreen> createState() => _CardLibraryScreenState();
}

class _CardLibraryScreenState extends State<CardLibraryScreen> {
  late final Future<UnifiedCardRepository?> _repositoryFuture =
      widget.repository != null
          ? Future.value(widget.repository)
          : widget.index != null
              ? Future.value(null)
              : CardLibraryScreen.resolveRepository();
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  List<_CardLibraryHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    if (widget.index == null) {
      _runQuery('');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _runQuery(raw.trim()),
    );
  }

  Future<void> _runQuery(String query) async {
    final legacyIndex = widget.index;
    if (legacyIndex != null) {
      final hits = query.isEmpty
          ? const <RichTextSearchHit>[]
          : legacyIndex.search(query);
      if (!mounted) return;
      setState(() {
        _hits = hits
            .map((hit) => _CardLibraryHit(
                  cardId: hit.cardId,
                  title: hit.title,
                  plainText: hit.plainText,
                ))
            .toList();
      });
      return;
    }
    final repository = await _repositoryFuture;
    if (repository == null) return;
    final records = await repository.listCards(CardLibraryQuery(search: query));
    if (!mounted) return;
    setState(() {
      _hits = records
          .map((record) => _CardLibraryHit(
                cardId: record.card.cardId,
                title: record.card.title,
                plainText: record.card.body,
              ))
          .toList();
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
                  borderSide: const BorderSide(
                      color: WhiteboardCanvasTokens.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: WhiteboardCanvasTokens.cardBorder),
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
    if (_queryController.text.trim().isEmpty && widget.index != null) {
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
  String _snippet(_CardLibraryHit hit) {
    final lines = hit.plainText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.isEmpty ? hit.cardId : lines.take(3).join(' · ');
  }
}

class _CardLibraryHit {
  const _CardLibraryHit({
    required this.cardId,
    required this.title,
    required this.plainText,
  });

  final String cardId;
  final String title;
  final String plainText;
}
