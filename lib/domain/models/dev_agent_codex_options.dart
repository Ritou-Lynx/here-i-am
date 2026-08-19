/// Per-run Codex controls exposed by Dev Room.
///
/// Null means "inherit the next layer". The service resolves layers in this
/// order: run override, Dev Session, Dev Project, then the computer's Codex
/// config.toml.
class DevAgentCodexOptions {
  const DevAgentCodexOptions({
    this.model,
    this.reasoningEffort,
    this.serviceTier,
    this.verbosity,
  });

  final String? model;
  final String? reasoningEffort;
  final String? serviceTier;
  final String? verbosity;

  static const inherited = DevAgentCodexOptions();

  static const quick = DevAgentCodexOptions(
    reasoningEffort: 'low',
    verbosity: 'low',
  );

  static const balanced = DevAgentCodexOptions(
    reasoningEffort: 'medium',
    verbosity: 'medium',
  );

  static const deep = DevAgentCodexOptions(
    reasoningEffort: 'high',
    verbosity: 'high',
  );

  bool get isEmpty =>
      model == null &&
      reasoningEffort == null &&
      serviceTier == null &&
      verbosity == null;

  DevAgentCodexOptions copyWith({
    String? model,
    bool clearModel = false,
    String? reasoningEffort,
    bool clearReasoningEffort = false,
    String? serviceTier,
    bool clearServiceTier = false,
    String? verbosity,
    bool clearVerbosity = false,
  }) {
    return DevAgentCodexOptions(
      model: clearModel ? null : model ?? this.model,
      reasoningEffort:
          clearReasoningEffort ? null : reasoningEffort ?? this.reasoningEffort,
      serviceTier: clearServiceTier ? null : serviceTier ?? this.serviceTier,
      verbosity: clearVerbosity ? null : verbosity ?? this.verbosity,
    );
  }

  /// Fills missing values from [fallback] without replacing explicit values.
  DevAgentCodexOptions withFallback(DevAgentCodexOptions fallback) {
    return DevAgentCodexOptions(
      model: model ?? fallback.model,
      reasoningEffort: reasoningEffort ?? fallback.reasoningEffort,
      serviceTier: serviceTier ?? fallback.serviceTier,
      verbosity: verbosity ?? fallback.verbosity,
    );
  }

  Map<String, dynamic> toJson() => {
        if (model != null) 'model': model,
        if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
        if (serviceTier != null) 'service_tier': serviceTier,
        if (verbosity != null) 'verbosity': verbosity,
      };

  String get summary {
    final parts = <String>[
      model ?? '继承模型',
      if (reasoningEffort != null) '思考 $reasoningEffort',
      if (serviceTier != null) '速度 $serviceTier',
      if (verbosity != null) '回答 $verbosity',
    ];
    return parts.join(' · ');
  }
}
