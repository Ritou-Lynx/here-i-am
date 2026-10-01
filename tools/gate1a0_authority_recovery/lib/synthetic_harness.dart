// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'migration_case_catalog.dart';

const _p5FormalObjectTypeOrder = <String>[
  'neutral_card',
  'user_truth',
  'card_forward_relation',
  'memory_structured_correction',
  'card_asset_provenance_relation',
  'source_content',
  'source_version',
  'rich_text_document',
  'card_revision_history',
  'board',
  'board_item',
  'board_group_membership',
  'board_edge',
  'annotation_card',
  'anchor',
  'timed_text_media_selector',
  'evidence_claim',
  'dreaming_fragment',
  'dreaming_episode_saga',
  'memory_entity_link',
  'project_memory',
  'task_room_decision',
  'task_artifact',
  'capture',
  'import_candidate',
  'link_inbox_item',
  'chat_message',
  'activity_event_shadow',
  'domain_operation_receipt_change',
  'tombstone_trash',
  'derived_index_cache',
  'backup_manifest',
];

const _p5FormalObjectTypes = <String>{
  'neutral_card',
  'user_truth',
  'card_forward_relation',
  'memory_structured_correction',
  'card_asset_provenance_relation',
  'source_content',
  'source_version',
  'rich_text_document',
  'card_revision_history',
  'board',
  'board_item',
  'board_group_membership',
  'board_edge',
  'annotation_card',
  'anchor',
  'timed_text_media_selector',
  'evidence_claim',
  'dreaming_fragment',
  'dreaming_episode_saga',
  'memory_entity_link',
  'project_memory',
  'task_room_decision',
  'task_artifact',
  'capture',
  'import_candidate',
  'link_inbox_item',
  'chat_message',
  'activity_event_shadow',
  'domain_operation_receipt_change',
  'tombstone_trash',
  'derived_index_cache',
  'backup_manifest',
};

const _p5FormalBlockedReasons = <String>{
  'duplicate_identity_payload_mismatch',
  'body_conflict',
  'unsupported_kind_or_owner',
  'rollback_unrepresentable',
  'truth_authorization_missing',
  'provenance_conflict',
  'dangling_reference',
  'relation_direction_undetermined',
  'richtext_element_unclassified',
  'structured_field_unclassified',
  'asset_bytes_missing',
  'asset_hash_mismatch',
  'evidence_role_escalation',
  'source_canonical_collision',
  'source_version_mutable',
  'source_version_missing',
  'ime_composition_uncommitted',
  'richtext_fingerprint_mismatch',
  'revision_lineage_unbound',
  'board_reference_set_not_closed',
  'board_item_reference_unclassified',
  'membership_identity_ambiguous',
  'anchor_tuple_invalid',
  'anchor_retarget_ambiguous',
  'timed_selector_unreliable',
  'evidence_claim_promotion_forbidden',
  'dreaming_lineage_unresolved',
  'project_scope_violation',
  'task_lane_leak',
  'artifact_promotion_unauthorized',
  'artifact_promotion_partial',
  'intake_key_digest_conflict',
  'intake_payload_incomplete',
  'intake_cancel_barrier',
  'parser_result_after_cancel',
  'link_fetch_fallback_forbidden',
  'chat_sync_id_missing',
  'activity_migration_forbidden',
  'operation_lineage_unbound',
  'ghost_receipt',
  'duplicate_change',
  'tombstone_source_missing',
  'projection_before_acceptance',
  'backup_manifest_incomplete',
  'backup_restore_unproven',
};

const _frozenFormalRowDigests = <String, String>{
  'neutral_card':
      '8c246dde0e25cc39a8e3c7a5c91fa821cc44009a88f4fa75bb922806df522063',
  'user_truth':
      '339c11f1aec32ce406c4ca61397f0b4afc973338343556b025891432094f7988',
  'card_forward_relation':
      '3ec9eab84c63097b3a38b76726c732fdd897f5416acd652e03fa1227ccfbda0a',
  'memory_structured_correction':
      'd11693cdc3ef72b5de0507eb6e11e95045e65598e74cdaa4e1c482d08377da21',
  'card_asset_provenance_relation':
      '6612749aa79d647895fc4726a0bde8ec7dce2a48bf607cb5aeab3d40ccdc9796',
  'source_content':
      '732c221214343bf670a86bb4bfa532cb3086fa8963272f90656a24bf1c60bd71',
  'source_version':
      'f446803dfd2a241f6379422aea6667a467501baefa7cc3294f9cfaee29f82d37',
  'rich_text_document':
      '8ae78023d41b8fd788a53c2dd339a2368697a7bef6e049b76d44103ec5f7b7e9',
  'card_revision_history':
      '677d6447cecc42dc1cea4fc0a1f27a25783754ac9c76cef746fb94a89da0d777',
  'board': '4c96977e4a2f12aeb15e2ac89801ae4c4dfb8daecf00eea82d86f51a87934d2f',
  'board_item':
      'cebd6ea4c563b91aeaf258cd960f262f7cfb157ce7649e8a0530392e474903ec',
  'board_group_membership':
      'b9546f9555afc077b6712e466a7ac9897f3f793812d1e82211daca1d8f0d0744',
  'board_edge':
      '9c1a701426f3ab2826ebecadceb4755172b0aac3c58b8e7328ddce51a7a6a0a3',
  'annotation_card':
      '9e5587ab98d012a10787ecc2993f4781678d707510ec33745deb34854b6036cb',
  'anchor': 'f07537ad45e0cd108425a15f3647f6598be0b4fcdf526e72fb1763b10bbf7d6c',
  'timed_text_media_selector':
      '19d0a5b7d5da0e91368c3ecdb0bc6d159ed51d9025082ded990517ccccdfe1ec',
  'evidence_claim':
      'f32d4094200cc7b52a05a392f65aa6c6b4fb190e7242d2cb69c372fb2a21dcee',
  'dreaming_fragment':
      'e4768366c892ed6e616ebbfaf9b250e3f0048143105115800a11197bca0a0690',
  'dreaming_episode_saga':
      '74d8c5da40332b70b260ba5b7656bf301a7ee593677d3e4e4efc529c364c8952',
  'memory_entity_link':
      '9c2faa5c3352606558ade00271bee4bcd28156582d6e07e89132dfbb045dab45',
  'project_memory':
      'aa2c82482b34e62c0e65736907bffa68346b38341c1f2465e4af4e6488ca7079',
  'task_room_decision':
      '239f855c7f90c603695b87b72ec5a22c8d2c11a77c1c652a6267d2eacf7492a0',
  'task_artifact':
      '7a2e91509e94563b6d224b31a6c10109617b13127b39ef2c19a288c6c381b629',
  'capture': '3c311eae48826a9f5a55875acea97e5d7cc82a8bec6424ea0976d8c81893a5b9',
  'import_candidate':
      'f451fe227e3d2aa557cae3ac8daa13f9d5d3e4d55807fc10311a0ed8be70d4f0',
  'link_inbox_item':
      '953f726d535989775647b90fef66cea96750ebc8b00d992b2df6aa94f6e7b161',
  'chat_message':
      '2b05ba50410b304ec5ac98b9c7586e1dcbcfda772cc59b62bf9db8162b2233a2',
  'activity_event_shadow':
      '202e494af3b5ad3bf22ee94c319690ad6a53f632aa1793476d878281158a6490',
  'domain_operation_receipt_change':
      'a788f47109180edc8dfefb443bb4e8bc306beff9cfd307bd7b5d17288eb49b87',
  'tombstone_trash':
      '64db09bce91c42932a5706a72e0a0a32a271630ae8038b2035ec51bfd35fc06d',
  'derived_index_cache':
      '1ce0fbd2688500aae2e64298f00b936381a76ea640b7290cafe981249fc2622a',
  'backup_manifest':
      '8772b592163cda35a5a6dfdafb3a976ecd59b5c325c1decbeb380a404cd88f7e',
};

const _p5CrashPointTemplates = <String>[
  'before_identity_precheck',
  'after_identity_precheck_before_idempotency',
  'after_idempotency_before_business_read',
  'before_journal_tx_a',
  'after_journal_tx_a_commit',
  'before_stage_file_write:<file>',
  'after_stage_file_write:<file>_before_file_fsync',
  'after_stage_file_fsync:<file>_before_directory_fsync',
  'after_stage_directory_fsync_before_tx_b',
  'after_tx_b_commit',
  'before_rollback_copy:<rollbackCopy>',
  'after_rollback_copy:<rollbackCopy>_before_rollback_fsync',
  'after_rollback_fsync:<rollbackCopy>',
  'before_publish_started_phase',
  'after_publish_started_phase',
  'before_file_publish:<file>',
  'after_file_publish:<file>',
  'before_object_publish:<object>',
  'after_object_publish:<object>',
  'before_files_published_phase',
  'after_files_published_phase',
  'before_activation_tx',
  'during_activation_tx_before_commit',
  'after_activation_tx_commit',
  'after_invalidation_before_rebuild',
  'before_projection_rebuild:<projection>',
  'during_projection_rebuild:<projection>',
  'after_projection_rebuild:<projection>_before_cursor_commit',
  'after_cursor_commit_before_notification',
  'after_notification_before_response',
  'after_response_before_cleanup',
  'during_cleanup:<cleanupItem>',
];

List<String> _expandCrashTemplates(Map<String, dynamic> dimensions) {
  _expectExactKeys(
      dimensions,
      const {
        'files',
        'objects',
        'rollbackCopies',
        'projections',
        'cleanupItems',
      },
      'manifest.fixtureDimensions');
  const expected = {
    'files': 2,
    'objects': 2,
    'rollbackCopies': 2,
    'projections': 4,
    'cleanupItems': 2,
  };
  if (!_deepExactEquals(dimensions, expected)) {
    fail(
      FailureClass.inputRejected,
      'fixture dimensions do not match the frozen P5 corpus',
    );
  }
  final expanded = <String>[];
  for (final template in _p5CrashPointTemplates) {
    final token = RegExp(r'<(file|object|rollbackCopy|projection|cleanupItem)>')
        .firstMatch(template);
    if (token == null) {
      expanded.add(template);
      continue;
    }
    final dimension = switch (token.group(1)!) {
      'file' => 'files',
      'object' => 'objects',
      'rollbackCopy' => 'rollbackCopies',
      'projection' => 'projections',
      'cleanupItem' => 'cleanupItems',
      _ => fail(FailureClass.unsupported, 'unknown fixture dimension token'),
    };
    for (var ordinal = 0; ordinal < (dimensions[dimension] as int); ordinal++) {
      expanded.add(template.replaceFirst(token.group(0)!, '$ordinal'));
    }
  }
  return expanded;
}

bool _validateFrozenFormalCatalog(List<dynamic> catalog) {
  if (catalog.length != 32 ||
      catalog.any((value) => value is! Map<String, dynamic>)) {
    return false;
  }
  final rows = catalog.cast<Map<String, dynamic>>();
  final orderedTypes = rows.map((row) => row['objectType']).toList();
  final types = orderedTypes.whereType<String>().toSet();
  if (!_setEquals(types, _p5FormalObjectTypes) || types.length != rows.length) {
    return false;
  }
  if (!_deepExactEquals(orderedTypes, _p5FormalObjectTypeOrder)) return false;
  for (final row in rows) {
    if (!_setEquals(row.keys.toSet(), const {
      'objectType',
      'classification',
      'stableIdMapping',
      'authority',
      'refs',
      'rollback',
      'deleteRecovery',
      'indexBackup',
      'blockedReason',
    })) return false;
    if (row['authority'] is! String ||
        (row['authority'] as String).isEmpty ||
        !const {
          'preserve',
          'migrate',
          'derive',
          'compatibility-only',
          'degraded-preserved',
          'blocked',
        }.contains(row['classification'])) return false;
    final stable = row['stableIdMapping'];
    final refs = row['refs'];
    final rollback = row['rollback'];
    final deletion = row['deleteRecovery'];
    final index = row['indexBackup'];
    if (stable is! Map<String, dynamic> ||
        !_setEquals(stable.keys.toSet(), const {'entries'}) ||
        stable['entries'] is! List ||
        (stable['entries'] as List).isEmpty ||
        refs is! List ||
        refs.any((value) => value is! String || value.isEmpty) ||
        rollback is! Map<String, dynamic> ||
        !_setEquals(rollback.keys.toSet(), const {
          'strategy',
          'preserveAcceptedNewWrites',
          'appendOnly',
          'reconstructFromAuthority',
        }) ||
        rollback['strategy'] is! String ||
        (rollback['strategy'] as String).isEmpty ||
        rollback['preserveAcceptedNewWrites'] is! bool ||
        rollback['appendOnly'] is! bool ||
        rollback['reconstructFromAuthority'] is! bool ||
        deletion is! Map<String, dynamic> ||
        !_setEquals(deletion.keys.toSet(), const {
          'strategy',
          'tombstoneBarrier',
          'physicalDeleteAllowed',
          'recoverySource',
        }) ||
        deletion['strategy'] is! String ||
        (deletion['strategy'] as String).isEmpty ||
        deletion['tombstoneBarrier'] is! bool ||
        deletion['physicalDeleteAllowed'] is! bool ||
        deletion['recoverySource'] is! String ||
        (deletion['recoverySource'] as String).isEmpty ||
        index is! Map<String, dynamic> ||
        !_setEquals(index.keys.toSet(),
            const {'rebuildFrom', 'backupRequired', 'excludedFromBackup'}) ||
        index.values.any((value) =>
            value is! List ||
            value.any((item) => item is! String || item.isEmpty))) {
      return false;
    }
    final objectType = row['objectType'] as String;
    final entries = stable['entries'] as List;
    for (final rawEntry in entries) {
      if (rawEntry is! Map<String, dynamic> ||
          !_setEquals(rawEntry.keys.toSet(), const {
            'legacyKind',
            'targetKind',
            'mode',
            'sourceFields',
            'targetField',
            'fallbackAlgorithm',
            'guard',
          })) return false;
      final entry = rawEntry;
      final mode = entry['mode'];
      final sourceFields = entry['sourceFields'];
      if (!const {
            'preserve',
            'derive_composite',
            'allocate_digest_if_missing',
            'not_applicable',
            'blocked',
          }.contains(mode) ||
          entry['legacyKind'] is! String ||
          (entry['legacyKind'] as String).isEmpty ||
          entry['targetKind'] is! String ||
          (entry['targetKind'] as String).isEmpty ||
          sourceFields is! List ||
          sourceFields.isEmpty ||
          sourceFields.any((field) => field is! String || field.isEmpty) ||
          entry['targetField'] is! String ||
          (entry['targetField'] as String).isEmpty ||
          entry['fallbackAlgorithm'] is! String ||
          entry['guard'] is! String ||
          (entry['guard'] as String).isEmpty) return false;
      final fallback = entry['fallbackAlgorithm'] as String;
      if (mode == 'allocate_digest_if_missing'
          ? fallback != 'deterministic_namespace_plus_payload_sha256'
          : fallback.isNotEmpty) return false;
      if ({'blocked', 'not_applicable'}.contains(mode)) {
        if (entry['targetField'] != 'not_applicable') return false;
      } else if (entry['targetField'] == 'not_applicable') {
        return false;
      }
    }
    if (rollback['reconstructFromAuthority'] == true &&
        !const {
          'rich_text_document',
          'activity_event_shadow',
          'derived_index_cache',
        }.contains(objectType)) return false;
    final blocked = row['classification'] == 'blocked';
    final reason = row['blockedReason'];
    if (reason is! String ||
        (blocked
            ? reason.isEmpty || !_p5FormalBlockedReasons.contains(reason)
            : reason.isNotEmpty)) {
      return false;
    }
    if (_frozenFormalRowDigests[objectType] != _canonicalSha256(row)) {
      return false;
    }
  }
  return _setEquals(
    _frozenFormalRowDigests.keys.toSet(),
    _p5FormalObjectTypes,
  );
}

/// Closed-world, synthetic-only model for the frozen Gate 1A-0 contracts.
///
/// Each scenario supplies a raw [input] subtree and an independently literal
/// [expected] sibling. Case identity, family, operation, schema and invariant
/// are canonical code; all-case input digests and whole-fixture bytes prevent
/// the fixture from redefining both sides of its own comparison.
class SyntheticAuthorityRecoveryHarness {
  static const schemaVersion = 2;
  static const contractVersion = 'gate1a0-synthetic-contract-v6';
  static const _pinnedFixtureDigest =
      'e6007a58309fa36b7ef5e41da223251a2b9fb16c249a2ad084cd459b48fdc9a7';
  static const purpose =
      'gate1a0 canonical authority recovery and migration simulation corpus';
  static const _allowedFiles = {'manifest.json', 'scenarios.json'};
  static final Map<String, _CaseSpec> _caseSpecs = _buildCaseSpecs();

  SyntheticAuthorityRecoveryHarness({
    required this.repositoryRoot,
    required this.fixtureBase,
  });

  final String repositoryRoot;
  final String fixtureBase;

  static Set<String> get canonicalCaseIds => Set.unmodifiable(_caseSpecs.keys);

  /// Test-only diagnostic surface proving raw-state changes alter derivation.
  static Map<String, Object?> simulateMigrationRawForTest(
    String caseId,
    Map<String, dynamic> input,
  ) {
    final definition = migrationCaseDefinitions.singleWhere(
      (candidate) => candidate.id == caseId,
      orElse: () => fail(
        FailureClass.unsupported,
        'migration operation has no canonical case definition: $caseId',
      ),
    );
    final result = _executeMigrationCase(definition, input);
    final legacy = input['legacy'] as Map<String, dynamic>;
    final derived = _deriveMigrationTarget(definition, legacy);
    return {
      'actual': result.actual,
      'evidence': result.evidence,
      'computedActualForComparator': result.evidence['literalComparable'],
      'invariantResults': {
        'contractInvariantHeld':
            result.evidence['contractInvariantHeld'] == true,
      },
      'targetForTest': derived.acceptedTarget,
      'preservationForTest': derived.preservation,
    };
  }

  /// Test-only diagnostic surface for injected acceptance ledger state.
  static Map<String, Object?> simulateAcceptanceRawForTest(
    Map<String, dynamic> input,
  ) {
    final result = _simulateAcceptanceCrash(input);
    return {'actual': result.actual, 'evidence': result.evidence};
  }

  /// Test-only comparator surface kept separate from the input-only simulator.
  static Map<String, bool> compareComputedMigrationForTest(
    Map<String, dynamic> computedActual,
    Map<String, dynamic> literalExpected, {
    required bool contractInvariantHeld,
  }) =>
      {
        'actualMatchesLiteralExpected':
            _deepExactEquals(computedActual, literalExpected),
        'contractInvariantHeld': contractInvariantHeld,
      };

  static bool evaluateContractForTest(
    String caseId,
    String actual,
    Map<String, Object?> evidence,
  ) {
    final spec = _caseSpecs[caseId];
    if (spec == null) {
      fail(FailureClass.inputRejected, 'unknown diagnostic case: $caseId');
    }
    return _evaluateInvariant(spec, _SimulationResult(actual, evidence));
  }

  static bool validateFormalCatalogForTest(List<dynamic> catalog) =>
      _validateFrozenFormalCatalog(catalog);

  static Map<String, Object?> recoverMigrationDurableStateForTest(
    String caseId,
    Map<String, dynamic> input,
    Map<String, dynamic> durableState,
  ) {
    final definition = migrationCaseDefinitions.singleWhere(
      (candidate) => candidate.id == caseId,
      orElse: () => fail(
        FailureClass.inputRejected,
        'unknown diagnostic migration case: $caseId',
      ),
    );
    if (!definition.commitCase) {
      fail(FailureClass.inputRejected, 'diagnostic case is not a commit case');
    }
    final transaction = input['transaction'];
    if (transaction is! Map<String, dynamic> ||
        transaction['crashPhase'] != definition.crashPhase ||
        transaction['initialLedgers'] is! Map<String, dynamic>) {
      fail(
        FailureClass.inputRejected,
        'diagnostic input does not match canonical crash transaction',
      );
    }
    _requireMigrationInitialLedgers(
      transaction['initialLedgers'],
      'diagnostic input transaction.initialLedgers',
    );
    final legacy = input['legacy'] as Map<String, dynamic>;
    final derived = _deriveMigrationTarget(definition, legacy);
    final legacyDigest = _canonicalSha256(legacy);
    final targetDigest = derived.acceptedTarget == null
        ? null
        : _canonicalSha256(derived.acceptedTarget);
    final manifests = _buildMigrationManifests(
      definition,
      legacyDigest,
      targetDigest,
      definition.commitCase,
    );
    final serializedDigest = _canonicalSha256(durableState);
    final recovered = _recoverMigrationDurableState(
      _roundTrip(durableState),
      manifests,
      crashDurability: 'diagnostic',
      serializedDigest: serializedDigest,
      tracePrefix: 'diagnostic-injected-state',
      expectedCrashPoint: definition.crashPhase,
      expectedInitialLedgers:
          transaction['initialLedgers'] as Map<String, dynamic>,
    );
    return {
      'convergence': recovered.convergence,
      'journalPhase': recovered.journalPhase,
      'ledgersExactlyOnce': recovered.ledgersExactlyOnce,
      'trace': recovered.trace,
    };
  }

  /// Test-only boundary surface: executes the same raw transaction to a
  /// caller-selected exact boundary without consulting a literal expected.
  static Map<String, Object?> migrationDurableStateAtBoundaryForTest(
    String caseId,
    Map<String, dynamic> input,
    String crashPoint,
  ) {
    final definition = migrationCaseDefinitions.singleWhere(
      (candidate) => candidate.id == caseId,
      orElse: () => fail(
        FailureClass.inputRejected,
        'unknown diagnostic migration case: $caseId',
      ),
    );
    if (!definition.commitCase) {
      fail(FailureClass.inputRejected, 'diagnostic case is not a commit case');
    }
    final legacy = input['legacy'] as Map<String, dynamic>;
    final details = legacy['details'] as Map<String, dynamic>;
    final facts = details['failureFacts'] as Map<String, dynamic>;
    final transaction = input['transaction'] as Map<String, dynamic>;
    final derived = _deriveMigrationTarget(definition, legacy);
    final manifests = _buildMigrationManifests(
      definition,
      _canonicalSha256(legacy),
      derived.acceptedTarget == null
          ? null
          : _canonicalSha256(derived.acceptedTarget),
      true,
    );
    final commit = _runMigrationCommit(
      crashPoint,
      manifests,
      failurePoint: 'none',
      oldHash: facts['oldHash'] as String,
      newHash: facts['newHash'] as String,
      observedHash: facts['observedHash'] as String,
      initialLedgers: transaction['initialLedgers'] as Map<String, dynamic>,
    );
    return commit.durableState;
  }

