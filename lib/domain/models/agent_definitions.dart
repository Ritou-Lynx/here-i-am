class AgentDefinitions {
  static const String pkmAgent = 'pkm_agent';
  static const String cardAgent = 'card_agent';
  static const String profileAgent = 'profile_agent';
  static const String scheduleAggregatorAgent = 'schedule_aggregator_agent';
  static const String scheduleRefreshRouterAgent =
      'schedule_refresh_router_agent';
  static const String commentAgent = 'comment_agent';
  static const String chatAgent = 'chat_agent';
  static const String companionAgent = 'companion_agent';
  static const String checkinAgent = 'checkin_agent';
  static const String analyzeAssets = 'analyze_assets';
  static const String clarificationResolutionAgent =
      'clarification_resolution_agent';
  static const String recordOrganizerAgent = 'record_organizer_agent';
  static const String lifeInsightAgent = 'life_insight_agent';
  static const String embeddingAgent = 'embedding_agent';

  static const Map<String, String> displayNames = {
    pkmAgent: 'PKM',
    cardAgent: 'Cards',
    profileAgent: 'Memory summary',
    scheduleAggregatorAgent: 'Schedule',
    scheduleRefreshRouterAgent: 'Schedule Router',
    commentAgent: 'Comments',
    chatAgent: 'Chat',
    companionAgent: 'Companion',
    checkinAgent: 'Companion checkin',
    analyzeAssets: 'Media analysis',
    clarificationResolutionAgent: 'Ask resolution',
    recordOrganizerAgent: 'Record organizer',
    lifeInsightAgent: 'Life insights',
    embeddingAgent: 'Embedding',
  };

  /// Agent IDs exposed in the model configuration screen.
  ///
  /// Keeping this derived from the display-name registry makes the settings UI
  /// pick up newly registered built-in agents automatically.
  static List<String> get configurableAgentIds =>
      List.unmodifiable(displayNames.keys);
}
