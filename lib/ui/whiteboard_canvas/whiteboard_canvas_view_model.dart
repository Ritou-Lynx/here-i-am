/// Whiteboard canvas ViewModel — manages undo/redo, selection, viewport
/// and coordinates between the [FlutterCanvasAdapter] and the UI layer.
///
/// This ViewModel does NOT import MemexRouter or any Memex-specific code.
/// It only depends on the W0 shared contracts and the [FlutterCanvasAdapter].
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

import 'engine/flutter_canvas_adapter.dart';

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

  /// Operations log for audit display (all operations since load).
  final List<WhiteboardOperation> _operationLog = [];

  /// Invoked when the user requests to save the snapshot.
  VoidCallback? onSaveRequested;

  WhiteboardCanvasViewModel({
    required WhiteboardSnapshot initialSnapshot,
    required this.boardId,
  })  : _adapter = FlutterCanvasAdapter(initialSnapshot),
        _viewport = initialSnapshot.viewport {
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
  bool get canUndo => _undoStack.length > 1;
  bool get canRedo => _redoStack.isNotEmpty;
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
    final items = _adapter.getBoardState(boardId).nodes;
    final ids = <String>[];
    for (final node in items) {
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

  void selectAll() {
    final ids = _adapter
        .getBoardState(boardId)
        .nodes
        .map((n) => n.itemId);
    _selection.selectAll(ids);
    notifyListeners();
  }

  // ── Operations ─────────────────────────────────────────────────────

  void placeCard({
    required String cardId,
    double x = 120,
    double y = 100,
    double width = 260,
    double height = 200,
  }) {
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
    if (_selection.isEmpty) return;
    final deltas = <String, math.Point<double>>{};
    for (final id in _selection.selectedItemIds) {
      deltas[id] = math.Point(dx, dy);
    }
    _adapter.moveItems(boardId: boardId, deltas: deltas);
    notifyListeners();
  }

  void moveItems(Map<String, math.Point<double>> deltas) {
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
    if (_selection.isEmpty) return;
    _adapter.removeItems(
      boardId: boardId,
      itemIds: _selection.selectedItemIds.toList(),
    );
    _selection.clear();
    notifyListeners();
  }

  void removeItems(List<String> itemIds) {
    _adapter.removeItems(boardId: boardId, itemIds: itemIds);
    for (final id in itemIds) {
      _selection.removeId(id);
    }
    notifyListeners();
  }

  void bringSelectedItemToFront() {
    if (_selection.isEmpty) return;
    for (final id in _selection.selectedItemIds) {
      _adapter.bringToFront(boardId: boardId, itemId: id);
    }
    notifyListeners();
  }

  void createGroupFromSelection({String name = ''}) {
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
    _adapter.removeGroup(boardId: boardId, groupId: groupId);
    notifyListeners();
  }

  void createEdge({
    required String fromItemId,
    required String toItemId,
    EdgeDirection direction = EdgeDirection.undirected,
    String? label,
  }) {
    _adapter.createEdge(
      boardId: boardId,
      fromItemId: fromItemId,
      toItemId: toItemId,
      direction: direction,
      label: label,
    );
    notifyListeners();
  }

  void removeEdge(String edgeId) {
    _adapter.removeEdge(boardId: boardId, edgeId: edgeId);
    notifyListeners();
  }

  // ── Undo / Redo ────────────────────────────────────────────────────

  void undo() {
    if (!canUndo) return;
    final current = _undoStack.removeLast();
    _redoStack.add(current);
    final previous = _undoStack.last;
    _adapter.load(previous.snapshot);
    _viewport = previous.snapshot.viewport;
    _selection.clear();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    _adapter.load(next.snapshot);
    _viewport = next.snapshot.viewport;
    _selection.clear();
    notifyListeners();
  }

  // ── Read-only mode ─────────────────────────────────────────────────

  void setReadonly(bool readonly) {
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

  void _handleOperation(WhiteboardOperation operation) {
    _operationLog.add(operation);
    final currentSnapshot = _adapter.exportSnapshot();
    _undoStack.add(UndoRedoEntry(
      snapshot: currentSnapshot,
      operation: operation,
    ));
    _redoStack.clear();
  }
}