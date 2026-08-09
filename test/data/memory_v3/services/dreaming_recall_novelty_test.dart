import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/memory_recall_trace_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fts5Available = _checkFts5();
  late AppDatabase db;
  late DreamingOrchestratorServiceV3 dreaming;
  late MemoryRecallTraceService trace;

  setUp(() async {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.searchDao.createFtsTables();
    dreaming = DreamingOrchestratorServiceV3(db);
    trace = MemoryRecallTraceService(db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('repeated fragment yields a limited slot to equally relevant fresh ones',
      () async {
    if (!fts5Available) return;
    for (final id in ['repeated', 'fresh-a', 'fresh-b']) {
      await _insertFragment(db, id: id, content: '用户喜欢在下午喝咖啡。');
    }
    for (final messageId in [401, 402, 403, 404, 405, 406]) {
      await trace.startTurn(chatMessageId: messageId, query: '咖啡');
      await trace.recordTargets(
        chatMessageId: messageId,
        query: '咖啡',
        targets: const [
          MemoryRecallTarget(
            targetTable: MemoryRecallTraceService.memoryFragmentsTable,
            targetId: 'repeated',
            score: 20,
          ),
        ],
      );
    }

    final result = await dreaming.queryRecentDreamingContext(
      queryHint: '咖啡',
      episodeLimit: 0,
      recentFragmentLimit: 2,
    );
    final ids = result.fragmentHits.map((hit) => hit.fragment.id).toList();

    expect(ids, containsAll(['fresh-a', 'fresh-b']));
    expect(ids, isNot(contains('repeated')));
  });
}

Future<void> _insertFragment(
  AppDatabase db, {
  required String id,
  required String content,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.into(db.memoryFragments).insert(
        MemoryFragmentsCompanion.insert(
          id: id,
          content: content,
          emotionalWeight: const Value(0.5),
          createdAt: now,
        ),
      );
  await db.searchDao.upsertMemoryFragmentFts(
    fragmentId: id,
    content: content,
  );
}

bool _checkFts5() {
  try {
    final db = sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; Dreaming novelty test skipped.');
    return false;
  }
}
