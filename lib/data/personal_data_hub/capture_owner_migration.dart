import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

import 'domain_http_transport.dart';
import 'domain_protocol.dart';

/// Immutable, content-addressed view of the legacy note consumer's durable
/// receipts and current outputs. It contains no source text or credentials.
class CaptureMigrationManifest {
  const CaptureMigrationManifest(this.value);
  final Json value;

  String get migrationId => value['migration_id'] as String;
  Json get binding => jsonObject(value['binding']);
  Json get source => jsonObject(value['source']);
  List<Json> get records => (value['records'] as List).map(jsonObject).toList();
  String get digest => domainDigest(value);
}

class VerifiedCaptureAdoptionProof {
  const VerifiedCaptureAdoptionProof(this.value);
  final Json value;
  String get migrationId => value['migration_id'] as String;
  Json get binding => jsonObject(value['binding']);
  Json get source => jsonObject(value['source']);
  Json get details => jsonObject(value['details']);
  String get proofRef => value['proof_ref'] as String;
}

/// Authenticated fields returned by a fresh Core operation/receipt lookup.
/// Its adapter validates the transport response and receipt authentication;
/// a caller-provided boolean is deliberately not an acceptance claim.
class CurrentCoreAdoptionReceipt {
  const CurrentCoreAdoptionReceipt({
    required this.status,
    required this.domain,
    required this.coreInstanceId,
    required this.principalId,
    required this.policyVersion,
    required this.sourceId,
    required this.sourceRevision,
    required this.targetId,
    required this.targetRevision,
    required this.acceptedOpId,
    required this.receiptId,
    required this.receiptAuth,
    required this.adoptionBindingDigest,
  });
  final String status,
      domain,
      coreInstanceId,
      principalId,
      policyVersion,
      sourceId,
      targetId,
      acceptedOpId,
      receiptId,
      receiptAuth,
      adoptionBindingDigest;
  final int sourceRevision, targetRevision;
}

typedef CaptureAdoptionReceiptRefetch = Future<CurrentCoreAdoptionReceipt>
    Function(Json adoptionEntry);

