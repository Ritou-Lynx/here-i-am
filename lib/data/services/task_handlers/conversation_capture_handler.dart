import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('ConversationCaptureHandler');

/// No-op handler for legacy `conversation_capture_task` payloads.
///
/// Auto-capture has been removed in favor of explicit User-truth writes
/// through the Memory V3 Record Organizer. We keep this handler registered so
/// historical tasks still sitting in the queue from older builds drain
/// instead of looping on "no handler" errors.
Future<void> handleConversationCapture(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  _logger.info(
    'Dropping legacy conversation_capture_task (auto-capture retired): '
    'characterId=${payload['character_id']}',
  );
}

/// No-op failure handler for the same reason as above.
Future<void> handleConversationCaptureFailure(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
  Object error,
  StackTrace? stackTrace,
) async {
  _logger.warning(
    'Legacy conversation_capture_task failed and is now retired; ignoring',
    error,
    stackTrace,
  );
}
