/// W1 whiteboard canvas engine adapter.
///
/// Implements the W0-frozen engine adapter boundary
/// (`load / exportSnapshot / onOperation / setReadonly / focusItem`)
/// using a Flutter-native canvas (CustomPainter + Transform + GestureDetector).
///
/// Engine-private node IDs are a 1:1 mapping with product item_ids —
/// in this adapter the key equals the value, because the Flutter canvas
/// uses product IDs directly. The mapping exists to honor the boundary
/// contract; a future engine swap would populate it differently.
library;

import 'dart:math' as math;

import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

/// Callback emitted when the adapter produces a [WhiteboardOperation].
typedef OnOperationCallback = void Function(WhiteboardOperation operation);

/// A renderable card item on the canvas, combining [BoardItem] layout with
/// its referenced [CardContract] content (read-only, not copied).
class CanvasCardNode {
  final BoardItem item;
  final CardContract? card;
  final bool isOrphaned;

  const CanvasCardNode({
    required this.item,
    this.card,
    this.isOrphaned = false,
  });

  String get itemId => item.itemId;
  String get cardId => item.cardId;
}

/// A renderable group on the canvas.
class CanvasGroupNode {
  final BoardGroup group;
  final List<GroupMember> members;

  const CanvasGroupNode({
    required this.group,
    this.members = const [],
  });

  String get groupId => group.groupId;
  bool get collapsed => group.collapsed;
}

/// A renderable edge on the canvas.
class CanvasEdgeNode {
  final BoardEdge edge;
  final BoardItem? fromItem;
  final BoardItem? toItem;

  const CanvasEdgeNode({
    required this.edge,
    this.fromItem,
    this.toItem,
  });

  String get edgeId => edge.edgeId;
}

/// The complete renderable state for one board on the canvas.
class CanvasBoardState {
  final Board board;
  final List<CanvasCardNode> nodes;
  final List<CanvasGroupNode> groups;
  final List<CanvasEdgeNode> edges;
  final BoardViewport viewport;

  const CanvasBoardState({
    required this.board,
    this.nodes = const [],
    this.groups = const [],
    this.edges = const [],
    this.viewport = const BoardViewport(),
  });
}

/// Flutter-native canvas engine adapter.
///
/// Loads a [WhiteboardSnapshot], produces renderable [CanvasBoardState] per
/// board, applies [WhiteboardOperation]s, and exports back to a snapshot.
/// All product IDs are used directly as canvas entity IDs — there is no
/// engine-private ID space, only a trivial identity mapping.
class FlutterCanvasAdapter {
  WhiteboardSnapshot _snapshot;
  bool _readonly = false;
  OnOperationCallback? _onOperation;

  /// Engine-private ID → product item_id mapping. In this adapter it is
  /// an identity map, but it exists to honor the boundary contract.
  final Map<String, String> _engineToProductId = {};

  FlutterCanvasAdapter([WhiteboardSnapshot? initial])
      : _snapshot = initial ?? const WhiteboardSnapshot() {
    _rebuildIdMapping();
  }

  /// Loads a [WhiteboardSnapshot] and rebuilds internal state.
  void load(WhiteboardSnapshot snapshot) {
    _snapshot = snapshot;
    _rebuildIdMapping();
  }

  /// Creates a new snapshot with the specified fields replaced.
  /// This avoids modifying the shared contract types.
  WhiteboardSnapshot _cloneSnapshot({
    List<CardContract>? cards,
    List<Board>? boards,
    List<BoardItem>? boardItems,
    List<BoardGroup>? groups,
    List<GroupMember>? groupMembers,
    List<BoardEdge>? edges,
    BoardViewport? viewport,
  }) {
    return WhiteboardSnapshot(
      schemaVersion: _snapshot.schemaVersion,
      sources: _snapshot.sources,
      sourceVersions: _snapshot.sourceVersions,
      cards: cards ?? _snapshot.cards,
      boards: boards ?? _snapshot.boards,
      boardItems: boardItems ?? _snapshot.boardItems,
      groups: groups ?? _snapshot.groups,
      groupMembers: groupMembers ?? _snapshot.groupMembers,
      edges: edges ?? _snapshot.edges,
      viewport: viewport ?? _snapshot.viewport,
      updatedAt: DateTime.now(),
    );
  }

  /// Exports the current state back to a [WhiteboardSnapshot].
  WhiteboardSnapshot exportSnapshot() => _snapshot;

