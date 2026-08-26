library;

import 'dart:convert';

import 'package:memex/data/memory_v3/services/task_room_service.dart';

import 'workbench_task_queue_tool_host.dart';

typedef TaskRoomServiceLoader = Future<TaskRoomService> Function();

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
    DesktopWorkbenchTaskQueueAuthorizationFactory authorizationFactory =
        const DesktopWorkbenchTaskQueueAuthorizationFactory(),
  })  : _loadService = loadService,
        _authorizationFactory = authorizationFactory;

  factory WorkbenchRuntimeTaskQueueTool.production() =>
      WorkbenchRuntimeTaskQueueTool(
        loadService: () async => TaskRoomService.instance,
      );

  final TaskRoomServiceLoader _loadService;
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
      final output = await WorkbenchTaskQueueToolHost(service).invoke(
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
