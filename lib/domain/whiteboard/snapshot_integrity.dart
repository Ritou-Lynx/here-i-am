/// Snapshot integrity validation and migration utilities.
///
/// Provides referential integrity checks, ID validation, and schema migration
/// for whiteboard snapshots. Used by contract tests and available to W1–W4
/// for validation.
library;

import 'board.dart';
import 'card_contract.dart';
import 'whiteboard_ids.dart';
import 'whiteboard_snapshot.dart';

/// The result of validating a snapshot's integrity.
class SnapshotIntegrityResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const SnapshotIntegrityResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });
}

/// Validates referential integrity of a [WhiteboardSnapshot].
///
/// Checks:
/// - All BoardItem board_ids reference existing Boards
/// - All BoardItem card_ids reference existing Cards
/// - All GroupMember group_ids reference existing Groups
/// - All GroupMember item_ids reference existing BoardItems
/// - All BoardEdge from/to item_ids reference existing BoardItems
/// - All BoardEdge board_ids reference existing Boards
/// - All Card source_ids (if present) reference existing Sources
/// - Source current_version_id references existing SourceVersions (if versions present)
SnapshotIntegrityResult validateSnapshotIntegrity(WhiteboardSnapshot snapshot) {
  final errors = <String>[];
  final warnings = <String>[];

  final boardIds = snapshot.boards.map((b) => b.boardId).toSet();
  final cardIds = snapshot.cards.map((c) => c.cardId).toSet();
  final sourceIds = snapshot.sources.map((s) => s.sourceId).toSet();
  final versionIds =
      snapshot.sourceVersions.map((v) => v.versionId).toSet();
  final groupIds = snapshot.groups.map((g) => g.groupId).toSet();
  final itemIds = snapshot.boardItems.map((i) => i.itemId).toSet();

  // Empty ID checks — any entity with an empty string ID is invalid
  for (final source in snapshot.sources) {
    if (source.sourceId.isEmpty) {
      errors.add('Source has empty source_id');
    }
  }
  for (final card in snapshot.cards) {
    if (card.cardId.isEmpty) {
      errors.add('Card has empty card_id');
    }
  }
  for (final board in snapshot.boards) {
    if (board.boardId.isEmpty) {
      errors.add('Board has empty board_id');
    }
  }

  // BoardItem → Board
  for (final item in snapshot.boardItems) {
    if (!boardIds.contains(item.boardId)) {
      errors.add(
          'BoardItem ${item.itemId} references non-existent board ${item.boardId}');
    }
    // BoardItem → Card
    if (!cardIds.contains(item.cardId)) {
      errors.add(
          'BoardItem ${item.itemId} references non-existent card ${item.cardId}');
    }
  }

  // GroupMember → Group
  for (final member in snapshot.groupMembers) {
    if (!groupIds.contains(member.groupId)) {
      errors.add(
          'GroupMember references non-existent group ${member.groupId}');
    }
    // GroupMember → BoardItem
    if (!itemIds.contains(member.itemId)) {
      errors.add(
          'GroupMember references non-existent item ${member.itemId}');
    }
  }

  // Group → Board
  for (final group in snapshot.groups) {
    if (!boardIds.contains(group.boardId)) {
      errors.add(
          'Group ${group.groupId} references non-existent board ${group.boardId}');
    }
  }

  // BoardEdge → Board and items
  for (final edge in snapshot.edges) {
    if (!boardIds.contains(edge.boardId)) {
      errors.add(
          'Edge ${edge.edgeId} references non-existent board ${edge.boardId}');
    }
    if (!itemIds.contains(edge.fromItemId)) {
      errors.add(
          'Edge ${edge.edgeId} from_item_id ${edge.fromItemId} does not exist');
    }
    if (!itemIds.contains(edge.toItemId)) {
      errors.add(
          'Edge ${edge.edgeId} to_item_id ${edge.toItemId} does not exist');
    }
    if (edge.fromItemId == edge.toItemId) {
      warnings.add(
          'Edge ${edge.edgeId} is a self-loop on ${edge.fromItemId}');
    }
  }

  // Card → Source
  for (final card in snapshot.cards) {
    if (card.sourceId != null && !sourceIds.contains(card.sourceId)) {
      errors.add(
          'Card ${card.cardId} references non-existent source ${card.sourceId}');
    }
  }

  // Source → SourceVersion
  for (final source in snapshot.sources) {
    if (source.currentVersionId != null &&
        snapshot.sourceVersions.isNotEmpty &&
        !versionIds.contains(source.currentVersionId)) {
      warnings.add(
          'Source ${source.sourceId} current_version_id ${source.currentVersionId} not found in versions');
    }
  }

  // SourceVersion → Source
  for (final version in snapshot.sourceVersions) {
    if (!sourceIds.contains(version.sourceId)) {
      errors.add(
          'SourceVersion ${version.versionId} references non-existent source ${version.sourceId}');
    }
  }

  return SnapshotIntegrityResult(
    isValid: errors.isEmpty,
    errors: errors,
    warnings: warnings,
  );
}

