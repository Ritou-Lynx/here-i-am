/// WhiteboardSnapshot and WhiteboardOperation contracts.
///
/// `WhiteboardSnapshot` is the unified data structure that all whiteboard
/// engines must load from and export to. `WhiteboardOperation` is the
/// append-only audit log entry for board modifications.
library;

import 'board.dart';
import 'card_contract.dart';
import 'source_content.dart';
import 'whiteboard_ids.dart';

/// The current schema version for whiteboard snapshots.
const whiteboardSnapshotSchemaVersion = 1;

/// The unified snapshot of all whiteboard state.
///
/// All third-party engines must go through an adapter that loads from and
/// exports to this structure. Engine-private node IDs only exist in adapter
/// mappings, never in this snapshot.
class WhiteboardSnapshot {
  final int schemaVersion;
  final List<SourceContent> sources;
  final List<SourceVersion> sourceVersions;
  final List<CardContract> cards;
  final List<Board> boards;
  final List<BoardItem> boardItems;
  final List<BoardGroup> groups;
  final List<GroupMember> groupMembers;
  final List<BoardEdge> edges;
  final BoardViewport viewport;
  final DateTime? updatedAt;

  const WhiteboardSnapshot({
    this.schemaVersion = whiteboardSnapshotSchemaVersion,
    this.sources = const [],
    this.sourceVersions = const [],
    this.cards = const [],
    this.boards = const [],
    this.boardItems = const [],
    this.groups = const [],
    this.groupMembers = const [],
    this.edges = const [],
    this.viewport = const BoardViewport(),
    this.updatedAt,
  });

  factory WhiteboardSnapshot.fromJson(Map<String, dynamic> json) {
    return WhiteboardSnapshot(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ??
          whiteboardSnapshotSchemaVersion,
      sources: (json['sources'] as List<dynamic>?)
          ?.map((e) => SourceContent.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      sourceVersions: (json['source_versions'] as List<dynamic>?)
          ?.map((e) => SourceVersion.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      cards: (json['cards'] as List<dynamic>?)
          ?.map((e) => CardContract.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      boards: (json['boards'] as List<dynamic>?)
          ?.map((e) => Board.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      boardItems: (json['board_items'] as List<dynamic>?)
          ?.map((e) => BoardItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      groups: (json['groups'] as List<dynamic>?)
          ?.map((e) => BoardGroup.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      groupMembers: (json['group_members'] as List<dynamic>?)
          ?.map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      edges: (json['edges'] as List<dynamic>?)
          ?.map((e) => BoardEdge.fromJson(e as Map<String, dynamic>))
          .toList() ??
          const [],
      viewport: json['viewport'] != null
          ? BoardViewport.fromJson(json['viewport'] as Map<String, dynamic>)
          : const BoardViewport(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        if (sources.isNotEmpty)
          'sources': sources.map((s) => s.toJson()).toList(),
        if (sourceVersions.isNotEmpty)
          'source_versions': sourceVersions.map((v) => v.toJson()).toList(),
        if (cards.isNotEmpty) 'cards': cards.map((c) => c.toJson()).toList(),
        if (boards.isNotEmpty) 'boards': boards.map((b) => b.toJson()).toList(),
        if (boardItems.isNotEmpty)
          'board_items': boardItems.map((i) => i.toJson()).toList(),
        if (groups.isNotEmpty) 'groups': groups.map((g) => g.toJson()).toList(),
        if (groupMembers.isNotEmpty)
          'group_members': groupMembers.map((m) => m.toJson()).toList(),
        if (edges.isNotEmpty) 'edges': edges.map((e) => e.toJson()).toList(),
        'viewport': viewport.toJson(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };
}

/// The kind of operation on a board.
enum OperationKind {
  place,
  move,
  resize,
  remove,
  group,
  ungroup,
  edge,
  removeEdge,
  viewport,
  undo;

  static OperationKind fromString(String? raw) {
    switch (raw) {
      case 'place':
        return OperationKind.place;
      case 'move':
        return OperationKind.move;
      case 'resize':
        return OperationKind.resize;
      case 'remove':
        return OperationKind.remove;
      case 'group':
        return OperationKind.group;
      case 'ungroup':
        return OperationKind.ungroup;
      case 'edge':
        return OperationKind.edge;
      case 'remove_edge':
        return OperationKind.removeEdge;
      case 'viewport':
        return OperationKind.viewport;
      case 'undo':
        return OperationKind.undo;
      default:
        throw ArgumentError('Unknown OperationKind: $raw');
    }
  }

  String get name {
    switch (this) {
      case OperationKind.removeEdge:
        return 'remove_edge';
      default:
        return toString().split('.').last;
    }
  }
}

/// Who performed a board operation.
enum OperationActor {
  user,
  i;

  static OperationActor fromString(String? raw) {
    switch (raw) {
      case 'user':
        return OperationActor.user;
      case 'i':
        return OperationActor.i;
      default:
        return OperationActor.user;
    }
  }
}

/// An append-only audit log entry for a board modification.
///
/// Each operation records what changed, the inverse (for undo), and the
/// authorization under which it was performed. Lin Ai's write operations must
/// always reference a valid authorization.
class WhiteboardOperation {
  final String operationId;
  final String boardId;
  final OperationActor actor;
  final OperationKind operationKind;
  final List<String> targetIds;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? inverse;
  final String? authorizationId;
  final String? undoOf;
  final DateTime createdAt;

  const WhiteboardOperation({
    required this.operationId,
    required this.boardId,
    this.actor = OperationActor.user,
    required this.operationKind,
    this.targetIds = const [],
    this.payload = const {},
    this.inverse,
    this.authorizationId,
    this.undoOf,
    required this.createdAt,
  });

  factory WhiteboardOperation.fromJson(Map<String, dynamic> json) {
    return WhiteboardOperation(
      operationId: StableId(json['operation_id']).value,
      boardId: StableId(json['board_id']).value,
      actor: OperationActor.fromString(json['actor'] as String?),
      operationKind: OperationKind.fromString(json['operation_kind'] as String?),
      targetIds: (json['target_ids'] as List<dynamic>?)?.cast<String>() ?? const [],
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      inverse: json['inverse'] as Map<String, dynamic>?,
      authorizationId: tryStableId(json['authorization_id']),
      undoOf: tryStableId(json['undo_of']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'operation_id': operationId,
        'board_id': boardId,
        'actor': actor.name,
        'operation_kind': operationKind.name,
        if (targetIds.isNotEmpty) 'target_ids': targetIds,
        if (payload.isNotEmpty) 'payload': payload,
        if (inverse != null) 'inverse': inverse,
        if (authorizationId != null) 'authorization_id': authorizationId,
        if (undoOf != null) 'undo_of': undoOf,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}