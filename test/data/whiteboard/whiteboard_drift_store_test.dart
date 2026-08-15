import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

/// W6 whiteboard integration base — Drift store round-trip tests.
void main() {
  const fixtureBoardId = 'board_whiteboard_mvp';

  late File tempDbFile;
  late AppDatabase db;
  late WhiteboardDriftStore store;

  setUp(() {
    final tempDir = Directory.systemTemp.createTempSync('whiteboard_store_test_');
    tempDbFile = File('${tempDir.path}/test.db');
    db = AppDatabase.forTesting(NativeDatabase(tempDbFile));
    store = WhiteboardDriftStore(db);
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    try {
      tempDbFile.deleteSync();
      tempDbFile.parent.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<WhiteboardSnapshot> loadFixture() async {
    final raw =
        File('test/domain/whiteboard/fixtures/normal_snapshot.json')
            .readAsStringSync();
    return loadSnapshot(jsonDecode(raw) as Map<String, dynamic>);
  }

  test('full fixture snapshot round-trips through Drift unchanged', () async {
    final snapshot = await loadFixture();
    expect(snapshot.boards.map((b) => b.boardId), contains(fixtureBoardId));

    final saved = await store.save(fixtureBoardId, snapshot);
    expect(saved, isTrue);

    final result = await store.load(fixtureBoardId);
    expect(result.isSuccess, isTrue);
    expect(result.integrity?.isValid, isTrue, reason: 'fixture is integral');

    final loaded = result.snapshot!;
    expect(jsonEncode(loaded.toJson()), jsonEncode(snapshot.toJson()),
        reason: 'snapshot must round-trip byte-for-byte');
  });

  test('empty board snapshot round-trips', () async {
    final boardId = await store.createBoard(name: '空白板');
    final savedAt = DateTime.utc(2026, 8, 15, 10);
    // The target board row carries the snapshot's updatedAt (save-time
    // normalization), so entity and snapshot timestamps must agree here.
    final snapshot = WhiteboardSnapshot(
      boards: [
        Board(
          boardId: boardId,
          name: '空白板',
          createdAt: DateTime.utc(2026, 8, 15),
          updatedAt: savedAt,
        ),
      ],
      viewport: const BoardViewport(centerX: 12, centerY: -34, zoom: 0.5),
      updatedAt: savedAt,
    );

    expect(await store.save(boardId, snapshot), isTrue);
    final result = await store.load(boardId);
    expect(result.isSuccess, isTrue);
    expect(result.integrity?.isValid, isTrue);
    expect(jsonEncode(result.snapshot!.toJson()),
        jsonEncode(snapshot.toJson()));
  });

  test('saving a board replaces its items but never deletes cards', () async {
    final first = await loadFixture();
    expect(await store.save(fixtureBoardId, first), isTrue);

    final second = WhiteboardSnapshot(
      boards: first.boards,
      sources: first.sources,
      sourceVersions: first.sourceVersions,
      cards: const [], // second snapshot omits all cards
      boardItems: [
        BoardItem(
          itemId: 'item_new',
          boardId: fixtureBoardId,
          cardId: first.cards.first.cardId,
          x: 5,
          y: 6,
        ),
      ],
      groups: const [],
      groupMembers: const [],
      edges: const [],
      viewport: const BoardViewport(),
      updatedAt: DateTime.utc(2026, 8, 15, 12),
    );
    expect(await store.save(fixtureBoardId, second), isTrue);

    final result = await store.load(fixtureBoardId);
    final loaded = result.snapshot!;

    // Board-scoped entities replaced, not accumulated.
    expect(loaded.boardItems.map((i) => i.itemId), ['item_new']);
    expect(loaded.groups, isEmpty);
    expect(loaded.edges, isEmpty);

    // Cards are additive — a snapshot that omits them must not delete them.
    expect(loaded.cards.map((c) => c.cardId).toSet(),
        first.cards.map((c) => c.cardId).toSet());
    expect(loaded.sources.length, first.sources.length);
    expect(loaded.sourceVersions.length, first.sourceVersions.length);
  });

  test('viewport is per-board and round-trips with the target board',
      () async {
    final snapshot = await loadFixture();
    final other = snapshot.boards.firstWhere(
        (b) => b.boardId != fixtureBoardId);
    final withViewport = WhiteboardSnapshot(
      boards: snapshot.boards,
      sources: snapshot.sources,
      sourceVersions: snapshot.sourceVersions,
      cards: snapshot.cards,
      boardItems: snapshot.boardItems,
      groups: snapshot.groups,
      groupMembers: snapshot.groupMembers,
      edges: snapshot.edges,
      viewport: const BoardViewport(centerX: 888, centerY: 777, zoom: 2.5),
      updatedAt: snapshot.updatedAt,
    );

    // Save the whole snapshot under board A; board B's viewport must not
    // be clobbered by board A's viewport when B loads.
    expect(await store.save(fixtureBoardId, withViewport), isTrue);
    final a = await store.load(fixtureBoardId);
    expect(a.snapshot!.viewport.centerX, 888);

    final b = await store.load(other.boardId);
    expect(b.snapshot!.viewport.centerX, 0,
        reason: 'board B keeps its own viewport, untouched by board A save');
  });

  test('missing board load returns error result without throwing', () async {
    final result = await store.load('board_does_not_exist');
    expect(result.isSuccess, isFalse);
    expect(result.error, contains('not found'));
  });

  test('invalid dangling refs are reported via integrity', () async {
    final snapshot = WhiteboardSnapshot(
      boards: [
        Board(
          boardId: 'board_dangling',
          name: 'Dangling',
          createdAt: DateTime.utc(2026, 8, 15),
        ),
      ],
      boardItems: [
        const BoardItem(
          itemId: 'item_x',
          boardId: 'board_dangling',
          cardId: 'card_no_such_card',
        ),
      ],
      updatedAt: DateTime.utc(2026, 8, 15, 10),
    );
    expect(await store.save('board_dangling', snapshot), isTrue);

    final result = await store.load('board_dangling');
    expect(result.isSuccess, isTrue);
    expect(result.hasIntegrityIssues, isTrue);
  });

  test('listBoards returns non-deleted boards newest-first', () async {
    await store.createBoard(name: 'B1');
    await store.createBoard(name: 'B2');
    await store.createBoard(name: 'B3');

    final boards = await store.listBoards();
    expect(boards.map((b) => b.name), ['B3', 'B2', 'B1']);

    // Soft delete removes the board from listings and lookups.
    expect(await store.delete(boards.first.boardId), isTrue);
    final after = await store.listBoards();
    expect(after.map((b) => b.name), ['B2', 'B1']);
    expect(await store.exists(boards.first.boardId), isFalse);
  });

  test('delete removes board-scoped rows but keeps cards and sources',
      () async {
    final snapshot = await loadFixture();
    expect(await store.save(fixtureBoardId, snapshot), isTrue);
    final before = await store.load(fixtureBoardId);

    expect(await store.delete(fixtureBoardId), isTrue);
    // Board-scoped data is gone.
    final itemRows = await db.select(db.whiteboardBoardItems).get();
    expect(itemRows.where((r) => r.boardId == fixtureBoardId), isEmpty);

    // Cards/sources survive deletion of the board.
    final cardIds = await db.select(db.whiteboardCardExtras).get();
    expect(cardIds.map((c) => c.cardId).toSet(),
        before.snapshot!.cards.map((c) => c.cardId).toSet());
    final sourceRows = await db.select(db.whiteboardSources).get();
    expect(sourceRows.length, before.snapshot!.sources.length);

    // Loading a deleted board behaves like a missing board.
    final after = await store.load(fixtureBoardId);
    expect(after.isSuccess, isFalse);
  });

  test('cards are stored as MemoryCards identity + WhiteboardCardExtras',
      () async {
    final snapshot = await loadFixture();
    expect(await store.save(fixtureBoardId, snapshot), isTrue);

    final memoryRows = await db.select(db.memoryCards).get();
    expect(memoryRows.map((r) => r.id).toSet(),
        snapshot.cards.map((c) => c.cardId).toSet());
    for (final row in memoryRows) {
      expect(row.memoryScope, 'user_truth');
      expect(row.type, 'note');
      expect(row.title, isNotEmpty);
    }

    final extras = await db.select(db.whiteboardCardExtras).get();
    expect(extras.length, snapshot.cards.length);
    final book =
        extras.firstWhere((e) => e.cardId == 'card_book_zhishen');
    expect(book.cardKind, 'source');
    expect(book.sourceId, 'src_book_zhishen');
    expect(jsonDecode(book.tagsJson), ['书籍', '经济']);
  });

  test('restart recovery: data survives closing and reopening the database',
      () async {
    final snapshot = await loadFixture();
    expect(await store.save(fixtureBoardId, snapshot), isTrue);
    await db.close();

    // "Restart": reopen the same file with a brand-new AppDatabase.
    final reopened = AppDatabase.forTesting(NativeDatabase(tempDbFile));
    final reopenedStore = WhiteboardDriftStore(reopened);

    final result = await reopenedStore.load(fixtureBoardId);
    expect(result.isSuccess, isTrue);
    expect(jsonEncode(result.snapshot!.toJson()),
        jsonEncode(snapshot.toJson()));

    final boards = await reopenedStore.listBoards();
    expect(boards.map((b) => b.boardId), contains(fixtureBoardId));

    await reopened.close();
  });
}
