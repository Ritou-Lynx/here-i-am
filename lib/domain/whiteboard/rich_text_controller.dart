/// Controller for the card rich text editor.
///
/// Bridges the [RichTextDocument] model to Flutter's per-paragraph
/// [TextEditingController]s and [FocusNode]s. Each top-level block gets its
/// own controller + focus node, so Chinese IME composition state is handled
/// correctly by Flutter's [EditableText] (each field manages its own
/// composing region). The controller rebuilds the [RichTextDocument] from
/// the text fields on demand, preserving marks.
library;

import 'package:flutter/widgets.dart';

import 'rich_text_document.dart';
import 'rich_text_history.dart';
import 'rich_text_marks.dart';

/// A single block's editing state.
/// A [TextEditingController] that renders a block's inline marks into a
/// [TextSpan]. Editing keeps Flutter's native composing-region (IME) handling
/// because it stays a real [TextEditingController].
class RichTextBlockController extends TextEditingController {
  RichTextBlock _block;
  final TextStyle baseStyle;
  final Color linkColor;

  RichTextBlockController({
    required RichTextBlock block,
    this.baseStyle = const TextStyle(),
    this.linkColor = const Color(0xFF6E7541),
  })  : _block = block,
        super(text: block.text);

  /// The marks currently rendered by this controller.
  List<RichTextMark> get marks => _block.marks;

  /// Updates the rendered block (and thus its marks) without touching text.
  void updateBlock(RichTextBlock block) {
    _block = block;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final effective = (style ?? baseStyle);
    final text = value.text;
    final len = text.length;
    // Build a sorted list of boundary points from mark ranges.
    final boundaries = <int>{0, len};
    for (final m in _block.marks) {
      boundaries.add(m.start.clamp(0, len));
      boundaries.add(m.end.clamp(0, len));
    }
    final points = boundaries.toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (start >= end) continue;
      final segText = text.substring(start, end);
      var segStyle = effective;
      for (final m in _block.marks) {
        if (m.end <= start || m.start >= end) continue;
        segStyle = _applyMarkStyle(segStyle, m);
      }
      children.add(TextSpan(text: segText, style: segStyle));
    }
    if (children.isEmpty && text.isNotEmpty) {
      children.add(TextSpan(text: text, style: effective));
    }
    // Flutter applies the composing underline itself when withComposing is
    // true; we just forward our styled children.
    return TextSpan(style: effective, children: children.isEmpty ? null : children);
  }

  TextStyle _applyMarkStyle(TextStyle style, RichTextMark mark) {
    var s = style;
    switch (mark.type) {
      case MarkType.bold:
        s = s.copyWith(fontWeight: FontWeight.bold);
      case MarkType.italic:
        s = s.copyWith(fontStyle: FontStyle.italic);
      case MarkType.underline:
        s = s.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: s.color);
      case MarkType.strikethrough:
        s = s.copyWith(
            decoration: TextDecoration.lineThrough,
            decorationColor: s.color);
      case MarkType.code:
        s = s.copyWith(fontFamily: 'monospace');
      case MarkType.link:
        s = s.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        );
    }
    return s;
  }
}

class _BlockEditState {
  final RichTextBlockController controller;
  final FocusNode focusNode;
  RichTextBlock block;

  _BlockEditState(this.block)
      : controller = RichTextBlockController(block: block),
        focusNode = FocusNode();
}

/// Controls a [RichTextDocument] for editing.
class RichTextEditingController extends ChangeNotifier {
  RichTextDocument _doc;
  late final RichTextDocumentHistory _history;
  final List<_BlockEditState> _states = [];
  bool _dirty = false;

  RichTextEditingController(RichTextDocument initial)
      : _doc = initial {
    _history = RichTextDocumentHistory(initial);
    _syncStates();
  }

  RichTextDocument get document => _doc;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  bool get isDirty => _dirty;

  /// Number of top-level blocks.
  int get blockCount => _states.length;

  /// Returns the TextEditingController for the block at [index].
  TextEditingController controllerFor(int index) =>
      _states[index].controller;

  /// Returns the FocusNode for the block at [index].
  FocusNode focusNodeFor(int index) => _states[index].focusNode;

  /// Returns the block at [index] (current model state).
  RichTextBlock blockAt(int index) => _states[index].block;

