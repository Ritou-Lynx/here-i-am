import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'v60 upgrade preserves legacy ids and adds nullable core ordering fields',
      () async {
    final dir = await Directory.systemTemp.createTemp('b3_order_v61_');
    final file = File('${dir.path}${Platform.pathSeparator}synthetic.db');
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''CREATE TABLE persona_chat_messages (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT, origin_device_id TEXT, character_id TEXT NOT NULL,
      is_from_character INTEGER NOT NULL, content TEXT NOT NULL, fact_id TEXT,
      is_read INTEGER NOT NULL DEFAULT 0, timestamp INTEGER NOT NULL,
      message_type TEXT NOT NULL DEFAULT 'chat', attachments_json TEXT, task_room_id TEXT
    )''');
    legacy.execute(
        "INSERT INTO persona_chat_messages(id,sync_id,origin_device_id,character_id,is_from_character,content,timestamp) VALUES(7,'synthetic:7','ordinary','lin-ai',0,'synthetic legacy',1786550400)");
    legacy.execute('PRAGMA user_version=60');
    legacy.dispose();
    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final row = (await db.select(db.personaChatMessages).get()).single;
      expect(row.id, 7);
      expect(row.syncId, 'synthetic:7');
      expect(row.content, 'synthetic legacy');
      expect(row.createdAtMs, isNull);
      expect(row.serverSequence, isNull);
      final columns = await db
          .customSelect("PRAGMA table_info('persona_chat_messages')")
          .get();
      expect(columns.map((r) => r.read<String>('name')),
          containsAll(['created_at_ms', 'server_sequence']));
      expect(
          (await db.customSelect('PRAGMA user_version').get())
              .single
              .read<int>('user_version'),
          61);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
