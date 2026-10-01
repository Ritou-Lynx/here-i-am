import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

/// The small, candidate-only host for one public queue task.
///
/// It deliberately retains only an exact persisted task id. It never discovers
/// a latest task and recovery only reads that exact id; resuming work remains a
/// separate, explicit button press.
class P6R7CandidateViewModel extends ChangeNotifier {
  P6R7CandidateViewModel({
    required this.tool,
    required this.service,
    required this.lifecycleOwner,
    required this.conversationId,
    required this.initialTaskId,
    required this.persistTaskId,
  }) : _exactTaskId = initialTaskId {
    enqueue = Command0<void>(_enqueue);
    start = Command0<void>(() => _invoke(WorkbenchTaskQueueAction.start));
    refresh = Command0<void>(() => _invoke(WorkbenchTaskQueueAction.status));
    pause = Command0<void>(() => _invoke(WorkbenchTaskQueueAction.pause));
    resume = Command0<void>(() => _invoke(WorkbenchTaskQueueAction.resume));
    cancel = Command0<void>(() => _invoke(WorkbenchTaskQueueAction.cancel));
    retry = Command0<void>(() => _invoke(WorkbenchTaskQueueAction.retry));
    _commands = [enqueue, start, refresh, pause, resume, cancel, retry];
    for (final command in _commands) {
      command.addListener(_onCommandChanged);
    }
  }

  static const title = '公开文字验收';
  static const goal = '只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。';

  final WorkbenchRuntimeTaskQueueTool tool;
  final TaskRoomService service;
  final WorkbenchTaskQueueLifecycleOwner lifecycleOwner;
  final String conversationId;
  final String? initialTaskId;
  final Future<void> Function(String) persistTaskId;

  late final Command0<void> enqueue;
  late final Command0<void> start;
  late final Command0<void> refresh;
  late final Command0<void> pause;
  late final Command0<void> resume;
  late final Command0<void> cancel;
  late final Command0<void> retry;
  late final List<Command0<void>> _commands;

  String? _exactTaskId;
  TaskQueueSnapshot? _snapshot;
  String? _errorMessage;
  int _requestSequence = 0;
  Timer? _statusObservation;
  bool _inflight = false;
  bool _persistencePending = false;
  bool _resumePartialBlocked = false;
  bool _disposed = false;
  bool _requestsStopped = false;
  Completer<void>? _quiescence;

  String? get taskId => _exactTaskId;
  TaskQueueSnapshot? get snapshot => _snapshot;
  String? get errorMessage =>
      _resumePartialBlocked ? _partialResumeMessage : _errorMessage;
  bool get hasTask => _exactTaskId != null;
  bool get isBusy =>
      enqueue.running ||
      start.running ||
      refresh.running ||
      pause.running ||
      resume.running ||
      cancel.running ||
      retry.running;

  void _onCommandChanged() {
    _notify();
    _completeQuiescence();
    if (_disposed && !isBusy) _removeCommandListeners();
  }

  /// Fence synchronously, then wait through marker persistence, error refresh,
  /// and Command completion. Never waits for a whole execution/monitor here.
  Future<void> quiesceForExit() {
    _requestsStopped = true;
    stopStatusObservation();
    final completion = _quiescence ??= Completer<void>();
    _completeQuiescence();
    return completion.future;
  }

  void _completeQuiescence() {
    final completion = _quiescence;
    if (completion != null &&
        !completion.isCompleted &&
        !_inflight &&
        !isBusy) {
      completion.complete();
    }
  }

  Future<Result<void>> _enqueue() async {
    if (_exactTaskId != null) {
      return Error<void>(StateError('已固定验收任务，不能再创建。'));
    }
    return _call(
      WorkbenchTaskQueueAction.enqueue,
      <String, dynamic>{'title': title, 'goal': goal},
    );
  }

  Future<Result<void>> _invoke(WorkbenchTaskQueueAction action) async {
    if (_exactTaskId == null) {
      return Error<void>(StateError('请先创建验收任务。'));
    }
    if (_persistencePending &&
        action != WorkbenchTaskQueueAction.status &&
        action != WorkbenchTaskQueueAction.cancel) {
      return Error<void>(StateError('任务标识尚未安全登记。'));
    }
    return _call(action, <String, dynamic>{'task_id': _exactTaskId});
  }

