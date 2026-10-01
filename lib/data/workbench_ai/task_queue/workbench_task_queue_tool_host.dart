library;

import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';

import 'workbench_task_queue_execution_controller.dart';

enum WorkbenchTaskQueueAction {
  enqueue('enqueue'),
  start('start'),
  status('status'),
  pause('pause'),
  resume('resume'),
  cancel('cancel'),
  retry('retry');

  const WorkbenchTaskQueueAction(this.wireName);
  final String wireName;

  static WorkbenchTaskQueueAction parse(Object? value) {
    if (value is! String) {
      throw const FormatException('action must be a string');
    }
    return values.firstWhere(
      (action) => action.wireName == value,
      orElse: () => throw FormatException('unsupported action: $value'),
    );
  }
}

const _knownExecutionErrorCodes = {
  'task_not_available',
  'task_not_startable',
  'task_not_resumable',
  'task_not_retryable',
  'task_retry_limit_reached',
  'execution_already_active',
  'execution_owner_unavailable',
  'execution_state_changed',
  'execution_claim_lost',
  'execution_request_limit',
  'runtime_stop_unconfirmed',
  'task_queue_request_conflict',
  'runtime_execution_failed',
  'text_only_isolation_unverified',
};

class _ExecutionResult {
  const _ExecutionResult({required this.changed, this.error});

  final bool changed;
  final Map<String, dynamic>? error;
}

/// Current-turn permission computed by trusted product code from the actual
/// product conversation and user message. It is never accepted in tool args.
class WorkbenchTaskQueueAuthorization {
  const WorkbenchTaskQueueAuthorization({
    required this.profileId,
    required this.conversationId,
    required this.allowedActions,
    this.targetTaskId,
    this.hasTargetConflict = false,
  });

  final String profileId;
  final String conversationId;
  final Set<WorkbenchTaskQueueAction> allowedActions;

  /// Exact task selected by trusted host input for this turn. This is never
  /// derived from a Runtime tool payload.
  final String? targetTaskId;

  /// The current user turn named more than one possible target, so no target
  /// may be selected by the model or by a latest-task fallback.
  final bool hasTargetConflict;

  TaskQueueHostScope get scope => TaskQueueHostScope(
        profileId: profileId,
        scopeType: 'conversation',
        scopeId: conversationId,
      );
}

/// Deterministic minimum authorization for the production desktop chat turn.
///
/// Queue writes require explicit task/queue wording in the user's own text.
/// This is intentionally narrow; ambiguous phrasing remains an ordinary turn.
class DesktopWorkbenchTaskQueueAuthorizationFactory {
  const DesktopWorkbenchTaskQueueAuthorizationFactory();

  static const profileId = 'desktop_workbench_task_queue_v1';