CaptureAdoptionReceiptRefetch createCaptureAdoptionReceiptRefetch(
    DomainHttpTransport transport, CoreDomainAccessGrant grant) {
  if (transport.binding.coreInstanceId != grant.coreInstanceId ||
      transport.binding.principalId != grant.principalId ||
      transport.binding.generation != grant.credentialGeneration ||
      transport.binding.installationId != grant.installationId) {
    throw const DomainFailure('binding_changed');
  }
  return (entry) async {
    final operation =
        await transport.operation('captures', entry['adopted_op_id'] as String);
    final result = jsonObject(operation['result']);
    final receipt = jsonObject(result['receipt']);
    const fields = {
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
      'adoption_binding_digest',
      'receipt_auth',
    };
    final targets = receipt['targets'];
    final target = targets is List && targets.length == 1
        ? jsonObject(targets.single)
        : null;
    if (operation['found'] != true ||
        !const {'accepted', 'duplicate'}.contains(result['outcome']) ||
        result['op_id'] != entry['adopted_op_id'] ||
        receipt.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(receipt.keys.toSet()).isNotEmpty ||
        receipt['receipt_id'] != entry['receipt_id'] ||
        receipt['core_instance_id'] != grant.coreInstanceId ||
        receipt['principal_id'] != grant.principalId ||
        receipt['policy_version'] != grant.policyVersion ||
        receipt['domain'] != 'captures' ||
        receipt['authority_mode'] != 'single_host' ||
        receipt['epoch'] != null ||
        receipt['accepted_op_id'] != entry['adopted_op_id'] ||
        receipt['receipt_auth'] != entry['receipt_auth'] ||
        receipt['adoption_binding_digest'] !=
            entry['adoption_binding_digest'] ||
        receipt['receipt_auth'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(receipt['receipt_auth']) ||
        receipt['adoption_binding_digest'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$')
            .hasMatch(receipt['adoption_binding_digest']) ||
        target == null ||
        target.keys.toSet().difference(const {'id', 'revision'}).isNotEmpty ||
        target.length != 2 ||
        target['id'] != entry['target_id'] ||
        target['revision'] != entry['target_revision']) {
      throw const DomainFailure('capture_adoption_receipt_mismatch');
    }
    final current =
        await transport.currentRecord('captures', entry['target_id'] as String);
    final record = jsonObject(current['record']);
    final deleted = current['deleted'] == true;
    if (current['policy_version'] != grant.policyVersion ||
        record['id'] != entry['target_id'] ||
        record['revision'] != entry['target_revision'] ||
        record['core_instance_id'] != grant.coreInstanceId ||
        record['domain'] != 'captures' ||
        deleted != entry['is_tombstone'] ||
        operation['target_state'] != (deleted ? 'deleted' : 'present') ||
        (!deleted &&
            (record['provenance'] is! Map ||
                record['provenance']['source'] != 'i_remember'))) {
      throw const DomainFailure('capture_adoption_record_changed');
    }
    return CurrentCoreAdoptionReceipt(
      status: result['outcome'] as String,
      domain: receipt['domain'] as String,
      coreInstanceId: receipt['core_instance_id'] as String,
      principalId: receipt['principal_id'] as String,
      policyVersion: receipt['policy_version'] as String,
      sourceId: entry['source_id'] as String,
      sourceRevision: entry['source_revision'] as int,
      targetId: target['id'] as String,
      targetRevision: target['revision'] as int,
      acceptedOpId: receipt['accepted_op_id'] as String,
      receiptId: receipt['receipt_id'] as String,
      receiptAuth: receipt['receipt_auth'] as String,
      adoptionBindingDigest: receipt['adoption_binding_digest'] as String,
    );
  };
}

/// Verifies Core's owner-controlled adoption report. Trusted App code holds the
/// shared HMAC secret, so this is channel/binding integrity rather than an
/// asymmetric claim against the App. Protocol separation, owner/adopt scopes,
/// historical witnesses, and fresh authenticated receipt lookup form the Gate.
class CaptureAdoptionProofVerifier {
  CaptureAdoptionProofVerifier(this.grant,
      {DateTime Function()? clock, Future<void> Function()? verifyCredential})
      : clock = clock ?? DateTime.now,
        _verifyCredential = verifyCredential,
        _secret = _decodeSecret(grant.authorization.secret);

  final CoreDomainAccessGrant grant;
  final DateTime Function() clock;
  final Future<void> Function()? _verifyCredential;
  final List<int> _secret;

  Json get binding => {
        'core_instance_id': grant.coreInstanceId,
        'principal_id': grant.principalId,
        'credential_generation': grant.credentialGeneration,
        'installation_id': grant.installationId,
      };
  Json get consumerBinding => DomainBinding(
        coreInstanceId: grant.coreInstanceId,
        principalId: grant.principalId,
        generation: grant.credentialGeneration,
        installationId: grant.installationId,
        policyVersion: grant.policyVersion,
        schemaVersion: grant.schemaVersion,
      ).forDomain('captures');

  Future<VerifiedCaptureAdoptionProof> verify(
          Json raw, CaptureMigrationManifest manifest) =>
      _verify(raw, manifest);

  Future<VerifiedCaptureAdoptionProof> verifyCommitted(
          Json raw, CaptureMigrationManifest manifest, DateTime verifiedAt) =>
      _verify(raw, manifest, committedAt: verifiedAt);

  Future<VerifiedCaptureAdoptionProof> _verify(
      Json raw, CaptureMigrationManifest manifest,
      {DateTime? committedAt}) async {
    await _verifyCredential?.call();
    _exact(raw, const {
      'protocol',
      'phase',
      'migration_id',
      'domain',
      'binding',
      'source',
      'prior_proof_digest',
      'details',
      'issued_at',
      'expires_at',
      'proof_ref'
    });
    if (raw['protocol'] != 'i-domain-migration-v1' ||
        raw['phase'] != 'adopt' ||
        raw['domain'] != 'captures' ||
        raw['migration_id'] != manifest.migrationId ||
        raw['prior_proof_digest'] != null ||
        canonicalJson(raw['binding']) != canonicalJson(binding) ||
        canonicalJson(raw['source']) != canonicalJson(manifest.source)) {
      throw const DomainFailure('capture_adoption_proof_invalid');
    }
    if (!grant.scopes.contains('captures:adopt') ||
        !grant.scopes.contains('captures:owner')) {
      throw const DomainFailure('scope_forbidden');
    }
    _checkWindow(raw, committedAt: committedAt);
    final details = jsonObject(raw['details']);
    _exact(details, const {
      'batch_id',
      'mapping_version',
      'entries',
      'entries_digest',
      'pending_ops',
      'conflict_count'
    });
    if (!_id(details['batch_id']) ||
        !_id(details['mapping_version']) ||
        details['pending_ops'] != 0 ||
        details['conflict_count'] != 0) {
      throw const DomainFailure('capture_adoption_incomplete');
    }
    final entries = (details['entries'] as List?)?.map(jsonObject).toList();
    if (entries == null ||
        entries.isEmpty ||
        entries.length > 5000 ||
        entries.length != manifest.records.length ||
        details['entries_digest'] != domainDigest(entries)) {
      throw const DomainFailure('capture_adoption_incomplete');
    }
    final expected = {
      for (final item in manifest.records) item['source_id']: item
    };
    final captures = <String>{}, sources = <String>{};
    for (final entry in entries) {
      _exact(entry, const {
        'source_id',
        'source_revision',
        'source_digest',
        'target_id',
        'target_revision',
        'is_tombstone',
        'adopted_op_id',
        'receipt_id',
        'receipt_auth',
        'adoption_binding_digest',
        'output_ids',
        'output_digest'
      });
      final local = expected.remove(entry['source_id']);
      final outputIds = (entry['output_ids'] as List?)?.cast<String>();
      if (local == null ||
          !sources.add(entry['source_id'] as String) ||
          entry['source_revision'] != local['source_revision'] ||
          entry['target_id'] != entry['source_id'] ||
          entry['target_revision'] != entry['source_revision'] ||
          entry['source_digest'] != local['source_digest'] ||
          entry['output_digest'] != local['output_digest'] ||
          canonicalJson(outputIds) != canonicalJson(local['output_ids']) ||
          entry['is_tombstone'] != (local['op'] == 'delete') ||
          entry['target_revision'] is! int ||
          (entry['target_revision'] as int) < 1 ||
          !_id(entry['target_id']) ||
          !_id(entry['adopted_op_id']) ||
          !_id(entry['receipt_id']) ||
          entry['receipt_auth'] is! String ||
          (entry['receipt_auth'] as String).isEmpty ||
          !_digest(entry['adoption_binding_digest']) ||
          !captures.add(entry['target_id'] as String)) {
        throw const DomainFailure('capture_adoption_incomplete');
      }
    }
    if (expected.isNotEmpty) {
      throw const DomainFailure('capture_adoption_incomplete');
    }
    final proofRef = raw['proof_ref'];
    final match = proofRef is String
        ? RegExp(r'^mig1\.([A-Za-z0-9_-]{1,40})\.([A-Za-z0-9_-]{43})$')
            .firstMatch(proofRef)
        : null;
    if (match == null || match.group(1) != grant.authorization.keyId) {
      throw const DomainFailure('capture_adoption_proof_invalid');
    }
    final unsigned = copyJson(raw)..remove('proof_ref');
    final mac = base64UrlEncode(Hmac(sha256, _secret)
            .convert(utf8.encode(canonicalJson(unsigned)))
            .bytes)
        .replaceAll('=', '');
    if (!_constantTimeEquals(match.group(2)!, mac)) {
      throw const DomainFailure('capture_adoption_proof_invalid');
    }
    return VerifiedCaptureAdoptionProof(copyJson(raw));
  }

  /// Synchronous commit-time check. It is safe inside the SQLite transaction
  /// and performs no credential, network, or storage access.
  DateTime checkFreshWindow(Json raw) => _checkWindow(raw);

  DateTime _checkWindow(Json raw, {DateTime? committedAt}) {
    final issuedText = raw['issued_at'];
    final expiresText = raw['expires_at'];
    final timestampPattern =
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');
    final issued = issuedText is String && timestampPattern.hasMatch(issuedText)
        ? DateTime.tryParse(issuedText)
        : null;
    final expires =
        expiresText is String && timestampPattern.hasMatch(expiresText)
            ? DateTime.tryParse(expiresText)
            : null;
    final at = (committedAt ?? clock()).toUtc();
    if (issued == null ||
        expires == null ||
        !expires.isAfter(issued) ||
        expires.difference(issued) > const Duration(hours: 24) ||
        at.isBefore(issued.toUtc()) ||
        !expires.toUtc().isAfter(at)) {
      throw const DomainFailure('capture_adoption_proof_expired');
    }
    return at;
  }

  void verifyCurrentReceipt(Json entry, CurrentCoreAdoptionReceipt receipt) {
    if (!const {'accepted', 'duplicate'}.contains(receipt.status) ||
        receipt.domain != 'captures' ||
        receipt.coreInstanceId != grant.coreInstanceId ||
        receipt.principalId != grant.principalId ||
        receipt.policyVersion != grant.policyVersion ||
        receipt.sourceId != entry['source_id'] ||
        receipt.sourceRevision != entry['source_revision'] ||
        receipt.targetId != entry['target_id'] ||
        receipt.targetRevision != entry['target_revision'] ||
        receipt.acceptedOpId != entry['adopted_op_id'] ||
        receipt.receiptId != entry['receipt_id'] ||
        receipt.receiptAuth != entry['receipt_auth']) {
      throw const DomainFailure('capture_adoption_receipt_mismatch');
    }
    if (receipt.adoptionBindingDigest != entry['adoption_binding_digest'] ||
        !_digest(receipt.adoptionBindingDigest)) {
      throw const DomainFailure('capture_adoption_receipt_mismatch');
    }
  }

  static void _exact(Json value, Set<String> keys) {
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty) {
      throw const DomainFailure('capture_adoption_proof_invalid');
    }
  }

  static bool _id(Object? value) =>
      value is String &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$').hasMatch(value);
  static bool _digest(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  static List<int> _decodeSecret(String value) {
    final bytes = base64Url.decode(value.padRight(44, '='));
    if (value.length != 43 ||
        bytes.length != 32 ||
        base64UrlEncode(bytes).replaceAll('=', '') != value) {
      throw const FormatException('invalid migration verification key');
    }
    return bytes;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}

/// Builds a manifest from durable receipts and the full current Memory V3
/// projection. Missing baselines are blocked instead of reconstructed.
Future<CaptureMigrationManifest> buildCaptureMigrationManifest({
  required AppDatabase db,
  required String migrationId,
  required Json binding,
  required String sourceInstanceId,
  required int sourceCursor,
}) async {
  if (!CaptureAdoptionProofVerifier._id(migrationId) ||
      !CaptureAdoptionProofVerifier._id(sourceInstanceId) ||
      sourceCursor < 0) {
    throw const DomainFailure('capture_migration_invalid');
  }
  final receiptRows = await (db.select(db.memoryCardOperations)
        ..where((t) =>
            t.sourceKind.equals('claude_web_note') &
            t.operationType.equals('external_note_import')))
      .get();
  final latest = <String, Json>{};
  final latestWitnessCount = <String, int>{};
  for (final row in receiptRows) {
    final receipt = jsonObject(jsonDecode(row.payload));
    final note = receipt['note_id'];
    final revision = receipt['revision'];
    if (note is! String || revision is! int || revision < 1) {
      throw const DomainFailure('capture_migration_unresolved');
    }
    if (latest[note] == null || revision > latest[note]!['revision']) {
      latest[note] = receipt;
      latestWitnessCount[note] = 1;
    } else if (revision == latest[note]!['revision']) {
      latestWitnessCount[note] = (latestWitnessCount[note] ?? 1) + 1;
    }
  }
  if (latest.isEmpty || latest.length > 5000) {
    throw const DomainFailure('capture_migration_unresolved');
  }
  final records = <Json>[];
  for (final note in latest.keys.toList()..sort()) {
    final receipt = latest[note]!;
    if (latestWitnessCount[note] != 1) {
      throw const DomainFailure('capture_migration_unresolved');
    }
    final slots = receipt['slots'];
    final outputIds = (receipt['card_ids'] as List?)?.cast<String>();
    if (slots is! List ||
        outputIds == null ||
        !const {'upsert', 'delete'}.contains(receipt['op']) ||
        receipt['projection_source_ref'] is! String) {
      throw const DomainFailure('capture_migration_unresolved');
    }
    final slotById = <String, Json>{};
    for (final raw in slots) {
      final slot = jsonObject(raw);
      if (slot['id'] is! String ||
          slotById.containsKey(slot['id']) ||
          slot['legacy'] == true ||
          slot['snapshot'] is! String) {
        throw const DomainFailure('capture_migration_unresolved');
      }
      slotById[slot['id'] as String] = slot;
    }
    final issues = (receipt['issues'] as List? ?? const []);
    final liveOutputIds = receipt['op'] == 'delete'
        ? slotById.keys.toList()
        : outputIds.toSet().toList();
    if (issues.isNotEmpty ||
        (receipt['op'] != 'delete' &&
            (slotById.keys.toSet().difference(outputIds.toSet()).isNotEmpty ||
                outputIds
                    .toSet()
                    .difference(slotById.keys.toSet())
                    .isNotEmpty))) {
      // Modified, missing, ambiguous, and pre-baseline cards stay owned by the
      // legacy consumer. Their current rows are never promoted to a baseline.
      throw const DomainFailure('capture_migration_unresolved');
    }
    final outputs = <Json>[];
    for (final id in liveOutputIds..sort()) {
      final output = await _captureOutput(
          db, id, receipt['projection_source_ref'] as String);
      if (output == null && receipt['op'] != 'delete') {
        throw const DomainFailure('capture_migration_unresolved');
      }
      if (output != null) {
        if (output['finance'] == true) {
          // Existing ledger rows do not have an immutable same-transaction
          // creation witness. Exact current values are insufficient evidence.
          throw const DomainFailure('finance_origin_unverified');
        }
        if (output['capture_fingerprint'] != slotById[id]!['snapshot']) {
          throw const DomainFailure('capture_migration_unresolved');
        }
        final operations = await (db.select(db.memoryCardOperations)
              ..where((t) =>
                  t.cardId.equals(id) &
                  t.sourceKind.equals('capture_reconcile')))
            .get();
        final creates = operations.where((row) {
          if (row.operationType != 'create') return false;
          final payload = jsonObject(jsonDecode(row.payload));
          return payload['_actor'] == 'import' &&
              payload['sourceRef'] == receipt['projection_source_ref'] &&
              payload['processor'] == 'capture_reconcile.v1';
        }).toList();
        if (creates.length != 1 || operations.length != 1) {
          throw const DomainFailure('capture_migration_unresolved');
        }
        outputs.add({...output, 'create_operation_id': creates.single.id});
      }
    }
    final source = <String, dynamic>{
      'note_id': note,
      'revision': receipt['revision'],
      'op': receipt['op'],
      'card_ids': outputIds,
      'slots': slots,
      'issues': receipt['issues'] ?? const [],
      'projection_source_ref': receipt['projection_source_ref'],
    };
    records.add({
      'source_id': note,
      'source_revision': receipt['revision'],
      'target_id': note,
      'target_revision': receipt['revision'],
      'is_tombstone': receipt['op'] == 'delete',
      'op': receipt['op'],
      'source_digest': domainDigest(source),
      'output_ids': liveOutputIds,
      'output_digest': domainDigest(outputs),
      'slots': slots,
      'issues': issues,
      'projection_source_ref': receipt['projection_source_ref'],
    });
  }
  final source = <String, dynamic>{
    'source_kind': 'claude_web_note',
    'source_instance_id': sourceInstanceId,
    'source_cursor': sourceCursor.toString(),
    'record_count': records.length,
    'records_digest': domainDigest([
      for (final r in records)
        {
          'source_id': r['source_id'],
          'source_revision': r['source_revision'],
          'source_digest': r['source_digest'],
        }
    ]..sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)))),
    'outputs_digest': domainDigest([
      for (final r in records)
        {
          'target_id': r['target_id'],
          'target_revision': r['target_revision'],
          'is_tombstone': r['is_tombstone'],
          'output_ids': r['output_ids'],
          'output_digest': r['output_digest'],
        }
    ]..sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)))),
  };
  return CaptureMigrationManifest({
    'protocol': 'i-domain-migration-manifest-v1',
    'migration_id': migrationId,
    'domain': 'captures',
    'binding': copyJson(binding),
    'source': source,
    'records': records,
  });
}

