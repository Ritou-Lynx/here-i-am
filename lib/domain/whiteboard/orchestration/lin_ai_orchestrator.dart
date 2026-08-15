/// LinAiOrchestrator：林埃编排层（W5 Phase 2）。
///
/// 用户一句消息 → 意图分类 → 固定路由派发 → TaskRoom（状态机合法）
/// → 结果压缩 → 写回 Memory V3（对话摘要 + 房间 + 产物）。
///
/// 编排器对画布的写操作产出 [WhiteboardOperation]（Huabu 三层命令架构），
/// 与用户操作走同一条执行 / 撤销路径（执行器由 Task B 提供，Phase 3 接线）。
/// 本层**绝不自动写 User-truth**（memory_cards 由用户显式动作产生）。
library;

import '../../../data/memory_v3/models/task_room_enums.dart';
import '../../../data/memory_v3/services/task_room_service.dart';
import '../agents/coding_agent.dart';
import '../agents/content_agent.dart';
import '../whiteboard_ids.dart';
import '../whiteboard_snapshot.dart';
import 'intent_classifier.dart';
import 'model_router.dart';
import 'result_compressor.dart';
import 'task_router.dart';

/// 一条对话回合记录（Memory V3 的 PersonaChatMessages 承载）。
class ConversationTurnRecord {
  /// 'user' 或 'assistant'。
  final String role;
  final String content;
  final String? taskRoomId;

  const ConversationTurnRecord({
    required this.role,
    required this.content,
    this.taskRoomId,
  });

  bool get isFromCharacter => role == 'assistant';
}

/// 对话日志写入接口（编排层不直接碰 Drift）。
///
/// 数据层实现：`lib/data/memory_v3/services/orchestration_chat_writer.dart`
/// 的 [PersonaChatLogWriter]。
abstract interface class ConversationLogWriter {
  Future<void> append(ConversationTurnRecord turn);
}

/// 一轮编排的完整结果。
class OrchestrationOutcome {
  /// 给用户的回复文本。
  final String reply;

  /// 创建的任务房间 ID。
  final String taskId;

  final TaskType taskType;
  final ModelSelection modelSelection;
  final CompressedResult compressed;

  /// 编排产出的画布操作（走与用户操作同一条执行路径）。
  final List<WhiteboardOperation> operations;

  final ExecutionStatus status;

  const OrchestrationOutcome({
    required this.reply,
    required this.taskId,
    required this.taskType,
    required this.modelSelection,
    required this.compressed,
    required this.operations,
    required this.status,
  });
}

/// 林埃编排器。
class LinAiOrchestrator {
  final TaskRoomService taskRooms;
  final ConversationLogWriter chat;
  final IntentClassifier classifier;
  final TaskRouter router;
  final ModelRouter modelRouter;
  final ResultCompressor compressor;

  LinAiOrchestrator({
    required this.taskRooms,
    required this.chat,
    IntentClassifier? classifier,
    TaskRouter? router,
    ModelRouter? modelRouter,
    ResultCompressor? compressor,
  })  : classifier = classifier ?? IntentClassifier(),
        router = _resolveRouter(router),
        modelRouter = modelRouter ??
            ModelRouter(config: const ModelConfig()),
        compressor = compressor ?? ResultCompressor();

  /// 默认接线：未提供 router 时注册 Mock/占位执行器；
  /// 调用方传入 router 则完全由其负责注册（默认不覆盖）。
  static TaskRouter _resolveRouter(TaskRouter? router) {
    if (router != null) return router;
    return TaskRouter()
      ..registerExecutor('coding-agent', CodingAgentExecutor(MockCodingAgent()))
      ..registerExecutor(
          'content-agent', ContentAgentExecutor(MockContentAgent()))
      ..registerExecutor('self', InlineSelfExecutor());
  }

  // ========================================================================
  // W5 § 5.1 接口：各环节独立暴露，便于单测
  // ========================================================================

  /// 意图分类（规则 + 关键词）。
  TaskIntent classifyIntent(String message) => classifier.classify(message);

  /// 固定路由表查名（TaskType → 执行器名）。
  String routeTask(TaskType type) => router.routeFor(type);

  /// 模型选择（含 fallback 链与额度检查）。
  ModelSelection selectModel(TaskType type) => modelRouter.selectModel(type);

  /// 结果压缩（长输出 → 摘要 + 决策 + 产物引用）。
  CompressedResult compressResult(TaskExecutionResult result) =>
      compressor.compress(result);

  // ========================================================================
  // 端到端闭环
  // ========================================================================

