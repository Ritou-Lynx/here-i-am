import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';

/// Opt-in consumer of accepted captures. Extraction is injected from the
/// configured Organizer model entry; pending drafts never enter this consumer.
/// No planner outputs, legacy 47862 polling, or implicit model configuration.
class CaptureConsumer {
  CaptureConsumer(
      {required this.db,
      required this.store,
      required this.organizer,
      required this.extract,
      required this.decodeText,
      required this.inputVersion});
  final AppDatabase db;
  final DomainStore store;
  final RecordOrganizerServiceV3 organizer;
  final Future<OrganizedRecord> Function(String rawInput) extract;
  // W2 owns the business field mapping; it must be explicitly provided.
  final String Function(Json data) decodeText;
  final int? Function(Json record) inputVersion;

  Future<int> consume() async {
    if (!identical(db, store.db)) {
      throw const DomainFailure('database_mismatch');
    }
    final s = await store.read(), d = store.domain(s, 'captures');
    store.checkBinding(d, 'captures');
    if (d['route'] != 'core' || d['cursor'] == null) return 0;
    var count = 0;
    for (final raw in (d['records'] as Map).values) {
      final record = jsonObject(raw);
      if (record['deleted_at'] != null ||
          record['provenance']?['source'] != 'claude_web') {
        continue;
      }
      final id = record['id'] as String;
      final version = inputVersion(record);
      if (version == null || version < 1) continue;
      final completed = record['data']?['organizer'];
      if (completed is Map &&
          completed['input_revision'] == version &&
          ['done', 'skipped'].contains(completed['status'])) {
        continue;
      }
      final key =
          'capture_consumed.${store.binding.coreInstanceId}.$id.$version';
      final exists = await db.customSelect(
          'SELECT key FROM kv_store WHERE key = ?',
          variables: [Variable(key)]).get();
      if (exists.isNotEmpty) continue;
      final text = decodeText(jsonObject(record['data']));
      final organized = await extract(text);
      // The extraction is outside a transaction. Recheck the latest canonical
      // tombstone/revision before committing any User-truth.
      await db.transaction(() async {
        final currentState = await store.read();
        final current = store.domain(currentState, 'captures')['records'][id];
        if (current == null ||
            current['deleted_at'] != null ||
            current['revision'] != record['revision']) {
          return;
        }
        final again = await db.customSelect(
            'SELECT key FROM kv_store WHERE key = ?',
            variables: [Variable(key)]).get();
        if (again.isNotEmpty) return;
        final life = OrganizedRecord(
            cards: organized.cards
                .where(
                    (c) => !const ['task', 'schedule', 'plan'].contains(c.type))
                .toList());
        final result = await organizer.persist(
            organized: life,
            source: RecordSource(
                sourceKind: 'import',
                rawInput: text,
                sourceRef: 'captures:$id'));
        final disposition = {
          'status': result.isEmpty ? 'skipped' : 'done',
          'outputs': result.cardIds,
          'input_revision': version
        };
        // Stable capture key and exact output IDs commit with the actual cards.
        await db.customStatement(
            'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?)',
            [
              key,
              jsonEncode({
                'capture_id': id,
                'revision': record['revision'],
                'disposition': disposition
              }),
              'capture_consumer',
              store.clock().millisecondsSinceEpoch
            ]);
        await store.enqueue('captures',
            id: id,
            kind: 'ack_capture',
            baseRevision: record['revision'],
            actor: 'agent_inferred',
            fields: {
              'processor': 'organizer',
              'disposition': {'organizer': disposition}
            });
        count++;
      });
    }
    return count;
  }
}