  /// Sets readonly mode.
  void setReadonly(bool readonly) {
    _readonly = readonly;
  }

  bool get isReadonly => _readonly;

  /// Refreshes card content used by the renderer without creating a canvas
  /// operation. Card content is Repository truth, not board-layout truth, so
  /// this never enters the board undo/audit stream.
  void upsertCardContent(CardContract card) {
    final cards = [..._snapshot.cards];
    final index =
        cards.indexWhere((candidate) => candidate.cardId == card.cardId);
    if (index == -1) {
      cards.add(card);
    } else {
      cards[index] = card;
    }
    _snapshot = _cloneSnapshot(cards: cards);
  }

  /// Removes renderer-only Card content without creating a board operation.
  /// Used only when a just-created Repository Card is compensated after its
  /// BoardItem failed to persist.
  void removeCardContent(String cardId) {
    if (!_snapshot.cards.any((card) => card.cardId == cardId)) return;
    _snapshot = _cloneSnapshot(
      cards: _snapshot.cards.where((card) => card.cardId != cardId).toList(),
    );
  }

  /// Registers a callback for operations produced by this adapter.
  void onOperation(OnOperationCallback callback) {
    _onOperation = callback;
  }

  /// Focuses (centers viewport on) a specific item.
  void focusItem(String itemId) {
    final item = _snapshot.boardItems
        .cast<BoardItem?>()
        .firstWhere((i) => i?.itemId == itemId, orElse: () => null);
    if (item == null) return;
    final newViewport = BoardViewport(
      centerX: item.x + item.width / 2,
      centerY: item.y + item.height / 2,
      zoom: _snapshot.viewport.zoom,
    );
    _applyViewport(item.boardId, newViewport);
  }

  /// Returns the renderable state for a specific board.
  CanvasBoardState getBoardState(String boardId) {
    final board = _snapshot.boards
        .cast<Board?>()
        .firstWhere((b) => b?.boardId == boardId, orElse: () => null);
    if (board == null) {
      return CanvasBoardState(
        board: Board(
          boardId: boardId,
          name: '',
          createdAt: DateTime.now(),
        ),
      );
    }

    final cardMap = {for (final c in _snapshot.cards) c.cardId: c};
    final items = _snapshot.boardItems.where((i) => i.boardId == boardId);
    final nodes = items.map((item) {
      final card = cardMap[item.cardId];
      return CanvasCardNode(
        item: item,
        card: card,
        isOrphaned: card == null,
      );
    }).toList()
      ..sort((a, b) => a.item.zIndex.compareTo(b.item.zIndex));

    final boardGroups = _snapshot.groups.where((g) => g.boardId == boardId);
    final groupNodes = boardGroups.map((group) {
      final members =
          _snapshot.groupMembers.where((m) => m.groupId == group.groupId);
      return CanvasGroupNode(group: group, members: members.toList());
    }).toList();

    final boardEdges = _snapshot.edges.where((e) => e.boardId == boardId);
    final itemMap = {for (final i in _snapshot.boardItems) i.itemId: i};
    final edgeNodes = boardEdges.map((edge) {
      return CanvasEdgeNode(
        edge: edge,
        fromItem: itemMap[edge.fromItemId],
        toItem: itemMap[edge.toItemId],
      );
    }).toList();

    return CanvasBoardState(
      board: board,
      nodes: nodes,
      groups: groupNodes,
      edges: edgeNodes,
      viewport: _snapshot.viewport,
    );
  }

  // ── Operation application methods ──────────────────────────────────

  /// Places a card onto a board as a new [BoardItem].
  /// Returns the created item, or null if board/card doesn't exist.
  BoardItem? placeCard({
    required String boardId,
    required String cardId,
    double x = 120,
    double y = 100,
    double width = 260,
    double height = 200,
    String? itemId,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return null;
    final boardExists = _snapshot.boards.any((b) => b.boardId == boardId);
    if (!boardExists) return null;
    final cardExists = _snapshot.cards.any((c) => c.cardId == cardId);
    if (!cardExists) return null;

    final id = itemId ?? StableId.generate('item').value;
    final maxZ = _snapshot.boardItems
        .where((i) => i.boardId == boardId)
        .fold(0, (max, i) => i.zIndex > max ? i.zIndex : max);
    final item = BoardItem(
      itemId: id,
      boardId: boardId,
      cardId: cardId,
      x: x,
      y: y,
      width: width,
      height: height,
      zIndex: maxZ + 1,
    );

    _snapshot = _cloneSnapshot(
      boardItems: [..._snapshot.boardItems, item],
    );
    _engineToProductId[id] = id;

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.place,
      targetIds: [id],
      payload: {
        'card_id': cardId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'z_index': item.zIndex,
      },
      inverse: {
        'kind': 'remove',
        'item_id': id,
      },
      authorizationId: authorizationId,
    );

    return item;
  }

