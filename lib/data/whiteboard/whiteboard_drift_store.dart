/// Drift-backed whiteboard persistence store (W6 production integration base).
///
/// Mirrors the `WhiteboardSnapshotStore` file API (`save / load / exists /
/// delete`) so it is a drop-in replacement, and adds `listBoards` /
/// `createBoard` for the whiteboard index. The file store in
/// `lib/ui/whiteboard_canvas/whiteboard_snapshot_store.dart` stays for W1
/// tests and as a fallback.
///
/// Mapping (WhiteboardSnapshot ↔ Drift tables, see
/// `lib/data/memory_v3/db/tables.dart` section 十):
///   Board            → WhiteboardBoards      (viewport lives on the board row)
///   BoardItem        → WhiteboardBoardItems  (board-scoped replace)
///   BoardGroup       → WhiteboardGroups
///   GroupMember      → WhiteboardGroupMembers
///   BoardEdge        → WhiteboardEdges
///   SourceContent    → WhiteboardSources
///   SourceVersion    → WhiteboardSourceVersions
///   CardContract     → MemoryCards (identity) + WhiteboardCardExtras (fields)
///
/// Save semantics (mirrors the file store, which wrote one full snapshot per
/// board file): the calling board's items/groups/members/edges are replaced,
/// boards/sources/versions/cards are upserted. Cards are NEVER deleted by
/// save — deleting a BoardItem must not delete a Card.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart'
    show SnapshotLoadResult;

/// A board list entry for the whiteboard index.
class WhiteboardIndexEntry {
  final String boardId;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const WhiteboardIndexEntry({
    required this.boardId,
    required this.name,
    required this.createdAt,
    this.updatedAt,
  });
}

/// Converts between contract [DateTime] and Drift INTEGER ms since epoch.
int _toMillis(DateTime dt) => dt.toUtc().millisecondsSinceEpoch;

/// Drift-backed store for the whiteboard surface.
class WhiteboardDriftStore {
  final AppDatabase db;

  WhiteboardDriftStore(this.db);

  // ── Board index ──────────────────────────────────────────────────────────

  /// Lists non-deleted boards, most recently updated first.
  Future<List<WhiteboardIndexEntry>> listBoards() async {
    final rows = await (db.select(db.whiteboardBoards)
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([
            (b) => OrderingTerm.desc(b.updatedAt),
            (b) => OrderingTerm.desc(b.createdAt),
          ]))
        .get();
    return rows
        .map((row) => WhiteboardIndexEntry(
              boardId: row.id,
              name: row.name,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
              updatedAt: row.updatedAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(row.updatedAt!,
                      isUtc: true)
                  : null,
            ))
        .toList();
  }

  /// Creates a board row plus its initial empty snapshot. Returns the stable
  /// board id.
  Future<String> createBoard({required String name}) async {
    final boardId = 'board_${const Uuid().v4()}';
    final now = DateTime.now().toUtc();
    await db.into(db.whiteboardBoards).insert(
          WhiteboardBoardsCompanion.insert(
            id: boardId,
            name: name,
            createdAt: _toMillis(now),
          ),
        );
    return boardId;
  }

  /// Whether a non-deleted snapshot exists for the given board.
  Future<bool> exists(String boardId) async {
    final row = await (db.select(db.whiteboardBoards)
          ..where((b) => b.id.equals(boardId) & b.deletedAt.isNull()))
        .getSingleOrNull();
    return row != null;
  }

  /// Deletes all rows belonging to the board (soft: board row keeps
  /// deletedAt; hard: removes items/groups/members/edges). Cards and sources
  /// are never deleted. Returns true when the board existed.
  Future<bool> delete(String boardId) async {
    final board = await (db.select(db.whiteboardBoards)
          ..where((b) => b.id.equals(boardId)))
        .getSingleOrNull();
    if (board == null) return false;
    await db.transaction(() async {
      await (db.delete(db.whiteboardBoardItems)
            ..where((i) => i.boardId.equals(boardId)))
          .go();
      await (db.delete(db.whiteboardEdges)
            ..where((e) => e.boardId.equals(boardId)))
          .go();
      final groups = await (db.select(db.whiteboardGroups)
            ..where((g) => g.boardId.equals(boardId)))
          .get();
      for (final group in groups) {
        await (db.delete(db.whiteboardGroupMembers)
              ..where((gm) => gm.groupId.equals(group.id)))
            .go();
      }
      await (db.delete(db.whiteboardGroups)
            ..where((g) => g.boardId.equals(boardId)))
          .go();
      await (db.update(db.whiteboardBoards)
            ..where((b) => b.id.equals(boardId)))
          .write(
        WhiteboardBoardsCompanion(
          deletedAt: Value(_toMillis(DateTime.now().toUtc())),
        ),
      );
    });
    return true;
  }

