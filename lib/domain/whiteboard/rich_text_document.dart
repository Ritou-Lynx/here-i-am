/// RichTextDocument contract — the minimal schema for card rich text content.
///
/// This is a minimal shell, not a full editor. W2 (rich text editing) will
/// flesh out the block tree, marks, asset references, and migration
/// functions. The key invariant established here: rich text is Card content
/// (or Source-derived content), never contains whiteboard x/y/size, and must
/// be serializable, migratable, and safely renderable.
library;

/// The schema version for rich text documents.
const richTextSchemaVersion = 1;

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
}

/// A block in the rich text document tree.
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
}

/// A rich text document — the minimal shell.
///
/// Contains a schema version, block tree, and a plain-text projection. W2
/// will implement the full editor, migration functions, and asset reference
/// handling. For now, this establishes the serializable contract.
class RichTextDocument {
  final int schemaVersion;
  final List<RichTextBlock> blocks;

  const RichTextDocument({
    this.schemaVersion = richTextSchemaVersion,
    this.blocks = const [],
  });

  factory RichTextDocument.fromJson(Map<String, dynamic> json) {
    return RichTextDocument(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ??
          richTextSchemaVersion,
      blocks: (json['blocks'] as List<dynamic>?)
          ?.map((b) => RichTextBlock.fromJson(b as Map<String, dynamic>))
          .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        if (blocks.isNotEmpty) 'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  /// Computes a plain-text projection of the document for search and preview.
  ///
  /// W2 will replace this with a proper projection that handles all block
  /// types and mark ranges.
  String toPlainText() {
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(block.text);
    }
    return buffer.toString();
  }
}