  WorkbenchTaskQueueAuthorization build({
    required String conversationId,
    required String userText,
  }) {
    final text = userText.trim().toLowerCase();
    final actions = <WorkbenchTaskQueueAction>{};
    final mentionsTask = _containsAny(text, const [
      '任务',
      '队列',
      'task',
      'queue',
    ]);
    final mentionsLongTask = _containsAny(text, const [
      '长任务',
      '后台任务',
      '任务队列',
      'long task',
      'background task',
      'task queue',
    ]);
    final targetIds = _extractExplicitTaskIds(text);

    final enqueueCreationRequested = _containsAny(text, const [
      '作为',
      '创建',
      '排队',
      '加入',
      'enqueue',
      'queue this long task',
      'queue this background task',
      'queue as a long task',
      'queue as a background task',
      'create a long task',
      'create the long task',
      'create a background task',
    ]);
    final enqueueStartRequested = _containsAny(text, const [
      '启动',
      '开始',
      'start a long task',
      'start the long task',
      'start a background task',
    ]);
    final creationNegated = _isNegated(text, const [
      '作为',
      '创建',
      '排队',
      '加入',
      'enqueue',
      'queue',
      'create',
    ]);
    final startNegated = _isNegated(text, const ['启动', '开始']) ||
        RegExp(r"\b(?:do not|don't|dont|never|no need to)\s+start\b")
            .hasMatch(text);
    if (targetIds.isEmpty &&
        mentionsLongTask &&
        !creationNegated &&
        (enqueueCreationRequested ||
            (enqueueStartRequested && !startNegated))) {
      actions.add(WorkbenchTaskQueueAction.enqueue);
    }
    if (mentionsTask &&
        targetIds.length == 1 &&
        (_containsAny(text, const ['启动', '开始执行']) ||
            RegExp(r'\bstart\b').hasMatch(text)) &&
        !startNegated) {
      actions.add(WorkbenchTaskQueueAction.start);
    }
    if (mentionsTask &&
        _containsAny(text, const ['状态', '进度', 'status', 'progress']) &&
        !_isNegated(text, const [
          '查看',
          '看',
          '查询',
          '查',
          '显示',
          'check',
          'show',
          'get',
        ])) {
      actions.add(WorkbenchTaskQueueAction.status);
    }
    if (mentionsTask &&
        _containsAny(text, const ['暂停', 'pause']) &&
        !_isNegated(text, const ['暂停', 'pause'])) {
      actions.add(WorkbenchTaskQueueAction.pause);
    }
    if (mentionsTask &&
        _containsAny(text, const ['恢复', '继续', 'resume', 'continue']) &&
        !_isNegated(text, const ['恢复', '继续', 'resume', 'continue'])) {
      actions.add(WorkbenchTaskQueueAction.resume);
    }
    if (mentionsTask &&
        _containsAny(text, const ['取消', '终止', 'cancel']) &&
        !_isNegated(text, const ['取消', '终止', 'cancel'])) {
      actions.add(WorkbenchTaskQueueAction.cancel);
    }
    if (mentionsTask &&
        _containsAny(text, const ['重试', '再试', 'retry']) &&
        !_isNegated(text, const ['重试', '再试', 'retry'])) {
      actions.add(WorkbenchTaskQueueAction.retry);
    }

    return WorkbenchTaskQueueAuthorization(
      profileId: profileId,
      conversationId: conversationId,
      allowedActions: Set.unmodifiable(actions),
      targetTaskId: targetIds.length == 1 ? targetIds.single : null,
      hasTargetConflict: targetIds.length > 1,
    );
  }

  bool _containsAny(String text, List<String> phrases) =>
      phrases.any(text.contains);

  /// Production turns accept only an explicit UUID as a queue target. Internal
  /// hosts may directly construct [WorkbenchTaskQueueAuthorization] with a
  /// synthetic persisted ID; that test seam is not user-text authorization.
  Set<String> _extractExplicitTaskIds(String text) => RegExp(
        r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
      ).allMatches(text).map((match) => match.group(0)!).toSet();

  bool _isNegated(String text, List<String> verbs) {
    const prefixes = [
      '不要',
      '别',
      '不',
      '无需',
      '不用',
      '不能',
      'do not ',
      "don't ",
      'dont ',
      'never ',
      'no need to ',
    ];
    return verbs.any(
      (verb) => prefixes.any((prefix) => text.contains('$prefix$verb')),
    );
  }
}

/// Provider-neutral host boundary for the durable long-task queue.
class WorkbenchTaskQueueToolHost {
  const WorkbenchTaskQueueToolHost(
    this._service, {
    WorkbenchTaskQueueExecutionController? executionController,
  }) : _executionController = executionController;

  static const toolName = 'manage_long_task_queue';
  static const toolVersion = '1';
  static const int maxTitleCharacters = 200;
  static const int maxGoalCharacters = 4000;

