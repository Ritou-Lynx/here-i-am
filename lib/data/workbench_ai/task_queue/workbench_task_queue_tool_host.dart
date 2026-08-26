library;

import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';

enum WorkbenchTaskQueueAction {
  enqueue('enqueue'),
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

/// Current-turn permission computed by trusted product code from the actual
/// product conversation and user message. It is never accepted in tool args.
class WorkbenchTaskQueueAuthorization {
  const WorkbenchTaskQueueAuthorization({
    required this.profileId,
    required this.conversationId,
    required this.allowedActions,
  });

  final String profileId;
  final String conversationId;
  final Set<WorkbenchTaskQueueAction> allowedActions;

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

    if (mentionsLongTask &&
        _containsAny(text, const [
          '作为',
          '创建',
          '启动',
          '开始',
          '排队',
          '加入',
          'enqueue',
          'queue',
          'start',
          'create',
        ])) {
      actions.add(WorkbenchTaskQueueAction.enqueue);
    }
    if (mentionsTask &&
        _containsAny(text, const ['状态', '进度', 'status', 'progress'])) {
      actions.add(WorkbenchTaskQueueAction.status);
    }
    if (mentionsTask && _containsAny(text, const ['暂停', 'pause'])) {
      actions.add(WorkbenchTaskQueueAction.pause);
    }
    if (mentionsTask &&
        _containsAny(text, const ['恢复', '继续', 'resume', 'continue'])) {
      actions.add(WorkbenchTaskQueueAction.resume);
    }
    if (mentionsTask &&
        _containsAny(text, const ['取消', '终止', 'cancel'])) {
      actions.add(WorkbenchTaskQueueAction.cancel);
    }
    if (mentionsTask &&
        _containsAny(text, const ['重试', '再试', 'retry'])) {
      actions.add(WorkbenchTaskQueueAction.retry);
    }

    return WorkbenchTaskQueueAuthorization(
      profileId: profileId,
      conversationId: conversationId,
      allowedActions: Set.unmodifiable(actions),
    );
  }

  bool _containsAny(String text, List<String> phrases) =>
      phrases.any(text.contains);
}

/// Provider-neutral host boundary for the durable long-task queue.
class WorkbenchTaskQueueToolHost {
  const WorkbenchTaskQueueToolHost(this._service);

  static const toolName = 'manage_long_task_queue';
  static const toolVersion = '1';
  static const int maxTitleCharacters = 200;
  static const int maxGoalCharacters = 4000;

  static const Map<String, dynamic> dynamicToolDefinition = {
    'name': toolName,
    'description': '管理 Here I am 产品宿主持有的独立长任务队列。'
        '仅在当前用户原话明确授权的动作上可用；scope、authorization、重试上限和执行者均由宿主持有，参数不能提供或扩大。'
        'task_id 省略时只会选择当前产品对话内最新的受控长任务。',
    'input_schema': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['request_id', 'action'],
      'properties': {
        'request_id': {'type': 'string', 'minLength': 1, 'maxLength': 256},
        'action': {
          'type': 'string',
          'enum': ['enqueue', 'status', 'pause', 'resume', 'cancel', 'retry'],
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
      final requestId = _boundedString(payload['request_id'], 'request_id', 256);
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
        final id = await _service.enqueueTaskRoom(
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
        final created = await _service.getTaskQueueSnapshot(id);
        if (created == null) {
          return _error(
            requestId: requestId,
            status: 'failed',
            errorCode: 'task_queue_persistence_failed',
          );
        }
        return _success(requestId, action, created, changed: true);
      }

      _expectAbsent(payload, const {'title', 'goal'});
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

      final validationError = _validateState(action, task);
      if (validationError != null) {
        return _error(
          requestId: requestId,
          status: 'rejected',
          errorCode: validationError,
          task: task,
        );
      }
      switch (action) {
        case WorkbenchTaskQueueAction.pause:
          await _service.pauseTaskRoom(id: task.id, reason: 'user_requested');
          break;
        case WorkbenchTaskQueueAction.resume:
          await _service.resumeTaskRoom(task.id);
          break;
        case WorkbenchTaskQueueAction.cancel:
          await _service.cancelTaskRoom(task.id);
          break;
        case WorkbenchTaskQueueAction.retry:
          await _service.retryTaskRoom(id: task.id);
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
      return _success(requestId, action, updated, changed: true);
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

  String? _validateState(
    WorkbenchTaskQueueAction action,
    TaskQueueSnapshot task,
  ) {
    switch (action) {
      case WorkbenchTaskQueueAction.pause:
        return task.status == TaskStatus.running ||
                (task.status == TaskStatus.blocked && task.isResumable)
            ? null
            : 'task_not_pausable';
      case WorkbenchTaskQueueAction.resume:
        return task.status == TaskStatus.blocked && task.isResumable
            ? null
            : 'task_not_resumable';
      case WorkbenchTaskQueueAction.cancel:
        return {
          TaskStatus.pending,
          TaskStatus.running,
          TaskStatus.blocked,
          TaskStatus.waitingForUser,
        }.contains(task.status)
            ? null
            : 'task_not_cancellable';
      case WorkbenchTaskQueueAction.retry:
        if (task.status != TaskStatus.failed) return 'task_not_retryable';
        return task.retryCount < task.maxRetries
            ? null
            : 'task_retry_limit_reached';
      case WorkbenchTaskQueueAction.enqueue:
      case WorkbenchTaskQueueAction.status:
        return null;
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
        if (task.resumableState != null)
          'resumable_state': task.resumableState,
        if (task.failureReason != null) 'failure_reason': task.failureReason,
        if (task.interruptedReason != null)
          'interrupted_reason': task.interruptedReason,
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
