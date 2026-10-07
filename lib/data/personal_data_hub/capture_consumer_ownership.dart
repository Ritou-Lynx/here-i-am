import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:memex/db/app_database.dart';
import 'capture_owner_migration.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';

/// The Gate owner supplies verified origin/adoption evidence. A UI toggle,
/// equal text, or equal note/capture ID is not proof. No production verifier is
/// registered until the real create/revise/delete Gate has passed.
@Deprecated('Use the signed CaptureMigrationManifest adoption workflow')
class CoreCaptureTakeover {
  const CoreCaptureTakeover(
      {required this.gateRef,
      required this.coreInstanceId,
      required this.bindingFingerprint,
      required this.adoptionProof,
      required this.noteToCapture});
  final String gateRef, coreInstanceId, bindingFingerprint, adoptionProof;
  final Map<String, String> noteToCapture;
  Json toJson() => {
        'gate_ref': gateRef,
        'core_instance_id': coreInstanceId,
        'binding_fingerprint': bindingFingerprint,
        'adoption_proof': adoptionProof,
        'note_to_capture': noteToCapture
      };
}

/// Short SQLite writer transactions protect admission, renewal and fencing.
/// No transaction is held during network/model work. A killed process's lease
/// expires; the next owner increments its generation before proceeding.
class CaptureConsumerOwnership {
  CaptureConsumerOwnership(this.db,
      {DateTime Function()? clock,
      this.leaseDuration = const Duration(seconds: 60),
      this.heartbeatInterval = const Duration(seconds: 15),
      CaptureAdoptionProofVerifier? adoptionVerifier})
      : _adoptionVerifier = adoptionVerifier,
        clock = clock ?? DateTime.now;
  static final _instances = Expando<CaptureConsumerOwnership>();
  static CaptureConsumerOwnership forDatabase(AppDatabase db) =>
      _instances[db] ??= CaptureConsumerOwnership(db);
  final AppDatabase db;
  final DateTime Function() clock;
  final Duration leaseDuration, heartbeatInterval;
  CaptureAdoptionProofVerifier? _adoptionVerifier;
  void configureAdoptionVerifier(CaptureAdoptionProofVerifier? verifier) {
    _adoptionVerifier = verifier;
  }

  static const _key = 'capture_consumer_ownership.v1';
  static const _bucket = 'capture_consumer_ownership';
  Future<void> _queue = Future.value();
  bool _suspended = false;
  Future<void> suspend() {
    _suspended = true;
    return _queue;
  }

