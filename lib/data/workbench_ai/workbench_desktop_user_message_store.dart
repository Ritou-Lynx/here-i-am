/// Persistence boundary shared by the ordinary desktop send entry and an
/// explicitly isolated acceptance store. It supplies no database default.
abstract interface class WorkbenchDesktopUserMessageStore {
  Future<int> addUserMessage(
    String characterId,
    String content, {
    DateTime? timestamp,
    List<Map<String, String>>? attachments,
    bool appendTimeline = true,
  });
}
