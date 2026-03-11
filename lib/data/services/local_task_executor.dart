import 'dart:async';
import 'package:meta/meta.dart';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/domain/models/task_exceptions.dart';

/// Context for task execution
class TaskContext {
  final String taskId;
  final String taskType;
  final String? bizId;

  TaskContext({
    required this.taskId,
    required this.taskType,
    this.bizId,
  });
}

/// Handler function type
typedef TaskHandler = Future<void> Function(
    String userId, Map<String, dynamic> payload, TaskContext context);

/// Failure handler function type - called when all retries are exhausted
typedef TaskFailureHandler = Future<void> Function(
    String userId,
    Map<String, dynamic> payload,
    TaskContext context,
    Object error,
    StackTrace? stackTrace);

class LocalTaskExecutor {
  static LocalTaskExecutor? _instance;
  static LocalTaskExecutor get instance {
    _instance ??= LocalTaskExecutor._();
    return _instance!;
  }

  LocalTaskExecutor._();

  @visibleForTesting
  LocalTaskExecutor.forTesting();

  final Logger _logger = getLogger('LocalTaskExecutor');
  // Dynamic getter to ensure we always use the current active DB instance (handling user switches)
  AppDatabase get _db => AppDatabase.instance;
  String? _currentUserId; // Track current user ID for worker context
  String? get currentUserId => _currentUserId;

  // Handlers registry
  final Map<String, TaskHandler> _handlers = {};

  // Failure handlers registry
  final Map<String, TaskFailureHandler> _failureHandlers = {};

  // Worker state
  bool _isRunning = false;
  Timer? _pollTimer;
  bool _isProcessing = false;

  // Polling interval
  static const Duration _pollInterval = Duration(seconds: 1);

  /// Stream that emits true if there are any active (pending, processing, retrying) tasks in the DB.
  /// Useful for global UI loading indicators.
  Stream<bool> get hasActiveTasksStream {
    final query = _db.select(_db.tasks)
      ..where((t) => t.status.isIn(['pending', 'processing', 'retrying']));
    return query.watch().map((tasks) => tasks.isNotEmpty).distinct();
  }

  void registerHandler(String taskType, TaskHandler handler) {
    _handlers[taskType] = handler;
  }

  /// Register a failure handler for a task type
  /// This handler will be called when all retries are exhausted and the task is permanently failed
  void registerFailureHandler(String taskType, TaskFailureHandler handler) {
    _failureHandlers[taskType] = handler;
  }

  /// Start the worker loop
  Future<void> start({String? userId}) async {
    if (_isRunning) return;
    _currentUserId = userId; // Store for use in worker loop

    // Reset any stale 'processing' tasks that might have been left over from a crash
    await _resetStaleTasks();

    _isRunning = true;
    _logger.info('LocalTaskExecutor started for user $_currentUserId');
    _scheduleNextPoll();
  }

  /// Reset tasks that are stuck in 'processing' state to 'pending'
  Future<void> _resetStaleTasks() async {
    try {
      final count = await (_db.update(_db.tasks)
            ..where((t) => t.status.equals('processing')))
          .write(TasksCompanion(
        status: const Value('pending'),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ));

      if (count > 0) {
        _logger.info('Reset $count stale processing tasks to pending');
      }
    } catch (e) {
      _logger.severe('Failed to reset stale tasks: $e');
    }
  }

  /// Stop the worker loop
  void stop() {
    _isRunning = false;
    _pollTimer?.cancel();
    _logger.info('LocalTaskExecutor stopped');
  }

  // Max concurrent tasks
  static const int _maxConcurrency = 5;

  /// Enqueue a new task
  Future<String> enqueueTask({
    required String userId,
    required String taskType,
    required Map<String, dynamic> payload,
    int priority = 0,
    int? scheduledAt,
    int maxRetries = 10,
    String? bizId,
    List<String>? dependencies,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // We use a manual UUID or let Drift handle it?
    // Our schema defined ID as Text. Drift doesn't auto-generate Text IDs usually.
    // So we generate one.
    final taskId =
        DateTime.now().microsecondsSinceEpoch.toString(); // Simple ID for now

    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: taskId,
          type: taskType,
          payload: Value(jsonEncode(payload)),
          status: 'pending',
          priority: Value(priority),
          createdAt: Value(now),
          scheduledAt: Value(scheduledAt),
          maxRetries: Value(maxRetries),
          bizId: Value(bizId),
          dependencies: Value(dependencies != null && dependencies.isNotEmpty
              ? jsonEncode(dependencies)
              : null),
        ));

