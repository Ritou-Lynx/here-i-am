/// Local-only media projection shared by the card library and whiteboard.
///
/// Rendering a Card must never turn an untrusted URL or path-looking string
/// into an ImageProvider. This resolver accepts only RichText object refs
/// guarded by [RichTextObjectStore], or integrity-checked cached Source
/// thumbnails returned by [UnifiedCardRepository.resolveCachedThumbnail].
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

enum CardLocalMediaState { none, available, missing }

class CardLocalMediaProjection {
  const CardLocalMediaProjection._({
    required this.state,
    this.file,
    this.label,
    this.opensFull = false,
    this.isImagePrimary = false,
  });

  const CardLocalMediaProjection.none()
      : this._(state: CardLocalMediaState.none);

  const CardLocalMediaProjection.available(
    File file, {
    String? label,
    bool opensFull = false,
    bool isImagePrimary = false,
  }) : this._(
          state: CardLocalMediaState.available,
          file: file,
          label: label,
          opensFull: opensFull,
          isImagePrimary: isImagePrimary,
        );

  const CardLocalMediaProjection.missing({
    String? label,
    bool opensFull = false,
    bool isImagePrimary = false,
  }) : this._(
          state: CardLocalMediaState.missing,
          label: label,
          opensFull: opensFull,
          isImagePrimary: isImagePrimary,
        );

  final CardLocalMediaState state;
  final File? file;
  final String? label;
  final bool opensFull;

  /// True only when the document is an image card, rather than text with an
  /// embedded image. Titles created from filenames do not count as body text.
  final bool isImagePrimary;

  bool get hasEvidence => state != CardLocalMediaState.none;
  bool get isAvailable => state == CardLocalMediaState.available;
}

class CardLocalMediaResolver {
  const CardLocalMediaResolver(this.repository);

  final UnifiedCardRepository repository;

  Future<CardLocalMediaProjection> resolve(
    String cardId, {
    CardContract? card,
  }) async {
    final document =
        repository.richTextStorage.loadWithStatusSync(cardId).document;
    final imageBlock = document == null ? null : _firstImage(document.blocks);
    if (imageBlock != null) {
      final ref = document!.assetRefById(imageBlock.assetRefId ?? '');
      final label = _imageLabel(imageBlock);
      final imagePrimary = isImagePrimaryDocument(document);
      final opensFull = imagePrimary;
      if (ref == null || !ref.mimeType.startsWith('image/')) {
        return CardLocalMediaProjection.missing(
          label: label,
          opensFull: opensFull,
          isImagePrimary: imagePrimary,
        );
      }
      final file = RichTextObjectStore(
        repository.richTextStorage.baseDir,
      ).resolveFile(ref);
      return file == null
          ? CardLocalMediaProjection.missing(
              label: label,
              opensFull: opensFull,
              isImagePrimary: imagePrimary,
            )
          : CardLocalMediaProjection.available(
              file,
              label: label,
              opensFull: opensFull,
              isImagePrimary: imagePrimary,
            );
    }

    final hasProjectedCache = card?.presentation['thumbnail_ref'] is String;
    if (card?.cardKind != CardKind.source && !hasProjectedCache) {
      return const CardLocalMediaProjection.none();
    }
    final record = await repository.getCard(cardId, loadDocument: false);
    if (record == null) return const CardLocalMediaProjection.none();

    final sourceType = record.source?.mediaType;
    final hasCachedEvidence =
        record.card.presentation['thumbnail_ref'] is String ||
            record.source?.metadata['thumbnail_ref'] is String;
    if (sourceType != SourceMediaType.image && !hasCachedEvidence) {
      return const CardLocalMediaProjection.none();
    }
    final thumbnail = await repository.resolveCachedThumbnail(record);
    if (thumbnail.isAvailable && thumbnail.file != null) {
      return CardLocalMediaProjection.available(
        thumbnail.file!,
        label: record.card.title,
        opensFull: sourceType == SourceMediaType.image,
      );
    }
    return CardLocalMediaProjection.missing(
      label: record.card.title,
      opensFull: sourceType == SourceMediaType.image,
    );
  }