  /// 处理一句用户消息，返回编排结果。
  ///
  /// [boardId] / [conversationId] 可挂在任务房间上；
  /// [context] 会写入任务房间 contextJson（含模型选择信息）。
  Future<OrchestrationOutcome> handleUserMessage(
    String message, {
    String? boardId,
    String? conversationId,
    Map<String, dynamic>? context,
  }) async {
    // 1. 意图分类
    final intent = classifyIntent(message);

    // 2. 模型选择（无配置时降级为占位模型，不阻塞闭环）
    ModelSelection model;
    try {
      model = selectModel(intent.type);
    } on ModelUnavailableException {
      model = const ModelSelection(
        model: 'unconfigured-local',
        level: FallbackLevel.local,
      );
    }

    // 3. 创建任务房间（pending）并置为 running
    final taskId = await taskRooms.createTaskRoom(
      title: _titleFor(message),
      goal: message,
      taskType: intent.type,
      executor: routeTask(intent.type),
      context: {
        'board_id': boardId,
        'model': model.model,
        'model_level': model.level.name,
        if (context != null) ...context,
      },
      conversationId: conversationId,
      boardId: boardId,
    );
    await taskRooms.updateTaskStatus(
      id: taskId,
      status: TaskStatus.running,
      currentStep: 'dispatched to ${routeTask(intent.type)}',
    );

    // 4. 写入用户回合
    await chat.append(
      ConversationTurnRecord(
        role: 'user',
        content: message,
        taskRoomId: taskId,
      ),
    );

    // 5. 派发执行（固定路由表）
    final request = TaskExecutionRequest(
      taskId: taskId,
      taskType: intent.type,
      goal: message,
      context: {'board_id': boardId, 'model': model.model},
    );
    TaskExecutionResult result;
    try {
      result = await router.dispatch(request);
    } catch (e) {
      result = TaskExecutionResult(
        status: ExecutionStatus.failed,
        summary: '执行器派发失败',
        error: e.toString(),
      );
    }

    // 6. 压缩结果
    final compressed = compressResult(result);

    // 7. 产物入 TaskArtifacts（压缩版入对话，完整产物入 Artifact 表）
    await taskRooms.recordArtifact(
      taskId: taskId,
      artifactType: _artifactTypeFor(intent.type),
      title: 'execution result (${model.model})',
      content: {
        'status': result.status.name,
        'summary': result.summary,
        'decisions': result.decisions,
        'artifact_refs': result.artifactRefs,
        'files_changed': result.filesChanged,
        'model': model.model,
        if (result.error != null) 'error': result.error,
      },
    );

    // 8. 状态机收口
    if (result.isSuccessful) {
      await taskRooms.updateTaskStatus(
        id: taskId,
        status: TaskStatus.completed,
        progressPercent: 100,
        currentStep: 'compressed & persisted',
      );
    } else {
      await taskRooms.updateTaskStatus(id: taskId, status: TaskStatus.failed);
    }

    // 9. 画布操作（内容生成 + 有目标板时产出 place 操作）
    final generatedCards = _extractCardDrafts(result.extra);
    final operations = buildBoardOperations(
      taskId: taskId,
      boardId: boardId,
      cards: generatedCards,
    );

    // 10. 组装回复 + 写入助理回合
    final reply = _composeReply(compressed, result, model);
    await chat.append(
      ConversationTurnRecord(
        role: 'assistant',
        content: reply,
        taskRoomId: taskId,
      ),
    );

    return OrchestrationOutcome(
      reply: reply,
      taskId: taskId,
      taskType: intent.type,
      modelSelection: model,
      compressed: compressed,
      operations: operations,
      status: result.status,
    );
  }

  /// 把内容生成的卡片草稿规划为白板操作（Huabu：agent 与用户收敛到同一执行路径）。
  ///
  /// - actor = [OperationActor.i]，authorizationId = 任务房间 ID
  ///   （任务由用户消息显式发起，即本轮授权）；
  /// - payload 只带 card_id / card_kind 元数据，不带内容；
  /// - 未指定 [boardId] 时返回空列表（无目标板不规划）。
  List<WhiteboardOperation> buildBoardOperations({
    required String taskId,
    required String? boardId,
    required List<GeneratedCardDraft> cards,
  }) {
    if (boardId == null || cards.isEmpty) return const [];
    final now = DateTime.now().toUtc();
    return [
      for (final card in cards)
        WhiteboardOperation(
          operationId: StableId.generate('op').value,
          boardId: boardId,
          actor: OperationActor.i,
          operationKind: OperationKind.place,
          targetIds: [card.draftId],
          payload: {'card_id': card.draftId, 'card_kind': card.cardKind},
          inverse: {
            'operation_kind': OperationKind.remove.name,
            'target_ids': [card.draftId],
          },
          authorizationId: taskId,
          createdAt: now,
        ),
    ];
  }

  // ========================================================================
  // 内部
  // ========================================================================

  static String _titleFor(String message) {
    final trimmed = message.trim();
    return trimmed.length <= 30 ? trimmed : '${trimmed.substring(0, 30)}…';
  }

  static ArtifactType _artifactTypeFor(TaskType type) {
    switch (type) {
      case TaskType.coding:
      case TaskType.debugging:
        return ArtifactType.codeDiff;
      case TaskType.contentGeneration:
        return ArtifactType.documentation;
      case TaskType.media:
      case TaskType.research:
        return ArtifactType.analysisResult;
      case TaskType.planning:
        return ArtifactType.documentation;
      case TaskType.whiteboard:
      case TaskType.linkIngestion:
      case TaskType.other:
        return ArtifactType.other;
    }
  }

  String _composeReply(
    CompressedResult compressed,
    TaskExecutionResult result,
    ModelSelection model,
  ) {
    if (!result.isSuccessful) {
      final reason = result.error ?? result.summary;
      return '任务未完成（${result.status.name}）：$reason';
    }
    final modelNote = model.isFallback
        ? '（当前使用${model.level == FallbackLevel.local ? '本地模型' : '备用模型'} ${model.model}）'
        : null;
    return compressor.composeReply(compressed, modelNote: modelNote);
  }

  /// 从执行结果的 extra 中取出内容生成器产出的卡片草稿。
  static List<GeneratedCardDraft> _extractCardDrafts(
    Map<String, dynamic>? extra,
  ) {
    final raw = extra?['generated_cards'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(GeneratedCardDraft.fromJson)
        .toList();
  }
}
