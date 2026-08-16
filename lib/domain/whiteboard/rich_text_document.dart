/// RichTextDocument contract — the serializable schema for card rich text.
///
/// Rich text is Card content (or Source-derived content). It never contains
/// whiteboard `x / y / size` — those belong to `BoardItem`. The document is
/// serializable, migratable, and safely renderable. Images and attachments
/// only hold stable asset references; temporary paths and large binaries are
/// never embedded in the JSON.
///
/// See:
/// - `docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md` §3 for the
///   shared-contract table (W0 + W2 own `RichTextDocument`).
/// - `rich_text_migration.dart` for schema migration from older versions.
library;

import 'rich_text_asset_ref.dart';

/// The current schema version for rich text documents.
const richTextSchemaVersion = 2;

/// The type of a rich text block.
enum BlockType {
  paragraph,
  heading,
  list,
  quote,
  code,
  image,
  video,
  reference;

  static BlockType fromString(String? raw) {
    switch (raw) {
      case 'paragraph':
        return BlockType.paragraph;
      case 'heading':
        return BlockType.heading;
      case 'list':
        return BlockType.list;
      case 'quote':
        return BlockType.quote;
      case 'code':
        return BlockType.code;
      case 'image':
        return BlockType.image;
      case 'video':
        return BlockType.video;
      case 'reference':
        return BlockType.reference;
      default:
        return BlockType.paragraph;
    }
  }
}

/// The type of an inline mark (bold, italic, etc.).
enum MarkType {
  bold,
  italic,
  underline,
  strikethrough,
  code,
  link;

  static MarkType fromString(String? raw) {
    switch (raw) {
      case 'bold':
        return MarkType.bold;
      case 'italic':
        return MarkType.italic;
      case 'underline':
        return MarkType.underline;
      case 'strikethrough':
        return MarkType.strikethrough;
      case 'code':
        return MarkType.code;
      case 'link':
        return MarkType.link;
      default:
        throw ArgumentError('Unknown MarkType: $raw');
    }
  }
}

/// An inline mark applied to a range of text within a block.
///
/// Mark ranges are character offsets into the parent block's [RichTextBlock.text].
/// `start` is inclusive, `end` is exclusive: `[start, end)`.
class RichTextMark {
  final MarkType type;
  final int start;
  final int end;
  final Map<String, dynamic> attrs;

  const RichTextMark({
    required this.type,
    required this.start,
    required this.end,
    this.attrs = const {},
  });