  void resume() {
    _suspended = false;
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final future = _queue.then((_) => action());
    _queue = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  Future<void> _lock() =>
      db.customStatement('UPDATE kv_store SET updated_at=updated_at WHERE 0');
  Future<Json> _read() async {
    final rows = await db.customSelect('SELECT value FROM kv_store WHERE key=?',
        variables: [const Variable(_key)]).get();
    return rows.isEmpty
        ? {'owner': 'legacy', 'generation': 0}
        : jsonObject(jsonDecode(rows.single.read<String>('value')));
  }

  Future<void> _save(Json state) => db.customStatement(
      'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?) '
      'ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at',
      [_key, jsonEncode(state), _bucket, clock().millisecondsSinceEpoch]);
  bool _active(Json s) =>
      s['token'] != null &&
      (s['expires_at'] as int) > clock().millisecondsSinceEpoch;

  Future<bool> coreSelected() async => (await _read())['owner'] == 'core';

  Future<CaptureConsumerLease> _claim(String? requiredOwner) =>
      db.transaction(() async {
        await _lock();
        final state = await _read();
        if (requiredOwner != null && state['owner'] != requiredOwner) {
          throw const DomainFailure('capture_owner_mismatch');
        }
        if (requiredOwner == 'legacy' && state['migration'] != null) {
          throw const DomainFailure('capture_migration_frozen');
        }
        if (_active(state)) throw const DomainFailure('capture_consumer_busy');
        final token = const Uuid().v4();
        final generation = (state['generation'] as int) + 1;
        await _save({
          ...state,
          'token': token,
          'generation': generation,
          'expires_at': clock().add(leaseDuration).millisecondsSinceEpoch
        });
        return CaptureConsumerLease._(this, token, generation);
      });

  Future<T> _run<T>(String? owner,
          Future<T> Function(CaptureConsumerLease lease) action) =>
      _serial(() async {
        if (_suspended) throw const DomainFailure('capture_owner_suspended');
        final lease = await _claim(owner);
        Future<void>? renewing;
        final timer = Timer.periodic(heartbeatInterval, (_) {
          if (renewing != null) return;
          final next = lease.renew().catchError((Object _) {});
          renewing = next;
          unawaited(next.whenComplete(() => renewing = null));
        });
        try {
          return await action(lease);
        } finally {
          timer.cancel();
          await renewing;
          await lease.release();
        }
      });
  Future<T> runLegacy<T>(Future<T> Function(CaptureConsumerLease) action) =>
      _run('legacy', action);
  Future<T> runCore<T>(Future<T> Function(CaptureConsumerLease) action,
          {required String bindingFingerprint}) =>
      _run('core', (lease) async {
        final state = await _read();
        final manifestRaw = state['manifest'];
        final proofRaw = state['proof'];
        final verifier = _adoptionVerifier;
        if (manifestRaw is! Map || proofRaw is! Map || verifier == null) {
          throw const DomainFailure('capture_core_gate_required');
        }
        final manifest = CaptureMigrationManifest(jsonObject(manifestRaw));
        if (state['binding_fingerprint'] != bindingFingerprint ||
            state['binding_fingerprint'] !=
                canonicalJson(verifier.consumerBinding)) {
          throw const DomainFailure('binding_changed');
        }
        final verifiedAt =
            DateTime.tryParse(state['verified_at'] as String? ?? '');
        if (verifiedAt == null) {
          throw const DomainFailure('capture_core_gate_required');
        }
        await verifier.verifyCommitted(
            jsonObject(proofRaw), manifest, verifiedAt);
        await lease.verify();
        return action(lease);
      });

  /// Configuration changes queue behind this instance's entire import+ACK.
  /// Another active instance returns busy instead of cancelling its receipt.
  Future<T> configure<T>(Future<T> Function() action) =>
      _run(null, (lease) => lease.fenced(action));

  /// The old free-form bool/string takeover path is deliberately closed.
  Future<void> selectCore(CoreCaptureTakeover _) async {
    throw const DomainFailure('capture_core_gate_required');
  }

  Future<CaptureMigrationManifest> freezeCaptureMigration({
    required DomainStore store,
    required String migrationId,
    required String sourceInstanceId,
    required int sourceCursor,
  }) =>
      _run('legacy', (lease) async {
        if (!identical(store.db, db)) {
          throw const DomainFailure('database_mismatch');
        }
        final verifier = _adoptionVerifier;
        if (verifier == null) {
          throw const DomainFailure('capture_core_gate_required');
        }
        final first = await buildCaptureMigrationManifest(
            db: db,
            migrationId: migrationId,
            binding: verifier.binding,
            sourceInstanceId: sourceInstanceId,
            sourceCursor: sourceCursor);
        await lease.fenced(() async {
          final current = await buildCaptureMigrationManifest(
              db: db,
              migrationId: migrationId,
              binding: verifier.binding,
              sourceInstanceId: sourceInstanceId,
              sourceCursor: sourceCursor);
          if (current.digest != first.digest) {
            throw const DomainFailure('capture_migration_changed');
          }
          final storeState = await store.read();
          final domain = store.domain(storeState, 'captures');
          store.checkBinding(domain, 'captures');
          if (domain['route'] != 'phone') {
            throw const DomainFailure('migration_route_changed');
          }
          if ((storeState['outbox'] as List).any((operation) =>
              operation['domain'] == 'captures' &&
              !['accepted', 'duplicate'].contains(operation['state']))) {
            throw const DomainFailure('outbox_not_drained');
          }
          final state = await _read();
          await _save({...state, 'migration': copyJson(first.value)});
        });
        return first;
      });

  Future<void> abortCaptureMigration(String migrationId) => _run(
      null,
      (lease) => lease.fenced(() async {
            final state = await _read();
            final migration = state['migration'];
            if (state['owner'] != 'legacy' ||
                migration is! Map ||
                migration['migration_id'] != migrationId) {
              throw const DomainFailure('capture_migration_mismatch');
            }
            state.remove('migration');
            await _save(state);
          }));

  Future<void> commitCaptureMigration({
    required DomainStore store,
    required Json adoptionProof,
    required CaptureAdoptionReceiptRefetch refetchCurrentReceipt,
  }) =>
      _run(null, (lease) async {
        if (!identical(store.db, db)) {
          throw const DomainFailure('database_mismatch');
        }
        final state = await _read();
        final frozenRaw = state['migration'];
        final verifier = _adoptionVerifier;
        if (state['owner'] != 'legacy' ||
            frozenRaw is! Map ||
            verifier == null) {
          throw const DomainFailure('capture_migration_mismatch');
        }
        final frozen = CaptureMigrationManifest(jsonObject(frozenRaw));
        final verified = await verifier.verify(adoptionProof, frozen);
        for (final raw in verified.details['entries'] as List) {
          final entry = jsonObject(raw);
          final receipt = await refetchCurrentReceipt(copyJson(entry));
          verifier.verifyCurrentReceipt(entry, receipt);
        }
        verifier.checkFreshWindow(adoptionProof);
        await store.commitCoreMigration('captures', () async {
          await lease.verify();
          final current = await buildCaptureMigrationManifest(
              db: db,
              migrationId: frozen.migrationId,
              binding: verifier.binding,
              sourceInstanceId: frozen.source['source_instance_id'] as String,
              sourceCursor:
                  int.parse(frozen.source['source_cursor'] as String));
          if (current.digest != frozen.digest) {
            throw const DomainFailure('capture_migration_changed');
          }
          final latest = await _read();
          if (latest['owner'] != 'legacy' ||
              canonicalJson(latest['migration']) !=
                  canonicalJson(frozen.value)) {
            throw const DomainFailure('capture_migration_changed');
          }
          verifier.checkFreshWindow(adoptionProof);
          await _seedAdoptedLedgers(frozen, verified);
          final verifiedAt =
              verifier.checkFreshWindow(adoptionProof).toIso8601String();
          await _save({
            ...latest,
            'owner': 'core',
            'manifest': copyJson(frozen.value),
            'proof': copyJson(verified.value),
            'binding_fingerprint': canonicalJson(verifier.consumerBinding),
            'verified_at': verifiedAt,
          }..remove('migration'));
        });
      });

  Future<void> _seedAdoptedLedgers(CaptureMigrationManifest manifest,
      VerifiedCaptureAdoptionProof proof) async {
    final records = {
      for (final record in manifest.records) record['source_id']: record
    };
    for (final raw in proof.details['entries'] as List) {
      final entry = jsonObject(raw);
      final record = records[entry['source_id']]!;
      final key =
          'capture_lifecycle.${proof.binding['core_instance_id']}.${entry['target_id']}';
      final existing = await db.customSelect(
          'SELECT value FROM kv_store WHERE key=? AND bucket=?',
          variables: [Variable(key), const Variable('capture_consumer')]).get();
      if (existing.isNotEmpty) {
        throw const DomainFailure('capture_adoption_ledger_conflict');
      }
      await db.customStatement(
          'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?)', [
        key,
        jsonEncode({
          'schema': 1,
          'capture_id': entry['target_id'],
          'input_version': entry['target_revision'],
          'deleted': entry['is_tombstone'],
          'source': 'i_remember',
          'slots': record['slots'],
          'removed_ids': <String>[],
          'issues': record['issues'],
          'adopted': true,
          'legacy_note_id': entry['source_id'],
          'projection_source_ref': record['projection_source_ref'],
          'adoption_proof': proof.proofRef,
          'adopted_op_id': entry['adopted_op_id'],
          'receipt_id': entry['receipt_id'],
        }),
        'capture_consumer',
        clock().millisecondsSinceEpoch,
      ]);
    }
  }
  // A reverse transition also needs proof; do not silently fall back to legacy
  // after core has consumed new sources. Reversal is deliberately not exposed.
}

class CaptureConsumerLease {
  CaptureConsumerLease._(this._owner, this.token, this.generation);
  final CaptureConsumerOwnership _owner;
  final String token;
  final int generation;
  Future<void> verify() async {
    final state = await _owner._read();
    if (state['token'] != token ||
        state['generation'] != generation ||
        !_owner._active(state)) {
      throw const DomainFailure('capture_consumer_fenced');
    }
  }

  /// Call inside an existing writer transaction, or use fenced for a local
  /// commit. Import/receipt/cursor writes can never race a lease takeover.
  Future<T> fenced<T>(Future<T> Function() action) =>
      _owner.db.transaction(() async {
        await _owner._lock();
        await verify();
        return action();
      });
  Future<void> renew() => fenced(() async {
        final state = await _owner._read();
        await _owner._save({
          ...state,
          'expires_at':
              _owner.clock().add(_owner.leaseDuration).millisecondsSinceEpoch
        });
      });
  Future<void> release() => _owner.db.transaction(() async {
        await _owner._lock();
        final state = await _owner._read();
        if (state['token'] == token && state['generation'] == generation) {
          state.remove('token');
          state.remove('expires_at');
          await _owner._save(state);
        }
      });
}
