/// Whiteboard canvas ViewModel — manages undo/redo, selection, viewport
/// and coordinates between the [FlutterCanvasAdapter] and the UI layer.
///
/// This ViewModel does NOT import MemexRouter or any Memex-specific code.
/// It only depends on the W0 shared contracts and the [FlutterCanvasAdapter].
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

import 'engine/flutter_canvas_adapter.dart';
import 'interactions/ui_intent.dart';

/// A snapshot of the undo/redo state, capturing both the [WhiteboardSnapshot]
/// and the operation that produced it (for audit display).
class UndoRedoEntry {
  final WhiteboardSnapshot snapshot;
  final WhiteboardOperation? operation;

  const UndoRedoEntry({required this.snapshot, this.operation});
}

/// Selection state on the canvas.
class CanvasSelection extends ChangeNotifier {
  final Set<String> _selectedItemIds = {};

  Set<String> get selectedItemIds => Set.unmodifiable(_selectedItemIds);

  int get length => _selectedItemIds.length;
  bool get isEmpty => _selectedItemIds.isEmpty;
  bool get isNotEmpty => _selectedItemIds.isNotEmpty;
  bool get isMultiple => _selectedItemIds.length > 1;

  bool isSelected(String itemId) => _selectedItemIds.contains(itemId);

  void select(String itemId) {
    _selectedItemIds
      ..clear()
      ..add(itemId);
    notifyListeners();
  }

  void addToSelection(String itemId) {
    _selectedItemIds.add(itemId);
    notifyListeners();
  }

  void toggleSelection(String itemId) {
    if (_selectedItemIds.contains(itemId)) {
      _selectedItemIds.remove(itemId);
    } else {
      _selectedItemIds.add(itemId);
    }
    notifyListeners();
  }

  void selectAll(Iterable<String> itemIds) {
    _selectedItemIds
      ..clear()
      ..addAll(itemIds);
    notifyListeners();
  }

  void selectMany(Iterable<String> itemIds) {
    _selectedItemIds.addAll(itemIds);
    notifyListeners();
  }

  void clear() {
    if (_selectedItemIds.isEmpty) return;
    _selectedItemIds.clear();
    notifyListeners();
  }

  void removeId(String itemId) {
    _selectedItemIds.remove(itemId);
    notifyListeners();
  }
}

/// The main ViewModel for the whiteboard canvas.
///
/// Owns the [FlutterCanvasAdapter], undo/redo stack, selection and viewport.
/// UI widgets listen to this and call its methods in response to gestures.
class WhiteboardCanvasViewModel extends ChangeNotifier {
  final FlutterCanvasAdapter _adapter;
  final String boardId;

  final List<UndoRedoEntry> _undoStack = [];
  final List<UndoRedoEntry> _redoStack = [];

  late CanvasSelection _selection;
  BoardViewport _viewport;
  bool _readonly = false;

  String? _selectedEdgeId;

  /// Operations log for audit display (all operations since load).
  final List<WhiteboardOperation> _operationLog = [];

  /// Repository-owned Card projections. Undo/redo owns board layout only;
  /// restoring an old layout must never restore stale Card title/body data.
  final Map<String, CardContract> _currentCards = {};

  /// Logical-action grouping: while a gesture runs (drag / resize / rotate /
  /// edge retarget), the adapter operations it produces are buffered and
  /// committed as ONE undo step on [endLogicalAction]. This is the
  /// Huabu-style "one logical action → one undo step" rule; a failed or
  /// cancelled action restores the baseline snapshot with no side effects.
  int _logicalActionDepth = 0;
  WhiteboardSnapshot? _logicalActionBaseline;
  final List<WhiteboardOperation> _bufferedOperations = [];

  /// Invoked when the user requests to save the snapshot.
  VoidCallback? onSaveRequested;