  HarnessResult run({required String fixtureRoot, required String outputRoot}) {
    final fixture = _directory(fixtureRoot, 'fixture root');
    final base = _directory(fixtureBase, 'fixture base');
    final output = _directory(outputRoot, 'output root');
    final temp = _directory(Directory.systemTemp.path, 'system temp root');
    final repo = _directory(repositoryRoot, 'repository root');
    if (!_strictChild(fixture, base)) {
      fail(
        FailureClass.pathRejected,
        'fixture root must be below the managed fixture base',
      );
    }
    if (!_strictChild(output, temp) || _within(output, repo)) {
      fail(
        FailureClass.pathRejected,
        'output root must be an empty strict system-temp child outside the repository',
      );
    }
    _rejectLinks(fixture, 'fixture tree');
    _rejectLinks(output, 'output root');
    if (Directory(output).listSync(followLinks: false).isNotEmpty) {
      fail(FailureClass.pathRejected, 'output root must be empty');
    }

    final manifestFile = File(_join(fixture, 'manifest.json'));
    final scenarioFile = File(_join(fixture, 'scenarios.json'));
    final manifestBytes = manifestFile.readAsBytesSync();
    final scenarioBytes = scenarioFile.readAsBytesSync();
    final manifest = _json(manifestFile);
    _validateManifest(manifest);
    final caseInputDigests = Map<String, dynamic>.from(
      manifest['caseInputDigests'] as Map,
    );
    final fixtureDimensions = Map<String, dynamic>.from(
      manifest['fixtureDimensions'] as Map,
    );
    final independentlyExpandedCrashPoints =
        _expandCrashTemplates(fixtureDimensions);
    if (!_listEquals(manifest['exactExpandedCrashPoints'],
            independentlyExpandedCrashPoints) ||
        !_listEquals(
            manifest['exactFailurePoints'], exactMigrationFailurePoints)) {
      fail(
        FailureClass.inputRejected,
        'manifest exact crash/failure allow-lists do not match P5 9.1',
      );
    }
    if (!_setEquals(caseInputDigests.keys.toSet(), _caseSpecs.keys.toSet()) ||
        caseInputDigests.values.any(
          (value) => value is! String || value.length != 64,
        )) {
      fail(
        FailureClass.inputRejected,
        'manifest all-case input digest registry is not exact',
      );
    }
    final files = Directory(fixture)
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) => _relative(file.path, fixture))
        .toSet();
    final declared = (manifest['declaredFiles'] as List).cast<String>().toSet();
    if (!_setEquals(files, _allowedFiles) ||
        !_setEquals(declared, _allowedFiles)) {
      fail(
        FailureClass.inputRejected,
        'fixture files must exactly match the declared allowlist',
      );
    }

    final scenarioDigest = sha256.convert(scenarioBytes).toString();
    if (manifest['scenarioSha'] != scenarioDigest) {
      fail(FailureClass.inputRejected, 'scenario bytes do not match manifest');
    }
    final fixtureDigest =
        sha256.convert([...manifestBytes, 0, ...scenarioBytes]).toString();
    final fixturePinned = fixtureDigest == _pinnedFixtureDigest;
    final document = _json(scenarioFile);
    _expectExactKeys(document, {'scenarios'}, 'scenario document');
    final rawScenarios = document['scenarios'];
    if (rawScenarios is! List ||
        rawScenarios.isEmpty ||
        rawScenarios.length > 256) {
      fail(
        FailureClass.inputRejected,
        'scenarios must be a non-empty bounded list',
      );
    }

    final seen = <String>{};
    final scenarios = <_Scenario>[];
    for (final raw in rawScenarios) {
      if (raw is Map<String, dynamic> &&
          caseInputDigests.containsKey(raw['id'])) {
        final input = raw['input'];
        if (_canonicalSha256(input) != caseInputDigests[raw['id']]) {
          fail(
            FailureClass.inputRejected,
            'case whole-input digest does not match raw input',
          );
        }
      }
      final scenario = _scenario(raw);
      if (!seen.add(scenario.id)) {
        fail(FailureClass.inputRejected,
            'duplicate scenario id: ${scenario.id}');
      }
      scenarios.add(scenario);
    }
    if (!_setEquals(seen, _caseSpecs.keys.toSet())) {
      fail(
        FailureClass.inputRejected,
        'scenario ids must exactly match the canonical case registry',
      );
    }
    scenarios.sort((left, right) => left.id.compareTo(right.id));

    final outcomes = <Map<String, Object?>>[];
    final crashPhases = <String>[];
    final expandedCrashPointsExecuted = <String>[];
    final failurePointsExecuted = <String>[];
    final externalConflictCrashBindings = <String>[];
    final migrationDefinitions = {
      for (final definition in migrationCaseDefinitions)
        definition.id: definition,
    };
    for (final scenario in scenarios) {
      final spec = _caseSpecs[scenario.id]!;
      final simulation = _simulate(spec, _roundTrip(scenario.input));
      final contractInvariantHeld = _evaluateInvariant(spec, simulation);
      final comparable = simulation.evidence['literalComparable'] is Map
          ? Map<String, dynamic>.from(
              simulation.evidence['literalComparable'] as Map,
            )
          : <String, dynamic>{'result': simulation.actual};
      final invariantResults = <String, bool>{
        'actualMatchesLiteralExpected':
            _deepExactEquals(comparable, scenario.expected),
        'contractInvariantHeld': contractInvariantHeld,
      };
      final passed = invariantResults.isNotEmpty &&
          invariantResults.values.every((value) => value);
      final reportEvidence = Map<String, Object?>.from(simulation.evidence)
        ..remove('literalComparable');
      outcomes.add({
        'id': scenario.id,
        'family': spec.family.label,
        'operation': spec.operation.label,
        'expected': scenario.expected,
        'actual': simulation.actual,
        'invariant': spec.invariant,
        'invariantResults': invariantResults,
        'invariantHeld': invariantResults.values.every((value) => value),
        'wholeInputDigest': scenario.wholeInputDigest,
        'result': passed ? 'pass' : 'fail',
        'evidence': reportEvidence,
      });
      final crashPhase = simulation.evidence['crashPhaseExecuted'];
      if (crashPhase is String &&
          RegExp(r'^crash-[A-F]$').hasMatch(scenario.id)) {
        crashPhases.add(crashPhase);
      }
      final migrationDefinition = migrationDefinitions[scenario.id];
      if (migrationDefinition != null && migrationDefinition.commitCase) {
        final crashPoint =
            simulation.evidence['exactExpandedCrashPointExecuted'];
        final failurePoint = simulation.evidence['exactFailurePointExecuted'];
        if (!migrationDefinition.isFailureCase) {
          if (crashPoint is String) expandedCrashPointsExecuted.add(crashPoint);
        } else {
          if (failurePoint is String) failurePointsExecuted.add(failurePoint);
          if (failurePoint == 'external_third_hash_conflict' &&
              crashPoint is String) {
            externalConflictCrashBindings.add(crashPoint);
          }
        }
      }
    }
    if (!_setEquals(expandedCrashPointsExecuted.toSet(),
            independentlyExpandedCrashPoints.toSet()) ||
        expandedCrashPointsExecuted.length !=
            independentlyExpandedCrashPoints.length ||
        !_setEquals(failurePointsExecuted.toSet(),
            exactMigrationFailurePoints.toSet()) ||
        failurePointsExecuted.length !=
            exactMigrationFailurePoints.length + 1 ||
        !_setEquals(externalConflictCrashBindings.toSet(), {
          'after_file_publish:0',
          'after_file_publish:1',
        }) ||
        externalConflictCrashBindings.length != 2) {
      fail(
        FailureClass.inputRejected,
        'migration exact crash/failure coverage is missing, extra, or duplicated',
      );
    }
    if (outcomes.any((outcome) =>
        (outcome['invariantResults'] as Map)['actualMatchesLiteralExpected'] !=
        true)) {
      fail(
        FailureClass.inputRejected,
        'literal expected does not match independently simulated actual',
      );
    }
    if (outcomes.any((outcome) =>
        (outcome['invariantResults'] as Map)['contractInvariantHeld'] !=
        true)) {
      fail(
        FailureClass.inputRejected,
        'computed contract invariant failed',
      );
    }
    if (!fixturePinned) {
      fail(FailureClass.inputRejected,
          'fixture bytes do not match pinned digest');
    }

    final passedCases =
        outcomes.where((outcome) => outcome['result'] == 'pass').length;
    final invariantCases = outcomes.where((outcome) {
      final results = outcome['invariantResults'] as Map;
      return results.isNotEmpty &&
          results.values.every((value) => value == true);
    }).length;
    final familyCounts = <String, int>{};
    final classificationCounts = <String, int>{};
    for (final outcome in outcomes) {
      final family = outcome['family'] as String;
      familyCounts[family] = (familyCounts[family] ?? 0) + 1;
      final evidence = outcome['evidence'] as Map<String, Object?>;
      final classification =
          evidence['classification'] as String? ?? 'not_applicable';
      classificationCounts[classification] =
          (classificationCounts[classification] ?? 0) + 1;
    }
    final fullRoundTripOutcomes = outcomes.where(
      (outcome) => outcome['id'] == 'migration-roundtrip-full',
    );
    final allSixRoundTripDomainsHeld = fullRoundTripOutcomes.length == 1 &&
        ((fullRoundTripOutcomes.single['evidence'] as Map)['fullRoundTrip']
                as Map?)?['allSixRoundTripDomainsHeld'] ==
            true;

    final report = <String, Object?>{
      'harness': 'gate1a0-authority-recovery',
      'mode': 'validate/simulate-only',
      'synthetic': true,
      'migrationExecuted': false,
      'migrationSimulated': true,
      'contractVersion': contractVersion,
      'fixtureDigest': fixtureDigest,
      'scenarioSha': scenarioDigest,
      'caseInputDigests': Map.fromEntries(
        caseInputDigests.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)),
      ),
      'fixtureDimensions': fixtureDimensions,
      'exactExpandedCrashPoints': independentlyExpandedCrashPoints,
      'exactFailurePoints': exactMigrationFailurePoints,
      'schemaVersion': schemaVersion,
      'fixedClock': '2030-01-02T03:04:05Z',
      'idStrategy': 'canonical-case-id',
      'productionClaims':
          'none; synthetic state machines do not switch production authority',
      'totalCases': outcomes.length,
      'passedCases': passedCases,
      'allInvariantsHeld': outcomes.isNotEmpty &&
          outcomes.every((outcome) {
            final results = outcome['invariantResults'] as Map;
            return results.isNotEmpty &&
                results.values.every((value) => value == true);
          }),
      'allSixRoundTripDomainsHeld': allSixRoundTripDomainsHeld,
      'caseCounts': {
        'total': outcomes.length,
        'passed': passedCases,
        'failed': outcomes.length - passedCases,
        'invariantHeld': invariantCases,
      },
      'familyCounts': Map.fromEntries(
        familyCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'classificationCounts': Map.fromEntries(
        classificationCounts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'stateMachineEvidence': {
        'acceptanceCrashPhases': crashPhases..sort(),
        'expandedCrashPointCaseCount': expandedCrashPointsExecuted.length,
        'uniqueExpandedCrashPointCount':
            expandedCrashPointsExecuted.toSet().length,
        'failurePointCaseCount': failurePointsExecuted.length,
        'uniqueFailurePointCount': failurePointsExecuted.toSet().length,
        'externalThirdHashConflictCrashBindings': externalConflictCrashBindings
          ..sort(),
      },
      'cases': outcomes,
    };
    final bytes = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    File(_join(output, 'report.json')).writeAsBytesSync(bytes, flush: true);
    return HarnessResult(report: report, reportBytes: bytes);
  }

  _Scenario _scenario(dynamic value) {
    if (value is! Map<String, dynamic>) {
      fail(FailureClass.inputRejected, 'scenario must be an object');
    }
    _expectExactKeys(
      value,
      {'id', 'family', 'schemaVersion', 'input', 'expected'},
      'scenario',
    );
    if (value['id'] is! String ||
        value['family'] is! String ||
        value['schemaVersion'] != schemaVersion ||
        value['input'] is! Map<String, dynamic> ||
        value['expected'] is! Map<String, dynamic>) {
      fail(FailureClass.inputRejected, 'scenario shape or schema is invalid');
    }
    final id = value['id'] as String;
    final spec = _caseSpecs[id];
    if (spec == null) {
      fail(FailureClass.inputRejected, 'unknown scenario id: $id');
    }
    if (value['family'] != spec.family.label) {
      fail(
        FailureClass.inputRejected,
        'scenario $id family does not match canonical registry',
      );
    }
    final input = value['input'] as Map<String, dynamic>;
    final expected = value['expected'] as Map<String, dynamic>;
    spec.inputSchema.validate(input, 'scenario[$id].input');
    if (input['operation'] != spec.operation.label) {
      fail(
        FailureClass.inputRejected,
        'scenario $id operation does not match canonical registry',
      );
    }
    _validateLiteralExpected(spec, expected, 'scenario[$id].expected');
    if (id == 'migration-formal-32-object-inventory') {
      final catalog =
          (expected['target'] as Map<String, dynamic>)['catalog'] as List;
      if (!_validateFrozenFormalCatalog(catalog)) {
        fail(
          FailureClass.inputRejected,
          'formal inventory literal does not match frozen P5 machine catalog',
        );
      }
    }
    return _Scenario(id, input, expected, _canonicalSha256(input));
  }

  void _validateLiteralExpected(
    _CaseSpec spec,
    Map<String, dynamic> expected,
    String path,
  ) {
    if (spec.operation != _Operation.migrationCorpus) {
      _expectExactKeys(expected, {'result'}, path);
      if (expected['result'] is! String) {
        fail(FailureClass.inputRejected, '$path.result must be a string');
      }
      return;
    }
    _expectExactKeys(
      expected,
      {'result', 'target', 'roundTrip', 'commit'},
      path,
    );
    if (expected['result'] is! String ||
        expected['target'] is! Map<String, dynamic> ||
        expected['roundTrip'] is! Map<String, dynamic> ||
        expected['commit'] is! Map<String, dynamic>) {
      fail(FailureClass.inputRejected, '$path migration shape is invalid');
    }
    _expectExactKeys(
      expected['target'] as Map<String, dynamic>,
      {
        'classification',
        'headHash',
        'targetRole',
        'migrationAction',
        'blockedReason',
        'catalog',
      },
      '$path.target',
    );
    _expectExactKeys(
      expected['roundTrip'] as Map<String, dynamic>,
      {
        'legacyDigest',
        'targetDigest',
        'rollbackDigest',
        'remigrateDigest',
        'newWriteMarkdown',
        'stableId',
        'revisionCount',
        'operationCount',
        'eventCount',
        'truthCount',
        'ledgersUnique',
        'fullRoundTrip',
      },
      '$path.roundTrip',
    );
    _expectExactKeys(
      expected['commit'] as Map<String, dynamic>,
      {
        'failurePoint',
        'convergence',
        'journalPhase',
        'oldManifest',
        'newManifest',
        'receiptCount',
        'changeCount',
        'projectionCount',
        'ledgersExactlyOnce',
      },
      '$path.commit',
    );
    final fullRoundTrip =
        (expected['roundTrip'] as Map<String, dynamic>)['fullRoundTrip'];
    if (fullRoundTrip != null) {
      if (fullRoundTrip is! Map<String, dynamic>) {
        fail(FailureClass.inputRejected, '$path.fullRoundTrip is invalid');
      }
      _expectExactKeys(
        fullRoundTrip,
        {
          'domains',
          'allSixRoundTripDomainsHeld',
          'derivedIndexRebuiltFromAcceptedState',
          'transitionTrace',
          'physicalDigests',
          'derivedIndexOperationIdsByStage',
        },
        '$path.roundTrip.fullRoundTrip',
      );
      final domains = fullRoundTrip['domains'];
      final physicalDigests = fullRoundTrip['physicalDigests'];
      final indexOperations = fullRoundTrip['derivedIndexOperationIdsByStage'];
      if (domains is! Map<String, dynamic> ||
          !_setEquals(domains.keys.toSet(), _fullRoundTripDomainKeys) ||
          physicalDigests is! Map<String, dynamic> ||
          !_setEquals(
            physicalDigests.keys.toSet(),
            _fullRoundTripDomainKeys,
          ) ||
          indexOperations is! Map<String, dynamic> ||
          !_setEquals(indexOperations.keys.toSet(), const {
            'oldBaseline',
            'firstMigration',
            'postCutover',
            'rollback',
            'remigration',
          }) ||
          indexOperations.values.any((value) => value is! List) ||
          fullRoundTrip['transitionTrace'] is! List ||
          (fullRoundTrip['transitionTrace'] as List).isEmpty) {
        fail(
          FailureClass.inputRejected,
          '$path.fullRoundTrip domains are not the exact six-domain oracle',
        );
      }
      for (final entry in domains.entries) {
        if (entry.value is! Map<String, dynamic>) {
          fail(
            FailureClass.inputRejected,
            '$path.fullRoundTrip.${entry.key} is invalid',
          );
        }
        _expectExactKeys(
          entry.value as Map<String, dynamic>,
          _fullRoundTripDomainFieldKeys,
          '$path.roundTrip.fullRoundTrip.domains.${entry.key}',
        );
        _expectExactKeys(
          physicalDigests[entry.key] as Map<String, dynamic>,
          {
            'oldBaseline',
            'firstMigration',
            'rollbackReadable',
            'remigration',
          },
          '$path.roundTrip.fullRoundTrip.physicalDigests.${entry.key}',
        );
      }
    }
  }

  _SimulationResult _simulate(_CaseSpec spec, Map<String, dynamic> input) {
    return switch (spec.operation) {
      _Operation.authorityMatrix => _simulateAuthorityMatrix(input),
      _Operation.authorityPreAccept => _simulateAuthorityPreAccept(input),
      _Operation.authorityOrdinaryWrite =>
        _simulateAuthorityOrdinaryWrite(input),
      _Operation.identitySubmit => _simulateIdentitySubmit(input),
      _Operation.identityRepair => _simulateIdentityRepair(input),
      _Operation.identityBacklog => _simulateIdentityBacklog(input),
      _Operation.identityConflict => _simulateIdentityConflict(input),
      _Operation.identityRecover => _simulateIdentityRecover(input),
      _Operation.outboxEnqueue => _simulateOutboxEnqueue(input),
      _Operation.outboxSubmit => _simulateOutboxSubmit(input),
      _Operation.outboxRetry => _simulateOutboxRetry(input),
      _Operation.acceptanceCrash => _simulateAcceptanceCrash(input),
      _Operation.cursorCheck => _simulateCursor(input),
      _Operation.cursorRead => _simulateCursorRead(input),
      _Operation.snapshotApply => _simulateSnapshot(input),
      _Operation.subjectDelete => _simulateDelete(input),
      _Operation.backupBuild => _simulateBackup(input),
      _Operation.retentionApply => _simulateRetention(input),
      _Operation.mdaInfer => _simulateMdaInference(input),
      _Operation.migrationCorpus => _simulateMigrationCorpus(input),
    };
  }

  static bool _evaluateInvariant(
    _CaseSpec spec,
    _SimulationResult simulation,
  ) {
    final evidence = simulation.evidence;
    if (spec.operation == _Operation.acceptanceCrash) {
      final eventCount = evidence['eventCount'] as int;
      final receiptCount = evidence['receiptCount'] as int;
      final changeCount = evidence['changeCount'] as int;
      final ledgerCount = evidence['ledgerCount'] as int;
      final trace = List<String>.from(evidence['trace'] as List);
      if (simulation.actual == 'rejected_precheck_zero_mutation') {
        return eventCount == 0 &&
            receiptCount == 0 &&
            changeCount == 0 &&
            ledgerCount == 0 &&
            evidence['exactlyOnceViolation'] == false &&
            !trace.any((entry) => entry.contains('idempotency:lookup')) &&
            !trace.any((entry) => entry.contains('resource:'));
      }
      if (simulation.actual == 'idempotency_conflict_zero_mutation') {
        return eventCount == 0 &&
            receiptCount == 0 &&
            changeCount == 0 &&
            evidence['exactlyOnceViolation'] == false &&
            trace.any((entry) => entry.contains('idempotency')) &&
            !trace.any((entry) => entry.contains('resource:'));
      }
      return simulation.actual == 'replay_converged' &&
          eventCount == 1 &&
          receiptCount == 1 &&
          changeCount == 1 &&
          ledgerCount == 1 &&
          evidence['ghostAccepted'] == false &&
          evidence['receiptOnly'] == false &&
          evidence['cursorAheadOfProjection'] == false &&
          evidence['duplicateEvent'] == false &&
          evidence['exactlyOnceViolation'] == false;
    }
    if (spec.operation == _Operation.migrationCorpus) {
      return simulation.evidence['contractInvariantHeld'] == true &&
          simulation.evidence['commitLedgersExactlyOnce'] == true &&
          simulation.evidence['roundTripLedgersUnique'] == true &&
          simulation.evidence['unclassifiedCount'] == 0;
    }
    return switch (spec.operation) {
      _Operation.authorityMatrix =>
        simulation.actual == 'authority_fields_complete'
            ? evidence['authorityRoot'] == 'windows_core' &&
                evidence['acceptedWriterCount'] == 1
            : simulation.actual == 'rejected_precheck' &&
                evidence['acceptedWriterCount'] == 0,
      _Operation.authorityPreAccept => simulation.actual == 'pre_accept_only'
          ? evidence['downstreamObjectCount'] == 0
          : simulation.actual == 'rejected_precheck' &&
              (evidence['downstreamObjectCount'] as int) > 0,
      _Operation.authorityOrdinaryWrite =>
        simulation.actual == 'no_user_truth_write' &&
            evidence['userTruthMutations'] == 0,
      _Operation.identitySubmit => simulation.actual == 'accepted'
          ? evidence['idempotencyLookup'] == true &&
              evidence['acceptanceMutationCount'] == 1
          : simulation.actual == 'rejected_precheck' &&
              evidence['idempotencyLookup'] == false &&
              evidence['acceptanceMutationCount'] == 0,
      _Operation.identityRepair => simulation.actual == 'accepted'
          ? evidence['activeGenerations'] == 1 &&
              evidence['oldGenerationRejected'] == true
          : simulation.actual == 'rejected_precheck' &&
              evidence['oldGenerationRejected'] == false,
      _Operation.identityBacklog => simulation.actual == 'needs_resolution'
          ? evidence['acceptanceMutationCount'] == 0 &&
              evidence['epochRewritten'] == false
          : simulation.actual == 'rejected_precheck' &&
              evidence['epochRewritten'] == false,
      _Operation.identityConflict => evidence['ledgerOverwritten'] == false &&
          (simulation.actual == 'idempotency_conflict'
              ? evidence['idempotencyLookup'] == true
              : simulation.actual == 'rejected_precheck'),
      _Operation.identityRecover => simulation.actual == 'accepted'
          ? evidence['epochAdvanced'] == true &&
              evidence['lineageVerified'] == true
          : simulation.actual == 'needs_resolution' &&
              evidence['epochAdvanced'] == false,
      _Operation.outboxEnqueue => const {
            'pending',
            'outbox_full',
            'payload_too_large'
          }.contains(simulation.actual) &&
          evidence['existingPendingPreserved'] == true,
      _Operation.outboxSubmit => switch (simulation.actual) {
          'accepted' => evidence['canonicalMutationCount'] == 1,
          'rejected_precheck' => evidence['canonicalMutationCount'] == 0,
          'expired' ||
          'protocol_rejected' =>
            evidence['problemResultPersisted'] == true,
          'needs_resolution' => evidence['problemResultPersisted'] == true &&
              evidence['containsPrivateBody'] == false,
          _ => false,
        },
      _Operation.outboxRetry => evidence['duplicateEventCount'] == 0 &&
          (simulation.actual == 'duplicate_receipt'
              ? evidence['receiptReused'] == true
              : simulation.actual == 'rejected_precheck' &&
                  evidence['receiptReused'] == false),
      _Operation.cursorCheck => const {
            'rejected_precheck',
            'resync_required',
            'cursor_current'
          }.contains(simulation.actual) &&
          evidence['cursorAdvanced'] == false,
      _Operation.cursorRead => simulation.actual == 'read_allowed'
          ? evidence['privateFeedRead'] == true
          : simulation.actual == 'rejected_precheck' &&
              evidence['privateFeedRead'] == false,
      _Operation.snapshotApply => simulation.actual == 'cursor_unchanged'
          ? evidence['cursor'] == evidence['originalCursor'] &&
              evidence['stateDigest'] == evidence['originalStateDigest'] &&
              evidence['stateUnchanged'] == true
          : simulation.actual == 'snapshot_atomically_applied' &&
              evidence['cursor'] is int &&
              (evidence['projectionCount'] as int) > 0 &&
              (evidence['trace'] as List).contains('atomic-commit'),
      _Operation.subjectDelete =>
        simulation.actual == 'online_isolated_cleanup_tracked' &&
            evidence['onlineVisible'] == false &&
            evidence['replayAllowed'] == false &&
            evidence['cleanupStatus'] == 'tracked',
      _Operation.backupBuild =>
        simulation.actual == 'backup_excluded_or_expiry_tracked' &&
            evidence['deletedSubjectExcluded'] == true &&
            evidence['immutableExpiryTracked'] == true,
      _Operation.retentionApply => evidence['historicalHeartRateRows'] == 0 &&
          (simulation.actual == 'fresh_snapshot_only'
              ? (evidence['rawDays'] as Map).values.every((value) => value == 1)
              : simulation.actual == 'rejected_precheck'),
      _Operation.mdaInfer => simulation.actual == 'no_state_inference' &&
          (evidence['signalCount'] as int) > 0 &&
          (evidence['humanStatesProduced'] as List).isEmpty,
      _Operation.acceptanceCrash || _Operation.migrationCorpus => false,
    };
  }

  _SimulationResult _simulateAuthorityMatrix(Map<String, dynamic> input) {
    final accepted = input['authority'] == 'windows_core' &&
        input['acceptedWriter'] == 'core' &&
        input['deleteOwner'] == 'core';
    return _result(
      accepted ? 'authority_fields_complete' : 'rejected_precheck',
      {
        'authorityRoot': input['authority'],
        'acceptedWriterCount': accepted ? 1 : 0
      },
    );
  }

  _SimulationResult _simulateAuthorityPreAccept(Map<String, dynamic> input) {
    final downstream = input['downstreamObjects'] as List;
    return _result(
      downstream.isEmpty ? 'pre_accept_only' : 'rejected_precheck',
      {'downstreamObjectCount': downstream.length},
    );
  }

  _SimulationResult _simulateAuthorityOrdinaryWrite(
    Map<String, dynamic> input,
  ) {
    final writes = input['writesUserTruth'] as bool;
    return _result(
      writes ? 'rejected_precheck' : 'no_user_truth_write',
      {'userTruthMutations': writes ? 1 : 0},
    );
  }

  bool _identityPrecheck(Map<String, dynamic> input) =>
      input['activeCore'] == true &&
      input['generation'] == 'current' &&
      input['epoch'] == 'current' &&
      input['fence'] == 'current' &&
      input['binding'] == 'matched' &&
      _listEquals(input['validationOrder'], _validationOrder);

  _SimulationResult _simulateIdentitySubmit(Map<String, dynamic> input) {
    final accepted = _identityPrecheck(input);
    return _result(
      accepted ? 'accepted' : 'rejected_precheck',
      {
        'idempotencyLookup': accepted,
        'acceptanceMutationCount': accepted ? 1 : 0,
      },
    );
  }

  _SimulationResult _simulateIdentityRepair(Map<String, dynamic> input) {
    final accepted =
        _identityPrecheck(input) && input['activeGenerations'] == 1;
    return _result(accepted ? 'accepted' : 'rejected_precheck', {
      'activeGenerations': input['activeGenerations'],
      'oldGenerationRejected': accepted,
    });
  }

  _SimulationResult _simulateIdentityBacklog(Map<String, dynamic> input) {
    final mutations = input['acceptanceMutations'] as List;
    final safe = _identityPrecheck(input) && mutations.isEmpty;
    return _result(safe ? 'needs_resolution' : 'rejected_precheck', {
      'acceptanceMutationCount': mutations.length,
      'epochRewritten': false,
    });
  }

  _SimulationResult _simulateIdentityConflict(Map<String, dynamic> input) {
    final prechecked = _identityPrecheck(input);
    final conflict = input['sameKey'] == true && input['sameDigest'] == false;
    return _result(
      prechecked && conflict ? 'idempotency_conflict' : 'rejected_precheck',
      {'ledgerOverwritten': false, 'idempotencyLookup': prechecked},
    );
  }

  _SimulationResult _simulateIdentityRecover(Map<String, dynamic> input) {
    final prechecked = _identityPrecheck(input);
    final verified = input['recoveryLineage'] == 'verified';
    return _result(
      prechecked && verified ? 'accepted' : 'needs_resolution',
      {'epochAdvanced': prechecked && verified, 'lineageVerified': verified},
    );
  }

  _SimulationResult _simulateOutboxEnqueue(Map<String, dynamic> input) {
    if (input['capacity'] == 'full') {
      return _result('outbox_full', {'existingPendingPreserved': true});
    }
    if (input['size'] == 'oversize') {
      return _result('payload_too_large', {'existingPendingPreserved': true});
    }
    return _result('pending', {'existingPendingPreserved': true});
  }

  _SimulationResult _simulateOutboxSubmit(Map<String, dynamic> input) {
    if (input['credential'] != 'current' || input['epoch'] != 'current') {
      return _result('rejected_precheck', {'canonicalMutationCount': 0});
    }
    if (input['ttl'] == 'expired') {
      return _result('expired', {'problemResultPersisted': true});
    }
    if (input['protocol'] == 'incompatible') {
      return _result('protocol_rejected', {'problemResultPersisted': true});
    }
    if (input['terminalResult'] == 'needs_resolution') {
      return _result('needs_resolution', {
        'problemResultPersisted': true,
        'containsPrivateBody': false,
      });
    }
    return _result('accepted', {'canonicalMutationCount': 1});
  }

  _SimulationResult _simulateOutboxRetry(Map<String, dynamic> input) {
    final duplicate = input['credential'] == 'current' &&
        input['epoch'] == 'current' &&
        input['accepted'] == true &&
        input['sameDigest'] == true;
    return _result(
      duplicate ? 'duplicate_receipt' : 'rejected_precheck',
      {'duplicateEventCount': 0, 'receiptReused': duplicate},
    );
  }

  static _SimulationResult _simulateAcceptanceCrash(
    Map<String, dynamic> input,
  ) {
    final phase = input['phase'] as String;
    final event =
        _SyntheticEvent.fromJson(input['event'] as Map<String, dynamic>);
    var state =
        _AcceptanceState.fromJson(input['initial'] as Map<String, dynamic>);
    final trace = <String>[];
    final precheckValid = event.precheckValid;
    for (final current in const ['A', 'B', 'C', 'D', 'E', 'F']) {
      if (current == 'A') state = state.enqueue(event);
      if (current == 'B') {
        _orderedAcceptancePrecheck(event, trace);
      }
      if (current == 'C' && precheckValid) {
        trace.add('idempotency:lookup');
        if (state.hasDigestConflict(event)) {
          trace.add('idempotency:conflict');
        } else {
          trace.addAll(const [
            'resource:parent-read',
            'resource:refs-read',
            'resource:payload-read',
            'commit:atomic-acceptance',
          ]);
          state = state.accept(event);
        }
      }
      if (current == 'D') state = state.loseResponse(event);
      if (current == 'E' && precheckValid && !state.hasDigestConflict(event)) {
        state = state.persistClientResult(event);
      }
      if (current == 'F' && precheckValid && !state.hasDigestConflict(event)) {
        state = state.applyProjectionAndCursor(event);
      }
      trace.add('phase-$current');
      if (current == phase) {
        state = _AcceptanceState.fromJson(_roundTrip(state.toJson()));
        trace.add('crash@$current');
        trace.add('restart@$current');
        break;
      }
    }
    state = _replayAcceptance(state, event, trace);
    final digestConflict = state.hasDigestConflict(event);
    final violations = state.invariantViolations(
      event,
      requireAccepted: precheckValid && !digestConflict,
    );
    final zeroCoreMutations = state.eventCount(event.id) == 0 &&
        state.receiptCount(event.id) == 0 &&
        state.changeCount(event.id) == 0;
    final actual = !precheckValid
        ? (zeroCoreMutations
            ? 'rejected_precheck_zero_mutation'
            : 'state_invariant_violation')
        : digestConflict
            ? (zeroCoreMutations
                ? 'idempotency_conflict_zero_mutation'
                : 'state_invariant_violation')
            : violations.isEmpty
                ? 'replay_converged'
                : 'state_invariant_violation';
    return _result(
      actual,
      {
        'crashPhaseExecuted': phase,
        'trace': trace,
        'stateDigest': _fingerprint(state.toJson()),
        'ghostAccepted': violations.contains('ghostAccepted'),
        'receiptOnly': violations.contains('receiptOnly'),
        'outboxMissingWithoutResult':
            violations.contains('outboxMissingWithoutResult'),
        'cursorAheadOfProjection':
            violations.contains('cursorAheadOfProjection'),
        'duplicateEvent': state.eventCount(event.id) > 1 ||
            state.receiptCount(event.id) > 1 ||
            state.changeCount(event.id) > 1 ||
            state.ledgerCount(event.key, event.digest) > 1,
        'exactlyOnceViolation': violations.contains('exactlyOnceViolation'),
        'eventCount': state.eventCount(event.id),
        'receiptCount': state.receiptCount(event.id),
        'changeCount': state.changeCount(event.id),
        'ledgerCount': state.ledgerCount(event.key, event.digest),
        'precheckPassed': precheckValid,
      },
    );
  }

  static _AcceptanceState _replayAcceptance(
    _AcceptanceState state,
    _SyntheticEvent event,
    List<String> trace,
  ) {
    trace.add('replay-start');
    state = state.enqueue(event);
    if (!_orderedAcceptancePrecheck(event, trace, prefix: 'replay-')) {
      return state;
    }
    trace.add('replay-idempotency:lookup');
    if (state.hasDigestConflict(event)) {
      trace.add('replay-idempotency-conflict');
      return state;
    }
    trace.addAll(const [
      'replay-resource:parent-read',
      'replay-resource:refs-read',
      'replay-resource:payload-read',
      'replay-commit:atomic-acceptance',
    ]);
    state = state.accept(event);
    state = state.persistClientResult(event);
    state = state.applyProjectionAndCursor(event);
    trace.add('replay-complete');
    return state;
  }

  static bool _orderedAcceptancePrecheck(
    _SyntheticEvent event,
    List<String> trace, {
    String prefix = '',
  }) {
    final checks = <String, bool>{
      'credential': event.credential == 'current',
      'binding': event.binding == 'current',
      'scope': event.scope == 'allowed',
      'core': event.core == 'active',
      'epoch': event.epoch == 'current',
      'fence': event.fence == 'current',
      'lineage-state': event.lineageState == 'valid',
    };
    for (final check in checks.entries) {
      trace.add('$prefix${check.key}:${check.value ? 'pass' : 'reject'}');
      if (!check.value) return false;
    }
    return true;
  }

  _SimulationResult _simulateCursor(Map<String, dynamic> input) {
    if (input['domainMatch'] != true) {
      return _result('rejected_precheck', {'cursorAdvanced': false});
    }
    if (input['watermark'] == 'behind') {
      return _result('resync_required', {'cursorAdvanced': false});
    }
    return _result('cursor_current', {'cursorAdvanced': false});
  }

  _SimulationResult _simulateCursorRead(Map<String, dynamic> input) {
    final allowed = input['tokenScope'] == 'chat_read' &&
        input['requestedDomain'] == 'chat';
    return _result(
      allowed ? 'read_allowed' : 'rejected_precheck',
      {'privateFeedRead': allowed},
    );
  }

  _SimulationResult _simulateSnapshot(Map<String, dynamic> input) {
    final original = _SnapshotLocal.fromJson(
      input['local'] as Map<String, dynamic>,
    );
    final envelope = input['snapshot'] as Map<String, dynamic>;
    final crashPhase = input['crashPhase'] as String;
    final valid = envelope['authenticated'] == true &&
        envelope['currentLineage'] == true &&
        envelope['digestValid'] == true;
    final originalStateDigest = _fingerprint(original.toJson());
    final trace = <String>['validate'];
    if (!valid) {
      return _result('cursor_unchanged', {
        'trace': trace,
        'stateDigest': originalStateDigest,
        'cursor': original.cursor,
        'originalStateDigest': originalStateDigest,
        'originalCursor': original.cursor,
        'stateUnchanged': true,
      });
    }
    trace.add('stage');
    if (crashPhase == 'stage') {
      final restarted = _SnapshotLocal.fromJson(_roundTrip(original.toJson()));
      trace.addAll(['crash@stage', 'restart@stage']);
      return _result('cursor_unchanged', {
        'trace': trace,
        'stateDigest': _fingerprint(restarted.toJson()),
        'cursor': restarted.cursor,
        'originalStateDigest': originalStateDigest,
        'originalCursor': original.cursor,
        'stateUnchanged':
            _deepExactEquals(restarted.toJson(), original.toJson()),
      });
    }
    var committed = original.commit(envelope);
    trace.add('atomic-commit');
    if (crashPhase == 'commit') {
      committed = _SnapshotLocal.fromJson(_roundTrip(committed.toJson()));
      trace.addAll(['crash@commit', 'restart@commit', 'replay-validated']);
      committed = committed.commit(envelope);
    }
    return _result('snapshot_atomically_applied', {
      'trace': trace,
      'stateDigest': _fingerprint(committed.toJson()),
      'cursor': committed.cursor,
      'originalStateDigest': originalStateDigest,
      'originalCursor': original.cursor,
      'stateUnchanged': false,
      'projectionCount': committed.projectionIds.length,
    });
  }

  _SimulationResult _simulateDelete(Map<String, dynamic> input) {
    final subject = Map<String, dynamic>.from(
      input['subject'] as Map<String, dynamic>,
    );
    final cleanup = Map<String, dynamic>.from(
      input['cleanup'] as Map<String, dynamic>,
    );
    subject['tombstoned'] = true;
    subject['onlineVisible'] = false;
    subject['replayAllowed'] = false;
    cleanup['status'] = 'tracked';
    cleanup['subjectId'] = subject['id'];
    return _result('online_isolated_cleanup_tracked', {
      'stateDigest': _fingerprint({'subject': subject, 'cleanup': cleanup}),
      'onlineVisible': false,
      'replayAllowed': false,
      'cleanupStatus': cleanup['status'],
    });
  }

  _SimulationResult _simulateBackup(Map<String, dynamic> input) {
    final subject = input['subject'] as Map<String, dynamic>;
    final manifest = input['newManifest'] as Map<String, dynamic>;
    final ids = List<String>.from(manifest['subjectIds'] as List)
      ..removeWhere((id) => id == subject['id']);
    final immutable = input['immutableBackup'] as Map<String, dynamic>;
    final expiryTracked = immutable['expiryPolicy'] == 'policy-v1';
    return _result('backup_excluded_or_expiry_tracked', {
      'newManifestSubjectIds': ids..sort(),
      'deletedSubjectExcluded': !ids.contains(subject['id']),
      'immutableExpiryTracked': expiryTracked,
    });
  }

  _SimulationResult _simulateRetention(Map<String, dynamic> input) {
    final raw = input['rawRetention'] as Map<String, dynamic>;
    final valid = raw.values.every((value) => value == 1) &&
        input['heartRate'] == 'fresh_current_only' &&
        input['summaryRetention'] == 'until_user_delete';
    return _result(valid ? 'fresh_snapshot_only' : 'rejected_precheck', {
      'rawDays': Map<String, dynamic>.from(raw),
      'historicalHeartRateRows': 0,
    });
  }

  _SimulationResult _simulateMdaInference(Map<String, dynamic> input) {
    final signals = List<String>.from(input['signals'] as List);
    final humanStates = <String>[];
    return _result('no_state_inference', {
      'signalCount': signals.length,
      'humanStatesProduced': humanStates,
    });
  }

  _SimulationResult _simulateMigrationCorpus(Map<String, dynamic> input) {
    final caseId = input['caseId'] as String;
    final definition = migrationCaseDefinitions.singleWhere(
      (candidate) => candidate.id == caseId,
      orElse: () => fail(
        FailureClass.unsupported,
        'migration operation has no canonical case definition: $caseId',
      ),
    );
    return _executeMigrationCase(definition, input);
  }

  void _validateManifest(Map<String, dynamic> manifest) {
    _expectExactKeys(
      manifest,
      {
        'schemaVersion',
        'contractVersion',
        'synthetic',
        'purpose',
        'declaredFiles',
        'scenarioSha',
        'caseInputDigests',
        'fixtureDimensions',
        'exactExpandedCrashPoints',
        'exactFailurePoints',
      },
      'manifest',
    );
    if (manifest['schemaVersion'] != schemaVersion) {
      fail(FailureClass.unsupported, 'unknown_manifest_schema_version');
    }
    if (manifest['synthetic'] != true ||
        manifest['contractVersion'] != contractVersion ||
        manifest['purpose'] != purpose ||
        manifest['scenarioSha'] is! String ||
        (manifest['scenarioSha'] as String).length != 64 ||
        manifest['caseInputDigests'] is! Map ||
        manifest['fixtureDimensions'] is! Map ||
        manifest['exactExpandedCrashPoints'] is! List ||
        manifest['exactFailurePoints'] is! List ||
        manifest['declaredFiles'] is! List ||
        (manifest['declaredFiles'] as List).any((value) => value is! String) ||
        (manifest['declaredFiles'] as List).length != _allowedFiles.length ||
        !_setEquals(
          (manifest['declaredFiles'] as List).cast<String>().toSet(),
          _allowedFiles,
        )) {
      fail(
        FailureClass.inputRejected,
        'manifest must declare the canonical synthetic schema and allowlist',
      );
    }
  }

  Map<String, dynamic> _json(File file) {
    if (!file.existsSync() || file.lengthSync() > 1024 * 1024) {
      fail(FailureClass.inputRejected, 'fixture is missing or too large');
    }
    try {
      final value = jsonDecode(file.readAsStringSync());
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // The bounded public failure below deliberately hides parser internals.
    }
    fail(FailureClass.inputRejected, 'invalid JSON: ${file.path}');
  }

  String _directory(String path, String label) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      fail(FailureClass.pathRejected, '$label cannot be a link');
    }
    if (type != FileSystemEntityType.directory) {
      fail(FailureClass.pathRejected, '$label must be an existing directory');
    }
    return Directory(path).resolveSymbolicLinksSync();
  }

  void _rejectLinks(String root, String label) {
    for (final entry in Directory(root).listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (FileSystemEntity.typeSync(entry.path, followLinks: false) ==
          FileSystemEntityType.link) {
        fail(FailureClass.pathRejected, '$label contains a link');
      }
    }
  }

  bool _strictChild(String child, String parent) =>
      child != parent && _within(child, parent);
  bool _within(String child, String parent) =>
      child == parent || child.startsWith('$parent${Platform.pathSeparator}');
  String _join(String left, String right) =>
      '$left${Platform.pathSeparator}$right';
  String _relative(String path, String root) =>
      path.substring(root.length + 1).replaceAll('\\', '/');
}

