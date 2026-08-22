/// Controller for the card rich text editor.
///
/// Bridges the [RichTextDocument] model to Flutter's per-paragraph
/// [TextEditingController]s and [FocusNode]s. Each top-level block gets its
/// own controller + focus node, so Chinese IME composition state is handled
/// correctly by Flutter's [EditableText] (each field manages its own
/// composing region). The controller rebuilds the [RichTextDocument] from
/// the text fields on demand, preserving marks.
///
/// Nested blocks ([RichTextBlock.children], used by quote children and list
/// nesting) get one editing level of their own: each child is backed by its
/// own [RichTextBlockController] + [FocusNode], and [flushToDocument] reads
/// child text back into the model. Deeper nesting is preserved by the model
/// and projection but not edited this round.
library;

import 'package:flutter/widgets.dart';

import 'package:memex/ui/whiteboard/fonts.dart';

import 'rich_text_asset_ref.dart';
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
    return TextSpan(
        style: effective,
        children: children.isEmpty ? null : children);
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
        // Inline code uses the Cascadia Code token (see lib/ui/whiteboard/fonts.dart).
        s = s.copyWith(
          fontFamily: richTextCodeFamily,
          fontFamilyFallback: richTextCodeFallback,
        );
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

/// A nested (child) block's editing state.
class _ChildEditState {
  final RichTextBlockController controller;
  final FocusNode focusNode;
  RichTextBlock block;

  _ChildEditState(this.block)
      : controller = RichTextBlockController(block: block),
        focusNode = FocusNode();
}

class _BlockEditState {
  final RichTextBlockController controller;
  final FocusNode focusNode;
  RichTextBlock block;
  final List<_ChildEditState> children = [];

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

  /// Number of editable child blocks nested under the block at [parentIndex].
  int childCount(int parentIndex) => _states[parentIndex].children.length;

  /// Returns the child block at `(parentIndex, childIndex)`.
  RichTextBlock childBlockAt(int parentIndex, int childIndex) =>
      _states[parentIndex].children[childIndex].block;

  /// Returns the TextEditingController for the child at
  /// `(parentIndex, childIndex)`.
  TextEditingController childControllerFor(int parentIndex, int childIndex) =>
      _states[parentIndex].children[childIndex].controller;

  /// Returns the FocusNode for the child at `(parentIndex, childIndex)`.
  FocusNode childFocusNodeFor(int parentIndex, int childIndex) =>
      _states[parentIndex].children[childIndex].focusNode;

