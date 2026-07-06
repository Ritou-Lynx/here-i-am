import 'dart:async';
import 'package:logging/logging.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/agent/insight_agent/knowledge_insight_agent.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/coros_sync_service.dart';

final Logger _logger = getLogger('LocalTaskHandlers');

/// Handler for Knowledge Insight Update
Future<void> handleKnowledgeInsight(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  _logger.info(
      'Executing handleKnowledgeInsight for task ${context.taskId}, bizId: ${context.bizId}');

  // Sync external data (COROS) to local files before insight generation.
  // Failure is logged but does not block the insight run.
  await CorosSyncService.syncIfConfigured(userId);

  try {
    await KnowledgeInsightAgent.updateKnowledgeInsight();
  } finally {
    // Always notify UI that the refresh operation is done (success or failure).
    // On failure, handleGenericAgentFailure also emits ErrorNotificationMessage
    // for the error toast, but we need NewInsightMessage to stop the loading state.
    EventBusService.instance.emitEvent(NewInsightMessage(
      insightId: context.bizId ?? context.taskId,
      html: '',
    ));
  }
}
