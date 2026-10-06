import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';
import '../models/organized_record.dart';
import '../services/record_organizer_service.dart';
import 'claude_web_note_models.dart';
import 'package:memex/data/personal_data_hub/capture_consumer_ownership.dart';

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
  AppDatabase get database => _db;
  final RecordOrganizerServiceV3 _organizer;
  final ClaudeWebNoteOrganizer _organize;
  static const sourceKind = 'claude_web_note';
  static const _receiptKind = 'external_note_import';

  String _prefix(String noteId) =>
      'claude-note:${base64Url.encode(utf8.encode(noteId))}:';

  Future<
      ({
        int revision,
        List<String> ids,
        List<Map<String, dynamic>>? slots,
        List<Map<String, dynamic>> issues
      })?> _receipt(String noteId) async {
    final rows = await (_db.select(_db.memoryCardOperations)
          ..where(
            (t) =>
                t.sourceKind.equals(sourceKind) &
                t.operationType.equals(_receiptKind) &
                t.id.like('${_prefix(noteId)}%'),
          ))
        .get();
    ({
      int revision,
      List<String> ids,
      List<Map<String, dynamic>>? slots,
      List<Map<String, dynamic>> issues
    })? latest;
    for (final row in rows) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      if (payload['note_id'] != noteId) continue;
      final revision = payload['revision'] as int;
      if (latest == null || revision > latest.revision) {
        latest = (
          revision: revision,
          ids: (payload['card_ids'] as List).cast<String>(),
          slots: (payload['slots'] as List?)
              ?.map((s) => Map<String, dynamic>.from(s as Map))
              .toList(),
          issues: (payload['issues'] as List? ?? [])
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList(),
        );
      }
    }
    return latest;
  }

  /// Returns the first card id for the wire acknowledgement; all generated
  /// cards are tracked locally. Replays never invoke the model again.
  Future<List<Map<String, dynamic>>> pendingIssues(String noteId) async =>
      (await _receipt(noteId))?.issues ?? [];

  static String projectionSourceRef(String noteId) =>
      'captures:legacy-note:${base64Url.encode(utf8.encode(noteId))}';

  Future<String?> apply(ClaudeWebNoteChange change,
      {CaptureConsumerLease? lease}) async {
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
      await _db
          .customStatement('UPDATE kv_store SET updated_at=updated_at WHERE 0');
      await lease?.verify();
      // A concurrent/restarted importer may already have committed this item.
      final current = await _receipt(change.noteId);
      if (current != null && current.revision >= change.revision) {
        return current.ids.firstOrNull;
      }
      await lease?.verify();
      // Pre-transition B3 receipts retain their exact IDs. They have no trusted
      // generated fingerprint, so PR11 protects them instead of reconstructing
      // a baseline from potentially user-edited cards. Never match by position.
      final sources = await (_db.select(_db.memoryCardSources)
            ..where((t) =>
                t.sourceKind.equals(sourceKind) &
                t.sourceRef.equals(change.noteId)))
          .get();
      final ids = {...?current?.ids, ...sources.map((s) => s.cardId)}.toList();
      final slots = current?.slots ?? await _organizer.captureLegacySlots(ids);
      final reconciled = await _organizer.reconcileCapture(
        previous: slots,
        organized: organized ?? OrganizedRecord(cards: []),
        source: RecordSource(
            sourceKind: 'import',
            rawInput: source.rawInput,
            sourceRef: projectionSourceRef(change.noteId),
            recordedAt: source.recordedAt),
        deleted: change.deleted,
        includePlanningCards: true,
      );
      final cardIds = (reconciled['slots'] as List)
          .where((s) => s['missing'] != true)
          .map((s) => s['id'] as String)
          .toList();
      final ackIds = change.deleted ? ids : cardIds;
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
                'slots': reconciled['slots'],
                'issues': reconciled['issues'],
                'projection_source_ref': projectionSourceRef(change.noteId),
              }),
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      return ackIds.firstOrNull;
    });
  }
}
