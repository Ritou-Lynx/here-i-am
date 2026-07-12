import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';

void main() {
  DreamingRecallLogEntry entry({
    List<DreamingRecallEpisodeHit> episodes = const [],
    List<DreamingRecallFragmentHit> fragments = const [],
  }) =>
      DreamingRecallLogEntry(
        query: 'test',
        timestamp: 1,
        episodeCount: episodes.length,
        fragmentCount: fragments.length,
        injectedContext: '',
        episodes: episodes,
        fragments: fragments,
      );

  DreamingRecallEpisodeHit episode(int score) => DreamingRecallEpisodeHit(
        id: 'episode-$score',
        narrative: 'episode',
        score: score,
        significance: 4,
      );

  DreamingRecallFragmentHit fragment(int score) => DreamingRecallFragmentHit(
        id: 'fragment-$score',
        content: 'fragment',
        score: score,
        emotionalWeight: 0.5,
        isUserTruthCandidate: false,
      );

  test('coverage separates episode, fragment-only, and zero-result queries',
      () {
    final coverage = DreamingRecallCoverage.fromEntries([
      entry(episodes: [episode(2)], fragments: [fragment(1)]),
      entry(episodes: [episode(0)], fragments: [fragment(3)]),
      entry(episodes: [episode(0)], fragments: [fragment(0)]),
    ]);

    expect(coverage.episodeMatched, 1);
    expect(coverage.fragmentOnly, 1);
    expect(coverage.zeroResult, 1);
    expect(coverage.total, 3);
  });

  test('recency-fill hits with zero scores count as zero result', () {
    final recall = entry(
      episodes: [episode(0)],
      fragments: [fragment(0)],
    );

    expect(recall.hasEpisodeMatch, isFalse);
    expect(recall.hasFragmentMatch, isFalse);
    expect(recall.isZeroResult, isTrue);
  });
}
