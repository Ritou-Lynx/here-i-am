library;

import 'dart:convert';

import 'package:memex/data/memory_v3/services/task_room_service.dart';

import '../workbench_runtime_client.dart';
import 'ollama_text_task_gateway.dart';
import 'workbench_task_queue_execution.dart';
import 'workbench_task_queue_execution_controller.dart';
import 'workbench_task_queue_lifecycle_owner.dart';
import 'workbench_task_queue_tool_host.dart';

typedef TaskRoomServiceLoader = Future<TaskRoomService> Function();
typedef WorkbenchTaskQueueExecutionLoader
    = Future<WorkbenchTaskQueueExecutionController> Function(
        TaskRoomService service);

class WorkbenchRuntimeTaskQueueResult {
  const WorkbenchRuntimeTaskQueueResult({
    required this.success,
    required this.text,
  });

  final bool success;
  final String text;
}

/// Provider-neutral binding from Runtime dynamic-tool transport to the
/// product-owned TaskRoom queue host.
class WorkbenchRuntimeTaskQueueTool {
  const WorkbenchRuntimeTaskQueueTool({
    required TaskRoomServiceLoader loadService,
    WorkbenchTaskQueueExecutionLoader? loadExecutionController,
    DesktopWorkbenchTaskQueueAuthorizationFactory authorizationFactory =
        const DesktopWorkbenchTaskQueueAuthorizationFactory(),
  })  : _loadService = loadService,
        _loadExecutionController = loadExecutionController,
        _authorizationFactory = authorizationFactory;

  /// Without an explicit [runtime], long tasks run on the Ollama model named
  /// by `HIA_TASK_OLLAMA_MODEL`, or stay fail-closed when none is configured.
  factory WorkbenchRuntimeTaskQueueTool.production({
    WorkbenchTextTaskBackend? runtime,
    WorkbenchTaskQueueLifecycleOwner? lifecycleOwner,
  }) =>
      WorkbenchRuntimeTaskQueueTool(
        loadService: () async => TaskRoomService.instance,
        loadExecutionController: (service) =>
            _productionExecution(
              service,
              runtime: runtime,
              lifecycleOwner: lifecycleOwner ?? WorkbenchTaskQueueLifecycleOwner.instance,
            ),
      );

  // One owner per initialized service, not one owner per dynamic tool call.
  // Expando does not keep a disposed test/database service alive.
  static final _executions = Expando<WorkbenchTaskQueueExecution>();

  static Future<WorkbenchTaskQueueExecutionController> _productionExecution(
    TaskRoomService service, {
    WorkbenchTextTaskBackend? runtime,
    required WorkbenchTaskQueueLifecycleOwner lifecycleOwner,
  }) async {
    final existing = _executions[service];
    if (existing != null) {
      lifecycleOwner.register(existing);
      return existing;
    }
    final textRuntime = runtime ?? defaultWorkbenchTextTaskBackend();
    final execution = WorkbenchTaskQueueExecution(
        service: service,
        runtime: textRuntime,
        ensureAvailable: textRuntime.ensureAvailable,
        startTextSession: (manifest) =>
            textRuntime.startTextTaskSession(contextManifest: manifest));
    _executions[service] = execution;
    lifecycleOwner.register(execution);
    return execution;
  }

  final TaskRoomServiceLoader _loadService;
  final WorkbenchTaskQueueExecutionLoader? _loadExecutionController;
  final DesktopWorkbenchTaskQueueAuthorizationFactory _authorizationFactory;

  Map<String, dynamic> get dynamicToolDefinition =>
      WorkbenchTaskQueueToolHost.dynamicToolDefinition;

  WorkbenchTaskQueueAuthorization authorizationForTurn({
    required String conversationId,
    required String userText,
  }) =>
      _authorizationFactory.build(
        conversationId: conversationId,
        userText: userText,
      );

  Future<WorkbenchRuntimeTaskQueueResult> invoke(
    Object? arguments, {
    required WorkbenchTaskQueueAuthorization authorization,
  }) async {
    try {
      if (arguments is! Map) return _invalidRequest();
      final payload = Map<String, dynamic>.from(arguments);
      final service = await _loadService();
      final execution = await _loadExecutionController?.call(service);
      final output = await WorkbenchTaskQueueToolHost(service,
              executionController: execution)
          .invoke(
        payload,
        authorization: authorization,
      );
      return WorkbenchRuntimeTaskQueueResult(
        success: output['status'] == 'ok',
        text: jsonEncode(output),
      );
    } catch (_) {
      return const WorkbenchRuntimeTaskQueueResult(
        success: false,
        text: '{"status":"failed","error_code":"task_queue_tool_failed"}',
      );
    }
  }

  WorkbenchRuntimeTaskQueueResult _invalidRequest() =>
      const WorkbenchRuntimeTaskQueueResult(
        success: false,
        text:
            '{"status":"invalid_request","error_code":"invalid_task_queue_request"}',
      );
}