/// Migrates an old-schema snapshot (schema_version 0, camelCase fields from
/// the desktop MVP) to the current [WhiteboardSnapshot] format.
///
/// This handles the `desktop/whiteboard_mvp/src/model.mjs` shape:
/// - `cardId` → `card_id`, `kind` → `card_kind`, `mediaType` folded into card
/// - `boardId` → `board_id`, `title` → `name`
/// - `boardItems` → `board_items`, `itemId` → `item_id`
/// - `zIndex` → `z_index`
/// - `ui.lastBoardId` is dropped (viewport is per-board, not global)
WhiteboardSnapshot migrateFromV0(Map<String, dynamic> raw) {
  final cardsRaw = (raw['cards'] as List<dynamic>?) ?? [];
  final boardsRaw = (raw['boards'] as List<dynamic>?) ?? [];
  final boardItemsRaw = (raw['boardItems'] as List<dynamic>?) ?? [];
  final groupsRaw = (raw['groups'] as List<dynamic>?) ?? [];
  final edgesRaw = (raw['edges'] as List<dynamic>?) ?? [];

  final cards = <CardContract>[];
  for (final cardRaw in cardsRaw) {
    if (cardRaw is! Map<String, dynamic>) continue;
    final cardId = tryStableId(cardRaw['cardId']);
    if (cardId == null) continue;
    cards.add(CardContract(
      cardId: cardId,
      cardKind: _migrateCardKind(cardRaw['kind'] as String?),
      sourceId: tryStableId(cardRaw['sourceId']),
      title: cardRaw['title'] as String? ?? '',
      body: cardRaw['body'] as String? ?? '',
      tags: (cardRaw['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      presentation: {
        if (cardRaw['accent'] != null) 'accent': cardRaw['accent'],
        if (cardRaw['mediaType'] != null) 'media_type': cardRaw['mediaType'],
        if (cardRaw['source'] != null) 'source_label': cardRaw['source'],
      },
      createdBy: CardCreatedBy.user,
      createdAt:
          DateTime.tryParse(cardRaw['createdAt'] as String? ?? '') ??
              DateTime.utc(2026, 1, 1),
    ));
  }

  final boards = <Board>[];
  for (final boardRaw in boardsRaw) {
    if (boardRaw is! Map<String, dynamic>) continue;
    final boardId = tryStableId(boardRaw['boardId']);
    if (boardId == null) continue;
    boards.add(Board(
      boardId: boardId,
      name: boardRaw['title'] as String? ?? '',
      createdAt:
          DateTime.tryParse(boardRaw['createdAt'] as String? ?? '') ??
              DateTime.utc(2026, 1, 1),
      updatedAt: boardRaw['updatedAt'] != null
          ? DateTime.tryParse(boardRaw['updatedAt'] as String)
          : null,
    ));
  }

  final boardItems = <BoardItem>[];
  for (final itemRaw in boardItemsRaw) {
    if (itemRaw is! Map<String, dynamic>) continue;
    final itemId = tryStableId(itemRaw['itemId']);
    final boardId = tryStableId(itemRaw['boardId']);
    final cardId = tryStableId(itemRaw['cardId']);
    if (itemId == null || boardId == null || cardId == null) continue;
    boardItems.add(BoardItem(
      itemId: itemId,
      boardId: boardId,
      cardId: cardId,
      x: (itemRaw['x'] as num?)?.toDouble() ?? 0,
      y: (itemRaw['y'] as num?)?.toDouble() ?? 0,
      width: (itemRaw['width'] as num?)?.toDouble() ?? 260,
      height: (itemRaw['height'] as num?)?.toDouble() ?? 200,
      zIndex: (itemRaw['zIndex'] as num?)?.toInt() ?? 0,
    ));
  }

  final groups = <BoardGroup>[];
  for (final groupRaw in groupsRaw) {
    if (groupRaw is! Map<String, dynamic>) continue;
    final groupId = tryStableId(groupRaw['groupId']);
    final boardId = tryStableId(groupRaw['boardId']);
    if (groupId == null || boardId == null) continue;
    groups.add(BoardGroup(
      groupId: groupId,
      boardId: boardId,
      name: groupRaw['name'] as String? ?? '',
    ));
  }

  final edges = <BoardEdge>[];
  for (final edgeRaw in edgesRaw) {
    if (edgeRaw is! Map<String, dynamic>) continue;
    final edgeId = tryStableId(edgeRaw['edgeId']);
    final boardId = tryStableId(edgeRaw['boardId']);
    final fromItemId = tryStableId(edgeRaw['fromItemId']);
    final toItemId = tryStableId(edgeRaw['toItemId']);
    if (edgeId == null || boardId == null) continue;
    edges.add(BoardEdge(
      edgeId: edgeId,
      boardId: boardId,
      fromItemId: fromItemId ?? '',
      toItemId: toItemId ?? '',
      createdAt:
          DateTime.tryParse(edgeRaw['createdAt'] as String? ?? '') ??
              DateTime.utc(2026, 1, 1),
    ));
  }

  return WhiteboardSnapshot(
    schemaVersion: whiteboardSnapshotSchemaVersion,
    cards: cards,
    boards: boards,
    boardItems: boardItems,
    groups: groups,
    edges: edges,
    updatedAt: raw['updatedAt'] != null
        ? DateTime.tryParse(raw['updatedAt'] as String)
        : null,
  );
}

CardKind _migrateCardKind(String? raw) {
  switch (raw) {
    case 'source':
      return CardKind.source;
    case 'note':
      return CardKind.note;
    case 'annotation':
      return CardKind.annotation;
    case 'reference':
      return CardKind.reference;
    default:
      return CardKind.note;
  }
}

/// Attempts to load a snapshot from raw JSON, migrating old schemas if needed.
///
/// - schema_version 0 → migrate via [migrateFromV0]
/// - schema_version 1 → direct parse via [WhiteboardSnapshot.fromJson]
/// - unknown schema_version → throws [ArgumentError]
WhiteboardSnapshot loadSnapshot(Map<String, dynamic> raw) {
  final version = (raw['schema_version'] as num?)?.toInt();
  switch (version) {
    case 0:
      return migrateFromV0(raw);
    case whiteboardSnapshotSchemaVersion:
    case null:
      return WhiteboardSnapshot.fromJson(raw);
    default:
      throw ArgumentError(
          'Unknown snapshot schema_version: $version. '
          'Expected 0 or $whiteboardSnapshotSchemaVersion.');
  }
}