    _logger.info('Enqueued task $taskId ($taskType)');

    // Trigger immediate poll if running
    if (_isRunning) {
      _scheduleNextPoll(immediate: true);
    }

    return taskId;
  }

  void _scheduleNextPoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!_isRunning) return;

    if (immediate) {
      _pollTimer = Timer(Duration.zero, _workerLoop);
    } else {
      _pollTimer = Timer(_pollInterval, _workerLoop);
    }
  }

  Future<void> _workerLoop() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // 1. Check current active tasks count
      final activeCountQuery = _db.select(_db.tasks)
        ..where((t) => t.status.isIn(['processing']));
      final activeTasks = await activeCountQuery.get();

      if (activeTasks.length >= _maxConcurrency) {
        _isProcessing = false;
        _scheduleNextPoll(); // Wait for next slot
        return;
      }

      final slotsAvailable = _maxConcurrency - activeTasks.length;

      // 2. Fetch candidate tasks
      // We look for pending or retrying tasks where scheduledAt <= now (or null)
      // Limit to 20 to check dependencies efficiently
      final query = _db.select(_db.tasks)
        ..where((t) => t.status.isIn(['pending', 'retrying']))
        ..where((t) =>
            t.scheduledAt.isNull() | t.scheduledAt.isSmallerOrEqualValue(now))
        ..orderBy([
          (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.rowId, mode: OrderingMode.asc),
        ])
        ..limit(20);

      final candidates = await query.get();

      if (candidates.isEmpty) {
        _isProcessing = false;
        _scheduleNextPoll();
        return;
      }

      var tasksToRun = <Task>[];

      for (final task in candidates) {
        if (tasksToRun.length >= slotsAvailable) break;

        // Check dependencies
        bool dependenciesMet = true;
        if (task.dependencies != null) {
          try {
            final deps =
                (jsonDecode(task.dependencies!) as List).cast<String>();
            if (deps.isNotEmpty) {
              // Check if any dependency is NOT completed or failed
              final pendingDepsQuery = _db.selectOnly(_db.tasks)
                ..addColumns([_db.tasks.id.count()])
                ..where(_db.tasks.id.isIn(deps))
                ..where(_db.tasks.status.isNotIn(['completed', 'failed']));

              final pendingCount = await pendingDepsQuery.getSingle();
              if ((pendingCount.read(_db.tasks.id.count()) ?? 0) > 0) {
                dependenciesMet = false;
              }
            }
          } catch (e) {
            _logger.warning(
                'Failed to parse dependencies for task ${task.id}: $e');
            // If parsing fails, assume dependencies met or fail? Safe to skip.
            dependenciesMet = false;
          }
        }

        if (dependenciesMet) {
          tasksToRun.add(task);
        }
      }

      if (tasksToRun.isEmpty) {
        // No runnable tasks found in top candidates
        _isProcessing = false;
        _scheduleNextPoll();
        return;
      }

      // 3. Mark and Execute
      for (final task in tasksToRun) {
        // Fire and forget execution - don't await
        _executeTask(task);
      }

      // Loop immediately to check for more tasks or completion
      _isProcessing = false;

      // If we filled all slots, wait. If we didn't, maybe check again soon.
      // Easiest is to just schedule next poll.
      _scheduleNextPoll(immediate: true);
    } catch (e) {
      _logger.severe('Error in worker loop, $e', e);
      _isProcessing = false;
      _scheduleNextPoll();
    }
  }

  Future<void> _executeTask(Task task) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Mark as processing
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          status: const Value('processing'),
          updatedAt: Value(now),
        ),
      );

      final handler = _handlers[task.type];
      if (handler == null) {
        throw Exception('No handler registered for task type: ${task.type}');
      }

      final payloadMap = task.payload != null
          ? jsonDecode(task.payload!) as Map<String, dynamic>
          : <String, dynamic>{};

      final currentUserId = _currentUserId;
      if (currentUserId == null) {
        _logger.severe(
            'Task execution failed: No active user ID in LocalTaskExecutor');
        // Should we fail the task? Yes, otherwise it hangs in processing if we don't update status.
        // Or just return and let it stay processing until restart?
        // Better to retry later.
        return;
      }

      await handler(
        currentUserId,
        payloadMap,
        TaskContext(
          taskId: task.id,
          taskType: task.type,
          bizId: task.bizId,
        ),
      );

      // Success
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          status: const Value('completed'),
          completedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ),
      );

      _logger.info('Task ${task.id} completed');
    } catch (e, stack) {
      _logger.severe('Task ${task.id} failed', e, stack);

      // Retry Logic
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final nextRetry = task.retryCount + 1;

      if (e is! NonRetryableTaskException && nextRetry <= task.maxRetries) {
        // Exponential backoff
        final backoff = 30; //* (1 << (task.retryCount));
        final nextRun = now + backoff;

        await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
          TasksCompanion(
            status: const Value('retrying'),
            retryCount: Value(nextRetry),
            updatedAt: Value(now),
            // For simple polling, we don't strictly update scheduledAt for retries currently in query logic
            // but we should if we want valid backoff.
            // Existing query handles scheduledAt logic, so updating it works.
            scheduledAt: Value(nextRun),
            error: Value(e.toString()),
          ),
        );
        _logger.info('Task ${task.id} scheduled for retry at $nextRun');
      } else {
        // Permanently failed
        final failureHandler = _failureHandlers[task.type];
        if (failureHandler != null) {
          try {
            final payloadMap = task.payload != null
                ? jsonDecode(task.payload!) as Map<String, dynamic>
                : <String, dynamic>{};
            final currentUserId = _currentUserId;
            if (currentUserId != null) {
              await failureHandler(
                currentUserId,
                payloadMap,
                TaskContext(
                  taskId: task.id,
                  taskType: task.type,
                  bizId: task.bizId,
                ),
                e,
                stack,
              );
            }
          } catch (fhError, fhStack) {
            _logger.severe('Failure handler error', fhError, fhStack);
          }
        }

        await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
          TasksCompanion(
            status: const Value('failed'),
            completedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            updatedAt: Value(now),
            error: Value(e.toString()),
          ),
        );
        _logger.severe('Task ${task.id} permanently failed');
      }
    } finally {
      // Trigger poll to pick up next tasks immediately upon completion of one
      if (_isRunning) {
        _scheduleNextPoll(immediate: true);
      }
    }
  }

  /// Update task result (called by handlers)
  Future<void> updateTaskResult(String taskId, String result) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        result: Value(result),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }

  /// Create a completed task record with the given result directly.
  /// Useful for mocking task results that were not produced by an actual task execution.
  Future<void> saveTaskResult({
    required String userId,
    required String taskType,
    required String bizId,
    required Map<String, dynamic> result,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final taskId = DateTime.now().microsecondsSinceEpoch.toString();
    final resultStr = jsonEncode(result);

    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: taskId,
          type: taskType,
          payload: const Value("{}"),
          status: 'completed',
          priority: const Value(0),
          createdAt: Value(now),
          completedAt: Value(now),
          updatedAt: Value(now),
          maxRetries: const Value(1),
          bizId: Value(bizId),
          result: Value(resultStr),
        ));
  }

  /// Get task result by taskId (for resumption)
  Future<Map<String, dynamic>?> getTaskResult(String taskId) async {
    final query = _db.select(_db.tasks)..where((t) => t.id.equals(taskId));
    final task = await query.getSingleOrNull();

    if (task != null && task.result != null) {
      try {
        return jsonDecode(task.result!) as Map<String, dynamic>;
      } catch (e) {
        _logger.warning('Failed to parse task result for task ${task.id}: $e');
      }
    }
    return null;
  }

  /// Get task result by bizId
  Future<Map<String, dynamic>?> getTaskResultByBizId(
      String userId, String taskType, String bizId) async {
    final query = _db.select(_db.tasks)
      ..where((t) => t.type.equals(taskType))
      ..where((t) => t.bizId.equals(bizId))
      ..where((t) => t.status.equals('completed'))
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc)
      ])
      ..limit(1);

    final task = await query.getSingleOrNull();
    if (task != null && task.result != null) {
      try {
        return jsonDecode(task.result!) as Map<String, dynamic>;
      } catch (e) {
        _logger.warning('Failed to parse task result for task ${task.id}: $e');
      }
    }
    return null;
  }

  /// Get tasks with pagination
  Future<List<Task>> getTasks({int limit = 10, int offset = 0}) async {
    final query = _db.select(_db.tasks)
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);

    return await query.get();
  }

  /// Get the last task by type
  /// This is useful for restoring sequential dependency chains after app restart
  Future<String?> getLastTaskByType(String taskType) async {
    final query = _db.selectOnly(_db.tasks)
      ..addColumns([_db.tasks.id])
      ..where(_db.tasks.type.equals(taskType))
      ..orderBy([
        OrderingTerm(expression: _db.tasks.createdAt, mode: OrderingMode.desc)
      ])
      ..limit(1);

    final result = await query.getSingleOrNull();
    return result?.read(_db.tasks.id);
  }
}
