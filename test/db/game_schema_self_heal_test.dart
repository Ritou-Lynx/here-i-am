import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/db/app_database.dart';

/// Regression coverage for the game library being completely unusable on
/// devices that played before the `GameCharacterCards` -> `GameDefinitions`
/// refactor.
///
/// `game_definitions` was a brand-new table name, so it got created with the
/// current schema. `game_sessions` kept its name, and `Migrator.createTable`
/// is a no-op on an existing table, so the pre-refactor columns
/// (`card_id`/`card_title`/`card_snapshot_json`, and no `game_type`) survived
/// every upgrade. Every session INSERT then failed with "no such column",
/// which surfaced in the UI as a start button that did nothing at all.
void main() {
  late Directory tempRoot;
  late File dbFile;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('game_schema_self_heal_');
    dbFile = File('${tempRoot.path}${Platform.pathSeparator}app.sqlite');
    WhiteboardDataBootstrap.setRepositoryForTesting(null);
    WhiteboardDataBootstrap.setProductionRootForTesting(tempRoot);
  });

  tearDown(() async {
    WhiteboardDataBootstrap.setRepositoryForTesting(null);
    WhiteboardDataBootstrap.setProductionRootForTesting(null);
    if (AppDatabase.isInitialized) await AppDatabase.instance.close();
    AppDatabase.setDatabaseFactoryForTesting(null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<AppDatabase> openOnDbFile() async {
    AppDatabase.setDatabaseFactoryForTesting(
      (_) => AppDatabase.forTesting(NativeDatabase(dbFile)),
    );
    await AppDatabase.init('desktop_local');
    return AppDatabase.instance;
  }

  Future<void> closeCurrent() async {
    if (AppDatabase.isInitialized) await AppDatabase.instance.close();
    AppDatabase.setDatabaseFactoryForTesting(null);
  }

  Future<Set<String>> columnsOf(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  /// Reproduce the exact broken shape observed on the device: a healthy,
  /// current-schema `game_definitions` next to a `game_sessions` still on the
  /// pre-refactor column names. Returns the planted columns, which can only be
  /// observed on this connection -- any later open repairs them in beforeOpen.
  Future<Set<String>> plantPreRefactorSessionsTable() async {
    final db = await openOnDbFile();
    await db.customStatement('DROP TABLE IF EXISTS game_sessions');
    await db.customStatement('''
      CREATE TABLE "game_sessions" (
        "id" TEXT NOT NULL,
        "card_id" TEXT NULL,
        "card_title" TEXT NOT NULL,
        "card_snapshot_json" TEXT NOT NULL,
        "session_title" TEXT NOT NULL,
        "status" TEXT NOT NULL DEFAULT 'active',
        "parent_session_id" TEXT NULL,
        "branch_from_message_id" INTEGER NULL,
        "world_state_json" TEXT NULL,
        "story_summary" TEXT NULL,
        "game_log_injected" INTEGER NOT NULL DEFAULT 0
            CHECK ("game_log_injected" IN (0, 1)),
        "created_at" INTEGER NOT NULL,
        "last_played_at" INTEGER NOT NULL,
        PRIMARY KEY ("id")
      )
    ''');
    final planted = await columnsOf(db, 'game_sessions');
    await closeCurrent();
    return planted;
  }

  GameSession sessionRow({required String id, required String title}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return GameSession(
      id: id,
      definitionId: 'def_1',
      gameType: 'card_roleplay',
      definitionTitle: title,
      definitionSnapshotJson: '{"name":"$title"}',
      sessionTitle: 'first meeting',
      status: 'active',
      gameLogInjected: false,
      createdAt: now,
      lastPlayedAt: now,
    );
  }

  test('pre-refactor game_sessions is rebuilt on the current schema', () async {
    // The broken shape only exists on the connection that plants it: the very
    // next open runs beforeOpen and repairs the table.
    final brokenCols = await plantPreRefactorSessionsTable();
    expect(brokenCols, contains('card_snapshot_json'));
    expect(brokenCols, isNot(contains('game_type')));

    // Reopening runs beforeOpen, which must repair the table.
    final healed = await openOnDbFile();
    final cols = await columnsOf(healed, 'game_sessions');
    expect(cols, contains('definition_id'));
    expect(cols, contains('definition_title'));
    expect(cols, contains('definition_snapshot_json'));
    expect(cols, contains('game_type'));
    expect(cols, isNot(contains('card_snapshot_json')));
  });

  test('session insert succeeds after self-heal', () async {
    await plantPreRefactorSessionsTable();

    final db = await openOnDbFile();
    // This is the write that previously threw "no such column" and left the
    // start button looking inert.
    await db
        .into(db.gameSessions)
        .insert(sessionRow(id: 'session_after_heal', title: 'adele'));

    final stored = await db.select(db.gameSessions).get();
    expect(stored, hasLength(1));
    expect(stored.single.definitionTitle, 'adele');
    expect(stored.single.gameType, 'card_roleplay');
  });

  test('healthy game schema is left untouched', () async {
    final first = await openOnDbFile();
    final before = await columnsOf(first, 'game_sessions');
    expect(before, contains('definition_snapshot_json'));

    await first
        .into(first.gameSessions)
        .insert(sessionRow(id: 'survivor', title: 'keep_me'));
    await closeCurrent();

    // A second open must not drop rows from an already-correct table.
    final second = await openOnDbFile();
    expect(await columnsOf(second, 'game_sessions'), before);
    final rows = await second.select(second.gameSessions).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'survivor');
  });
}
