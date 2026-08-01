/// Service for routing a message from the floating ball directly to a
/// companion chat without requiring UI navigation extras.
///
/// The floating ball lives outside the Navigator tree, so it cannot pass
/// constructor args to [PersonaChatScreen]. Instead it calls [queue], then
/// navigates to the home route. [PersonaChatScreen.initState] calls [take]
/// to pick up any pending message and auto-sends it.
library;

/// In-memory, single-slot pending message queue.
/// Thread-safe for Flutter's single-threaded UI isolate.
class QuickChatService {
  QuickChatService._();

  static String? _pendingMessage;
  static String? _pendingCharacterId;

  /// Queue [message] to be sent to [characterId] on the next chat screen open.
  static void queue({required String characterId, required String message}) {
    _pendingMessage = message.trim();
    _pendingCharacterId = characterId;
  }

  /// Take and clear the pending message for [characterId].
  /// Returns null if no message is pending or if it is for a different character.
  static String? take(String characterId) {
    if (_pendingMessage == null) return null;
    if (_pendingCharacterId != characterId) return null;
    final msg = _pendingMessage!;
    _pendingMessage = null;
    _pendingCharacterId = null;
    return msg;
  }

  /// Whether any message is pending (any character).
  static bool get hasPending => _pendingMessage != null;
}
