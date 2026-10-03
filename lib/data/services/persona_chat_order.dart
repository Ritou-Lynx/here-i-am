import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';

/// Timestamp precision and core ordering survive pulls, restarts and pagination.
Expression<int> chatCreatedAtMs($PersonaChatMessagesTable table) =>
    coalesce([table.createdAtMs, table.timestamp.unixepoch * const Constant(1000)]);

Expression<int> chatSequence($PersonaChatMessagesTable table) =>
    coalesce([table.serverSequence, table.id]);

int compareChatMessages(PersonaChatMessage a, PersonaChatMessage b) {
  final byTime = (a.createdAtMs ?? a.timestamp.millisecondsSinceEpoch)
      .compareTo(b.createdAtMs ?? b.timestamp.millisecondsSinceEpoch);
  if (byTime != 0) return byTime;
  final bySequence =
      (a.serverSequence ?? a.id).compareTo(b.serverSequence ?? b.id);
  return bySequence != 0 ? bySequence : a.id.compareTo(b.id);
}
