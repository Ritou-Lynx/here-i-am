import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../candidate/p6_r7_candidate_config.dart';
import '../task_queue/workbench_runtime_task_queue_tool.dart';
import '../task_queue/workbench_task_queue_tool_host.dart';
import 'workbench_task_product_session.dart';

/// First product Gate: one fixed public task, not arbitrary production tasks.
/// Persist must perform the existing Store validation and first-witness bind.
class P6R7ProductTaskBinding implements WorkbenchTaskProductSessionBinding {
  P6R7ProductTaskBinding({
    required this.conversationId,
    required Future<void> Function(String) persist,
    required Future<String> Function(String) readGoal,
    required Future<void> Function(String, String) register,
  })  : _persist = persist,
        _readGoal = readGoal,
        _register = register;

  final String conversationId;
  final Future<void> Function(String) _persist;
  final Future<String> Function(String) _readGoal;
  final Future<void> Function(String, String) _register;
  String? _taskId;
  bool _ready = false;
  Future<void>? _initialization;
  Future<void>? _binding;
  String? get taskId => _taskId;

  Future<void> initialize(String? initialTaskId) =>
      _initialization ??= _initialize(initialTaskId);

  Future<void> _initialize(String? initialTaskId) async {
    if (initialTaskId != null) await _bind(initialTaskId);
    _ready = true;
  }

  @override
  bool accepts(WorkbenchTaskQueueAuthorization authorization) {
    if (!_ready ||
        authorization.profileId !=
            DesktopWorkbenchTaskQueueAuthorizationFactory.profileId ||
        authorization.conversationId != conversationId ||
        authorization.hasTargetConflict ||
        authorization.allowedActions.isEmpty) {
      return false;
    }
    final actions = authorization.allowedActions;
    final target = authorization.targetTaskId;
    if (target == null &&
        actions.length == 1 &&
        actions.contains(WorkbenchTaskQueueAction.status)) {
      return true;
    }
    if (_taskId == null) {
      return target == null &&
          actions.length == 1 &&
          actions.contains(WorkbenchTaskQueueAction.enqueue);
    }
    return target == _taskId &&
        !actions.contains(WorkbenchTaskQueueAction.enqueue);
  }

  Future<void> afterInvoke({
    required WorkbenchRuntimeTaskQueueResult result,
    required WorkbenchTaskQueueAuthorization authorization,
  }) async {
    if (!result.success) return;
    final value = jsonDecode(result.text);
    candidateCheck(value is Map && value['status'] == 'ok');
    if (value['action'] != 'enqueue') return;
    candidateCheck(accepts(authorization) &&
        authorization.allowedActions
            .contains(WorkbenchTaskQueueAction.enqueue));
    final task = value['task'];
    candidateCheck(task is Map && task['task_id'] is String);
    await _bind(task['task_id'] as String);
  }

  Future<void> _bind(String taskId) {
    candidateCheck(p6R7CandidateUuid.hasMatch(taskId) && taskId.length == 36);
    candidateCheck(_taskId == null || _taskId == taskId);
    _taskId = taskId;
    return _binding ??= _persistAndRegister(taskId);
  }

  Future<void> _persistAndRegister(String taskId) async {
    await _persist(taskId);
    final goal = await _readGoal(taskId);
    candidateCheck(goal == p6R7CandidateGoal);
    await _register(taskId, goal);
  }
}

void p6R7ValidateProductTaskRegistration(
  Object? value, {
  required String taskId,
  required String scopeHash,
  required String goal,
}) {
  const keys = {'schema', 'task_id', 'scope_hash', 'goal_sha256'};
  candidateCheck(value is Map &&
      value.length == keys.length &&
      value.keys.every(keys.contains));
  final row = value as Map;
  candidateCheck(row['schema'] == 'p6_r7_product_task_bound_v1' &&
      row['task_id'] == taskId &&
      row['scope_hash'] == scopeHash &&
      row['goal_sha256'] == sha256.convert(utf8.encode(goal)).toString());
}
