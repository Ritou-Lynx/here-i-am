import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/domain/whiteboard/agents/coding_agent.dart';
import 'package:memex/domain/whiteboard/agents/content_agent.dart';
import 'package:memex/domain/whiteboard/orchestration/task_router.dart';

void main() {
  group('TaskRouter - 固定路由表', () {
    final router = TaskRouter();

    test('coding → coding-agent', () {
      expect(router.routeFor(TaskType.coding), 'coding-agent');
    });

    test('contentGeneration → content-agent', () {
      expect(router.routeFor(TaskType.contentGeneration), 'content-agent');
    });

    test('未指定类型回落 self', () {
      expect(router.routeFor(TaskType.research), 'self');
      expect(router.routeFor(TaskType.other), 'self');
    });

    test('未注册执行器时 canDispatch=false 且 dispatch 抛 StateError', () {
      expect(router.canDispatch(TaskType.coding), isFalse);
      expect(
        () => router.dispatch(const TaskExecutionRequest(
          taskId: 't1',
          taskType: TaskType.coding,
          goal: 'g',
        )),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('TaskRouter - 注册与派发', () {
    test('registerExecutor 后按名派发（coding → MockCodingAgent）', () async {
      final router = TaskRouter()
        ..registerExecutor('coding-agent', CodingAgentExecutor(MockCodingAgent()));

      expect(router.canDispatch(TaskType.coding), isTrue);
      final result = await router.dispatch(const TaskExecutionRequest(
        taskId: 'task-123',
        taskType: TaskType.coding,
        goal: '添加导出功能',
      ));
      expect(result.status, ExecutionStatus.completed);
      expect(result.isSuccessful, isTrue);
      expect(result.filesChanged, isNotEmpty);
      expect(result.artifactRefs, isNotEmpty);
    });

    test('内容生成派发带出卡片草稿（extra）', () async {
      final router = TaskRouter()
        ..registerExecutor(
            'content-agent', ContentAgentExecutor(MockContentAgent()));

      final result = await router.dispatch(const TaskExecutionRequest(
        taskId: 'task-456',
        taskType: TaskType.contentGeneration,
        goal: '生成一张卡片',
        context: {'board_id': 'board-1'},
      ));
      expect(result.status, ExecutionStatus.completed);
      final drafts = result.extra?['generated_cards'] as List<dynamic>;
      expect(drafts, isNotEmpty);
      expect((drafts.first as Map<String, dynamic>)['draft_id'], startsWith('card_draft_'));
    });

    test('覆盖注册同名执行器', () async {
      final router = TaskRouter()
        ..registerExecutor('self', InlineSelfExecutor());
      router.registerExecutor('self', _CustomExecutor());

      final result = await router.dispatch(const TaskExecutionRequest(
        taskId: 't2',
        taskType: TaskType.other,
        goal: 'g',
      ));
      expect(result.summary, contains('custom'));
    });

    test('InlineSelfExecutor 直接可用（固定表 self 路由）', () async {
      final router = TaskRouter()..registerExecutor('self', InlineSelfExecutor());
      final result = await router.dispatch(const TaskExecutionRequest(
        taskId: 't3',
        taskType: TaskType.planning,
        goal: '安排一下',
      ));
      expect(result.status, ExecutionStatus.completed);
    });
  });
}

class _CustomExecutor implements TaskExecutor {
  @override
  String get executorId => 'self';

  @override
  Future<TaskExecutionResult> execute(TaskExecutionRequest request) async {
    return const TaskExecutionResult(
      status: ExecutionStatus.completed,
      summary: 'custom executor result',
    );
  }
}
