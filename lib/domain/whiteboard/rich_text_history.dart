/// Undo / redo history for [RichTextDocument].
///
/// The history holds a stack of document snapshots. Each [commit] pushes the
/// new document onto the undo stack and clears the redo stack. [undo] pops
/// the current document onto the redo stack and returns the previous one.
/// [redo] reverses that. A coalescing window ([coalesceMs]) merges commits
/// that arrive within the window and differ only trivially (e.g. consecutive
/// character insertions in the same block), so the user doesn't undo one
/// keystroke at a time.
library;

import 'dart:async';

import 'rich_text_document.dart';

class RichTextDocumentHistory {
  final Duration coalesceWindow;
  final List<RichTextDocument> _undo = [];
  final List<RichTextDocument> _redo = [];
  RichTextDocument _current;
  DateTime _lastCommitAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _coalesceTimer;

  RichTextDocumentHistory(RichTextDocument initial, {this.coalesceWindow = const Duration(milliseconds: 800)})
      : _current = initial;

  RichTextDocument get current => _current;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Commits a new document state.
  ///
  /// If [coalesce] is true and the commit arrives within [coalesceWindow] of
  /// the previous one, the previous entry is replaced instead of stacking,
  /// collapsing rapid edits into a single undo step.
  void commit(RichTextDocument next, {bool coalesce = true}) {
    final now = DateTime.now();
    if (coalesce &&
        _undo.isNotEmpty &&
        now.difference(_lastCommitAt) < coalesceWindow) {
      // Coalesce: keep the previous undo entry (the pre-edit state) and
      // just advance current. The intermediate states are discarded so
      // one undo returns to the pre-edit snapshot.
    } else {
      _undo.add(_current);
    }
    _current = next;
    _redo.clear();
    _lastCommitAt = now;
  }

  /// Undo: returns the previous document, or null if nothing to undo.
  RichTextDocument? undo() {
    if (!canUndo) return null;
    _redo.add(_current);
    _current = _undo.removeLast();
    return _current;
  }

  /// Redo: returns the next document, or null if nothing to redo.
  RichTextDocument? redo() {
    if (!canRedo) return null;
    _undo.add(_current);
    _current = _redo.removeLast();
    return _current;
  }

  /// Resets the history to a new initial document, clearing all stacks.
  void reset(RichTextDocument doc) {
    _undo.clear();
    _redo.clear();
    _current = doc;
    _lastCommitAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void dispose() {
    _coalesceTimer?.cancel();
  }
}