/// Paste sanitization for [RichTextDocument].
///
/// When a user pastes content (from HTML, another editor, or plain text), the
/// input is cleaned before entering the document:
/// - Disallowed block types are downgraded to paragraphs.
/// - Disallowed inline marks are dropped.
/// - Links are validated: only `http`, `https`, and `mailto` schemes are kept;
///   `javascript:`, `data:`, `file:`, and unknown schemes are stripped to
///   plain text.
/// - Inline styles, event handlers, and foreign markup never enter the model.
/// - Asset references from pasted HTML are dropped (we only keep our own
///   stable refs); images become placeholder paragraphs with alt text.
library;

import 'rich_text_document.dart';

/// Result of sanitizing pasted content.
class SanitizeResult {
  final List<RichTextBlock> blocks;
  final List<String> warnings;

  const SanitizeResult(this.blocks, this.warnings);
}

/// Sanitizes a list of incoming blocks (e.g. from HTML parsing or another
/// editor's JSON) into safe [RichTextBlock]s for this document.
///
/// [allowedSchemes] defaults to `http`, `https`, `mailto`.
SanitizeResult sanitizePastedBlocks(
  List<RichTextBlock> input, {
  Set<String> allowedSchemes = const {'http', 'https', 'mailto'},
}) {
  final warnings = <String>[];
  final blocks = <RichTextBlock>[];
  for (final block in input) {
    blocks.add(_sanitizeBlock(block, allowedSchemes, warnings));
  }
  if (blocks.isEmpty) {
    blocks.add(const RichTextBlock(type: BlockType.paragraph));
  }
  return SanitizeResult(blocks, warnings);
}

RichTextBlock _sanitizeBlock(
  RichTextBlock block,
  Set<String> allowedSchemes,
  List<String> warnings,
) {
  // Image / video blocks from paste: drop asset refs, keep alt as text.
  // Handle these before type-downgrade so media blocks are converted, not
  // silently turned into empty paragraphs by the generic path.
  if (block.type == BlockType.image || block.type == BlockType.video) {
    final alt = (block.attrs['alt'] as String?) ?? '';
    if (alt.isNotEmpty) {
      warnings.add('Pasted media block converted to text (alt: "$alt").');
      return RichTextBlock(type: BlockType.paragraph, text: alt);
    }
    warnings.add('Pasted media block without alt dropped.');
    return const RichTextBlock(type: BlockType.paragraph);
  }

  // Downgrade disallowed block types to paragraph.
  final type = _allowedBlockTypes.contains(block.type)
      ? block.type
      : BlockType.paragraph;
  if (type != block.type) {
    warnings.add('Disallowed block type ${block.type.name} downgraded to paragraph.');
  }

  // Sanitize marks: drop disallowed mark types and unsafe links.
  final marks = <RichTextMark>[];
  for (final mark in block.marks) {
    if (!_allowedMarkTypes.contains(mark.type)) {
      warnings.add('Disallowed mark ${mark.type.name} dropped.');
      continue;
    }
    if (mark.type == MarkType.link) {
      final href = mark.attrs['href'] as String?;
      final scheme = _uriScheme(href);
      if (href == null || scheme == null || !allowedSchemes.contains(scheme)) {
        warnings.add('Unsafe link scheme "$scheme" stripped to plain text.');
        continue;
      }
      marks.add(RichTextMark(
        type: MarkType.link,
        start: mark.start,
        end: mark.end,
        attrs: {'href': href},
      ));
    } else {
      marks.add(mark);
    }
  }

  // Strip disallowed attrs (only keep known block-level keys).
  final attrs = _sanitizeAttrs(type, block.attrs, warnings);

  // Recursively sanitize children.
  final children = block.children
      .map((c) => _sanitizeBlock(c, allowedSchemes, warnings))
      .toList();

  return RichTextBlock(
    type: type,
    text: block.text,
    marks: marks,
    attrs: attrs,
    children: children,
  );
}

const _allowedBlockTypes = {
  BlockType.paragraph,
  BlockType.heading,
  BlockType.list,
  BlockType.quote,
  BlockType.code,
  BlockType.reference,
};

const _allowedMarkTypes = {
  MarkType.bold,
  MarkType.italic,
  MarkType.underline,
  MarkType.strikethrough,
  MarkType.code,
  MarkType.link,
};

Map<String, dynamic> _sanitizeAttrs(
  BlockType type,
  Map<String, dynamic> attrs,
  List<String> warnings,
) {
  final out = <String, dynamic>{};
  switch (type) {
    case BlockType.heading:
      final level = (attrs['level'] as num?)?.toInt();
      if (level != null) out['level'] = level.clamp(1, 6);
      break;
    case BlockType.list:
      if (attrs['ordered'] == true) out['ordered'] = true;
      final depth = (attrs['depth'] as num?)?.toInt();
      if (depth != null) out['depth'] = depth.clamp(0, 8);
      break;
    case BlockType.code:
      final lang = attrs['language'] as String?;
      if (lang != null && lang.isNotEmpty) out['language'] = lang;
      break;
    case BlockType.reference:
      final label = attrs['label'] as String?;
      if (label != null) out['label'] = label;
      break;
    default:
      break;
  }
  return out;
}

/// Extracts the URI scheme (lowercased, without `:`) or null if invalid.
String? _uriScheme(String? href) {
  if (href == null) return null;
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;
  final colon = trimmed.indexOf(':');
  if (colon <= 0) return null;
  final scheme = trimmed.substring(0, colon).toLowerCase();
  if (RegExp(r'^[a-z][a-z0-9+.\-]*$').hasMatch(scheme)) return scheme;
  return null;
}