const _validationOrder = [
  'protocol',
  'credential',
  'binding_scope',
  'authority_fence',
  'lineage_state',
  'idempotency',
  'resource',
];

Map<String, _CaseSpec> _buildCaseSpecs() {
  final specs = <String, _CaseSpec>{};

  void add(
    String id,
    _Family family,
    _Operation operation,
    String expected,
    String invariant,
    _Rule schema,
  ) {
    specs[id] = _CaseSpec(family, operation, expected, invariant, schema);
  }

  void authority(
    String id,
    String domain,
    String preAccept,
    String receipt,
    String recovery,
  ) {
    add(
      id,
      _Family.authorityMatrix,
      _Operation.authorityMatrix,
      'authority_fields_complete',
      '$domain has one Core authority and canonical receipt lineage',
      _inputRule(_Operation.authorityMatrix, {
        'domain': _string({domain}),
        'authority': _string({'windows_core'}),
        'acceptedWriter': _string({'core'}),
        'preAccept': _string({preAccept}),
        'receiptChange': _string({receipt}),
        'deleteOwner': _string({'core'}),
        'recoverySource': _string({recovery}),
      }),
    );
  }

  authority('authority-card', 'card', 'pending_command', 'core_receipt_change',
      'canonical_lineage');
  authority('authority-user-truth', 'user-truth', 'explicit_record_intent',
      'core_receipt_change', 'canonical_operations');
  authority('authority-source', 'source', 'staged_import',
      'core_receipt_change', 'verified_original_lineage');
  authority('authority-evidence', 'evidence', 'review_candidate',
      'immutable_claim_change', 'claim_source_lineage');
  authority('authority-dreaming', 'dreaming', 'worker_candidate',
      'core_receipt_change', 'relationship_memory_lineage');
  authority('authority-task-artifact', 'task-artifact', 'task_local_draft',
      'task_receipt_change', 'task_artifact_lineage');
  authority('authority-chat', 'chat', 'device_outbox', 'chat_change',
      'immutable_message_lineage');
  authority('authority-activity', 'activity', 'probe_spool', 'activity_change',
      'retained_evidence_summary');

  void preAccept(String id, String domain, String state) {
    add(
      id,
      _Family.authorityMatrix,
      _Operation.authorityPreAccept,
      'pre_accept_only',
      '$domain cannot create downstream accepted objects before Core acceptance',
      _inputRule(_Operation.authorityPreAccept, {
        'domain': _string({domain}),
        'preAccept': _string({state}),
        'downstreamObjects': _ListRule(_string(), min: 0, max: 0),
      }),
    );
  }

  preAccept('authority-capture', 'capture', 'local_capture');
  preAccept(
      'authority-import-candidate', 'import-candidate', 'parser_candidate');
  preAccept('authority-link-inbox', 'link-inbox', 'extracted_link');

  void ordinary(String id, String domain) {
    add(
      id,
      _Family.authorityMatrix,
      _Operation.authorityOrdinaryWrite,
      'no_user_truth_write',
      'ordinary $domain creates no User-truth mutation',
      _inputRule(_Operation.authorityOrdinaryWrite, {
        'domain': _string({domain}),
        'writesUserTruth': const _BoolRule(),
      }),
    );
  }

  ordinary('chat-no-auto-user-truth', 'chat');
  ordinary('activity-no-auto-user-truth', 'activity');

  final identityBase = <String, _Rule>{
    'activeCore': const _BoolRule(),
    'generation': _string({'current', 'revoked'}),
    'epoch': _string({'current', 'old'}),
    'fence': _string({'current', 'old'}),
    'binding': _string({'matched', 'mismatch'}),
    'validationOrder': const _ExactListRule(_validationOrder),
  };

  void identitySubmit(String id, String expected, String invariant) {
    add(
      id,
      _Family.identityFencing,
      _Operation.identitySubmit,
      expected,
      invariant,
      _inputRule(_Operation.identitySubmit, identityBase),
    );
  }

  identitySubmit('active-core-accept', 'accepted',
      'only the active bound Core accepts after ordered precheck');
  identitySubmit('superseded-core', 'rejected_precheck',
      'superseded Core fails before idempotency lookup');
  identitySubmit('old-epoch', 'rejected_precheck',
      'old epoch fails before receipt lookup');
  identitySubmit('revoked-generation', 'rejected_precheck',
      'revoked generation cannot learn duplicate status');
  identitySubmit('cross-device-impersonation', 'rejected_precheck',
      'caller binding mismatch fails closed');
  identitySubmit('old-worker-lease', 'rejected_precheck',
      'worker lease cannot cross authority epoch');
  identitySubmit('same-core-stale-workload', 'rejected_precheck',
      'stale workload fence fails inside active Core');

  add(
    'repair-one-active-generation',
    _Family.identityFencing,
    _Operation.identityRepair,
    'accepted',
    're-pair leaves exactly one active generation',
    _inputRule(_Operation.identityRepair, {
      ...identityBase,
      'activeGenerations': const _IntRule(min: 0, max: 2),
    }),
  );
  add(
    'backlog-needs-resolution',
    _Family.identityFencing,
    _Operation.identityBacklog,
    'needs_resolution',
    'old backlog is preserved without acceptance mutation or epoch rewrite',
    _inputRule(_Operation.identityBacklog, {
      ...identityBase,
      'acceptanceMutations': _ListRule(_string(), min: 0, max: 0),
    }),
  );
  add(
    'same-key-different-digest',
    _Family.identityFencing,
    _Operation.identityConflict,
    'idempotency_conflict',
    'same key with a different digest never overwrites the ledger',
    _inputRule(_Operation.identityConflict, {
      ...identityBase,
      'sameKey': const _BoolRule(),
      'sameDigest': const _BoolRule(),
    }),
  );
  add(
    'missing-recovery-lineage',
    _Family.identityFencing,
    _Operation.identityRecover,
    'needs_resolution',
    'unverified recovery lineage cannot activate a Core',
    _inputRule(_Operation.identityRecover, {
      ...identityBase,
      'recoveryLineage': _string({'missing', 'verified'}),
    }),
  );

  final outboxBase = <String, _Rule>{
    'capacity': _string({'open', 'full'}),
    'size': _string({'ok', 'oversize'}),
    'ttl': _string({'valid', 'expired'}),
    'protocol': _string({'compatible', 'incompatible'}),
    'credential': _string({'current', 'revoked'}),
    'epoch': _string({'current', 'old'}),
  };
  add(
      'outbox-full',
      _Family.outboxCrash,
      _Operation.outboxEnqueue,
      'outbox_full',
      'full outbox preserves existing pending intents',
      _inputRule(_Operation.outboxEnqueue, outboxBase));
  add(
      'outbox-oversize',
      _Family.outboxCrash,
      _Operation.outboxEnqueue,
      'payload_too_large',
      'oversize intent cannot evict pending data',
      _inputRule(_Operation.outboxEnqueue, outboxBase));
  add(
      'outbox-ttl',
      _Family.outboxCrash,
      _Operation.outboxSubmit,
      'expired',
      'expired intent persists an auditable problem result',
      _inputRule(_Operation.outboxSubmit, {
        ...outboxBase,
        'terminalResult': _string({'none', 'needs_resolution'}),
      }));
  add(
      'outbox-protocol',
      _Family.outboxCrash,
      _Operation.outboxSubmit,
      'protocol_rejected',
      'incompatible protocol is a terminal refusal',
      _inputRule(_Operation.outboxSubmit, {
        ...outboxBase,
        'terminalResult': _string({'none', 'needs_resolution'}),
      }));
  add(
      'outbox-refusal',
      _Family.outboxCrash,
      _Operation.outboxSubmit,
      'needs_resolution',
      'refusal persists no private body or credential',
      _inputRule(_Operation.outboxSubmit, {
        ...outboxBase,
        'terminalResult': _string({'none', 'needs_resolution'}),
      }));
  add(
    'lost-accepted-response-current-identity',
    _Family.outboxCrash,
    _Operation.outboxRetry,
    'duplicate_receipt',
    'current identity retry reuses the receipt without duplicate event',
    _inputRule(_Operation.outboxRetry, {
      ...outboxBase,
      'accepted': const _BoolRule(),
      'sameDigest': const _BoolRule(),
    }),
  );

  final eventRule = _ObjectRule({
    'id': _string(),
    'key': _string(),
    'digest': _string(),
    'payload': _string(),
    'originSequence': const _IntRule(min: 1, max: 1000000),
    'credential': _string({'current', 'revoked'}),
    'binding': _string({'current', 'wrong'}),
    'scope': _string({'allowed', 'denied'}),
    'core': _string({'active', 'superseded'}),
    'epoch': _string({'current', 'old'}),
    'fence': _string({'current', 'old'}),
    'lineageState': _string({'valid', 'invalid'}),
  });
  final acceptanceInitialRule = _ObjectRule({
    'outboxIds': _ListRule(_string(), min: 0, max: 8, unique: true),
    'optimisticIds': _ListRule(_string(), min: 0, max: 8, unique: true),
    'resultIds': _ListRule(_string(), min: 0, max: 8, unique: true),
    'projectionIds': _ListRule(_string(), min: 0, max: 8, unique: true),
    'cursor': const _IntRule(min: 0, max: 1000000),
    'coreEventIds': _ListRule(_string(), min: 0, max: 8),
    'receiptIds': _ListRule(_string(), min: 0, max: 8),
    'changeIds': _ListRule(_string(), min: 0, max: 8),
    'ledgerEntries': _ListRule(
      _ObjectRule({'key': _string(), 'digest': _string()}),
      min: 0,
      max: 8,
    ),
  });
  for (final phase in const ['A', 'B', 'C', 'D', 'E', 'F']) {
    add(
      'crash-$phase',
      _Family.outboxCrash,
      _Operation.acceptanceCrash,
      'replay_converged',
      'phase $phase crash/restart/replay has no partial or duplicate state',
      _inputRule(_Operation.acceptanceCrash, {
        'phase': _string({phase}),
        'event': eventRule,
        'initial': acceptanceInitialRule,
      }),
    );
  }
  for (final invalid in const {
    'revoked-credential': [
      'revoked',
      'current',
      'allowed',
      'active',
      'current',
      'current',
      'valid'
    ],
    'wrong-binding': [
      'current',
      'wrong',
      'allowed',
      'active',
      'current',
      'current',
      'valid'
    ],
    'denied-scope': [
      'current',
      'current',
      'denied',
      'active',
      'current',
      'current',
      'valid'
    ],
    'superseded-core': [
      'current',
      'current',
      'allowed',
      'superseded',
      'current',
      'current',
      'valid'
    ],
    'old-epoch': [
      'current',
      'current',
      'allowed',
      'active',
      'old',
      'current',
      'valid'
    ],
    'stale-fence': [
      'current',
      'current',
      'allowed',
      'active',
      'current',
      'old',
      'valid'
    ],
    'invalid-lineage': [
      'current',
      'current',
      'allowed',
      'active',
      'current',
      'current',
      'invalid'
    ],
  }.entries) {
    add(
      'crash-precheck-${invalid.key}',
      _Family.outboxCrash,
      _Operation.acceptanceCrash,
      'rejected_precheck_zero_mutation',
      'invalid ${invalid.key} fails at B with zero Core mutation',
      _inputRule(_Operation.acceptanceCrash, {
        'phase': _string({'B'}),
        'event': _ObjectRule({
          'id': _string(),
          'key': _string(),
          'digest': _string(),
          'payload': _string(),
          'originSequence': const _IntRule(min: 1, max: 1000000),
          'credential': _string({invalid.value[0]}),
          'binding': _string({invalid.value[1]}),
          'scope': _string({invalid.value[2]}),
          'core': _string({invalid.value[3]}),
          'epoch': _string({invalid.value[4]}),
          'fence': _string({invalid.value[5]}),
          'lineageState': _string({invalid.value[6]}),
        }),
        'initial': acceptanceInitialRule,
      }),
    );
  }
  add(
    'crash-idempotency-digest-conflict',
    _Family.outboxCrash,
    _Operation.acceptanceCrash,
    'idempotency_conflict_zero_mutation',
    'same idempotency key with a different digest fails with zero Core mutation',
    _inputRule(_Operation.acceptanceCrash, {
      'phase': _string({'C'}),
      'event': eventRule,
      'initial': acceptanceInitialRule,
    }),
  );

  add(
    'cursor-domain-isolation',
    _Family.cursorSnapshot,
    _Operation.cursorCheck,
    'rejected_precheck',
    'chat and activity cursors cannot cross domains',
    _inputRule(_Operation.cursorCheck, {
      'domainMatch': const _BoolRule(),
      'watermark': _string({'current', 'behind'}),
    }),
  );
  add(
    'watermark-resync',
    _Family.cursorSnapshot,
    _Operation.cursorCheck,
    'resync_required',
    'cursor behind the retained watermark cannot silently continue',
    _inputRule(_Operation.cursorCheck, {
      'domainMatch': const _BoolRule(),
      'watermark': _string({'current', 'behind'}),
    }),
  );
  add(
    'activity-token-reads-chat',
    _Family.cursorSnapshot,
    _Operation.cursorRead,
    'rejected_precheck',
    'write-only activity token cannot read chat',
    _inputRule(_Operation.cursorRead, {
      'tokenScope': _string({'chat_read', 'activity_write'}),
      'requestedDomain': _string({'chat', 'activity'}),
    }),
  );

  final localSnapshotRule = _ObjectRule({
    'projectionIds': _ListRule(_string(), min: 1, max: 8, unique: true),
    'cursor': const _IntRule(min: 0, max: 1000000),
    'snapshotReceiptIds': _ListRule(_string(), min: 0, max: 8, unique: true),
  });
  final envelopeRule = _ObjectRule({
    'id': _string(),
    'authenticated': const _BoolRule(),
    'currentLineage': const _BoolRule(),
    'digestValid': const _BoolRule(),
    'baseCursor': const _IntRule(min: 1, max: 1000000),
    'projectionIds': _ListRule(_string(), min: 1, max: 8, unique: true),
  });
  void snapshot(
      String id, String expected, String invariant, Set<String> phases) {
    add(
      id,
      _Family.cursorSnapshot,
      _Operation.snapshotApply,
      expected,
      invariant,
      _inputRule(_Operation.snapshotApply, {
        'local': localSnapshotRule,
        'snapshot': envelopeRule,
        'crashPhase': _string(phases),
      }),
    );
  }

  snapshot('old-snapshot', 'cursor_unchanged',
      'old lineage snapshot does not advance cursor', {'none'});
  snapshot('corrupt-snapshot', 'cursor_unchanged',
      'bad digest snapshot does not advance cursor', {'none'});
  snapshot('snapshot-interrupted', 'cursor_unchanged',
      'stage crash keeps old projection and cursor', {'stage'});
  snapshot(
      'authenticated-snapshot',
      'snapshot_atomically_applied',
      'authenticated snapshot commits projection and cursor atomically',
      {'none'});
  snapshot('snapshot-commit-restart', 'snapshot_atomically_applied',
      'commit crash restarts and converges atomically', {'commit'});

  add(
    'revoke-delete-isolation',
    _Family.deleteRetentionMda,
    _Operation.subjectDelete,
    'online_isolated_cleanup_tracked',
    'tombstone blocks online read/replay before tracked cleanup',
    _inputRule(_Operation.subjectDelete, {
      'subject': _ObjectRule({
        'id': _string(),
        'tombstoned': const _BoolRule(),
        'onlineVisible': const _BoolRule(),
        'replayAllowed': const _BoolRule(),
      }),
      'cleanup': _ObjectRule({
        'status': _string({'not_started'})
      }),
    }),
  );
  add(
    'backup-retention',
    _Family.deleteRetentionMda,
    _Operation.backupBuild,
    'backup_excluded_or_expiry_tracked',
    'new manifest excludes tombstone and immutable backup tracks expiry',
    _inputRule(_Operation.backupBuild, {
      'subject': _ObjectRule({
        'id': _string(),
        'tombstoned': const _BoolRule(),
      }),
      'newManifest': _ObjectRule({
        'subjectIds': _ListRule(_string(), min: 1, max: 8, unique: true),
      }),
      'immutableBackup': _ObjectRule({
        'containsSubject': const _BoolRule(),
        'expiryPolicy': _string({'policy-v1'}),
      }),
    }),
  );
  add(
    'mda-retention',
    _Family.deleteRetentionMda,
    _Operation.retentionApply,
    'fresh_snapshot_only',
    'raw/spool/BLE/diagnostic are one day and HR is fresh-only',
    _inputRule(_Operation.retentionApply, {
      'rawRetention': const _ObjectRule({
        'eventDays': _IntRule(min: 0, max: 30),
        'spoolDays': _IntRule(min: 0, max: 30),
        'bleDays': _IntRule(min: 0, max: 30),
        'diagnosticDays': _IntRule(min: 0, max: 30),
      }),
      'heartRate': _string({'fresh_current_only', 'historical'}),
      'summaryRetention': _string({'until_user_delete', 'forever'}),
    }),
  );
  add(
    'mda-no-inference',
    _Family.deleteRetentionMda,
    _Operation.mdaInfer,
    'no_state_inference',
    'non-empty weak signals produce no human state',
    _inputRule(_Operation.mdaInfer, {
      'signals': _ListRule(
        _string({'network', 'heartbeat', 'silence', 'no_reply', 'single_hr'}),
        min: 1,
        max: 5,
        unique: true,
      ),
    }),
  );

  for (final definition in migrationCaseDefinitions) {
    add(
      definition.id,
      _Family.migrationRecovery,
      _Operation.migrationCorpus,
      'migration_case_verified',
      'canonical migration input derives classification, hashes, manifests, '
          'counts and restart convergence from raw state',
      const _PinnedMigrationInputRule(),
    );
  }

  return Map.unmodifiable(specs);
}

