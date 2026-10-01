library;

import 'package:memex/data/memory_v3/services/task_room_service.dart';

class WorkbenchTaskQueueExecutionException implements Exception {
  const WorkbenchTaskQueueExecutionException(this.code);
  final String code;
}

/// The tool host authorizes the exact user-selected task before invoking this
/// port. Implementations must control a real executor, not just queue metadata.
/// The bool reports whether THIS request changed execution state. A persisted
/// request replay is false regardless of concurrent provider progress.
abstract interface class WorkbenchTaskQueueExecutionController {
  Future<bool> start(
      {required String id,
      required TaskQueueHostScope scope,
      required String requestId});
  Future<bool> resume(
      {required String id,
      required TaskQueueHostScope scope,
      required String requestId});
  Future<bool> retry(
      {required String id,
      required TaskQueueHostScope scope,
      required String requestId});
  Future<bool> pause(
      {required String id,
      required TaskQueueHostScope scope,
      required String requestId});
  Future<bool> cancel(
      {required String id,
      required TaskQueueHostScope scope,
      required String requestId});
}
