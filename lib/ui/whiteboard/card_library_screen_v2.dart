/// The single Repository-backed card library.
///
/// Production reads and writes only through [UnifiedCardRepository]. The
/// legacy [RichTextSearchIndex] injection remains solely for older focused
/// widget tests; it is never selected by the production route.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_search.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

class CardLibraryScreen extends StatefulWidget {
  final RichTextSearchIndex? index;
  final UnifiedCardRepository? repository;

  const CardLibraryScreen({super.key, this.index, this.repository});

  static Future<UnifiedCardRepository> resolveRepository() =>
      WhiteboardDataBootstrap.productionRepository();

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
  final _queryController = TextEditingController();
  Timer? _debounce;
  List<_CardLibraryHit> _hits = const [];
  Set<String> _knownTags = const {};
  CardKind? _kind;
  SourceMediaType? _sourceType;
  String? _tag;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _runQuery();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runQuery);
  }

  Future<void> _runQuery() async {
    final requestId = ++_requestId;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final query = _queryController.text.trim();
      final legacyIndex = widget.index;
      if (legacyIndex != null) {
        final results = query.isEmpty
            ? const <RichTextSearchHit>[]
            : legacyIndex.search(query);
        if (!mounted || requestId != _requestId) return;
        setState(() {
          _hits = results
              .map((hit) => _CardLibraryHit.legacy(
                    cardId: hit.cardId,
                    title: hit.title,
                    plainText: hit.plainText,
                  ))
              .toList();
          _loading = false;
        });
        return;
      }

      final repository = await _repositoryFuture;
      if (repository == null) return;
      final records = await repository.listCards(CardLibraryQuery(
        kinds: _kind == null ? null : {_kind!},
        sourceTypes: _sourceType == null ? null : {_sourceType!},
        tags: _tag == null ? null : {_tag!},
        search: query,
      ));
      final allRecords = _knownTags.isEmpty
          ? await repository.listCards()
          : const <UnifiedCardRecord>[];
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _hits = records.map(_CardLibraryHit.fromRecord).toList();
        if (allRecords.isNotEmpty) {
          _knownTags = {
            for (final record in allRecords) ...record.card.tags,
          };
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '卡片库加载失败：$error';
      });
    }
  }

  Future<void> _createTextCard() async {
    if (_creating || widget.index != null) return;
    setState(() => _creating = true);
    try {
      final repository = await _repositoryFuture;
      if (repository == null) return;
      final card = await repository.createTextCard();
      if (!mounted) return;
      await context.push(AppRoutes.cardEditPath(card.cardId));
      if (mounted) await _runQuery();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新建失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _open(_CardLibraryHit hit) async {
    final path = hit.opensSource
        ? AppRoutes.sourceStudyPath(hit.sourceId!)
        : AppRoutes.cardEditPath(hit.cardId);
    await context.push(path);
    if (mounted && widget.index == null) await _runQuery();
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
              context.go(AppRoutes.home);
            }
          },
        ),
        title: const Text('卡片库'),
        titleTextStyle: whiteboardUiTextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: _buildToolbar(),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('card-library-search'),
                controller: _queryController,
                onChanged: _onQueryChanged,
                style: richTextBodyTextStyle(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索标题、正文或标签…',
                  hintStyle: richTextBodyTextStyle(
                    color: WhiteboardCanvasTokens.textFaint,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: WhiteboardCanvasTokens.textFaint,
                  ),
                  filled: true,
                  fillColor: WhiteboardCanvasTokens.cardSurface,
                  constraints: const BoxConstraints(minHeight: 44),
                  border: _inputBorder(),
                  enabledBorder: _inputBorder(),
                  focusedBorder: _inputBorder(
                    color: WhiteboardCanvasTokens.action,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const ValueKey('card-library-import-link'),
              onPressed: () => context.push(AppRoutes.linkImport),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('导入链接'),
              style: _secondaryButtonStyle(),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('card-library-create-text'),
              onPressed:
                  widget.index != null || _creating ? null : _createTextCard,
              icon: _creating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建文字卡'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: WhiteboardCanvasTokens.action,
                foregroundColor: WhiteboardCanvasTokens.canvas,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: whiteboardUiTextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (widget.index == null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterMenu<CardKind>(
                key: const ValueKey('card-library-kind-filter'),
                label: '类型',
                value: _kind,
                values: CardKind.values,
                labelFor: _cardKindLabel,
                onChanged: (value) {
                  setState(() => _kind = value);
                  _runQuery();
                },
              ),
              _FilterMenu<SourceMediaType>(
                key: const ValueKey('card-library-source-filter'),
                label: '来源',
                value: _sourceType,
                values: SourceMediaType.values,
                labelFor: _sourceTypeLabel,
                onChanged: (value) {
                  setState(() => _sourceType = value);
                  _runQuery();
                },
              ),
              _FilterMenu<String>(
                key: const ValueKey('card-library-tag-filter'),
                label: '标签',
                value: _tag,
                values: _knownTags.toList()..sort(),
                labelFor: (value) => value,
                onChanged: (value) {
                  setState(() => _tag = value);
                  _runQuery();
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: WhiteboardCanvasTokens.action,
        ),
      );
    }
    if (_error != null) {
      return _LibraryMessage(
        icon: Icons.error_outline_rounded,
        title: _error!,
        actionLabel: '重试',
        onAction: _runQuery,
      );
    }
    if (_queryController.text.trim().isEmpty && widget.index != null) {
      return const _LibraryMessage(
        icon: Icons.collections_bookmark_outlined,
        title: '输入关键词搜索卡片内容',
      );
    }
    if (_hits.isEmpty) {
      final narrowed = _kind != null ||
          _sourceType != null ||
          _tag != null ||
          _queryController.text.trim().isNotEmpty;
      return _LibraryMessage(
        icon: Icons.inbox_outlined,
        title: narrowed ? '没有匹配的卡片' : '卡片库还是空的',
        detail: narrowed ? '调整筛选条件或换一个关键词。' : '新建一张文字卡，或从链接导入内容。',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1180
            ? 4
            : width >= 820
                ? 3
                : width >= 540
                    ? 2
                    : 1;
        return GridView.builder(
          key: const ValueKey('card-library-grid'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 1.8 : 1.04,
          ),
          itemCount: _hits.length,
          itemBuilder: (context, index) {
            final hit = _hits[index];
            return _CardPreview(
              key: ValueKey('card-library-card-${hit.cardId}'),
              hit: hit,
              onTap: () => _open(hit),
            );
          },
        );
      },
    );
  }

  OutlineInputBorder _inputBorder({
    Color color = WhiteboardCanvasTokens.cardBorder,
    double width = 1,
  }) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  ButtonStyle _secondaryButtonStyle() => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        side: const BorderSide(color: WhiteboardCanvasTokens.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: whiteboardUiTextStyle(fontSize: 14),
      );
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> values;
  final String Function(T value) labelFor;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FilterChoice<T>>(
      tooltip: '$label筛选',
      onSelected: (choice) => onChanged(choice.value),
      color: WhiteboardCanvasTokens.panelSurface,
      itemBuilder: (context) => [
        PopupMenuItem<_FilterChoice<T>>(
          value: _FilterChoice<T>(null),
          child: Text('全部', style: whiteboardUiTextStyle(fontSize: 13)),
        ),
        for (final item in values)
          PopupMenuItem<_FilterChoice<T>>(
            value: _FilterChoice<T>(item),
            child: Text(
              labelFor(item),
              style: whiteboardUiTextStyle(fontSize: 13),
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value == null
              ? WhiteboardCanvasTokens.cardSurface
              : WhiteboardCanvasTokens.cardSurfaceSelected,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WhiteboardCanvasTokens.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label：${value == null ? '全部' : labelFor(value as T)}',
              style: whiteboardUiTextStyle(
                fontSize: 12,
                color: WhiteboardCanvasTokens.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: WhiteboardCanvasTokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChoice<T> {
  const _FilterChoice(this.value);

  final T? value;
}

class _CardPreview extends StatelessWidget {
  const _CardPreview({
    super.key,
    required this.hit,
    required this.onTap,
  });

  final _CardLibraryHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WhiteboardCanvasTokens.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: WhiteboardCanvasTokens.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: hit.isMedia ? _mediaCard() : _textCard(),
      ),
    );
  }

  Widget _mediaCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 7, child: _MediaPreview(hit: hit)),
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hit.title.isEmpty ? '未命名卡片' : hit.title,
                  style: richTextBodyTextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    _sourceTypeLabel(hit.sourceType!),
                    if (hit.sourceLabel != null) hit.sourceLabel!,
                    if (hit.tags.isNotEmpty) hit.tags.take(2).join(' · '),
                  ].join(' · '),
                  style: whiteboardUiTextStyle(
                    fontSize: 12,
                    color: WhiteboardCanvasTokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _textCard() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              _NeutralLabel(text: _cardKindLabel(hit.cardKind)),
              if (hit.tags.isNotEmpty) _NeutralLabel(text: hit.tags.first),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Text(
              hit.previewText,
              style: richTextBodyTextStyle(fontSize: 14, height: 1.65),
              maxLines: 7,
              overflow: TextOverflow.fade,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hit.title.isEmpty ? '未命名文字卡' : hit.title,
            style: richTextBodyTextStyle(
              fontSize: 12,
              color: WhiteboardCanvasTokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.hit});

  final _CardLibraryHit hit;

  @override
  Widget build(BuildContext context) {
    final thumbnail = hit.thumbnail?.trim();
    if (thumbnail != null && thumbnail.isNotEmpty) {
      if (thumbnail.startsWith('http://') || thumbnail.startsWith('https://')) {
        return Image.network(
          thumbnail,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _missing(),
        );
      }
      final path = thumbnail.startsWith('file://')
          ? Uri.parse(thumbnail).toFilePath()
          : thumbnail;
      final file = File(path);
      if (file.isAbsolute && file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _missing(),
        );
      }
    }
    return _missing();
  }

  Widget _missing() {
    final type = hit.sourceType;
    final icon = switch (type) {
      SourceMediaType.image => Icons.image_outlined,
      SourceMediaType.video => Icons.play_circle_outline_rounded,
      SourceMediaType.web => Icons.language_rounded,
      SourceMediaType.book => Icons.menu_book_outlined,
      SourceMediaType.audio => Icons.graphic_eq_rounded,
      SourceMediaType.pdf => Icons.picture_as_pdf_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    final label = switch (type) {
      SourceMediaType.video => '暂无视频封面',
      SourceMediaType.web => '暂无网页预览',
      SourceMediaType.image => '暂无图片预览',
      SourceMediaType.book => '暂无书籍封面',
      _ => '暂无媒体预览',
    };
    return ColoredBox(
      color: WhiteboardCanvasTokens.dark,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: WhiteboardCanvasTokens.canvas),
            const SizedBox(height: 8),
            Text(
              label,
              style: whiteboardUiTextStyle(
                fontSize: 12,
                color: WhiteboardCanvasTokens.canvas,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeutralLabel extends StatelessWidget {
  const _NeutralLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: WhiteboardCanvasTokens.cardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WhiteboardCanvasTokens.cardBorder),
      ),
      child: Text(
        text,
        style: whiteboardUiTextStyle(
          fontSize: 11,
          color: WhiteboardCanvasTokens.textSecondary,
        ),
      ),
    );
  }
}

class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    required this.icon,
    required this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: WhiteboardCanvasTokens.textFaint, size: 40),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: whiteboardUiTextStyle(
              color: WhiteboardCanvasTokens.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: whiteboardUiTextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 12,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _CardLibraryHit {
  const _CardLibraryHit({
    required this.cardId,
    required this.title,
    required this.plainText,
    required this.cardKind,
    required this.tags,
    this.sourceId,
    this.sourceType,
    this.sourceLabel,
    this.thumbnail,
  });

  factory _CardLibraryHit.legacy({
    required String cardId,
    required String title,
    required String plainText,
  }) =>
      _CardLibraryHit(
        cardId: cardId,
        title: title,
        plainText: plainText,
        cardKind: CardKind.note,
        tags: const [],
      );

  factory _CardLibraryHit.fromRecord(UnifiedCardRecord record) {
    final metadata = record.source?.metadata ?? const <String, dynamic>{};
    String? thumbnail = record.thumbnail;
    for (final key in const [
      'thumbnail',
      'thumbnail_url',
      'og_image',
      'cover',
      'cover_url',
    ]) {
      final candidate = metadata[key];
      if ((thumbnail == null || thumbnail.isEmpty) && candidate is String) {
        thumbnail = candidate;
      }
    }
    return _CardLibraryHit(
      cardId: record.card.cardId,
      title: record.card.title,
      plainText: record.card.body,
      cardKind: record.card.cardKind,
      tags: record.card.tags,
      sourceId: record.card.sourceId,
      sourceType: record.source?.mediaType,
      sourceLabel: record.source?.provider,
      thumbnail: thumbnail,
    );
  }

  final String cardId;
  final String title;
  final String plainText;
  final CardKind cardKind;
  final List<String> tags;
  final String? sourceId;
  final SourceMediaType? sourceType;
  final String? sourceLabel;
  final String? thumbnail;

  bool get isMedia => sourceType != null && sourceType != SourceMediaType.text;
  bool get opensSource => cardKind == CardKind.source && sourceId != null;

  String get previewText {
    final lines = plainText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isNotEmpty) return lines.take(5).join('\n');
    if (title.trim().isNotEmpty) return title.trim();
    return '空白文字卡';
  }
}

String _cardKindLabel(CardKind kind) => switch (kind) {
      CardKind.source => '来源',
      CardKind.note => '文字',
      CardKind.annotation => '批注',
      CardKind.taskArtifact => '任务产物',
      CardKind.reference => '引用',
    };

String _sourceTypeLabel(SourceMediaType type) => switch (type) {
      SourceMediaType.text => '文本',
      SourceMediaType.book => '书籍',
      SourceMediaType.pdf => 'PDF',
      SourceMediaType.image => '图片',
      SourceMediaType.web => '网页',
      SourceMediaType.video => '视频',
      SourceMediaType.audio => '音频',
      SourceMediaType.file => '文件',
    };