  /// Rebuilds the [RichTextDocument] from the current text field values,
  /// preserving marks and attrs (including children). Call this before
  /// reading [document] after the user has typed.
  RichTextDocument flushToDocument() {
    final blocks = <RichTextBlock>[];
    for (final s in _states) {
      final children = <RichTextBlock>[
        for (final c in s.children)
          c.block.copyWith(text: c.controller.text),
      ];
      blocks.add(s.block.copyWith(
        text: s.controller.text,
        children: children.isEmpty ? null : children,
      ));
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

  /// Replaces the top-level blocks from the continuous document surface.
  ///
  /// The UI owns selection and IME composition while an edit is in progress;
  /// this method only mirrors the serializable block document. Rebuilding the
  /// legacy per-block states keeps the existing storage, history, media and
  /// migration APIs compatible without making block boundaries separate text
  /// inputs again.
  void replaceContinuousBlocks(List<RichTextBlock> blocks) {
    final normalized = blocks.isEmpty
        ? const [RichTextBlock(type: BlockType.paragraph)]
        : List<RichTextBlock>.unmodifiable(blocks);
    _doc = _doc.copyWith(
      blocks: normalized,
      assetRefs: _usedAssetRefs(normalized, _doc.assetRefs),
    );
    _syncStates();
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

  /// Toggles an inline mark over a selection in a nested child block.
  void applyMarkToChild(int parentIndex, int childIndex, MarkType type,
      int start, int end,
      {Map<String, dynamic> attrs = const {}}) {
    final c = _states[parentIndex].children[childIndex];
    c.block = c.block.copyWith(text: c.controller.text);
    c.block = toggleMark(c.block, type, start, end, attrs: attrs);
    c.controller.updateBlock(c.block);
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

  /// Inserts a new child block after `(parentIndex, childIndex)` inside the
  /// parent's children list, and returns the inserted child index.
  ///
  /// [childIndex] may be `-1` to insert at the front.
  int insertChildAfter(
      int parentIndex, int childIndex, RichTextBlock block) {
    final newDoc = flushToDocument();
    final parent = newDoc.blocks[parentIndex];
    final children = List<RichTextBlock>.from(parent.children);
    final insertAt = (childIndex + 1).clamp(0, children.length);
    children.insert(insertAt, block);
    final blocks = List<RichTextBlock>.from(newDoc.blocks);
    blocks[parentIndex] = parent.copyWith(children: children);
    _doc = newDoc.copyWith(blocks: blocks);
    _history.commit(_doc);
    _syncStates();
    _dirty = true;
    notifyListeners();
    return insertAt;
  }

  /// Deletes the child block at `(parentIndex, childIndex)`.
  void deleteChild(int parentIndex, int childIndex) {
    final newDoc = flushToDocument();
    final parent = newDoc.blocks[parentIndex];
    final children = List<RichTextBlock>.from(parent.children);
    if (children.isEmpty || childIndex >= children.length) return;
    children.removeAt(childIndex);
    final blocks = List<RichTextBlock>.from(newDoc.blocks);
    blocks[parentIndex] = parent.copyWith(children: children);
    _doc = newDoc.copyWith(
      blocks: blocks,
      assetRefs: _usedAssetRefs(blocks, newDoc.assetRefs),
    );
    _history.commit(_doc);
    _syncStates();
    _dirty = true;
    notifyListeners();
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

  /// Changes the type of the child block at `(parentIndex, childIndex)`.
  void setChildBlockType(int parentIndex, int childIndex, BlockType type,
      {Map<String, dynamic> attrs = const {}}) {
    final c = _states[parentIndex].children[childIndex];
    c.block =
        c.block.copyWith(type: type, attrs: {...c.block.attrs, ...attrs});
    c.controller.updateBlock(c.block);
    _dirty = true;
    notifyListeners();
  }

  /// Indents a list block at [index] (depth +1, clamped to 8). When
  /// [childIndex] is given, targets the nested child instead of the
  /// top-level block. Returns the new depth, or null when the block is not a
  /// list / already at the bound.
  int? indentListBlock(int index, {int? childIndex}) =>
      _adjustListDepth(index, childIndex: childIndex, delta: 1);

  /// Outdents a list block at [index] (depth -1, clamped to 0). When
  /// [childIndex] is given, targets the nested child instead of the
  /// top-level block. Returns the new depth, or null when the block is not a
  /// list / already at the bound.
  int? outdentListBlock(int index, {int? childIndex}) =>
      _adjustListDepth(index, childIndex: childIndex, delta: -1);

  int? _adjustListDepth(int index, {int? childIndex, required int delta}) {
    if (childIndex != null) {
      final c = _states[index].children[childIndex];
      if (c.block.type != BlockType.list) return null;
      final current = c.block.listDepth;
      final next = (current + delta).clamp(0, 8);
      if (next == current) return null;
      c.block = c.block.copyWith(
        attrs: {...c.block.attrs, 'depth': next},
      );
      c.controller.updateBlock(c.block);
      _history.commit(flushToDocument(), coalesce: false);
      _dirty = true;
      notifyListeners();
      return next;
    }
    final s = _states[index];
    if (s.block.type != BlockType.list) return null;
    final current = s.block.listDepth;
    final next = (current + delta).clamp(0, 8);
    if (next == current) return null;
    s.block = s.block.copyWith(
      attrs: {...s.block.attrs, 'depth': next},
    );
    s.controller.updateBlock(s.block);
    _history.commit(flushToDocument(), coalesce: false);
    _dirty = true;
    notifyListeners();
    return next;
  }

  /// Deletes the block at [index]. Ensures at least one block remains.
  void deleteBlock(int index) {
    if (_states.length <= 1) {
      // Clear the only block instead of removing it.
      _states.first.controller.clear();
      _states.first.children.clear();
      _states.first.block = const RichTextBlock(type: BlockType.paragraph);
      _dirty = true;
      notifyListeners();
      return;
    }
    final newDoc = flushToDocument();
    final blocks = List<RichTextBlock>.from(newDoc.blocks);
    blocks.removeAt(index);
    _doc = newDoc.copyWith(
      blocks: blocks,
      assetRefs: _usedAssetRefs(blocks, newDoc.assetRefs),
    );
    _history.commit(_doc);
    _syncStates();
    _dirty = true;
    notifyListeners();
  }

  /// Keeps only the asset refs still referenced by at least one block
  /// (garbage collection of orphaned objects after block deletion).
  static List<RichTextAssetRef> _usedAssetRefs(
    List<RichTextBlock> blocks,
    List<RichTextAssetRef> refs,
  ) {
    final used = <String>{};
    void visit(RichTextBlock b) {
      final id = b.assetRefId;
      if (id != null) used.add(id);
      for (final c in b.children) {
        visit(c);
      }
    }

    for (final b in blocks) {
      visit(b);
    }
    return [
      for (final r in refs)
        if (used.contains(r.refId)) r,
    ];
  }

  /// Replaces the entire document (e.g. after loading from storage).
  void loadDocument(RichTextDocument doc) {
    _doc = doc;
    _history.reset(doc);
    _syncStates();
    _dirty = false;
    notifyListeners();
  }

  /// Adds a stable asset reference to the document (idempotent by refId).
  /// Used by media import; the document JSON then only carries the object
  /// ref, never the temporary source path.
  void appendAssetRef(RichTextAssetRef ref) {
    final refs = List<RichTextAssetRef>.from(_doc.assetRefs);
    if (refs.any((r) => r.refId == ref.refId)) return;
    refs.add(ref);
    _doc = _doc.copyWith(assetRefs: refs);
    _dirty = true;
    notifyListeners();
  }

  /// Syncs the per-block editing states from [_doc].
  void _syncStates() {
    // Dispose old states.
    for (final s in _states) {
      s.controller.dispose();
      s.focusNode.dispose();
      for (final c in s.children) {
        c.controller.dispose();
        c.focusNode.dispose();
      }
    }
    _states.clear();
    if (_doc.blocks.isEmpty) {
      _doc = RichTextDocument.empty();
    }
    for (final block in _doc.blocks) {
      final state = _BlockEditState(block);
      for (final child in block.children) {
        state.children.add(_ChildEditState(child));
      }
      _states.add(state);
    }
  }

  @override
  void dispose() {
    for (final s in _states) {
      s.controller.dispose();
      s.focusNode.dispose();
      for (final c in s.children) {
        c.controller.dispose();
        c.focusNode.dispose();
      }
    }
    _history.dispose();
    super.dispose();
  }
}