  WhiteboardCanvasViewModel({
    required WhiteboardSnapshot initialSnapshot,
    required this.boardId,
  })  : _adapter = FlutterCanvasAdapter(initialSnapshot),
        _viewport = initialSnapshot.viewport {
    _currentCards.addEntries(
      initialSnapshot.cards.map((card) => MapEntry(card.cardId, card)),
    );
    _selection = CanvasSelection();
    _undoStack.add(UndoRedoEntry(snapshot: initialSnapshot));
    _adapter.onOperation(_handleOperation);
  }

  // ── Snapshot / state access ────────────────────────────────────────

  WhiteboardSnapshot get snapshot => _adapter.exportSnapshot();
  CanvasBoardState get boardState => _adapter.getBoardState(boardId);
  CanvasSelection get selection => _selection;
  BoardViewport get viewport => _viewport;
  bool get isReadonly => _readonly;
  bool get canUndo => !_readonly && _undoStack.length > 1;
  bool get canRedo => !_readonly && _redoStack.isNotEmpty;
  String? get selectedEdgeId => _selectedEdgeId;
  BoardEdge? get selectedEdge {
    final id = _selectedEdgeId;
    if (id == null) return null;
    return boardState.edges
        .cast<CanvasEdgeNode?>()
        .firstWhere((edge) => edge?.edgeId == id, orElse: () => null)
        ?.edge;
  }

  bool get isInLogicalAction => _logicalActionDepth > 0;
  List<WhiteboardOperation> get operationLog =>
      List.unmodifiable(_operationLog);

  // ── Viewport ───────────────────────────────────────────────────────

  void panViewport(double dx, double dy) {
    _viewport = BoardViewport(
      centerX: _viewport.centerX - dx / _viewport.zoom,
      centerY: _viewport.centerY - dy / _viewport.zoom,
      zoom: _viewport.zoom,
    );
    notifyListeners();
  }

  void zoomViewport(double factor, math.Point<double> focalPoint) {
    final newZoom = (_viewport.zoom * factor).clamp(0.25, 4.0);
    _viewport = BoardViewport(
      centerX: _viewport.centerX,
      centerY: _viewport.centerY,
      zoom: newZoom,
    );
    notifyListeners();
  }

  void setViewport(BoardViewport viewport) {
    _viewport = viewport;
    _adapter.updateViewport(boardId: boardId, viewport: viewport);
    notifyListeners();
  }

  void resetViewport() {
    _viewport = const BoardViewport(centerX: 0, centerY: 0, zoom: 1);
    notifyListeners();
  }

  // ── Selection ──────────────────────────────────────────────────────

  void selectItem(String itemId) {
    _selection.select(itemId);
    notifyListeners();
  }

  void toggleItemSelection(String itemId) {
    _selection.toggleSelection(itemId);
    notifyListeners();
  }

  void addToSelection(String itemId) {
    _selection.addToSelection(itemId);
    notifyListeners();
  }

  void selectInRect(math.Rectangle<double> canvasRect) {
    final state = _adapter.getBoardState(boardId);
    final hidden = _hiddenItemIds(state);
    final ids = <String>[];
    for (final node in state.nodes) {
      if (hidden.contains(node.itemId)) continue;
      final itemRect = math.Rectangle(
        node.item.x,
        node.item.y,
        node.item.width,
        node.item.height,
      );
      if (canvasRect.intersects(itemRect)) {
        ids.add(node.itemId);
      }
    }
    _selection.selectAll(ids);
    notifyListeners();
  }

  void clearSelection() {
    _selection.clear();
    notifyListeners();
  }

  void selectAll([Set<String> exclude = const {}]) {
    final ids = _adapter
        .getBoardState(boardId)
        .nodes
        .where((n) => !exclude.contains(n.itemId))
        .map((n) => n.itemId);
    _selection.selectAll(ids);
    notifyListeners();
  }

  // ── Logical-action grouping ───────────────────────────────────────────

