/// Memory V3 Query Benchmark
///
/// Covers the query expansion layer (always runs) and full FTS5 integration
/// (skipped on Windows where sqlite3 lacks FTS5).
///
/// Run: flutter test test/data/memory_v3/retrieval/query_benchmark_test.dart
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/retrieval/intent_classifier.dart';
import 'package:memex/data/memory_v3/retrieval/query_expander.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/db/app_database.dart';

/// Whether the test host supports FTS5 (sqlite3_flutter_libs has it; the
/// Dart standalone sqlite3 on Windows typically does not).
final bool _fts5Available = !Platform.isWindows;

// ---------------------------------------------------------------------------
// Section 1 — QueryExpander unit tests (runs everywhere)
// ---------------------------------------------------------------------------

void main() {
  group('QueryExpander — finance / spending', () {
    test('"花钱" expands to 消费 支出 花费', () {
      final plan = QueryExpander.expand('花钱', intent: QueryIntent.factLookup);
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('消费'));
      expect(expanded.query, contains('支出'));
      expect(expanded.query, contains('花费'));
    });

    test('"我上次花钱买了什么" generates original + expanded variants', () {
      final plan = QueryExpander.expand('我上次花钱买了什么',
          intent: QueryIntent.factLookup);
      expect(plan.variants.length, greaterThanOrEqualTo(2));
      expect(plan.variants.any((v) => v.strategy == QueryExpansionStrategy.original), isTrue);
      expect(plan.variants.any((v) => v.strategy == QueryExpansionStrategy.expanded), isTrue);
    });

    test('"消费了多少" triggers finance synonyms', () {
      final plan = QueryExpander.expand('消费了多少');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('支出'));
    });

    test('"买了什么" triggers purchase synonyms', () {
      final plan = QueryExpander.expand('买了什么');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('购买'));
    });
  });

  group('QueryExpander — food / beverage', () {
    test('"咖啡" expands to 拿铁 饮料', () {
      final plan = QueryExpander.expand('咖啡');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('拿铁'));
      expect(expanded.query, contains('饮料'));
    });

    test('"喝" expands to beverage terms', () {
      final plan = QueryExpander.expand('喝');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('咖啡'));
      expect(expanded.query, contains('奶茶'));
    });

    test('"吃了什么" expands to food terms', () {
      final plan = QueryExpander.expand('吃了什么');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('饭'));
    });
  });

  group('QueryExpander — mood / emotion', () {
    test('"心情" expands to 情绪 感受 状态', () {
      final plan = QueryExpander.expand('心情');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('情绪'));
      expect(expanded.query, contains('感受'));
      expect(expanded.query, contains('状态'));
    });

    test('"最近心情怎么样" produces expanded + relaxed variants', () {
      final plan = QueryExpander.expand('最近心情怎么样');
      expect(plan.variants.any((v) => v.strategy == QueryExpansionStrategy.expanded), isTrue);
    });
  });

  group('QueryExpander — task / progress', () {
    test('"任务" expands to 待办 计划 完成', () {
      final plan = QueryExpander.expand('任务');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('待办'));
      expect(expanded.query, contains('计划'));
      expect(expanded.query, contains('完成'));
    });

    test('"做完了吗" expands to task synonyms', () {
      final plan = QueryExpander.expand('做完了吗');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('完成'));
    });
  });

  group('QueryExpander — sleep / health', () {
    test('"睡眠" expands to 睡觉 休息', () {
      final plan = QueryExpander.expand('睡眠');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('睡觉'));
      expect(expanded.query, contains('休息'));
    });
  });

  group('QueryExpander — reading / books', () {
    test('"书" expands to 阅读 读书', () {
      final plan = QueryExpander.expand('书');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('阅读'));
      expect(expanded.query, contains('读书'));
    });
  });

  group('QueryExpander — relaxed fallback', () {
    test('long sentence produces relaxed variant from distinctive terms', () {
      final plan = QueryExpander.expand('你还记得我有没有买咖啡吗');
      final relaxed = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.relaxed);
      // Should strip stop words and keep only distinctive content terms
      expect(relaxed.query, contains('买'));
      expect(relaxed.query, contains('咖啡'));
      expect(relaxed.query, isNot(contains('有没有')));
      expect(relaxed.query, isNot(contains('还记得')));
    });

    test('stop-filtered query with only noise words has no relaxed variant', () {
      final plan = QueryExpander.expand('的吗了呢啊');
      final hasRelaxed =
          plan.variants.any((v) => v.strategy == QueryExpansionStrategy.relaxed);
      expect(hasRelaxed, isFalse);
    });
  });

  group('QueryExpander — recency / time', () {
    test('"最近" expands to 近期 这周 这个月', () {
      final plan = QueryExpander.expand('最近');
      final expanded = plan.variants
          .firstWhere((v) => v.strategy == QueryExpansionStrategy.expanded);
      expect(expanded.query, contains('近期'));
    });
  });

  group('QueryExpander — no expansion when term unknown', () {
    test('random ASCII gibberish only produces original variant', () {
      final plan = QueryExpander.expand('asdfghjkl');
      // No jieba tokens match any synonym trigger — only the original variant.
      expect(plan.variants.where((v) => v.strategy != QueryExpansionStrategy.original),
          isEmpty);
    });

    test('single rare CJK char only produces original variant', () {
      final plan = QueryExpander.expand('曌'); // extremely rare character
      final nonOriginal =
          plan.variants.where((v) => v.strategy != QueryExpansionStrategy.original);
      expect(nonOriginal, isEmpty);
    });
  });