  /// Moves one or more items by a delta.
  void moveItems({
    required String boardId,
    required Map<String, math.Point<double>> deltas,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final items = _snapshot.boardItems
        .where((i) => i.boardId == boardId && deltas.containsKey(i.itemId))
        .toList();
    if (items.isEmpty) return;

    final oldPositions = <String, Map<String, double>>{};
    final newItems = _snapshot.boardItems.map((item) {
      final delta = deltas[item.itemId];
      if (delta == null) return item;
      oldPositions[item.itemId] = {
        'x': item.x,
        'y': item.y,
      };
      return BoardItem(
        itemId: item.itemId,
        boardId: item.boardId,
        cardId: item.cardId,
        x: item.x + delta.x,
        y: item.y + delta.y,
        width: item.width,
        height: item.height,
        rotation: item.rotation,
        zIndex: item.zIndex,
        viewState: item.viewState,
      );
    }).toList();

    _snapshot = _cloneSnapshot(boardItems: newItems);

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.move,
      targetIds: deltas.keys.toList(),
      payload: {
        for (final entry in deltas.entries)
          entry.key: {'dx': entry.value.x, 'dy': entry.value.y},
      },
      inverse: {
        'kind': 'move',
        'positions': oldPositions,
      },
      authorizationId: authorizationId,
    );
  }

  /// Resizes a single item.
  void resizeItem({
    required String boardId,
    required String itemId,
    required double width,
    required double height,
    double? x,
    double? y,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final item = _snapshot.boardItems
        .cast<BoardItem?>()
        .firstWhere((i) => i?.itemId == itemId, orElse: () => null);
    if (item == null || item.boardId != boardId) return;

    final oldGeometry = {
      'x': item.x,
      'y': item.y,
      'width': item.width,
      'height': item.height,
    };

    final newItem = BoardItem(
      itemId: item.itemId,
      boardId: item.boardId,
      cardId: item.cardId,
      x: x ?? item.x,
      y: y ?? item.y,
      width: width,
      height: height,
      rotation: item.rotation,
      zIndex: item.zIndex,
      viewState: item.viewState,
    );

    _snapshot = _cloneSnapshot(
      boardItems: _snapshot.boardItems
          .map((i) => i.itemId == itemId ? newItem : i)
          .toList(),
    );

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.resize,
      targetIds: [itemId],
      payload: {
        'x': newItem.x,
        'y': newItem.y,
        'width': width,
        'height': height,
      },
      inverse: {
        'kind': 'resize',
        'geometry': oldGeometry,
      },
      authorizationId: authorizationId,
    );
  }

  /// Removes one or more items from a board. Does NOT delete the Card.
  void removeItems({
    required String boardId,
    required List<String> itemIds,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final removed = _snapshot.boardItems
        .where((i) => i.boardId == boardId && itemIds.contains(i.itemId))
        .toList();
    if (removed.isEmpty) return;

    final removedData = <Map<String, dynamic>>[];
    for (final item in removed) {
      removedData.add(item.toJson());
    }

    _snapshot = _cloneSnapshot(
      boardItems: _snapshot.boardItems
          .where((i) => !itemIds.contains(i.itemId))
          .toList(),
      groupMembers: _snapshot.groupMembers
          .where((m) => !itemIds.contains(m.itemId))
          .toList(),
      edges: _snapshot.edges
          .where((e) =>
              !itemIds.contains(e.fromItemId) && !itemIds.contains(e.toItemId))
          .toList(),
    );

    for (final id in itemIds) {
      _engineToProductId.remove(id);
    }

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.remove,
      targetIds: itemIds,
      payload: {},
      inverse: {
        'kind': 'place',
        'items': removedData,
      },
      authorizationId: authorizationId,
    );
  }

  /// Adds a board to the snapshot (used by the BoardTargetPicker "新建白板"
  /// flow). Creating an empty board is not a content operation, so no audit
  /// operation is emitted — the subsequent placement on that board is.
  void addBoard(Board board) {
    if (_readonly) return;
    _snapshot = _cloneSnapshot(
      boards: [..._snapshot.boards, board],
    );
  }