  /// Rebuilds the [RichTextDocument] from the current text field values,
  /// preserving marks and attrs. Call this before reading [document] after
  /// the user has typed.
  RichTextDocument flushToDocument() {
    final blocks = <RichTextBlock>[];
    for (final s in _states) {
      blocks.add(s.block.copyWith(text: s.controller.text));
    }
    _doc = _doc.copyWith(blocks: blocks);
    return _doc;
  }

  /// Commits the current state to history (undo checkpoint).
  void commitHistory({bool coalesce = true}) {
    flushToDocument();
    _history.commit(_doc, coalesce: coalesce);
    _dirty = true;
    notifyListeners();
  }

  /// Undo. Returns true if an undo happened.
  bool undo() {
    final prev = _history.undo();
    if (prev == null) return false;
    _doc = prev;
    _syncStates();
    _dirty = true;
    notifyListeners();
    return true;
  }

  /// Redo. Returns true if a redo happened.
  bool redo() {
    final next = _history.redo();
    if (next == null) return false;
    _doc = next;
    _syncStates();
    _dirty = true;
    notifyListeners();
    return true;
  }

  /// Marks the document as saved (clean).
  void markSaved() {
    _dirty = false;
    notifyListeners();
  }

  /// Marks the document as having unsaved changes. Called when the user types
  /// so the exit guard knows edits are pending even before a commit.
  void markDirty() {
    if (_dirty) return;
    _dirty = true;
    notifyListeners();
  }

  /// Toggles an inline mark over a selection in a specific block.
  void applyMarkToBlock(int blockIndex, MarkType type, int start, int end,
      {Map<String, dynamic> attrs = const {}}) {
    final s = _states[blockIndex];
    // Sync the model text from the live field before applying marks, so the
    // range math works against what the user actually typed.
    s.block = s.block.copyWith(text: s.controller.text);
    s.block = toggleMark(s.block, type, start, end, attrs: attrs);
    s.controller.updateBlock(s.block);
    _dirty = true;
    notifyListeners();
  }

  /// Inserts a new block after [blockIndex] and returns its index.
  int insertBlockAfter(int blockIndex, RichTextBlock block) {
    final newDoc = flushToDocument();
    final blocks = List<RichTextBlock>.from(newDoc.blocks);
    blocks.insert(blockIndex + 1, block);
    _doc = newDoc.copyWith(blocks: blocks);
    _history.commit(_doc);
    _syncStates();
    _dirty = true;
    notifyListeners();
    return blockIndex + 1;
  }

  /// Changes the type of the block at [index] (e.g. paragraph → heading).
  void setBlockType(int index, BlockType type,
      {Map<String, dynamic> attrs = const {}}) {
    final s = _states[index];
    s.block = s.block.copyWith(type: type, attrs: {...s.block.attrs, ...attrs});
    s.controller.updateBlock(s.block);
    _dirty = true;
    notifyListeners();
  }

  /// Deletes the block at [index]. Ensures at least one block remains.
  void deleteBlock(int index) {
    if (_states.length <= 1) {
      // Clear the only block instead of removing it.
      _states.first.controller.clear();
      _states.first.block = const RichTextBlock(type: BlockType.paragraph);
      _dirty = true;
      notifyListeners();
      return;
    }
    final newDoc = flushToDocument();
    final blocks = List<RichTextBlock>.from(newDoc.blocks);
    blocks.removeAt(index);
    _doc = newDoc.copyWith(blocks: blocks);
    _history.commit(_doc);
    _syncStates();
    _dirty = true;
    notifyListeners();
  }

  /// Replaces the entire document (e.g. after loading from storage).
  void loadDocument(RichTextDocument doc) {
    _doc = doc;
    _history.reset(doc);
    _syncStates();
    _dirty = false;
    notifyListeners();
  }

  /// Syncs the per-block editing states from [_doc].
  void _syncStates() {
    // Dispose old states.
    for (final s in _states) {
      s.controller.dispose();
      s.focusNode.dispose();
    }
    _states.clear();
    if (_doc.blocks.isEmpty) {
      _doc = RichTextDocument.empty();
    }
    for (final block in _doc.blocks) {
      _states.add(_BlockEditState(block));
    }
  }

  @override
  void dispose() {
    for (final s in _states) {
      s.controller.dispose();
      s.focusNode.dispose();
    }
    _history.dispose();
    super.dispose();
  }
}