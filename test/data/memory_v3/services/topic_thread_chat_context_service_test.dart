import 'dart:io' show stderr;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/topic_thread_chat_context_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fts5Available = _checkFts5();
  late AppDatabase db;

  setUp(() {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('persists, loads, and clears the active topic anchor', () async {
    if (!fts5Available) return;
    final service = TopicThreadChatContextService(db: db);
    final now = DateTime(2026, 8, 18, 20);
    await service.save(TopicThreadChatContext(
      characterId: 'i',
      threadId: 'thread-autumn',
      threadTitle: '秋招',
      afterMessageId: 42,
      updatedAt: now,
    ));

    final loaded = await service.load('i', now: now);
    expect(loaded?.threadId, 'thread-autumn');
    expect(loaded?.afterMessageId, 42);

    await service.clear('i');
    expect(await service.load('i', now: now), isNull);
  });

  test('expires a stale topic anchor', () async {
    if (!fts5Available) return;
    final service = TopicThreadChatContextService(
      db: db,
      maxAge: const Duration(hours: 24),
    );
    final savedAt = DateTime(2026, 8, 17, 10);
    await service.save(TopicThreadChatContext(
      characterId: 'i',
      threadId: 'thread-autumn',
      threadTitle: '秋招',
      afterMessageId: 42,
      updatedAt: savedAt,
    ));

    expect(
      await service.load('i', now: savedAt.add(const Duration(hours: 25))),
      isNull,
    );
  });
}

bool _checkFts5() {
  try {
    final db = sqlite3.sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; TopicThread context tests skipped.');
    return false;
  }
}
