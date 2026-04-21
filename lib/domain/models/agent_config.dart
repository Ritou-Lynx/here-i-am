class AgentConfig {
  static const Object _unset = Object();

  /// The key of the LLMConfig to use for this agent.
  final String? llmConfigKey;

  /// The key of the LLMConfig to use for speech processing.
  /// Null or empty means using the local speech model.
  final String? speechLlmConfigKey;

  /// Whether speech processing should fall back to the local model
  /// when the selected cloud model fails or returns no result.
  final bool speechFallbackToLocal;

  const AgentConfig({
    this.llmConfigKey,
    this.speechLlmConfigKey,
    this.speechFallbackToLocal = false,
  });

  bool get usesLocalSpeechModel =>
      speechLlmConfigKey == null || speechLlmConfigKey!.isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'llmConfigKey': llmConfigKey,
      'speechLlmConfigKey': speechLlmConfigKey,
      'speechFallbackToLocal': speechFallbackToLocal,
    };
  }

  factory AgentConfig.fromJson(Map<String, dynamic> json) {
    return AgentConfig(
      llmConfigKey: json['llmConfigKey'] as String?,
      speechLlmConfigKey: json['speechLlmConfigKey'] as String?,
      speechFallbackToLocal: json['speechFallbackToLocal'] as bool? ?? false,
    );
  }

  AgentConfig copyWith({
    Object? llmConfigKey = _unset,
    Object? speechLlmConfigKey = _unset,
    bool? speechFallbackToLocal,
  }) {
    return AgentConfig(
      llmConfigKey:
          identical(llmConfigKey, _unset) ? this.llmConfigKey : llmConfigKey as String?,
      speechLlmConfigKey: identical(speechLlmConfigKey, _unset)
          ? this.speechLlmConfigKey
          : speechLlmConfigKey as String?,
      speechFallbackToLocal:
          speechFallbackToLocal ?? this.speechFallbackToLocal,
    );
  }
}