  // ── Snapshot persistence ────────────────────────────────────────────────

  /// Saves the full [snapshot] for [boardId]. Returns true on success.
  ///
  /// The snapshot is the full truth (mirroring the file store's per-board
  /// full snapshot files): all layout rows (items/groups/members/edges) are
  /// replaced by the snapshot's, boards/sources/versions/cards are upserted.
  /// Cards are additive — rows never disappear because a snapshot omitted
  /// them; deleting a BoardItem never deletes a Card.
  Future<bool> save(String boardId, WhiteboardSnapshot snapshot) async {
    try {
      await db.transaction(() async {
        await _saveBoards(boardId, snapshot);
        await _replaceAllItems(snapshot);
        await _replaceAllGroups(snapshot);
        await _replaceAllEdges(snapshot);
        await _saveSources(snapshot);
        await _saveCards(snapshot);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveBoards(String boardId, WhiteboardSnapshot snapshot) async {
    final existing = {
      for (final row
          in await db.select(db.whiteboardBoards).get())
        row.id: row,
    };
    for (final board in snapshot.boards) {
      final isTarget = board.boardId == boardId;
      final prior = existing[board.boardId];
      await db.into(db.whiteboardBoards).insertOnConflictUpdate(
            WhiteboardBoardsCompanion.insert(
              id: board.boardId,
              name: board.name,
              ownerSpace: Value(board.ownerSpace.name),
              createdBy: Value(board.createdBy.name),
              viewportCenterX: Value(
                isTarget ? snapshot.viewport.centerX : (prior?.viewportCenterX ?? 0)),
              viewportCenterY: Value(
                isTarget ? snapshot.viewport.centerY : (prior?.viewportCenterY ?? 0)),
              viewportZoom: Value(
                isTarget ? snapshot.viewport.zoom : (prior?.viewportZoom ?? 1)),
              createdAt: _toMillis(board.createdAt),
              updatedAt: Value(
                isTarget
                    ? (snapshot.updatedAt != null
                        ? _toMillis(snapshot.updatedAt!)
                        : null)
                    : (board.updatedAt != null
                        ? _toMillis(board.updatedAt!)
                        : prior?.updatedAt),
              ),
              deletedAt: Value(board.deletedAt != null ? _toMillis(board.deletedAt!) : null),
            ),
          );
    }
  }

  Future<void> _replaceAllItems(WhiteboardSnapshot snapshot) async {
    await db.delete(db.whiteboardBoardItems).go();
    for (final item in snapshot.boardItems) {
      await db.into(db.whiteboardBoardItems).insert(
            WhiteboardBoardItemsCompanion.insert(
              id: item.itemId,
              boardId: item.boardId,
              cardId: item.cardId,
              x: Value(item.x),
              y: Value(item.y),
              width: Value(item.width),
              height: Value(item.height),
              rotation: Value(item.rotation),
              zIndex: Value(item.zIndex),
              viewStateJson: Value(
                item.viewState.isEmpty ? null : jsonEncode(item.viewState)),
            ),
          );
    }
  }

  Future<void> _replaceAllGroups(WhiteboardSnapshot snapshot) async {
    await db.delete(db.whiteboardGroupMembers).go();
    await db.delete(db.whiteboardGroups).go();
    for (final group in snapshot.groups) {
      await db.into(db.whiteboardGroups).insert(
            WhiteboardGroupsCompanion.insert(
              id: group.groupId,
              boardId: group.boardId,
              name: Value(group.name),
              styleJson: Value(
                group.style.isEmpty ? null : jsonEncode(group.style)),
              collapsed: Value(group.collapsed),
            ),
          );
      final members = snapshot.groupMembers
          .where((gm) => gm.groupId == group.groupId)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      for (var i = 0; i < members.length; i++) {
        final member = members[i];
        await db.into(db.whiteboardGroupMembers).insert(
              WhiteboardGroupMembersCompanion.insert(
                groupId: member.groupId,
                itemId: member.itemId,
                sortOrder: Value(member.order),
              ),
            );
      }
    }
  }

  Future<void> _replaceAllEdges(WhiteboardSnapshot snapshot) async {
    await db.delete(db.whiteboardEdges).go();
    for (final edge in snapshot.edges) {
      await db.into(db.whiteboardEdges).insert(
            WhiteboardEdgesCompanion.insert(
              id: edge.edgeId,
              boardId: edge.boardId,
              fromItemId: edge.fromItemId,
              toItemId: edge.toItemId,
              direction: Value(edge.direction.name),
              semanticType: Value(edge.semanticType),
              label: Value(edge.label),
              styleJson: Value(
                edge.style.isEmpty ? null : jsonEncode(edge.style)),
              createdBy: Value(edge.createdBy.name),
              createdAt: _toMillis(edge.createdAt),
              deletedAt: Value(
                edge.deletedAt != null ? _toMillis(edge.deletedAt!) : null),
            ),
          );
    }
  }

  Future<void> _saveSources(WhiteboardSnapshot snapshot) async {
    for (final source in snapshot.sources) {
      await db.into(db.whiteboardSources).insertOnConflictUpdate(
            WhiteboardSourcesCompanion.insert(
              id: source.sourceId,
              mediaType: source.mediaType.name,
              title: source.title,
              ownerSpace: Value(source.ownerSpace.name),
              origin: Value(source.origin.name),
              provider: Value(source.provider),
              canonicalId: Value(source.canonicalId),
              mimeType: Value(source.mimeType),
              currentVersionId: Value(source.currentVersionId),
              contentHash: Value(source.contentHash),
              objectRef: Value(source.objectRef),
              metadataJson: Value(
                source.metadata.isEmpty ? null : jsonEncode(source.metadata)),
              createdAt: _toMillis(source.createdAt),
              updatedAt: Value(
                source.updatedAt != null ? _toMillis(source.updatedAt!) : null),
              deletedAt: Value(
                source.deletedAt != null ? _toMillis(source.deletedAt!) : null),
            ),
          );
    }
    for (final version in snapshot.sourceVersions) {
      await db.into(db.whiteboardSourceVersions).insertOnConflictUpdate(
            WhiteboardSourceVersionsCompanion.insert(
              id: version.versionId,
              sourceId: version.sourceId,
              contentHash: version.contentHash,
              objectRef: version.objectRef,
              parserVersion: Value(version.parserVersion),
              createdAt: _toMillis(version.createdAt),
            ),
          );
    }
  }

  Future<void> _saveCards(WhiteboardSnapshot snapshot) async {
    for (final card in snapshot.cards) {
      // Identity row lives in MemoryCards (memory_scope = 'user_truth',
      // type = 'note'); whiteboard-specific fields in WhiteboardCardExtras.
      await db.into(db.memoryCards).insertOnConflictUpdate(
            MemoryCardsCompanion.insert(
              id: card.cardId,
              memoryScope: const Value('user_truth'),
              type: 'note',
              title: card.title,
              dropletLabel: _dropletLabel(card.title),
              presentationModule: '[]',
              retrievalText: card.body,
              valence: 0.0,
              arousal: 0.0,
              createdAt: _toMillis(card.createdAt),
              updatedAt: card.updatedAt != null
                  ? _toMillis(card.updatedAt!)
                  : _toMillis(card.createdAt),
            ),
          );
      await db.into(db.whiteboardCardExtras).insertOnConflictUpdate(
            WhiteboardCardExtrasCompanion.insert(
              cardId: card.cardId,
              cardKind: card.cardKind.name,
              sourceId: Value(card.sourceId),
              ownerSpace: Value(card.ownerSpace.name),
              body: Value(card.body),
              tagsJson: Value(jsonEncode(card.tags)),
              presentationJson: Value(
                card.presentation.isEmpty ? null : jsonEncode(card.presentation)),
              createdBy: Value(card.createdBy.name),
              updatedAt: Value(
                card.updatedAt != null ? _toMillis(card.updatedAt!) : null),
              deletedAt: Value(
                card.deletedAt != null ? _toMillis(card.deletedAt!) : null),
            ),
          );
    }
  }

  static String _dropletLabel(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '卡片';
    return trimmed.length <= 4 ? trimmed : trimmed.substring(0, 4);
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  /// Loads the snapshot for [boardId] from Drift.
  ///
  /// Returns [SnapshotLoadResult] with the full snapshot reconstructed from
  /// the database (all boards/cards/sources round-trip, like the file store's
  /// per-board full snapshots). Missing board → error result, no throw.
  Future<SnapshotLoadResult> load(String boardId) async {
    try {
      final board = await (db.select(db.whiteboardBoards)
            ..where((b) => b.id.equals(boardId) & b.deletedAt.isNull()))
          .getSingleOrNull();
      if (board == null) {
        return SnapshotLoadResult(error: 'Board not found: $boardId');
      }

      final boards = await db.select(db.whiteboardBoards).get();
      final items = await db.select(db.whiteboardBoardItems).get();
      final groups = await db.select(db.whiteboardGroups).get();
      final groupMembers = await db.select(db.whiteboardGroupMembers).get();
      final edges = await db.select(db.whiteboardEdges).get();
      final sources = await db.select(db.whiteboardSources).get();
      final versions = await db.select(db.whiteboardSourceVersions).get();
      final cardRows = await db.select(db.memoryCards).get();
      final cardExtras = await db.select(db.whiteboardCardExtras).get();

      final extrasByCard = {for (final e in cardExtras) e.cardId: e};

      final snapshot = WhiteboardSnapshot(
        sources: [
          for (final row in sources)
            SourceContent(
              sourceId: row.id,
              mediaType: SourceMediaType.fromString(row.mediaType),
              title: row.title,
              ownerSpace: OwnerSpace.fromString(row.ownerSpace),
              origin: SourceOrigin.fromString(row.origin),
              provider: row.provider,
              canonicalId: row.canonicalId,
              mimeType: row.mimeType,
              currentVersionId: row.currentVersionId,
              contentHash: row.contentHash,
              objectRef: row.objectRef,
              metadata: _decodeMap(row.metadataJson) ?? const {},
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
              updatedAt: row.updatedAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(row.updatedAt!,
                      isUtc: true)
                  : null,
              deletedAt: row.deletedAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(row.deletedAt!,
                      isUtc: true)
                  : null,
            ),
        ],
        sourceVersions: [
          for (final row in versions)
            SourceVersion(
              versionId: row.id,
              sourceId: row.sourceId,
              contentHash: row.contentHash,
              objectRef: row.objectRef,
              parserVersion: row.parserVersion,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
            ),
        ],
        cards: [
          for (final row in cardRows)
            _toCardContract(row, extrasByCard[row.id]),
        ],
        boards: [
          for (final row in boards)
            Board(
              boardId: row.id,
              name: row.name,
              ownerSpace: OwnerSpace.fromString(row.ownerSpace),
              createdBy: CardCreatedBy.fromString(row.createdBy),
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
              updatedAt: row.updatedAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(row.updatedAt!,
                      isUtc: true)
                  : null,
              deletedAt: row.deletedAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(row.deletedAt!,
                      isUtc: true)
                  : null,
            ),
        ],
        boardItems: [
          for (final row in items)
            BoardItem(
              itemId: row.id,
              boardId: row.boardId,
              cardId: row.cardId,
              x: row.x,
              y: row.y,
              width: row.width,
              height: row.height,
              rotation: row.rotation,
              zIndex: row.zIndex,
              viewState: _decodeMap(row.viewStateJson) ?? const {},
            ),
        ],
        groups: [
          for (final row in groups)
            BoardGroup(
              groupId: row.id,
              boardId: row.boardId,
              name: row.name,
              style: _decodeMap(row.styleJson) ?? const {},
              collapsed: row.collapsed,
            ),
        ],
        groupMembers: [
          for (final row in groupMembers)
            GroupMember(
              groupId: row.groupId,
              itemId: row.itemId,
              order: row.sortOrder,
            ),
        ],
        edges: [
          for (final row in edges)
            BoardEdge(
              edgeId: row.id,
              boardId: row.boardId,
              fromItemId: row.fromItemId,
              toItemId: row.toItemId,
              direction: EdgeDirection.fromString(row.direction),
              semanticType: row.semanticType,
              label: row.label,
              style: _decodeMap(row.styleJson) ?? const {},
              createdBy: CardCreatedBy.fromString(row.createdBy),
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
              deletedAt: row.deletedAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(row.deletedAt!,
                      isUtc: true)
                  : null,
            ),
        ],
        viewport: BoardViewport(
          centerX: board.viewportCenterX,
          centerY: board.viewportCenterY,
          zoom: board.viewportZoom,
        ),
        updatedAt: board.updatedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(board.updatedAt!,
                isUtc: true)
            : null,
      );

      return SnapshotLoadResult(
        snapshot: snapshot,
        integrity: validateSnapshotIntegrity(snapshot),
      );
    } catch (e) {
      return SnapshotLoadResult(error: 'Failed to load snapshot: $e');
    }
  }

  static CardContract _toCardContract(
      MemoryCard row, WhiteboardCardExtra? extra) {
    return CardContract(
      cardId: row.id,
      cardKind: extra != null
          ? CardKind.fromString(extra.cardKind)
          : CardKind.note,
      sourceId: extra?.sourceId,
      ownerSpace: extra != null
          ? OwnerSpace.fromString(extra.ownerSpace)
          : OwnerSpace.user,
      title: row.title,
      body: row.retrievalText,
      tags: extra != null ? _decodeStringList(extra.tagsJson) : const [],
      presentation: extra != null
          ? (_decodeMap(extra.presentationJson) ?? const {})
          : const {},
      createdBy: extra != null
          ? CardCreatedBy.fromString(extra.createdBy)
          : CardCreatedBy.user,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
      updatedAt: extra?.updatedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(extra!.updatedAt!,
              isUtc: true)
          : null,
      deletedAt: extra?.deletedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(extra!.deletedAt!,
              isUtc: true)
          : null,
    );
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _decodeStringList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {}
    return const [];
  }
}