// ---------------------------------------------------------------------------
// Section 2 — Full FTS5 integration (skipped on Windows)
// ---------------------------------------------------------------------------

  group('MemoryCardQueryService — FTS5 recall', () {
    late AppDatabase db;
    late MemoryCardQueryService service;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = MemoryCardQueryService(db);
    });

    setUpAll(() {
      if (!_fts5Available) {
        // ignore: avoid_print
        print('[benchmark] FTS5 not available on ${Platform.operatingSystem} — '
            'skipping integration tests. Run on macOS/Linux or device.');
      }
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insertCard({
      required String id,
      required String type,
      required String label,
      required String text,
    }) async {
      final now = DateTime(2026, 7, 3, 12).millisecondsSinceEpoch;
      await db.into(db.memoryCards).insert(
            MemoryCardsCompanion.insert(
              id: id,
              type: type,
              title: label,
              dropletLabel: label,
              presentationModule: '[]',
              retrievalText: text,
              valence: 0,
              arousal: 0.2,
              createdAt: now,
              updatedAt: now,
              status: const Value.absent(),
              needsFollowUp: const Value.absent(),
            ),
          );
      await db.searchDao.upsertMemoryV3Fts(
        cardId: id,
        dropletLabel: label,
        title: label,
        retrievalText: text,
      );
    }

    // ── Finance ──────────────────────────────────────────────────────

    test('"花钱" recalls card about 消费', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'fin-001',
        type: 'fact',
        label: '书店',
        text: '在书店消费了 38 元，买了一本旅行随笔。',
      );

      final hits = await service.searchCards('花钱');
      expect(hits.map((h) => h['card_id']), contains('fin-001'));
    }, skip: !_fts5Available);

    test('"我上次花钱买了什么" recalls purchase card', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'fin-002',
        type: 'fact',
        label: '充电宝',
        text: '旧的充电宝快炸了，换了一个新的 W&P 35W 充电宝。',
      );

      final hits = await service.searchCards('我上次花钱买了什么');
      expect(hits.map((h) => h['card_id']), contains('fin-002'));
    }, skip: !_fts5Available);

    test('"支出" recalls card with 消费 through expansion', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'fin-003',
        type: 'fact',
        label: '午餐',
        text: '中午在食堂消费了 25 元。',
      );

      final hits = await service.searchCards('支出');
      expect(hits.map((h) => h['card_id']), contains('fin-003'));
    }, skip: !_fts5Available);

    // ── Beverage ─────────────────────────────────────────────────────

    test('"咖啡" recalls card about 拿铁 through synonym expansion', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'bev-001',
        type: 'event',
        label: '拿铁',
        text: '下午在咖啡店喝了一杯拿铁，感觉精神好多了。',
      );

      final hits = await service.searchCards('咖啡');
      expect(hits.map((h) => h['card_id']), contains('bev-001'));
    }, skip: !_fts5Available);

    test('"我有没有喝咖啡" recalls beverage card', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'bev-002',
        type: 'event',
        label: '奶茶',
        text: '今天路过一点点，买了一杯四季春。',
      );

      final hits = await service.searchCards('我有没有喝咖啡');
      expect(hits.map((h) => h['card_id']), contains('bev-002'));
    }, skip: !_fts5Available);

    // ── Mood ─────────────────────────────────────────────────────────

    test('"心情" recalls card about 情绪', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'mood-001',
        type: 'event',
        label: '心情不错',
        text: '今天心情不错，天气也好，适合出去走走。',
      );

      final hits = await service.searchCards('心情');
      expect(hits.map((h) => h['card_id']), contains('mood-001'));
    }, skip: !_fts5Available);

    test('"最近心情怎么样" recalls mood card', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'mood-002',
        type: 'event',
        label: '情绪低',
        text: '最近情绪不太好，工作压力有点大。',
      );

      final hits = await service.searchCards('最近心情怎么样');
      expect(hits.map((h) => h['card_id']), contains('mood-002'));
    }, skip: !_fts5Available);

    // ── Task ─────────────────────────────────────────────────────────

    test('"任务" recalls card about 完成', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'task-001',
        type: 'task',
        label: '项目报告',
        text: '那个项目报告终于做完了，可以松一口气。',
      );

      final hits = await service.searchCards('任务');
      expect(hits.map((h) => h['card_id']), contains('task-001'));
    }, skip: !_fts5Available);

    test('"那个任务做完了吗" recalls completed task card', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'task-002',
        type: 'task',
        label: '周报',
        text: '本周周报已完成并提交。',
      );

      final hits = await service.searchCards('那个任务做完了吗');
      expect(hits.map((h) => h['card_id']), contains('task-002'));
    }, skip: !_fts5Available);

    // ── Sleep ────────────────────────────────────────────────────────

    test('"睡眠" recalls card about 睡觉', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'sleep-001',
        type: 'event',
        label: '熬夜',
        text: '昨晚熬夜到两点才睡觉，现在困死了。',
      );

      final hits = await service.searchCards('睡眠');
      expect(hits.map((h) => h['card_id']), contains('sleep-001'));
    }, skip: !_fts5Available);

    // ── Relaxed fallback ─────────────────────────────────────────────

    test('relaxed fallback: long query still finds card by content terms', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'rlx-001',
        type: 'fact',
        label: '买书',
        text: '买了一本旅行随笔。',
      );

      // A long query where original + expanded may fail;
      // relaxed fallback should pick up "买" + "书".
      final hits = await service.searchCards('你还记得我上次买了什么书吗');
      expect(hits.map((h) => h['card_id']), contains('rlx-001'));
    }, skip: !_fts5Available);

    // ── Edge: exact label match ──────────────────────────────────────

    test('exact dropletLabel match returns card', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'edge-001',
        type: 'fact',
        label: '健身房年卡',
        text: '办了一张健身房年卡，花了 1200。',
      );

      final hits = await service.searchCards('健身房年卡');
      expect(hits.map((h) => h['card_id']), contains('edge-001'));
    }, skip: !_fts5Available);

    // ── Edge: no match ───────────────────────────────────────────────

    test('unrelated query returns empty', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'edge-002',
        type: 'fact',
        label: '咖啡',
        text: '喝了一杯拿铁。',
      );

      final hits = await service.searchCards('火箭发射');
      expect(hits, isEmpty);
    }, skip: !_fts5Available);

    // ── Multiple cards, best match ranks first ───────────────────────

    test('multiple matches are ranked by relevance', () async {
      if (!_fts5Available) return;
      await insertCard(
        id: 'multi-001',
        type: 'fact',
        label: '购书',
        text: '在书店消费了 38 元买了一本旅行随笔。',
      );
      await insertCard(
        id: 'multi-002',
        type: 'event',
        label: '喝咖啡',
        text: '下午喝了一杯拿铁。',
      );

      final hits = await service.searchCards('花钱');
      // Both cards have "费" etc but the 消费 one should rank higher
      expect(hits.length, greaterThanOrEqualTo(1));
      expect(hits.first['card_id'], 'multi-001');
    }, skip: !_fts5Available);
  });
}
