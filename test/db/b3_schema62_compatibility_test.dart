import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

// Frozen generator output from B3, not derived from the implementation under test.
final _b3Ddl = File('test/db/fixtures/b3_schema62.sql').readAsStringSync();
const _device = 'synthetic-installation';

sqlite.Database _createFixture(File file, int version) {
  final raw = sqlite.sqlite3.open(file.path);
  raw.execute(_b3Ddl);
  if (version < 62) {
    raw.execute('ALTER TABLE sync_outbox_messages DROP COLUMN sender');
  }
  if (version < 61) {
    raw.execute('ALTER TABLE persona_chat_messages DROP COLUMN created_at_ms');
    raw.execute(
        'ALTER TABLE persona_chat_messages DROP COLUMN server_sequence');
  }
  raw.execute('PRAGMA user_version = $version');
  raw.execute('''INSERT INTO persona_chat_messages
    (id,sync_id,origin_device_id,character_id,is_from_character,content,
     fact_id,is_read,timestamp,message_type,attachments_json,task_room_id)
    VALUES (7,'synthetic:7','synthetic-installation','lin-ai',0,'legacy user',
      'synthetic-fact',1,1791028800,'chat','[]','synthetic-room')''');
  raw.execute('''INSERT INTO sync_outbox_messages
    (sync_id,origin_device_id,origin_sequence,character_id,content,created_at_ms,
     message_type,asset_refs_json)
    VALUES ('synthetic:7','synthetic-installation',19,'lin-ai','legacy user',
      1791028800123,'chat','[]')''');
  raw.execute('''INSERT INTO kv_store (key,value,bucket,updated_at)
    VALUES ('cursor.synthetic-installation.synthetic-core','opaque-cursor',
      'core_sync',1791028800123)''');
  if (version >= 61) {
    raw.execute('''UPDATE persona_chat_messages
      SET created_at_ms=1791028800123,server_sequence=73 WHERE id=7''');
  }
  if (version >= 62) {
    raw.execute('''INSERT INTO persona_chat_messages
      (id,sync_id,origin_device_id,created_at_ms,server_sequence,character_id,
       is_from_character,content,timestamp)
      VALUES (8,'synthetic:8','synthetic-installation',1791028800456,74,
       'lin-ai',1,'local companion',1791028800)''');
    raw.execute('''INSERT INTO sync_outbox_messages
      (sync_id,origin_device_id,sender,origin_sequence,character_id,content,
       created_at_ms) VALUES ('synthetic:8','synthetic-installation','companion',
       20,'lin-ai','local companion',1791028800456)''');
  }
  return raw;
}

Map<String, String> _schema(sqlite.Database raw) => {
      for (final row in raw.select("SELECT name,sql FROM sqlite_master "
          "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name"))
        row['name'] as String: row['sql'] as String,
    };

Map<String, Object?> _row(Map<String, Object?> value) => Map.of(value);