  factory RichTextMark.fromJson(Map<String, dynamic> json) {
    return RichTextMark(
      type: MarkType.fromString(json['type'] as String?),
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      attrs: (json['attrs'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'start': start,
        'end': end,
        if (attrs.isNotEmpty) 'attrs': attrs,
      };

  /// Returns a copy with `start` and `end` shifted by [delta]. Clamps at 0.
  RichTextMark shift(int delta) => RichTextMark(
        type: type,
        start: (start + delta < 0) ? 0 : start + delta,
        end: (end + delta < 0) ? 0 : end + delta,
        attrs: attrs,
      );

  /// Returns a copy clamped to `[0, length]` and dropped if it collapses.
  RichTextMark? clamp(int length) {
    final s = start.clamp(0, length);
    final e = end.clamp(0, length);
    if (s >= e) return null;
    return RichTextMark(type: type, start: s, end: e, attrs: attrs);
  }
}

/// A block in the rich text document tree.
///
/// - [type] determines rendering and which [attrs] keys are meaningful.
/// - [text] is the inline text of this block (empty for media blocks).
/// - [marks] are inline marks over [text] character ranges.
/// - [attrs] holds block-level metadata (heading level, list ordered/depth,
///   code language, asset ref id, etc.).
/// - [children] are nested blocks (used by list items and quotes).
class RichTextBlock {
  final BlockType type;
  final String text;
  final List<RichTextMark> marks;
  final Map<String, dynamic> attrs;
  final List<RichTextBlock> children;

  const RichTextBlock({
    required this.type,
    this.text = '',
    this.marks = const [],
    this.attrs = const {},
    this.children = const [],
  });

  factory RichTextBlock.fromJson(Map<String, dynamic> json) {
    return RichTextBlock(
      type: BlockType.fromString(json['type'] as String?),
      text: json['text'] as String? ?? '',
      marks: (json['marks'] as List<dynamic>?)
              ?.map((m) => RichTextMark.fromJson(m as Map<String, dynamic>))
              .toList() ??
          const [],
      attrs: (json['attrs'] as Map<String, dynamic>?) ?? const {},
      children: (json['children'] as List<dynamic>?)
              ?.map((c) => RichTextBlock.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (text.isNotEmpty) 'text': text,
        if (marks.isNotEmpty) 'marks': marks.map((m) => m.toJson()).toList(),
        if (attrs.isNotEmpty) 'attrs': attrs,
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
      };

  /// Heading level (1–6). Defaults to 1 when absent or invalid.
  int get headingLevel {
    if (type != BlockType.heading) return 1;
    final raw = attrs['level'];
    if (raw is num) return raw.toInt().clamp(1, 6);
    if (raw is int) return raw.clamp(1, 6);
    return 1;
  }

  /// Whether a list block is ordered (`true`) or bullet (`false`).
  bool get listOrdered => attrs['ordered'] == true;

  /// List nesting depth (0 = top level).
  int get listDepth {
    final raw = attrs['depth'];
    if (raw is num) return raw.toInt().clamp(0, 8);
    return 0;
  }

  /// Code block language hint (e.g. `dart`, `python`). May be empty.
  String get codeLanguage => (attrs['language'] as String?) ?? '';

  /// Stable asset reference id for image / video / reference blocks.
  /// Resolved via [RichTextAssetRef] lookup; never a raw filesystem path.
  String? get assetRefId => attrs['asset_ref_id'] as String?;

  RichTextBlock copyWith({
    BlockType? type,
    String? text,
    List<RichTextMark>? marks,
    Map<String, dynamic>? attrs,
    List<RichTextBlock>? children,
  }) =>
      RichTextBlock(
        type: type ?? this.type,
        text: text ?? this.text,
        marks: marks ?? this.marks,
        attrs: attrs ?? this.attrs,
        children: children ?? this.children,
      );
}

/// A rich text document — the serializable content of a Card or Source-derived
/// annotation body.
///
/// The document is a flat list of top-level blocks. List items and quote
/// contents use [RichTextBlock.children] for nesting. All asset references
/// are collected in [assetRefs] and referenced by `asset_ref_id` in block
/// attrs, so the JSON never carries temporary paths or large binaries.
class RichTextDocument {
  final int schemaVersion;
  final List<RichTextBlock> blocks;
  final List<RichTextAssetRef> assetRefs;

  const RichTextDocument({
    this.schemaVersion = richTextSchemaVersion,
    this.blocks = const [],
    this.assetRefs = const [],
  });

  factory RichTextDocument.fromJson(Map<String, dynamic> json) {
    return RichTextDocument(
      schemaVersion:
          (json['schema_version'] as num?)?.toInt() ?? richTextSchemaVersion,
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((b) => RichTextBlock.fromJson(b as Map<String, dynamic>))
              .toList() ??
          const [],
      assetRefs: (json['asset_refs'] as List<dynamic>?)
              ?.map((a) =>
                  RichTextAssetRef.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        if (blocks.isNotEmpty) 'blocks': blocks.map((b) => b.toJson()).toList(),
        if (assetRefs.isNotEmpty)
          'asset_refs': assetRefs.map((a) => a.toJson()).toList(),
      };

  /// Computes a plain-text projection of the document for search and preview.
  ///
  /// Recursively concatenates block text, joining blocks with newlines. List
  /// items are prefixed with `- ` (bullet) or `1. ` (ordered, using a running
  /// counter per list). Quote blocks are prefixed with `> `. Heading and code
  /// blocks contribute their text. Media blocks contribute their caption /
  /// alt text (from attrs), not the asset ref id.
  String toPlainText() {
    final buffer = StringBuffer();
    _appendPlainText(buffer, blocks, prefix: '');
    return buffer.toString();
  }

  static void _appendPlainText(
    StringBuffer buffer,
    List<RichTextBlock> blocks, {
    required String prefix,
  }) {
    var orderedIndex = 1;
    for (final block in blocks) {
      if (buffer.isNotEmpty) buffer.write('\n');
      switch (block.type) {
        case BlockType.list:
          final marker = block.listOrdered
              ? '$orderedIndex. '
              : '- ';
          orderedIndex++;
          if (block.text.isNotEmpty) {
            buffer.write(prefix);
            buffer.write('  ' * block.listDepth);
            buffer.write(marker);
            buffer.write(block.text);
          }
          if (block.children.isNotEmpty) {
            buffer.write('\n');
            // Nested children sit one visual level deeper than the parent's
            // own depth-based indent.
            _appendPlainText(buffer, block.children,
                prefix: '$prefix${'  ' * (block.listDepth + 1)}');
          }
          if (!block.listOrdered) orderedIndex = 1;
          break;
        case BlockType.quote:
          buffer.write(prefix);
          buffer.write('> ');
          buffer.write(block.text);
          if (block.children.isNotEmpty) {
            buffer.write('\n');
            _appendPlainText(buffer, block.children, prefix: '$prefix> ');
          }
          break;
        case BlockType.image:
        case BlockType.video:
          final caption = (block.attrs['caption'] as String?) ?? '';
          final alt = (block.attrs['alt'] as String?) ?? '';
          buffer.write(prefix);
          buffer.write(caption.isNotEmpty ? caption : alt);
          break;
        case BlockType.reference:
          final label = (block.attrs['label'] as String?) ?? block.text;
          buffer.write(prefix);
          buffer.write(label);
          break;
        default:
          buffer.write(prefix);
          buffer.write(block.text);
          if (block.children.isNotEmpty) {
            buffer.write('\n');
            _appendPlainText(buffer, block.children, prefix: prefix);
          }
      }
    }
  }

  /// Looks up an [RichTextAssetRef] by id from [assetRefs].
  RichTextAssetRef? assetRefById(String id) {
    for (final ref in assetRefs) {
      if (ref.refId == id) return ref;
    }
    return null;
  }

  /// Creates an empty document (a single empty paragraph).
  factory RichTextDocument.empty() => const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph)],
      );

  /// Returns a copy with the provided fields replaced.
  RichTextDocument copyWith({
    int? schemaVersion,
    List<RichTextBlock>? blocks,
    List<RichTextAssetRef>? assetRefs,
  }) =>
      RichTextDocument(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        blocks: blocks ?? this.blocks,
        assetRefs: assetRefs ?? this.assetRefs,
      );
}