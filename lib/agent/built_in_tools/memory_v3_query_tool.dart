import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/retrieval/fusion_ranker.dart';
import 'package:memex/data/memory_v3/retrieval/intent_classifier.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/db/app_database.dart';

/// Agent tool for searching the user's V3 memory cards.
///
/// Uses FTS5 full-text search on `retrievalText`, `dropletLabel`, and `title`,
/// then re-ranks results with [FusionRanker] based on intent classification.
Tool buildMemoryV3QueryTool() {
  return Tool(
    name: 'memory_v3_query',
    description: '''Search the user's memory cards (facts, events, tasks, plans, schedules).

Use this tool whenever the user asks a "do you remember" question, references a past event, or you need to recall something the user recorded. Results are ranked by a combination of keyword relevance, recency, and intent match.

Each result includes:
- card_id: unique identifier
- type: fact / event / task / schedule / plan
- dropletLabel: short essence label
- snippet: relevant excerpt from the card
- score: fusion relevance score (higher = more relevant)

Tips:
- Search with natural keywords, not full sentences
- If the first query returns nothing, try synonyms or related terms
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
            ));
          }
        }

        // 5. Fusion rank
        FusionRanker.rank(rankable, intent);

        // 6. Format output
        final buf = StringBuffer();
        buf.writeln('Found ${rankable.length} memory card(s) '
            'matching "$query" ($intentLabel):');
        buf.writeln();
        for (var i = 0; i < rankable.length && i < 10; i++) {
          final h = rankable[i];
          final id = h.cardId.substring(0, 8);
          final hitData = rawHits.firstWhere(
            (r) => r['card_id'] == h.cardId,
            orElse: () => <String, dynamic>{},
          );
          buf.writeln('- [$id] ${h.cardType} · '
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
