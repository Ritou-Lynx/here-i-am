import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/orchestration_chat_writer.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/orchestration/lin_ai_orchestrator.dart';
import 'package:memex/domain/whiteboard/orchestration/model_router.dart';
import 'package:memex/domain/whiteboard/orchestration/task_router.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

ModelConfig _config({bool exhaustPrimary = false}) {
  return ModelConfig.fromJson(jsonEncode({
    'schema_version': 1,
    'task_routing': {
      'content_generation': {
        'primary': {
          'model': 'claude-sonnet-4',
          'quota_key': 'anthropic_main',
        },
        'fallback': {
          'model': 'gemini-pro',
          'quota_key': 'google_main',
        },
        'local': {'model': 'local-llm'},
      },
      'other': {
        'primary': {'model': 'gpt-4o'},
        'fallback': {'model': 'gpt-4o-mini'},
      },
    },
    'quotas': {
      'anthropic_main': {
        'total': 1000,
        'used': exhaustPrimary ? 1000 : 100,
      },
      'google_main': {
        'total': 1000,
        'used': 100,
      },
    },
  }));
}

void main() {
  late AppDatabase db;
  late TaskRoomService taskRooms;
  late ConversationLogWriter chat;
  late LinAiOrchestrator orchestrator;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    taskRooms = TaskRoomService(db: db);
    chat = PersonaChatLogWriter(db: db);
    orchestrator = LinAiOrchestrator(
      taskRooms: taskRooms,
      chat: chat,
      modelRouter: ModelRouter(config: _config()),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('端到端闭环：用户消息 → TaskRoom → 压缩 → 写回 Memory V3', () {
    test('内容生成 + 目标板：完整闭环且库中可查', () async {
      final outcome = await orchestrator.handleUserMessage(
        '帮我生成一张关于现代主义建筑的卡片',
        boardId: 'board-1',
      );

      // 1. 任务房间创建并完成（状态机合法路径 pending→running→completed）
      final rooms = await taskRooms.listTaskRooms();
      expect(rooms.length, 1);
      final room = rooms.first;
      expect(room.id, outcome.taskId);
      expect(room.taskType, 'content_generation');
      expect(room.status, TaskStatus.completed.value);
      expect(room.executor, 'content-agent');
      expect(room.boardId, 'board-1');
      expect(room.progressPercent, 100);

      // 2. 对话回合写入（用户 + 林埃摘要），均关联 taskRoomId
      final turns = await db.select(db.personaChatMessages).get();
      expect(turns.length, 2);
      expect(turns.every((t) => t.taskRoomId == outcome.taskId), isTrue);
      expect(turns.first.isFromCharacter, isFalse);
      expect(turns.first.content, '帮我生成一张关于现代主义建筑的卡片');
      expect(turns.last.isFromCharacter, isTrue);
      expect(turns.last.content, outcome.reply);

      // 3. 产物入 TaskArtifacts
      final artifacts = await taskRooms.getTaskArtifacts(outcome.taskId);
      expect(artifacts.length, 1);
      expect(artifacts.first.artifactType, ArtifactType.documentation.value);
      final content =
          jsonDecode(artifacts.first.contentJson) as Map<String, dynamic>;
      expect(content['status'], 'completed');
      expect(content['artifact_refs'], isNotEmpty);

      // 4. 回复为压缩摘要
      expect(outcome.reply, contains('卡片草稿'));
      expect(outcome.status, ExecutionStatus.completed);
      expect(outcome.taskType, TaskType.contentGeneration);
    });

    test('coding 消息走 coding-agent', () async {
      final outcome = await orchestrator.handleUserMessage('帮我添加导出功能');

      final room = await taskRooms.getTaskRoom(outcome.taskId);
      expect(room!.taskType, 'coding');
      expect(room.executor, 'coding-agent');
      expect(room.status, TaskStatus.completed.value);
      expect(outcome.compressed.decisions, isNotEmpty);
    });

    test('未知意图 → other → self 执行器，闭环仍完成', () async {
      final outcome = await orchestrator.handleUserMessage('今天天气怎么样');
      expect(outcome.taskType, TaskType.other);
      expect(outcome.status, ExecutionStatus.completed);

      final room = await taskRooms.getTaskRoom(outcome.taskId);
      expect(room!.executor, 'self');
    });

    test('执行器失败 → 房间 failed，回复说明失败', () async {
      final router = TaskRouter()
        ..registerExecutor('self', _FailingExecutor());
      orchestrator = LinAiOrchestrator(
        taskRooms: taskRooms,
        chat: chat,
        router: router,
        modelRouter: ModelRouter(config: _config()),
      );

      final outcome = await orchestrator.handleUserMessage('今天天气怎么样');
      expect(outcome.status, ExecutionStatus.failed);
      expect(outcome.reply, contains('任务未完成'));

      final room = await taskRooms.getTaskRoom(outcome.taskId);
      expect(room!.status, TaskStatus.failed.value);
    });
  });

  group('模型选择与 fallback', () {
    test('primary 耗尽 → fallback 模型，回复含备用模型提示', () async {
      orchestrator = LinAiOrchestrator(
        taskRooms: taskRooms,
        chat: chat,
        modelRouter: ModelRouter(config: _config(exhaustPrimary: true)),
      );

      final outcome = await orchestrator.handleUserMessage(
        '帮我生成一张关于现代主义建筑的卡片',
        boardId: 'board-1',
      );
      expect(outcome.modelSelection.model, 'gemini-pro');
      expect(outcome.modelSelection.level, FallbackLevel.fallback);
      expect(outcome.modelSelection.isFallback, isTrue);
      expect(outcome.reply, contains('备用模型 gemini-pro'));

      // 房间 context 记录实际模型
      final room = await taskRooms.getTaskRoom(outcome.taskId);
      final context =
          jsonDecode(room!.contextJson) as Map<String, dynamic>;
      expect(context['model'], 'gemini-pro');
      expect(context['model_level'], 'fallback');
    });

    test('无配置 → 占位模型不阻塞闭环', () async {
      orchestrator = LinAiOrchestrator(
        taskRooms: taskRooms,
        chat: chat,
        modelRouter: ModelRouter(config: const ModelConfig()),
      );
      final outcome = await orchestrator.handleUserMessage('帮我生成一张卡片');
      expect(outcome.modelSelection.model, 'unconfigured-local');
      expect(outcome.status, ExecutionStatus.completed);
    });
  });

  group('状态机守卫', () {
    test('所有状态转移都经 TaskRoomService；非法转移被拒', () async {
      final outcome = await orchestrator.handleUserMessage('帮我生成一张卡片');
      expect(outcome.status, ExecutionStatus.completed);

      // completed 是终态：不可回到 running
      expect(
        () => taskRooms.updateTaskStatus(
          id: outcome.taskId,
          status: TaskStatus.running,
        ),
        throwsA(isA<StateError>()),
      );

      // 终态同状态更新也被拒
      expect(
        () => taskRooms.updateTaskStatus(
          id: outcome.taskId,
          status: TaskStatus.completed,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('编排器不会在完成后再次写状态（房间只有一条合法转移链）', () async {
      final outcome = await orchestrator.handleUserMessage('帮我生成一张卡片');
      final room = await taskRooms.getTaskRoom(outcome.taskId);
      expect(room!.status, TaskStatus.completed.value);
      expect(room.completedAt, isNotNull);
      expect(room.updatedAt, isNotNull);
    });
  });

  group('User-truth 守卫', () {
    test('编排全程不自动写 memory_cards（User-truth 契约）', () async {
      await orchestrator.handleUserMessage(
        '帮我生成一张关于现代主义建筑的卡片',
        boardId: 'board-1',
      );
      await orchestrator.handleUserMessage('帮我添加导出功能');

      final cards = await db.select(db.memoryCards).get();
      expect(cards, isEmpty,
          reason: '编排/Agent 过程产物不得自动进入 User-truth');
    });
  });

  group('跨边界契约：WhiteboardOperation', () {
    test('编排产出的操作符合 W0 契约（actor=i / 授权 / 可往返）', () async {
      final outcome = await orchestrator.handleUserMessage(
        '帮我生成一张关于现代主义建筑的卡片',
        boardId: 'board-1',
      );

      expect(outcome.operations, isNotEmpty);
      for (final op in outcome.operations) {
        // 与用户操作同一条执行路径的契约形态：可序列化往返
        final restored = WhiteboardOperation.fromJson(op.toJson());
        expect(restored.operationId, op.operationId);
        expect(restored.boardId, 'board-1');

        // 林埃写操作：actor=i 且必须携带授权引用
        expect(restored.actor, OperationActor.i);
        expect(restored.authorizationId, outcome.taskId,
            reason: 'i 的写操作必须引用有效授权（任务由用户消息显式发起）');

        // place 操作：targets 是草稿卡
        expect(restored.operationKind, OperationKind.place);
        expect(restored.targetIds, isNotEmpty);
        expect(restored.targetIds.first, startsWith('card_draft_'));
        // payload 只含元数据，不含内容
        expect(restored.payload.keys, contains('card_id'));
        expect(restored.payload.keys, isNot(contains('content')));
      }
    });

    test('无目标板时不产出操作', () async {
      final outcome = await orchestrator.handleUserMessage(
        '帮我生成一张关于现代主义建筑的卡片',
      );
      expect(outcome.operations, isEmpty);
    });
  });
}

class _FailingExecutor implements TaskExecutor {
  @override
  String get executorId => 'self';

  @override
  Future<TaskExecutionResult> execute(TaskExecutionRequest request) async {
    return const TaskExecutionResult(
      status: ExecutionStatus.failed,
      summary: '执行失败',
      error: 'mock failure',
    );
  }
}
