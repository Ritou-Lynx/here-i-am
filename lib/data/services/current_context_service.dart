/// Tracks the most-recently opened item that the floating ball should be
/// aware of.
///
/// Screens call [push] in initState and [pop] (with their own id) in dispose.
/// The floating ball reads [current] when the quick-chat sheet opens so it can
/// show a context label and inject a hint into the companion message.
///
/// This is intentionally in-memory and single-slot — only the top-most detail
/// screen's context is relevant. If nested screens exist, the innermost one
/// wins because it pushes last and pops first (LIFO).
library;

/// What kind of item is currently open.
enum CurrentContextType {
  memoryCard,
  topicThread,
}

/// A single context slot describing what the user is looking at.
class CurrentPageContext {
  final CurrentContextType type;
  final String id;
  final String title;

  const CurrentPageContext({
    required this.type,
    required this.id,
    required this.title,
  });

  /// Short label shown in the floating-ball chat sheet header.
  String get label => switch (type) {
        CurrentContextType.memoryCard => '记忆卡片·$title',
        CurrentContextType.topicThread => '话题线索·$title',
      };

  /// Context hint prepended to the user's message so the companion knows
  /// what is currently on screen without the user having to spell it out.
  String get messageHint => switch (type) {
        CurrentContextType.memoryCard => '【正在查看记忆卡片「$title」】',
        CurrentContextType.topicThread => '【正在查看话题线索「$title」】',
      };
}

class CurrentContextService {
  CurrentContextService._();

  static CurrentPageContext? _current;

  /// Register [context] as the currently visible detail item.
  ///
  /// Call from a detail screen's [State.initState].
  static void push(CurrentPageContext context) {
    _current = context;
  }

  /// Clear the context registered by [id].
  ///
  /// Call from [State.dispose]. Only clears if the id still matches —
  /// prevents a screen below a stack from accidentally wiping a newer context.
  static void pop(String id) {
    if (_current?.id == id) _current = null;
  }

  /// The currently visible item, or null if no detail screen is open.
  static CurrentPageContext? get current => _current;
}