  /// Starts a logical action: subsequent adapter operations are buffered
  /// instead of each becoming an undo step.
  void beginLogicalAction() {
    if (_readonly) return;
    _logicalActionDepth++;
    if (_logicalActionDepth == 1) {
      _logicalActionBaseline = _adapter.exportSnapshot();
      _bufferedOperations.clear();
    }
  }

  /// Ends a logical action, committing all buffered operations as a single
  /// undo step.
  void endLogicalAction() {
    if (_logicalActionDepth == 0) return;
    _logicalActionDepth--;
    if (_logicalActionDepth == 0) {
      _commitUndoStep();
      _bufferedOperations.clear();
      _logicalActionBaseline = null;
    }
  }

  /// Cancels a logical action: restores the snapshot captured at
  /// [beginLogicalAction], discards buffered operations from both the undo
  /// pipeline and the audit log — no state change, no side effects, no undo
  /// entry. Used when a gesture fails or is aborted.
  void cancelLogicalAction() {
    if (_logicalActionDepth == 0) return;
    _logicalActionDepth = 0;
    final baseline = _logicalActionBaseline;
    if (baseline != null) {
      _adapter.load(_overlayCurrentCards(baseline));
      _pruneEdgeSelection();
    }
    for (final op in _bufferedOperations) {
      _operationLog.remove(op);
    }
    _bufferedOperations.clear();
    _logicalActionBaseline = null;
    notifyListeners();
  }

  // ── UiIntent routing ──────────────────────────────────────────────────

  /// Resolves a user [UiIntent] into adapter operations — the only entry
  /// point for UI gestures. Returns false when the intent could not be
  /// applied (readonly / nothing to do / invalid target); in that case the
  /// state is unchanged.
  bool handleIntent(UiIntent intent) {
    if (_readonly) return false;
    switch (intent) {
      case SelectItemIntent(:final itemId):
        _selection.select(itemId);
        notifyListeners();
        return true;
      case ToggleItemSelectionIntent(:final itemId):
        _selection.toggleSelection(itemId);
        notifyListeners();
        return true;
      case MarqueeSelectIntent(:final canvasRect):
        selectInRect(canvasRect);
        return true;
      case SelectAllIntent(:final exclude):
        selectAll(exclude);
        return true;
      case ClearSelectionIntent():
        clearSelection();
        return true;
      case MoveSelectionIntent(:final dx, :final dy):
        moveSelectedItems(dx, dy);
        return true;
      case NudgeSelectionIntent(:final dx, :final dy):
        if (_selection.isEmpty) return false;
        beginLogicalAction();
        moveSelectedItems(dx, dy);
        endLogicalAction();
        return true;
      case DeleteSelectionIntent():
        if (_selectedEdgeId != null) {
          removeEdge(_selectedEdgeId!);
          return true;
        }
        if (_selection.isEmpty) return false;
        removeSelectedItems();
        return true;
      case RotateItemIntent(:final itemId, :final rotationDegrees):
        rotateItem(itemId: itemId, rotationDegrees: rotationDegrees);
        return true;
      case ResizeItemIntent(:final itemId, :final width, :final height):
        resizeItem(itemId: itemId, width: width, height: height);
        return true;
      case ToggleGroupCollapsedIntent(:final groupId):
        toggleGroupCollapsed(groupId);
        return true;
      case RetargetEdgeIntent(
          :final edgeId,
          :final fromItemId,
          :final toItemId
        ):
        return retargetEdge(
          edgeId: edgeId,
          fromItemId: fromItemId,
          toItemId: toItemId,
        );
      case SelectEdgeIntent(:final edgeId):
        _selectedEdgeId = edgeId;
        notifyListeners();
        return true;
      case ClearEdgeSelectionIntent():
        _selectedEdgeId = null;
        notifyListeners();
        return true;
    }
  }

  // ── Operations ─────────────────────────────────────────────────────