_ObjectRule _inputRule(_Operation operation, Map<String, _Rule> fields) =>
    _ObjectRule({
      'operation': _string({operation.label}),
      ...fields
    });

_StringRule _string([Set<String>? allowed]) => _StringRule(allowed: allowed);

class _AcceptanceState {
  const _AcceptanceState({
    required this.outboxIds,
    required this.optimisticIds,
    required this.resultIds,
    required this.projectionIds,
    required this.cursor,
    required this.coreEventIds,
    required this.receiptIds,
    required this.changeIds,
    required this.ledgerEntries,
  });

  factory _AcceptanceState.fromJson(Map<String, dynamic> json) =>
      _AcceptanceState(
        outboxIds: List<String>.from(json['outboxIds'] as List),
        optimisticIds: List<String>.from(json['optimisticIds'] as List),
        resultIds: List<String>.from(json['resultIds'] as List),
        projectionIds: List<String>.from(json['projectionIds'] as List),
        cursor: json['cursor'] as int,
        coreEventIds: List<String>.from(json['coreEventIds'] as List),
        receiptIds: List<String>.from(json['receiptIds'] as List),
        changeIds: List<String>.from(json['changeIds'] as List),
        ledgerEntries: (json['ledgerEntries'] as List)
            .map(
                (value) => _LedgerEntry.fromJson(value as Map<String, dynamic>))
            .toList(),
      );

  final List<String> outboxIds;
  final List<String> optimisticIds;
  final List<String> resultIds;
  final List<String> projectionIds;
  final int cursor;
  final List<String> coreEventIds;
  final List<String> receiptIds;
  final List<String> changeIds;
  final List<_LedgerEntry> ledgerEntries;

  _AcceptanceState enqueue(_SyntheticEvent event) => _copy(
        outboxIds:
            outboxIds.contains(event.id) ? outboxIds : [...outboxIds, event.id],
        optimisticIds: optimisticIds.contains(event.id)
            ? optimisticIds
            : [...optimisticIds, event.id],
      );

  _AcceptanceState accept(_SyntheticEvent event) {
    if (ledgerEntries.any(
      (entry) => entry.key == event.key && entry.digest == event.digest,
    )) {
      return _copy();
    }
    if (hasDigestConflict(event)) return _copy();
    return _copy(
      coreEventIds: [...coreEventIds, event.id],
      receiptIds: [...receiptIds, event.id],
      changeIds: [...changeIds, event.id],
      ledgerEntries: [...ledgerEntries, _LedgerEntry(event.key, event.digest)],
    );
  }

  bool hasDigestConflict(_SyntheticEvent event) => ledgerEntries.any(
        (entry) => entry.key == event.key && entry.digest != event.digest,
      );

  _AcceptanceState loseResponse(_SyntheticEvent event) => _copy();

  _AcceptanceState persistClientResult(_SyntheticEvent event) => _copy(
        outboxIds: [...outboxIds]..removeWhere((id) => id == event.id),
        resultIds:
            resultIds.contains(event.id) ? resultIds : [...resultIds, event.id],
      );

  _AcceptanceState applyProjectionAndCursor(_SyntheticEvent event) => _copy(
        projectionIds: projectionIds.contains(event.id)
            ? projectionIds
            : [...projectionIds, event.id],
        cursor: event.originSequence > cursor ? event.originSequence : cursor,
      );

  int eventCount(String id) =>
      coreEventIds.where((value) => value == id).length;
  int receiptCount(String id) =>
      receiptIds.where((value) => value == id).length;
  int changeCount(String id) => changeIds.where((value) => value == id).length;
  int ledgerCount(String key, String digest) => ledgerEntries
      .where((entry) => entry.key == key && entry.digest == digest)
      .length;

  List<String> invariantViolations(
    _SyntheticEvent event, {
    required bool requireAccepted,
  }) {
    final violations = <String>[];
    if (optimisticIds.contains(event.id) &&
        !outboxIds.contains(event.id) &&
        !resultIds.contains(event.id)) {
      violations.add('ghostAccepted');
    }
    if (receiptCount(event.id) > 0 &&
        (eventCount(event.id) != 1 ||
            changeCount(event.id) != 1 ||
            ledgerCount(event.key, event.digest) != 1)) {
      violations.add('receiptOnly');
    }
    if (!outboxIds.contains(event.id) && !resultIds.contains(event.id)) {
      violations.add('outboxMissingWithoutResult');
    }
    if (cursor >= event.originSequence && !projectionIds.contains(event.id)) {
      violations.add('cursorAheadOfProjection');
    }
    if (requireAccepted &&
        (eventCount(event.id) != 1 ||
            receiptCount(event.id) != 1 ||
            changeCount(event.id) != 1 ||
            ledgerCount(event.key, event.digest) != 1)) {
      violations.add('exactlyOnceViolation');
    }
    return violations;
  }

  _AcceptanceState _copy({
    List<String>? outboxIds,
    List<String>? optimisticIds,
    List<String>? resultIds,
    List<String>? projectionIds,
    int? cursor,
    List<String>? coreEventIds,
    List<String>? receiptIds,
    List<String>? changeIds,
    List<_LedgerEntry>? ledgerEntries,
  }) =>
      _AcceptanceState(
        outboxIds: List.unmodifiable(outboxIds ?? this.outboxIds),
        optimisticIds: List.unmodifiable(optimisticIds ?? this.optimisticIds),
        resultIds: List.unmodifiable(resultIds ?? this.resultIds),
        projectionIds: List.unmodifiable(projectionIds ?? this.projectionIds),
        cursor: cursor ?? this.cursor,
        coreEventIds: List.unmodifiable(coreEventIds ?? this.coreEventIds),
        receiptIds: List.unmodifiable(receiptIds ?? this.receiptIds),
        changeIds: List.unmodifiable(changeIds ?? this.changeIds),
        ledgerEntries: List.unmodifiable(ledgerEntries ?? this.ledgerEntries),
      );

  Map<String, dynamic> toJson() => {
        'outboxIds': _sorted(outboxIds),
        'optimisticIds': _sorted(optimisticIds),
        'resultIds': _sorted(resultIds),
        'projectionIds': _sorted(projectionIds),
        'cursor': cursor,
        'coreEventIds': _sorted(coreEventIds),
        'receiptIds': _sorted(receiptIds),
        'changeIds': _sorted(changeIds),
        'ledgerEntries': ledgerEntries.map((entry) => entry.toJson()).toList(),
      };
}

class _LedgerEntry {
  const _LedgerEntry(this.key, this.digest);

  factory _LedgerEntry.fromJson(Map<String, dynamic> json) =>
      _LedgerEntry(json['key'] as String, json['digest'] as String);

  final String key;
  final String digest;

  Map<String, dynamic> toJson() => {'key': key, 'digest': digest};
}

class _SyntheticEvent {
  const _SyntheticEvent(
    this.id,
    this.key,
    this.digest,
    this.payload,
    this.originSequence,
    this.credential,
    this.binding,
    this.scope,
    this.core,
    this.epoch,
    this.fence,
    this.lineageState,
  );

  factory _SyntheticEvent.fromJson(Map<String, dynamic> json) =>
      _SyntheticEvent(
        json['id'] as String,
        json['key'] as String,
        json['digest'] as String,
        json['payload'] as String,
        json['originSequence'] as int,
        json['credential'] as String,
        json['binding'] as String,
        json['scope'] as String,
        json['core'] as String,
        json['epoch'] as String,
        json['fence'] as String,
        json['lineageState'] as String,
      );

  final String id;
  final String key;
  final String digest;
  final String payload;
  final int originSequence;
  final String credential;
  final String binding;
  final String scope;
  final String core;
  final String epoch;
  final String fence;
  final String lineageState;

  bool get precheckValid =>
      credential == 'current' &&
      binding == 'current' &&
      scope == 'allowed' &&
      core == 'active' &&
      epoch == 'current' &&
      fence == 'current' &&
      lineageState == 'valid';
}

class _DerivedMigrationTarget {
  const _DerivedMigrationTarget(
    this.classification,
    this.outcome,
    this.targetRole,
    this.migrationAction,
    this.blockedReason,
    this.acceptedTarget,
    this.preservation,
  );

  final String classification;
  final String outcome;
  final String targetRole;
  final String migrationAction;
  final String? blockedReason;
  final Map<String, dynamic>? acceptedTarget;
  final Map<String, dynamic> preservation;
}

FormalMigrationObjectSpec _formalSpecFor(String objectType) =>
    formalMigrationObjectCatalog.singleWhere(
      (spec) => spec.objectType == objectType,
      orElse: () => fail(
        FailureClass.unsupported,
        'unclassified formal migration object: $objectType',
      ),
    );

_DerivedMigrationTarget _deriveMigrationTarget(
  MigrationCaseDefinition definition,
  Map<String, dynamic> legacy,
) {
  final details = Map<String, dynamic>.from(legacy['details'] as Map);
  final conversion = switch (definition.objectType) {
    'neutral_card' ||
    'user_truth' =>
      _convertCardRaw(definition.objectType, details),
    'rich_text_document' => _convertRichTextRaw(details),
    'card_asset_provenance_relation' => _convertAssetRaw(details),
    'card_revision_history' => _convertHistoryRaw(details),
    'anchor' => _convertAnchorRaw(details),
    'evidence_claim' => _convertEvidenceRaw(details),
    'task_artifact' => _convertTaskRaw(details),
    'capture' ||
    'import_candidate' ||
    'link_inbox_item' =>
      _convertIntakeRaw(definition.objectType, details),
    'domain_operation_receipt_change' => _convertCommitRaw(details),
    'backup_manifest' => _convertFormalCatalogRaw(details),
    _ => fail(
        FailureClass.unsupported,
        'no raw converter for ${definition.objectType}',
      ),
  };
  final formal = _formalSpecFor(definition.objectType);
  final preservation = <String, dynamic>{
    'schema': 'legacy-raw-preservation-v1',
    'stableId': legacy['stableId'],
    'rawDigest': _canonicalSha256({
      'bytes': legacy['bytes'],
      'details': legacy['details'],
    }),
    'refs': List<String>.from(legacy['refs'] as List),
    'reason': conversion.blockedReason ?? 'rollback_source',
  };
  if (conversion.classification == 'blocked') {
    return _DerivedMigrationTarget(
      conversion.classification,
      conversion.outcome,
      formal.targetRole,
      'blocked',
      conversion.blockedReason,
      null,
      preservation,
    );
  }
  final stableId = legacy['stableId'];
  final fingerprint = _canonicalSha256({
    'bytes': legacy['bytes'],
    'details': legacy['details'],
  });
  final acceptedTarget = switch (definition.objectType) {
    'neutral_card' => <String, dynamic>{
        'schema': 'hereiam-card-envelope-v1',
        'cardId': conversion.payload['cardId'],
        'markdown': conversion.payload['markdown'],
        'sourceFingerprint': fingerprint,
      },
    'user_truth' => <String, dynamic>{
        'schema': 'user-truth-relation-v1',
        'truthRelationId': stableId,
        'cardRef': conversion.payload['cardRef'],
        'provenance': conversion.payload['provenance'],
        'authorization': conversion.payload['authorization'],
        'payloadDigest': fingerprint,
      },
    'rich_text_document' => <String, dynamic>{
        'schema': 'richtext-compatibility-map-v1',
        'cacheKey': '$stableId:$fingerprint',
        ...conversion.payload,
        'authoritative': false,
      },
    'card_asset_provenance_relation' => <String, dynamic>{
        'schema': 'asset-provenance-relation-v1',
        'relationId': stableId,
        ...conversion.payload,
        'claimCreated': false,
      },
    'card_revision_history' => <String, dynamic>{
        'schema': 'card-revision-lineage-v1',
        'revisionId': stableId,
        ...conversion.payload,
        'envelopeHash': fingerprint,
      },
    'anchor' => <String, dynamic>{
        'schema': 'anchor-record-v1',
        'anchorId': stableId,
        ...conversion.payload,
      },
    'evidence_claim' => <String, dynamic>{
        'schema': 'evidence-proposal-v1',
        'proposalId': stableId,
        ...conversion.payload,
      },
    'task_artifact' => <String, dynamic>{
        'schema': 'artifact-promotion-ledger-v1',
        'taskArtifactId': stableId,
        'promotionId': 'promotion-$stableId',
        ...conversion.payload,
      },
    'capture' => <String, dynamic>{
        'schema': 'capture-intake-state-v1',
        'captureId': stableId,
        ...conversion.payload,
      },
    'import_candidate' => <String, dynamic>{
        'schema': 'import-candidate-state-v1',
        'importCandidateId': stableId,
        ...conversion.payload,
      },
    'link_inbox_item' => <String, dynamic>{
        'schema': 'link-inbox-state-v1',
        'linkInboxItemId': stableId,
        ...conversion.payload,
      },
    'domain_operation_receipt_change' => <String, dynamic>{
        'schema': 'cross-medium-commit-journal-v1',
        'operationId': stableId,
        'intentDigest': fingerprint,
        ...conversion.payload,
      },
    'backup_manifest' => <String, dynamic>{
        'schema': 'formal-migration-catalog-v1',
        ...conversion.payload,
      },
    _ => fail(
        FailureClass.unsupported,
        'no domain target builder for ${definition.objectType}',
      ),
  };
  return _DerivedMigrationTarget(
    conversion.classification,
    conversion.outcome,
    formal.targetRole,
    formal.migrationAction,
    null,
    acceptedTarget,
    preservation,
  );
}

class _RawConversion {
  const _RawConversion(
    this.classification,
    this.outcome,
    this.payload, {
    this.blockedReason,
  });

  final String classification;
  final String outcome;
  final Map<String, dynamic> payload;
  final String? blockedReason;
}

_RawConversion _blockedRaw(String reason) =>
    _RawConversion('blocked', reason, const {}, blockedReason: reason);

void _requireRawKind(Map<String, dynamic> details, String expected) {
  if (details['rawKind'] != expected) {
    fail(
      FailureClass.inputRejected,
      'raw converter expected $expected, got ${details['rawKind']}',
    );
  }
}