Future<void> _expectPreserved(AppDatabase db, {required int from}) async {
  expect(db.schemaVersion, 62);
  expect((await db.customSelect('PRAGMA user_version').get()).single.data,
      {'user_version': 62});
  final chat = await (db.select(db.personaChatMessages)
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();
  expect(chat.length, from == 62 ? 2 : 1);
  final legacy = chat.first;
  expect(legacy.id, 7);
  expect(legacy.syncId, 'synthetic:7');
  expect(legacy.originDeviceId, _device);
  expect(legacy.characterId, 'lin-ai');
  expect(legacy.content, 'legacy user');
  expect(legacy.factId, 'synthetic-fact');
  expect(legacy.isRead, isTrue);
  expect(legacy.timestamp.millisecondsSinceEpoch, 1791028800000);
  expect(legacy.messageType, 'chat');
  expect(legacy.attachmentsJson, '[]');
  expect(legacy.taskRoomId, 'synthetic-room');
  expect(legacy.createdAtMs, from >= 61 ? 1791028800123 : null);
  expect(legacy.serverSequence, from >= 61 ? 73 : null);
  final outbox = await (db.select(db.syncOutboxMessages)
        ..orderBy([(t) => OrderingTerm.asc(t.originSequence)]))
      .get();
  expect(outbox.length, from == 62 ? 2 : 1);
  expect(outbox.first.syncId, 'synthetic:7');
  expect(outbox.first.originDeviceId, _device);
  expect(outbox.first.originSequence, 19);
  expect(outbox.first.sender, 'user');
  expect(outbox.first.characterId, 'lin-ai');
  expect(outbox.first.content, 'legacy user');
  expect(outbox.first.createdAtMs, 1791028800123);
  expect(outbox.first.messageType, 'chat');
  expect(outbox.first.assetRefsJson, '[]');
  if (from == 62) {
    expect(chat.last.syncId, 'synthetic:8');
    expect(chat.last.isFromCharacter, isTrue);
    expect(chat.last.createdAtMs, 1791028800456);
    expect(chat.last.serverSequence, 74);
    expect(outbox.last.syncId, 'synthetic:8');
    expect(outbox.last.sender, 'companion');
    expect(outbox.last.originSequence, 20);
  }
  final cursor = (await db.select(db.kvStore).get()).single;
  expect(cursor.key, 'cursor.synthetic-installation.synthetic-core');
  expect(cursor.value, 'opaque-cursor');
  expect(cursor.bucket, 'core_sync');
  expect(cursor.updatedAt, 1791028800123);
  // Installation identity lives in preferences, not inside the SQLite file.
  expect(await DeviceIdentityService.getOrCreate(), _device);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {DeviceIdentityService.preferenceKey: _device});
    DeviceIdentityService.resetForTesting();
  });
  tearDown(DeviceIdentityService.resetForTesting);

  test(
      'B3 exact schema62 copy opens and reopens without downgrade or data loss',
      () async {
    final dir = await Directory.systemTemp.createTemp('b3_schema62_copy_');
    addTearDown(() => dir.delete(recursive: true));
    final original = File('${dir.path}/b3-original.db');
    final raw = _createFixture(original, 62);
    final expectedSchema = _schema(raw);
    final expectedRows = {
      for (final table in [
        'persona_chat_messages',
        'sync_outbox_messages',
        'kv_store'
      ])
        table: raw.select('SELECT * FROM $table').map(_row).toList(),
    };
    raw.dispose();
    final originalBytes = await original.readAsBytes();
    final copy = await original.copy('${dir.path}/mainline-copy.db');

    for (var reopen = 0; reopen < 2; reopen++) {
      final db = AppDatabase.forTesting(NativeDatabase(copy));
      try {
        await _expectPreserved(db, from: 62);
      } finally {
        await db.close();
      }
      final actual = sqlite.sqlite3.open(copy.path);
      try {
        expect(_schema(actual), expectedSchema);
        for (final entry in expectedRows.entries) {
          expect(actual.select('SELECT * FROM ${entry.key}').map(_row).toList(),
              entry.value);
        }
        expect(actual.select('PRAGMA integrity_check').single.values, ['ok']);
      } finally {
        actual.dispose();
      }
    }
    expect(await original.readAsBytes(), originalBytes);
  });

  for (final from in [60, 61]) {
    test('v$from to 62 matches B3 SQL and preserves existing records',
        () async {
      final dir = await Directory.systemTemp.createTemp('b3_migrate_$from');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/candidate.db');
      _createFixture(file, from).dispose();
      final expectedFile = await file.copy('${dir.path}/b3-expected.db');
      final expected = sqlite.sqlite3.open(expectedFile.path);
      // Independent frozen B3 61/62 SQL, in the same order as its migration.
      if (from < 61) {
        expected.execute(
            'ALTER TABLE persona_chat_messages ADD COLUMN created_at_ms INTEGER');
        expected.execute(
            'ALTER TABLE persona_chat_messages ADD COLUMN server_sequence INTEGER');
      }
      expected.execute(
          "ALTER TABLE sync_outbox_messages ADD COLUMN sender TEXT NOT NULL DEFAULT 'user'");
      final expectedSchema = _schema(expected);
      expected.dispose();
      final db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await _expectPreserved(db, from: from);
        final columns = await db
            .customSelect('PRAGMA table_info(persona_chat_messages)')
            .get();
        for (final name in ['created_at_ms', 'server_sequence']) {
          final column =
              columns.singleWhere((r) => r.data['name'] == name).data;
          expect(column['type'], 'INTEGER');
          expect(column['notnull'], 0);
          expect(column['dflt_value'], isNull);
        }
        final sender = (await db
                .customSelect('PRAGMA table_info(sync_outbox_messages)')
                .get())
            .singleWhere((r) => r.data['name'] == 'sender')
            .data;
        expect(sender['type'], 'TEXT');
        expect(sender['notnull'], 1);
        expect(sender['dflt_value'], "'user'");
      } finally {
        await db.close();
      }
      final actual = sqlite.sqlite3.open(file.path);
      try {
        expect(_schema(actual), expectedSchema);
        expect(actual.select('PRAGMA integrity_check').single.values, ['ok']);
      } finally {
        actual.dispose();
      }
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await _expectPreserved(reopened, from: from);
      } finally {
        await reopened.close();
      }
    });
  }

  test('fresh mainline chat and outbox definitions equal frozen B3 DDL',
      () async {
    final expected = sqlite.sqlite3.openInMemory()..execute(_b3Ddl);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      for (final table in ['persona_chat_messages', 'sync_outbox_messages']) {
        final actual = await db.customSelect('PRAGMA table_info($table)').get();
        expect(actual.map((r) => r.data).toList(),
            expected.select('PRAGMA table_info($table)').map(_row).toList());
      }
    } finally {
      await db.close();
      expected.dispose();
    }
  });
}
