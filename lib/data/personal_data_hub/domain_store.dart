import 'dart:async';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'domain_protocol.dart';
import 'domain_row_storage.dart';

/// Persists in the existing kv_store on the injected AppDatabase connection.
/// Records, tombstones, corrections and outbox operations own separate rows.
/// Every local write / outbox change / cursor change uses a real transaction. No schema migration, global database, or filesystem is opened.
class DomainStore {
  DomainStore(this.db,
      {required this.binding,
      DateTime Function()? clock,
      this.testFault,
      this.maxItems = DomainPolicy.maxItems,
      this.maxBytes = DomainPolicy.maxBytes})
      : clock = clock ?? DateTime.now;
  final GeneratedDatabase db;
  final DomainBinding binding;
  final DateTime Function() clock;
  final FutureOr<void> Function(String point)? testFault;
  final int maxItems, maxBytes;
  Future<void> fault(String point) async {
    await testFault?.call(point);
  }

  late final _rows = DomainRowStorage(db,
      installationId: binding.installationId, clock: clock, fault: fault);

  /// A coherent SQLite snapshot. Old state migrates atomically on first access;
  /// IDs, pending request bodies, sealed operations and receipts are preserved.
  Future<Json> read() async {
    final loaded = await db.transaction(_rows.read);
    if (loaded.migrated) await fault('legacy_migration_after_commit');
    return loaded.state;
  }

  Future<T> transaction<T>(Future<T> Function(Json state) work) async {
    var migrated = false;
    final result = await db.transaction(() async {
      final loaded = await _rows.read();
      migrated = loaded.migrated;
      final result = await work(loaded.state);
      await _rows.save(loaded.state);
      await fault('before_local_commit');
      return result;
    });
    if (migrated) await fault('legacy_migration_after_commit');
    return result;
  }

  /// Explicit owner prerequisite; never implicitly restore destructive cleanup.
  Future<void> disableLocalDedupe(String name) => transaction((s) async {
        final d = domain(s, name);
        checkBinding(d, name);
        d['local_dedupe_disabled'] = true;
      });

  Json domain(Json s, String name) => s['domains'].putIfAbsent(
      name,
      () => <String, dynamic>{
            'route': 'phone',
            'records': <String, dynamic>{},
            'phone_records': <String, dynamic>{},
            'cursor': null,
            'binding': binding.forDomain(name),
            'corrections': <dynamic>[]
          }) as Json;

  void checkBinding(Json d, String name) {
    if (canonicalJson(d['binding']) != canonicalJson(binding.forDomain(name))) {
      throw const DomainFailure('binding_changed');
    }
  }

  /// Called only by an owner-controlled migration workflow, never by HTTP or
  /// ordinary domain actions. Default phone does not send any domain traffic.
  Future<void> configureRoute(String name, DomainRoute route) =>
      transaction((s) async {
        final d = domain(s, name);
        checkBinding(d, name);
        final old = d['route'];
        if (old == 'core' && route != DomainRoute.core) {
          throw const DomainFailure('rollback_requires_migration');
        }
        if (old != 'core' &&
            route == DomainRoute.core &&
            (s['outbox'] as List).any((o) =>
                o['domain'] == name &&
                !['accepted', 'duplicate'].contains(o['state']))) {
          throw const DomainFailure('outbox_not_drained');
        }
        if (route != DomainRoute.phone) {
          d['local_dedupe_disabled'] = true;
        }
        d['route'] = route.name;
        if (old != route.name) {
          d['cursor'] = null;
          d['records'] = <String, dynamic>{};
        }
      });