  Future<Result<void>> _call(
    WorkbenchTaskQueueAction action,
    Map<String, dynamic> payload,
  ) async {
    if (_disposed || _requestsStopped || _inflight) {
      return Error<void>(StateError('当前无法执行操作。'));
    }
    _inflight = true;
    _errorMessage = null;
    _notify();
    try {
      if (action == WorkbenchTaskQueueAction.resume &&
          await _hasSavedPartialResult()) {
        _resumePartialBlocked = true;
        _notify();
        return Error<void>(StateError(_partialResumeMessage));
      }
      final authorization = WorkbenchTaskQueueAuthorization(
        profileId: DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
        conversationId: conversationId,
        allowedActions: {action},
        targetTaskId:
            action == WorkbenchTaskQueueAction.enqueue ? null : _exactTaskId,
      );
      final result = await tool.invoke(
        <String, dynamic>{
          'request_id': _nextRequestId(action),
          'action': action.wireName,
          ...payload,
        },
        authorization: authorization,
      );
      final decoded = jsonDecode(result.text);
      if (!result.success || decoded is! Map<String, dynamic>) {
        throw StateError(_errorFrom(decoded));
      }
      final rawTask = decoded['task'];
      if (rawTask is! Map) throw const FormatException('缺少任务状态');
      final returnedId = _requiredId(rawTask);
      if (action != WorkbenchTaskQueueAction.enqueue &&
          returnedId != _exactTaskId) {
        throw StateError('任务状态无法读取');
      }
      final next = await service.getTaskQueueSnapshot(returnedId);
      if (next == null || !next.belongsTo(_scope)) {
        throw StateError('任务状态无法读取');
      }
      if (action == WorkbenchTaskQueueAction.enqueue) {
        if (next.title != title) throw StateError('任务状态无法读取');
        _exactTaskId = next.id;
        _persistencePending = true;
        await persistTaskId(next.id);
        _persistencePending = false;
      }
      _snapshot = next;
      _resumePartialBlocked = next.status == TaskStatus.blocked &&
          (next.resultPreview?.trim().isNotEmpty ?? false);
      _notify();
      return const Ok.v();
    } catch (error, stackTrace) {
      await _refreshExactSnapshot();
      _errorMessage = '操作未能完成，请读取状态后再决定。';
      _notify();
      return Error<void>(error, stackTrace);
    } finally {
      _inflight = false;
      _notify();
      _completeQuiescence();
    }
  }

  String _nextRequestId(WorkbenchTaskQueueAction action) =>
      'p6-r7-${action.wireName}-${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';

  String _requiredId(Map rawTask) {
    final id = rawTask['task_id'];
    if (id is! String || id.isEmpty) throw const FormatException('任务标识无效');
    return id;
  }

  String _errorFrom(Object? decoded) {
    if (decoded is Map && decoded['error_code'] is String) {
      return '操作未能完成';
    }
    return '请求未完成';
  }

  Future<bool> _hasSavedPartialResult() async {
    final id = _exactTaskId;
    if (id == null) return false;
    final snapshot = await service.getTaskQueueSnapshot(id);
    if (snapshot == null || !snapshot.belongsTo(_scope)) return true;
    final room = await service.getTaskRoom(id);
    if (room == null) return true;
    try {
      final context = jsonDecode(room.contextJson);
      if (context is! Map) return true;
      final queue = context['__queue'];
      if (queue is! Map) return false;
      final execution = queue['execution'];
      if (execution is! Map) return false;
      final resultText = execution['resultText'];
      return resultText is! String || resultText.trim().isNotEmpty;
    } on FormatException {
      return true;
    }
  }

  static const _partialResumeMessage = '本轮验收只支持尚未生成文字的任务继续；已有文字请显式重试。';

  /// Recovery is read-only and never starts, resumes, or retries a task.
  Future<void> restoreExactTask() {
    if (_exactTaskId == null) return Future.value();
    return refresh.execute();
  }

  /// Starts read-only polling for a live candidate task. It never dispatches
  /// start, resume, or retry, and it is stopped by the root UI's dispose.
  void startStatusObservation(
      {Duration interval = const Duration(seconds: 5)}) {
    if (_disposed || _requestsStopped) return;
    _statusObservation ??= Timer.periodic(interval, (_) {
      if (_exactTaskId != null && !_inflight && !refresh.running) {
        unawaited(refresh.execute());
      }
    });
  }

  void stopStatusObservation() {
    _statusObservation?.cancel();
    _statusObservation = null;
  }

  Future<void> _refreshExactSnapshot() async {
    final id = _exactTaskId;
    if (id == null) return;
    try {
      final snapshot = await service.getTaskQueueSnapshot(id);
      if (snapshot != null && snapshot.belongsTo(_scope)) {
        _snapshot = snapshot;
      }
    } on Object {
      // The displayed candidate state remains unknown rather than exposing an
      // implementation error or treating a failed read as a state transition.
    }
  }

  TaskQueueHostScope get _scope => TaskQueueHostScope(
        profileId: DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
        scopeType: 'conversation',
        scopeId: conversationId,
      );

  @override
  void dispose() {
    _disposed = true;
    _requestsStopped = true;
    stopStatusObservation();
    // Commands notify once more after their pending work settles. Retain this
    // guarded listener until then so an exit join cannot be stranded by dispose.
    if (!isBusy) _removeCommandListeners();
    _completeQuiescence();
    super.dispose();
  }

  void _removeCommandListeners() {
    for (final command in _commands) {
      command.removeListener(_onCommandChanged);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String get statusLabel {
    final state = _snapshot?.status;
    return switch (state) {
      TaskStatus.pending => '等待开始',
      TaskStatus.running => '运行中',
      TaskStatus.blocked => '已中断或受阻',
      TaskStatus.waitingForUser => '等待处理',
      TaskStatus.completed => '已完成',
      TaskStatus.failed => '失败',
      TaskStatus.cancelled => '已取消',
      TaskStatus.archived => '已归档',
      null => '尚未读取',
    };
  }
}
