/// Shared detection of explicit "record this" requests from the user.
///
/// This is the single source of truth for the User-truth write contract:
/// ordinary chat must never produce a Memory Card. It is used in two places
/// that must agree:
///
/// 1. [CompanionAgent] — to inject the record directive when the user *did*
///    ask, so the model actually calls the tool instead of only saying "记上了".
/// 2. `LifeMemoryCapture` tool executable — as a hard gate that rejects the
///    call when the user did *not* ask, so a model that ignores the prompt
///    constraint still cannot write User-truth.
///
/// Keep the patterns here and nowhere else. Duplicating them lets the
/// directive and the gate drift apart, which is exactly how an unrequested
/// card gets written.
library;

const List<String> _zhTriggers = [
  '记一下',
  '帮我记',
  '记录一下',
  '保存一下',
  '存一下',
  '加到记录',
  '记住这个',
  '帮我记账',
  '记上账',
  '记一笔',
  '记个账',
  '记下来',
  '记下这个',
  '你帮我记',
  '给我记',
  '帮我存',
];

final List<RegExp> _recordRequestPatterns = [
  RegExp('(${_zhTriggers.join('|')})'),
  // "把这个记上" / "把刚才那条记上" — verb split by an object phrase.
  RegExp(r'把.{0,10}记上'),
  RegExp(r'(write.{0,8}down|record.{0,8}this|save.{0,8}this|note.{0,8}down)',
      caseSensitive: false),
];

/// Whether [text] contains an explicit user request to record/save something.
bool containsRecordRequest(String text) {
  if (text.trim().isEmpty) return false;
  return _recordRequestPatterns.any((p) => p.hasMatch(text));
}