_RawConversion _convertCardRaw(
  String objectType,
  Map<String, dynamic> details,
) {
  _requireRawKind(details, 'card');
  final conflicts = <String, bool>{
    'id': details['legacyId'] != details['targetId'],
    'title': details['legacyTitle'] != details['targetTitle'],
    'body': details['legacyBody'] != details['targetBody'],
  };
  final conflictingFields = conflicts.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toList(growable: false);
  if (conflictingFields.isNotEmpty) {
    return _blockedRaw('${conflictingFields.join('_')}_conflict');
  }
  final authorized = details['truthAuthorization'] == true;
  final provenance = details['provenance'] as String;
  if (objectType == 'user_truth') {
    if (!authorized || provenance == 'none' || provenance.isEmpty) {
      return _blockedRaw('truth_authorization_or_provenance_missing');
    }
    return _RawConversion(
      'deterministic',
      'explicit_truth_preserved_with_provenance',
      {
        'cardRef': 'card-ref-${details['legacyId']}',
        'provenance': provenance,
        'authorization': 'explicit',
      },
    );
  }
  return _RawConversion(
    'deterministic',
    details['roundtripRequested'] == true
        ? 'roundtrip_converged'
        : 'no_truth_promotion',
    {
      'cardId': details['legacyId'],
      'markdown': '# ${details['legacyTitle']}\n\n${details['legacyBody']}',
    },
  );
}

_RawConversion _convertRichTextRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'richtext');
  if (details['rawSchemaVersion'] != 1) {
    return _blockedRaw('unsupported_richtext_schema');
  }
  final text = details['text'] as String;
  if (details['imeCommitted'] != true) {
    return _blockedRaw('save_deferred_ime_composition');
  }
  if (details['sourceEncoding'] != 'utf16' ||
      details['utf16Fingerprint'] != _canonicalSha256(text.codeUnits)) {
    return _blockedRaw('utf16_fingerprint_mismatch');
  }
  final marks = (details['marks'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  const knownMarks = {
    'bold',
    'italic',
    'underline',
    'code',
    'strike',
    'link',
  };
  for (final mark in marks) {
    final type = mark['type'];
    final start = mark['start'];
    final end = mark['end'];
    if (!knownMarks.contains(type)) return _blockedRaw('unknown_mark');
    if (type == 'link') {
      final href = mark['href'];
      if (href is! String || !_isSafeRichTextHref(href)) {
        return _blockedRaw('unsafe_or_missing_link_href');
      }
    }
    final allowedKeys = type == 'link'
        ? const {'type', 'start', 'end', 'href'}
        : const {'type', 'start', 'end'};
    if (!_setEquals(mark.keys.toSet(), allowedKeys)) {
      return _blockedRaw('unsupported_mark_attribute');
    }
    if (start is! int ||
        end is! int ||
        start < 0 ||
        end <= start ||
        end > text.codeUnits.length) {
      return _blockedRaw('invalid_utf16_mark_range');
    }
  }
  final assets = (details['assets'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  for (final asset in assets) {
    final kind = asset['kind'];
    if (!const {'image', 'video', 'attachment'}.contains(kind)) {
      return _blockedRaw('unknown_asset_kind');
    }
    if (asset['stableRef'] is! String ||
        (asset['stableRef'] as String).isEmpty) {
      return _blockedRaw('asset_missing_stable_ref');
    }
    if (asset['expectedHash'] != asset['actualHash']) {
      return _blockedRaw('asset_hash_mismatch');
    }
    if (asset['storage'] != 'content_addressed') {
      return _blockedRaw('asset_storage_not_durable');
    }
    final mime = asset['mime'];
    if (mime is! String || mime.isEmpty) {
      return _blockedRaw('asset_mime_missing');
    }
    if (asset['embeddedBytesLength'] is! int ||
        (asset['embeddedBytesLength'] as int) != 0) {
      return _blockedRaw('embedded_asset_bytes_forbidden');
    }
  }
  var crossing = false;
  for (var left = 0; left < marks.length; left++) {
    for (var right = left + 1; right < marks.length; right++) {
      final a = marks[left];
      final b = marks[right];
      final aStart = a['start'] as int;
      final aEnd = a['end'] as int;
      final bStart = b['start'] as int;
      final bEnd = b['end'] as int;
      crossing = crossing ||
          (aStart < bStart && bStart < aEnd && aEnd < bEnd) ||
          (bStart < aStart && aStart < bEnd && bEnd < aEnd);
    }
  }
  final blocks = (details['blocks'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  final fragments = <String>[];
  final preservationCapsules = <Map<String, dynamic>>[];
  var controlled = crossing || marks.any((mark) => mark['type'] == 'underline');
  var degraded = (details['history'] as Map)['cacheOnly'] == true;
  for (final block in blocks) {
    if (!_setEquals(block.keys.toSet(), const {
      'blockId',
      'kind',
      'level',
      'depth',
      'text',
      'children',
      'listStyle',
      'language',
      'legacyFence',
      'referenceKind',
      'referenceId',
    })) {
      return _blockedRaw('unsupported_block_attribute');
    }
    final kind = block['kind'];
    final blockId = block['blockId'] as String;
    final blockText = block['text'] as String;
    final level = block['level'] as int;
    final depth = block['depth'] as int;
    if (blockId.isEmpty || depth < 0 || depth > 8) {
      return _blockedRaw('invalid_list_depth_or_block_id');
    }
    final children = (block['children'] as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
    switch (kind) {
      case 'paragraph':
        fragments.add(blockText);
      case 'heading':
        if (level < 1 || level > 6) return _blockedRaw('invalid_heading_level');
        fragments.add('${List.filled(level, '#').join()} $blockText');
      case 'list_item':
        final style = block['listStyle'];
        if (!const {'unordered', 'ordered'}.contains(style)) {
          return _blockedRaw('unknown_list_attribute');
        }
        final marker = style == 'ordered' ? '1.' : '-';
        fragments.add(
          '${List.filled(depth, '  ').join()}$marker $blockText',
        );
      case 'quote':
        fragments.add('${List.filled(depth + 1, '> ').join()}$blockText');
      case 'code':
        final language = block['language'] as String;
        final legacyFence = block['legacyFence'] as String;
        if (!RegExp(r'^[A-Za-z0-9_+.-]*$').hasMatch(language) ||
            !RegExp(r'^`{3,}$').hasMatch(legacyFence)) {
          return _blockedRaw('invalid_code_metadata');
        }
        final fence = _markdownFenceFor(blockText);
        fragments.add('$fence$language\n$blockText\n$fence');
      case 'empty':
        controlled = true;
        final emptyKind = block['referenceKind'];
        if (!const {'paragraph', 'list', 'quote'}.contains(emptyKind)) {
          return _blockedRaw('invalid_empty_block_kind');
        }
        fragments.add(
          '<!-- hereiam:empty-block block_id=$blockId kind=$emptyKind -->',
        );
      case 'footnote':
        degraded = true;
        fragments.add('[^legacy]: $blockText');
      case 'gfm_table':
        degraded = true;
        fragments.add(blockText);
      case 'raw':
        degraded = true;
        final rawPayload = details['rawPayload'];
        if (rawPayload is! Map<String, dynamic> ||
            !_setEquals(rawPayload.keys.toSet(), const {
              'encoding',
              'rawBytesBase64',
              'byteLength',
              'rawSha256',
            }) ||
            rawPayload['encoding'] != 'base64' ||
            rawPayload['rawBytesBase64'] is! String ||
            rawPayload['byteLength'] is! int ||
            rawPayload['rawSha256'] is! String) {
          return _blockedRaw('raw_bytes_envelope_invalid');
        }
        late List<int> rawBytes;
        try {
          rawBytes = base64Decode(rawPayload['rawBytesBase64'] as String);
        } on FormatException {
          return _blockedRaw('raw_bytes_base64_invalid');
        }
        if (rawBytes.length != rawPayload['byteLength']) {
          return _blockedRaw('raw_bytes_length_mismatch');
        }
        final rawSha = sha256.convert(rawBytes).toString();
        if (rawSha != rawPayload['rawSha256']) {
          return _blockedRaw('raw_bytes_hash_mismatch');
        }
        final encoded = base64Encode(rawBytes);
        final restored = base64Decode(encoded);
        final bytewiseEqual = restored.length == rawBytes.length &&
            List.generate(restored.length, (index) => index)
                .every((index) => restored[index] == rawBytes[index]);
        if (!bytewiseEqual) return _blockedRaw('raw_bytes_restore_mismatch');
        preservationCapsules.add({
          'blockId': blockId,
          'kind': 'raw_html',
          'encoding': 'base64',
          'rawBytesBase64': encoded,
          'byteLength': rawBytes.length,
          'rawSha256': rawSha,
          'restoredBytewiseEqual': bytewiseEqual,
        });
        fragments.add(
          '<legacy-raw block_id="$blockId" '
          'digest="$rawSha" />',
        );
      case 'reference':
        final referenceKind = block['referenceKind'];
        final referenceId = block['referenceId'] as String;
        if (referenceId.isEmpty ||
            !const {'card', 'source', 'anchor', 'evidence'}
                .contains(referenceKind)) {
          return _blockedRaw('invalid_reference_block');
        }
        if (referenceKind == 'card') {
          fragments.add('[$blockText](hereiam-card:$referenceId)');
        } else {
          controlled = true;
          fragments.add(
            '[$blockText](hereiam-$referenceKind:$referenceId) '
            '<typed-ref kind="$referenceKind" id="$referenceId" />',
          );
        }
      default:
        return _blockedRaw('unknown_block_kind');
    }
    for (final child in children) {
      final childKind = child['kind'];
      final childDepth = child['depth'];
      if (childDepth is! int ||
          childDepth < 1 ||
          childDepth > 8 ||
          !const {'paragraph', 'list_item', 'quote'}.contains(childKind)) {
        return _blockedRaw('invalid_nested_block');
      }
      if (childKind == 'quote') {
        fragments.add(
          '${List.filled(childDepth + 1, '> ').join()}${child['text']}',
        );
      } else if (childKind == 'list_item') {
        final marker = child['listStyle'] == 'ordered' ? '1.' : '-';
        fragments.add(
          '${List.filled(childDepth, '  ').join()}$marker ${child['text']}',
        );
      } else {
        fragments
            .add('${List.filled(childDepth, '  ').join()}${child['text']}');
      }
    }
  }
  final classification = degraded
      ? 'degraded_preserved'
      : controlled
          ? 'controlled_extension'
          : 'deterministic';
  final representation = degraded
      ? 'preservation_capsule'
      : controlled
          ? 'controlled_extension'
          : 'markdown';
  for (final asset in assets) {
    final kind = asset['kind'];
    final ref = asset['stableRef'];
    fragments
        .add(kind == 'image' ? '![$kind]($ref)' : '<$kind-ref src="$ref" />');
  }
  var markdownFragment = fragments.join('\n');
  if (crossing) {
    markdownFragment = '$markdownFragment\n'
        '<mark-extension digest="${_canonicalSha256(marks)}" />';
  } else if (marks.isNotEmpty) {
    if (blocks.length != 1 || blocks.single['kind'] != 'paragraph') {
      return _blockedRaw('marks_require_single_text_block');
    }
    markdownFragment = _renderExactUtf16Marks(text, marks);
  }
  return _RawConversion(
    classification,
    (details['history'] as Map)['cacheOnly'] == true
        ? 'cache_preserved_without_revision'
        : crossing
            ? 'crossing_marks_extension'
            : 'richtext_converted',
    {
      'representation': representation,
      'markdownFragment': markdownFragment,
      'normalizedMarks': marks,
      'assetRefs': assets.map((asset) => asset['stableRef']).toList(),
      'preservationCapsules': preservationCapsules,
      'utf16Fingerprint': details['utf16Fingerprint'],
      'parentRevision': (details['history'] as Map)['parentRevision'],
    },
  );
}

bool _isSafeRichTextHref(String href) {
  if (href.isEmpty || href.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    return false;
  }
  final uri = Uri.tryParse(href);
  if (uri == null || !const {'https', 'hereiam-card'}.contains(uri.scheme)) {
    return false;
  }
  if (uri.scheme == 'https') return uri.host.isNotEmpty;
  return uri.path.isNotEmpty;
}

String _markdownFenceFor(String content) {
  var longest = 0;
  for (final match in RegExp(r'`+').allMatches(content)) {
    if (match.group(0)!.length > longest) longest = match.group(0)!.length;
  }
  return List.filled(longest < 3 ? 3 : longest + 1, '`').join();
}

String _renderExactUtf16Marks(
  String text,
  List<Map<String, dynamic>> marks,
) {
  final boundaries = <int>{0, text.codeUnits.length};
  for (final mark in marks) {
    boundaries.add(mark['start'] as int);
    boundaries.add(mark['end'] as int);
  }
  final ordered = boundaries.toList()..sort();
  final buffer = StringBuffer();
  for (var index = 0; index < ordered.length - 1; index++) {
    final position = ordered[index];
    final ending = marks.where((mark) => mark['end'] == position).toList()
      ..sort((left, right) =>
          (right['start'] as int).compareTo(left['start'] as int));
    for (final mark in ending) {
      buffer.write(_markCloseToken(mark, text));
    }
    final starting = marks.where((mark) => mark['start'] == position).toList()
      ..sort(
          (left, right) => (right['end'] as int).compareTo(left['end'] as int));
    for (final mark in starting) {
      buffer.write(_markOpenToken(mark, text));
    }
    buffer.write(text.substring(position, ordered[index + 1]));
  }
  final finalPosition = ordered.last;
  final ending = marks.where((mark) => mark['end'] == finalPosition).toList()
    ..sort((left, right) =>
        (right['start'] as int).compareTo(left['start'] as int));
  for (final mark in ending) {
    buffer.write(_markCloseToken(mark, text));
  }
  return buffer.toString();
}

String _markOpenToken(Map<String, dynamic> mark, String text) =>
    switch (mark['type']) {
      'bold' => '**',
      'italic' => '_',
      'strike' => '~~',
      'underline' => '<u>',
      'link' => '[',
      'code' => _inlineDelimiterForRange(mark, text),
      _ => '',
    };

String _markCloseToken(Map<String, dynamic> mark, String text) =>
    switch (mark['type']) {
      'bold' => '**',
      'italic' => '_',
      'strike' => '~~',
      'underline' => '</u>',
      'link' => '](${mark['href']})',
      'code' => _inlineDelimiterForRange(mark, text),
      _ => '',
    };

String _inlineDelimiterForRange(Map<String, dynamic> mark, String text) {
  final content = text.substring(mark['start'] as int, mark['end'] as int);
  var longest = 0;
  for (final match in RegExp(r'`+').allMatches(content)) {
    if (match.group(0)!.length > longest) longest = match.group(0)!.length;
  }
  return List.filled(longest + 1, '`').join();
}

_RawConversion _convertAssetRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'asset_relation');
  final asset = Map<String, dynamic>.from(details['asset'] as Map);
  final stableRef = asset['stableRef'] as String;
  if (stableRef.isEmpty) return _blockedRaw('asset_missing_stable_ref');
  if (asset['expectedHash'] != asset['actualHash']) {
    return _blockedRaw('asset_hash_mismatch');
  }
  if (asset['storage'] != 'content_addressed') {
    return _blockedRaw('asset_storage_not_durable');
  }
  if (asset['mime'] is! String || (asset['mime'] as String).isEmpty) {
    return _blockedRaw('asset_mime_missing');
  }
  if (asset['embeddedBytesLength'] is! int ||
      (asset['embeddedBytesLength'] as int) != 0) {
    return _blockedRaw('embedded_asset_bytes_forbidden');
  }
  final kind = asset['kind'] as String;
  if (!const {'image', 'video', 'attachment'}.contains(kind)) {
    return _blockedRaw('unknown_asset_kind');
  }
  return _RawConversion(
    kind == 'image' ? 'deterministic' : 'controlled_extension',
    'asset_relation_converted',
    {
      'assetKind': kind,
      'stableRef': stableRef,
      'assetDigest': asset['actualHash'],
      'mime': asset['mime'],
      'markdownFragment': kind == 'image'
          ? '![$kind]($stableRef)'
          : '<$kind-ref src="$stableRef" />',
    },
  );
}

_RawConversion _convertHistoryRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'history');
  if (details['cacheOnly'] == true) {
    return _RawConversion(
      'degraded_preserved',
      'cache_preserved_without_revision',
      {'cacheCapsule': _canonicalSha256(details)},
    );
  }
  final parent = details['parentRevision'] as String;
  final child = details['childRevision'] as String;
  if (parent.isEmpty || child.isEmpty || parent == child) {
    return _blockedRaw('invalid_revision_lineage');
  }
  return _RawConversion(
    'deterministic',
    'history_parent_preserved',
    {'parentRevision': parent, 'childRevision': child},
  );
}

_RawConversion _convertAnchorRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'anchor');
  final selector = Map<String, dynamic>.from(details['selector'] as Map);
  if (details['sourceId'] == '' ||
      details['sourceVersionId'] == '' ||
      selector['type'] != 'text_quote' ||
      selector['exact'] is! String ||
      details['expectedFingerprint'] != details['actualFingerprint'] ||
      details['actualFingerprint'] != _canonicalSha256(selector)) {
    return _blockedRaw('anchor_selector_or_fingerprint_invalid');
  }
  final matchCount = details['matchCount'] as int;
  if (matchCount == 0) return _blockedRaw('anchor_orphan');
  if (matchCount != 1) return _blockedRaw('anchor_ambiguous');
  return _RawConversion('deterministic', 'anchor_exact_rebound', {
    'sourceId': details['sourceId'],
    'sourceVersionId': details['sourceVersionId'],
    'selector': selector,
    'fingerprint': details['actualFingerprint'],
  });
}

_RawConversion _convertEvidenceRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'evidence');
  if (details['attachmentPresent'] != true || details['attachmentHash'] == '') {
    return _blockedRaw('evidence_attachment_missing');
  }
  final claimAuthorized = details['claimAuthorization'] == true;
  return _RawConversion(
    claimAuthorized ? 'deterministic' : 'degraded_preserved',
    claimAuthorized ? 'authorized_claim_recorded' : 'proposal_without_claim',
    {
      'attachmentDigest': details['attachmentHash'],
      'claimCreated': claimAuthorized,
      'proposalCreated': details['proposalRequested'] == true,
    },
  );
}

_RawConversion _convertTaskRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'task_promotion');
  final authorized = details['promotionAuthorization'] == true;
  final artifactSucceeded = details['artifactStepSucceeded'] == true;
  final cardSucceeded = details['cardStepSucceeded'] == true;
  if (!authorized || !artifactSucceeded || !cardSucceeded) {
    return _blockedRaw('partial_promotion_zero_downstream');
  }
  return _RawConversion('deterministic', 'promotion_atomic', {
    'authorized': true,
    'artifactRecorded': true,
    'cardRevisionCreated': true,
    'truthCreated': details['truthAuthorization'] == true,
  });
}

_RawConversion _convertIntakeRaw(
  String objectType,
  Map<String, dynamic> details,
) {
  _requireRawKind(details, 'intake');
  final stableIdentity = details['stableIdentity'];
  final dedupeKey = details['dedupeKey'];
  if (stableIdentity is! String || stableIdentity.isEmpty) {
    return _blockedRaw('intake_stable_identity_missing');
  }
  if (dedupeKey is! String || dedupeKey.isEmpty) {
    return _blockedRaw('intake_dedupe_key_missing');
  }
  final trace = <String>['received', 'identity_checked'];
  String classification;
  String outcome;
  if (details['existingDigest'] != details['incomingDigest']) {
    return _blockedRaw('idempotency_conflict');
  } else if (details['cancelled'] == true &&
      details['parserCompleted'] == true) {
    classification = 'controlled_extension';
    outcome = 'late_parser_rejected';
    trace.addAll(['cancel_barrier_seen', 'late_parser_rejected']);
  } else if (details['cancelled'] == true) {
    classification = 'deterministic';
    outcome = 'cancel_barrier_applied';
    trace.add('cancelled');
  } else if (details['restartPhase'] != 'none') {
    classification = 'deterministic';
    outcome = 'restart_zero_downstream';
    trace.addAll(['serialized', 'restarted', 'intake_recovered']);
  } else {
    classification = 'deterministic';
    outcome = 'duplicate_identity_reused';
    trace.add('dedupe_reused');
  }
  final downstream = <String>[];
  return _RawConversion(classification, outcome, {
    'intakeKind': objectType,
    'stableIdentity': stableIdentity,
    'dedupeKey': dedupeKey,
    'status': outcome,
    'parserCompleted': details['parserCompleted'],
    'failurePhase': details['failurePhase'],
    'restartPhase': details['restartPhase'],
    'trace': trace,
    'downstream': downstream,
  });
}

_RawConversion _convertCommitRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'commit');
  final failurePoint = _deriveMigrationFailurePoint(details);
  final facts = details['failureFacts'] as Map<String, dynamic>;
  final oldHash = facts['oldHash'] as String;
  final newHash = facts['newHash'] as String;
  final observedHash = facts['observedHash'] as String;
  final conflict = observedHash != oldHash && observedHash != newHash;
  return _RawConversion(
    failurePoint == 'none' ? 'deterministic' : 'controlled_extension',
    failurePoint == 'none'
        ? 'journal_prepared'
        : 'failure_detected_$failurePoint',
    {
      'hashConflict': conflict,
      'derivedFailurePoint': failurePoint,
      'oldHash': oldHash,
      'newHash': newHash,
      'observedHash': observedHash,
    },
  );
}

String _deriveMigrationFailurePoint(Map<String, dynamic> details) {
  final factsValue = details['failureFacts'];
  if (factsValue is! Map<String, dynamic>) {
    fail(FailureClass.inputRejected, 'commit failureFacts are required');
  }
  final facts = factsValue;
  _expectExactKeys(
      facts,
      const {
        'credential',
        'binding',
        'scope',
        'core',
        'epoch',
        'fence',
        'lineage',
        'existingDigest',
        'incomingDigest',
        'parentState',
        'refsClosed',
        'diskCapacity',
        'stageBytes',
        'publishBytes',
        'stagePermission',
        'publishPermission',
        'yamlValid',
        'sourceExpectedHash',
        'sourceActualHash',
        'externalState',
        'oldHash',
        'newHash',
        'observedHash',
        'activationConstraintValid',
        'projectionOutcome',
        'notificationOutcome',
        'rollbackManifestValid',
        'stagingManifestValid',
      },
      'commit.failureFacts');
  for (final key in const {
    'credential',
    'binding',
    'scope',
    'core',
    'epoch',
    'fence',
    'lineage',
    'existingDigest',
    'incomingDigest',
    'parentState',
    'stagePermission',
    'publishPermission',
    'sourceExpectedHash',
    'sourceActualHash',
    'externalState',
    'oldHash',
    'newHash',
    'observedHash',
    'projectionOutcome',
    'notificationOutcome',
  }) {
    if (facts[key] is! String) {
      fail(FailureClass.inputRejected, 'commit.failureFacts.$key is invalid');
    }
  }
  for (final key in const {
    'refsClosed',
    'yamlValid',
    'activationConstraintValid',
    'rollbackManifestValid',
    'stagingManifestValid',
  }) {
    if (facts[key] is! bool) {
      fail(FailureClass.inputRejected, 'commit.failureFacts.$key is invalid');
    }
  }
  for (final key in const {'diskCapacity', 'stageBytes', 'publishBytes'}) {
    if (facts[key] is! int || (facts[key] as int) < 0) {
      fail(FailureClass.inputRejected, 'commit.failureFacts.$key is invalid');
    }
  }
  final enums = <String, Set<String>>{
    'credential': const {'current', 'stale'},
    'binding': const {'matched', 'mismatch'},
    'scope': const {'allowed', 'denied'},
    'core': const {'active', 'stale'},
    'epoch': const {'current', 'stale'},
    'fence': const {'current', 'stale'},
    'lineage': const {'valid', 'rejected'},
    'parentState': const {'current', 'stale'},
    'stagePermission': const {'allowed', 'denied'},
    'publishPermission': const {'allowed', 'denied'},
    'externalState': const {'present', 'moved', 'deleted'},
    'projectionOutcome': const {'success', 'failed'},
    'notificationOutcome': const {'success', 'failed'},
  };
  for (final entry in enums.entries) {
    if (!entry.value.contains(facts[entry.key])) {
      fail(
        FailureClass.inputRejected,
        'commit.failureFacts.${entry.key} has an unknown enum',
      );
    }
  }
  if (facts['credential'] != 'current') return 'stale_credential_generation';
  if (facts['binding'] != 'matched') return 'identity_binding_mismatch';
  if (facts['scope'] != 'allowed') return 'scope_denied';
  if (facts['core'] != 'active') return 'stale_core_instance';
  if (facts['epoch'] != 'current') return 'stale_authority_epoch';
  if (facts['fence'] != 'current') return 'stale_worker_fence';
  if (facts['lineage'] != 'valid') return 'lineage_state_rejected';
  final existingDigest = facts['existingDigest'] as String;
  final incomingDigest = facts['incomingDigest'] as String;
  if (existingDigest != 'none') {
    return existingDigest == incomingDigest
        ? 'duplicate_key_same_digest'
        : 'duplicate_key_different_digest';
  }
  if (facts['parentState'] != 'current') return 'stale_parent_revision';
  if (facts['refsClosed'] != true) return 'dangling_stable_ref';
  final capacity = facts['diskCapacity'] as int;
  if (capacity < (facts['stageBytes'] as int)) {
    return 'disk_full_during_stage';
  }
  if (capacity < (facts['publishBytes'] as int)) {
    return 'disk_full_during_publish';
  }
  if (facts['stagePermission'] != 'allowed') {
    return 'permission_denied_during_stage';
  }
  if (facts['publishPermission'] != 'allowed') {
    return 'permission_denied_during_publish';
  }
  if (facts['yamlValid'] != true) return 'invalid_yaml';
  if (facts['sourceExpectedHash'] != facts['sourceActualHash']) {
    return 'source_object_hash_mismatch';
  }
  if (facts['externalState'] == 'moved') return 'external_move';
  if (facts['externalState'] == 'deleted') return 'external_delete';
  final observed = facts['observedHash'];
  if (observed != facts['oldHash'] && observed != facts['newHash']) {
    return 'external_third_hash_conflict';
  }
  if (facts['activationConstraintValid'] != true) {
    return 'activation_constraint_failure';
  }
  if (facts['projectionOutcome'] != 'success') {
    return 'projection_rebuild_failure';
  }
  if (facts['notificationOutcome'] != 'success') {
    return 'notification_failure';
  }
  if (facts['rollbackManifestValid'] != true) {
    return 'rollback_manifest_corrupt';
  }
  if (facts['stagingManifestValid'] != true) {
    return 'staging_manifest_corrupt';
  }
  return 'none';
}

