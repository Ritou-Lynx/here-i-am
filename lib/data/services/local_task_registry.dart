import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/task_handlers/analyze_assets_handler.dart';
import 'package:memex/data/services/task_handlers/clarification_resolution_handler.dart';
import 'package:memex/data/services/task_handlers/companion_delegation_handler.dart';
import 'package:memex/data/services/task_handlers/conversation_capture_handler.dart';
import 'package:memex/data/services/task_handlers/custom_agent_task_handler.dart';
import 'package:memex/data/services/task_handlers/dev_session_followup_handler.dart';
import 'package:memex/data/services/task_handlers/fts_index_handler.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';

void registerLocalTaskHandlers() {
  final executor = LocalTaskExecutor.instance;

  executor.registerHandler('handle_analyze_assets', handleAnalyzeAssetsImpl);
  executor.registerHandler('fts_index_update', handleFtsIndexUpdateImpl);
  // Retained as a no-op drainer for historical conversation_capture_task rows
  // (legacy auto-capture is retired; see AGENTS.md memory contract).
  executor.registerHandler(
    'conversation_capture_task',
    handleConversationCapture,
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
    'clarification_resolution_task',
    'handle_analyze_assets',
  ]) {
    executor.registerFailureHandler(taskType, handleGenericAgentFailure);
  }

  initCustomAgentHandler();
}
