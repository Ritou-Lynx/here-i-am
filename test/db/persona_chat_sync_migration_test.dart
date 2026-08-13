import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schema v55 backfills stable chat identities without changing local ids',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('chat_sync_v55_');
    final dbFile = File('${tempDir.path}${Platform.pathSeparator}legacy.db');

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
        attachments_json TEXT
      )
    ''');
    legacy.execute(
      'INSERT INTO persona_chat_messages '
      '(id, character_id, is_from_character, content, is_read, timestamp) '
      "VALUES (7, 'lin-ai', 0, 'hello', 1, 1786550400)",
    );
    legacy.execute('PRAGMA user_version = 54');
    legacy.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    try {
      final rows = await db.select(db.personaChatMessages).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 7);
      expect(rows.single.syncId, 'legacy-v55:7');
      expect(rows.single.originDeviceId, 'legacy-authority');

      final indexes = await db
          .customSelect("PRAGMA index_list('persona_chat_messages')")
          .get();
      expect(
        indexes.map((row) => row.read<String>('name')),
        contains('idx_persona_chat_sync_id'),
      );
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });
}
