import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';

/// Accepted-capture lifecycle. Extraction is outside SQLite; projections,
/// source ledger, protection issues and acknowledgement commit together.
class CaptureConsumer {
  CaptureConsumer({
    required this.db,
    required this.store,
    required this.organizer,
    required this.extract,
    required this.decodeText,
    required this.inputVersion,
  });
  final AppDatabase db;
  final DomainStore store;
  final RecordOrganizerServiceV3 organizer;
  final Future<OrganizedRecord> Function(String rawInput) extract;
  final String Function(Json data) decodeText;
  final int? Function(Json record) inputVersion;
  String get _prefix => 'capture_lifecycle.${store.binding.coreInstanceId}.';
  String get _oldPrefix => 'capture_consumed.${store.binding.coreInstanceId}.';
  static String _digest(String text) =>
      sha256.convert(utf8.encode(text)).toString();
  static bool _supported(Json record) => const {
        'claude_web',
        'phone_quick',
      }.contains(record['provenance']?['source'] ?? record['data']?['source']);

  /// Processing receipt only; contains no source body or private model trace.
  Future<Json?> processingResult(String id, {String? expectedText}) async {
    final value = await _ledger(id);
    if (value == null || value['deleted'] == true) return null;
    if (expectedText != null &&
        value['input_digest'] != _digest(expectedText)) {
      return null;
    }
    final issues = value['issues'] as List? ?? [];
    final outputs = (value['slots'] as List? ?? [])
        .where((s) => s['missing'] != true)
        .map((s) => s['id'])
        .toList();
    return {
      'status': issues.isNotEmpty
          ? 'pending'
          : outputs.isEmpty
              ? 'skipped'
              : 'done',
      'outputs': issues.isEmpty ? outputs : <String>[],
    };
  }

