import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:matcher/matcher.dart' as matcher;

/// W6 whiteboard integration base — schema v59 migration tests.
///
/// Covers: fresh empty database (onCreate), real v58 → v59 upgrade,
/// interrupted-upgrade self-healing, index verification, and data
/// preservation across the upgrade.
void main() {
  late File tempDbFile;
  late Database rawDb;

  const whiteboardTables = [
    'whiteboard_boards',
    'whiteboard_board_items',
    'whiteboard_groups',
    'whiteboard_group_members',
    'whiteboard_edges',
    'whiteboard_sources',
    'whiteboard_source_versions',
    'whiteboard_card_extras',
  ];

  const whiteboardIndices = [
    'idx_whiteboard_items_board',
    'idx_whiteboard_groups_board',
    'idx_whiteboard_group_members_item',
    'idx_whiteboard_edges_board',
    'idx_whiteboard_sources_canonical',
    'idx_whiteboard_source_versions_source',
    'idx_whiteboard_card_extras_source',
  ];

  setUp(() {
    final tempDir =
        Directory.systemTemp.createTempSync('whiteboard_migration_test_');
    tempDbFile = File('${tempDir.path}/test.db');
  });

  tearDown(() {
    try {
      rawDb.dispose();
    } catch (_) {}
    try {
      tempDbFile.deleteSync();
      tempDbFile.parent.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<List<String>> tableNames(AppDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ).get();
    return rows.map((row) => row.data['name'] as String).toList();
  }

  Future<List<String>> indexNames(AppDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index'",
    ).get();
    return rows.map((row) => row.data['name'] as String).toList();
  }

  test('fresh database (onCreate) builds all whiteboard tables and indices',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    final version =
        await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 59);

    final tables = await tableNames(db);
    for (final table in whiteboardTables) {
      expect(tables, contains(table), reason: 'missing table $table');
    }

    final indices = await indexNames(db);
    for (final index in whiteboardIndices) {
      expect(indices, contains(index), reason: 'missing index $index');
    }

    // New tables are writable and round-trip basic rows.
    await db.into(db.whiteboardBoards).insert(
          WhiteboardBoardsCompanion.insert(
            id: 'board_a',
            name: 'A',
            createdAt: 1000,
          ),
        );
    await db.into(db.whiteboardBoardItems).insert(
          WhiteboardBoardItemsCompanion.insert(
            id: 'item_1',
            boardId: 'board_a',
            cardId: 'card_1',
            x: const Value(1.5),
            y: const Value(2.5),
          ),
        );
    final item = await (db.select(db.whiteboardBoardItems)
          ..where((i) => i.id.equals('item_1')))
        .getSingle();
    expect(item.boardId, 'board_a');
    expect(item.x, 1.5);

    await db.close();
  });

  test('v58 → v59 upgrade creates whiteboard tables, indices, keeps data',
      () async {
    // 1. Build a real v58 database with pre-existing data.
    rawDb = sqlite3.open(tempDbFile.path);
    rawDb.execute('''
      CREATE TABLE persona_chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        character_id TEXT NOT NULL,
        is_from_character INTEGER NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    rawDb.execute('PRAGMA user_version = 58');
    rawDb.execute('''
      INSERT INTO persona_chat_messages
      (character_id, is_from_character, content, timestamp)
      VALUES ('char-1', 0, 'pre-existing row', 1000000)
    ''');
    rawDb.dispose();

    // 2. Open — triggers v58 → v59 migration.
    final db = AppDatabase.forTesting(NativeDatabase(tempDbFile));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 59);

    final tables = await tableNames(db);
    for (final table in whiteboardTables) {
      expect(tables, contains(table), reason: 'missing table $table');
    }

    final indices = await indexNames(db);
    for (final index in whiteboardIndices) {
      expect(indices, contains(index), reason: 'missing index $index');
    }

    // 3. Pre-existing data survives.
    final oldMessage = await db.customSelect(
      'SELECT * FROM persona_chat_messages WHERE id = 1',
    ).getSingleOrNull();
    expect(oldMessage, matcher.isNotNull);
    expect(oldMessage!.data['content'], 'pre-existing row');

    // 4. New tables accept data after upgrade.
    await db.into(db.whiteboardBoards).insert(
          WhiteboardBoardsCompanion.insert(
            id: 'board_upgraded',
            name: 'Upgraded',
            createdAt: 2000,
          ),
        );
    final board = await (db.select(db.whiteboardBoards)
          ..where((b) => b.id.equals('board_upgraded')))
        .getSingleOrNull();
    expect(board, matcher.isNotNull);
    expect(board!.name, 'Upgraded');

    await db.close();
  });

  test(
      'v58 → v59 migration self-heals an interrupted partial state '
      '(some tables exist, indices missing)', () async {
    // An interrupted upgrade may leave user_version=58 with a few whiteboard
    // tables already created (createTable is atomic per table, so a partial
    // state means full tables) but indices absent; the migration must be
    // idempotent instead of failing on "already exists".
    rawDb = sqlite3.open(tempDbFile.path);
    rawDb.execute('''
      CREATE TABLE whiteboard_boards (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        owner_space TEXT NOT NULL DEFAULT 'user',
        created_by TEXT NOT NULL DEFAULT 'user',
        viewport_center_x REAL NOT NULL DEFAULT 0,
        viewport_center_y REAL NOT NULL DEFAULT 0,
        viewport_zoom REAL NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        deleted_at INTEGER
      )
    ''');
    rawDb.execute('''
      CREATE TABLE whiteboard_board_items (
        id TEXT PRIMARY KEY NOT NULL,
        board_id TEXT NOT NULL,
        card_id TEXT NOT NULL,
        x REAL NOT NULL DEFAULT 0,
        y REAL NOT NULL DEFAULT 0,
        width REAL NOT NULL DEFAULT 260,
        height REAL NOT NULL DEFAULT 200,
        rotation REAL NOT NULL DEFAULT 0,
        z_index INTEGER NOT NULL DEFAULT 0,
        view_state_json TEXT
      )
    ''');
    rawDb.execute('PRAGMA user_version = 58');
    rawDb.execute('''
      INSERT INTO whiteboard_boards (id, name, created_at)
      VALUES ('board_partial', 'Partial', 1)
    ''');
    rawDb.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(tempDbFile));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 59);

    // Missing tables were created, existing tables untouched (data kept).
    final tables = await tableNames(db);
    for (final table in whiteboardTables) {
      expect(tables, contains(table), reason: 'missing table $table');
    }
    final partial = await (db.select(db.whiteboardBoards)
          ..where((b) => b.id.equals('board_partial')))
        .getSingleOrNull();
    expect(partial, matcher.isNotNull);
    expect(partial!.name, 'Partial');

    final indices = await indexNames(db);
    for (final index in whiteboardIndices) {
      expect(indices, contains(index), reason: 'missing index $index');
    }

    await db.close();
  });
}