_RawConversion _convertFormalCatalogRaw(Map<String, dynamic> details) {
  _requireRawKind(details, 'formal_catalog');
  final catalog = formalMigrationObjectLiteral
      .map((entry) => _roundTrip(entry))
      .toList(growable: false);
  if (!_validateFrozenFormalCatalog(catalog)) {
    return _blockedRaw('formal_catalog_not_exact');
  }
  return _RawConversion(
    'deterministic',
    'all_32_objects_classified',
    {'catalog': catalog},
  );
}

class _RoundTripResult {
  const _RoundTripResult(
    this.rollbackDigest,
    this.remigrateDigest,
    this.newWriteMarkdown,
    this.rollback,
    this.remigrated,
    this.fullRoundTripDomains,
    this.allSixRoundTripDomainsHeld,
    this.derivedIndexRebuiltFromAcceptedState,
    this.transitionTrace,
    this.physicalDigests,
    this.derivedIndexOperationIdsByStage,
  );

  final String rollbackDigest;
  final String? remigrateDigest;
  final String? newWriteMarkdown;
  final Map<String, dynamic> rollback;
  final Map<String, dynamic> remigrated;
  final Map<String, Map<String, Object?>> fullRoundTripDomains;
  final bool allSixRoundTripDomainsHeld;
  final bool derivedIndexRebuiltFromAcceptedState;
  final List<String> transitionTrace;
  final Map<String, Map<String, String>> physicalDigests;
  final Map<String, List<String>> derivedIndexOperationIdsByStage;

  int get revisionCount => (remigrated['revisionLedger'] as List).length;
  int get operationCount => (remigrated['operationLedger'] as List).length;
  int get eventCount => (remigrated['eventLedger'] as List).length;
  int get truthCount => (remigrated['truthLedger'] as List).length;

  bool get ledgersUnique => const [
        'revisionLedger',
        'operationLedger',
        'eventLedger',
        'truthLedger',
      ].every((name) {
        final values = remigrated[name] as List;
        return values.map(_canonicalSha256).toSet().length == values.length;
      });
}

const _fullRoundTripDomainKeys = <String>{
  'cardContent',
  'userTruthSet',
  'sourceAnchor',
  'operationLog',
  'revisionHistory',
  'derivedIndex',
};

const _fullRoundTripDomainFieldKeys = <String>{
  'oldBaselineSemanticDigest',
  'newAfterFirstMigrationSemanticDigest',
  'postCutoverNewWriteSetDigest',
  'oldAfterRollbackSemanticDigest',
  'newAfterRemigrationSemanticDigest',
  'stableIdSetDigest',
  'operationIdSetDigest',
  'newWritesPreserved',
  'duplicateAcceptedCount',
  'domainInvariantHeld',
};

Map<String, dynamic> _roundTripDomainState(
  Object? value,
  String path,
) {
  if (value is! Map<String, dynamic>) {
    fail(FailureClass.inputRejected, '$path must be an object');
  }
  _expectExactKeys(value, {'stableIds', 'operationIds', 'records'}, path);
  if (value['stableIds'] is! List ||
      (value['stableIds'] as List).any((entry) => entry is! String) ||
      value['operationIds'] is! List ||
      (value['operationIds'] as List).any((entry) => entry is! String) ||
      value['records'] is! List ||
      (value['records'] as List).any((entry) => entry is! Map)) {
    fail(FailureClass.inputRejected, '$path has invalid domain state');
  }
  return _roundTrip(value);
}

String _domainRowKey(String name) => switch (name) {
      'cardContent' => 'cardRevisionRows',
      'userTruthSet' => 'truthRelationRows',
      'sourceAnchor' => 'sourceAnchorRows',
      'operationLog' => 'operationLedgerRows',
      'revisionHistory' => 'revisionHistoryRows',
      'derivedIndex' => 'rebuiltIndexRows',
      _ => fail(FailureClass.unsupported, 'unknown roundtrip domain: $name'),
    };

Map<String, dynamic> _encodeNewDomain(
  String name,
  Map<String, dynamic> semantic,
) =>
    {
      'schema': 'hereiam-$name-new-v1',
      '${name}StableIdRows': _roundTripList(semantic['stableIds'] as List),
      '${name}OperationIdRows':
          _roundTripList(semantic['operationIds'] as List),
      _domainRowKey(name): _roundTripList(semantic['records'] as List),
    };

Map<String, dynamic> _encodeRollbackDomain(
  String name,
  Map<String, dynamic> semantic,
) =>
    {
      'legacyReadableEnvelope': {
        'domain': name,
        'stableIdCells': _roundTripList(semantic['stableIds'] as List),
        'operationIdCells': _roundTripList(semantic['operationIds'] as List),
        'payloadCells': _roundTripList(semantic['records'] as List),
      },
    };

Map<String, dynamic> _decodeRoundTripDomain(
  String name,
  Map<String, dynamic> physical,
) {
  if (physical.containsKey('stableIds')) return _domainSemanticState(physical);
  if (physical.containsKey('legacyReadableEnvelope')) {
    final envelope = physical['legacyReadableEnvelope'] as Map<String, dynamic>;
    if (envelope['domain'] != name) {
      fail(FailureClass.inputRejected, 'rollback domain envelope mismatch');
    }
    return {
      'stableIds': _roundTripList(envelope['stableIdCells'] as List),
      'operationIds': _roundTripList(envelope['operationIdCells'] as List),
      'records': _roundTripList(envelope['payloadCells'] as List),
    };
  }
  return {
    'stableIds': _roundTripList(physical['${name}StableIdRows'] as List),
    'operationIds': _roundTripList(physical['${name}OperationIdRows'] as List),
    'records': _roundTripList(physical[_domainRowKey(name)] as List),
  };
}

Map<String, dynamic> _rebuiltIndexState(
  Map<String, Map<String, dynamic>> acceptedDomains,
) {
  final accepted = <String, dynamic>{
    for (final name in _fullRoundTripDomainKeys.where(
      (name) => name != 'derivedIndex',
    ))
      name: acceptedDomains[name],
  };
  final operationIds = acceptedDomains.entries
      .where((entry) => entry.key != 'derivedIndex')
      .expand((entry) => entry.value['operationIds'] as List)
      .cast<String>()
      .toSet()
      .toList()
    ..sort();
  return {
    'stableIds': const ['index:accepted-domains'],
    'operationIds': operationIds,
    'records': <dynamic>[
      {
        'kind': 'rebuilt-derived-index',
        'acceptedStateDigest': _canonicalSha256(accepted),
        'refs': acceptedDomains.entries
            .where((entry) => entry.key != 'derivedIndex')
            .expand((entry) => entry.value['stableIds'] as List)
            .cast<String>()
            .toSet()
            .toList()
          ..sort(),
      },
    ],
  };
}

Map<String, dynamic> _domainSemanticState(Map<String, dynamic> state) => {
      'stableIds': List<String>.from(state['stableIds'] as List)..sort(),
      'operationIds': List<String>.from(state['operationIds'] as List)..sort(),
      'records': _roundTripList(state['records'] as List),
    };

List<dynamic> _roundTripList(List values) =>
    jsonDecode(jsonEncode(values)) as List<dynamic>;

int _duplicateRecordCount(Map<String, dynamic> state) {
  final records = state['records'] as List;
  final seen = <String>{};
  var duplicates = 0;
  for (final record in records) {
    if (!seen.add(_canonicalSha256(record))) duplicates++;
  }
  return duplicates;
}

Set<String> _roundTripRecordReferences(
  String domain,
  Map<dynamic, dynamic> record,
) {
  final references = <String>{};
  void addField(String field) {
    final value = record[field];
    if (value is String && value.isNotEmpty) references.add(value);
  }

  final generic = record['refs'];
  if (generic is List) {
    references
        .addAll(generic.whereType<String>().where((value) => value.isNotEmpty));
  }
  switch (domain) {
    case 'userTruthSet':
      addField('cardId');
    case 'sourceAnchor':
      addField('sourceVersionId');
    case 'operationLog':
      addField('targetId');
    case 'revisionHistory':
      addField('cardId');
      addField('parentRevisionId');
    case 'cardContent' || 'derivedIndex':
      break;
    default:
      fail(FailureClass.unsupported, 'unknown roundtrip reference domain');
  }
  return references;
}

_RoundTripResult _executeRoundTrip(
  MigrationCaseDefinition definition,
  Map<String, dynamic> legacy,
  Map<String, dynamic>? acceptedTarget,
) {
  final stableId = legacy['stableId'] as String;
  final targetHead =
      acceptedTarget == null ? null : _canonicalSha256(acceptedTarget);
  final isFullRoundTrip =
      (legacy['details'] as Map<String, dynamic>)['roundtripRequested'] == true;
  final newWriteMarkdown = isFullRoundTrip
      ? '# post-cutover $stableId\n\nkept across rollback'
      : null;
  final newWriteHash =
      newWriteMarkdown == null ? null : _canonicalSha256(newWriteMarkdown);
  final rawDomains = isFullRoundTrip
      ? Map<String, dynamic>.from(
          (legacy['details'] as Map<String, dynamic>)['roundtripDomains']
              as Map,
        )
      : <String, dynamic>{};
  if (isFullRoundTrip &&
      !_setEquals(rawDomains.keys.toSet(), _fullRoundTripDomainKeys)) {
    fail(
      FailureClass.inputRejected,
      'roundtripDomains must contain the exact six P5 domains',
    );
  }
  final oldDomains = <String, Map<String, dynamic>>{
    if (isFullRoundTrip)
      for (final name in _fullRoundTripDomainKeys)
        name: _roundTripDomainState(
          rawDomains[name],
          'legacy.details.roundtripDomains.$name',
        ),
  };
  final firstMigrationSemantic = <String, Map<String, dynamic>>{
    if (isFullRoundTrip)
      for (final entry in oldDomains.entries)
        if (entry.key != 'derivedIndex') entry.key: _roundTrip(entry.value),
  };
  if (isFullRoundTrip) {
    firstMigrationSemantic['derivedIndex'] =
        _rebuiltIndexState(firstMigrationSemantic);
    final roundTripDetails = legacy['details'] as Map<String, dynamic>;
    if (roundTripDetails['injectFirstMigrationSemanticDrift'] == true) {
      final card = firstMigrationSemantic['cardContent']!;
      final records = List<dynamic>.from(card['records'] as List);
      final firstRecord = Map<String, dynamic>.from(records.first as Map);
      firstRecord['body'] = '${firstRecord['body']} [drifted during migration]';
      records[0] = firstRecord;
      card['records'] = records;
    }
    if (roundTripDetails['injectFirstMigrationDerivedIndexSemanticDrift'] ==
        true) {
      final index = firstMigrationSemantic['derivedIndex']!;
      final records = List<dynamic>.from(index['records'] as List);
      final firstRecord = Map<String, dynamic>.from(records.first as Map);
      firstRecord['acceptedStateDigest'] = 'drifted-derived-index-semantic';
      records[0] = firstRecord;
      index['records'] = records;
    }
    if (roundTripDetails['injectFirstMigrationDerivedIndexFutureOperation'] ==
        true) {
      final index = firstMigrationSemantic['derivedIndex']!;
      final operationIds = List<String>.from(index['operationIds'] as List)
        ..add('future-op');
      index['operationIds'] = operationIds;
    }
  }
  final firstMigrationDomains = <String, dynamic>{
    for (final entry in firstMigrationSemantic.entries)
      entry.key: _encodeNewDomain(entry.key, entry.value),
  };
  final postCutoverSemantic = <String, Map<String, dynamic>>{
    for (final entry in firstMigrationDomains.entries)
      entry.key: _decodeRoundTripDomain(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      ),
  };
  final newWriteSets = <String, List<Map<String, dynamic>>>{
    if (isFullRoundTrip) ...{
      'cardContent': [
        {
          'cardId': stableId,
          'operationId': 'operation-new-write-1',
          'markdown': newWriteMarkdown,
          'hash': newWriteHash,
          'refs': const <String>[],
        },
      ],
      'userTruthSet': [
        {
          'truthId': 'truth-post-cutover-1',
          'operationId': 'operation-new-write-1',
          'cardId': stableId,
          'provenance': 'explicit-post-cutover',
          'refs': [stableId],
        },
      ],
      'sourceAnchor': [
        {
          'anchorId': 'anchor-post-cutover-1',
          'operationId': 'operation-new-write-1',
          'sourceVersionId': 'source-version-1',
          'selector': 'kept-across-rollback',
          'refs': const ['source-version-1'],
        },
      ],
      'operationLog': [
        {
          'operationId': 'operation-new-write-1',
          'kind': 'post-cutover-write',
          'digest': newWriteHash,
          'refs': [stableId],
        },
      ],
      'revisionHistory': [
        {
          'revisionId': 'revision-new-write-1',
          'parentRevisionId': 'revision-legacy-1',
          'bodyHash': newWriteHash,
          'operationId': 'operation-new-write-1',
          'refs': [stableId, 'revision-legacy-1'],
        },
      ],
      'derivedIndex': const [],
    },
  };
  if (isFullRoundTrip) {
    for (final name in _fullRoundTripDomainKeys.where(
      (value) => value != 'derivedIndex',
    )) {
      final state = postCutoverSemantic[name]!;
      final writes = newWriteSets[name]!;
      (state['records'] as List).addAll(
        writes.map((write) => _roundTrip(write)),
      );
      for (final write in writes) {
        final stableIdValue = write['cardId'] ??
            write['truthId'] ??
            write['anchorId'] ??
            write['operationId'] ??
            write['revisionId'];
        if (stableIdValue is String) {
          (state['stableIds'] as List).add(stableIdValue);
        }
        final operationId = write['operationId'];
        if (operationId is String) {
          (state['operationIds'] as List).add(operationId);
        }
      }
    }
    postCutoverSemantic['derivedIndex'] =
        _rebuiltIndexState(postCutoverSemantic);
    newWriteSets['derivedIndex'] = List<Map<String, dynamic>>.from(
      postCutoverSemantic['derivedIndex']!['records'] as List,
    );
    final roundTripDetails = legacy['details'] as Map<String, dynamic>;
    if (roundTripDetails['injectRoundTripDuplicateRecord'] == true) {
      final state = postCutoverSemantic['operationLog']!;
      final records = state['records'] as List;
      records.add(_roundTrip(records.last));
    }
    if (roundTripDetails['injectRoundTripDuplicateStableId'] == true) {
      final state = postCutoverSemantic['cardContent']!;
      final ids = state['stableIds'] as List;
      ids.add(ids.last);
    }
    if (roundTripDetails['injectRoundTripDuplicateOperationId'] == true) {
      final state = postCutoverSemantic['sourceAnchor']!;
      final ids = state['operationIds'] as List;
      ids.add(ids.last);
    }
    if (roundTripDetails['injectRoundTripDanglingRef'] == true) {
      final state = postCutoverSemantic['userTruthSet']!;
      final record = (state['records'] as List).last as Map;
      (record['refs'] as List).add('missing-stable-id');
    }
    if (roundTripDetails['injectRoundTripDanglingUserTruthCardId'] == true) {
      final record =
          (postCutoverSemantic['userTruthSet']!['records'] as List).last as Map;
      record['cardId'] = 'missing-card-id';
    }
    if (roundTripDetails['injectRoundTripDanglingSourceVersionId'] == true) {
      final record =
          (postCutoverSemantic['sourceAnchor']!['records'] as List).last as Map;
      record['sourceVersionId'] = 'missing-source-version-id';
    }
    if (roundTripDetails['injectRoundTripDanglingRevisionParentId'] == true) {
      final record =
          (postCutoverSemantic['revisionHistory']!['records'] as List).last
              as Map;
      record['parentRevisionId'] = 'missing-parent-revision-id';
    }
    postCutoverSemantic['derivedIndex'] =
        _rebuiltIndexState(postCutoverSemantic);
  }
  final postCutoverDomains = <String, dynamic>{
    for (final entry in postCutoverSemantic.entries)
      entry.key: _encodeNewDomain(entry.key, entry.value),
  };
  final rollbackDomains = <String, dynamic>{
    for (final entry in postCutoverSemantic.entries)
      entry.key: _encodeRollbackDomain(entry.key, entry.value),
  };
  final remigratedSemantic = <String, Map<String, dynamic>>{
    for (final entry in rollbackDomains.entries)
      entry.key: _decodeRoundTripDomain(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      ),
  };
  if (isFullRoundTrip) {
    remigratedSemantic['derivedIndex'] = _rebuiltIndexState(remigratedSemantic);
  }
  final remigratedDomains = <String, dynamic>{
    for (final entry in remigratedSemantic.entries)
      entry.key: _encodeNewDomain(entry.key, entry.value),
  };
  final rollback = <String, dynamic>{
    'authority': 'legacy-readable',
    'stableId': stableId,
    'legacyBytes': legacy['bytes'],
    'preservedTargetHead': targetHead,
    'preservedNewWrite': newWriteMarkdown == null
        ? null
        : {
            'format': 'markdown',
            'body': newWriteMarkdown,
            'hash': newWriteHash,
          },
    'operationLedger': isFullRoundTrip
        ? [
            {'key': 'op-migrate-$stableId', 'digest': targetHead},
            {'key': 'op-new-write-$stableId', 'digest': newWriteHash},
          ]
        : <Map<String, dynamic>>[],
    'domains': rollbackDomains,
  };
  final revisionLedger = isFullRoundTrip
      ? List<Map<String, dynamic>>.from(
          (remigratedSemantic['revisionHistory']!['records'] as List)
              .map((value) => Map<String, dynamic>.from(value as Map)),
        )
      : <Map<String, dynamic>>[];
  final operationLedger = isFullRoundTrip
      ? List<Map<String, dynamic>>.from(
          (remigratedSemantic['operationLog']!['records'] as List)
              .map((value) => Map<String, dynamic>.from(value as Map)),
        )
      : <Map<String, dynamic>>[];
  final truthLedger = isFullRoundTrip
      ? List<Map<String, dynamic>>.from(
          (remigratedSemantic['userTruthSet']!['records'] as List)
              .map((value) => Map<String, dynamic>.from(value as Map)),
        )
      : <Map<String, dynamic>>[];
  final remigrated = <String, dynamic>{
    'authority': acceptedTarget == null ? 'legacy-blocked' : 'domain-target',
    'schema': acceptedTarget?['schema'],
    'stableId': stableId,
    'acceptedTarget': acceptedTarget,
    'revisionLedger': revisionLedger,
    'operationLedger': operationLedger,
    'eventLedger': <Map<String, dynamic>>[],
    'truthLedger': truthLedger,
    'domains': remigratedDomains,
  };
  final fullRoundTripDomains = <String, Map<String, Object?>>{};
  final physicalDigests = <String, Map<String, String>>{};
  if (isFullRoundTrip) {
    final acceptedStableIds = remigratedSemantic.values
        .expand((state) => state['stableIds'] as List)
        .cast<String>()
        .toSet();
    for (final name in _fullRoundTripDomainKeys) {
      final old = oldDomains[name]!;
      final first = firstMigrationDomains[name];
      final firstSemantic = firstMigrationSemantic[name]!;
      final rolledBack = rollbackDomains[name];
      final rolledBackSemantic = _decodeRoundTripDomain(
        name,
        Map<String, dynamic>.from(rolledBack as Map),
      );
      final remigratedDomain = remigratedSemantic[name]!;
      final remigratedPhysical = remigratedDomains[name];
      final writes = newWriteSets[name]!;
      final preserved = writes.isNotEmpty &&
          writes.every((write) {
            final digest = _canonicalSha256(write);
            return (rolledBackSemantic['records'] as List)
                    .any((record) => _canonicalSha256(record) == digest) &&
                (remigratedDomain['records'] as List)
                    .any((record) => _canonicalSha256(record) == digest);
          });
      final stableIds =
          List<String>.from(remigratedDomain['stableIds'] as List);
      final baselineSemantic = name == 'derivedIndex'
          ? _domainSemanticState(_rebuiltIndexState(oldDomains))
          : _domainSemanticState(old);
      final baselineStableIds =
          Set<String>.from(baselineSemantic['stableIds'] as List);
      final firstStableIds =
          Set<String>.from(firstSemantic['stableIds'] as List);
      final rollbackStableIds =
          Set<String>.from(rolledBackSemantic['stableIds'] as List);
      final remigratedStableIds = stableIds.toSet();
      final operationIds =
          List<String>.from(remigratedDomain['operationIds'] as List);
      final duplicateCount = _duplicateRecordCount(remigratedDomain) +
          (stableIds.length - stableIds.toSet().length) +
          (operationIds.length - operationIds.toSet().length);
      final referencesClosed = (remigratedDomain['records'] as List).every(
        (record) =>
            record is Map &&
            _roundTripRecordReferences(name, record)
                .every(acceptedStableIds.contains),
      );
      final oldPhysical = _canonicalSha256(old);
      final firstPhysical = _canonicalSha256(first);
      final rollbackPhysical = _canonicalSha256(rolledBack);
      final remigratePhysical = _canonicalSha256(remigratedPhysical);
      final firstSemanticPreserved = _deepExactEquals(
        baselineSemantic,
        _domainSemanticState(firstSemantic),
      );
      final stableIdsPreserved =
          baselineStableIds.difference(firstStableIds).isEmpty &&
              firstStableIds.difference(baselineStableIds).isEmpty &&
              firstStableIds.difference(rollbackStableIds).isEmpty &&
              rollbackStableIds.difference(remigratedStableIds).isEmpty;
      final invariantHeld = oldPhysical != firstPhysical &&
          rollbackPhysical != remigratePhysical &&
          firstSemanticPreserved &&
          stableIdsPreserved &&
          _deepExactEquals(
            _domainSemanticState(rolledBackSemantic),
            _domainSemanticState(remigratedDomain),
          ) &&
          preserved &&
          duplicateCount == 0 &&
          referencesClosed;
      physicalDigests[name] = {
        'oldBaseline': oldPhysical,
        'firstMigration': firstPhysical,
        'rollbackReadable': rollbackPhysical,
        'remigration': remigratePhysical,
      };
      fullRoundTripDomains[name] = {
        'oldBaselineSemanticDigest': _canonicalSha256(baselineSemantic),
        'newAfterFirstMigrationSemanticDigest':
            _canonicalSha256(_domainSemanticState(firstSemantic)),
        'postCutoverNewWriteSetDigest': _canonicalSha256(writes),
        'oldAfterRollbackSemanticDigest':
            _canonicalSha256(_domainSemanticState(rolledBackSemantic)),
        'newAfterRemigrationSemanticDigest':
            _canonicalSha256(_domainSemanticState(remigratedDomain)),
        'stableIdSetDigest': _canonicalSha256(
          (List<String>.from(remigratedDomain['stableIds'] as List)..sort()),
        ),
        'operationIdSetDigest': _canonicalSha256(
          (List<String>.from(remigratedDomain['operationIds'] as List)..sort()),
        ),
        'newWritesPreserved': preserved,
        'duplicateAcceptedCount': duplicateCount,
        'domainInvariantHeld': invariantHeld,
      };
    }
  }
  final derivedIndexRebuilt = !isFullRoundTrip ||
      _deepExactEquals(
        remigratedSemantic['derivedIndex'],
        _rebuiltIndexState(remigratedSemantic),
      );
  final derivedIndexOperationIdsByStage = !isFullRoundTrip
      ? <String, List<String>>{}
      : <String, List<String>>{
          'oldBaseline': List<String>.from(
            (_rebuiltIndexState(oldDomains)['operationIds'] as List),
          ),
          'firstMigration': List<String>.from(
            firstMigrationSemantic['derivedIndex']!['operationIds'] as List,
          ),
          'postCutover': List<String>.from(
            postCutoverSemantic['derivedIndex']!['operationIds'] as List,
          ),
          'rollback': List<String>.from(
            (_decodeRoundTripDomain(
              'derivedIndex',
              Map<String, dynamic>.from(rollbackDomains['derivedIndex'] as Map),
            )['operationIds'] as List),
          ),
          'remigration': List<String>.from(
            remigratedSemantic['derivedIndex']!['operationIds'] as List,
          ),
        };
  final derivedIndexOperationIdsHeld = !isFullRoundTrip ||
      (() {
        final baseline =
            derivedIndexOperationIdsByStage['oldBaseline']!.toSet();
        final first =
            derivedIndexOperationIdsByStage['firstMigration']!.toSet();
        final post = derivedIndexOperationIdsByStage['postCutover']!.toSet();
        final rollbackIds =
            derivedIndexOperationIdsByStage['rollback']!.toSet();
        final remigration =
            derivedIndexOperationIdsByStage['remigration']!.toSet();
        final newAccepted = newWriteSets.values
            .expand((writes) => writes)
            .map((write) => write['operationId'])
            .whereType<String>()
            .toSet();
        return _setEquals(baseline, first) &&
            newAccepted.isNotEmpty &&
            baseline.intersection(newAccepted).isEmpty &&
            post.containsAll(newAccepted) &&
            _setEquals(post, rollbackIds) &&
            _setEquals(rollbackIds, remigration);
      })();
  final allSixHeld = !isFullRoundTrip ||
      _setEquals(fullRoundTripDomains.keys.toSet(), _fullRoundTripDomainKeys) &&
          fullRoundTripDomains.values.every(
            (domain) =>
                _setEquals(
                    domain.keys.toSet(), _fullRoundTripDomainFieldKeys) &&
                domain['domainInvariantHeld'] == true,
          ) &&
          derivedIndexRebuilt &&
          derivedIndexOperationIdsHeld;
  return _RoundTripResult(
    _canonicalSha256(rollback),
    acceptedTarget == null ? null : _canonicalSha256(remigrated),
    newWriteMarkdown,
    rollback,
    remigrated,
    fullRoundTripDomains,
    allSixHeld,
    derivedIndexRebuilt,
    isFullRoundTrip
        ? [
            'old-baseline:${_canonicalSha256(oldDomains)}',
            'first-migration-new-physical:'
                '${_canonicalSha256(firstMigrationDomains)}',
            'post-cutover-nonempty-domain-writes:'
                '${_canonicalSha256(postCutoverDomains)}',
            'rollback-legacy-readable-preserving-new-writes:'
                '${_canonicalSha256(rollbackDomains)}',
            'remigration-new-physical-rebuilt-index:'
                '${_canonicalSha256(remigratedDomains)}',
          ]
        : const [],
    physicalDigests,
    derivedIndexOperationIdsByStage,
  );
}