  static RichTextBlock? _firstImage(List<RichTextBlock> blocks) {
    for (final block in blocks) {
      if (block.type == BlockType.image) return block;
      final nested = _firstImage(block.children);
      if (nested != null) return nested;
    }
    return null;
  }

  static RichTextBlock? _firstContentBlock(List<RichTextBlock> blocks) {
    for (final block in blocks) {
      if (block.type == BlockType.image ||
          block.type == BlockType.video ||
          block.type == BlockType.reference ||
          block.text.trim().isNotEmpty) {
        return block;
      }
    }
    return null;
  }

  static String? _imageLabel(RichTextBlock block) {
    for (final key in const ['caption', 'alt']) {
      final value = block.attrs[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

/// Image-card classification shared by canvas, library and the full viewer.
/// Nested editable text disqualifies an image-only card; captions/alt metadata
/// remain image metadata and do not create a fake text editor.
bool isImagePrimaryDocument(RichTextDocument document) {
  final first = CardLocalMediaResolver._firstContentBlock(document.blocks);
  if (first?.type != BlockType.image) return false;

  bool hasEditableText(List<RichTextBlock> blocks) {
    for (final block in blocks) {
      if (block.type != BlockType.image && block.text.trim().isNotEmpty) {
        return true;
      }
      if (hasEditableText(block.children)) return true;
    }
    return false;
  }

  return !hasEditableText(document.blocks);
}

class CardLocalMediaPreview extends StatefulWidget {
  const CardLocalMediaPreview({
    super.key,
    required this.repository,
    required this.cardId,
    this.card,
    required this.placementKey,
    required this.maxHeight,
    required this.surfaceColor,
    required this.foregroundColor,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
  });

  final UnifiedCardRepository repository;
  final String cardId;
  final CardContract? card;
  final String placementKey;
  final double maxHeight;
  final Color surfaceColor;
  final Color foregroundColor;
  final BoxFit fit;
  final BorderRadius borderRadius;

  @override
  State<CardLocalMediaPreview> createState() => _CardLocalMediaPreviewState();
}

class _CardLocalMediaPreviewState extends State<CardLocalMediaPreview> {
  late Future<CardLocalMediaProjection> _projection = _load();

  String _projectionKey(CardLocalMediaPreview value) =>
      '${value.cardId}|${value.card?.updatedAt?.toIso8601String()}|'
      '${value.card?.presentation['thumbnail_ref']}|${value.card?.sourceId}';

  Future<CardLocalMediaProjection> _load() => CardLocalMediaResolver(
        widget.repository,
      ).resolve(widget.cardId, card: widget.card);

  @override
  void didUpdateWidget(covariant CardLocalMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.cardId != widget.cardId ||
        _projectionKey(oldWidget) != _projectionKey(widget)) {
      _projection = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CardLocalMediaProjection>(
      future: _projection,
      builder: (context, snapshot) {
        final projection = snapshot.data;
        if (projection == null || !projection.hasEvidence) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          key: ValueKey('wb_local_media_${widget.placementKey}'),
          width: double.infinity,
          height: widget.maxHeight.isFinite ? widget.maxHeight : null,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: projection.isAvailable && projection.file != null
                ? Image.file(
                    projection.file!,
                    key: ValueKey(
                      'wb_local_media_image_${widget.placementKey}',
                    ),
                    fit: widget.fit,
                    filterQuality: FilterQuality.medium,
                    cacheWidth: 1024,
                    errorBuilder: (_, __, ___) => _missing(),
                  )
                : _missing(),
          ),
        );
      },
    );
  }

  Widget _missing() => ColoredBox(
        color: widget.surfaceColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 24,
                color: widget.foregroundColor,
              ),
              const SizedBox(height: 6),
              Text(
                '图片对象缺失',
                style: whiteboardUiTextStyle(
                  fontSize: 11,
                  color: widget.foregroundColor,
                ),
              ),
            ],
          ),
        ),
      );
}
