class LLMConfig {
  static const String defaultClientKey = 'default';

  static const String typeGemini = 'gemini';
  static const String typeChatCompletion = 'chat_completion';
  static const String typeResponses = 'responses';
  static const String typeBedrockClaude = 'bedrock_claude';
  static const String typeClaude = 'claude';
  static const String typeOpenAiOauth = 'openai_oauth';

  /// Get valid API Key (return default if empty)
  String getEffectiveApiKey() {
    if (apiKey.isNotEmpty) {
      return apiKey;
    }
    return apiKey;
  }

  final String key;
  final String type;
  final String modelId;
  final String apiKey;
  final String baseUrl;
  final String? proxyUrl; // Added proxyUrl
  final Map<String, dynamic> extra;
  final double? temperature;
  final int? maxTokens;
  final double? topP;

  const LLMConfig({
    required this.key,
    required this.type,
    required this.modelId,
    required this.apiKey,
    required this.baseUrl,
    this.proxyUrl,
    this.extra = const {},
    this.temperature,
    this.maxTokens,
    this.topP,
  });

  bool get isDefault => key == defaultClientKey;

  /// Check if this config is valid
  bool get isValid {
    if (type.isEmpty || modelId.isEmpty) {
      return false;
    }
    // OpenAI OAuth uses its own internal token, so apiKey is allowed to be empty
    if ((type == typeResponses ||
            type == typeChatCompletion ||
            type == typeClaude ||
            type == typeGemini) &&
        getEffectiveApiKey().isEmpty) {
      return false;
    }
    if ([typeGemini, typeChatCompletion, typeResponses, typeClaude]
        .contains(type)) {
      return baseUrl.isNotEmpty;
    }
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'type': type,
      'modelId': modelId,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'proxyUrl': proxyUrl,
      'extra': extra,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'topP': topP,
    };
  }

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      key: json['key'] as String,
      type: json['type'] as String,
      modelId: json['modelId'] as String,
      apiKey: json['apiKey'] as String,
      baseUrl: json['baseUrl'] as String,
      proxyUrl: json['proxyUrl'] as String?,
      extra: json['extra'] as Map<String, dynamic>? ?? {},
      temperature: (json['temperature'] as num?)?.toDouble(),
      maxTokens: json['maxTokens'] as int?,
      topP: (json['topP'] as num?)?.toDouble(),
    );
  }

  LLMConfig copyWith({
    String? key,
    String? type,
    String? modelId,
    String? apiKey,
    String? baseUrl,
    String? proxyUrl,
    Map<String, dynamic>? extra,
    double? temperature,
    int? maxTokens,
    double? topP,
  }) {
    return LLMConfig(
      key: key ?? this.key,
      type: type ?? this.type,
      modelId: modelId ?? this.modelId,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      extra: extra ?? this.extra,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
    );
  }

  static LLMConfig createDefaultClient() {
    return const LLMConfig(
      key: defaultClientKey,
      baseUrl: "https://api.openai.com/v1",
      type: typeChatCompletion,
      modelId: 'o1',
      maxTokens: 65536,
      apiKey: '',
      extra: {"reasoning_effort": "medium"},
    );
  }

  static LLMConfig createDefault(String key, String type) {
    if (key == defaultClientKey) {
      return createDefaultClient();
    }
    throw Exception('Unknown LLM config key: $key');
  }
}