  Future<int> _consumePhone(Json domain, {String route = 'phone'}) async {
    var count = 0;
    for (final raw in (domain['phone_records'] as Map).values) {
      final record = jsonObject(raw);
      final id = record['id'] as String;
      if (record['deleted_at'] != null &&
          record['local_delete_action'] is String) {
        await db.transaction(() async {
          await store.acquireWriteLock();
          final latest = store.domain(await store.read(), 'captures');
          store.checkBinding(latest, 'captures');
          final current = latest['phone_records'][id];
          final before = await _ledger(id);
          if (latest['route'] != 'phone' ||
              before == null ||
              before['deleted'] == true ||
              current?['local_delete_action'] !=
                  record['local_delete_action'] ||
              current?['deleted_at'] == null) {
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
            'local_pending': true,
            'source': 'phone_quick',
            ...reconciled
          });
          await store.fault('capture_before_commit');
          count++;
        });
        continue;
      }
      if (record['data']?['source'] != 'phone_quick') continue;
      final text = decodeText(jsonObject(record['data']));
      final digest = _digest(text);
      final ledger = await _ledger(id);
      if (ledger?['input_digest'] == digest && ledger?['deleted'] != true) {
        continue;
      }
      final organized = await extract(text);
      await db.transaction(() async {
        await store.acquireWriteLock();
        final latest = store.domain(await store.read(), 'captures');
        store.checkBinding(latest, 'captures');
        final current = route == 'phone'
            ? latest['phone_records'][id]
            : (await store.visible('captures'))
                .where((r) => r['id'] == id)
                .firstOrNull;
        if (latest['route'] != route ||
            current == null ||
            current['deleted_at'] != null ||
            _digest(decodeText(jsonObject(current['data']))) != digest) {
          return;
        }
        final before = await _ledger(id);
        if (before?['input_digest'] == digest && before?['deleted'] != true) {
          return;
        }
        final reconciled = await organizer.reconcileCapture(
          previous: (before?['slots'] as List? ?? []).map(jsonObject).toList(),
          organized: OrganizedRecord(
            cards: organized.cards
                .where(
                  (c) => !const {'task', 'schedule', 'plan'}.contains(c.type),
                )
                .toList(),
          ),
          source: RecordSource(
            sourceKind: 'import',
            rawInput: text,
            sourceRef: 'captures:$id',
          ),
        );
        await _save(id, {
          'schema': 1,
          'capture_id': id,
          'input_version': current['local_input_version'] ?? 1,
          'input_digest': digest,
          'local_pending': true,
          'source': 'phone_quick',
          'deleted': false,
          ...reconciled,
        });
        await store.fault('capture_before_commit');
        count++;
      });
    }
    return count;
  }

  Future<Json?> _ledger(String id) async {
    final rows = await db.customSelect(
      'SELECT value FROM kv_store WHERE key = ? AND bucket = ?',
      variables: [
        Variable('$_prefix$id'),
        const Variable('capture_consumer'),
      ],
    ).get();
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
          store.clock().millisecondsSinceEpoch,
        ],
      );

  /// W4 can query issues without discarded source text or audit history.
  Future<List<Json>> pendingIssues() async {
    final rows = await db
        .customSelect(
          "SELECT key,value FROM kv_store WHERE bucket='capture_consumer'",
        )
        .get();
    final result = <Json>[];
    for (final row in rows) {
      if (!row.read<String>('key').startsWith(_prefix)) continue;
      final ledger = jsonObject(jsonDecode(row.read<String>('value')));
      for (final issue in ledger['issues'] as List? ?? []) {
        result.add({
          'capture_id': ledger['capture_id'],
          ...jsonObject(issue),
          'message': captureIssueMessage(
            issue['reason'] as String,
            deleted: ledger['deleted'] == true,
          ),
        });
      }
    }
    return result;
  }

  Future<void> _upgradeLegacy(Future<void> Function()? verifyOwnership) =>
      db.transaction(() async {
        await store.acquireWriteLock();
        await verifyOwnership?.call();
        final rows = await db
            .customSelect(
              "SELECT key,value FROM kv_store WHERE bucket='capture_consumer'",
            )
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
              .expand(
                (r) => (r['disposition']?['outputs'] as List? ?? [])
                    .whereType<String>(),
              )
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
                        },
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
                        },
                    ],
                  },
          );
          for (final row in entry.value) {
            await db.customStatement('DELETE FROM kv_store WHERE key = ?', [
              row['key'],
            ]);
          }
        }
      });

  // A hidden replica alone is insufficient: require the tombstone or the
  // matching accepted delete/purge receipt. Merge/permission hiding is not it.
  bool _deleted(Json state, Json d, String id) =>
      d['records'][id]?['deleted_at'] != null ||
      (d['hidden_ids']?[id] != null &&
          (state['outbox'] as List).any(
            (o) =>
                o['domain'] == 'captures' &&
                o['id'] == id &&
                ['accepted', 'duplicate'].contains(o['state']) &&
                (['delete', 'purge'].contains(o['intent']?['kind']) ||
                    (o['target_state'] == 'deleted' &&
                        o['result']?['reason'] != 'semantic_duplicate')) &&
                (o['result']?['receipt']?['targets'] as List? ?? []).any(
                  (t) => t['id'] == id,
                ),
          ));

  Future<int> consume(
      {bool allowRemoteWeb = true,
      Future<void> Function()? verifyRemoteOwnership}) async {
    if (!identical(db, store.db) || !organizer.captureUsesDatabase(db)) {
      throw const DomainFailure('database_mismatch');
    }
    final state = await store.read();
    final d = store.domain(state, 'captures');
    store.checkBinding(d, 'captures');
    if (d['route'] == 'phone') return _consumePhone(d);
    if (d['route'] != 'core') return 0;
    if (allowRemoteWeb) await _upgradeLegacy(verifyRemoteOwnership);
    final pendingIds = (state['outbox'] as List)
        .where((o) =>
            o['domain'] == 'captures' &&
            ['pending', 'submitting'].contains(o['state']) &&
            ['create', 'patch'].contains(o['intent']?['kind']))
        .map((o) => o['id'])
        .toSet();
    var count = await _consumePhone({
      'phone_records': {
        for (final r in await store.visible('captures'))
          if (pendingIds.contains(r['id']) &&
              r['data']?['source'] == 'phone_quick')
            r['id']: r,
      }
    }, route: 'core');
    final ids = <String>{
      ...(d['records'] as Map).keys.cast<String>(),
      ...(d['hidden_ids'] as Map? ?? {}).keys.cast<String>(),
    };
    for (final id in ids) {
      final ledger = await _ledger(id);
      final recordSource = d['records'][id]?['provenance']?['source'] ??
          d['records'][id]?['data']?['source'] ??
          ledger?['source'];
      // Bodyless tombstones and unknown old receipts are not assumed to be
      // phone quick captures. The web owner gate covers deletes as well.
      if (!allowRemoteWeb && recordSource != 'phone_quick') continue;
      if (_deleted(state, d, id)) {
        if (ledger == null || ledger['deleted'] == true) continue;
        await db.transaction(() async {
          await store.acquireWriteLock();
          await verifyRemoteOwnership?.call();
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
              sourceRef: 'captures:$id',
            ),
            deleted: true,
          );
          await _save(id, {
            'schema': 1,
            'capture_id': id,
            'input_version': before['input_version'],
            'source': recordSource,
            'deleted': true,
            ...reconciled,
          });
          await store.fault('capture_before_commit');
          // A body-less tombstone must never be acked or resurrected.
          count++;
        });
        continue;
      }
      if (d['cursor'] == null || d['records'][id] == null) continue;
      final record = jsonObject(d['records'][id]);
      if (!_supported(record)) continue;
      final version = inputVersion(record);
      if (version == null ||
          version < 1 ||
          (ledger?['local_pending'] != true &&
              ledger?['input_version'] == version)) {
        continue;
      }
      final completed = record['data']?['organizer'];
      // A remote ack without local ownership is not permission to duplicate a
      // whole result set. Its IDs can only become unverifiable legacy slots.
      if (ledger == null &&
          completed is Map &&
          ['done', 'skipped'].contains(completed['status'])) {
        await db.transaction(() async {
          await store.acquireWriteLock();
          await verifyRemoteOwnership?.call();
          if (await _ledger(id) != null) return;
          final slots = await organizer.captureLegacySlots(
            (completed['outputs'] as List? ?? []).whereType<String>().toList(),
          );
          await _save(id, {
            'schema': 1,
            'capture_id': id,
            'input_version': completed['input_revision'],
            'deleted': false,
            'slots': slots,
            'removed_ids': <String>[],
            'issues': [
              for (final s in slots)
                {'card_id': s['id'], 'reason': 'legacy_generation_unverified'},
            ],
          });
        });
        if (completed['input_revision'] == version) continue;
      }
      final text = decodeText(jsonObject(record['data']));
      final digest = _digest(text);
      // A stale remote revision must not overwrite unsynchronized local edits.
      if (ledger?['local_pending'] == true &&
          ledger?['input_digest'] != digest) {
        continue;
      }
      final alreadyExtracted =
          ledger?['local_pending'] == true && ledger?['input_digest'] == digest;
      final organized =
          alreadyExtracted ? OrganizedRecord(cards: []) : await extract(text);
      await db.transaction(() async {
        await store.acquireWriteLock();
        await verifyRemoteOwnership?.call();
        final latestState = await store.read();
        final latest = store.domain(latestState, 'captures');
        store.checkBinding(latest, 'captures');
        final current = latest['records'][id];
        if (latest['route'] != 'core' ||
            latest['cursor'] == null ||
            current == null ||
            _deleted(latestState, latest, id) ||
            !_supported(jsonObject(current)) ||
            inputVersion(jsonObject(current)) != version) {
          return;
        }
        final before = await _ledger(id);
        if (before?['local_pending'] != true &&
            before?['input_version'] == version) {
          return;
        }
        if (alreadyExtracted &&
            (before?['input_digest'] != digest || before?['deleted'] == true)) {
          return;
        }
        final remote = current['data']?['organizer'];
        if (before == null &&
            remote is Map &&
            remote['input_revision'] == version &&
            ['done', 'skipped'].contains(remote['status'])) {
          final slots = await organizer.captureLegacySlots(
            (remote['outputs'] as List? ?? []).whereType<String>().toList(),
          );
          await _save(id, {
            'schema': 1,
            'capture_id': id,
            'input_version': version,
            'deleted': false,
            'slots': slots,
            'removed_ids': <String>[],
            'issues': [
              for (final s in slots)
                {'card_id': s['id'], 'reason': 'legacy_generation_unverified'},
            ],
          });
          return;
        }
        final reconciled = alreadyExtracted
            ? <String, dynamic>{
                'slots': before!['slots'],
                'removed_ids': before['removed_ids'],
                'issues': before['issues'],
              }
            : await organizer.reconcileCapture(
                previous:
                    (before?['slots'] as List? ?? []).map(jsonObject).toList(),
                organized: record['data']?['source'] == 'phone_quick' ||
                        record['provenance']?['source'] == 'phone_quick'
                    ? OrganizedRecord(
                        cards: organized.cards
                            .where(
                              (c) => !const {
                                'task',
                                'schedule',
                                'plan',
                              }.contains(c.type),
                            )
                            .toList(),
                      )
                    : organized,
                source: RecordSource(
                  sourceKind: 'import',
                  rawInput: text,
                  sourceRef: 'captures:$id',
                ),
              );
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
          'input_revision': version,
        };
        await _save(id, {
          'schema': 1,
          'capture_id': id,
          'input_version': version,
          'input_digest': digest,
          'local_pending': false,
          'source': recordSource,
          'deleted': false,
          ...reconciled,
        });
        await store.enqueue(
          'captures',
          id: id,
          kind: 'ack_capture',
          baseRevision: current['revision'],
          actor: 'agent_inferred',
          fields: {
            'processor': 'organizer',
            'disposition': {'organizer': disposition},
          },
        );
        await store.fault('capture_before_commit');
        count++;
      });
    }
    return count;
  }
}
