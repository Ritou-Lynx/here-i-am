import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';
import '../models/task_room_enums.dart';

/// TaskRoomService: 管理任务房间、产物和决策
///
/// 任务房间是用户与林埃协作完成复杂任务的空间，支持：
/// - 任务生命周期管理（创建、更新、完成、取消）
/// - 产物记录（代码变更、生成卡片、分析结果、决策记录、错误日志）
/// - 决策追踪（方案选择、参数值、审批/拒绝）
/// - 与 PersonaChatMessages 的软引用关联
class TaskRoomService {
  final AppDatabase _db;
  final Logger _log = Logger('TaskRoomService');
  final Uuid _uuid = const Uuid();

  static bool _initialized = false;
  static TaskRoomService? _instance;

  TaskRoomService({required AppDatabase db}) : _db = db;

  static void init(AppDatabase db) {
    _instance = TaskRoomService(db: db);
    _initialized = true;
  }

  static TaskRoomService get instance {
    if (!_initialized || _instance == null) {
      throw StateError('TaskRoomService not initialized. Call init() first.');
    }
    return _instance!;
  }

  // ========================================================================
  // Task Room CRUD
  // ========================================================================

  /// 创建新任务房间
  Future<String> createTaskRoom({
    required String title,
    required String goal,
    required TaskType taskType,
    String? executor, // claude-code / gpt-4v / self / manual
    Map<String, dynamic>? permissions,
    Map<String, dynamic>? context,
    String? conversationId,
    String? parentTaskId,
    String? boardId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.into(_db.taskRooms).insert(
          TaskRoomsCompanion.insert(
            id: id,
            title: title,
            goal: goal,
            taskType: taskType.value,
            status: TaskStatus.pending.value,
            executor: Value(executor),
            permissionsJson: Value(
              permissions != null ? jsonEncode(permissions) : '{}',
            ),
            contextJson: Value(
              context != null ? jsonEncode(context) : '{}',
            ),
            progressPercent: const Value(0),
            currentStep: const Value(null),
            conversationId: Value(conversationId),
            parentTaskId: Value(parentTaskId),
            boardId: Value(boardId),
            createdAt: now,
            updatedAt: now,
            completedAt: const Value(null),
          ),
        );

    _log.info('Created task room: $id "$title" type=${taskType.value}');
    return id;
  }

  /// 获取单个任务房间
  Future<TaskRoom?> getTaskRoom(String id) async {
    final query = _db.select(_db.taskRooms)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// 列出任务房间（支持过滤和分页）
  Future<List<TaskRoom>> listTaskRooms({
    TaskStatus? status,
    TaskType? taskType,
    String? boardId,
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = _db.select(_db.taskRooms);

    // 默认过滤掉已归档的任务
    if (!includeArchived) {
      query.where((t) => t.status.isNotValue(TaskStatus.archived.value));
    }

    if (status != null) {
      query.where((t) => t.status.equals(status.value));
    }
    if (taskType != null) {
      query.where((t) => t.taskType.equals(taskType.value));
    }
    if (boardId != null) {
      query.where((t) => t.boardId.equals(boardId));
    }

    query
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit, offset: offset);

    return query.get();
  }

  /// 更新任务房间状态
  ///
  /// 验证状态转移是否合法，如果转移无效则抛出异常。
  /// progressPercent 必须在 0-100 范围内。
  Future<void> updateTaskStatus({
    required String id,
    required TaskStatus status,
    int? progressPercent,
    String? currentStep,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 验证 progressPercent 范围
    if (progressPercent != null && (progressPercent < 0 || progressPercent > 100)) {
      throw ArgumentError('progressPercent must be between 0 and 100, got: $progressPercent');
    }

    // Validate state transition
    final currentTask = await getTaskRoom(id);
    if (currentTask == null) {
      throw ArgumentError('Task room not found: $id');
    }

    final currentStatus = TaskStatus.fromString(currentTask.status);

    // Allow same-state updates only for non-terminal states (to update progress/currentStep)
    // Terminal states (completed/failed/cancelled/archived) cannot be modified
    if (currentStatus != status) {
      // Different state: validate transition
      if (!currentStatus.canTransitionTo(status)) {
        throw StateError(
          'Invalid status transition: ${currentStatus.value} -> ${status.value}. '
          'Valid transitions: ${TaskStatus.validTransitions[currentStatus]?.map((s) => s.value).join(", ")}',
        );
      }
    } else {
      // Same state: only allow for non-terminal states
      if (currentStatus.isTerminal) {
        throw StateError(
          'Cannot update terminal state ${currentStatus.value}. '
          'Terminal states (completed/failed/cancelled/archived) are immutable.',
        );
      }
    }

    var updates = TaskRoomsCompanion(
      status: Value(status.value),
      updatedAt: Value(now),
    );

    if (progressPercent != null) {
      updates = updates.copyWith(progressPercent: Value(progressPercent));
    }
    if (currentStep != null) {
      updates = updates.copyWith(currentStep: Value(currentStep));
    }

    // 设置完成或归档时间戳
    if (status == TaskStatus.completed) {
      updates = updates.copyWith(completedAt: Value(now));
    } else if (status == TaskStatus.archived) {
      updates = updates.copyWith(archivedAt: Value(now));
    }

    await (_db.update(_db.taskRooms)..where((t) => t.id.equals(id)))
        .write(updates);

    _log.info('Updated task $id: status=${status.value} progress=$progressPercent');
  }

  /// 更新任务上下文
  Future<void> updateTaskContext({
    required String id,
    Map<String, dynamic>? context,
    Map<String, dynamic>? permissions,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var updates = TaskRoomsCompanion(
      updatedAt: Value(now),
    );

    if (context != null) {
      updates = updates.copyWith(contextJson: Value(jsonEncode(context)));
    }
    if (permissions != null) {
      updates = updates.copyWith(
          permissionsJson: Value(jsonEncode(permissions)));
    }

    await (_db.update(_db.taskRooms)..where((t) => t.id.equals(id)))
        .write(updates);
  }

  /// 归档任务房间（软删除）
  ///
  /// 将任务房间标记为 archived 状态，而不是物理删除。
  /// 这符合 append-only 原则：保留历史证据，但在日常查询中隐藏。
  ///
  /// 如需彻底删除隐私数据，应使用专门的数据清除流程。
  Future<void> archiveTaskRoom(String id) async {
    await updateTaskStatus(
      id: id,
      status: TaskStatus.archived,
    );
    _log.info('Archived task room: $id');
  }

  /// 物理删除任务房间（仅用于数据清除流程）
  ///
  /// ⚠️ **警告：此操作不可逆，会永久删除所有相关数据！**
  ///
  /// 此方法仅用于用户明确要求的隐私数据清除流程，不应在日常任务操作中使用。
  /// 日常操作应使用 [archiveTaskRoom] 进行软删除。
  @Deprecated('Use archiveTaskRoom for normal operations')
  Future<void> permanentlyDeleteTaskRoom(String id) async {
    await _db.transaction(() async {
      // 删除关联的产物
      await (_db.delete(_db.taskArtifacts)
            ..where((t) => t.taskId.equals(id)))
          .go();

      // 删除关联的决策
      await (_db.delete(_db.taskDecisions)
            ..where((t) => t.taskId.equals(id)))
          .go();

      // 删除任务房间
      await (_db.delete(_db.taskRooms)..where((t) => t.id.equals(id))).go();
    });

    _log.info('Permanently deleted task room: $id (with artifacts and decisions)');
  }

  // ========================================================================
  // Task Artifacts
  // ========================================================================

  /// 记录任务产物
  ///
  /// **大小限制与外部存储：**
  /// - contentJson 内联存储限制为 100KB（UTF-8 字节数）
  /// - 超过 100KB 的产物必须提供 storageRef 外部引用
  /// - 当提供 storageRef 时，contentJson 只应保存摘要和元数据，不存储完整 payload
  /// - sizeBytes 保存外部原始产物的实际大小
  ///
  /// **调用者责任：**
  /// - 大产物（>100KB）：先写入外部存储，获得 storageRef，然后只传递元数据到 content
  /// - 小产物（≤100KB）：可直接传递完整内容到 content
  Future<String> recordArtifact({
    required String taskId,
    required ArtifactType artifactType,
    required String title,
    required Map<String, dynamic> content,
    int? sizeBytes,
    String? mimeType,
    String? storageRef,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    final contentJson = jsonEncode(content);
    final contentBytes = utf8.encode(contentJson).length;
    const maxInlineSize = 100 * 1024; // 100KB

    // 验证内联存储大小限制（无论是否有 storageRef，contentJson 都不得超过 100KB）
    if (contentBytes > maxInlineSize) {
      throw ArgumentError(
        'Artifact contentJson size ($contentBytes bytes) exceeds 100KB limit. '
        '${storageRef != null ? 'When using external storage (storageRef), ' : ''}'
        'contentJson must contain only metadata (file path, size, hash, etc.), not the full payload. '
        'Store large content externally first, then record only metadata here.',
      );
    }

    await _db.into(_db.taskArtifacts).insert(
          TaskArtifactsCompanion.insert(
            id: id,
            taskId: taskId,
            artifactType: artifactType.value,
            title: title,
            contentJson: contentJson,
            sizeBytes: Value(sizeBytes ?? contentBytes),
            mimeType: Value(mimeType),
            storageRef: Value(storageRef),
            createdAt: now,
          ),
        );

    _log.info('Recorded artifact: $id for task $taskId type=${artifactType.value}');
    return id;
  }

  /// 获取任务的所有有效产物（已过滤被撤销的产物）
  Future<List<TaskArtifact>> getTaskArtifacts(String taskId) async {
    final allArtifacts = await (_db.select(_db.taskArtifacts)
          ..where((t) => t.taskId.equals(taskId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();

    // 收集所有被撤销的产物 ID
    final retractedIds = <String>{};
    for (final artifact in allArtifacts) {
      if (artifact.artifactType == ArtifactType.other.value) {
        try {
          final content = jsonDecode(artifact.contentJson) as Map<String, dynamic>;
          final retractedId = content['retracted_artifact_id'];
          if (retractedId is String) {
            retractedIds.add(retractedId);
          }
        } catch (_) {
          // Not a retraction marker
        }
      }
    }

    // 过滤：排除被撤销的产物和撤销标记本身
    return allArtifacts.where((artifact) {
      final isRetracted = retractedIds.contains(artifact.id);
      final isRetractionMarker = artifact.artifactType == ArtifactType.other.value &&
          artifact.title.startsWith('Retraction: ');
      return !isRetracted && !isRetractionMarker;
    }).toList();
  }

  /// 获取特定类型的有效产物
  Future<List<TaskArtifact>> getArtifactsByType({
    required String taskId,
    required ArtifactType artifactType,
  }) async {
    final allArtifacts = await getTaskArtifacts(taskId);
    return allArtifacts
        .where((a) => a.artifactType == artifactType.value)
        .toList();
  }

  /// 撤销产物（追加 retracted 状态）
  ///
  /// 不物理删除产物，而是追加一条新的 retracted 标记产物。
  /// 这符合 append-only 原则：保留完整的产物演化历史。
  ///
  /// 查询产物时，应过滤掉被 retracted 的产物。
  Future<void> retractArtifact({
    required String originalArtifactId,
    String? reason,
  }) async {
    // 读取原产物以获取 taskId
    final original = await (_db.select(_db.taskArtifacts)
          ..where((t) => t.id.equals(originalArtifactId)))
        .getSingleOrNull();

    if (original == null) {
      throw StateError('Artifact not found: $originalArtifactId');
    }

    // 追加一条 retracted 标记产物
    await recordArtifact(
      taskId: original.taskId,
      artifactType: ArtifactType.other, // Retraction marker
      title: 'Retraction: ${original.title}',
      content: {
        'retracted_artifact_id': originalArtifactId,
        'reason': reason,
      },
    );

    _log.info('Retracted artifact: $originalArtifactId (reason: $reason)');
  }

  /// 物理删除产物（仅用于数据清除流程）
  ///
  /// ⚠️ **警告：此操作不可逆！**
  ///
  /// 此方法仅用于用户明确要求的隐私数据清除流程，不应在日常任务操作中使用。
  /// 日常操作应使用 [retractArtifact] 追加撤销标记。
  @Deprecated('Use retractArtifact for normal operations')
  Future<void> permanentlyDeleteArtifact(String id) async {
    await (_db.delete(_db.taskArtifacts)..where((t) => t.id.equals(id))).go();
    _log.info('Permanently deleted artifact: $id');
  }

  // ========================================================================
  // Task Decisions
  // ========================================================================

  /// 记录任务决策
  ///
  /// 支持两种模式：
  /// 1. 已解决决策：提供 selectedOption 和 decidedBy
  /// 2. 待决策：不提供 selectedOption，状态为 pending
  Future<String> recordDecision({
    required String taskId,
    required DecisionType decisionType,
    required String question,
    required List<String> options,
    String? selectedOption,
    String? reasoning,
    String? decidedBy, // user / lin_ai / system
    DecisionStatus status = DecisionStatus.pending,
    String? supersedesDecisionId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.into(_db.taskDecisions).insert(
          TaskDecisionsCompanion.insert(
            id: id,
            taskId: taskId,
            decisionType: decisionType.value,
            status: Value(status.value),
            question: question,
            optionsJson: jsonEncode(options),
            selectedOption: Value(selectedOption),
            reasoning: Value(reasoning),
            decidedBy: Value(decidedBy),
            requestedAt: now,
            decidedAt: Value(status == DecisionStatus.resolved ? now : null),
            supersedesDecisionId: Value(supersedesDecisionId),
          ),
        );

    _log.info(
        'Recorded decision: $id for task $taskId type=${decisionType.value} status=${status.value}');
    return id;
  }

  /// 解决待决策（append-only 模式）
  ///
  /// 不修改原 pending 记录，而是追加一条新的 resolved 记录，
  /// 通过 supersedesDecisionId 指向原记录，保留完整决策历史。
  Future<String> resolveDecision({
    required String decisionId,
    required String selectedOption,
    required String decidedBy,
    String? reasoning,
  }) async {
    // 读取原决策
    final originalDecision = await (_db.select(_db.taskDecisions)
          ..where((t) => t.id.equals(decisionId)))
        .getSingleOrNull();

    if (originalDecision == null) {
      throw ArgumentError('Decision not found: $decisionId');
    }

    if (originalDecision.status != DecisionStatus.pending.value) {
      throw StateError(
        'Decision $decisionId is already ${originalDecision.status}, cannot resolve again',
      );
    }

    // 追加新的 resolved 记录
    final resolvedId = await recordDecision(
      taskId: originalDecision.taskId,
      decisionType: DecisionType.values.firstWhere(
        (e) => e.value == originalDecision.decisionType,
      ),
      question: originalDecision.question,
      options: (jsonDecode(originalDecision.optionsJson) as List).cast<String>(),
      selectedOption: selectedOption,
      reasoning: reasoning,
      decidedBy: decidedBy,
      status: DecisionStatus.resolved,
      supersedesDecisionId: decisionId,
    );

    _log.info('Resolved decision: $decisionId → $resolvedId choice=$selectedOption by=$decidedBy');
    return resolvedId;
  }

  /// 获取任务的所有决策（默认折叠，只返回最新版本）
  ///
  /// 通过 supersedesDecisionId 关系折叠决策历史，只返回当前有效的决策。
  /// 设置 includeSuperseded=true 可查看完整历史。
  Future<List<TaskDecision>> getTaskDecisions(
    String taskId, {
    bool includeSuperseded = false,
  }) async {
    final allDecisions = await (_db.select(_db.taskDecisions)
          ..where((t) => t.taskId.equals(taskId))
          ..orderBy([(t) => OrderingTerm.desc(t.requestedAt)]))
        .get();

    if (includeSuperseded) {
      return allDecisions;
    }

    // 收集所有被 supersede 的决策 ID
    final supersededIds = <String>{};
    for (final decision in allDecisions) {
      if (decision.supersedesDecisionId != null) {
        supersededIds.add(decision.supersedesDecisionId!);
      }
    }

    // 只返回未被 supersede 的决策
    return allDecisions.where((d) => !supersededIds.contains(d.id)).toList();
  }

  /// 获取特定类型的决策
  Future<List<TaskDecision>> getDecisionsByType({
    required String taskId,
    required DecisionType decisionType,
  }) async {
    final query = _db.select(_db.taskDecisions)
      ..where((t) => t.taskId.equals(taskId))
      ..where((t) => t.decisionType.equals(decisionType.value))
      ..orderBy([(t) => OrderingTerm.desc(t.requestedAt)]);
    return query.get();
  }

  /// 获取待决策列表
  Future<List<TaskDecision>> getPendingDecisions(String taskId) async {
    final query = _db.select(_db.taskDecisions)
      ..where((t) => t.taskId.equals(taskId))
      ..where((t) => t.status.equals(DecisionStatus.pending.value))
      ..orderBy([(t) => OrderingTerm.asc(t.requestedAt)]);
    return query.get();
  }

  // ========================================================================
  // 关联查询
  // ========================================================================

  /// 获取任务房间的所有聊天消息（通过 taskRoomId 软引用）
  Future<List<PersonaChatMessage>> getTaskRoomMessages(String taskId) async {
    final query = _db.select(_db.personaChatMessages)
      ..where((t) => t.taskRoomId.equals(taskId))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    return query.get();
  }

  /// 获取任务房间的完整上下文（房间 + 产物 + 决策 + 消息）
  ///
  /// ⚠️ **警告：此方法仅供 UI 展示使用，禁止用于 Agent 上下文注入！**
  ///
  /// 此方法会无上限返回任务房间的所有历史数据，包括：
  /// - 所有聊天消息（可能包含授权确认、错误信息、琐碎对话）
  /// - 所有产物（可能包含大型 diff、中间草稿、失败尝试）
  /// - 所有决策（可能包含撤销的决策、过时的方案）
  ///
  /// **直接将这些数据注入 Agent 上下文会违反记忆契约：**
  /// - 污染 User-truth：未经用户确认的过程数据不应进入 Memory V3
  /// - 上下文膨胀：任务过程数据可能极大，导致上下文窗口浪费
  /// - 隐私泄漏：可能包含用户不希望保留的临时数据
  ///
  /// **正确的使用方式：**
  /// - ✅ UI 展示：任务详情页、历史回放、调试面板
  /// - ❌ Agent 上下文：不要直接传给 Companion/RecordOrganizer 等 Agent
  ///
  /// **如需 Agent 访问任务上下文，应使用 Task Context Pack 机制（待实现）：**
  /// 1. 用户选择需要记住的消息/产物/决策
  /// 2. 对选择内容进行压缩和摘要
  /// 3. 生成带版本号的上下文快照
  /// 4. 只注入最新的已确认快照
  ///
  /// 参见：W5 Phase 1.1 的 Context Pack 设计
  Future<Map<String, dynamic>> getTaskRoomFullContext(String taskId) async {
    final room = await getTaskRoom(taskId);
    if (room == null) {
      throw StateError('Task room not found: $taskId');
    }

    final artifacts = await getTaskArtifacts(taskId);
    final decisions = await getTaskDecisions(taskId);
    final messages = await getTaskRoomMessages(taskId);

    return {
      'room': room,
      'artifacts': artifacts,
      'decisions': decisions,
      'messages': messages,
    };
  }
}
