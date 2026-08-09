/// Lightweight fusion ranker for memory-card search results.
///
/// Re-ranks FTS5 raw hits by combining:
/// - FTS5 BM25 relevance score
/// - Recency boost (newer cards rank higher)
/// - Intent-type relevance (e.g. task cards for progress queries)
///
/// All scores are normalised to [0,1] before fusion.
library;

import 'intent_classifier.dart';
import 'recall_novelty_policy.dart';

/// A search hit with its metadata for ranking.
class RankableHit {
  RankableHit({
    required this.cardId,
    required this.ftsRank,
    required this.updatedAt, // ms since epoch
    required this.cardType, // fact / event / task / schedule / plan
    this.recentRecallCount = 0,
  });

  final String cardId;
  final double ftsRank; // lower = better in FTS5
  final int updatedAt;
  final String cardType;
  final int recentRecallCount;

  /// Computed fusion score (higher = better).
  double score = 0;
}

class FusionRanker {
  const FusionRanker._();

  /// Weights for each dimension (sum ≈ 1.0).
  static const double _wFts = 0.50;
  static const double _wRecency = 0.30;
  static const double _wIntent = 0.20;

  /// How many days back counts as "recent" for the recency curve.
  static const int _recentWindowDays = 30;

  /// Re-rank [hits] for the given [intent]. Modifies each hit's [RankableHit.score]
  /// in-place and returns the list sorted by descending score.
  static List<RankableHit> rank(
    List<RankableHit> hits,
    QueryIntent intent,
  ) {
    if (hits.isEmpty) return hits;

    final now = DateTime.now().millisecondsSinceEpoch;

    // ── Normalise FTS rank (lower = better → invert) ───────────
    final ftsValues = hits.map((h) => h.ftsRank).toList();
    final ftsMin = ftsValues.reduce((a, b) => a < b ? a : b);
    final ftsRange = (ftsValues.reduce((a, b) => a > b ? a : b) - ftsMin)
        .clamp(0.001, double.infinity);
    for (final h in hits) {
      h.score += _wFts * (1.0 - (h.ftsRank - ftsMin) / ftsRange);
    }

    // ── Recency boost ──────────────────────────────────────────
    const oneDay = 24 * 60 * 60 * 1000;
    for (final h in hits) {
      final daysAgo =
          ((now - h.updatedAt) / oneDay).clamp(0, _recentWindowDays);
      final recency =
          1.0 - (daysAgo / _recentWindowDays); // 1.0 = today, 0.0 = 30+ days
      h.score += _wRecency * recency;
    }

    // ── Intent-type relevance ──────────────────────────────────
    for (final h in hits) {
      h.score += _wIntent * _typeBoost(h.cardType, intent);
    }

    // ── Novelty penalty ────────────────────────────────────────
    for (final h in hits) {
      h.score = RecallNoveltyPolicy.adjustedScore(
        baseScore: h.score,
        recentRecallCount: h.recentRecallCount,
      );
    }

    // Sort descending by score
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  /// How relevant is [cardType] for the given [intent]? Returns [0, 1].
  static double _typeBoost(String cardType, QueryIntent intent) {
    switch (intent) {
      case QueryIntent.progressCheck:
        return switch (cardType) {
          'task' => 1.0,
          'plan' => 0.9,
          'schedule' => 0.8,
          'event' => 0.3,
          _ => 0.1,
        };
      case QueryIntent.emotionRecall:
        return switch (cardType) {
          'event' => 1.0,
          'fact' => 0.6,
          _ => 0.3,
        };
      case QueryIntent.reflection:
        // Reflection values all types roughly equally
        return 0.5;
      case QueryIntent.factLookup:
        return switch (cardType) {
          'fact' => 1.0,
          'event' => 0.8,
          'task' => 0.4,
          _ => 0.5,
        };
    }
  }
}
