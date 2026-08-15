/// ContentAgent 接口占位（W5 Phase 2）。
///
/// 内容生成（卡片 / 文章 / 文案）的接口 + Mock。
/// 真实 LLM 接线在 Phase 3；本轮 Mock 产出卡片草稿（draft），
/// 不落 User-truth，最终卡片创建需用户确认（记忆契约）。
library;

import '../orchestration/task_router.dart';

/// 内容生成任务请求。
class ContentRequest {
  final String taskId;
  final String goal;
  final String? boardId;
  final Map<String, dynamic> context;

  const ContentRequest({
    required this.taskId,
    required this.goal,
    this.boardId,
    this.context = const {},
  });
}

  /// 生成的卡片草稿。
  ///
  /// draftId 是草稿标识，不是已创建 Card 的稳定 ID；真实建卡由执行器
  /// （Task B / Phase 3）在用户确认后完成。
  class GeneratedCardDraft {
  final String draftId;
  final String cardKind;
  final String title;
  final String summary;

  const GeneratedCardDraft({
    required this.draftId,
    required this.cardKind,
    required this.title,
    required this.summary,
  });

  factory GeneratedCardDraft.fromJson(Map<String, dynamic> json) {
    return GeneratedCardDraft(
      draftId: json['draft_id'] as String,
      cardKind: json['card_kind'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'draft_id': draftId,
        'card_kind': cardKind,
        'title': title,
        'summary': summary,
      };
}

/// 内容生成任务结果。
class ContentResult {
  final ExecutionStatus status;
  final String summary;
  final List<GeneratedCardDraft> generatedCards;
  final List<String> decisions;
  final List<String> artifactRefs;
  final String? error;

  const ContentResult({
    required this.status,
    required this.summary,
    this.generatedCards = const [],
    this.decisions = const [],
    this.artifactRefs = const [],
    this.error,
  });

  TaskExecutionResult toExecutionResult() => TaskExecutionResult(
        status: status,
        summary: summary,
        decisions: decisions,
        artifactRefs: artifactRefs,
        error: error,
        extra: generatedCards.isEmpty
            ? null
            : {
                'generated_cards':
                    generatedCards.map((c) => c.toJson()).toList(),
              },
      );
}

/// 内容生成 Agent 接口。
abstract interface class ContentAgent {
  String get executorId;
  Future<ContentResult> execute(ContentRequest request);
}

/// TaskExecutor 适配：把 [ContentAgent] 包装成 TaskRouter 可派发的执行器。
class ContentAgentExecutor implements TaskExecutor {
  final ContentAgent agent;

  ContentAgentExecutor(this.agent);

  @override
  String get executorId => agent.executorId;

  @override
  Future<TaskExecutionResult> execute(TaskExecutionRequest request) async {
    final result = await agent.execute(
      ContentRequest(
        taskId: request.taskId,
        goal: request.goal,
        boardId: request.context['board_id'] as String?,
        context: request.context,
      ),
    );
    return result.toExecutionResult();
  }
}

/// Mock Content Agent：返回确定性的卡片草稿。
///
/// 与固定路由表一致，executorId 为 `content-agent`。
class MockContentAgent implements ContentAgent {
  @override
  String get executorId => 'content-agent';

  @override
  Future<ContentResult> execute(ContentRequest request) async {
    final shortId = _shortContentId(request.taskId);
    return ContentResult(
      status: ExecutionStatus.completed,
      summary: '已生成 1 张卡片草稿「${request.goal}」的要点卡片（Mock 占位，真实生成 Phase 3 接入）',
      generatedCards: [
        GeneratedCardDraft(
          draftId: 'card_draft_${shortId}_0',
          cardKind: 'note',
          title: '关于「${request.goal}」的要点',
          summary: 'Mock 生成的卡片要点：定义、背景、关键信息占位。',
        ),
      ],
      decisions: const ['卡片暂存为草稿，等待用户确认后再正式建卡'],
      artifactRefs: ['card-$shortId.json'],
    );
  }
}

String _shortContentId(String taskId) {
  final cleaned = taskId.replaceAll('-', '');
  return cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
}
