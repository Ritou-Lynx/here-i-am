library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';

class PersistedWorkbenchAction {
  const PersistedWorkbenchAction({
    required this.messageId,
    required this.projection,
  });

  final int messageId;
  final WorkbenchActionProjection projection;
}

typedef WorkbenchActionReader =
    Future<List<PersistedWorkbenchAction>> Function(String characterId);

/// Reads action addenda from the real Drift chat stream. The bounded query is
/// deliberately separate from in-memory facade state so process restart tests
/// exercise the same persistence boundary as production.
Future<List<PersistedWorkbenchAction>> readPersistedWorkbenchActions(
  AppDatabase db,
  String characterId, {
  int limit = 512,
}) async {
  if (limit <= 0 || limit > 512) {
    throw RangeError.range(limit, 1, 512, 'limit');
  }
  final rows =
      await (db.select(db.personaChatMessages)
            ..where(
              (row) =>
                  row.characterId.equals(characterId) &
                  row.messageType.equals('action'),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.timestamp),
              (row) => OrderingTerm.desc(row.id),
            ])
            ..limit(limit))
          .get();
  final result = <PersistedWorkbenchAction>[];
  for (final row in rows) {
    final raw = row.attachmentsJson;
    if (raw == null || raw.trim().isEmpty) continue;
    try {
      final attachments = jsonDecode(raw);
      if (attachments is! List) continue;
      for (final attachment in attachments) {
        if (attachment is! Map || attachment['type'] != 'workbench_action') {
          continue;
        }
        final action = attachment['action'];
        if (action is! Map) continue;
        result.add(
          PersistedWorkbenchAction(
            messageId: row.id,
            projection: WorkbenchActionProjection.fromJson(
              Map<String, dynamic>.from(action),
            ),
          ),
        );
      }
    } catch (_) {
      // One malformed historical addendum cannot hide independent records.
    }
  }
  return result;
}