Future<Json?> _captureOutput(
    AppDatabase db, String id, String expectedSourceRef) async {
  final card = await (db.select(db.memoryCards)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
  if (card == null) return null;
  final sources = await (db.select(db.memoryCardSources)
        ..where((t) => t.cardId.equals(id)))
      .get();
  final fields = await (db.select(db.memoryCardStructuredFields)
        ..where((t) => t.cardId.equals(id)))
      .get();
  final links = await (db.select(db.memoryEntityLinks)
        ..where((t) =>
            t.sourceTable.equals('memory_cards') & t.sourceId.equals(id)))
      .get();
  final relations = await (db.select(db.memoryCardRelations)
        ..where((t) => t.fromCardId.equals(id) | t.toCardId.equals(id)))
      .get();
  final assets = await (db.select(db.memoryCardAssets)
        ..where((t) => t.cardId.equals(id)))
      .get();
  final corrections = await (db.select(db.userCorrections)
        ..where((t) => t.targetId.equals(id)))
      .get();
  if (sources.length != 1 ||
      sources.single.sourceKind != 'import' ||
      sources.single.sourceRef != expectedSourceRef) {
    return null;
  }
  if (corrections.isNotEmpty ||
      fields.any((row) => row.userCorrected) ||
      relations.any((row) => row.userCorrected)) {
    return null;
  }
  List<String> rows(Iterable<Json> values) =>
      values.map(_legacyDigest).toList()..sort();
  final projection = {
    'card': card.toJson(),
    'sources': rows(sources.map((r) => r.toJson())),
    'fields': rows(fields.map((r) => r.toJson())),
    'links': rows(links.map((r) => r.toJson())),
    'relations': rows(relations.map((r) => r.toJson())),
    'assets': rows(assets.map((r) => r.toJson())),
  };
  return {
    'id': id,
    ...projection,
    'capture_fingerprint': _legacyDigest(projection),
    'finance': fields.any((row) => const {
          'expense_entry',
          'income_entry',
          'shopping_order'
        }.contains(row.structuredFieldsType)),
  };
}

String _legacyDigest(Object? value) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) return item.map(sorted).toList();
    return item;
  }

  return sha256.convert(utf8.encode(jsonEncode(sorted(value)))).toString();
}