  /// Rotates an item to an absolute [rotationDegrees] (0–360, clockwise).
  ///
  /// Emits a `resize` operation (geometry change) with the rotation in the
  /// payload/inverse.
  void rotateItem({
    required String boardId,
    required String itemId,
    required double rotationDegrees,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final item = _snapshot.boardItems
        .cast<BoardItem?>()
        .firstWhere((i) => i?.itemId == itemId, orElse: () => null);
    if (item == null || item.boardId != boardId) return;
    if (item.rotation == rotationDegrees) return;

    final oldRotation = item.rotation;
    final newItem = BoardItem(
      itemId: item.itemId,
      boardId: item.boardId,
      cardId: item.cardId,
      x: item.x,
      y: item.y,
      width: item.width,
      height: item.height,
      rotation: rotationDegrees,
      zIndex: item.zIndex,
      viewState: item.viewState,
    );

    _snapshot = _cloneSnapshot(
      boardItems: _snapshot.boardItems
          .map((i) => i.itemId == itemId ? newItem : i)
          .toList(),
    );

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.resize,
      targetIds: [itemId],
      payload: {'rotation': rotationDegrees},
      inverse: {'kind': 'resize', 'rotation': oldRotation},
      authorizationId: authorizationId,
    );
  }

  /// Sets a group's collapsed state.
  ///
  /// Emits a `group` operation carrying the new collapsed flag.
  void setGroupCollapsed({
    required String boardId,
    required String groupId,
    required bool collapsed,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final group = _snapshot.groups
        .cast<BoardGroup?>()
        .firstWhere((g) => g?.groupId == groupId, orElse: () => null);
    if (group == null || group.boardId != boardId) return;
    if (group.collapsed == collapsed) return;

    final newGroup = BoardGroup(
      groupId: group.groupId,
      boardId: group.boardId,
      name: group.name,
      style: group.style,
      collapsed: collapsed,
    );

    _snapshot = _cloneSnapshot(
      groups: _snapshot.groups
          .map((g) => g.groupId == groupId ? newGroup : g)
          .toList(),
    );

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.group,
      targetIds: [groupId],
      payload: {'collapsed': collapsed},
      inverse: {'kind': 'group', 'collapsed': !collapsed},
      authorizationId: authorizationId,
    );
  }

  /// Retargets one endpoint of an existing edge to another item.
  ///
  /// Exactly one of [fromItemId] / [toItemId] should differ from the current
  /// value; passing the same item for both endpoints is rejected (no
  /// self-loops). Returns false when the retarget is invalid — the snapshot
  /// is left untouched (no side effects).
  bool retargetEdge({
    required String boardId,
    required String edgeId,
    String? fromItemId,
    String? toItemId,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return false;
    final edge = _snapshot.edges
        .cast<BoardEdge?>()
        .firstWhere((e) => e?.edgeId == edgeId, orElse: () => null);
    if (edge == null || edge.boardId != boardId) return false;

    final newFrom = fromItemId ?? edge.fromItemId;
    final newTo = toItemId ?? edge.toItemId;
    if (newFrom == newTo) return false;
    if (newFrom == edge.fromItemId && newTo == edge.toItemId) return false;

    final itemIds = _snapshot.boardItems
        .where((i) => i.boardId == boardId)
        .map((i) => i.itemId)
        .toSet();
    if (!itemIds.contains(newFrom) || !itemIds.contains(newTo)) return false;

    final newEdge = BoardEdge(
      edgeId: edge.edgeId,
      boardId: edge.boardId,
      fromItemId: newFrom,
      toItemId: newTo,
      direction: edge.direction,
      semanticType: edge.semanticType,
      label: edge.label,
      style: edge.style,
      createdBy: edge.createdBy,
      createdAt: edge.createdAt,
      deletedAt: edge.deletedAt,
    );

    _snapshot = _cloneSnapshot(
      edges:
          _snapshot.edges.map((e) => e.edgeId == edgeId ? newEdge : e).toList(),
    );

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.edge,
      targetIds: [edgeId],
      payload: {
        'from_item_id': newFrom,
        'to_item_id': newTo,
        'direction': edge.direction.name,
      },
      inverse: {
        'kind': 'edge',
        'from_item_id': edge.fromItemId,
        'to_item_id': edge.toItemId,
      },
      authorizationId: authorizationId,
    );
    return true;
  }

