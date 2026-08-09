import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/retrieval/fusion_ranker.dart';
import 'package:memex/data/memory_v3/retrieval/intent_classifier.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/memory_recall_trace_service.dart';
import 'package:memex/db/app_database.dart';

/// Agent tool for searching the user's V3 memory cards.
///
/// Uses FTS5 full-text search on `retrievalText`, `dropletLabel`, and `title`,
/// with lightweight query expansion before re-ranking results with
/// [FusionRanker] based on intent classification.
Tool buildMemoryV3QueryTool({int? currentUserMessageId}) {
  return Tool(
    name: 'memory_v3_query',
    description:
        '''Search the user's memory cards (facts, events, tasks, plans, schedules).

Use this tool whenever the user asks a "do you remember" question, references a past event, or you need to recall something the user recorded. Results are ranked by a combination of keyword relevance, lightweight synonym expansion, recency, and intent match.

Each result includes:
- card_id: FULL UUID — pass this verbatim to `memory_v3_update_card` when the user wants to change a card.
- type: fact / event / task / schedule / plan
- dropletLabel: short essence label
- snippet: relevant excerpt from the card
- score: fusion relevance score (higher = more relevant)

Tips:
- Search with natural keywords, not full sentences
- Search can expand common Chinese synonyms and loosen brittle no-result queries automatically
- For task/progress questions, task cards are boosted automatically''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Search keywords. Use the most distinctive words from what '
                  'the user mentioned. For example: "lunch mala tang" not '
                  '"what did I eat for lunch that one time".',
        },
      },
      'required': ['query'],
    },
    executable: (String query) async {
      if (!AppDatabase.isInitialized) {
        return 'Memory system not available.';
      }
      final service = MemoryCardQueryService(AppDatabase.instance);
      try {
        // 1. Raw FTS5 search
        final rawHits = await service.searchCards(query);
        if (rawHits.isEmpty) {
          return 'No memory cards found matching "$query".';
        }

        // 2. Intent classification
        final intent = IntentClassifier.classify(query);
        final intentLabel = IntentClassifier.label(intent);

        // 3. Resolve card metadata for ranking
        final cardIds = rawHits.map((h) => h['card_id'] as String).toList();
        final cards = await service.getCardsByIds(cardIds);
        final cardById = {for (final c in cards) c.id: c};
        final recallTraceService =
            MemoryRecallTraceService(AppDatabase.instance);
        final recallCounts = await recallTraceService.recentRecallCounts(
          targetTable: MemoryRecallTraceService.memoryCardsTable,
          targetIds: cardIds,
          excludeChatMessageId: currentUserMessageId,
        );

        // 4. Build rankable hits
        final rankable = <RankableHit>[];
        for (final hit in rawHits) {
          final cardId = hit['card_id'] as String;
          final card = cardById[cardId];
          if (card != null) {
            rankable.add(RankableHit(
              cardId: cardId,
              ftsRank: (hit['rank'] as num).toDouble(),
              updatedAt: card.updatedAt,
              cardType: card.type,
              recentRecallCount: recallCounts[cardId] ?? 0,
            ));
          }
        }

        // 5. Fusion rank
        FusionRanker.rank(rankable, intent);

        if (currentUserMessageId != null && currentUserMessageId > 0) {
          final visibleHits = rankable.take(10).toList(growable: false);
          await recallTraceService.recordTargets(
            chatMessageId: currentUserMessageId,
            query: query,
            targets: visibleHits.map((hit) => MemoryRecallTarget(
                  targetTable: MemoryRecallTraceService.memoryCardsTable,
                  targetId: hit.cardId,
                  score: hit.score * 100,
                )),
          );
        }

        // 6. Format output
        final buf = StringBuffer();
        buf.writeln('Found ${rankable.length} memory card(s) '
            'matching "$query" ($intentLabel):');
        buf.writeln();
        for (var i = 0; i < rankable.length && i < 10; i++) {
          final h = rankable[i];
          final hitData = rawHits.firstWhere(
            (r) => r['card_id'] == h.cardId,
            orElse: () => <String, dynamic>{},
          );
          buf.writeln('- card_id: ${h.cardId} · ${h.cardType} · '
              '${hitData['label_snippet'] ?? ''}');
          final textSnippet = hitData['text_snippet'] as String?;
          if (textSnippet != null && textSnippet.isNotEmpty) {
            buf.writeln('  $textSnippet');
          }
        }
        return buf.toString();
      } catch (e) {
        return 'Failed to search memory cards: $e';
      }
    },
  );
}
