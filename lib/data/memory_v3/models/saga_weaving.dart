/// Saga weaving model.
///
/// Pure DTO passed between [SagaWeaverV3] and
/// [DreamingOrchestratorServiceV3]. No DB dependencies.
library;

class SagaWeavingDraft {
  SagaWeavingDraft({
    required this.title,
    required this.description,
    required this.episodeIds,
    required this.emotionalAxis,
    this.existingSagaId,
  });

  /// Short saga title (≤ 20 chars).
  final String title;

  /// Long-term narrative description. Must contain coverage period.
  final String description;

  /// Episode IDs that this saga summarizes.
  final List<String> episodeIds;

  /// {valence, arousal, connection} — connection is 0..1 bond strength.
  final SagaEmotionalAxis emotionalAxis;

  /// If this is an update to an existing saga, its ID. Null = new saga.
  final String? existingSagaId;
}

class SagaEmotionalAxis {
  const SagaEmotionalAxis({
    required this.valence,
    required this.arousal,
    required this.connection,
  });

  final double valence;
  final double arousal;

  /// Emotional bond strength with the user, 0..1.
  final double connection;

  factory SagaEmotionalAxis.fromJson(Map<String, dynamic> json) {
    return SagaEmotionalAxis(
      valence: (json['valence'] as num?)?.toDouble() ?? 0.0,
      arousal: (json['arousal'] as num?)?.toDouble() ?? 0.0,
      connection: (json['connection'] as num?)?.toDouble() ?? 0.5,
    );
  }

  Map<String, dynamic> toJson() => {
        'valence': valence,
        'arousal': arousal,
        'connection': connection,
      };
}

class SagaWeavingResult {
  SagaWeavingResult({
    required this.sagas,
    required this.skippedReasons,
  });

  final List<SagaWeavingDraft> sagas;
  final List<String> skippedReasons;

  bool get isEmpty => sagas.isEmpty;
}