  /// Updates the editable presentation fields of an existing board edge.
  /// Endpoint identity is intentionally unchanged here.
  bool updateEdge({
    required String boardId,
    required String edgeId,
    required EdgeDirection direction,
    String? label,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return false;
    final edge = _snapshot.edges.cast<BoardEdge?>().firstWhere(
        (candidate) => candidate?.edgeId == edgeId,
        orElse: () => null);
    if (edge == null || edge.boardId != boardId) return false;
    final normalizedLabel = label?.trim();
    final newLabel = normalizedLabel == null || normalizedLabel.isEmpty
        ? null
        : normalizedLabel;
    if (edge.direction == direction && edge.label == newLabel) return false;

    final updated = BoardEdge(
      edgeId: edge.edgeId,
      boardId: edge.boardId,
      fromItemId: edge.fromItemId,
      toItemId: edge.toItemId,
      direction: direction,
      semanticType: edge.semanticType,
      label: newLabel,
      style: edge.style,
      createdBy: edge.createdBy,
      createdAt: edge.createdAt,
      deletedAt: edge.deletedAt,
    );
    _snapshot = _cloneSnapshot(
      edges: _snapshot.edges
          .map((candidate) => candidate.edgeId == edgeId ? updated : candidate)
          .toList(),
    );
    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.edge,
      targetIds: [edgeId],
      payload: {
        'direction': direction.name,
        'label': newLabel,
      },
      inverse: {
        'kind': 'edge',
        'direction': edge.direction.name,
        'label': edge.label,
      },
      authorizationId: authorizationId,
    );
    return true;
  }

  /// Brings an item to the front (max zIndex + 1).
  void bringToFront({
    required String boardId,
    required String itemId,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final item = _snapshot.boardItems
        .cast<BoardItem?>()
        .firstWhere((i) => i?.itemId == itemId, orElse: () => null);
    if (item == null || item.boardId != boardId) return;

    final maxZ = _snapshot.boardItems
        .where((i) => i.boardId == boardId)
        .fold(0, (max, i) => i.zIndex > max ? i.zIndex : max);
    if (item.zIndex == maxZ) return;

    final oldZ = item.zIndex;
    _snapshot = _cloneSnapshot(
      boardItems: _snapshot.boardItems.map((i) {
        if (i.itemId != itemId) return i;
        return BoardItem(
          itemId: i.itemId,
          boardId: i.boardId,
          cardId: i.cardId,
          x: i.x,
          y: i.y,
          width: i.width,
          height: i.height,
          rotation: i.rotation,
          zIndex: maxZ + 1,
          viewState: i.viewState,
        );
      }).toList(),
    );

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.move,
      targetIds: [itemId],
      payload: {'z_index': maxZ + 1},
      inverse: {'kind': 'move', 'z_index': oldZ},
      authorizationId: authorizationId,
    );
  }

