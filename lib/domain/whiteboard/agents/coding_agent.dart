/// CodingAgent 接口占位（W5 Phase 2）。
///
/// 真实实现接线 Dev Room Bridge（Phase 3）。本轮提供接口 + Mock，
/// 供编排层端到端闭环使用。
library;

import '../orchestration/task_router.dart';

/// Coding 任务请求。
class CodingRequest {
  final String taskId;
  final String goal;
  final Map<String, List<String>> permissions;
  final Map<String, dynamic> context;

  const CodingRequest({
    required this.taskId,
    required this.goal,
    this.permissions = const {},
    this.context = const {},
  });
}

/// Coding 任务结果。
class CodingResult {
  final ExecutionStatus status;
  final String summary;
  final List<String> decisions;
  final List<String> filesChanged;
  final List<String> artifactRefs;
  final String? error;

  const CodingResult({
    required this.status,
    required this.summary,
    this.decisions = const [],
    this.filesChanged = const [],
    this.artifactRefs = const [],
    this.error,
  });

  TaskExecutionResult toExecutionResult() => TaskExecutionResult(
        status: status,
        summary: summary,
        decisions: decisions,
        artifactRefs: artifactRefs,
        filesChanged: filesChanged,
        error: error,
      );
}

/// Coding Agent 接口。
abstract interface class CodingAgent {
  String get executorId;
  Future<CodingResult> execute(CodingRequest request);
}

/// TaskExecutor 适配：把 [CodingAgent] 包装成 TaskRouter 可派发的执行器。
class CodingAgentExecutor implements TaskExecutor {
  final CodingAgent agent;

  CodingAgentExecutor(this.agent);

  @override
  String get executorId => agent.executorId;

  @override
  Future<TaskExecutionResult> execute(TaskExecutionRequest request) async {
    final result = await agent.execute(
      CodingRequest(
        taskId: request.taskId,
        goal: request.goal,
        context: request.context,
      ),
    );
    return result.toExecutionResult();
  }
}

/// Mock Coding Agent：返回确定性的占位结果。
///
/// 与固定路由表 [TaskRouter.fixedRouteTable] 一致，executorId 为 `coding-agent`。
class MockCodingAgent implements CodingAgent {
  @override
  String get executorId => 'coding-agent';

  @override
  Future<CodingResult> execute(CodingRequest request) async {
    final shortId = _shortId(request.taskId);
    return CodingResult(
      status: ExecutionStatus.completed,
      summary: '已实现「${request.goal}」：新增导出与配置处理（Mock 占位，真实执行器 Phase 3 接入）',
      decisions: const ['选择 JSON 作为默认导出格式'],
      filesChanged: const ['src/export.dart', 'src/app.dart'],
      artifactRefs: ['diff-$shortId.patch', 'test-$shortId.log'],
    );
  }
}

String _shortId(String taskId) {
  final cleaned = taskId.replaceAll('-', '');
  return cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
}
