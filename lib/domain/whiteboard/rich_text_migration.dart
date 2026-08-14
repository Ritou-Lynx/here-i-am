/// Schema migration for [RichTextDocument].
///
/// Older documents may carry a lower `schema_version`. This module upgrades
/// them to the current [richTextSchemaVersion]. Migration is idempotent:
/// running it on an already-current document is a no-op. Damaged documents
/// (unparseable, missing fields) degrade to a single empty paragraph rather
/// than throwing, so a corrupt card never blocks the editor.
library;

import 'rich_text_document.dart';

/// Migrates a raw JSON map to the current [RichTextDocument] schema.
///
/// Handles:
/// - schema_version 0 (pre-contract): plain string body → single paragraph.
/// - schema_version 1 (W0 shell): blocks without asset_refs; marks preserved.
/// - schema_version 2 (current): passthrough after validation.
/// - Unknown / corrupt: degrades to empty document.
RichTextDocument migrateRichTextDocument(Map<String, dynamic> json) {
  final version = (json['schema_version'] as num?)?.toInt() ?? 0;
  switch (version) {
    case 0:
      return _migrateV0(json);
    case 1:
      return _migrateV1(json);
    case >= 2:
      return _migrateCurrent(json);
    default:
      return RichTextDocument.empty();
  }
}

/// V0: the card body was a plain string under `body` or `text`.
RichTextDocument _migrateV0(Map<String, dynamic> json) {
  final body = (json['body'] as String?) ?? (json['text'] as String?) ?? '';
  if (body.isEmpty) return RichTextDocument.empty();
  // Split on newlines into paragraphs.
  final lines = body.split('\n');
  final blocks = <RichTextBlock>[];
  for (final line in lines) {
    blocks.add(RichTextBlock(type: BlockType.paragraph, text: line));
  }
  return RichTextDocument(blocks: blocks);
}

/// V1: the W0 shell schema. Blocks exist but asset_refs did not.
RichTextDocument _migrateV1(Map<String, dynamic> json) {
  try {
    final doc = RichTextDocument.fromJson({
      ...json,
      'schema_version': richTextSchemaVersion,
    });
    // Re-normalize: clamp marks, drop empty trailing blocks except one.
    return _normalize(doc);
  } catch (_) {
    return RichTextDocument.empty();
  }
}

/// Current schema: validate and normalize.
RichTextDocument _migrateCurrent(Map<String, dynamic> json) {
  try {
    return _normalize(RichTextDocument.fromJson(json));
  } catch (_) {
    return RichTextDocument.empty();
  }
}

/// Normalizes a document: clamps mark ranges to text length, ensures at least
/// one block, and strips blocks with unknown type down to paragraphs.
RichTextDocument _normalize(RichTextDocument doc) {
  if (doc.blocks.isEmpty) return RichTextDocument.empty();
  final blocks = doc.blocks.map(_normalizeBlock).toList();
  return doc.copyWith(blocks: blocks);
}

RichTextBlock _normalizeBlock(RichTextBlock block) {
  final textLen = block.text.length;
  final marks = block.marks
      .map((m) => m.clamp(textLen))
      .where((m) => m != null)
      .cast<RichTextMark>()
      .toList();
  final children = block.children.map(_normalizeBlock).toList();
  return block.copyWith(marks: marks, children: children);
}