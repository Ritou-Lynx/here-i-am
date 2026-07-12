import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/retrieval/project_memory_intent_classifier.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProjectMemoryService service;
  late bool fts5Available;

  setUpAll(() {
    fts5Available = _checkFts5();
  });

  setUp(() async {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.searchDao.createFtsTables();
    service = ProjectMemoryService(db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('projects a personal closeout idempotently with provenance', () async {
    if (!fts5Available) return;
    final envelope = _personalEnvelope();

    expect(await service.project(envelope), isTrue);
    expect(await service.project(envelope), isFalse);

    final items = await db.select(db.projectMemoryItems).get();
    final sources = await db.select(db.projectMemorySources).get();
    expect(items, hasLength(1));
    expect(sources, hasLength(1));
    expect(items.single.projectId, 'paper-project');
    expect(sources.single.sourceTool, 'codex');
  });

  test('ordinary life scope produces no project candidates', () async {
    if (!fts5Available) return;
    await service.project(_personalEnvelope());

    final hits = await service.search(
      '论文写作计划',
      scope: const ProjectMemoryQueryScope(
        isProjectIntent: false,
        allowedProjectIds: {'paper-project'},
      ),
    );

    expect(hits, isEmpty);
  });

  test('project intent filters candidates before top-k by allowed project',
      () async {
    if (!fts5Available) return;
    await service.project(_personalEnvelope());
    await service.project(_personalEnvelope(
      eventId: 'event-other',
      projectId: 'other-project',
      projectKey: 'other',
    ));

    final hits = await service.search(
      '论文写作计划',
      scope: const ProjectMemoryQueryScope(
        isProjectIntent: true,
        allowedProjectIds: {'paper-project'},
      ),
    );

    expect(hits, hasLength(1));
    expect(hits.single.projectId, 'paper-project');
    expect(hits.single.openLoops, contains('完成论文写作计划'));
  });

  test('explicit project intent falls back within allowed projects', () async {
    if (!fts5Available) return;
    await service.project(_personalEnvelope());
    await service.project(_personalEnvelope(
      eventId: 'event-other',
      projectId: 'other-project',
      projectKey: 'other',
    ));

    final hits = await service.search(
      'tokens-with-no-literal-overlap',
      scope: const ProjectMemoryQueryScope(
        isProjectIntent: true,
        allowedProjectIds: {'paper-project'},
      ),
    );

    expect(hits, hasLength(1));
    expect(hits.single.projectId, 'paper-project');
  });

  test('current projection returns only the latest closeout per project',
      () async {
    if (!fts5Available) return;
    await service.project(_personalEnvelope(
      eventId: 'event-old',
      summary: 'Old project state.',
      occurredAt: DateTime.utc(2026, 7, 1),
    ));
    await service.project(_personalEnvelope(
      eventId: 'event-current',
      summary: 'Current project state.',
      occurredAt: DateTime.utc(2026, 7, 12),
    ));

    final hits = await service.search(
      'tokens-with-no-literal-overlap',
      scope: const ProjectMemoryQueryScope(
        isProjectIntent: true,
        allowedProjectIds: {'paper-project'},
      ),
    );

    expect(hits, hasLength(1));
    expect(hits.single.itemId, 'event-current');
    expect(hits.single.summary, 'Current project state.');
    expect(
      hits.single.isStale(now: DateTime.utc(2026, 7, 20)),
      isTrue,
    );
    expect(
      hits.single.isStale(now: DateTime.utc(2026, 7, 18)),
      isFalse,
    );
  });

  test('confidential and unredacted work envelopes fail closed', () async {
    if (!fts5Available) return;
    expect(
      () => service.project(_personalEnvelope(
        policyId: 'confidential_local',
        memoryV3Policy: 'none',
      )),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.project(_personalEnvelope(
        policyId: 'work_redacted',
        memoryV3Policy: 'redacted_summary',
        redactionState: 'activity_index_redacted',
      )),
      throwsA(isA<FormatException>()),
    );
  });

  test('project intent gate accepts project progress and rejects life recall',
      () {
    expect(
      ProjectMemoryIntentClassifier.isProjectIntent('Here I am 的 UI 搭建到哪了'),
      isTrue,
    );
    expect(
      ProjectMemoryIntentClassifier.isProjectIntent('论文下一步写什么'),
      isTrue,
    );
    expect(
      ProjectMemoryIntentClassifier.isProjectIntent('我昨天晚饭吃了什么'),
      isFalse,
    );
    expect(
      ProjectMemoryIntentClassifier.isProjectIntent('最近心情怎么样'),
      isFalse,
    );
  });
}

ProjectMemoryProjectionEnvelope _personalEnvelope({
  String eventId = 'event-paper',
  String projectId = 'paper-project',
  String projectKey = 'livestream-paper',
  String policyId = 'personal_full',
  String memoryV3Policy = 'project_summary',
  String redactionState = 'policy_summary',
  String summary = '整理了直播带货论文材料。',
  DateTime? occurredAt,
}) {
  return ProjectMemoryProjectionEnvelope(
    eventId: eventId,
    projectId: projectId,
    projectKey: projectKey,
    policyId: policyId,
    policyVersion: 1,
    memoryV3Policy: memoryV3Policy,
    sensitivity: 'personal',
    redactionState: redactionState,
    authority: 'agent_inferred',
    trustLevel: 'trusted_client_unverified_content',
    sourceTool: 'codex',
    sourceSessionId: 'session-paper',
    sourceUri: 'i://project-activity/$eventId',
    summary: summary,
    decisions: const ['使用国际中文教育投稿格式'],
    openLoops: const ['完成论文写作计划'],
    artifactRefs: const ['初期思路.docx'],
    occurredAt: occurredAt ?? DateTime.utc(2026, 7, 11, 10),
    receivedAt: DateTime.utc(2026, 7, 11, 10, 1),
  );
}

bool _checkFts5() {
  try {
    final db = sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; Project Memory tests skipped.');
    return false;
  }
}
