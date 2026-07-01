import 'package:dart_agent_core/dart_agent_core.dart';

/// Lightweight in-memory state for the continuous-reply feature.
///
/// The companion agent calls [request] during a tool-call turn. After the chat
/// turn completes, the UI reads (and consumes) the pending count via
/// [consumePending]. If a non-null count is returned, the UI enters batch mode
/// and drives consecutive AI replies until the counter reaches zero or the user
/// interrupts.
class ContinuousModeState {
  static final ContinuousModeState _instance = ContinuousModeState._();
  static ContinuousModeState get instance => _instance;
  ContinuousModeState._();

  int? _pendingCount;

  /// Called by the `request_continuous_replies` tool executable.
  void request(int count) {
    _pendingCount = count;
  }

  /// Returns the requested count and clears the pending state so the same
  /// request is not consumed twice.
  int? consumePending() {
    final count = _pendingCount;
    _pendingCount = null;
    return count;
  }

  /// Cancel a pending continuous-mode request (e.g. user interrupted).
  void cancel() {
    _pendingCount = null;
  }
}

/// Returns a [Tool] that the companion agent can call when the user explicitly
/// asks for continuous narration / consecutive messages.
///
/// Example user requests the agent should recognise:
/// - "发30条" / "发20条"
/// - "一直发消息"
/// - "连续发消息不要停"
/// - "keep talking without me"
/// - "你自己继续写"
Tool buildContinuousReplyTool() {
  return Tool(
    name: 'request_continuous_replies',
    description: '''Request the system to enter continuous-reply mode.

Call this tool when the user EXPLICITLY asks you to send multiple consecutive
messages without waiting for their input. Examples:
- "从现在开始一直发消息" / "发30条" / "发20条" / "连续发不要停"
- "keep talking without me" / "continue the scene yourself"

Extract the count from the user's request (e.g. "发30条" → 30). If the user
did not specify a number, default to 30.

Do NOT call this tool during normal conversation. Only call it when the user
unambiguously wants you to keep generating messages on your own.''',
    parameters: {
      'type': 'object',
      'properties': {
        'count': {
          'type': 'integer',
          'description':
              'Number of consecutive replies to generate. Default 30 if the '
              'user did not specify a number.',
        },
      },
      'required': ['count'],
    },
    executable: (int count) async {
      // ignore: avoid_print
      print('[continuous_reply] AI requested $count consecutive replies');
      ContinuousModeState.instance.request(count);
      return 'Continuous reply mode activated for $count messages. '
          'The system will now drive consecutive turns.';
    },
  );
}
