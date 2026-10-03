import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'v61 outbox upgrade keeps pending identities and defaults sender to user',
      () async {
    final dir = await Directory.systemTemp.createTemp('b3_transcript_v62_');
    final file = File('${dir.path}${Platform.pathSeparator}synthetic.db');
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''CREATE TABLE sync_outbox_messages (
      sync_id TEXT NOT NULL PRIMARY KEY, origin_device_id TEXT NOT NULL,
      origin_sequence INTEGER NOT NULL, character_id TEXT NOT NULL,
      content TEXT NOT NULL, created_at_ms INTEGER NOT NULL,
      message_type TEXT NOT NULL DEFAULT 'chat', asset_refs_json TEXT
    )''');
    legacy.execute(
        "INSERT INTO sync_outbox_messages VALUES('synthetic:pending','approved-phone',19,'lin-ai','synthetic pending',1791028800123,'chat',NULL)");
    legacy.execute('PRAGMA user_version=61');
    legacy.dispose();
    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final row = (await db.select(db.syncOutboxMessages).get()).single;
      expect(row.syncId, 'synthetic:pending');
      expect(row.originDeviceId, 'approved-phone');
      expect(row.originSequence, 19);
      expect(row.characterId, 'lin-ai');
      expect(row.content, 'synthetic pending');
      expect(row.createdAtMs, 1791028800123);
      expect(row.sender, 'user');
      expect(row.assetRefsJson, isNull);
      expect(
          (await db.customSelect('PRAGMA user_version').get())
              .single
              .read<int>('user_version'),
          62);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