  /// Updates the viewport for a board.
  void updateViewport({
    required String boardId,
    required BoardViewport viewport,
    OperationActor actor = OperationActor.user,
  }) {
    _applyViewport(boardId, viewport);
    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.viewport,
      payload: {
        'center_x': viewport.centerX,
        'center_y': viewport.centerY,
        'zoom': viewport.zoom,
      },
    );
  }

  /// Creates a group on a board.
  BoardGroup? createGroup({
    required String boardId,
    required List<String> itemIds,
    String name = '',
    String? groupId,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return null;
    final boardExists = _snapshot.boards.any((b) => b.boardId == boardId);
    if (!boardExists) return null;

    final id = groupId ?? StableId.generate('group').value;
    final group = BoardGroup(
      groupId: id,
      boardId: boardId,
      name: name,
    );
    final members = itemIds.asMap().entries.map((e) {
      return GroupMember(groupId: id, itemId: e.value, order: e.key);
    }).toList();

    _snapshot = _cloneSnapshot(
      groups: [..._snapshot.groups, group],
      groupMembers: [..._snapshot.groupMembers, ...members],
    );
    _engineToProductId[id] = id;

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.group,
      targetIds: [id],
      payload: {
        'item_ids': itemIds,
        'name': name,
      },
      inverse: {'kind': 'ungroup', 'group_id': id},
      authorizationId: authorizationId,
    );

    return group;
  }

  /// Removes a group (ungroup). Items remain on the board.
  void removeGroup({
    required String boardId,
    required String groupId,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final group = _snapshot.groups
        .cast<BoardGroup?>()
        .firstWhere((g) => g?.groupId == groupId, orElse: () => null);
    if (group == null) return;

    final oldMembers =
        _snapshot.groupMembers.where((m) => m.groupId == groupId).toList();

    _snapshot = _cloneSnapshot(
      groups: _snapshot.groups.where((g) => g.groupId != groupId).toList(),
      groupMembers:
          _snapshot.groupMembers.where((m) => m.groupId != groupId).toList(),
    );
    _engineToProductId.remove(groupId);

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.ungroup,
      targetIds: [groupId],
      payload: {},
      inverse: {
        'kind': 'group',
        'group': group.toJson(),
        'members': oldMembers.map((m) => m.toJson()).toList(),
      },
      authorizationId: authorizationId,
    );
  }

  /// Creates an edge between two items.
  BoardEdge? createEdge({
    required String boardId,
    required String fromItemId,
    required String toItemId,
    EdgeDirection direction = EdgeDirection.undirected,
    String? semanticType,
    String? label,
    String? edgeId,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly || fromItemId == toItemId) return null;
    final items = _snapshot.boardItems.where((i) => i.boardId == boardId);
    final fromExists = items.any((i) => i.itemId == fromItemId);
    final toExists = items.any((i) => i.itemId == toItemId);
    if (!fromExists || !toExists) return null;

    final id = edgeId ?? StableId.generate('edge').value;
    final edge = BoardEdge(
      edgeId: id,
      boardId: boardId,
      fromItemId: fromItemId,
      toItemId: toItemId,
      direction: direction,
      semanticType: semanticType,
      label: label,
      createdAt: DateTime.now(),
    );

    _snapshot = _cloneSnapshot(edges: [..._snapshot.edges, edge]);
    _engineToProductId[id] = id;

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.edge,
      targetIds: [id],
      payload: {
        'from_item_id': fromItemId,
        'to_item_id': toItemId,
        'direction': direction.name,
      },
      inverse: {'kind': 'remove_edge', 'edge_id': id},
      authorizationId: authorizationId,
    );

    return edge;
  }

  /// Removes an edge.
  void removeEdge({
    required String boardId,
    required String edgeId,
    OperationActor actor = OperationActor.user,
    String? authorizationId,
  }) {
    if (_readonly) return;
    final edge = _snapshot.edges
        .cast<BoardEdge?>()
        .firstWhere((e) => e?.edgeId == edgeId, orElse: () => null);
    if (edge == null) return;

    _snapshot = _cloneSnapshot(
      edges: _snapshot.edges.where((e) => e.edgeId != edgeId).toList(),
    );
    _engineToProductId.remove(edgeId);

    _emitOperation(
      boardId: boardId,
      actor: actor,
      kind: OperationKind.removeEdge,
      targetIds: [edgeId],
      payload: {},
      inverse: {'kind': 'edge', 'edge': edge.toJson()},
      authorizationId: authorizationId,
    );
  }

  // ── Internal helpers ───────────────────────────────────────────────

  void _rebuildIdMapping() {
    _engineToProductId.clear();
    for (final item in _snapshot.boardItems) {
      _engineToProductId[item.itemId] = item.itemId;
    }
    for (final group in _snapshot.groups) {
      _engineToProductId[group.groupId] = group.groupId;
    }
    for (final edge in _snapshot.edges) {
      _engineToProductId[edge.edgeId] = edge.edgeId;
    }
  }

  void _applyViewport(String boardId, BoardViewport viewport) {
    _snapshot = _cloneSnapshot(viewport: viewport);
  }

  void _emitOperation({
    required String boardId,
    required OperationActor actor,
    required OperationKind kind,
    List<String> targetIds = const [],
    Map<String, dynamic> payload = const {},
    Map<String, dynamic>? inverse,
    String? authorizationId,
    String? undoOf,
  }) {
    if (_onOperation == null) return;
    final op = WhiteboardOperation(
      operationId: StableId.generate('op').value,
      boardId: boardId,
      actor: actor,
      operationKind: kind,
      targetIds: targetIds,
      payload: payload,
      inverse: inverse,
      authorizationId: authorizationId,
      undoOf: undoOf,
      createdAt: DateTime.now(),
    );
    _onOperation!(op);
  }

  /// Gets the engine→product ID mapping (for inspection/testing).
  Map<String, String> get idMapping => Map.unmodifiable(_engineToProductId);
}
