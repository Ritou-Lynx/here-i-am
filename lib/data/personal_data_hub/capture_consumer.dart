import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';

/// Accepted-capture lifecycle. Extraction is outside SQLite; projections,
/// source ledger, protection issues and acknowledgement commit together.
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
  final String Function(Json data) decodeText;
  final int? Function(Json record) inputVersion;
  String get _prefix => 'capture_lifecycle.${store.binding.coreInstanceId}.';
  String get _oldPrefix => 'capture_consumed.${store.binding.coreInstanceId}.';

  Future<Json?> _ledger(String id) async {
    final rows = await db.customSelect(
        'SELECT value FROM kv_store WHERE key = ? AND bucket = ?',
        variables: [
          Variable('$_prefix$id'),
          const Variable('capture_consumer')
        ]).get();
    return rows.isEmpty
        ? null
        : jsonObject(jsonDecode(rows.single.read<String>('value')));
  }

  Future<void> _save(String id, Json value) => db.customStatement(
          'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?) '
          'ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at',
          [
            '$_prefix$id',
            jsonEncode(value),
            'capture_consumer',
            store.clock().millisecondsSinceEpoch
          ]);

  /// W4 can query issues without discarded source text or audit history.
  Future<List<Json>> pendingIssues() async {
    final rows = await db
        .customSelect(
            "SELECT key,value FROM kv_store WHERE bucket='capture_consumer'")
        .get();
    final result = <Json>[];
    for (final row in rows) {
      if (!row.read<String>('key').startsWith(_prefix)) continue;
      final ledger = jsonObject(jsonDecode(row.read<String>('value')));
      for (final issue in ledger['issues'] as List? ?? []) {
        result.add({
          'capture_id': ledger['capture_id'],
          ...jsonObject(issue),
          'message': captureIssueMessage(issue['reason'] as String,
              deleted: ledger['deleted'] == true)
        });
      }
    }
    return result;
  }

  Future<void> _upgradeLegacy() => db.transaction(() async {
        final rows = await db
            .customSelect(
                "SELECT key,value FROM kv_store WHERE bucket='capture_consumer'")
            .get();
        final grouped = <String, List<Json>>{};
        for (final row in rows) {
          final key = row.read<String>('key');
          if (!key.startsWith(_oldPrefix)) continue;
          final value = jsonObject(jsonDecode(row.read<String>('value')));
          final id = value['capture_id'];
          if (id is! String || !key.startsWith('$_oldPrefix$id.')) {
            continue;
          }
          grouped.putIfAbsent(id, () => []).add({...value, 'key': key});
        }
        for (final entry in grouped.entries) {
          final current = await _ledger(entry.key);
          final versions = entry.value
              .map((r) => r['disposition']?['input_revision'])
              .whereType<int>()
              .toList()
            ..sort();
          final ids = entry.value
              .expand((r) => (r['disposition']?['outputs'] as List? ?? [])
                  .whereType<String>())
              .toSet();
          if (current != null) {
            ids.removeAll(
                (current['slots'] as List).map((s) => s['id'] as String));
          }
          final extra = await organizer.captureLegacySlots(ids.toList());
          await _save(
              entry.key,
              current == null
                  ? {
                      'schema': 1,
                      'capture_id': entry.key,
                      'input_version': versions.isEmpty ? null : versions.last,
                      'deleted': false,
                      'slots': extra,
                      'removed_ids': <String>[],
                      'issues': [
                        for (final id in ids)
                          {
                            'card_id': id,
                            'reason': 'legacy_generation_unverified'
                          }
                      ],
                    }
                  : {
                      ...current,
                      'slots': [...current['slots'], ...extra],
                      'issues': [
                        ...current['issues'],
                        for (final id in ids)
                          {
                            'card_id': id,
                            'reason': 'legacy_generation_unverified'
                          }
                      ]
                    });
          for (final row in entry.value) {
            await db.customStatement(
                'DELETE FROM kv_store WHERE key = ?', [row['key']]);
          }
        }
      });

  // A hidden replica alone is insufficient: require the tombstone or the
  // matching accepted delete/purge receipt. Merge/permission hiding is not it.
  bool _deleted(Json state, Json d, String id) =>
      d['records'][id]?['deleted_at'] != null ||
      (d['hidden_ids']?[id] != null &&
          (state['outbox'] as List).any((o) =>
              o['domain'] == 'captures' &&
              o['id'] == id &&
              ['accepted', 'duplicate'].contains(o['state']) &&
              (['delete', 'purge'].contains(o['intent']?['kind']) ||
                  (o['target_state'] == 'deleted' &&
                      o['result']?['reason'] != 'semantic_duplicate')) &&
              (o['result']?['receipt']?['targets'] as List? ?? [])
                  .any((t) => t['id'] == id)));

  Future<int> consume() async {
    if (!identical(db, store.db) || !organizer.captureUsesDatabase(db)) {
      throw const DomainFailure('database_mismatch');
    }
    final state = await store.read();
    final d = store.domain(state, 'captures');
    store.checkBinding(d, 'captures');
    if (d['route'] != 'core') return 0;
    await _upgradeLegacy();
    var count = 0;
    final ids = <String>{
      ...(d['records'] as Map).keys.cast<String>(),
      ...(d['hidden_ids'] as Map? ?? {}).keys.cast<String>()
    };
    for (final id in ids) {
      final ledger = await _ledger(id);
      if (_deleted(state, d, id)) {
        if (ledger == null || ledger['deleted'] == true) continue;
        await db.transaction(() async {
          final latestState = await store.read();
          final latest = store.domain(latestState, 'captures');
          store.checkBinding(latest, 'captures');
          final before = await _ledger(id);
          if (latest['route'] != 'core' ||
              !_deleted(latestState, latest, id) ||
              before == null ||
              before['deleted'] == true) {
            return;
          }
          final reconciled = await organizer.reconcileCapture(
              previous: (before['slots'] as List).map(jsonObject).toList(),
              organized: OrganizedRecord(cards: []),
              source: RecordSource(
                  sourceKind: 'import',
                  rawInput: '',
                  sourceRef: 'captures:$id'),
              deleted: true);
          await _save(id, {
            'schema': 1,
            'capture_id': id,
            'input_version': before['input_version'],
            'deleted': true,
            ...reconciled
          });
          await store.fault('capture_before_commit');
          // A body-less tombstone must never be acked or resurrected.
          count++;
        });
        continue;
      }
      if (d['cursor'] == null || d['records'][id] == null) continue;
      final record = jsonObject(d['records'][id]);
      if (record['provenance']?['source'] != 'claude_web') continue;
      final version = inputVersion(record);
      if (version == null ||
          version < 1 ||
          ledger?['input_version'] == version) {
        continue;
      }
      final completed = record['data']?['organizer'];
      // A remote ack without local ownership is not permission to duplicate a
      // whole result set. Its IDs can only become unverifiable legacy slots.
      if (ledger == null &&
          completed is Map &&
          ['done', 'skipped'].contains(completed['status'])) {
        await db.transaction(() async {
          if (await _ledger(id) != null) return;
          final slots = await organizer.captureLegacySlots(
              (completed['outputs'] as List? ?? [])
                  .whereType<String>()
                  .toList());
          await _save(id, {
            'schema': 1,
            'capture_id': id,
            'input_version': completed['input_revision'],
            'deleted': false,
            'slots': slots,
            'removed_ids': <String>[],
            'issues': [
              for (final s in slots)
                {'card_id': s['id'], 'reason': 'legacy_generation_unverified'}
            ]
          });
        });
        if (completed['input_revision'] == version) continue;
      }
      final text = decodeText(jsonObject(record['data']));
      final organized = await extract(text);
      await db.transaction(() async {
        final latestState = await store.read();
        final latest = store.domain(latestState, 'captures');
        store.checkBinding(latest, 'captures');
        final current = latest['records'][id];
        if (latest['route'] != 'core' ||
            latest['cursor'] == null ||
            current == null ||
            _deleted(latestState, latest, id) ||
            current['provenance']?['source'] != 'claude_web' ||
            inputVersion(jsonObject(current)) != version) {
          return;
        }
        final before = await _ledger(id);
        if (before?['input_version'] == version) return;
        final remote = current['data']?['organizer'];
        if (before == null &&
            remote is Map &&
            remote['input_revision'] == version &&
            ['done', 'skipped'].contains(remote['status'])) {
          final slots = await organizer.captureLegacySlots(
              (remote['outputs'] as List? ?? []).whereType<String>().toList());
          await _save(id, {
            'schema': 1,
            'capture_id': id,
            'input_version': version,
            'deleted': false,
            'slots': slots,
            'removed_ids': <String>[],
            'issues': [
              for (final s in slots)
                {'card_id': s['id'], 'reason': 'legacy_generation_unverified'}
            ]
          });
          return;
        }
        final reconciled = await organizer.reconcileCapture(
            previous:
                (before?['slots'] as List? ?? []).map(jsonObject).toList(),
            organized: organized,
            source: RecordSource(
                sourceKind: 'import',
                rawInput: text,
                sourceRef: 'captures:$id'));
        final issues = reconciled['issues'] as List;
        final outputs = (reconciled['slots'] as List)
            .where((s) => s['missing'] != true)
            .map((s) => s['id'])
            .toList();
        final disposition = {
          'status': issues.isNotEmpty
              ? 'pending'
              : outputs.isEmpty
                  ? 'skipped'
                  : 'done',
          'outputs': issues.isNotEmpty ? <String>[] : outputs,
          'input_revision': version
        };
        await _save(id, {
          'schema': 1,
          'capture_id': id,
          'input_version': version,
          'deleted': false,
          ...reconciled
        });
        await store.enqueue('captures',
            id: id,
            kind: 'ack_capture',
            baseRevision: current['revision'],
            actor: 'agent_inferred',
            fields: {
              'processor': 'organizer',
              'disposition': {'organizer': disposition}
            });
        await store.fault('capture_before_commit');
        count++;
      });
    }
    return count;
  }
}
