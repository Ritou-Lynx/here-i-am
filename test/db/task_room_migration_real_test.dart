import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:matcher/matcher.dart' as matcher;

/// 真实 v57 → v58 迁移测试
///
/// 此测试创建一个真正的 v57 数据库，插入数据，然后执行升级到 v58。
/// 这验证了实际的迁移路径，而不是从空数据库创建 v58。
void main() {
  late File tempDbFile;
  late Database rawDb;

  setUp(() {
    // 创建临时数据库文件
    final tempDir = Directory.systemTemp.createTempSync('task_room_migration_test_');
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

  test('v57 → v58 migration creates TaskRooms tables and adds PersonaChatMessages.taskRoomId', () async {
    // ========================================================================
    // 1. 创建 v57 数据库
    // ========================================================================
    rawDb = sqlite3.open(tempDbFile.path);

    // 创建 v57 schema 的关键表（只创建迁移依赖的表）
    rawDb.execute('''
      CREATE TABLE persona_chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        sync_id TEXT,
        origin_device_id TEXT,
        character_id TEXT NOT NULL,
        is_from_character INTEGER NOT NULL,
        content TEXT NOT NULL,
        fact_id TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'chat',
        attachments_json TEXT
      )
    ''');

    // 设置 user_version = 57
    rawDb.execute('PRAGMA user_version = 57');

    // 插入测试数据到 v57 表
    rawDb.execute('''
      INSERT INTO persona_chat_messages
      (character_id, is_from_character, content, timestamp)
      VALUES ('char-1', 0, 'Hello', 1000000)
    ''');

    rawDb.dispose();

    // ========================================================================
    // 2. 打开数据库，触发 v57 → v58 迁移
    // ========================================================================
    final migratedDb = AppDatabase.forTesting(NativeDatabase(tempDbFile));

    // 验证 user_version 已升级到 59（W6 集成基座将 schemaVersion bump 到 59）
    final version = await migratedDb.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 59);

    // ========================================================================
    // 3. 验证新表已创建
    // ========================================================================
    final tables = await migratedDb.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('task_rooms', 'task_artifacts', 'task_decisions')"
    ).get();

    expect(tables.length, 3);
    final tableNames = tables.map((row) => row.data['name']).toSet();
    expect(tableNames, containsAll(['task_rooms', 'task_artifacts', 'task_decisions']));

    // ========================================================================
    // 4. 验证 PersonaChatMessages 新增了 taskRoomId 字段
    // ========================================================================
    final columnsResult = await migratedDb.customSelect(
      "PRAGMA table_info(persona_chat_messages)"
    ).get();

    final columnNames = columnsResult.map((row) => row.data['name'] as String).toList();
    expect(columnNames, contains('task_room_id'));

    // 验证旧数据依然存在
    final oldMessage = await migratedDb.customSelect(
      "SELECT * FROM persona_chat_messages WHERE id = 1"
    ).getSingleOrNull();

    expect(oldMessage, matcher.isNotNull);
    expect(oldMessage!.data['content'], 'Hello');
    expect(oldMessage.data['task_room_id'], matcher.isNull); // 旧数据的新字段应该是 null

    // ========================================================================
    // 5. 验证索引已创建
    // ========================================================================
    final indices = await migratedDb.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' AND name IN ('idx_task_artifacts_task', 'idx_task_decisions_task', 'idx_persona_chat_messages_task_room')"
    ).get();

    expect(indices.length, 3);

    // ========================================================================
    // 6. 验证新表可以正常插入数据
    // ========================================================================
    await migratedDb.into(migratedDb.taskRooms).insert(
      TaskRoomsCompanion.insert(
        id: 'task-test',
        title: 'Test task',
        goal: 'Test migration',
        taskType: 'coding',
        status: 'pending',
        progressPercent: const Value(0),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final insertedTask = await (migratedDb.select(migratedDb.taskRooms)
          ..where((t) => t.id.equals('task-test')))
        .getSingleOrNull();

    expect(insertedTask, matcher.isNotNull);
    expect(insertedTask!.title, 'Test task');

    await migratedDb.close();
  });

  test('v57 → v58 migration preserves all existing persona_chat_messages data', () async {
    // ========================================================================
    // 1. 创建 v57 数据库并插入多条消息
    // ========================================================================
    rawDb = sqlite3.open(tempDbFile.path);

    rawDb.execute('''
      CREATE TABLE persona_chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        sync_id TEXT,
        origin_device_id TEXT,
        character_id TEXT NOT NULL,
        is_from_character INTEGER NOT NULL,
        content TEXT NOT NULL,
        fact_id TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'chat',
        attachments_json TEXT
      )
    ''');

    rawDb.execute('PRAGMA user_version = 57');

    // 插入多条测试消息
    for (int i = 1; i <= 5; i++) {
      rawDb.execute('''
        INSERT INTO persona_chat_messages
        (character_id, is_from_character, content, timestamp)
        VALUES ('char-1', ${i % 2}, 'Message $i', ${1000000 + i * 1000})
      ''');
    }

    rawDb.dispose();

    // ========================================================================
    // 2. 迁移到 v58
    // ========================================================================
    final migratedDb = AppDatabase.forTesting(NativeDatabase(tempDbFile));

    // 验证所有消息都保留
    final messages = await migratedDb.select(migratedDb.personaChatMessages).get();
    expect(messages.length, 5);

    // 验证每条消息的内容正确
    for (int i = 1; i <= 5; i++) {
      final msg = messages.firstWhere((m) => m.id == i);
      expect(msg.content, 'Message $i');
      expect(msg.taskRoomId, matcher.isNull); // 新字段默认为 null
    }

    // 验证可以更新 taskRoomId
    await (migratedDb.update(migratedDb.personaChatMessages)
          ..where((t) => t.id.equals(1)))
        .write(PersonaChatMessagesCompanion(
          taskRoomId: const Value('task-123'),
        ));

    final updatedMsg = await (migratedDb.select(migratedDb.personaChatMessages)
          ..where((t) => t.id.equals(1)))
        .getSingle();

    expect(updatedMsg.taskRoomId, 'task-123');

    await migratedDb.close();
  });

  test(
      'v57→v58 migration repairs a partial state (tables exist, column missing)',
      () async {
    // Reproduces a real-device failure: an interrupted/concurrent upgrade
    // left user_version=57 with the three task_* tables already created but
    // persona_chat_messages.task_room_id missing. Every launch then re-ran
    // the migration and failed (createTable "already exists" / index "no such
    // column"), leaving the app stuck on "正在初始化".
    rawDb = sqlite3.open(tempDbFile.path);

    rawDb.execute('''
      CREATE TABLE persona_chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        sync_id TEXT,
        origin_device_id TEXT,
        character_id TEXT NOT NULL,
        is_from_character INTEGER NOT NULL,
        content TEXT NOT NULL,
        fact_id TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'chat',
        attachments_json TEXT
      )
    ''');
    // Only the columns referenced by _createTaskRoomIndices are required to
    // make the index step succeed after the missing column is backfilled.
    rawDb.execute('''
      CREATE TABLE task_rooms (
        id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL,
        task_type TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    rawDb.execute('''
      CREATE TABLE task_artifacts (
        task_id TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    rawDb.execute('''
      CREATE TABLE task_decisions (
        task_id TEXT NOT NULL,
        decided_at INTEGER NOT NULL
      )
    ''');

    rawDb.execute('PRAGMA user_version = 57');
    rawDb.execute('''
      INSERT INTO persona_chat_messages
      (character_id, is_from_character, content, timestamp)
      VALUES ('char-1', 0, 'Hello', 1000000)
    ''');

    rawDb.dispose();

    final migratedDb = AppDatabase.forTesting(NativeDatabase(tempDbFile));

    final version = await migratedDb.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 59);

    final columnsResult = await migratedDb.customSelect(
      'PRAGMA table_info(persona_chat_messages)',
    ).get();
    final columnNames =
        columnsResult.map((row) => row.data['name'] as String).toList();
    expect(columnNames, contains('task_room_id'));

    final indices = await migratedDb.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' AND name IN "
      "('idx_task_rooms_status','idx_task_rooms_type','idx_task_rooms_updated',"
      "'idx_task_artifacts_task','idx_task_decisions_task',"
      "'idx_persona_chat_messages_task_room')",
    ).get();
    expect(indices.length, 6);

    final oldMessage = await migratedDb.customSelect(
      'SELECT * FROM persona_chat_messages WHERE id = 1',
    ).getSingleOrNull();
    expect(oldMessage, matcher.isNotNull);
    expect(oldMessage!.data['content'], 'Hello');

    await migratedDb.close();
  });
}
