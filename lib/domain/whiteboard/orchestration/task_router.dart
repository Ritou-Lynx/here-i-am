/// 任务路由：固定路由表 + 执行器注册（W5 Phase 2）。
///
/// 路由表是固定的名称映射（coding → coding-agent 等）；执行器实例通过
/// [registerExecutor] 注入。真实 CodingAgent 接线 Dev Room Bridge（Phase 3），
/// 本轮默认由 [LinAiOrchestrator] 注册 Mock / Inline 占位执行器。
library;

import '../../../data/memory_v3/models/task_room_enums.dart';

/// 执行结果状态。
enum ExecutionStatus {
  completed,
  failed,
  cancelled;

  static ExecutionStatus fromString(String raw) {
    return ExecutionStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => ExecutionStatus.failed,
    );
  }
}

/// 派发给执行器的任务请求。
class TaskExecutionRequest {
  final String taskId;
  final TaskType taskType;
  final String goal;
  final Map<String, dynamic> context;

  const TaskExecutionRequest({
    required this.taskId,
    required this.taskType,
    required this.goal,
    this.context = const {},
  });
}

/// 执行器返回的结果。
class TaskExecutionResult {
  final ExecutionStatus status;
  final String summary;
  final List<String> decisions;
  final List<String> artifactRefs;
  final List<String> filesChanged;
  final String? error;

  /// 类型特定的附加结构化数据（如内容生成器的卡片草稿），
  /// 保持 [TaskExecutionResult] 本身与具体 Agent 类型解耦。
  final Map<String, dynamic>? extra;

  const TaskExecutionResult({
    required this.status,
    required this.summary,
    this.decisions = const [],
    this.artifactRefs = const [],
    this.filesChanged = const [],
    this.error,
    this.extra,
  });

  bool get isSuccessful => status == ExecutionStatus.completed;
}

/// 执行器统一接口（CodingAgent / ContentAgent / 林埃自执行都实现它）。
abstract interface class TaskExecutor {
  String get executorId;
  Future<TaskExecutionResult> execute(TaskExecutionRequest request);
}

/// 林埃自执行占位：无外部 Agent 时由编排器内联处理的任务类型。
///
/// Phase 2 只产生确定性的占位结果；真实执行器在 Phase 3 接入。
class InlineSelfExecutor implements TaskExecutor {
  @override
  String get executorId => 'self';

  @override
  Future<TaskExecutionResult> execute(TaskExecutionRequest request) async {
    return TaskExecutionResult(
      status: ExecutionStatus.completed,
      summary: '已由林埃内联处理（Phase 2 占位）：${request.goal}',
      decisions: const ['本轮使用占位执行器，真实策略待 Phase 3 接入'],
    );
  }
}

/// 任务路由器：固定路由表 + 按名注册的执行器。
class TaskRouter {
  /// 固定路由表：TaskType → 执行器名。
  ///
  /// 这是 Phase 2 的固定派发表，不是配置；变更需走契约流程。
  static const Map<TaskType, String> fixedRouteTable = {
    TaskType.coding: 'coding-agent',
    TaskType.debugging: 'coding-agent',
    TaskType.contentGeneration: 'content-agent',
    TaskType.research: 'self',
    TaskType.planning: 'self',
    TaskType.media: 'self',
    TaskType.linkIngestion: 'self',
    TaskType.whiteboard: 'self',
    TaskType.other: 'self',
  };

  final Map<String, TaskExecutor> _executors = {};

  /// 注册执行器（同名重复注册会覆盖）。
  void registerExecutor(String executorId, TaskExecutor executor) {
    _executors[executorId] = executor;
  }

  /// 固定路由表查名。
  String routeFor(TaskType type) {
    return fixedRouteTable[type] ?? fixedRouteTable[TaskType.other]!;
  }

  /// 查执行器实例；未注册返回 null。
  TaskExecutor? executorFor(TaskType type) {
    return _executors[routeFor(type)];
  }

  /// 该类型是否可派发（对应执行器已注册）。
  bool canDispatch(TaskType type) => executorFor(type) != null;

  /// 派发任务。没有注册对应执行器时抛 [StateError]。
  Future<TaskExecutionResult> dispatch(TaskExecutionRequest request) async {
    final executor = executorFor(request.taskType);
    if (executor == null) {
      throw StateError(
        'No executor registered for "${request.taskType.value}" '
        '(route="${routeFor(request.taskType)}"). '
        'Register one via registerExecutor().',
      );
    }
    return executor.execute(request);
  }
}
