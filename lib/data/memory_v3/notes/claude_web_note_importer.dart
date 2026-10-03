import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';
import '../models/organized_record.dart';
import '../services/record_organizer_service.dart';
import 'claude_web_note_models.dart';

typedef ClaudeWebNoteOrganizer = Future<OrganizedRecord> Function(
    RecordSource source);

/// The production callback runs RecordOrganizerAgentV3 with the user's memory
/// extraction model. Analysis happens before the transaction; projections,
/// source links, corrections and the revision receipt commit atomically.
class ClaudeWebNoteImporter {
  ClaudeWebNoteImporter({
    required AppDatabase db,
    required RecordOrganizerServiceV3 organizer,
    required ClaudeWebNoteOrganizer organize,
  })  : _db = db,
        _organizer = organizer,
        _organize = organize;
  final AppDatabase _db;
  final RecordOrganizerServiceV3 _organizer;
  final ClaudeWebNoteOrganizer _organize;
  static const sourceKind = 'claude_web_note';
  static const _receiptKind = 'external_note_import';

  String _prefix(String noteId) =>
      'claude-note:${base64Url.encode(utf8.encode(noteId))}:';

  Future<({int revision, List<String> ids})?> _receipt(String noteId) async {
    final rows = await (_db.select(_db.memoryCardOperations)
          ..where(
            (t) =>
                t.sourceKind.equals(sourceKind) &
                t.operationType.equals(_receiptKind) &
                t.id.like('${_prefix(noteId)}%'),
          ))
        .get();
    ({int revision, List<String> ids})? latest;
    for (final row in rows) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      if (payload['note_id'] != noteId) continue;
      final revision = payload['revision'] as int;
      if (latest == null || revision > latest.revision) {
        latest = (
          revision: revision,
          ids: (payload['card_ids'] as List).cast<String>(),
        );
      }
    }
    return latest;
  }

  /// Returns the first card id for the wire acknowledgement; all generated
  /// cards are tracked locally. Replays never invoke the model again.
  Future<String?> apply(ClaudeWebNoteChange change) async {
    final previous = await _receipt(change.noteId);
    if (previous != null && previous.revision >= change.revision) {
      return previous.ids.firstOrNull;
    }
    final source = RecordSource(
      sourceKind: sourceKind,
      rawInput: change.text ?? '',
      sourceRef: change.noteId,
      recordedAt: change.createdAt,
    );
    final organized = change.deleted ? null : await _organize(source);
    if (organized != null && organized.isEmpty) {
      throw StateError('记录整理未生成卡片，保留等待重试');
    }
    return _db.transaction(() async {
      // A concurrent/restarted importer may already have committed this item.
      final current = await _receipt(change.noteId);
      if (current != null && current.revision >= change.revision) {
        return current.ids.firstOrNull;
      }
      final sources = await (_db.select(_db.memoryCardSources)
            ..where(
              (t) =>
                  t.sourceKind.equals(sourceKind) &
                  t.sourceRef.equals(change.noteId),
            ))
          .get();
      final linked = {for (final row in sources) row.cardId: row};
      final orderedIds = <String>[
        ...?current?.ids.where(linked.containsKey),
        ...linked.keys
            .where((id) => !(current?.ids.contains(id) ?? false))
            .toList()
          ..sort(),
      ];
      final cardIds = <String>[];
      if (!change.deleted) {
        for (var i = 0; i < organized!.cards.length; i++) {
          final card = organized.cards[i];
          final existingId = i < orderedIds.length ? orderedIds[i] : null;
          final existing = existingId == null
              ? null
              : await (_db.select(
                  _db.memoryCards,
                )..where((t) => t.id.equals(existingId)))
                  .getSingleOrNull();
          if (existing == null) {
            final result = await _organizer.persist(
              organized: OrganizedRecord(cards: [card]),
              source: source,
              deduplicate: false,
            );
            cardIds.addAll(result.cardIds);
          } else {
            await _organizer.replaceOrganizedCard(existing.id, card, source);
            cardIds.add(existing.id);
          }
        }
      }
      for (final id in orderedIds.where((id) => !cardIds.contains(id))) {
        await _organizer.deleteCard(id, sourceKind: sourceKind);
      }
      final ackIds = change.deleted ? (current?.ids ?? orderedIds) : cardIds;
      await _db.into(_db.memoryCardOperations).insert(
            MemoryCardOperationsCompanion.insert(
              id: '${_prefix(change.noteId)}${change.revision}',
              cardId: ackIds.firstOrNull ?? 'external-note:${change.noteId}',
              operationType: _receiptKind,
              sourceKind: sourceKind,
              // No text in the durable receipt, including tombstones.
              payload: jsonEncode({
                'note_id': change.noteId,
                'revision': change.revision,
                'op': change.deleted ? 'delete' : 'upsert',
                'card_ids': ackIds,
              }),
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      return ackIds.firstOrNull;
    });
  }
}