  static const Map<String, dynamic> dynamicToolDefinition = {
    'name': toolName,
    'description': '管理 Here I am 产品宿主持有的独立长任务队列。'
        '仅在当前用户原话明确授权的动作上可用；scope、authorization、重试上限和执行者均由宿主持有，参数不能提供或扩大。'
        '仅目标未点名的 status 可省略 task_id 并只读当前对话内最新受控长任务；所有执行动作必须回传宿主绑定的精确 task_id。',
    'input_schema': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['request_id', 'action'],
      'properties': {
        'request_id': {'type': 'string', 'minLength': 1, 'maxLength': 256},
        'action': {
          'type': 'string',
          'enum': [
            'enqueue',
            'start',
            'status',
            'pause',
            'resume',
            'cancel',
            'retry',
          ],
        },
        'task_id': {'type': 'string', 'minLength': 1, 'maxLength': 128},
        'title': {
          'type': 'string',
          'minLength': 1,
          'maxLength': maxTitleCharacters,
        },
        'goal': {
          'type': 'string',
          'minLength': 1,
          'maxLength': maxGoalCharacters,
        },
      },
    },
  };

  final TaskRoomService _service;
  final WorkbenchTaskQueueExecutionController? _executionController;

  Future<Map<String, dynamic>> invoke(
    Map<String, dynamic> payload, {
    required WorkbenchTaskQueueAuthorization authorization,
  }) async {
    try {
      _expectKeys(payload, const {
        'request_id',
        'action',
        'task_id',
        'title',
        'goal',
      });
      final requestId =
          _boundedString(payload['request_id'], 'request_id', 256);
      final action = WorkbenchTaskQueueAction.parse(payload['action']);
      if (!authorization.allowedActions.contains(action)) {
        return _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: 'task_queue_action_not_authorized',
        );
      }
      if (action == WorkbenchTaskQueueAction.enqueue) {
        _expectAbsent(payload, const {'task_id'});
        final title = _boundedString(
          payload['title'],
          'title',
          maxTitleCharacters,
        );
        final goal = _boundedString(
          payload['goal'],
          'goal',
          maxGoalCharacters,
        );
        final enqueued = await _service.enqueueTaskRoomIdempotent(
          requestId: requestId,
          title: title,
          goal: goal,
          taskType: TaskType.other,
          executor: 'workbench_runtime',
          permissions: {
            'profile_id': authorization.profileId,
            'scope_type': 'conversation',
            'scope_id': authorization.conversationId,
          },
          conversationId: authorization.conversationId,
          queueHostScope: authorization.scope,
        );
        return _success(
          requestId,
          action,
          enqueued.snapshot,
          changed: enqueued.changed,
        );
      }

      _expectAbsent(payload, const {'title', 'goal'});
      final targetAuthorizationError = _targetAuthorizationError(
        action,
        payload['task_id'],
        authorization,
      );
      if (targetAuthorizationError != null) {
        return _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: targetAuthorizationError,
        );
      }
      final task = await _resolveTask(payload['task_id'], authorization.scope);
      if (task == null) {
        return _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: 'task_not_available',
        );
      }
      if (action == WorkbenchTaskQueueAction.status) {
        return _success(requestId, action, task, changed: false);
      }

      var changed = false;
      switch (action) {
        case WorkbenchTaskQueueAction.start:
          final executionError = await _invokeExecution(
            requestId: requestId,
            operation: (controller) => controller.start(
              id: task.id,
              scope: authorization.scope,
              requestId: requestId,
            ),
          );
          if (executionError.error != null) return executionError.error!;
          changed = executionError.changed;
          break;
        case WorkbenchTaskQueueAction.pause:
          final executionError = await _invokeExecution(
            requestId: requestId,
            operation: (controller) => controller.pause(
              id: task.id,
              scope: authorization.scope,
              requestId: requestId,
            ),
          );
          if (executionError.error != null) return executionError.error!;
          changed = executionError.changed;
          break;
        case WorkbenchTaskQueueAction.resume:
          final executionError = await _invokeExecution(
            requestId: requestId,
            operation: (controller) => controller.resume(
              id: task.id,
              scope: authorization.scope,
              requestId: requestId,
            ),
          );
          if (executionError.error != null) return executionError.error!;
          changed = executionError.changed;
          break;
        case WorkbenchTaskQueueAction.cancel:
          if (_executionController == null) {
            final queuedCancelError = await _cancelQueuedOnly(
              task: task,
              scope: authorization.scope,
              requestId: requestId,
            );
            if (queuedCancelError.error != null) {
              return queuedCancelError.error!;
            }
            changed = queuedCancelError.changed;
            break;
          }
          final executionError = await _invokeExecution(
            requestId: requestId,
            operation: (controller) => controller.cancel(
              id: task.id,
              scope: authorization.scope,
              requestId: requestId,
            ),
          );
          if (executionError.error != null) return executionError.error!;
          changed = executionError.changed;
          break;
        case WorkbenchTaskQueueAction.retry:
          final executionError = await _invokeExecution(
            requestId: requestId,
            operation: (controller) => controller.retry(
              id: task.id,
              scope: authorization.scope,
              requestId: requestId,
            ),
          );
          if (executionError.error != null) return executionError.error!;
          changed = executionError.changed;
          break;
        case WorkbenchTaskQueueAction.enqueue:
        case WorkbenchTaskQueueAction.status:
          throw StateError('unreachable task queue action');
      }
      final updated = await _service.getTaskQueueSnapshot(task.id);
      if (updated == null || !updated.belongsTo(authorization.scope)) {
        return _error(
          requestId: requestId,
          status: 'failed',
          errorCode: 'task_queue_persistence_failed',
        );
      }
      return _success(
        requestId,
        action,
        updated,
        changed: changed,
      );
    } on TaskQueueIdempotencyConflict {
      return const {
        'status': 'rejected',
        'error_code': 'task_queue_request_conflict',
      };
    } on FormatException {
      return const {
        'status': 'invalid_request',
        'error_code': 'invalid_task_queue_request',
      };
    } on ArgumentError {
      return const {
        'status': 'invalid_request',
        'error_code': 'invalid_task_queue_request',
      };
    } on StateError {
      return const {
        'status': 'rejected',
        'error_code': 'task_state_conflict',
      };
    } catch (_) {
      return const {
        'status': 'failed',
        'error_code': 'task_queue_host_failed',
      };
    }
  }

  Future<TaskQueueSnapshot?> _resolveTask(
    Object? rawTaskId,
    TaskQueueHostScope scope,
  ) async {
    if (rawTaskId == null) {
      return _service.findLatestTaskQueueForScope(scope);
    }
    final taskId = _boundedString(rawTaskId, 'task_id', 128);
    final task = await _service.getTaskQueueSnapshot(taskId);
    return task != null && task.belongsTo(scope) ? task : null;
  }

  String? _targetAuthorizationError(
    WorkbenchTaskQueueAction action,
    Object? rawTaskId,
    WorkbenchTaskQueueAuthorization authorization,
  ) {
    if (authorization.hasTargetConflict) return 'task_target_ambiguous';

    // A targetless status request is the sole preserved latest-task path, and
    // remains read-only. Any explicit user target must be echoed exactly.
    if (action == WorkbenchTaskQueueAction.status &&
        authorization.targetTaskId == null &&
        rawTaskId == null) {
      return null;
    }

    final targetTaskId = authorization.targetTaskId;
    if (targetTaskId == null || rawTaskId == null) {
      return 'task_target_required';
    }
    if (rawTaskId is! String || rawTaskId.trim() != targetTaskId) {
      return 'task_target_not_authorized';
    }
    return null;
  }

  Future<_ExecutionResult> _invokeExecution({
    required String requestId,
    required Future<bool> Function(
      WorkbenchTaskQueueExecutionController controller,
    ) operation,
  }) async {
    final controller = _executionController;
    if (controller == null) {
      return _ExecutionResult(
        changed: false,
        error: _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: 'task_queue_execution_unavailable',
        ),
      );
    }
    try {
      return _ExecutionResult(changed: await operation(controller));
    } on WorkbenchTaskQueueExecutionException catch (error) {
      return _ExecutionResult(
        changed: false,
        error: _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: _knownExecutionErrorCodes.contains(error.code)
              ? error.code
              : 'task_queue_execution_failed',
        ),
      );
    } catch (_) {
      return _ExecutionResult(
        changed: false,
        error: _error(
          requestId: requestId,
          status: 'failed',
          errorCode: 'task_queue_execution_failed',
        ),
      );
    }
  }

  /// The only controllerless cancellation path. B re-reads status and
  /// execution phase in its transaction, so a concurrent start cannot be
  /// cancelled from this stale host snapshot.
  Future<_ExecutionResult> _cancelQueuedOnly({
    required TaskQueueSnapshot task,
    required TaskQueueHostScope scope,
    required String requestId,
  }) async {
    try {
      final changed = await _service.cancelPendingTaskQueue(
        id: task.id,
        scope: scope,
        requestId: requestId,
      );
      return _ExecutionResult(changed: changed);
    } on TaskQueueIdempotencyConflict {
      return _ExecutionResult(
        changed: false,
        error: _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: 'task_queue_request_conflict',
        ),
      );
    } on StateError catch (error) {
      final code = error.message;
      return _ExecutionResult(
        changed: false,
        error: _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: _knownExecutionErrorCodes.contains(code)
              ? code
              : 'task_queue_execution_failed',
        ),
      );
    } on ArgumentError {
      return _ExecutionResult(
        changed: false,
        error: _error(
          requestId: requestId,
          status: 'invalid_request',
          errorCode: 'invalid_task_queue_request',
        ),
      );
    } catch (_) {
      return _ExecutionResult(
        changed: false,
        error: _error(
          requestId: requestId,
          status: 'failed',
          errorCode: 'task_queue_execution_failed',
        ),
      );
    }
  }

  Map<String, dynamic> _success(
    String requestId,
    WorkbenchTaskQueueAction action,
    TaskQueueSnapshot task, {
    required bool changed,
  }) =>
      {
        'status': 'ok',
        'request_id': requestId,
        'action': action.wireName,
        'changed': changed,
        'task': _snapshotJson(task),
      };

  Map<String, dynamic> _error({
    required String requestId,
    required String status,
    required String errorCode,
    TaskQueueSnapshot? task,
  }) =>
      {
        'status': status,
        'request_id': requestId,
        'error_code': errorCode,
        if (errorCode == 'text_only_isolation_unverified')
          'message': '无法验证独立文字执行隔离，任务未启动。',
        if (task != null) 'task': _snapshotJson(task),
      };

  Map<String, dynamic> _snapshotJson(TaskQueueSnapshot task) => {
        'task_id': task.id,
        'title': task.title,
        'status': task.status.value,
        'progress_percent': task.progressPercent,
        if (task.currentStep != null) 'current_step': task.currentStep,
        'retry_count': task.retryCount,
        'max_retries': task.maxRetries,
        'resumable': task.isResumable,
        if (task.resumableState != null) 'resumable_state': task.resumableState,
        if (task.failureReason != null) 'failure_reason': task.failureReason,
        if (task.interruptedReason != null)
          'interrupted_reason': task.interruptedReason,
        if (task.executionPhase != null) 'execution_phase': task.executionPhase,
        if (task.resultPreview != null) 'result_preview': task.resultPreview,
      };
}

void _expectKeys(Map<String, dynamic> payload, Set<String> allowed) {
  if (payload.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('unsupported task queue field');
  }
}

void _expectAbsent(Map<String, dynamic> payload, Set<String> fields) {
  if (fields.any(payload.containsKey)) {
    throw const FormatException('field is not valid for this action');
  }
}

String _boundedString(Object? value, String field, int maxLength) {
  if (value is! String) throw FormatException('$field must be a string');
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maxLength) {
    throw FormatException('$field is outside its length boundary');
  }
  return normalized;
}