class _MigrationManifests {
  const _MigrationManifests(this.oldManifest, this.newManifest);

  final List<Map<String, dynamic>> oldManifest;
  final List<Map<String, dynamic>> newManifest;
}

_MigrationManifests _buildMigrationManifests(
  MigrationCaseDefinition definition,
  String legacyDigest,
  String? targetDigest,
  bool commitCase,
) {
  if (!commitCase || targetDigest == null) {
    return const _MigrationManifests([], []);
  }
  final id = definition.id;
  final targetRole = _formalSpecFor(definition.objectType).targetRole;
  return _MigrationManifests(
    [
      {
        'path': 'state/$targetRole/$id.json',
        'kind': 'file',
        'hash': legacyDigest,
      },
      {
        'path': 'state/$targetRole/$id.meta.yaml',
        'kind': 'file',
        'hash': _canonicalSha256('old-file-meta:$id'),
      },
      {
        'path': 'objects/$id-0.bin',
        'kind': 'object',
        'hash': _canonicalSha256('old-object-0:$id'),
      },
      {
        'path': 'objects/$id-1.bin',
        'kind': 'object',
        'hash': _canonicalSha256('old-object-1:$id'),
      },
    ],
    [
      {
        'path': 'state/$targetRole/$id.json',
        'kind': 'file',
        'hash': targetDigest,
      },
      {
        'path': 'state/$targetRole/$id.meta.yaml',
        'kind': 'file',
        'hash': _canonicalSha256('new-file-meta:$id'),
      },
      {
        'path': 'objects/$id-0.bin',
        'kind': 'object',
        'hash': _canonicalSha256('new-object-0:$id'),
      },
      {
        'path': 'objects/$id-1.bin',
        'kind': 'object',
        'hash': _canonicalSha256('new-object-1:$id'),
      },
    ],
  );
}

class _MigrationCommitResult {
  const _MigrationCommitResult({
    required this.convergence,
    required this.journalPhase,
    required this.receiptCount,
    required this.changeCount,
    required this.projectionCount,
    required this.ledgersExactlyOnce,
    required this.crashDurability,
    required this.serializedDigest,
    required this.trace,
    this.idempotencyLookupCount = 0,
    this.businessReadCount = 0,
    this.reusedReceipt = false,
    this.durableState = const {},
  });

  final String convergence;
  final String journalPhase;
  final int receiptCount;
  final int changeCount;
  final int projectionCount;
  final bool ledgersExactlyOnce;
  final String crashDurability;
  final String serializedDigest;
  final List<String> trace;
  final int idempotencyLookupCount;
  final int businessReadCount;
  final bool reusedReceipt;
  final Map<String, Object?> durableState;
}

_MigrationCommitResult _blockedMigrationCommit(String crashPhase) =>
    _MigrationCommitResult(
      convergence: 'needs_resolution',
      journalPhase: 'none',
      receiptCount: 0,
      changeCount: 0,
      projectionCount: 0,
      ledgersExactlyOnce: true,
      crashDurability: crashPhase == 'none' ? 'none' : 'blocked_before_stage',
      serializedDigest: 'none',
      trace: const ['preserve-raw', 'blocked-before-acceptance'],
    );

Map<String, dynamic> _initialMigrationDurableState(
  Map<String, dynamic> initialLedgers,
) {
  _requireMigrationInitialLedgers(
    initialLedgers,
    'migration initial durable ledgers',
  );
  return {
    'journalPhase': 'none',
    'authority': 'old',
    'actionTrace': <String>[],
    'publishedHashes': <String>[],
    'identityPrecheckPassed': false,
    'idempotencyChecked': false,
    'businessReadCompleted': false,
    'stageWrites': <int>[],
    'stagedHashes': <String>[],
    'stageFsyncs': <int>[],
    'stageFsyncHashes': <String>[],
    'stageDirectoryFsync': false,
    'txBCommitted': false,
    'rollbackCopies': <int>[],
    'rollbackCopyHashes': <String>[],
    'rollbackFsyncs': <int>[],
    'rollbackFsyncHashes': <String>[],
    'publishPhaseStarted': false,
    'publishedFiles': <int>[],
    'publishedObjects': <int>[],
    'filesPublishedPhaseCommitted': false,
    'activationStarted': false,
    'activationCommitted': false,
    'projectionsStarted': <int>[],
    'projectionsCompleted': <int>[],
    'invalidated': false,
    'cursorCommitted': false,
    'notificationSent': false,
    'responseSent': false,
    'cleanupInProgress': <int>[],
    'cleanupCompleted': <int>[],
    'initialLedgers': {
      'receipt': _copyLedger(initialLedgers['receipt'] as List),
      'change': _copyLedger(initialLedgers['change'] as List),
      'projection': _copyLedger(initialLedgers['projection'] as List),
    },
    'receiptLedger': _copyLedger(initialLedgers['receipt'] as List),
    'changeLedger': _copyLedger(initialLedgers['change'] as List),
    'projectionLedger': _copyLedger(initialLedgers['projection'] as List),
  };
}

_MigrationCommitResult _runMigrationCommit(
  String crashPoint,
  _MigrationManifests manifests, {
  required String failurePoint,
  required String oldHash,
  required String newHash,
  required String observedHash,
  required Map<String, dynamic> initialLedgers,
}) {
  _requireMigrationInitialLedgers(
    initialLedgers,
    'migration transaction.initialLedgers',
  );
  if (crashPoint == 'none') {
    return const _MigrationCommitResult(
      convergence: 'not_applicable',
      journalPhase: 'none',
      receiptCount: 0,
      changeCount: 0,
      projectionCount: 0,
      ledgersExactlyOnce: true,
      crashDurability: 'none',
      serializedDigest: 'none',
      trace: [],
    );
  }
  if (!exactExpandedMigrationCrashPoints.contains(crashPoint)) {
    fail(
      FailureClass.unsupported,
      'unknown exact migration crash point: $crashPoint',
    );
  }
  if (failurePoint != 'none' &&
      !exactMigrationFailurePoints.contains(failurePoint)) {
    fail(
      FailureClass.unsupported,
      'unknown exact migration failure point: $failurePoint',
    );
  }
  final initialState = _initialMigrationDurableState(initialLedgers);
  final thirdPartyConflict = observedHash != oldHash && observedHash != newHash;
  if ((failurePoint == 'external_third_hash_conflict') != thirdPartyConflict) {
    fail(
      FailureClass.inputRejected,
      'external third hash failure must be derived from observed/old/new hash',
    );
  }
  final boundary = _migrationBoundaryStops[crashPoint];
  if (boundary == null) {
    fail(FailureClass.unsupported, 'unmapped exact crash point: $crashPoint');
  }
  final state = _executeMigrationActionsToBoundary(
    initialState,
    boundary,
    manifests,
  );
  final serialized = jsonEncode(_canonicalizeJson(state));
  final serializedDigest = sha256.convert(utf8.encode(serialized)).toString();
  final durability = boundary.durability;
  if (failurePoint != 'none') {
    return _recoverExactMigrationFailure(
      failurePoint,
      crashPoint,
      state,
      serializedDigest,
    );
  }
  return _recoverMigrationDurableState(
    jsonDecode(serialized) as Map<String, dynamic>,
    manifests,
    crashDurability: durability,
    serializedDigest: serializedDigest,
    tracePrefix: 'crash:$crashPoint',
    expectedCrashPoint: crashPoint,
    expectedInitialLedgers: initialLedgers,
  );
}

class _MigrationBoundaryStop {
  const _MigrationBoundaryStop(this.afterAction, this.durability);

  final String? afterAction;
  final String durability;
}

const _migrationActions = <String>[
  'identity_precheck',
  'idempotency_lookup',
  'business_read',
  'journal_tx_a_commit',
  'stage_file_write:0',
  'stage_file_fsync:0',
  'stage_file_write:1',
  'stage_file_fsync:1',
  'stage_directory_fsync',
  'journal_tx_b_commit',
  'rollback_copy:0',
  'rollback_fsync:0',
  'rollback_copy:1',
  'rollback_fsync:1',
  'publish_phase_start',
  'publish_file:0',
  'publish_file:1',
  'publish_object:0',
  'publish_object:1',
  'files_published_phase_commit',
  'activation_start',
  'activation_commit',
  'invalidation',
  'projection_start:0',
  'projection_finish:0',
  'projection_start:1',
  'projection_finish:1',
  'projection_start:2',
  'projection_finish:2',
  'projection_start:3',
  'projection_finish:3',
  'cursor_commit',
  'notification_send',
  'response_send',
  'cleanup_start:0',
  'cleanup_finish:0',
  'cleanup_start:1',
  'cleanup_finish:1',
];

Map<String, _MigrationBoundaryStop> _buildMigrationBoundaryStops() {
  final stops = <String, _MigrationBoundaryStop>{};
  void add(String boundary, String? action, String durability) {
    stops[boundary] = _MigrationBoundaryStop(action, durability);
  }

  add('before_identity_precheck', null, 'before');
  add('after_identity_precheck_before_idempotency', 'identity_precheck',
      'after');
  add('after_idempotency_before_business_read', 'idempotency_lookup', 'after');
  add('before_journal_tx_a', 'business_read', 'before');
  add('after_journal_tx_a_commit', 'journal_tx_a_commit', 'after');
  for (var ordinal = 0; ordinal < 2; ordinal++) {
    final previousFsync =
        ordinal == 0 ? 'journal_tx_a_commit' : 'stage_file_fsync:0';
    add('before_stage_file_write:$ordinal', previousFsync, 'before');
    add('after_stage_file_write:${ordinal}_before_file_fsync',
        'stage_file_write:$ordinal', 'after');
    add('after_stage_file_fsync:${ordinal}_before_directory_fsync',
        'stage_file_fsync:$ordinal', 'after');
  }
  add('after_stage_directory_fsync_before_tx_b', 'stage_directory_fsync',
      'after');
  add('after_tx_b_commit', 'journal_tx_b_commit', 'after');
  for (var ordinal = 0; ordinal < 2; ordinal++) {
    final previousFsync =
        ordinal == 0 ? 'journal_tx_b_commit' : 'rollback_fsync:0';
    add('before_rollback_copy:$ordinal', previousFsync, 'before');
    add('after_rollback_copy:${ordinal}_before_rollback_fsync',
        'rollback_copy:$ordinal', 'after');
    add('after_rollback_fsync:$ordinal', 'rollback_fsync:$ordinal', 'after');
  }
  add('before_publish_started_phase', 'rollback_fsync:1', 'before');
  add('after_publish_started_phase', 'publish_phase_start', 'after');
  add('before_file_publish:0', 'publish_phase_start', 'before');
  add('after_file_publish:0', 'publish_file:0', 'after');
  add('before_file_publish:1', 'publish_file:0', 'before');
  add('after_file_publish:1', 'publish_file:1', 'after');
  add('before_object_publish:0', 'publish_file:1', 'before');
  add('after_object_publish:0', 'publish_object:0', 'after');
  add('before_object_publish:1', 'publish_object:0', 'before');
  add('after_object_publish:1', 'publish_object:1', 'after');
  add('before_files_published_phase', 'publish_object:1', 'before');
  add('after_files_published_phase', 'files_published_phase_commit', 'after');
  add('before_activation_tx', 'files_published_phase_commit', 'before');
  add('during_activation_tx_before_commit', 'activation_start', 'during');
  add('after_activation_tx_commit', 'activation_commit', 'after');
  add('after_invalidation_before_rebuild', 'invalidation', 'after');
  for (var ordinal = 0; ordinal < 4; ordinal++) {
    final previous =
        ordinal == 0 ? 'invalidation' : 'projection_finish:${ordinal - 1}';
    add('before_projection_rebuild:$ordinal', previous, 'before');
    add('during_projection_rebuild:$ordinal', 'projection_start:$ordinal',
        'during');
    add('after_projection_rebuild:${ordinal}_before_cursor_commit',
        'projection_finish:$ordinal', 'after');
  }
  add('after_cursor_commit_before_notification', 'cursor_commit', 'after');
  add('after_notification_before_response', 'notification_send', 'after');
  add('after_response_before_cleanup', 'response_send', 'after');
  add('during_cleanup:0', 'cleanup_start:0', 'during');
  add('during_cleanup:1', 'cleanup_start:1', 'during');
  if (!_setEquals(
      stops.keys.toSet(), exactExpandedMigrationCrashPoints.toSet())) {
    throw StateError('migration boundary/action map is not exact');
  }
  return Map.unmodifiable(stops);
}

final _migrationBoundaryStops = _buildMigrationBoundaryStops();

List<String> _migrationActionTraceForCrashPoint(String crashPoint) {
  final boundary = _migrationBoundaryStops[crashPoint];
  if (boundary == null) {
    fail(FailureClass.unsupported, 'unmapped exact crash point: $crashPoint');
  }
  if (boundary.afterAction == null) return const <String>[];
  final index = _migrationActions.indexOf(boundary.afterAction!);
  if (index < 0) {
    fail(
      FailureClass.unsupported,
      'crash point action is not in the ordered migration machine',
    );
  }
  return _migrationActions.take(index + 1).toList(growable: false);
}

Map<String, dynamic> _executeMigrationActionsToBoundary(
  Map<String, dynamic> initial,
  _MigrationBoundaryStop boundary,
  _MigrationManifests manifests,
) {
  var state = _roundTrip(initial);
  if (boundary.afterAction == null) return state;
  for (final action in _migrationActions) {
    state = _applyMigrationAction(state, action, manifests);
    if (action == boundary.afterAction) return state;
  }
  fail(FailureClass.unsupported, 'boundary action is not executable');
}

Map<String, dynamic> _applyMigrationAction(
  Map<String, dynamic> state,
  String action,
  _MigrationManifests manifests,
) {
  final next = _roundTrip(state);
  final trace = next['actionTrace'] as List;
  if (!trace.contains(action)) trace.add(action);
  final files = manifests.newManifest
      .where((entry) => entry['kind'] == 'file')
      .toList(growable: false);
  final objects = manifests.newManifest
      .where((entry) => entry['kind'] == 'object')
      .toList(growable: false);
  final rollbackFiles = manifests.oldManifest
      .where((entry) => entry['kind'] == 'file')
      .toList(growable: false);

  void addOrdinal(String key, int ordinal) {
    final values = next[key] as List;
    if (!values.contains(ordinal)) values.add(ordinal);
  }

  void addHash(String key, String hash) {
    final values = next[key] as List;
    if (!values.contains(hash)) values.add(hash);
  }

  final ordinalMatch = RegExp(r':(\d+)$').firstMatch(action);
  final ordinal =
      ordinalMatch == null ? null : int.parse(ordinalMatch.group(1)!);
  switch (action.split(':').first) {
    case 'identity_precheck':
      next['identityPrecheckPassed'] = true;
    case 'idempotency_lookup':
      next['idempotencyChecked'] = true;
    case 'business_read':
      next['businessReadCompleted'] = true;
    case 'journal_tx_a_commit':
      next['journalPhase'] = 'intent_durable';
    case 'stage_file_write':
      addOrdinal('stageWrites', ordinal!);
      addHash('stagedHashes', files[ordinal]['hash'] as String);
    case 'stage_file_fsync':
      addOrdinal('stageFsyncs', ordinal!);
      addHash('stageFsyncHashes', files[ordinal]['hash'] as String);
    case 'stage_directory_fsync':
      next['stageDirectoryFsync'] = true;
    case 'journal_tx_b_commit':
      next['txBCommitted'] = true;
      next['journalPhase'] = 'staged';
    case 'rollback_copy':
      addOrdinal('rollbackCopies', ordinal!);
      addHash('rollbackCopyHashes', rollbackFiles[ordinal]['hash'] as String);
    case 'rollback_fsync':
      addOrdinal('rollbackFsyncs', ordinal!);
      addHash('rollbackFsyncHashes', rollbackFiles[ordinal]['hash'] as String);
    case 'publish_phase_start':
      next['publishPhaseStarted'] = true;
      next['journalPhase'] = 'publish_started';
    case 'publish_file':
      addOrdinal('publishedFiles', ordinal!);
      addHash('publishedHashes', files[ordinal]['hash'] as String);
    case 'publish_object':
      addOrdinal('publishedObjects', ordinal!);
      addHash('publishedHashes', objects[ordinal]['hash'] as String);
    case 'files_published_phase_commit':
      next['filesPublishedPhaseCommitted'] = true;
      next['journalPhase'] = 'files_published';
    case 'activation_start':
      next['activationStarted'] = true;
    case 'activation_commit':
      next['activationCommitted'] = true;
      next['authority'] = 'new';
      next['journalPhase'] = 'db_activated';
      next['receiptLedger'] =
          _appendMigrationLedger(next['receiptLedger'] as List);
      next['changeLedger'] =
          _appendMigrationLedger(next['changeLedger'] as List);
    case 'invalidation':
      next['invalidated'] = true;
    case 'projection_start':
      addOrdinal('projectionsStarted', ordinal!);
      next['journalPhase'] = 'projections_rebuilding';
    case 'projection_finish':
      addOrdinal('projectionsCompleted', ordinal!);
    case 'cursor_commit':
      next['cursorCommitted'] = true;
      next['projectionLedger'] =
          _appendMigrationLedger(next['projectionLedger'] as List);
      next['journalPhase'] = 'complete';
    case 'notification_send':
      next['notificationSent'] = true;
    case 'response_send':
      next['responseSent'] = true;
    case 'cleanup_start':
      next['cleanupInProgress'] = [ordinal!];
    case 'cleanup_finish':
      next['cleanupInProgress'] = <int>[];
      addOrdinal('cleanupCompleted', ordinal!);
    default:
      fail(FailureClass.unsupported, 'unknown migration action: $action');
  }
  return next;
}

bool _migrationDurableStateValid(
  Map<String, dynamic> state,
  _MigrationManifests manifests, {
  required Map<String, dynamic> expectedInitialLedgers,
  required List<String> expectedActionTrace,
}) {
  final trace = state['actionTrace'];
  final initialLedgers = state['initialLedgers'];
  if (!_isMigrationInitialLedgers(expectedInitialLedgers) ||
      !_isMigrationInitialLedgers(initialLedgers) ||
      !_isMigrationLedger(state['receiptLedger']) ||
      !_isMigrationLedger(state['changeLedger']) ||
      !_isMigrationLedger(state['projectionLedger']) ||
      trace is! List ||
      trace.any((entry) => entry is! String) ||
      trace.length > _migrationActions.length ||
      !_deepExactEquals(
        trace,
        _migrationActions.take(trace.length).toList(growable: false),
      )) {
    return false;
  }
  if (!_deepExactEquals(initialLedgers, expectedInitialLedgers) ||
      !_deepExactEquals(trace, expectedActionTrace)) {
    return false;
  }
  var expected = _initialMigrationDurableState(
    initialLedgers as Map<String, dynamic>,
  );
  for (final action in trace.cast<String>()) {
    expected = _applyMigrationAction(expected, action, manifests);
  }
  return _deepExactEquals(state, expected);
}

_MigrationCommitResult _recoverMigrationDurableState(
  Map<String, dynamic> restarted,
  _MigrationManifests manifests, {
  required String crashDurability,
  required String serializedDigest,
  required String tracePrefix,
  required String expectedCrashPoint,
  required Map<String, dynamic> expectedInitialLedgers,
}) {
  final trace = <String>[
    tracePrefix,
    'restart:${restarted['journalPhase']}',
    'validate-granular-durable-state',
  ];
  if (!_migrationDurableStateValid(
    restarted,
    manifests,
    expectedInitialLedgers: expectedInitialLedgers,
    expectedActionTrace: _migrationActionTraceForCrashPoint(expectedCrashPoint),
  )) {
    trace.add('recover:needs-resolution-corrupt-durable-state');
    return _MigrationCommitResult(
      convergence: 'needs_resolution',
      journalPhase: 'needs_resolution',
      receiptCount: _migrationLedgerCount(restarted['receiptLedger']),
      changeCount: _migrationLedgerCount(restarted['changeLedger']),
      projectionCount: _migrationLedgerCount(restarted['projectionLedger']),
      ledgersExactlyOnce: false,
      crashDurability: crashDurability,
      serializedDigest: serializedDigest,
      trace: trace,
      durableState: Map<String, Object?>.from(restarted),
    );
  }
  if (restarted['txBCommitted'] != true) {
    trace.add('recover:old-complete-from-pre-tx-b-state');
    return _MigrationCommitResult(
      convergence: 'old',
      journalPhase: 'rolled_back',
      receiptCount: 0,
      changeCount: 0,
      projectionCount: 0,
      ledgersExactlyOnce: true,
      crashDurability: crashDurability,
      serializedDigest: serializedDigest,
      trace: trace,
      durableState: Map<String, Object?>.from(restarted),
    );
  }
  var recovered = restarted;
  for (final action in _migrationActions) {
    recovered = _applyMigrationAction(recovered, action, manifests);
  }
  trace.add('recover:roll-forward-from-validated-granular-state');
  final receiptCount = _migrationLedgerCount(
    _copyLedger(recovered['receiptLedger'] as List),
  );
  final changeCount = _migrationLedgerCount(
    _copyLedger(recovered['changeLedger'] as List),
  );
  final projectionCount = _migrationLedgerCount(
    _copyLedger(recovered['projectionLedger'] as List),
  );
  final recoveredValid = _migrationDurableStateValid(
    recovered,
    manifests,
    expectedInitialLedgers: expectedInitialLedgers,
    expectedActionTrace: _migrationActions,
  );
  return _MigrationCommitResult(
    convergence: recoveredValid ? 'new' : 'needs_resolution',
    journalPhase: recoveredValid ? 'complete' : 'needs_resolution',
    receiptCount: receiptCount,
    changeCount: changeCount,
    projectionCount: projectionCount,
    ledgersExactlyOnce: recoveredValid &&
        receiptCount == 1 &&
        changeCount == 1 &&
        projectionCount == 1,
    crashDurability: crashDurability,
    serializedDigest: serializedDigest,
    trace: trace,
    durableState: Map<String, Object?>.from(restarted),
  );
}

