/// Shared novelty penalty for Memory V3 retrieval.
///
/// A memory that has already been injected many times in the recent window is
/// still eligible, but it must earn its place with stronger relevance than a
/// fresh candidate. This prevents generic memories from occupying every turn.
library;

class RecallNoveltyPolicy {
  const RecallNoveltyPolicy._();

  static const int maxCountedRecalls = 8;
  static const double penaltyPerRecall = 0.12;

  static double adjustedScore({
    required double baseScore,
    required int recentRecallCount,
  }) {
    if (recentRecallCount <= 0) return baseScore;
    final count = recentRecallCount.clamp(0, maxCountedRecalls);

    // A zero-score item is a recency fill rather than a semantic match. Give
    // repeated fills a small negative score so fresh fills are preferred.
    if (baseScore <= 0) return -count * 0.01;

    return baseScore / (1 + count * penaltyPerRecall);
  }
}
