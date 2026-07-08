/// Episode consolidation model.
///
/// Pure DTO passed between [EpisodeConsolidatorV3] and
/// [DreamingOrchestratorServiceV3]. No DB dependencies.
library;

class EpisodeConsolidationDraft {
  EpisodeConsolidationDraft({
    required this.narrative,
    required this.topicId,
    required this.primaryEntityId,
    required this.sourceFragmentIds,
    required this.significance,
    required this.confidence,
    required this.valence,
    required this.arousal,
    this.occurredAtStart,
    this.occurredAtEnd,
    this.linkedEntityIds = const [],
  });

  final String narrative;
  final String topicId;
  final String primaryEntityId;
  final List<String> sourceFragmentIds;
  final int significance;
  final String confidence;
  final double valence;
  final double arousal;
  final String? occurredAtStart;
  final String? occurredAtEnd;
  final List<String> linkedEntityIds;

  factory EpisodeConsolidationDraft.fromJson(Map<String, dynamic> json) {
    final occurred = json['occurredAtRange'] as Map<String, dynamic>?;
    final topicId = (json['topicId'] as String? ??
            json['primaryEntityId'] as String? ??
            '__ungrouped__')
        .trim();
    return EpisodeConsolidationDraft(
      narrative: json['narrative'] as String,
      topicId: topicId.isNotEmpty ? topicId : '__ungrouped__',
      primaryEntityId: (json['primaryEntityId'] as String? ?? '').trim(),
      sourceFragmentIds: (json['sourceFragmentIds'] as List).cast<String>(),
      significance: json['significance'] as int,
      confidence: json['confidence'] as String,
      valence: (json['valence'] as num).toDouble(),
      arousal: (json['arousal'] as num).toDouble(),
      occurredAtStart: occurred?['start'] as String?,
      occurredAtEnd: occurred?['end'] as String?,
      linkedEntityIds:
          (json['linkedEntityIds'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class EpisodeConsolidationResult {
  EpisodeConsolidationResult({
    required this.episodes,
    required this.skippedEntityIds,
    required this.isDryRun,
  });

  final List<EpisodeConsolidationDraft> episodes;
  final List<String> skippedEntityIds;
  final bool isDryRun;

  bool get isEmpty => episodes.isEmpty && skippedEntityIds.isEmpty;

  Map<String, dynamic> toJson() => {
        'episodes': episodes
            .map((e) => {
                  'narrative': e.narrative,
                  'topicId': e.topicId,
                  'primaryEntityId': e.primaryEntityId,
                  'significance': e.significance,
                  'confidence': e.confidence,
                  'sourceFragmentIds': e.sourceFragmentIds,
                })
            .toList(),
        'skippedEntityIds': skippedEntityIds,
        'isDryRun': isDryRun,
      };
}