  /// No wire request is changed after its first submission. A dependent edit
  /// gets its predecessor's receipt revision when sealed for the FIRST send.
  Future<String> enqueue(String name,
      {required String id,
      required String kind,
      required Json fields,
      required String actor,
      String? authorizationRef,
      int schemaVersion = 1,
      int? baseRevision,
      Future<void> Function()? phoneWrite}) async {
    if (!['user_direct', 'user_via_agent', 'agent_inferred', 'import']
            .contains(actor) ||
        (actor.startsWith('user_') && (authorizationRef?.isEmpty ?? true))) {
      throw const DomainFailure('actor_evidence_required');
    }
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(name) || id.isEmpty) {
      throw const DomainFailure('invalid_request');
    }
    if (schemaVersion != binding.schemaVersion ||
        (baseRevision != null && baseRevision < 0)) {
      throw const DomainFailure('schema_mismatch');
    }
    const allowed = {
      'create': ['data', 'provenance'],
      'patch': ['patch', 'confirm_fields'],
      'status': ['patch'],
      'ack_capture': ['processor', 'disposition'],
      'delete': ['permanent'],
      'restore': <String>[],
      'purge': <String>[],
      'merge': [
        'target_id',
        'target_base_revision',
        'target_data',
        'reference_updates'
      ],
    };
    if (!allowed.containsKey(kind) ||
        fields.keys.any((k) => !allowed[kind]!.contains(k))) {
      throw const DomainFailure('invalid_request');
    }
    final op = const Uuid().v4();
    final now = DateTime.fromMillisecondsSinceEpoch(
        clock().millisecondsSinceEpoch,
        isUtc: true);
    await transaction((s) async {
      final d = domain(s, name);
      checkBinding(d, name);
      final route = d['route'];
      final rows = s['outbox'] as List;
      final touched = <String>{id};
      if (kind == 'merge') {
        touched.add(fields['target_id'] as String);
        for (final ref in fields['reference_updates'] as List) {
          touched.add(ref['id'] as String);
        }
      }
      if (!['restore', 'delete', 'purge'].contains(kind) &&
          touched.any((target) =>
              d['records'][target]?['deleted_at'] != null ||
              (route != 'core' &&
                  d['phone_records'][target]?['deleted_at'] != null) ||
              (d['hidden_ids'] as Map? ?? {}).containsKey(target))) {
        throw const DomainFailure('deleted_target');
      }
      final predecessors = <String>{};
      for (final target in touched) {
        final last = rows
            .where((o) =>
                o['domain'] == name &&
                o['namespace'] ==
                    (route == 'shadow' ? 'shadow' : 'production') &&
                ((o['touched_ids'] as List?) ?? [o['id']]).contains(target))
            .lastOrNull;
        if (last != null &&
            !['accepted', 'duplicate'].contains(last['state'])) {
          predecessors.add(last['op_id'] as String);
        }
      }
      final prior = rows
          .where((o) =>
              o['domain'] == name &&
              o['id'] == id &&
              o['namespace'] == (route == 'shadow' ? 'shadow' : 'production'))
          .lastOrNull;
      var knownRevision = d['records'][id]?['revision'] as int? ?? 0;
      for (final previous in rows) {
        if (previous['domain'] != name ||
            previous['namespace'] !=
                (route == 'shadow' ? 'shadow' : 'production') ||
            previous['intent']['core_instance_id'] != binding.coreInstanceId ||
            !['accepted', 'duplicate'].contains(previous['state'])) {
          continue;
        }
        final saved = previous['result'];
        if (saved is! Map ||
            saved['op_id'] != previous['op_id'] ||
            saved['domain'] != name ||
            saved['outcome'] != previous['state']) {
          continue;
        }
        try {
          // Even historical hints must retain their accepted operation binding.
          // This also handles semantic_duplicate's original receipt separately.
          _validateReceipt(jsonObject(previous), jsonObject(saved),
              previous['target_state'] as String?);
        } on DomainFailure {
          continue;
        }
        final targets = saved['receipt']['targets'] as List;
        for (final target in targets) {
          if (target['id'] == id && target['revision'] > knownRevision) {
            knownRevision = target['revision'] as int;
          }
        }
        final intent = previous['intent'];
        final checkedBase = intent['target_base_revision'];
        if (intent['kind'] == 'merge' &&
            intent['target_id'] == id &&
            !targets.any((target) => target['id'] == id) &&
            checkedBase is int &&
            checkedBase > 0 &&
            checkedBase <= 9007199254740991 &&
            checkedBase > knownRevision) {
          // A successful sparse merge checked this target at exactly this base,
          // but emitted no changed-target revision. Retain that proven floor for
          // operations enqueued AFTER the merge as well as pending successors.
          knownRevision = checkedBase;
        }
      }
      final intent = <String, dynamic>{
        'domain_protocol_version': 1,
        'core_instance_id': binding.coreInstanceId,
        'op_id': op,
        'schema_version': schemaVersion,
        'kind': kind,
        'id': id,
        'base_revision': baseRevision ?? (kind == 'create' ? 0 : knownRevision),
        'created_at': now.toIso8601String(),
        'expires_at': now.add(DomainPolicy.ttl).toIso8601String(),
        'actor': actor,
        'authorization_ref': authorizationRef,
        ...copyJson(fields),
      };
      if (jsonBytes(intent) > DomainPolicy.maxOpBytes) {
        throw const DomainFailure('payload_too_large');
      }
      if (route != 'phone') {
        final pending = rows
            .where((o) => !['accepted', 'duplicate', 'rejected', 'expired']
                .contains(o['state']))
            .toList();
        if (pending.length >= maxItems ||
            pending.fold<int>(0, (n, o) => n + jsonBytes(o['intent'])) +
                    jsonBytes(intent) >
                maxBytes) {
          throw const DomainFailure('outbox_full');
        }
        rows.add({
          'op_id': op,
          'domain': name,
          'id': id,
          'intent': intent,
          'state': 'pending',
          'namespace': route == 'shadow' ? 'shadow' : 'production',
          'sealed': false,
          'predecessor': prior?['op_id'],
          'predecessors': predecessors.toList(),
          'touched_ids': touched.toList(),
          'attempts': 0,
          'next_attempt_at': null
        });
      }
      if (route != 'core') {
        if (phoneWrite != null) await phoneWrite();
        _overlay(d['phone_records'] as Json, intent);
        if (route == 'phone' && ['delete', 'purge'].contains(kind)) {
          for (final correction in d['corrections'] as List) {
            if (correction['id'] == id) correction.remove('value');
          }
        }
      }
      final patch = fields['patch'] ?? fields['data'] ?? {};
      if (actor.startsWith('user_')) {
        for (final field in (patch as Map).keys) {
          (d['corrections'] as List).add({
            'op_id': op,
            'id': id,
            'field': field,
            'actor': actor,
            'value': patch[field],
            'state': route == 'phone' ? 'phone' : 'pending'
          });
        }
      }
      await fault('enqueue_before_commit');
    });
    await fault('enqueue_after_commit');
    return op;
  }

  static void _overlay(Json records, Json intent) {
    final id = intent['id'] as String;
    if (intent['kind'] == 'delete' || intent['kind'] == 'purge') {
      final old = records[id];
      records[id] = {
        'id': id,
        'revision': old?['revision'] ?? 0,
        'local_input_version': (old?['local_input_version'] as int? ?? 0) + 1,
        'deleted_at': intent['created_at'],
        'local_delete_action': intent['op_id'],
        'body_state': 'purged',
      };
      return;
    }
    if (intent['kind'] == 'create') {
      records[id] = {
        'id': id,
        'data': copyJson(jsonObject(intent['data'])),
        'provenance': copyJson(jsonObject(intent['provenance'])),
        'local_input_version': 1,
        'revision': 0
      };
    } else if (intent['patch'] is Map) {
      final current =
          records[id] ?? {'id': id, 'data': <String, dynamic>{}, 'revision': 0};
      if ((intent['patch'] as Map).containsKey('text')) {
        current['local_input_version'] =
            (current['local_input_version'] as int? ?? 0) + 1;
      }
      current['data'] = {
        ...?current['data'] as Map?,
        ...intent['patch'] as Map
      };
      records[id] = current;
    }
  }

  /// The UI and companion receive an explicit local-only label for overlays.
  Future<List<Json>> visible(String name) async {
    final s = await read(), d = domain(s, name);
    checkBinding(d, name);
    if (d['route'] == 'core' && d['replica_requires_resync'] == true) return [];
    final source = d['route'] == 'core' ? d['records'] : d['phone_records'];
    final records = copyJson(jsonObject(source));
    if (d['route'] == 'core') {
      for (final raw in s['outbox'] as List) {
        final o = jsonObject(raw);
        if (o['domain'] != name ||
            !['pending', 'submitting'].contains(o['state'])) {
          continue;
        }
        if (records[o['id']]?['deleted_at'] != null ||
            (d['hidden_ids'] as Map? ?? {}).containsKey(o['id'])) {
          continue;
        }
        _overlay(records, jsonObject(o['intent']));
        if (records[o['id']] != null) records[o['id']]['sync_label'] = '未同步';
      }
    }
    return records.values
        .where((r) => r['deleted_at'] == null)
        .map((r) => copyJson(jsonObject(r)))
        .toList();
  }

  /// Explicit credential-view reset. Old authority requests are quarantined,
  /// never retargeted or automatically regenerated under a new principal.
  Future<void> resetCredentialView(String name) => transaction((s) async {
        final d = domain(s, name);
        d['records'] = <String, dynamic>{};
        d['cursor'] = null;
        d.remove('manifest');
        d.remove('ack_snapshot_id');
        d['binding'] = binding.forDomain(name);
        for (final o in s['outbox'] as List) {
          if (o['domain'] == name &&
              ['pending', 'submitting'].contains(o['state'])) {
            o['state'] = 'needs_resolution';
            o['reason'] = 'binding_changed';
          }
        }
      });

  Future<void> invalidateReplica(String name) => transaction((s) async {
        final d = domain(s, name);
        checkBinding(d, name);
        d['records'] = <String, dynamic>{};
        d['cursor'] = null;
        d.remove('manifest');
        d.remove('ack_snapshot_id');
      });

  void _scrubIntentPayload(Json operation) {
    for (final key in const [
      'data',
      'provenance',
      'patch',
      'target_data',
      'reference_updates',
      'disposition',
      'authorization_ref'
    ]) {
      (operation['intent'] as Map).remove(key);
    }
  }

  Future<void> runRetention() => transaction((s) async {
        for (final o in s['outbox'] as List) {
          if (!['rejected', 'expired', 'needs_resolution']
              .contains(o['state'])) {
            continue;
          }
          final expiry = DateTime.parse(o['intent']['expires_at'])
              .add(const Duration(days: 30));
          if (clock().isBefore(expiry)) continue;
          _scrubIntentPayload(jsonObject(o));
          o['payload_expired'] = true;
          if (o['result'] is Map) o['result'].remove('record');
          final d = domain(s, o['domain']);
          for (final correction in d['corrections'] as List) {
            if (correction['op_id'] == o['op_id']) correction.remove('value');
          }
        }
      });

  Future<List<Json>> problems() async => ((await read())['outbox'] as List)
      .where((o) =>
          ['needs_resolution', 'rejected', 'expired'].contains(o['state']))
      .map((o) => copyJson(jsonObject(o)))
      .toList();

  Future<List<Json>> reminders() async => ((await read())['outbox'] as List)
      .where((o) =>
          ['pending', 'submitting'].contains(o['state']) &&
          clock().difference(DateTime.parse(o['intent']['created_at'])) >=
              DomainPolicy.reminderAge)
      .map((o) =>
          {'domain': o['domain'], 'op_id': o['op_id'], 'label': '已超过 7 天未同步'})
      .toList();

  Future<Json?> prepare(String name) => transaction((s) async {
        final d = domain(s, name);
        checkBinding(d, name);
        if (d['route'] == 'phone') return null;
        final rows = s['outbox'] as List;
        for (final o in rows) {
          if (o['domain'] != name ||
              !['pending', 'submitting'].contains(o['state']) ||
              o['shadow_staged'] == true) {
            continue;
          }
          final next = o['next_attempt_at'];
          if (next != null && clock().isBefore(DateTime.parse(next))) continue;
          if (o['namespace'] !=
              (d['route'] == 'shadow' ? 'shadow' : 'production')) {
            continue;
          }
          final dependencies = (o['predecessors'] as List?) ??
              [if (o['predecessor'] != null) o['predecessor']];
          final predecessors =
              rows.where((p) => dependencies.contains(p['op_id'])).toList();
          if (predecessors
              .any((p) => !['accepted', 'duplicate'].contains(p['state']))) {
            continue;
          }
          var blocked = false;
          if (o['sealed'] != true) {
            for (final predecessor in predecessors) {
              final targets =
                  predecessor['result']?['receipt']?['targets'] as List? ?? [];
              for (final target in (o['touched_ids'] as List?) ?? [o['id']]) {
                if (!((predecessor['touched_ids'] as List?) ??
                        [predecessor['id']])
                    .contains(target)) {
                  continue;
                }
                final accepted = targets
                        .where((t) => t['id'] == target)
                        .firstOrNull ??
                    // An accepted merge may leave its target unchanged. Core
                    // checked that target at this base; it emits no new revision.
                    (predecessor['intent']['kind'] == 'merge' &&
                            predecessor['intent']['target_id'] == target
                        ? {
                            'id': target,
                            'revision': predecessor['intent']
                                ['target_base_revision']
                          }
                        : null);
                if (accepted == null ||
                    (predecessor['intent']['kind'] == 'delete' &&
                        !['restore', 'purge', 'delete']
                            .contains(o['intent']['kind']))) {
                  o['state'] = 'needs_resolution';
                  o['reason'] = 'causal_predecessor_unavailable';
                  blocked = true;
                  break;
                }
                if (target == o['id']) {
                  if (accepted['revision'] > o['intent']['base_revision']) {
                    o['intent']['base_revision'] = accepted['revision'];
                  }
                }
                if (target == o['intent']['target_id']) {
                  if (accepted['revision'] >
                      o['intent']['target_base_revision']) {
                    o['intent']['target_base_revision'] = accepted['revision'];
                  }
                }
                for (final ref
                    in o['intent']['reference_updates'] as List? ?? []) {
                  if (ref['id'] == target) {
                    if (accepted['revision'] > ref['base_revision']) {
                      ref['base_revision'] = accepted['revision'];
                    }
                  }
                }
              }
            }
          }
          if (blocked) continue;
          final queryFirst = o['sealed'] == true;
          o['sealed'] = true;
          o['state'] = 'submitting';
          await fault('submit_before_commit');
          return {...copyJson(jsonObject(o)), 'query_first': queryFirst};
        }
        return null;
      });

  Future<void> defer(String opId, String code,
          {bool requiresAction = false,
          Duration delay = const Duration(seconds: 2)}) =>
      transaction((s) async {
        final o = (s['outbox'] as List).firstWhere((o) => o['op_id'] == opId);
        if (['accepted', 'duplicate'].contains(o['state'])) return;
        o['state'] = requiresAction ? 'needs_resolution' : 'pending';
        o['reason'] = code;
        o['attempts'] = (o['attempts'] as int) + 1;
        o['next_attempt_at'] = clock().add(delay).toUtc().toIso8601String();
      });

  Future<void> complete(String opId, Json result, {String? targetState}) =>
      transaction((s) async {
        final o = (s['outbox'] as List).firstWhere((o) => o['op_id'] == opId);
        final d = domain(s, o['domain']);
        checkBinding(d, o['domain']);
        if (result['transport_state'] == 'shadow_staged' &&
            o['namespace'] == 'shadow') {
          o['shadow_staged'] = true;
          o['state'] = 'pending';
          o['shadow_result_id'] = result['shadow_result_id'];
          return;
        }
        if (o['namespace'] != 'production' ||
            result['op_id'] != opId ||
            result['domain'] != o['domain']) {
          throw const DomainFailure('invalid_response');
        }
        final outcome = result['outcome'];
        if (![
          'accepted',
          'duplicate',
          'rejected',
          'expired',
          'needs_resolution'
        ].contains(outcome)) {
          throw const DomainFailure('invalid_response');
        }
        if (['accepted', 'duplicate'].contains(outcome)) {
          _validateReceipt(o, result, targetState);
        } else if (result['receipt'] != null) {
          throw const DomainFailure('invalid_receipt');
        }
        if (['accepted', 'duplicate'].contains(o['state'])) {
          if (canonicalJson(o['result']?['receipt']) !=
              canonicalJson(result['receipt'])) {
            throw const DomainFailure('receipt_conflict');
          }
          if (targetState != 'deleted') return;
        }
        o['state'] = outcome;
        o.remove('lookup_only');
        o['result'] = copyJson(result);
        o['reason'] = result['reason'];
        if (outcome == 'accepted' || outcome == 'duplicate') {
          _scrubIntentPayload(jsonObject(o));
        }

        for (final c in d['corrections'] as List) {
          if (c['op_id'] == opId) c['state'] = outcome;
        }
        // A receipt sequence is NEVER a cursor. Readable state is provisional until
        // feed/snapshot arrives; hidden write-only results cannot invent a replica.
        if (result['record'] is Map) {
          _applyRecord(d, jsonObject(result['record']), o['domain']);
          // Keep the readable body only in the canonical replica. Receipts,
          // touched_ids and duplicate_of retain all retry/causal associations.
          (o['result'] as Map).remove('record');
        }
        if ((outcome == 'accepted' || outcome == 'duplicate') &&
            (targetState == 'deleted' ||
                ['delete', 'merge', 'purge'].contains(o['intent']['kind']))) {
          final target = (result['receipt']['targets'] as List)
              .where((t) => t['id'] == o['id'])
              .firstOrNull;
          if (target != null) {
            d.putIfAbsent('hidden_ids', () => <String, dynamic>{})[o['id']] =
                target['revision'];
            d['records'].remove(o['id']);
            _markDeletedPending(s, d, o['domain']);
          }
        }
        if (targetState == 'deleted') {
          final targets = result['receipt']?['targets'] as List? ?? [];
          final duplicate = result['reason'] == 'semantic_duplicate';
          final deletedIds = duplicate
              ? (targets.length == 1 ? {targets.single['id']} : <dynamic>{})
              // Core GET target_state is for the operation's primary id.
              // A merge deletes only its source, never its target/references.
              : {o['id']};
          if (duplicate && deletedIds.isEmpty) {
            // An original merge receipt can name several records. GET removed
            // duplicate_of, so none may be guessed as the deleted target. Drop
            // readable caches and old accepted bodies until a fresh snapshot.
            d['records'] = <String, dynamic>{};
            d['phone_records'] = <String, dynamic>{};
            for (final old in s['outbox'] as List) {
              if (old['domain'] != o['domain']) continue;
              if (old['result'] is Map) old['result'].remove('record');
              if (['accepted', 'duplicate'].contains(old['state'])) {
                _scrubIntentPayload(jsonObject(old));
              }
            }
            for (final c in d['corrections'] as List) {
              c.remove('value');
            }
          } else {
            for (final id in deletedIds) {
              final target = targets.where((t) => t['id'] == id).firstOrNull;
              final receiptRevision = target?['revision'] as int? ?? 0;
              final cachedRevision = d['records'][id]?['revision'] as int? ?? 0;
              final hidden =
                  d.putIfAbsent('hidden_ids', () => <String, dynamic>{});
              final previous = hidden[id] as int? ?? 0;
              hidden[id] = [receiptRevision, cachedRevision, previous]
                  .reduce((a, b) => a > b ? a : b);
              d['records'].remove(id);
            }
            _markDeletedPending(s, d, o['domain']);
          }
          d['cursor'] = null;
          d.remove('manifest');
          d.remove('ack_snapshot_id');
          d['replica_requires_resync'] = true;
          d['replica_version'] = (d['replica_version'] as int? ?? 0) + 1;
          o['target_state'] = 'deleted';
          for (final c in d['corrections'] as List) {
            if (c['op_id'] == opId) c.remove('value');
          }
        }
        await fault('receipt_before_commit');
      });

  void _validateReceipt(Json operation, Json result, String? targetState) {
    final receipt = jsonObject(result['receipt']);
    bool identifier(dynamic v) =>
        v is String && v.isNotEmpty && v.length <= 128;
    bool positive(dynamic v) => v is int && v > 0 && v <= 9007199254740991;
    final targets = receipt['targets'];
    final sequences = receipt['change_sequences'];
    const receiptFields = {
      'receipt_id',
      'core_instance_id',
      'authority_mode',
      'epoch',
      'domain',
      'accepted_op_id',
      'principal_id',
      'accepted_at',
      'policy_version',
      'targets',
      'change_sequences',
      'receipt_auth'
    };
    if (receipt.keys.toSet().difference(receiptFields).isNotEmpty ||
        receipt.keys.length != receiptFields.length ||
        jsonBytes(receipt) > DomainPolicy.maxOpBytes ||
        !identifier(receipt['receipt_id']) ||
        !identifier(receipt['accepted_op_id']) ||
        !identifier(receipt['principal_id']) ||
        receipt['core_instance_id'] != binding.coreInstanceId ||
        receipt['domain'] != operation['domain'] ||
        receipt['policy_version'] != binding.policyVersion ||
        receipt['authority_mode'] != 'single_host' ||
        receipt['epoch'] != null ||
        receipt['accepted_at'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
            .hasMatch(receipt['accepted_at']) ||
        DateTime.tryParse(receipt['accepted_at']) == null ||
        receipt['receipt_auth'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(receipt['receipt_auth']) ||
        targets is! List ||
        targets.isEmpty ||
        sequences is! List ||
        sequences.length != targets.length ||
        sequences.any((v) => !positive(v)) ||
        sequences.toSet().length != sequences.length) {
      throw const DomainFailure('invalid_receipt');
    }
    final ids = <String>{};
    for (final t in targets) {
      if (t is! Map ||
          t.length != 2 ||
          !identifier(t['id']) ||
          !positive(t['revision']) ||
          !ids.add(t['id'])) {
        throw const DomainFailure('invalid_receipt');
      }
    }
    if (result['record'] is Map) {
      final shown = result['record'];
      final target = targets.where((t) => t['id'] == shown['id']).firstOrNull;
      if (target == null || target['revision'] != shown['revision']) {
        throw const DomainFailure('invalid_receipt_binding');
      }
    }
    final outcome = result['outcome'], reason = result['reason'];
    final expected =
        ((operation['touched_ids'] as List?) ?? [operation['id']]).toSet();
    if (outcome == 'accepted' || reason == 'idempotent_replay') {
      // Merge always changes the source and supplied references, but Core only
      // includes the target when target_data actually changes it.
      final required = {...expected};
      if (operation['intent']['kind'] == 'merge') {
        required.remove(operation['intent']['target_id']);
      }
      if (receipt['accepted_op_id'] != operation['op_id'] ||
          receipt['principal_id'] != binding.principalId ||
          !expected.containsAll(ids) ||
          !ids.containsAll(required)) {
        throw const DomainFailure('invalid_receipt_binding');
      }
    } else if (reason == 'semantic_duplicate') {
      if (operation['intent']['kind'] != 'create' ||
          (targetState != 'deleted' &&
              (!identifier(result['duplicate_of']) ||
                  !ids.contains(result['duplicate_of'])))) {
        throw const DomainFailure('invalid_receipt_binding');
      }
    } else if (reason == 'no_change' || reason == 'already_purged') {
      final allowed = reason == 'no_change'
          ? ['patch', 'status', 'ack_capture']
          : ['purge'];
      if (!allowed.contains(operation['intent']['kind']) ||
          !ids.contains(operation['id'])) {
        throw const DomainFailure('invalid_receipt_binding');
      }
    } else {
      throw const DomainFailure('invalid_receipt_binding');
    }
  }

  void _applyRecord(Json d, Json r, String name) {
    if (r['domain'] != name ||
        r['core_instance_id'] != binding.coreInstanceId ||
        r['id'] is! String ||
        r['revision'] is! int ||
        r['revision'] < 1 ||
        r['revision'] > 9007199254740991 ||
        jsonBytes(r) > DomainPolicy.maxOpBytes) {
      throw const DomainFailure('invalid_record');
    }
    if (r['deleted_at'] != null && r.containsKey('data')) {
      throw const DomainFailure('invalid_tombstone');
    }
    final hidden = d['hidden_ids']?[r['id']];
    if (hidden != null && r['deleted_at'] == null && r['revision'] <= hidden) {
      return;
    }
    if (hidden != null && r['revision'] > hidden) {
      d['hidden_ids'].remove(r['id']);
    }
    final old = d['records'][r['id']];
    if (old == null || r['revision'] > old['revision']) {
      d['records'][r['id']] = copyJson(r);
      d['replica_version'] = (d['replica_version'] as int? ?? 0) + 1;
    }
  }

  Future<void> applyPage(String name, Json page,
          {String? expectedCursor, bool compareCursor = false}) =>
      transaction((s) async {
        final d = domain(s, name);
        checkBinding(d, name);
        if (compareCursor && d['cursor'] != expectedCursor) {
          throw const DomainFailure('stale_response');
        }
        if (page['next_cursor'] is! String ||
            page['policy_version'] != binding.policyVersion ||
            jsonBytes(page) > DomainPolicy.maxPageBytes) {
          throw const DomainFailure('invalid_page');
        }
        for (final r in page['records'] as List) {
          _applyRecord(d, jsonObject(r), name);
        }
        _markDeletedPending(s, d, name);
        d['cursor'] = page['next_cursor'];
        d['ack_snapshot_id'] = null;
        await fault('feed_before_commit');
      });

  void _markDeletedPending(Json s, Json d, String name) {
    final deleted = (d['records'] as Map)
        .entries
        .where((e) => e.value['deleted_at'] != null)
        .map((e) => e.key)
        .toSet()
      ..addAll((d['hidden_ids'] as Map? ?? {}).keys);
    for (final id in deleted) {
      d['phone_records'].remove(id);
    }
    for (final c in d['corrections'] as List) {
      if (deleted.contains(c['id'])) c.remove('value');
    }
    for (final o in s['outbox'] as List) {
      if (o['domain'] != name) continue;
      final result = o['result'];
      final linkedIds = <dynamic>{
        ...(o['touched_ids'] as List? ?? [o['id']]),
        if (result is Map) result['duplicate_of'],
        if (result is Map) result['record']?['id']
      };
      if (!linkedIds.any(deleted.contains)) continue;
      if (result is Map) result.remove('record');
      _scrubIntentPayload(jsonObject(o));
      for (final c in d['corrections'] as List) {
        if (c['op_id'] == o['op_id']) c.remove('value');
      }
      o['payload_purged'] = true;
      if (['pending', 'submitting'].contains(o['state'])) {
        if (o['sealed'] == true) {
          // The tombstone can be this very operation's committed effect after
          // its response was lost. Keep its durable identity queryable, but its
          // scrubbed body can never be submitted again, even after a 404.
          o['state'] = 'pending';
          o['lookup_only'] = true;
          o['reason'] = 'deleted_target_lookup_required';
        } else {
          o['state'] = 'needs_resolution';
          o['reason'] = 'deleted_target';
        }
      }
    }
  }

  Future<void> replaceSnapshot(String name, List<Json> records, Json manifest,
          {String? expectedCursor,
          bool compareCursor = false,
          int? expectedReplicaVersion}) =>
      transaction((s) async {
        final d = domain(s, name);
        checkBinding(d, name);
        if (compareCursor && d['cursor'] != expectedCursor) {
          throw const DomainFailure('stale_response');
        }
        if (expectedReplicaVersion != null &&
            (d['replica_version'] ?? 0) != expectedReplicaVersion) {
          throw const DomainFailure('stale_response');
        }
        d['replica_version'] = (d['replica_version'] as int? ?? 0) + 1;
        d['records'] = <String, dynamic>{};
        for (final r in records) {
          _applyRecord(d, r, name);
        }
        _markDeletedPending(s, d, name);
        d.remove('replica_requires_resync');
        d['cursor'] = manifest['base_cursor'];
        d['manifest'] = copyJson(manifest);
        d['ack_snapshot_id'] = manifest['snapshot_id'];
        await fault('snapshot_before_commit');
      });
}
