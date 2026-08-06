import 'package:dart_agent_core/dart_agent_core.dart';

/// In-memory state for the continuous-reply feature.
///
/// Lifecycle:
/// 1. The companion agent calls `request_continuous_replies` during a tool-call
///    turn, which lands in [request].
/// 2. After that chat turn completes, the UI calls [consumePending]. A non-null
///    result starts a run via [startRun].
/// 3. While [isActive], the UI drives one synthetic turn per [tick] until the
///    counter drains, the user cancels, or the character changes.
///
/// Runs are scoped to a character id so switching chats cannot inherit another
/// character's run. State is deliberately in-memory: an app restart abandons a
/// run rather than resurrecting one the user has forgotten about.
class ContinuousModeState {
  static final ContinuousModeState _instance = ContinuousModeState._();
  static ContinuousModeState get instance => _instance;
  ContinuousModeState._();

  /// Upper bound on a single run. The model is told to default to 30; this caps
  /// what an over-eager (or malformed) tool call can start, since each turn is
  /// a full LLM call plus TTS synthesis.
  static const int maxRunLength = 60;

  /// Pause between consecutive synthetic turns. In voice mode TTS playback
  /// already paces the loop; this keeps text mode from slamming.
  static const Duration interTurnDelay = Duration(milliseconds: 1200);

  int? _pendingCount;
  String? _activeCharacterId;
  int _remaining = 0;

  /// Called by the `request_continuous_replies` tool executable.
  void request(int count) {
    _pendingCount = count.clamp(1, maxRunLength);
  }

  /// Returns the requested count and clears the pending state so the same
  /// request is not consumed twice. Returns null when nothing is pending.
  int? consumePending() {
    final count = _pendingCount;
    _pendingCount = null;
    return count;
  }

  /// Begin a run of [count] turns for [characterId].
  void startRun({required String characterId, required int count}) {
    _activeCharacterId = characterId;
    _remaining = count.clamp(1, maxRunLength);
  }

  bool get isActive => _activeCharacterId != null && _remaining > 0;

  String? get activeCharacterId => _activeCharacterId;

  int get remaining => _remaining;

  /// Whether a run is active for [characterId] specifically.
  bool isActiveFor(String characterId) =>
      isActive && _activeCharacterId == characterId;

  /// Consume one turn of the active run. Returns true when the caller should
  /// drive another turn, false when the run is finished (and clears it).
  ///
  /// Checks the budget *before* decrementing so every `true` maps to exactly
  /// one scheduled turn: with count=2 the caller schedules two turns and the
  /// third tick (after both completed) returns false.
  bool tick(String characterId) {
    if (!isActiveFor(characterId)) {
      return false;
    }
    if (_remaining <= 0) {
      _clearRun();
      return false;
    }
    _remaining -= 1;
    return true;
  }

  /// Stop the active run while keeping a pending request intact. Used when a
  /// real user turn takes over mid-run (the request may belong to a fresh
  /// "keep talking" ask that arrives after this run is stopped).
  void stopRun() => _clearRun();

  /// Cancel any pending request and any active run (user interrupted, send
  /// canceled, character switched, screen disposed).
  void cancel() {
    _pendingCount = null;
    _clearRun();
  }

  void _clearRun() {
    _activeCharacterId = null;
    _remaining = 0;
  }
}

/// Sentinel sent as the synthetic user turn that advances a continuous run.
///
/// The companion agent's continuous-mode reminder tells the model to treat this
/// as "advance the scene" rather than as something to acknowledge.
const String kContinuousAdvanceSentinel = '[继续叙述]';

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
did not specify a number, default to 30. Counts above
${ContinuousModeState.maxRunLength} are clamped.

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
      ContinuousModeState.instance.request(count);
      final clamped = count.clamp(1, ContinuousModeState.maxRunLength);
      return 'Continuous reply mode requested for $clamped messages. '
          'Reply once now; the system drives the remaining turns.';
    },
  );
}
