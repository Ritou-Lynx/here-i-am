import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/task_handlers/analyze_assets_handler.dart';
import 'package:memex/data/services/task_handlers/clarification_resolution_handler.dart';
import 'package:memex/data/services/task_handlers/comment_agent_handler.dart';
import 'package:memex/data/services/task_handlers/companion_delegation_handler.dart';
import 'package:memex/data/services/task_handlers/conversation_capture_handler.dart';
import 'package:memex/data/services/task_handlers/custom_agent_task_handler.dart';
import 'package:memex/data/services/task_handlers/dev_session_followup_handler.dart';
import 'package:memex/data/services/task_handlers/fts_index_handler.dart';
import 'package:memex/data/services/task_handlers/knowledge_insight_handler.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/data/services/task_handlers/reprocess_cards_handler.dart';
import 'package:memex/data/services/task_handlers/reprocess_comments_handler.dart';
import 'package:memex/data/services/task_handlers/reprocess_knowledge_base_handler.dart';
import 'package:memex/data/services/task_handlers/schedule_aggregator_handler.dart';
import 'package:memex/data/services/task_handlers/schedule_refresh_router_handler.dart';

void registerLocalTaskHandlers() {
  final executor = LocalTaskExecutor.instance;

  executor.registerHandler('handle_analyze_assets', handleAnalyzeAssetsImpl);
  executor.registerHandler('fts_index_update', handleFtsIndexUpdateImpl);
  executor.registerHandler('reprocess_cards_task', handleReprocessCardsImpl);
  executor.registerHandler('comment_agent_task', handleCommentAgentImpl);
  executor.registerHandler(
    'conversation_capture_task',
    handleConversationCapture,
  );
  executor.registerHandler(
    'reprocess_comments_task',
    handleReprocessCommentsImpl,
  );
  executor.registerHandler(
    'reprocess_knowledge_base_task',
    handleReprocessKnowledgeBaseImpl,
  );
  executor.registerHandler('process_ai_reply', handleProcessAiReplyImpl);
  executor.registerHandler('knowledge_insight_task', handleKnowledgeInsight);
  executor.registerHandler(
      'schedule_aggregator_task', handleScheduleAggregation);
  executor.registerHandler(
    'schedule_refresh_router_task',
    handleScheduleRefreshRouter,
  );
  executor.registerHandler(
    'clarification_resolution_task',
    handleClarificationResolution,
  );
  executor.registerHandler(
    'companion_delegation',
    handleCompanionDelegation,
  );
  executor.registerHandler(
    'dev_session_followup',
    handleDevSessionFollowup,
  );

  executor.registerFailureHandler(
    'conversation_capture_task',
    handleConversationCaptureFailure,
  );
  executor.registerFailureHandler(
    'companion_delegation',
    handleCompanionDelegationFailure,
  );
  executor.registerFailureHandler(
    'dev_session_followup',
    handleDevSessionFollowupFailure,
  );
  for (final taskType in [
    'comment_agent_task',
    'knowledge_insight_task',
    'schedule_aggregator_task',
    'schedule_refresh_router_task',
    'clarification_resolution_task',
    'reprocess_cards_task',
    'reprocess_comments_task',
    'reprocess_knowledge_base_task',
    'process_ai_reply',
    'handle_analyze_assets',
  ]) {
    executor.registerFailureHandler(taskType, handleGenericAgentFailure);
  }

  initCustomAgentHandler();
}
