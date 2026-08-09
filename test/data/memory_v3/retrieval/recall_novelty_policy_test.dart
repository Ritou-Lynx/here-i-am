import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/retrieval/fusion_ranker.dart';
import 'package:memex/data/memory_v3/retrieval/intent_classifier.dart';
import 'package:memex/data/memory_v3/retrieval/recall_novelty_policy.dart';

void main() {
  test('fresh candidate keeps its relevance score', () {
    expect(
      RecallNoveltyPolicy.adjustedScore(
        baseScore: 50,
        recentRecallCount: 0,
      ),
      50,
    );
  });

  test('repeated candidate is penalized but not hard filtered', () {
    final adjusted = RecallNoveltyPolicy.adjustedScore(
      baseScore: 50,
      recentRecallCount: 4,
    );

    expect(adjusted, lessThan(50));
    expect(adjusted, greaterThan(0));
  });

  test('fresh recency fill ranks ahead of a repeatedly injected fill', () {
    final fresh = RecallNoveltyPolicy.adjustedScore(
      baseScore: 0,
      recentRecallCount: 0,
    );
    final repeated = RecallNoveltyPolicy.adjustedScore(
      baseScore: 0,
      recentRecallCount: 3,
    );

    expect(fresh, greaterThan(repeated));
  });

  test('fusion ranker lets an equivalent fresh card outrank a repeated card',
      () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final repeated = RankableHit(
      cardId: 'repeated',
      ftsRank: -2,
      updatedAt: now,
      cardType: 'fact',
      recentRecallCount: 6,
    );
    final fresh = RankableHit(
      cardId: 'fresh',
      ftsRank: -2,
      updatedAt: now,
      cardType: 'fact',
    );

    final ranked = FusionRanker.rank(
      [repeated, fresh],
      QueryIntent.factLookup,
    );

    expect(ranked.first.cardId, 'fresh');
    expect(fresh.score, greaterThan(repeated.score));
  });
}
