/// Inline mark helpers for the rich text editor.
///
/// These utilities apply / remove / toggle [MarkType] over a character range
/// in a [RichTextBlock], returning a new block. They are pure functions used
/// by the editor controller and toolbar.
library;

import 'rich_text_document.dart';

/// Applies a mark over `[start, end)` in [block], merging with overlapping
/// marks of the same type. Returns a new block.
RichTextBlock applyMark(RichTextBlock block, MarkType type, int start, int end,
    {Map<String, dynamic> attrs = const {}}) {
  if (start >= end) return block;
  final textLen = block.text.length;
  final s = start.clamp(0, textLen);
  final e = end.clamp(0, textLen);
  if (s >= e) return block;
  final marks = List<RichTextMark>.from(block.marks);
  // Merge with existing same-type marks that overlap or are adjacent.
  final merged = <RichTextMark>[];
  var added = false;
  for (final m in marks) {
    if (m.type == type && m.start <= e && m.end >= s) {
      // Overlap or adjacent: extend.
      final ns = m.start < s ? m.start : s;
      final ne = m.end > e ? m.end : e;
      merged.add(RichTextMark(type: type, start: ns, end: ne, attrs: attrs));
      added = true;
    } else {
      merged.add(m);
    }
  }
  if (!added) {
    merged.add(RichTextMark(type: type, start: s, end: e, attrs: attrs));
  }
  merged.sort((a, b) =>
      a.start.compareTo(b.start) == 0
          ? a.end.compareTo(b.end)
          : a.start.compareTo(b.start));
  return block.copyWith(marks: merged);
}

/// Removes a mark type from `[start, end)` in [block], splitting overlapping
/// marks as needed. Returns a new block.
RichTextBlock removeMark(RichTextBlock block, MarkType type, int start, int end) {
  if (start >= end) return block;
  final textLen = block.text.length;
  final s = start.clamp(0, textLen);
  final e = end.clamp(0, textLen);
  if (s >= e) return block;
  final marks = <RichTextMark>[];
  for (final m in block.marks) {
    if (m.type != type || m.start >= e || m.end <= s) {
      marks.add(m);
      continue;
    }
    // Overlap: split into up to two fragments.
    if (m.start < s) {
      marks.add(RichTextMark(type: m.type, start: m.start, end: s, attrs: m.attrs));
    }
    if (m.end > e) {
      marks.add(RichTextMark(type: m.type, start: e, end: m.end, attrs: m.attrs));
    }
  }
  return block.copyWith(marks: marks);
}

/// Toggles a mark over `[start, end)`: if any mark of [type] covers the whole
/// range, remove it; otherwise apply it.
RichTextBlock toggleMark(RichTextBlock block, MarkType type, int start, int end,
    {Map<String, dynamic> attrs = const {}}) {
  final covers = block.marks.any((m) =>
      m.type == type && m.start <= start && m.end >= end);
  if (covers) {
    return removeMark(block, type, start, end);
  }
  return applyMark(block, type, start, end, attrs: attrs);
}

/// Checks whether a mark of [type] covers the entire `[start, end)` range.
bool hasMark(RichTextBlock block, MarkType type, int start, int end) {
  return block.marks.any((m) =>
      m.type == type && m.start <= start && m.end >= end);
}