_MigrationCommitResult _recoverExactMigrationFailure(
  String failurePoint,
  String crashPoint,
  Map<String, dynamic> state,
  String serializedDigest,
) {
  final trace = <String>[
    'failure:$failurePoint@$crashPoint',
    'restart:${state['journalPhase']}',
  ];
  final precheckFailure = const {
    'stale_credential_generation',
    'identity_binding_mismatch',
    'scope_denied',
    'stale_core_instance',
    'stale_authority_epoch',
    'stale_worker_fence',
    'lineage_state_rejected',
  }.contains(failurePoint);
  final duplicateSame = failurePoint == 'duplicate_key_same_digest';
  final notification = failurePoint == 'notification_failure';
  final recoverToNew =
      notification || failurePoint == 'projection_rebuild_failure';
  final recoverToOld = precheckFailure ||
      failurePoint == 'disk_full_during_stage' ||
      failurePoint == 'permission_denied_during_stage' ||
      failurePoint == 'invalid_yaml' ||
      failurePoint == 'rollback_manifest_corrupt' ||
      failurePoint == 'staging_manifest_corrupt';
  final existingReceiptCount = _migrationLedgerCount(
    _copyLedger(state['receiptLedger'] as List),
  );
  final receipts = duplicateSame
      ? existingReceiptCount
      : recoverToNew
          ? 1
          : 0;
  final changes = recoverToNew ? 1 : 0;
  final projections = recoverToNew ? 1 : 0;
  return _MigrationCommitResult(
    convergence: duplicateSame
        ? 'duplicate_reused'
        : recoverToNew
            ? 'new'
            : recoverToOld
                ? 'old'
                : 'needs_resolution',
    journalPhase: duplicateSame
        ? 'none'
        : recoverToNew
            ? 'complete'
            : recoverToOld
                ? 'rolled_back'
                : 'needs_resolution',
    receiptCount: receipts,
    changeCount: changes,
    projectionCount: projections,
    ledgersExactlyOnce: receipts <= 1 && changes <= 1 && projections <= 1,
    crashDurability: 'failure',
    serializedDigest: serializedDigest,
    trace: trace,
    idempotencyLookupCount: precheckFailure ? 0 : 1,
    businessReadCount: precheckFailure ||
            duplicateSame ||
            failurePoint == 'duplicate_key_different_digest'
        ? 0
        : 1,
    reusedReceipt: duplicateSame && existingReceiptCount == 1,
  );
}

bool _isMigrationLedger(Object? value) =>
    value is List &&
    value.every(
      (entry) =>
          entry is Map<String, dynamic> &&
          _setEquals(entry.keys.toSet(), const {'key', 'digest'}) &&
          entry['key'] is String &&
          (entry['key'] as String).isNotEmpty &&
          (entry['key'] as String).length <= 512 &&
          entry['digest'] is String &&
          (entry['digest'] as String).isNotEmpty &&
          (entry['digest'] as String).length <= 512,
    );

bool _isMigrationInitialLedgers(Object? value) =>
    value is Map<String, dynamic> &&
    _setEquals(
      value.keys.toSet(),
      const {'receipt', 'change', 'projection'},
    ) &&
    value.values.every(_isMigrationLedger);

void _requireMigrationInitialLedgers(Object? value, String path) {
  if (!_isMigrationInitialLedgers(value)) {
    fail(
      FailureClass.inputRejected,
      '$path must contain exact structured receipt/change/projection ledgers',
    );
  }
}

List<Map<String, dynamic>> _copyLedger(Object? values) {
  if (!_isMigrationLedger(values)) {
    fail(
      FailureClass.inputRejected,
      'migration ledger must contain exact non-empty key/digest entries',
    );
  }
  return (values as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: true);
}

List<Map<String, dynamic>> _appendMigrationLedger(List values) {
  final ledger = _copyLedger(values);
  final same = ledger.any((entry) =>
      entry['key'] == 'migration' && entry['digest'] == 'migration-digest');
  final conflict = ledger.any((entry) =>
      entry['key'] == 'migration' && entry['digest'] != 'migration-digest');
  if (!same && !conflict) {
    ledger.add({'key': 'migration', 'digest': 'migration-digest'});
  }
  return ledger;
}

int _migrationLedgerCount(Object? value) {
  if (!_isMigrationLedger(value)) return 0;
  return (value as List)
      .cast<Map<String, dynamic>>()
      .where((entry) =>
          entry['key'] == 'migration' && entry['digest'] == 'migration-digest')
      .length;
}

_SimulationResult _executeMigrationCase(
  MigrationCaseDefinition definition,
  Map<String, dynamic> input,
) {
  final legacy = input['legacy'] as Map<String, dynamic>;
  final transaction = input['transaction'] as Map<String, dynamic>;
  final details = Map<String, dynamic>.from(legacy['details'] as Map);
  final derivedFailurePoint = details['rawKind'] == 'commit'
      ? _deriveMigrationFailurePoint(details)
      : 'none';
  final failureFacts = details['rawKind'] == 'commit'
      ? details['failureFacts'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final derived = _deriveMigrationTarget(definition, legacy);
  final computedLegacyHeadHash = _canonicalSha256({
    'bytes': legacy['bytes'],
    'details': legacy['details'],
    'refs': legacy['refs'],
  });
  final legacyDigest = _canonicalSha256(legacy);
  final targetDigest = derived.acceptedTarget == null
      ? null
      : _canonicalSha256(derived.acceptedTarget);
  final roundTrip =
      _executeRoundTrip(definition, legacy, derived.acceptedTarget);
  final manifests = _buildMigrationManifests(
    definition,
    legacyDigest,
    targetDigest,
    definition.commitCase,
  );
  final initialLedgers = transaction['initialLedgers'] as Map<String, dynamic>;
  final oldHash = details['rawKind'] == 'commit'
      ? failureFacts['oldHash'] as String
      : transaction['oldHash'] as String;
  final newHash = details['rawKind'] == 'commit'
      ? failureFacts['newHash'] as String
      : transaction['newHash'] as String;
  final observedHash = details['rawKind'] == 'commit'
      ? failureFacts['observedHash'] as String
      : transaction['observedHash'] as String;
  final commit = derived.acceptedTarget == null
      ? _blockedMigrationCommit(transaction['crashPhase'] as String)
      : _runMigrationCommit(
          transaction['crashPhase'] as String,
          manifests,
          failurePoint: derivedFailurePoint,
          oldHash: oldHash,
          newHash: newHash,
          observedHash: observedHash,
          initialLedgers: initialLedgers,
        );
  final refs = Set<String>.from(legacy['refs'] as List);
  final isFormalInventory = details['rawKind'] == 'formal_catalog';
  final derivedCatalog = isFormalInventory
      ? List<Map<String, dynamic>>.from(
          (derived.acceptedTarget!['catalog'] as List)
              .map((value) => Map<String, dynamic>.from(value as Map)),
        )
      : <Map<String, dynamic>>[];
  final catalogTypes =
      derivedCatalog.map((entry) => entry['objectType'] as String).toSet();
  final inventoryComplete = !isFormalInventory ||
      refs.length == 32 &&
          refs.containsAll(_p5FormalObjectTypes) &&
          derivedCatalog.length == 32 &&
          catalogTypes.length == 32 &&
          _validateFrozenFormalCatalog(derivedCatalog);
  final computedCounts = {
    'revision': roundTrip.revisionCount,
    'operation': roundTrip.operationCount,
    'event': roundTrip.eventCount,
    'truth': roundTrip.truthCount,
  };
  final targetSchema = derived.acceptedTarget?['schema'];
  final markdownFragment = derived.acceptedTarget?['markdownFragment'];
  final leadingFence = markdownFragment is String
      ? RegExp(r'^`+').firstMatch(markdownFragment)?.group(0)?.length ?? 0
      : 0;
  final isIntake = const {
    'capture',
    'import_candidate',
    'link_inbox_item',
  }.contains(definition.objectType);
  final downstream = isIntake && derived.acceptedTarget != null
      ? List<String>.from(derived.acceptedTarget!['downstream'] as List)
      : const <String>[];
  final downstreamCounts = {
    for (final kind in const ['card', 'source', 'truth', 'index'])
      kind: downstream.where((entry) => entry.startsWith('$kind:')).length,
  };
  final domainTargetValid = (!isIntake ||
          (derived.acceptedTarget == null
              ? derived.classification == 'blocked'
              : targetSchema != 'hereiam-card-envelope-v1' &&
                  !derived.acceptedTarget!.containsKey('markdown') &&
                  (derived.acceptedTarget!['downstream'] as List).isEmpty)) &&
      (definition.objectType != 'evidence_claim' ||
          derived.acceptedTarget?['claimCreated'] == false) &&
      (definition.objectType != 'task_artifact' ||
          derived.acceptedTarget == null ||
          derived.acceptedTarget?['truthCreated'] == false) &&
      (derived.classification != 'blocked' ||
          (derived.acceptedTarget == null &&
              targetDigest == null &&
              manifests.newManifest.isEmpty &&
              commit.receiptCount == 0 &&
              commit.changeCount == 0 &&
              commit.projectionCount == 0));
  final exactCommitBinding = !definition.commitCase ||
      (transaction['crashPhase'] == definition.crashPhase &&
          (definition.isFailureCase
              ? exactMigrationFailurePoints.contains(derivedFailurePoint)
              : derivedFailurePoint == 'none') &&
          (details['rawKind'] != 'commit' ||
              (transaction['oldHash'] == failureFacts['oldHash'] &&
                  transaction['newHash'] == failureFacts['newHash'] &&
                  transaction['observedHash'] ==
                      failureFacts['observedHash'])) &&
          exactExpandedMigrationCrashPoints.contains(definition.crashPhase) &&
          (derivedFailurePoint == 'none' ||
              exactMigrationFailurePoints.contains(derivedFailurePoint)));
  final precheckFailure = const {
    'stale_credential_generation',
    'identity_binding_mismatch',
    'scope_denied',
    'stale_core_instance',
    'stale_authority_epoch',
    'stale_worker_fence',
    'lineage_state_rejected',
  }.contains(derivedFailurePoint);
  final exactFailureOrdering = !definition.commitCase ||
      (precheckFailure
          ? commit.idempotencyLookupCount == 0 && commit.businessReadCount == 0
          : derivedFailurePoint == 'duplicate_key_same_digest'
              ? commit.idempotencyLookupCount == 1 &&
                  commit.businessReadCount == 0 &&
                  commit.reusedReceipt
              : derivedFailurePoint == 'duplicate_key_different_digest'
                  ? commit.idempotencyLookupCount == 1 &&
                      commit.businessReadCount == 0
                  : true);
  final valid = exactCommitBinding &&
      exactFailureOrdering &&
      legacy['classification'] == 'legacy_physical' &&
      legacy['headHash'] == computedLegacyHeadHash &&
      const {
        'deterministic',
        'controlled_extension',
        'degraded_preserved',
        'blocked',
      }.contains(derived.classification) &&
      roundTrip.ledgersUnique &&
      roundTrip.allSixRoundTripDomainsHeld &&
      commit.ledgersExactlyOnce &&
      inventoryComplete &&
      domainTargetValid;
  final computedResult =
      valid ? 'migration_case_verified' : 'migration_case_contract_violation';
  final fullRoundTrip = roundTrip.fullRoundTripDomains.isEmpty
      ? null
      : <String, Object?>{
          'domains': roundTrip.fullRoundTripDomains,
          'allSixRoundTripDomainsHeld': roundTrip.allSixRoundTripDomainsHeld,
          'derivedIndexRebuiltFromAcceptedState':
              roundTrip.derivedIndexRebuiltFromAcceptedState,
          'transitionTrace': roundTrip.transitionTrace,
          'physicalDigests': roundTrip.physicalDigests,
          'derivedIndexOperationIdsByStage':
              roundTrip.derivedIndexOperationIdsByStage,
        };
  final literalComparable = <String, Object?>{
    'result': computedResult,
    'target': {
      'classification': derived.classification,
      'headHash': targetDigest,
      'targetRole': derived.targetRole,
      'migrationAction': derived.migrationAction,
      'blockedReason': derived.blockedReason,
      'catalog': derivedCatalog,
    },
    'roundTrip': {
      'legacyDigest': legacyDigest,
      'targetDigest': targetDigest,
      'rollbackDigest': roundTrip.rollbackDigest,
      'remigrateDigest': roundTrip.remigrateDigest,
      'newWriteMarkdown': roundTrip.newWriteMarkdown,
      'stableId': legacy['stableId'],
      'revisionCount': computedCounts['revision'],
      'operationCount': computedCounts['operation'],
      'eventCount': computedCounts['event'],
      'truthCount': computedCounts['truth'],
      'ledgersUnique': roundTrip.ledgersUnique,
      'fullRoundTrip': fullRoundTrip,
    },
    'commit': {
      'failurePoint':
          derivedFailurePoint == 'none' ? null : derivedFailurePoint,
      'convergence': commit.convergence,
      'journalPhase': commit.journalPhase,
      'oldManifest': manifests.oldManifest,
      'newManifest': manifests.newManifest,
      'receiptCount': commit.receiptCount,
      'changeCount': commit.changeCount,
      'projectionCount': commit.projectionCount,
      'ledgersExactlyOnce': commit.ledgersExactlyOnce,
    },
  };
  return _result(computedResult, {
    'contractInvariantHeld': valid,
    'literalComparable': literalComparable,
    'caseId': definition.id,
    'objectType': definition.objectType,
    'classification': derived.classification,
    'derivedOutcome': derived.outcome,
    'targetRole': derived.targetRole,
    'migrationAction': derived.migrationAction,
    'blockedReason': derived.blockedReason,
    'targetSchema': targetSchema,
    'hasMarkdown': derived.acceptedTarget?.containsKey('markdown') ?? false,
    'acceptedTargetPresent': derived.acceptedTarget != null,
    'acceptedTargetDigest': targetDigest,
    'conversionOutputDigest': derived.acceptedTarget == null
        ? null
        : _canonicalSha256(derived.acceptedTarget),
    'markdownFenceLength': leadingFence,
    'preservationDigest': _canonicalSha256(derived.preservation),
    'legacyClassification': legacy['classification'],
    'legacyHeadHash': computedLegacyHeadHash,
    'headHash': targetDigest,
    'legacyDigest': legacyDigest,
    'targetDigest': targetDigest,
    'rollbackDigest': roundTrip.rollbackDigest,
    'remigrateDigest': roundTrip.remigrateDigest,
    'newWriteMarkdownHash': roundTrip.newWriteMarkdown == null
        ? null
        : _canonicalSha256(roundTrip.newWriteMarkdown),
    'stableId': legacy['stableId'],
    'exactExpandedCrashPointExecuted':
        definition.commitCase ? transaction['crashPhase'] : null,
    'exactFailurePointExecuted':
        derivedFailurePoint == 'none' ? null : derivedFailurePoint,
    'crashDurability': commit.crashDurability,
    'restartCount': definition.commitCase ? 1 : 0,
    'serializedBeforeRestartDigest': commit.serializedDigest,
    'durableStateAtCrash': commit.durableState,
    'recoveryTrace': commit.trace,
    'convergence': commit.convergence,
    'journalPhase': commit.journalPhase,
    'oldManifest': manifests.oldManifest,
    'newManifest': manifests.newManifest,
    'receiptCount': commit.receiptCount,
    'changeCount': commit.changeCount,
    'projectionCount': commit.projectionCount,
    'commitLedgersExactlyOnce': commit.ledgersExactlyOnce,
    'idempotencyLookupCount': commit.idempotencyLookupCount,
    'businessReadCount': commit.businessReadCount,
    'idempotencyReused': commit.reusedReceipt,
    'revisionCount': computedCounts['revision'],
    'operationCount': computedCounts['operation'],
    'eventCount': computedCounts['event'],
    'truthCount': computedCounts['truth'],
    'roundTripLedgersUnique': roundTrip.ledgersUnique,
    'fullRoundTrip': fullRoundTrip,
    'allSixRoundTripDomainsHeld': roundTrip.allSixRoundTripDomainsHeld,
    'inventoryCount': refs.length,
    'formalCatalog': derivedCatalog,
    'unclassifiedCount': inventoryComplete ? 0 : 1,
    'roundTripStateDigest': _canonicalSha256(roundTrip.remigrated),
    'zeroDownstream': downstreamCounts,
  });
}

String _canonicalSha256(Object? value) {
  final canonical = _canonicalizeJson(value);
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

Object? _canonicalizeJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalizeJson(value[key])};
  }
  if (value is List) return value.map(_canonicalizeJson).toList();
  return value;
}

bool _deepExactEquals(Object? left, Object? right) {
  if (left is Map || right is Map) {
    if (left is! Map || right is! Map) return false;
    if (left.length != right.length ||
        !left.keys.toSet().containsAll(right.keys)) {
      return false;
    }
    return left.keys.every((key) => _deepExactEquals(left[key], right[key]));
  }
  if (left is List || right is List) {
    if (left is! List || right is! List) return false;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_deepExactEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left.runtimeType != right.runtimeType) return false;
  return left == right;
}

class _SnapshotLocal {
  const _SnapshotLocal(this.projectionIds, this.cursor, this.receiptIds);

  factory _SnapshotLocal.fromJson(Map<String, dynamic> json) => _SnapshotLocal(
        Set<String>.from(json['projectionIds'] as List),
        json['cursor'] as int,
        Set<String>.from(json['snapshotReceiptIds'] as List),
      );

  final Set<String> projectionIds;
  final int cursor;
  final Set<String> receiptIds;

  _SnapshotLocal commit(Map<String, dynamic> envelope) => _SnapshotLocal(
        Set.unmodifiable(Set<String>.from(envelope['projectionIds'] as List)),
        envelope['baseCursor'] as int,
        Set.unmodifiable({...receiptIds, envelope['id'] as String}),
      );

  Map<String, dynamic> toJson() => {
        'projectionIds': _sorted(projectionIds),
        'cursor': cursor,
        'snapshotReceiptIds': _sorted(receiptIds),
      };
}

abstract class _Rule {
  const _Rule();
  void validate(dynamic value, String path);
}

class _PinnedMigrationInputRule extends _Rule {
  const _PinnedMigrationInputRule();

  @override
  void validate(dynamic value, String path) {
    if (value is! Map<String, dynamic> ||
        value['operation'] != _Operation.migrationCorpus.label ||
        value['caseId'] is! String) {
      fail(FailureClass.inputRejected, '$path is not a migration input');
    }
  }
}

class _ObjectRule extends _Rule {
  const _ObjectRule(this.fields);
  final Map<String, _Rule> fields;

  @override
  void validate(dynamic value, String path) {
    if (value is! Map<String, dynamic>) {
      fail(FailureClass.inputRejected, '$path must be an object');
    }
    _expectExactKeys(value, fields.keys.toSet(), path);
    for (final entry in fields.entries) {
      entry.value.validate(value[entry.key], '$path.${entry.key}');
    }
  }
}

class _StringRule extends _Rule {
  const _StringRule({this.allowed});
  final Set<String>? allowed;

  @override
  void validate(dynamic value, String path) {
    if (value is! String || value.isEmpty || value.length > 512) {
      fail(FailureClass.inputRejected,
          '$path must be a bounded non-empty string');
    }
    if (allowed != null && !allowed!.contains(value)) {
      fail(FailureClass.inputRejected, '$path has an unsupported enum value');
    }
  }
}

class _BoolRule extends _Rule {
  const _BoolRule();

  @override
  void validate(dynamic value, String path) {
    if (value is! bool)
      fail(FailureClass.inputRejected, '$path must be boolean');
  }
}

class _IntRule extends _Rule {
  const _IntRule({required this.min, required this.max});
  final int min;
  final int max;

  @override
  void validate(dynamic value, String path) {
    if (value is! int || value < min || value > max) {
      fail(FailureClass.inputRejected, '$path must be an integer in range');
    }
  }
}

class _ListRule extends _Rule {
  const _ListRule(this.item,
      {required this.min, required this.max, this.unique = false});
  final _Rule item;
  final int min;
  final int max;
  final bool unique;

  @override
  void validate(dynamic value, String path) {
    if (value is! List || value.length < min || value.length > max) {
      fail(FailureClass.inputRejected, '$path has an invalid list length');
    }
    if (unique && value.toSet().length != value.length) {
      fail(FailureClass.inputRejected, '$path must contain unique items');
    }
    for (var index = 0; index < value.length; index++) {
      item.validate(value[index], '$path[$index]');
    }
  }
}

class _ExactListRule extends _Rule {
  const _ExactListRule(this.expected);
  final List<String> expected;

  @override
  void validate(dynamic value, String path) {
    if (!_listEquals(value, expected)) {
      fail(FailureClass.inputRejected, '$path does not match canonical order');
    }
  }
}

enum _Family {
  authorityMatrix('authority-matrix'),
  identityFencing('identity-fencing'),
  outboxCrash('outbox-crash'),
  cursorSnapshot('cursor-snapshot'),
  deleteRetentionMda('delete-retention-mda'),
  migrationRecovery('migration-recovery');

  const _Family(this.label);
  final String label;
}

enum _Operation {
  authorityMatrix('authority_matrix'),
  authorityPreAccept('authority_pre_accept'),
  authorityOrdinaryWrite('authority_ordinary_write'),
  identitySubmit('identity_submit'),
  identityRepair('identity_repair'),
  identityBacklog('identity_backlog'),
  identityConflict('identity_conflict'),
  identityRecover('identity_recover'),
  outboxEnqueue('outbox_enqueue'),
  outboxSubmit('outbox_submit'),
  outboxRetry('outbox_retry'),
  acceptanceCrash('acceptance_crash'),
  cursorCheck('cursor_check'),
  cursorRead('cursor_read'),
  snapshotApply('snapshot_apply'),
  subjectDelete('subject_delete'),
  backupBuild('backup_build'),
  retentionApply('retention_apply'),
  mdaInfer('mda_infer'),
  migrationCorpus('migration_corpus_case');

  const _Operation(this.label);
  final String label;
}

class _CaseSpec {
  const _CaseSpec(this.family, this.operation, this.expected, this.invariant,
      this.inputSchema);
  final _Family family;
  final _Operation operation;
  final String expected;
  final String invariant;
  final _Rule inputSchema;
}

class _Scenario {
  const _Scenario(
    this.id,
    this.input,
    this.expected,
    this.wholeInputDigest,
  );
  final String id;
  final Map<String, dynamic> input;
  final Map<String, dynamic> expected;
  final String wholeInputDigest;
}

class _SimulationResult {
  const _SimulationResult(this.actual, this.evidence);
  final String actual;
  final Map<String, Object?> evidence;
}

_SimulationResult _result(String actual, Map<String, Object?> evidence) =>
    _SimulationResult(actual, evidence);

Map<String, dynamic> _roundTrip(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

bool _listEquals(dynamic value, List<String> expected) {
  if (value is! List || value.length != expected.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (value[index] != expected[index]) return false;
  }
  return true;
}

bool _setEquals(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

void _expectExactKeys(
    Map<String, dynamic> value, Set<String> keys, String path) {
  if (!_setEquals(value.keys.toSet(), keys)) {
    fail(FailureClass.inputRejected, '$path has missing or extra fields');
  }
}

String _fingerprint(Object? value) {
  final bytes = utf8.encode(jsonEncode(value));
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

Never fail(FailureClass kind, String message) =>
    throw HarnessFailure(kind, message);

enum FailureClass { pathRejected, inputRejected, unsupported }

class HarnessFailure implements Exception {
  const HarnessFailure(this.failureClass, this.message);
  final FailureClass failureClass;
  final String message;

  @override
  String toString() => '${failureClass.name}: $message';
}

class HarnessResult {
  const HarnessResult({required this.report, required this.reportBytes});
  final Map<String, Object?> report;
  final List<int> reportBytes;
}
