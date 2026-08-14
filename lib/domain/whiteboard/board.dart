/// Board, BoardItem, BoardGroup, GroupMember, and BoardEdge contracts.
///
/// These entities define the spatial organization layer. `BoardItem` is a
/// placement of a `Card` on a `Board` — it holds layout coordinates and local
/// view state, but does NOT hold card content. Deleting a `BoardItem` does not
/// delete the `Card` or `SourceContent`.
library;

import 'card_contract.dart';
import 'source_content.dart';
import 'whiteboard_ids.dart';

/// A whiteboard — the spatial organization surface.
class Board {
  final String boardId;
  final String name;
  final OwnerSpace ownerSpace;
  final CardCreatedBy createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const Board({
    required this.boardId,
    required this.name,
    this.ownerSpace = OwnerSpace.user,
    this.createdBy = CardCreatedBy.user,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory Board.fromJson(Map<String, dynamic> json) {
    return Board(
      boardId: StableId(json['board_id']).value,
      name: json['name'] as String? ?? '',
      ownerSpace: OwnerSpace.fromString(json['owner_space'] as String?),
      createdBy: CardCreatedBy.fromString(json['created_by'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'board_id': boardId,
        'name': name,
        'owner_space': ownerSpace.name,
        'created_by': createdBy.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
      };
}

/// A card's placement on a specific board.
///
/// The same `cardId` can map to multiple `BoardItem`s, even on the same board.
/// `BoardItem` holds only layout (x, y, width, height, rotation, zIndex) and
/// local view state — never card content.
class BoardItem {
  final String itemId;
  final String boardId;
  final String cardId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int zIndex;
  final Map<String, dynamic> viewState;

  const BoardItem({
    required this.itemId,
    required this.boardId,
    required this.cardId,
    this.x = 0,
    this.y = 0,
    this.width = 260,
    this.height = 200,
    this.rotation = 0,
    this.zIndex = 0,
    this.viewState = const {},
  });

  factory BoardItem.fromJson(Map<String, dynamic> json) {
    return BoardItem(
      itemId: StableId(json['item_id']).value,
      boardId: StableId(json['board_id']).value,
      cardId: StableId(json['card_id']).value,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 260,
      height: (json['height'] as num?)?.toDouble() ?? 200,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      zIndex: (json['z_index'] as num?)?.toInt() ?? 0,
      viewState: (json['view_state'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'board_id': boardId,
        'card_id': cardId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
        'z_index': zIndex,
        if (viewState.isNotEmpty) 'view_state': viewState,
      };
}

/// An explicit group on a board. Membership is tracked by [GroupMember], not
/// by coordinates.
class BoardGroup {
  final String groupId;
  final String boardId;
  final String name;
  final Map<String, dynamic> style;
  final bool collapsed;

  const BoardGroup({
    required this.groupId,
    required this.boardId,
    this.name = '',
    this.style = const {},
    this.collapsed = false,
  });

  factory BoardGroup.fromJson(Map<String, dynamic> json) {
    return BoardGroup(
      groupId: StableId(json['group_id']).value,
      boardId: StableId(json['board_id']).value,
      name: json['name'] as String? ?? '',
      style: (json['style'] as Map<String, dynamic>?) ?? const {},
      collapsed: json['collapsed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'board_id': boardId,
        'name': name,
        if (style.isNotEmpty) 'style': style,
        if (collapsed) 'collapsed': collapsed,
      };
}

/// Explicit membership linking a [BoardItem] to a [BoardGroup].
///
/// Group membership is NOT inferred from coordinates — it is always explicit.
class GroupMember {
  final String groupId;
  final String itemId;
  final int order;

  const GroupMember({
    required this.groupId,
    required this.itemId,
    this.order = 0,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      groupId: StableId(json['group_id']).value,
      itemId: StableId(json['item_id']).value,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'item_id': itemId,
        'order': order,
      };
}

/// The direction of a board edge.
enum EdgeDirection {
  directed,
  undirected;

  static EdgeDirection fromString(String? raw) {
    switch (raw) {
      case 'directed':
        return EdgeDirection.directed;
      case 'undirected':
        return EdgeDirection.undirected;
      default:
        return EdgeDirection.undirected;
    }
  }
}

/// A connection between two [BoardItem]s on a board.
///
/// Cross-board references do not connect canvas coordinates directly — they
/// connect `card_id`s or create reference cards.
class BoardEdge {
  final String edgeId;
  final String boardId;
  final String fromItemId;
  final String toItemId;
  final EdgeDirection direction;
  final String? semanticType;
  final String? label;
  final Map<String, dynamic> style;
  final CardCreatedBy createdBy;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const BoardEdge({
    required this.edgeId,
    required this.boardId,
    required this.fromItemId,
    required this.toItemId,
    this.direction = EdgeDirection.undirected,
    this.semanticType,
    this.label,
    this.style = const {},
    this.createdBy = CardCreatedBy.user,
    required this.createdAt,
    this.deletedAt,
  });

  factory BoardEdge.fromJson(Map<String, dynamic> json) {
    return BoardEdge(
      edgeId: StableId(json['edge_id']).value,
      boardId: StableId(json['board_id']).value,
      fromItemId: StableId(json['from_item_id']).value,
      toItemId: StableId(json['to_item_id']).value,
      direction: EdgeDirection.fromString(json['direction'] as String?),
      semanticType: json['semantic_type'] as String?,
      label: json['label'] as String?,
      style: (json['style'] as Map<String, dynamic>?) ?? const {},
      createdBy: CardCreatedBy.fromString(json['created_by'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'edge_id': edgeId,
        'board_id': boardId,
        'from_item_id': fromItemId,
        'to_item_id': toItemId,
        'direction': direction.name,
        if (semanticType != null) 'semantic_type': semanticType,
        if (label != null) 'label': label,
        if (style.isNotEmpty) 'style': style,
        'created_by': createdBy.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
      };
}

/// The viewport state of a board — center position and zoom level.
///
/// Viewport is device experience state, not content truth. It can be cached
/// locally but is not the authoritative content.
class BoardViewport {
  final double centerX;
  final double centerY;
  final double zoom;

  const BoardViewport({
    this.centerX = 0,
    this.centerY = 0,
    this.zoom = 1,
  });

  factory BoardViewport.fromJson(Map<String, dynamic> json) {
    return BoardViewport(
      centerX: (json['center_x'] as num?)?.toDouble() ?? 0,
      centerY: (json['center_y'] as num?)?.toDouble() ?? 0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'center_x': centerX,
        'center_y': centerY,
        'zoom': zoom,
      };
}