  void placeCard({
    required String cardId,
    double x = 120,
    double y = 100,
    double width = 260,
    double height = 200,
  }) {
    if (_readonly) return;
    final item = _adapter.placeCard(
      boardId: boardId,
      cardId: cardId,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    if (item != null) {
      _selection.select(item.itemId);
    }
    notifyListeners();
  }

  void moveSelectedItems(double dx, double dy) {
    if (_readonly) return;
    if (_selection.isEmpty) return;
    final deltas = <String, math.Point<double>>{};
    for (final id in _selection.selectedItemIds) {
      deltas[id] = math.Point(dx, dy);
    }
    _adapter.moveItems(boardId: boardId, deltas: deltas);
    notifyListeners();
  }

  void moveItems(Map<String, math.Point<double>> deltas) {
    if (_readonly) return;
    if (deltas.isEmpty) return;
    _adapter.moveItems(boardId: boardId, deltas: deltas);
    notifyListeners();
  }

  void resizeItem({
    required String itemId,
    required double width,
    required double height,
    double? x,
    double? y,
  }) {
    if (_readonly) return;
    _adapter.resizeItem(
      boardId: boardId,
      itemId: itemId,
      width: width,
      height: height,
      x: x,
      y: y,
    );
    notifyListeners();
  }

  void removeSelectedItems() {
    if (_readonly) return;
    if (_selection.isEmpty) return;
    _adapter.removeItems(
      boardId: boardId,
      itemIds: _selection.selectedItemIds.toList(),
    );
    _selection.clear();
    notifyListeners();
  }

  void removeItems(List<String> itemIds) {
    if (_readonly) return;
    _adapter.removeItems(boardId: boardId, itemIds: itemIds);
    for (final id in itemIds) {
      _selection.removeId(id);
    }
    notifyListeners();
  }

  void bringSelectedItemToFront() {
    if (_readonly) return;
    if (_selection.isEmpty) return;
    for (final id in _selection.selectedItemIds) {
      _adapter.bringToFront(boardId: boardId, itemId: id);
    }
    notifyListeners();
  }

  void createGroupFromSelection({String name = ''}) {
    if (_readonly) return;
    if (_selection.isEmpty) return;
    final group = _adapter.createGroup(
      boardId: boardId,
      itemIds: _selection.selectedItemIds.toList(),
      name: name,
    );
    if (group != null) {
      _selection.clear();
    }
    notifyListeners();
  }

  void removeGroup(String groupId) {
    if (_readonly) return;
    _adapter.removeGroup(boardId: boardId, groupId: groupId);
    notifyListeners();
  }

  bool createEdge({
    required String fromItemId,
    required String toItemId,
    EdgeDirection direction = EdgeDirection.undirected,
    String? label,
  }) {
    if (_readonly) return false;
    final edge = _adapter.createEdge(
      boardId: boardId,
      fromItemId: fromItemId,
      toItemId: toItemId,
      direction: direction,
      label: label,
    );
    if (edge == null) return false;
    _selectedEdgeId = edge.edgeId;
    notifyListeners();
    return true;
  }

  bool updateEdge({
    required String edgeId,
    required EdgeDirection direction,
    String? label,
  }) {
    if (_readonly) return false;
    final updated = _adapter.updateEdge(
      boardId: boardId,
      edgeId: edgeId,
      direction: direction,
      label: label,
    );
    if (updated) notifyListeners();
    return updated;
  }

  /// Refreshes Repository-owned Card content in the render snapshot without
  /// adding it to the board operation/undo stream.
  void upsertCardContent(CardContract card) {
    _currentCards[card.cardId] = card;
    _adapter.upsertCardContent(card);
    notifyListeners();
  }

  /// Removes a renderer projection after a failed create transaction. This
  /// does not delete Repository data and never enters layout history.
  void removeCardContent(String cardId) {
    _currentCards.remove(cardId);
    _adapter.removeCardContent(cardId);
    notifyListeners();
  }

  void removeEdge(String edgeId) {
    if (_readonly) return;
    _adapter.removeEdge(boardId: boardId, edgeId: edgeId);
    if (_selectedEdgeId == edgeId) _selectedEdgeId = null;
    notifyListeners();
  }

  /// Rotates an item to an absolute rotation (degrees).
  void rotateItem({
    required String itemId,
    required double rotationDegrees,
  }) {
    if (_readonly) return;
    _adapter.rotateItem(
      boardId: boardId,
      itemId: itemId,
      rotationDegrees: rotationDegrees,
    );
    notifyListeners();
  }

  void toggleGroupCollapsed(String groupId) {
    final group = _adapter
        .getBoardState(boardId)
        .groups
        .cast<CanvasGroupNode?>()
        .firstWhere((g) => g?.groupId == groupId, orElse: () => null);
    if (group == null) return;
    setGroupCollapsed(groupId, !group.group.collapsed);
  }

  void setGroupCollapsed(String groupId, bool collapsed) {
    if (_readonly) return;
    _adapter.setGroupCollapsed(
      boardId: boardId,
      groupId: groupId,
      collapsed: collapsed,
    );
    if (collapsed) {
      final members = _adapter
          .getBoardState(boardId)
          .groups
          .where((g) => g.groupId == groupId)
          .expand((g) => g.members)
          .map((m) => m.itemId)
          .toSet();
      for (final id in members) {
        _selection.removeId(id);
      }
    }
    notifyListeners();
  }

  /// Retargets an edge endpoint. Returns false when invalid (self-loop,
  /// unknown target, unchanged) — the snapshot is untouched.
  bool retargetEdge({
    required String edgeId,
    String? fromItemId,
    String? toItemId,
  }) {
    if (_readonly) return false;
    final ok = _adapter.retargetEdge(
      boardId: boardId,
      edgeId: edgeId,
      fromItemId: fromItemId,
      toItemId: toItemId,
    );
    if (ok) notifyListeners();
    return ok;
  }

  /// Creates a new board in the snapshot (BoardTargetPicker "新建白板").
  /// Returns the created board.
  Board createBoard(String name) {
    if (_readonly) {
      throw StateError('只读白板不能新建白板');
    }
    final board = Board(
      boardId: StableId.generate('board').value,
      name: name,
      createdAt: DateTime.now(),
    );
    _adapter.addBoard(board);
    notifyListeners();
    return board;
  }

  /// Places a card onto [boardId] at the given canvas position. The board
  /// must already exist in the snapshot.
  BoardItem? placeCardOnBoard({
    required String cardId,
    required String boardId,
    required double x,
    required double y,
  }) {
    if (_readonly) return null;
    final item = _adapter.placeCard(
      boardId: boardId,
      cardId: cardId,
      x: x,
      y: y,
    );
    if (item != null && boardId == this.boardId) {
      _selection.select(item.itemId);
    }
    notifyListeners();
    return item;
  }

  // ── Undo / Redo ────────────────────────────────────────────────────

  void undo() {
    if (_readonly || !canUndo) return;
    cancelLogicalAction();
    final current = _undoStack.removeLast();
    _redoStack.add(current);
    final previous = _undoStack.last;
    _adapter.load(_overlayCurrentCards(previous.snapshot));
    _viewport = previous.snapshot.viewport;
    _selection.clear();
    _selectedEdgeId = null;
    notifyListeners();
  }

  void redo() {
    if (_readonly || !canRedo) return;
    cancelLogicalAction();
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    _adapter.load(_overlayCurrentCards(next.snapshot));
    _viewport = next.snapshot.viewport;
    _selection.clear();
    _selectedEdgeId = null;
    notifyListeners();
  }

  // ── Read-only mode ─────────────────────────────────────────────────

  void setReadonly(bool readonly) {
    if (readonly && _logicalActionDepth > 0) cancelLogicalAction();
    _readonly = readonly;
    _adapter.setReadonly(readonly);
    if (readonly) _selection.clear();
    notifyListeners();
  }

  // ── Persistence ────────────────────────────────────────────────────

  /// Returns the current snapshot for persistence.
  WhiteboardSnapshot exportForSave() => _adapter.exportSnapshot();

  /// Loads a snapshot from persistence, replacing all current state.
  void loadFromSnapshot(WhiteboardSnapshot snapshot) {
    _adapter.load(snapshot);
    _currentCards
      ..clear()
      ..addEntries(
        snapshot.cards.map((card) => MapEntry(card.cardId, card)),
      );
    _viewport = snapshot.viewport;
    _undoStack
      ..clear()
      ..add(UndoRedoEntry(snapshot: snapshot));
    _redoStack.clear();
    _operationLog.clear();
    _selection.clear();
    notifyListeners();
  }

  // ── Internal ───────────────────────────────────────────────────────

  WhiteboardSnapshot _overlayCurrentCards(WhiteboardSnapshot layout) {
    return WhiteboardSnapshot(
      schemaVersion: layout.schemaVersion,
      sources: layout.sources,
      sourceVersions: layout.sourceVersions,
      cards: _currentCards.values.toList(growable: false),
      boards: layout.boards,
      boardItems: layout.boardItems,
      groups: layout.groups,
      groupMembers: layout.groupMembers,
      edges: layout.edges,
      viewport: layout.viewport,
      updatedAt: layout.updatedAt,
    );
  }

  void _handleOperation(WhiteboardOperation operation) {
    _operationLog.add(operation);
    _pruneEdgeSelection();
    _bufferedOperations.add(operation);
    if (_logicalActionDepth > 0) {
      // A gesture is in flight: buffer, commit as one undo step on end.
      return;
    }
    _commitUndoStep();
    _bufferedOperations.clear();
  }

  /// Commits the current snapshot as one undo step. When called at the end
  /// of a logical action, the buffered operations are merged into a single
  /// undo entry; otherwise the single operation produced it.
  void _commitUndoStep() {
    final currentSnapshot = _adapter.exportSnapshot();
    final op = _bufferedOperations.isEmpty
        ? null
        : _bufferedOperations.length == 1
            ? _bufferedOperations.first
            : _mergeOperations(_bufferedOperations);
    _undoStack.add(UndoRedoEntry(
      snapshot: currentSnapshot,
      operation: op,
    ));
    _redoStack.clear();
  }

  /// Merges the operations of one logical action into a single audit entry.
  /// The merged entry keeps the action's kind, actor and target scope and
  /// records the operation count in the payload for audit display.
  WhiteboardOperation _mergeOperations(List<WhiteboardOperation> ops) {
    final first = ops.first;
    final boardIds = ops.map((o) => o.boardId).toSet();
    return WhiteboardOperation(
      operationId: first.operationId,
      boardId: boardIds.length == 1 ? first.boardId : boardId,
      actor: first.actor,
      operationKind: first.operationKind,
      targetIds: {
        for (final op in ops) ...op.targetIds,
      }.toList(),
      payload: {
        'merged_count': ops.length,
        'kinds': [for (final op in ops) op.operationKind.name],
      },
      createdAt: first.createdAt,
    );
  }

  /// Drops the edge selection when the selected edge no longer exists
  /// (e.g. its endpoints were removed).
  void _pruneEdgeSelection() {
    final id = _selectedEdgeId;
    if (id == null) return;
    final stillExists =
        _adapter.exportSnapshot().edges.any((e) => e.edgeId == id);
    if (!stillExists) _selectedEdgeId = null;
  }

  /// Item ids hidden by collapsed groups (not rendered, not selectable).
  Set<String> _hiddenItemIds(CanvasBoardState state) {
    final hidden = <String>{};
    for (final group in state.groups) {
      if (!group.group.collapsed) continue;
      for (final member in group.members) {
        hidden.add(member.itemId);
      }
    }
    return hidden;
  }
}
