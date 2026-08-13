import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schema v56 backfills stable message refs from v55 chat sync_ids',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('chat_sync_v56_');
    final dbFile = File('${tempDir.path}${Platform.pathSeparator}legacy.db');

    // Build a v55-shaped database with all four evidence tables populated,
    // then open it through AppDatabase so the v56 migration runs.
    final legacy = sqlite.sqlite3.open(dbFile.path);
    legacy.execute('''
      CREATE TABLE persona_chat_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        character_id TEXT NOT NULL,
        is_from_character INTEGER NOT NULL CHECK (is_from_character IN (0, 1)),
        content TEXT NOT NULL,
        fact_id TEXT,
        is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
        timestamp INTEGER NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'chat',
        attachments_json TEXT,
        sync_id TEXT,
        origin_device_id TEXT
      )
    ''');
    // v55 backfill assigns legacy-v55:<id>; mirror that here.
    legacy.execute(
      "INSERT INTO persona_chat_messages "
      "(id, character_id, is_from_character, content, is_read, timestamp, sync_id, origin_device_id) "
      "VALUES (7, 'lin-ai', 0, 'hello', 1, 1786550400, 'legacy-v55:7', 'legacy-authority'), "
      "(8, 'lin-ai', 1, 'hi back', 1, 1786550460, 'legacy-v55:8', 'legacy-authority')",
    );

    legacy.execute('''
      CREATE TABLE shared_life_event_operations (
        id TEXT NOT NULL PRIMARY KEY,
        entity_id TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        title TEXT NOT NULL,
        patch_json TEXT NOT NULL,
        source_message_ids TEXT NOT NULL,
        source_character_id TEXT NOT NULL,
        capture_task_id TEXT,
        reverts_operation_id TEXT,
        created_at INTEGER NOT NULL,
        source_kind TEXT NOT NULL DEFAULT 'chat_message',
        source_ref TEXT,
        raw_input TEXT,
        primary_domain TEXT NOT NULL DEFAULT 'general',
        facets TEXT
      )
    ''');
    legacy.execute(
      "INSERT INTO shared_life_event_operations "
      "(id, entity_id, operation_type, entity_type, title, patch_json, source_message_ids, source_character_id, created_at) "
      "VALUES ('op-1', 'e-1', 'create', 'fact', 't', '{}', '[7, 8]', 'lin-ai', 1786550500)",
    );

    legacy.execute('''
      CREATE TABLE memory_fragments (
        id TEXT NOT NULL PRIMARY KEY,
        content TEXT NOT NULL,
        source_message_ids TEXT,
        source_scope TEXT NOT NULL DEFAULT 'main_chat',
        emotional_weight REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'active',
        is_user_truth_candidate INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        character_id TEXT NOT NULL,
        saga_id TEXT,
        episode_id TEXT,
        source_analysis_json TEXT,
        discarded_reason TEXT
      )
    ''');
    legacy.execute(
      "INSERT INTO memory_fragments "
      "(id, content, source_message_ids, created_at, character_id) "
      "VALUES ('frag-1', 'a fragment', '[7]', 1786550600, 'lin-ai')",
    );

    legacy.execute('''
      CREATE TABLE memory_recall_events (
        id TEXT NOT NULL PRIMARY KEY,
        target_table TEXT NOT NULL,
        target_id TEXT NOT NULL,
        chat_message_id TEXT,
        query TEXT,
        score REAL NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    legacy.execute(
      "INSERT INTO memory_recall_events "
      "(id, target_table, target_id, chat_message_id, query, score, created_at) "
      "VALUES ('ev-1', 'memory_cards', 'card-1', '7', 'hello', 0.9, 1786550700)",
    );

    legacy.execute('''
      CREATE TABLE co_reading_session_messages (
        session_id TEXT NOT NULL,
        message_id INTEGER NOT NULL,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (session_id, message_id)
      )
    ''');
    legacy.execute(
      "INSERT INTO co_reading_session_messages (session_id, message_id, added_at) "
      "VALUES ('sess-1', 8, 1786550800)",
    );

    legacy.execute('''
      CREATE TABLE memory_card_sources (
        card_id TEXT NOT NULL PRIMARY KEY,
        raw_input TEXT NOT NULL,
        recorded_at INTEGER NOT NULL,
        recorded_place TEXT,
        source_ref TEXT,
        source_kind TEXT NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 1
      )
    ''');
    legacy.execute(
      "INSERT INTO memory_card_sources "
      "(card_id, raw_input, recorded_at, source_ref, source_kind) "
      "VALUES ('card-1', 'hello', 1786550900, '7', 'record_button')",
    );

    legacy.execute('PRAGMA user_version = 55');
    legacy.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    try {
      final ops = await db.customSelect(
        'SELECT source_sync_ids FROM shared_life_event_operations WHERE id = ?',
        variables: [Variable.withString('op-1')],
      ).getSingle();
      expect(
        ops.read<String?>('source_sync_ids'),
        '["legacy-v55:7","legacy-v55:8"]',
      );

      final frag = await db.customSelect(
        'SELECT source_sync_ids FROM memory_fragments WHERE id = ?',
        variables: [Variable.withString('frag-1')],
      ).getSingle();
      expect(
        frag.read<String?>('source_sync_ids'),
        '["legacy-v55:7"]',
      );

      final ev = await db.customSelect(
        'SELECT chat_message_sync_id FROM memory_recall_events WHERE id = ?',
        variables: [Variable.withString('ev-1')],
      ).getSingle();
      expect(
        ev.read<String?>('chat_message_sync_id'),
        'legacy-v55:7',
      );

      final co = await db.customSelect(
        'SELECT message_sync_id FROM co_reading_session_messages WHERE message_id = ?',
        variables: [Variable.withInt(8)],
      ).getSingle();
      expect(
        co.read<String?>('message_sync_id'),
        'legacy-v55:8',
      );

      final src = await db.customSelect(
        'SELECT source_sync_id FROM memory_card_sources WHERE card_id = ?',
        variables: [Variable.withString('card-1')],
      ).getSingle();
      expect(
        src.read<String?>('source_sync_id'),
        'legacy-v55:7',
      );

      // Indices created.
      final indexes = await db
          .customSelect("PRAGMA index_list('memory_recall_events')")
          .get();
      expect(
        indexes.map((row) => row.read<String>('name')),
        contains('idx_memory_recall_sync'),
      );
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });

  test('v56 migration adds nullable columns and skips empty backfill',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('chat_sync_v56_empty_');
    final dbFile = File('${tempDir.path}${Platform.pathSeparator}empty.db');

    // Minimal v55 schema: chat table carries sync_ids, evidence tables exist
    // but hold no rows that reference real messages.
    final legacy = sqlite.sqlite3.open(dbFile.path);
    legacy.execute('''
      CREATE TABLE persona_chat_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        character_id TEXT NOT NULL,
        is_from_character INTEGER NOT NULL,
        content TEXT NOT NULL,
        fact_id TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'chat',
        attachments_json TEXT,
        sync_id TEXT,
        origin_device_id TEXT
      )
    ''');
    legacy.execute('''
      CREATE TABLE shared_life_event_operations (
        id TEXT NOT NULL PRIMARY KEY,
        entity_id TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        title TEXT NOT NULL,
        patch_json TEXT NOT NULL,
        source_message_ids TEXT NOT NULL,
        source_character_id TEXT NOT NULL,
        capture_task_id TEXT,
        reverts_operation_id TEXT,
        created_at INTEGER NOT NULL,
        source_kind TEXT NOT NULL DEFAULT 'chat_message',
        source_ref TEXT,
        raw_input TEXT,
        primary_domain TEXT NOT NULL DEFAULT 'general',
        facets TEXT
      )
    ''');
    // One operation whose source message no longer exists (deleted). Backfill
    // must leave source_sync_ids NULL rather than fabricating a stable ref.
    legacy.execute(
      "INSERT INTO shared_life_event_operations "
      "(id, entity_id, operation_type, entity_type, title, patch_json, source_message_ids, source_character_id, created_at) "
      "VALUES ('op-x', 'e-x', 'create', 'fact', 't', '{}', '[9999]', 'lin-ai', 1786550900)",
    );
    legacy.execute('PRAGMA user_version = 55');
    legacy.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    try {
      final op = await db.customSelect(
        'SELECT source_sync_ids FROM shared_life_event_operations WHERE id = ?',
        variables: [Variable.withString('op-x')],
      ).getSingle();
      // Dangling int ref -> no stable ref written (stays NULL).
      expect(op.read<String?>('source_sync_ids'), isNull);

      final cols = await db
          .customSelect("PRAGMA table_info('shared_life_event_operations')")
          .get();
      expect(
        cols.map((row) => row.read<String>('name')),
        containsAll(['source_sync_ids', 'source_message_ids']),
      );
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });

  test('schema v57 creates the sync outbox table on upgrade', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('chat_sync_v57_');
    final dbFile = File('${tempDir.path}${Platform.pathSeparator}legacy.db');

    // v56-shaped minimal database: chat + outbox prerequisite tables, with the
    // sync columns from v55/v56 present.
    final legacy = sqlite.sqlite3.open(dbFile.path);
    legacy.execute('''
      CREATE TABLE persona_chat_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        character_id TEXT NOT NULL,
        is_from_character INTEGER NOT NULL,
        content TEXT NOT NULL,
        fact_id TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'chat',
        attachments_json TEXT,
        sync_id TEXT,
        origin_device_id TEXT
      )
    ''');
    legacy.execute('PRAGMA user_version = 56');
    legacy.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    try {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString('sync_outbox_messages')],
      ).get();
      expect(tables, hasLength(1));

      final idx = await db
          .customSelect("PRAGMA index_list('sync_outbox_messages')")
          .get();
      expect(
        idx.map((row) => row.read<String>('name')),
        contains('idx_sync_outbox_device_seq'),
      );
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });
}
