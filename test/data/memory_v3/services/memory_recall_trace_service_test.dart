import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/memory_recall_trace_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MemoryRecallTraceService service;
  late bool fts5Available;

  setUpAll(() => fts5Available = _checkFts5());

  setUp(() async {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.searchDao.createFtsTables();
    service = MemoryRecallTraceService(db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('episode recall resolves through fragments to original chat messages',
      () async {
    if (!fts5Available) return;
    final sourceMessageId = await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'i',
            isFromCharacter: false,
            content: '我上周说过想去海边。',
            timestamp: DateTime(2026, 8, 1, 12),
          ),
        );
    final queryMessageId = await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: 'i',
            isFromCharacter: false,
            content: '我之前想去哪？',
            timestamp: DateTime(2026, 8, 10, 12),
          ),
        );
    await db.into(db.memoryFragments).insert(
          MemoryFragmentsCompanion.insert(
            id: 'fragment-1',
            content: '用户想去海边。',
            sourceMessageIds: Value('[$sourceMessageId]'),
            createdAt: DateTime(2026, 8, 1, 13).millisecondsSinceEpoch,
          ),
        );
    await db.into(db.memoryEpisodes).insert(
          MemoryEpisodesCompanion.insert(
            id: 'episode-1',
            primaryEntityId: 'entity-travel',
            narrative: '你曾经说过想去海边。',
            sourceFragmentIds: '["fragment-1"]',
            significance: 5,
            confidence: 'high',
            valence: 0.5,
            arousal: 0.3,
            createdAt: DateTime(2026, 8, 1, 14).millisecondsSinceEpoch,
            updatedAt: DateTime(2026, 8, 1, 14).millisecondsSinceEpoch,
          ),
        );

    await service.startTurn(
      chatMessageId: queryMessageId,
      query: '我之前想去哪？',
    );
    await service.recordTargets(
      chatMessageId: queryMessageId,
      query: '我之前想去哪？',
      targets: const [
        MemoryRecallTarget(
          targetTable: MemoryRecallTraceService.memoryEpisodesTable,
          targetId: 'episode-1',
          score: 24,
        ),
      ],
    );

    final trace = await service.loadTrace(queryMessageId);
    expect(trace.wasCaptured, isTrue);
    expect(trace.query, '我之前想去哪？');
    expect(trace.items, hasLength(1));
    expect(trace.items.single.body, contains('海边'));
    expect(trace.items.single.sourceMessages.single.id, sourceMessageId);
    expect(trace.items.single.sourceMessages.single.content, contains('上周'));
  });

  test('retrying a turn replaces the old trace instead of duplicating it',
      () async {
    if (!fts5Available) return;
    await service.startTurn(chatMessageId: 42, query: '第一次');
    await service.recordTargets(
      chatMessageId: 42,
      query: '第一次',
      targets: const [
        MemoryRecallTarget(
          targetTable: MemoryRecallTraceService.memoryFragmentsTable,
          targetId: 'old-fragment',
          score: 1,
        ),
      ],
    );

    await service.startTurn(chatMessageId: 42, query: '重试');
    final trace = await service.loadTrace(42);

    expect(trace.wasCaptured, isTrue);
    expect(trace.query, '重试');
    expect(trace.items, isEmpty);
  });

  test('all messages in one compose batch resolve to the primary turn trace',
      () async {
    if (!fts5Available) return;
    await service.startTurn(
      chatMessageId: 101,
      relatedChatMessageIds: const [101, 102, 103],
      query: '合并后的三条消息',
    );
    await service.recordTargets(
      chatMessageId: 101,
      query: '合并后的三条消息',
      targets: const [
        MemoryRecallTarget(
          targetTable: MemoryRecallTraceService.memoryFragmentsTable,
          targetId: 'shared-fragment',
          score: 8,
        ),
      ],
    );

    final secondaryTrace = await service.loadTrace(103);
    expect(secondaryTrace.wasCaptured, isTrue);
    expect(secondaryTrace.query, '合并后的三条消息');
    expect(secondaryTrace.items.single.targetId, 'shared-fragment');
  });

  test('recent recall counts distinct turns for novelty penalty', () async {
    if (!fts5Available) return;
    for (final messageId in [201, 202]) {
      await service.startTurn(chatMessageId: messageId, query: '重复主题');
      await service.recordTargets(
        chatMessageId: messageId,
        query: '重复主题',
        targets: const [
          MemoryRecallTarget(
            targetTable: MemoryRecallTraceService.memoryCardsTable,
            targetId: 'generic-card',
            score: 10,
          ),
        ],
      );
    }

    final counts = await service.recentRecallCounts(
      targetTable: MemoryRecallTraceService.memoryCardsTable,
      targetIds: const ['generic-card', 'fresh-card'],
    );
    expect(counts['generic-card'], 2);
    expect(counts['fresh-card'], null);
  });

  test('feedback on a batch alias is visible and changes penalty signals',
      () async {
    if (!fts5Available) return;
    await service.startTurn(
      chatMessageId: 501,
      relatedChatMessageIds: const [501, 502],
      query: '这一轮',
    );
    await service.recordTargets(
      chatMessageId: 501,
      query: '这一轮',
      targets: const [
        MemoryRecallTarget(
          targetTable: MemoryRecallTraceService.memoryFragmentsTable,
          targetId: 'feedback-fragment',
          score: 12,
        ),
      ],
    );

    await service.setFeedback(
      chatMessageId: 502,
      targetTable: MemoryRecallTraceService.memoryFragmentsTable,
      targetId: 'feedback-fragment',
      feedback: MemoryRecallFeedback.irrelevant,
    );
    var trace = await service.loadTrace(502);
    var signals = await service.recentRecallSignals(
      targetTable: MemoryRecallTraceService.memoryFragmentsTable,
      targetIds: const ['feedback-fragment'],
    );
    expect(trace.items.single.feedback, MemoryRecallFeedback.irrelevant);
    expect(signals['feedback-fragment']?.recallCount, 1);
    expect(signals['feedback-fragment']?.irrelevantCount, 1);
    expect(signals['feedback-fragment']?.effectivePenaltyCount, 4);

    await service.setFeedback(
      chatMessageId: 502,
      targetTable: MemoryRecallTraceService.memoryFragmentsTable,
      targetId: 'feedback-fragment',
      feedback: MemoryRecallFeedback.helpful,
    );
    trace = await service.loadTrace(501);
    signals = await service.recentRecallSignals(
      targetTable: MemoryRecallTraceService.memoryFragmentsTable,
      targetIds: const ['feedback-fragment'],
    );
    expect(trace.items.single.feedback, MemoryRecallFeedback.helpful);
    expect(signals['feedback-fragment']?.helpfulCount, 1);
    expect(signals['feedback-fragment']?.irrelevantCount, 0);
    expect(signals['feedback-fragment']?.effectivePenaltyCount, 0);
  });
}

bool _checkFts5() {
  try {
    final db = sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; recall trace tests skipped.');
    return false;
  }
}
