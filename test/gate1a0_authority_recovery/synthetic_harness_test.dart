// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import '../../tools/gate1a0_authority_recovery/lib/synthetic_harness.dart';

const _p5ExactExpandedCrashPoints = <String>[
  'before_identity_precheck',
  'after_identity_precheck_before_idempotency',
  'after_idempotency_before_business_read',
  'before_journal_tx_a',
  'after_journal_tx_a_commit',
  'before_stage_file_write:0',
  'before_stage_file_write:1',
  'after_stage_file_write:0_before_file_fsync',
  'after_stage_file_write:1_before_file_fsync',
  'after_stage_file_fsync:0_before_directory_fsync',
  'after_stage_file_fsync:1_before_directory_fsync',
  'after_stage_directory_fsync_before_tx_b',
  'after_tx_b_commit',
  'before_rollback_copy:0',
  'before_rollback_copy:1',
  'after_rollback_copy:0_before_rollback_fsync',
  'after_rollback_copy:1_before_rollback_fsync',
  'after_rollback_fsync:0',
  'after_rollback_fsync:1',
  'before_publish_started_phase',
  'after_publish_started_phase',
  'before_file_publish:0',
  'before_file_publish:1',
  'after_file_publish:0',
  'after_file_publish:1',
  'before_object_publish:0',
  'before_object_publish:1',
  'after_object_publish:0',
  'after_object_publish:1',
  'before_files_published_phase',
  'after_files_published_phase',
  'before_activation_tx',
  'during_activation_tx_before_commit',
  'after_activation_tx_commit',
  'after_invalidation_before_rebuild',
  'before_projection_rebuild:0',
  'before_projection_rebuild:1',
  'before_projection_rebuild:2',
  'before_projection_rebuild:3',
  'during_projection_rebuild:0',
  'during_projection_rebuild:1',
  'during_projection_rebuild:2',
  'during_projection_rebuild:3',
  'after_projection_rebuild:0_before_cursor_commit',
  'after_projection_rebuild:1_before_cursor_commit',
  'after_projection_rebuild:2_before_cursor_commit',
  'after_projection_rebuild:3_before_cursor_commit',
  'after_cursor_commit_before_notification',
  'after_notification_before_response',
  'after_response_before_cleanup',
  'during_cleanup:0',
  'during_cleanup:1',
];

const _p5ExactFailurePoints = <String>[
  'stale_credential_generation',
  'identity_binding_mismatch',
  'scope_denied',
  'stale_core_instance',
  'stale_authority_epoch',
  'stale_worker_fence',
  'lineage_state_rejected',
  'duplicate_key_same_digest',
  'duplicate_key_different_digest',
  'stale_parent_revision',
  'dangling_stable_ref',
  'disk_full_during_stage',
  'disk_full_during_publish',
  'permission_denied_during_stage',
  'permission_denied_during_publish',
  'invalid_yaml',
  'source_object_hash_mismatch',
  'external_move',
  'external_delete',
  'external_third_hash_conflict',
  'activation_constraint_failure',
  'projection_rebuild_failure',
  'notification_failure',
  'rollback_manifest_corrupt',
  'staging_manifest_corrupt',
];

const _p5MigrationActionOrder = <String>[
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

const _allCanonicalOperations = <String>{
  'authority_matrix',
  'authority_pre_accept',
  'authority_ordinary_write',
  'identity_submit',
  'identity_repair',
  'identity_backlog',
  'identity_conflict',
  'identity_recover',
  'outbox_enqueue',
  'outbox_submit',
  'outbox_retry',
  'acceptance_crash',
  'cursor_check',
  'cursor_read',
  'snapshot_apply',
  'subject_delete',
  'backup_build',
  'retention_apply',
  'mda_infer',
  'migration_corpus_case',
};

const _p5RoundTripDomains = <String>{
  'cardContent',
  'userTruthSet',
  'sourceAnchor',
  'operationLog',
  'revisionHistory',
  'derivedIndex',
};

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

const _p5RoundTripDomainFields = <String>{
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

const _migrationFailureFactKeys = <String>{
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
};

void main() {
  final repositoryRoot = Directory.current.path;
  final sourceFixtureBase =
      '$repositoryRoot${Platform.pathSeparator}tools${Platform.pathSeparator}gate1a0_authority_recovery${Platform.pathSeparator}fixtures';
  final golden = '$sourceFixtureBase${Platform.pathSeparator}synthetic_v1';
  final temporaryRoots = <Directory>[];

  Map<String, dynamic> literalScenario(String id) {
    final document = jsonDecode(
      File('$golden${Platform.pathSeparator}scenarios.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    return jsonDecode(jsonEncode(
      (document['scenarios'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((scenario) => scenario['id'] == id),
    )) as Map<String, dynamic>;
  }

  Directory temporaryDirectory(String prefix) {
    final directory = Directory.systemTemp.createTempSync(prefix);
    temporaryRoots.add(directory);
    return directory;
  }

  Directory output() => temporaryDirectory('gate1a0_output_');

  SyntheticAuthorityRecoveryHarness harnessFor(String fixtureBase) =>
      SyntheticAuthorityRecoveryHarness(
        repositoryRoot: repositoryRoot,
        fixtureBase: fixtureBase,
      );

  _FixtureCopy fixtureCopy({
    void Function(Map<String, dynamic>)? mutateManifest,
    void Function(Map<String, dynamic>)? mutateScenarios,
    bool addExtraFile = false,
    bool deleteScenarios = false,
    bool corruptScenarios = false,
  }) {
    final base = temporaryDirectory('gate1a0_fixture_base_');
    final fixture = Directory('${base.path}${Platform.pathSeparator}case')
      ..createSync();
    final manifest = jsonDecode(
      File('$golden${Platform.pathSeparator}manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenarios = jsonDecode(
      File('$golden${Platform.pathSeparator}scenarios.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    mutateManifest?.call(manifest);
    mutateScenarios?.call(scenarios);
    File('${fixture.path}${Platform.pathSeparator}manifest.json')
        .writeAsStringSync(jsonEncode(manifest));
    if (!deleteScenarios) {
      File('${fixture.path}${Platform.pathSeparator}scenarios.json')
          .writeAsStringSync(
        corruptScenarios ? '{not-json' : jsonEncode(scenarios),
      );
    }
    if (addExtraFile) {
      File('${fixture.path}${Platform.pathSeparator}extra.json')
          .writeAsStringSync('{}');
    }
    return _FixtureCopy(base.path, fixture.path);
  }

  Map<String, dynamic> caseById(
    Map<String, dynamic> document,
    String id,
  ) =>
      (document['scenarios'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((item) => item['id'] == id);

  Map<String, dynamic> reportCase(HarnessResult result, String id) =>
      (result.report['cases'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((item) => item['id'] == id);

  tearDown(() {
    for (final directory in temporaryRoots.reversed) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
    temporaryRoots.clear();
  });

  test(
      'runs the exact 202-case canonical registry without production migration',
      () {
    final beforeManifest = File(
      '$golden${Platform.pathSeparator}manifest.json',
    ).readAsBytesSync();
    final beforeScenarios = File(
      '$golden${Platform.pathSeparator}scenarios.json',
    ).readAsBytesSync();
    final result = harnessFor(sourceFixtureBase).run(
      fixtureRoot: golden,
      outputRoot: output().path,
    );
    final cases = (result.report['cases'] as List).cast<Map<String, dynamic>>();

    expect(result.report['totalCases'], 202);
    expect(result.report['passedCases'], 202);
    expect(result.report['migrationExecuted'], false);
    expect(result.report['migrationSimulated'], true);
    expect(
      result.report['contractVersion'],
      SyntheticAuthorityRecoveryHarness.contractVersion,
    );
    expect(
      result.report['fixtureDigest'],
      'e6007a58309fa36b7ef5e41da223251a2b9fb16c249a2ad084cd459b48fdc9a7',
    );
    expect(result.report['scenarioSha'], hasLength(64));
    expect((result.report['caseInputDigests'] as Map), hasLength(202));
    expect(result.report['fixtureDimensions'], {
      'files': 2,
      'objects': 2,
      'rollbackCopies': 2,
      'projections': 4,
      'cleanupItems': 2,
    });
    expect(result.report['synthetic'], true);
    expect(result.report['mode'], 'validate/simulate-only');
    expect(result.report['allInvariantsHeld'], true);
    expect(result.report['caseCounts'], {
      'total': 202,
      'passed': 202,
      'failed': 0,
      'invariantHeld': 202,
    });
    expect(result.report['familyCounts'], {
      'authority-matrix': 13,
      'cursor-snapshot': 8,
      'delete-retention-mda': 4,
      'identity-fencing': 11,
      'migration-recovery': 146,
      'outbox-crash': 20,
    });
    expect(result.report['classificationCounts'], {
      'blocked': 16,
      'controlled_extension': 38,
      'degraded_preserved': 5,
      'deterministic': 87,
      'not_applicable': 56,
    });
    expect(
      result.report['exactExpandedCrashPoints'],
      _p5ExactExpandedCrashPoints,
    );
    expect(result.report['exactFailurePoints'], _p5ExactFailurePoints);
    final machineEvidence = result.report['stateMachineEvidence'] as Map;
    expect(machineEvidence['expandedCrashPointCaseCount'], 52);
    expect(machineEvidence['uniqueExpandedCrashPointCount'], 52);
    expect(machineEvidence['failurePointCaseCount'], 26);
    expect(machineEvidence['uniqueFailurePointCount'], 25);
    expect(cases.map((item) => item['id']).toSet(),
        SyntheticAuthorityRecoveryHarness.canonicalCaseIds);
    expect(cases.every((item) => item['result'] == 'pass'), true);
    expect(cases.every((item) => item['invariantHeld'] == true), true);
    expect(
      cases.every((item) {
        final invariants = item['invariantResults'] as Map;
        return invariants.keys.toSet().containsAll({
              'actualMatchesLiteralExpected',
              'contractInvariantHeld',
            }) &&
            invariants.values.every((value) => value == true) &&
            (item['wholeInputDigest'] as String).length == 64;
      }),
      true,
    );
    final literalDocument = jsonDecode(utf8.decode(beforeScenarios)) as Map;
    final literals = (literalDocument['scenarios'] as List).cast<Map>();
    expect(
      literals.every((scenario) =>
          scenario.keys.toSet().containsAll({'input', 'expected'}) &&
          scenario['input'] is Map &&
          scenario['expected'] is Map),
      true,
    );
    final migrationLiterals = literals.where(
      (scenario) =>
          (scenario['input'] as Map)['operation'] == 'migration_corpus_case',
    );
    expect(
      migrationLiterals.every((scenario) {
        final input = scenario['input'] as Map;
        return !input.containsKey('expectedTarget') &&
            !input.containsKey('expectedRoundTrip') &&
            !(input['transaction'] as Map).keys.any(
                  (key) => key.toString().startsWith('expected'),
                );
      }),
      true,
    );
    expect(
      cases.map((item) => item['family']).toSet(),
      {
        'authority-matrix',
        'identity-fencing',
        'outbox-crash',
        'cursor-snapshot',
        'delete-retention-mda',
        'migration-recovery',
      },
    );
    expect(
      File('$golden${Platform.pathSeparator}manifest.json').readAsBytesSync(),
      beforeManifest,
    );
    expect(
      File('$golden${Platform.pathSeparator}scenarios.json').readAsBytesSync(),
      beforeScenarios,
    );
  });

  test('all 20 operations derive contract invariants from actual evidence', () {
    final result = harnessFor(sourceFixtureBase).run(
      fixtureRoot: golden,
      outputRoot: output().path,
    );
    final cases = (result.report['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.map((item) => item['operation']).toSet(),
        _allCanonicalOperations);
    final violations = <String, void Function(Map<String, Object?>)>{
      'authority-card': (evidence) => evidence['acceptedWriterCount'] = 0,
      'authority-capture': (evidence) => evidence['downstreamObjectCount'] = 1,
      'activity-no-auto-user-truth': (evidence) =>
          evidence['userTruthMutations'] = 1,
      'active-core-accept': (evidence) =>
          evidence['acceptanceMutationCount'] = 0,
      'repair-one-active-generation': (evidence) =>
          evidence['activeGenerations'] = 2,
      'backlog-needs-resolution': (evidence) =>
          evidence['acceptanceMutationCount'] = 1,
      'same-key-different-digest': (evidence) =>
          evidence['ledgerOverwritten'] = true,
      'missing-recovery-lineage': (evidence) =>
          evidence['epochAdvanced'] = true,
      'outbox-oversize': (evidence) =>
          evidence['existingPendingPreserved'] = false,
      'outbox-protocol': (evidence) =>
          evidence['problemResultPersisted'] = false,
      'lost-accepted-response-current-identity': (evidence) =>
          evidence['duplicateEventCount'] = 1,
      'crash-A': (evidence) => evidence['eventCount'] = 2,
      'cursor-domain-isolation': (evidence) =>
          evidence['cursorAdvanced'] = true,
      'activity-token-reads-chat': (evidence) =>
          evidence['privateFeedRead'] = true,
      'authenticated-snapshot': (evidence) => evidence['projectionCount'] = 0,
      'revoke-delete-isolation': (evidence) => evidence['onlineVisible'] = true,
      'backup-retention': (evidence) =>
          evidence['deletedSubjectExcluded'] = false,
      'mda-retention': (evidence) => evidence['historicalHeartRateRows'] = 1,
      'mda-no-inference': (evidence) =>
          evidence['humanStatesProduced'] = ['invented'],
    };
    expect(
      violations.keys.map((id) => reportCase(result, id)['operation']).toSet(),
      _allCanonicalOperations.difference({'migration_corpus_case'}),
    );
    for (final entry in violations.entries) {
      final canonical = reportCase(result, entry.key);
      expect(
        (canonical['invariantResults'] as Map)['actualMatchesLiteralExpected'],
        true,
        reason: entry.key,
      );
      final evidence = Map<String, Object?>.from(
        jsonDecode(jsonEncode(canonical['evidence'])) as Map,
      );
      entry.value(evidence);
      expect(
        SyntheticAuthorityRecoveryHarness.evaluateContractForTest(
          entry.key,
          canonical['actual'] as String,
          evidence,
        ),
        false,
        reason: entry.key,
      );
    }
  });

  test('A-F execute real crash restart replay with no partial-state invariant',
      () {
    final result = harnessFor(sourceFixtureBase).run(
      fixtureRoot: golden,
      outputRoot: output().path,
    );
    final evidence = result.report['stateMachineEvidence'] as Map;
    expect(evidence['acceptanceCrashPhases'], ['A', 'B', 'C', 'D', 'E', 'F']);
    for (final phase in const ['A', 'B', 'C', 'D', 'E', 'F']) {
      final item = reportCase(result, 'crash-$phase');
      final state = item['evidence'] as Map;
      expect(item['operation'], 'acceptance_crash');
      expect(item['actual'], 'replay_converged');
      expect(state['crashPhaseExecuted'], phase);
      expect(state['trace'], contains('crash@$phase'));
      expect(state['trace'], contains('restart@$phase'));
      expect(state['trace'], contains('replay-complete'));
      expect(state['ghostAccepted'], false);
      expect(state['receiptOnly'], false);
      expect(state['outboxMissingWithoutResult'], false);
      expect(state['cursorAheadOfProjection'], false);
      expect(state['duplicateEvent'], false);
      expect(state['eventCount'], 1);
      expect(state['receiptCount'], 1);
      expect(state['changeCount'], 1);
      expect(state['ledgerCount'], 1);
    }
  });

  test('snapshot and migration state machines derive atomic convergence', () {
    final result = harnessFor(sourceFixtureBase).run(
      fixtureRoot: golden,
      outputRoot: output().path,
    );
    expect(reportCase(result, 'snapshot-interrupted')['actual'],
        'cursor_unchanged');
    expect(reportCase(result, 'snapshot-commit-restart')['actual'],
        'snapshot_atomically_applied');
    final exactCrashCases = (result.report['cases'] as List)
        .cast<Map<String, dynamic>>()
        .where((item) {
      final evidence = item['evidence'] as Map;
      return evidence['exactExpandedCrashPointExecuted'] != null &&
          evidence['exactFailurePointExecuted'] == null;
    }).toList();
    expect(exactCrashCases, hasLength(52));
    expect(
      exactCrashCases
          .map((item) =>
              (item['evidence'] as Map)['exactExpandedCrashPointExecuted'])
          .toSet(),
      _p5ExactExpandedCrashPoints.toSet(),
    );
    for (final item in exactCrashCases) {
      final evidence = item['evidence'] as Map;
      expect(item['actual'], 'migration_case_verified');
      expect(evidence['restartCount'], 1);
      expect(evidence['serializedBeforeRestartDigest'], isNot('none'));
      expect(evidence['recoveryTrace'], contains(startsWith('crash:')));
      expect(evidence['convergence'], anyOf('old', 'new'));
      expect(evidence['oldManifest'], hasLength(4));
      expect(evidence['newManifest'], hasLength(4));
    }
    final inventory = reportCase(
      result,
      'migration-formal-32-object-inventory',
    )['evidence'] as Map;
    expect(inventory['inventoryCount'], 32);
    expect(
      reportCase(result, 'migration-roundtrip-full')['actual'],
      'migration_case_verified',
    );

    for (final id in const [
      'old-snapshot',
      'corrupt-snapshot',
      'snapshot-interrupted',
    ]) {
      final canonical = reportCase(result, id);
      final evidence =
          jsonDecode(jsonEncode(canonical['evidence'])) as Map<String, dynamic>;
      expect(evidence['cursor'], evidence['originalCursor'], reason: id);
      expect(
        evidence['stateDigest'],
        evidence['originalStateDigest'],
        reason: id,
      );
      final advancedCursor =
          jsonDecode(jsonEncode(evidence)) as Map<String, dynamic>;
      advancedCursor['cursor'] = (advancedCursor['originalCursor'] as int) + 1;
      expect(
        SyntheticAuthorityRecoveryHarness.evaluateContractForTest(
          id,
          canonical['actual'] as String,
          advancedCursor,
        ),
        false,
        reason: '$id cursor advanced',
      );
      final rewrittenState =
          jsonDecode(jsonEncode(evidence)) as Map<String, dynamic>;
      rewrittenState['stateDigest'] = 'rewritten-state-digest';
      expect(
        SyntheticAuthorityRecoveryHarness.evaluateContractForTest(
          id,
          canonical['actual'] as String,
          rewrittenState,
        ),
        false,
        reason: '$id state rewritten',
      );
    }
  });

  test('report is byte deterministic, redacted, and consumes raw state', () {
    final harness = harnessFor(sourceFixtureBase);
    final first = harness.run(fixtureRoot: golden, outputRoot: output().path);
    final second = harness.run(fixtureRoot: golden, outputRoot: output().path);
    expect(first.reportBytes, second.reportBytes);

    final text = utf8.decode(first.reportBytes);
    for (final forbidden in const [
      'payload-A',
      'digest-A',
      'validationOrder',
      'record_organizer',
      '新路径写入',
      'legacy-bytes:',
      'credentialValue',
      'leaseToken',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }

    final canonical = literalScenario('richtext-paragraph');
    final originalInput =
        jsonDecode(jsonEncode(canonical['input'])) as Map<String, dynamic>;
    final changedInput =
        jsonDecode(jsonEncode(originalInput)) as Map<String, dynamic>;
    (changedInput['legacy'] as Map<String, dynamic>)['bytes'] =
        'changed raw legacy bytes';
    final original =
        SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
            'richtext-paragraph', originalInput);
    final changed =
        SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
            'richtext-paragraph', changedInput);
    expect(
      (original['evidence'] as Map)['targetDigest'],
      isNot((changed['evidence'] as Map)['targetDigest']),
    );
    expect(changed['actual'], 'migration_case_contract_violation');
  });

  test('migration outcomes are derived from raw values, not feature labels',
      () {
    Map<String, dynamic> canonicalInput(String id) =>
        literalScenario(id)['input'] as Map<String, dynamic>;

    Map<String, Object?> simulate(String id, Map<String, dynamic> input) =>
        SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
          id,
          input,
        );

    final inputOnlyDiagnostic = simulate(
      'richtext-paragraph',
      canonicalInput('richtext-paragraph'),
    );
    expect(inputOnlyDiagnostic['computedActualForComparator'], isA<Map>());
    expect(
      (inputOnlyDiagnostic['computedActualForComparator'] as Map).keys.toSet(),
      {'result', 'target', 'roundTrip', 'commit'},
    );
    expect(
      (inputOnlyDiagnostic['invariantResults'] as Map).keys.toSet(),
      {'contractInvariantHeld'},
    );

    void expectRawChange(
      String id,
      void Function(Map<String, dynamic> details) mutate, {
      String? classification,
      String? outcome,
    }) {
      final originalInput = canonicalInput(id);
      final changedInput = canonicalInput(id);
      final original = simulate(id, originalInput);
      final details = (changedInput['legacy']
          as Map<String, dynamic>)['details'] as Map<String, dynamic>;
      mutate(details);
      final changed = simulate(id, changedInput);
      final originalEvidence = original['evidence'] as Map;
      final changedEvidence = changed['evidence'] as Map;
      expect(changed['actual'], 'migration_case_contract_violation',
          reason: id);
      expect(
        [
          changedEvidence['classification'],
          changedEvidence['derivedOutcome'],
          changedEvidence['conversionOutputDigest'],
        ],
        isNot([
          originalEvidence['classification'],
          originalEvidence['derivedOutcome'],
          originalEvidence['conversionOutputDigest'],
        ]),
        reason: id,
      );
      if (classification != null) {
        expect(changedEvidence['classification'], classification, reason: id);
      }
      if (outcome != null) {
        expect(changedEvidence['derivedOutcome'], outcome, reason: id);
      }
    }

    expectRawChange(
      'richtext-nested-marks',
      (details) => (details['marks'] as List).cast<Map>().first['end'] = 99,
      classification: 'blocked',
      outcome: 'invalid_utf16_mark_range',
    );
    expectRawChange(
      'richtext-unknown-mark',
      (details) =>
          (details['marks'] as List).cast<Map>().first['type'] = 'bold',
      classification: 'deterministic',
      outcome: 'richtext_converted',
    );
    expectRawChange(
      'richtext-utf16-fingerprint',
      (details) => details['utf16Fingerprint'] = 'wrong-fingerprint',
      classification: 'blocked',
      outcome: 'utf16_fingerprint_mismatch',
    );
    expectRawChange(
      'asset-image',
      (details) => (details['asset'] as Map)['actualHash'] = 'wrong-hash',
      classification: 'blocked',
      outcome: 'asset_hash_mismatch',
    );
    expectRawChange(
      'richtext-ime-defer',
      (details) => details['imeCommitted'] = true,
      classification: 'deterministic',
      outcome: 'richtext_converted',
    );
    expectRawChange(
      'capture-same-digest',
      (details) => details['incomingDigest'] = 'different-digest',
      classification: 'blocked',
      outcome: 'idempotency_conflict',
    );
    expectRawChange(
      'capture-cancel-barrier',
      (details) => details['cancelled'] = false,
      outcome: 'duplicate_identity_reused',
    );
    expectRawChange(
      'import-parser-late',
      (details) => details['parserCompleted'] = false,
      classification: 'deterministic',
      outcome: 'cancel_barrier_applied',
    );
    expectRawChange(
      'task-promotion-authorized',
      (details) => details['promotionAuthorization'] = false,
      classification: 'blocked',
      outcome: 'partial_promotion_zero_downstream',
    );
    expectRawChange(
      'anchor-exact',
      (details) => details['matchCount'] = 2,
      classification: 'blocked',
      outcome: 'anchor_ambiguous',
    );
    expectRawChange(
      'anchor-exact',
      (details) =>
          (details['selector'] as Map<String, dynamic>)['exact'] = 'Other',
      classification: 'blocked',
      outcome: 'anchor_selector_or_fingerprint_invalid',
    );
    expectRawChange(
      'migration-body-conflict',
      (details) => details['targetBody'] = details['legacyBody'],
      classification: 'deterministic',
      outcome: 'no_truth_promotion',
    );
    expectRawChange(
      'migration-explicit-truth-provenance',
      (details) => details['truthAuthorization'] = false,
      classification: 'blocked',
      outcome: 'truth_authorization_or_provenance_missing',
    );
    expectRawChange(
      'evidence-attachment-no-claim',
      (details) => details['claimAuthorization'] = true,
      classification: 'deterministic',
      outcome: 'authorized_claim_recorded',
    );
    expectRawChange(
      'richtext-link-https',
      (details) => (details['marks'] as List).cast<Map>().first['href'] =
          'javascript:alert(1)',
      classification: 'blocked',
      outcome: 'unsafe_or_missing_link_href',
    );
    expectRawChange(
      'richtext-link-card',
      (details) => (details['marks'] as List).cast<Map>().first.remove('href'),
      classification: 'blocked',
      outcome: 'unsafe_or_missing_link_href',
    );
    expectRawChange(
      'richtext-strike',
      (details) =>
          (details['marks'] as List).cast<Map>().first['unsafeAttr'] = true,
      classification: 'blocked',
      outcome: 'unsupported_mark_attribute',
    );
    expectRawChange(
      'richtext-list',
      (details) => (details['blocks'] as List).cast<Map>().first['depth'] = 9,
      classification: 'blocked',
      outcome: 'invalid_list_depth_or_block_id',
    );
    expectRawChange(
      'richtext-ordered-list',
      (details) =>
          (details['blocks'] as List).cast<Map>().first['listStyle'] = 'roman',
      classification: 'blocked',
      outcome: 'unknown_list_attribute',
    );
    expectRawChange(
      'richtext-paragraph',
      (details) =>
          (details['blocks'] as List).cast<Map>().first['kind'] = 'future',
      classification: 'blocked',
      outcome: 'unknown_block_kind',
    );
    expectRawChange(
      'richtext-paragraph',
      (details) => details['rawSchemaVersion'] = 2,
      classification: 'blocked',
      outcome: 'unsupported_richtext_schema',
    );
    expectRawChange(
      'richtext-code',
      (details) =>
          (details['blocks'] as List).cast<Map>().first['language'] = '````',
      classification: 'blocked',
      outcome: 'invalid_code_metadata',
    );
    expectRawChange(
      'asset-image',
      (details) => (details['asset'] as Map)['mime'] = '',
      classification: 'blocked',
      outcome: 'asset_mime_missing',
    );
    expectRawChange(
      'asset-image',
      (details) => (details['asset'] as Map)['embeddedBytesLength'] = 1,
      classification: 'blocked',
      outcome: 'embedded_asset_bytes_forbidden',
    );
    expectRawChange(
      'anchor-exact',
      (details) => details['sourceVersionId'] = '',
      classification: 'blocked',
      outcome: 'anchor_selector_or_fingerprint_invalid',
    );
    expectRawChange(
      'capture-same-digest',
      (details) => details['stableIdentity'] = '',
      classification: 'blocked',
      outcome: 'intake_stable_identity_missing',
    );
    expectRawChange(
      'capture-same-digest',
      (details) => details['dedupeKey'] = '',
      classification: 'blocked',
      outcome: 'intake_dedupe_key_missing',
    );
    expectRawChange(
      'commit-failure-external-third-hash-conflict-file-0',
      (details) {
        final facts = details['failureFacts'] as Map;
        facts['observedHash'] = facts['oldHash'];
      },
      classification: 'deterministic',
      outcome: 'journal_prepared',
    );
    expectRawChange(
      'commit-failure-invalid-yaml',
      (details) => (details['failureFacts'] as Map)['yamlValid'] = true,
      classification: 'deterministic',
      outcome: 'journal_prepared',
    );

    final codeBackticks = simulate(
      'richtext-code-backticks',
      canonicalInput('richtext-code-backticks'),
    )['evidence'] as Map;
    expect(codeBackticks['classification'], 'deterministic');
    expect(codeBackticks['markdownFenceLength'], 4);
    final longerFenceInput = canonicalInput('richtext-code-backticks');
    final longerFenceDetails = (longerFenceInput['legacy']
        as Map<String, dynamic>)['details'] as Map<String, dynamic>;
    (longerFenceDetails['blocks'] as List).cast<Map>().first['text'] =
        'content with ````` five ticks';
    longerFenceDetails['text'] = 'content with ````` five ticks';
    longerFenceDetails['utf16Fingerprint'] = sha256
        .convert(
            utf8.encode(jsonEncode('content with ````` five ticks'.codeUnits)))
        .toString();
    final longerFence = simulate('richtext-code-backticks', longerFenceInput);
    expect(longerFence['actual'], 'migration_case_contract_violation');
    expect((longerFence['evidence'] as Map)['markdownFenceLength'], 6);

    final featureInput = canonicalInput('richtext-paragraph');
    (featureInput['legacy'] as Map<String, dynamic>)['feature'] =
        'mark_unknown';
    final canonicalParagraph =
        simulate('richtext-paragraph', canonicalInput('richtext-paragraph'));
    final featureOnly = simulate('richtext-paragraph', featureInput);
    expect(featureOnly['actual'], 'migration_case_verified');
    expect(
      (featureOnly['evidence'] as Map)['classification'],
      (canonicalParagraph['evidence'] as Map)['classification'],
    );
    expect(
      (featureOnly['evidence'] as Map)['derivedOutcome'],
      (canonicalParagraph['evidence'] as Map)['derivedOutcome'],
    );
    expect(
      (featureOnly['evidence'] as Map)['conversionOutputDigest'],
      (canonicalParagraph['evidence'] as Map)['conversionOutputDigest'],
    );

    final nestedMarks = simulate(
      'richtext-nested-marks',
      canonicalInput('richtext-nested-marks'),
    );
    expect(
      (nestedMarks['targetForTest'] as Map)['markdownFragment'],
      '**_Alpha_ beta**',
    );
    final rawHtml = simulate(
      'richtext-raw',
      canonicalInput('richtext-raw'),
    );
    final capsules =
        ((rawHtml['targetForTest'] as Map)['preservationCapsules'] as List)
            .cast<Map>();
    const nonUtf8Bytes = <int>[0xff, 0xfe, 0x3c, 0x00, 0x41, 0x80];
    final rawSha = sha256.convert(nonUtf8Bytes).toString();
    expect(
      (rawHtml['targetForTest'] as Map)['markdownFragment'],
      '<legacy-raw block_id="block-ae9b3439ef69" '
      'digest="$rawSha" />',
    );
    expect(capsules, hasLength(1));
    expect(capsules.single['encoding'], 'base64');
    expect(capsules.single['rawBytesBase64'], base64Encode(nonUtf8Bytes));
    expect(capsules.single['byteLength'], nonUtf8Bytes.length);
    expect(capsules.single['rawSha256'], rawSha);
    expect(capsules.single['restoredBytewiseEqual'], true);
    expect(base64Decode(capsules.single['rawBytesBase64'] as String),
        nonUtf8Bytes);

    for (final control in <MapEntry<String, void Function(Map)>>[
      MapEntry('raw_bytes_base64_invalid',
          (payload) => payload['rawBytesBase64'] = '*not-base64*'),
      MapEntry('raw_bytes_length_mismatch',
          (payload) => payload['byteLength'] = nonUtf8Bytes.length + 1),
      MapEntry('raw_bytes_hash_mismatch',
          (payload) => payload['rawSha256'] = List.filled(64, '0').join()),
    ]) {
      final invalid = canonicalInput('richtext-raw');
      final details = (invalid['legacy'] as Map)['details'] as Map;
      control.value(details['rawPayload'] as Map);
      final actual = simulate('richtext-raw', invalid);
      expect(actual['actual'], 'migration_case_contract_violation');
      expect((actual['evidence'] as Map)['classification'], 'blocked');
      expect((actual['evidence'] as Map)['derivedOutcome'], control.key);
    }

    final partialLinkInput = canonicalInput('richtext-link-https');
    final partialLinkDetails = (partialLinkInput['legacy']
        as Map<String, dynamic>)['details'] as Map<String, dynamic>;
    (partialLinkDetails['marks'] as List).cast<Map>().single['end'] = 5;
    final partialLink = simulate('richtext-link-https', partialLinkInput);
    expect(partialLink['actual'], 'migration_case_contract_violation');
    expect(
      (partialLink['targetForTest'] as Map)['markdownFragment'],
      '[Alpha](https://example.invalid/card) beta',
    );

    final richTextDigests = const [
      'richtext-paragraph',
      'richtext-heading',
      'richtext-list',
      'richtext-ordered-list',
      'richtext-quote',
      'richtext-code',
      'richtext-code-backticks',
      'richtext-empty',
      'richtext-empty-list',
      'richtext-empty-quote',
      'richtext-nested',
      'richtext-nested-quote',
      'richtext-footnote',
      'richtext-gfm-table',
      'richtext-raw',
      'richtext-reference-card',
      'richtext-reference-source',
      'richtext-reference-anchor',
      'richtext-reference-evidence',
      'richtext-nested-marks',
      'richtext-crossing-marks',
      'richtext-underline',
      'richtext-strike',
      'richtext-inline-code',
      'richtext-link-https',
      'richtext-link-card',
      'richtext-combining-sequence',
    ].map((id) {
      final evidence = simulate(id, canonicalInput(id))['evidence'] as Map;
      return evidence['conversionOutputDigest'];
    }).toSet();
    expect(richTextDigests, hasLength(27));
  });

  test('fixture cannot synchronously redefine input and old expected', () {
    final copy = fixtureCopy(mutateScenarios: (document) {
      final item = caseById(document, 'active-core-accept');
      item['expected'] = {'result': 'rejected_precheck'};
      item['input']['operation'] = 'future_accept';
    });
    expect(
      () => harnessFor(copy.base).run(
        fixtureRoot: copy.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.inputRejected),
    );

    final oldExpectedOnly = fixtureCopy(mutateScenarios: (document) {
      caseById(document, 'active-core-accept')['expected'] = {
        'result': 'accepted',
        'extra': true,
      };
    });
    expect(
      () => harnessFor(oldExpectedOnly.base).run(
        fixtureRoot: oldExpectedOnly.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.inputRejected),
    );
  });

  test('literal oracle rejects synchronized migration input and expected', () {
    final copy = fixtureCopy(mutateScenarios: (document) {
      final item = caseById(document, 'richtext-paragraph');
      item['input']['legacy']['bytes'] = 'coordinated tampered bytes';
      final legacy = item['input']['legacy'] as Map<String, dynamic>;
      legacy['headHash'] = _canonicalDigestForTest({
        'bytes': legacy['bytes'],
        'details': legacy['details'],
        'refs': legacy['refs'],
      });
      final diagnostic =
          SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
        'richtext-paragraph',
        Map<String, dynamic>.from(item['input'] as Map),
      );
      item['expected'] = diagnostic['computedActualForComparator'];
    });
    final scenarioFile =
        File('${copy.fixture}${Platform.pathSeparator}scenarios.json');
    final scenarioBytes = scenarioFile.readAsBytesSync();
    final scenarioDocument =
        jsonDecode(utf8.decode(scenarioBytes)) as Map<String, dynamic>;
    final tampered = caseById(scenarioDocument, 'richtext-paragraph');
    final manifestFile =
        File('${copy.fixture}${Platform.pathSeparator}manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    manifest['scenarioSha'] = sha256.convert(scenarioBytes).toString();
    (manifest['caseInputDigests']
            as Map<String, dynamic>)['richtext-paragraph'] =
        _canonicalDigestForTest(tampered['input']);
    manifestFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    expect(
      () => harnessFor(copy.base).run(
        fixtureRoot: copy.fixture,
        outputRoot: output().path,
      ),
      _failureMessage('fixture bytes do not match pinned digest'),
    );
  });

  test('expected-only tamper reaches comparator without changing input digest',
      () {
    final canonical = literalScenario('richtext-paragraph');
    final diagnostic =
        SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
      'richtext-paragraph',
      canonical['input'] as Map<String, dynamic>,
    );
    final tamperedLiteral =
        jsonDecode(jsonEncode(canonical['expected'])) as Map<String, dynamic>;
    tamperedLiteral['target']['headHash'] = 'literal-only-tamper';
    final comparator =
        SyntheticAuthorityRecoveryHarness.compareComputedMigrationForTest(
      diagnostic['computedActualForComparator'] as Map<String, dynamic>,
      tamperedLiteral,
      contractInvariantHeld:
          (diagnostic['invariantResults'] as Map)['contractInvariantHeld'] ==
              true,
    );
    expect(comparator['actualMatchesLiteralExpected'], false);
    expect(comparator['contractInvariantHeld'], true);
    expect(comparator.values.every((value) => value), false);

    final copy = fixtureCopy(mutateScenarios: (document) {
      caseById(document, 'richtext-paragraph')['expected']['target']
          ['headHash'] = 'literal-only-tamper';
    });
    final scenarioFile =
        File('${copy.fixture}${Platform.pathSeparator}scenarios.json');
    final scenarioBytes = scenarioFile.readAsBytesSync();
    final manifestFile =
        File('${copy.fixture}${Platform.pathSeparator}manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final inputDigestBefore =
        (manifest['caseInputDigests'] as Map)['richtext-paragraph'];
    manifest['scenarioSha'] = sha256.convert(scenarioBytes).toString();
    manifestFile.writeAsStringSync(jsonEncode(manifest));
    expect(
      (manifest['caseInputDigests'] as Map)['richtext-paragraph'],
      inputDigestBefore,
    );
    expect(
      () => harnessFor(copy.base).run(
        fixtureRoot: copy.fixture,
        outputRoot: output().path,
      ),
      _failureMessage(
        'literal expected does not match independently simulated actual',
      ),
    );
  });

  test('missing and extra literal expected fields fail closed', () {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (document) =>
          caseById(document, 'active-core-accept')['expected'].remove('result'),
      (document) => caseById(document, 'richtext-paragraph')['expected']
          ['unexpected'] = true,
    ]) {
      final copy = fixtureCopy(mutateScenarios: mutation);
      expect(
        () => harnessFor(copy.base).run(
          fixtureRoot: copy.fixture,
          outputRoot: output().path,
        ),
        _failure(FailureClass.inputRejected),
      );
    }
  });

  test('unknown operation and extra missing type enum fields fail closed', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (document) => caseById(document, 'active-core-accept')['input']
          ['operation'] = 'future_accept',
      (document) =>
          caseById(document, 'active-core-accept')['input']['extra'] = true,
      (document) =>
          (caseById(document, 'crash-A')['input'] as Map).remove('event'),
      (document) => caseById(document, 'crash-A')['input']['phase'] = 1,
      (document) => caseById(document, 'active-core-accept')['input']
          ['generation'] = 'future',
    ];
    for (final mutate in mutations) {
      final copy = fixtureCopy(mutateScenarios: mutate);
      expect(
        () => harnessFor(copy.base).run(
          fixtureRoot: copy.fixture,
          outputRoot: output().path,
        ),
        _failure(FailureClass.inputRejected),
      );
    }
  });

  test('ID family phase mismatch and empty signals fail closed', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (document) => caseById(document, 'crash-A')['family'] = 'cursor-snapshot',
      (document) => caseById(document, 'crash-A')['input']['phase'] = 'B',
      (document) => caseById(document, 'mda-no-inference')['input']
          ['signals'] = <String>[],
      (document) => (document['scenarios'] as List).removeLast(),
    ];
    for (final mutate in mutations) {
      final copy = fixtureCopy(mutateScenarios: mutate);
      expect(
        () => harnessFor(copy.base).run(
          fixtureRoot: copy.fixture,
          outputRoot: output().path,
        ),
        _failure(FailureClass.inputRejected),
      );
    }
  });

  test('inconsistent raw state changes computed actual and cannot stay green',
      () {
    final input = literalScenario('crash-A')['input'] as Map<String, dynamic>;
    final initial = input['initial'] as Map<String, dynamic>;
    initial['coreEventIds'] = ['event-A', 'event-A'];
    initial['receiptIds'] = ['event-A', 'event-A'];
    initial['changeIds'] = ['event-A', 'event-A'];
    initial['ledgerEntries'] = [
      {'key': 'key-A', 'digest': 'digest-A'},
      {'key': 'key-A', 'digest': 'digest-A'},
    ];
    final result =
        SyntheticAuthorityRecoveryHarness.simulateAcceptanceRawForTest(input);
    expect(result['actual'], 'state_invariant_violation');
    final evidence = result['evidence'] as Map;
    expect(evidence['duplicateEvent'], true);
    expect(evidence['exactlyOnceViolation'], true);
  });

  test('precheck and digest conflict reject before Core mutation', () {
    final result = harnessFor(sourceFixtureBase).run(
      fixtureRoot: golden,
      outputRoot: output().path,
    );
    for (final id in const [
      'crash-precheck-revoked-credential',
      'crash-precheck-wrong-binding',
      'crash-precheck-denied-scope',
      'crash-precheck-superseded-core',
      'crash-precheck-old-epoch',
      'crash-precheck-stale-fence',
      'crash-precheck-invalid-lineage',
    ]) {
      final item = reportCase(result, id);
      final evidence = item['evidence'] as Map;
      expect(item['actual'], 'rejected_precheck_zero_mutation');
      expect(evidence['precheckPassed'], false);
      expect(evidence['eventCount'], 0);
      expect(evidence['receiptCount'], 0);
      expect(evidence['changeCount'], 0);
      expect(evidence['exactlyOnceViolation'], false);
      final trace = List<String>.from(evidence['trace'] as List);
      expect(trace.any((entry) => entry.contains('idempotency:lookup')), false);
      expect(trace.any((entry) => entry.contains('resource:')), false);
    }
    final conflict = reportCase(
      result,
      'crash-idempotency-digest-conflict',
    );
    final evidence = conflict['evidence'] as Map;
    expect(conflict['actual'], 'idempotency_conflict_zero_mutation');
    expect(evidence['eventCount'], 0);
    expect(evidence['receiptCount'], 0);
    expect(evidence['changeCount'], 0);
    expect(evidence['exactlyOnceViolation'], false);
    final conflictTrace = List<String>.from(evidence['trace'] as List);
    expect(
      conflictTrace.any((entry) => entry.contains('idempotency')),
      true,
    );
    expect(conflictTrace.any((entry) => entry.contains('resource:')), false);
  });

  test('P5 migration minimum corpus is present and derives invariants', () {
    final result = harnessFor(sourceFixtureBase).run(
      fixtureRoot: golden,
      outputRoot: output().path,
    );
    const required = {
      'migration-ordinary-card-no-truth',
      'migration-explicit-truth-provenance',
      'migration-body-conflict',
      'migration-title-conflict',
      'migration-id-conflict',
      'richtext-paragraph',
      'richtext-heading',
      'richtext-list',
      'richtext-ordered-list',
      'richtext-quote',
      'richtext-code',
      'richtext-code-backticks',
      'richtext-empty',
      'richtext-empty-list',
      'richtext-empty-quote',
      'richtext-nested',
      'richtext-nested-quote',
      'richtext-footnote',
      'richtext-gfm-table',
      'richtext-raw',
      'richtext-reference-card',
      'richtext-reference-source',
      'richtext-reference-anchor',
      'richtext-reference-evidence',
      'richtext-nested-marks',
      'richtext-crossing-marks',
      'richtext-underline',
      'richtext-strike',
      'richtext-inline-code',
      'richtext-link-https',
      'richtext-link-card',
      'richtext-invalid-mark',
      'richtext-unknown-mark',
      'richtext-utf16-fingerprint',
      'asset-image',
      'asset-video',
      'asset-attachment',
      'asset-missing',
      'asset-hash-mismatch',
      'asset-temp-path',
      'asset-base64',
      'richtext-ime-defer',
      'richtext-cjk-emoji-variation',
      'richtext-combining-sequence',
      'history-parent',
      'editor-cache-no-revision',
      'anchor-exact',
      'anchor-ambiguous',
      'anchor-orphan',
      'evidence-attachment-no-claim',
      'task-promotion-authorized',
      'task-promotion-partial-failure',
      'capture-same-digest',
      'capture-different-digest',
      'capture-cancel-barrier',
      'capture-restart',
      'import-same-digest',
      'import-different-digest',
      'import-cancel-barrier',
      'import-parser-late',
      'import-restart',
      'link-same-digest',
      'link-different-digest',
      'link-cancel-barrier',
      'link-parser-late',
      'link-restart',
      'migration-roundtrip-full',
      'migration-formal-32-object-inventory',
      'commit-failure-external-third-hash-conflict-file-0',
      'commit-failure-external-third-hash-conflict-file-1',
    };
    expect(
      SyntheticAuthorityRecoveryHarness.canonicalCaseIds,
      containsAll(required),
    );
    const blockedIds = {
      'migration-body-conflict',
      'migration-title-conflict',
      'migration-id-conflict',
      'richtext-invalid-mark',
      'richtext-unknown-mark',
      'asset-missing',
      'asset-hash-mismatch',
      'asset-temp-path',
      'asset-base64',
      'richtext-ime-defer',
      'anchor-ambiguous',
      'anchor-orphan',
      'task-promotion-partial-failure',
      'capture-different-digest',
      'import-different-digest',
      'link-different-digest',
    };
    for (final id in required) {
      final evidence = reportCase(result, id)['evidence'] as Map;
      expect(
        evidence['classification'],
        isIn(const {
          'deterministic',
          'controlled_extension',
          'degraded_preserved',
          'blocked',
        }),
      );
      expect(evidence['legacyDigest'], hasLength(64));
      expect(evidence['rollbackDigest'], hasLength(64));
      if (blockedIds.contains(id)) {
        expect(evidence['classification'], 'blocked');
        expect(evidence['headHash'], isNull);
        expect(evidence['targetDigest'], isNull);
        expect(evidence['acceptedTargetPresent'], false);
        expect(evidence['revisionCount'], 0);
        expect(evidence['operationCount'], 0);
        expect(evidence['receiptCount'], 0);
        expect(evidence['changeCount'], 0);
        expect(evidence['projectionCount'], 0);
        expect(evidence['convergence'], 'needs_resolution');
      } else {
        expect(evidence['headHash'], hasLength(64));
        expect(evidence['targetDigest'], hasLength(64));
      }
    }
    final roundtrip = reportCase(
      result,
      'migration-roundtrip-full',
    )['evidence'] as Map;
    expect(roundtrip['revisionCount'], 2);
    expect(roundtrip['operationCount'], 2);
    expect(roundtrip['eventCount'], 0);
    expect(roundtrip['remigrateDigest'], hasLength(64));
    expect(roundtrip['roundTripLedgersUnique'], true);
    expect(roundtrip['truthCount'], 2);
    final fullRoundTrip = roundtrip['fullRoundTrip'] as Map;
    final domains = fullRoundTrip['domains'] as Map;
    expect(domains.keys.toSet(), _p5RoundTripDomains);
    expect(fullRoundTrip['allSixRoundTripDomainsHeld'], true);
    expect(fullRoundTrip['derivedIndexRebuiltFromAcceptedState'], true);
    expect(fullRoundTrip['transitionTrace'], hasLength(5));
    final indexOperations =
        fullRoundTrip['derivedIndexOperationIdsByStage'] as Map;
    expect(indexOperations.keys.toSet(), {
      'oldBaseline',
      'firstMigration',
      'postCutover',
      'rollback',
      'remigration',
    });
    expect(indexOperations['oldBaseline'], ['operation-migrate-1']);
    expect(indexOperations['firstMigration'], ['operation-migrate-1']);
    for (final stage in const ['postCutover', 'rollback', 'remigration']) {
      expect(
        (indexOperations[stage] as List).toSet(),
        {'operation-migrate-1', 'operation-new-write-1'},
        reason: stage,
      );
    }
    final physicalDigests = fullRoundTrip['physicalDigests'] as Map;
    expect(physicalDigests.keys.toSet(), _p5RoundTripDomains);
    expect(result.report['allSixRoundTripDomainsHeld'], true);
    for (final name in _p5RoundTripDomains) {
      final domain = domains[name] as Map;
      expect(domain.keys.toSet(), _p5RoundTripDomainFields, reason: name);
      for (final field in const [
        'oldBaselineSemanticDigest',
        'newAfterFirstMigrationSemanticDigest',
        'postCutoverNewWriteSetDigest',
        'oldAfterRollbackSemanticDigest',
        'newAfterRemigrationSemanticDigest',
        'stableIdSetDigest',
        'operationIdSetDigest',
      ]) {
        expect(domain[field], hasLength(64), reason: '$name.$field');
      }
      final physical = physicalDigests[name] as Map;
      expect(physical.keys.toSet(), {
        'oldBaseline',
        'firstMigration',
        'rollbackReadable',
        'remigration',
      });
      expect(physical['oldBaseline'], isNot(physical['firstMigration']),
          reason: name);
      expect(physical['rollbackReadable'], isNot(physical['remigration']),
          reason: name);
      expect(
        domain['oldBaselineSemanticDigest'],
        domain['newAfterFirstMigrationSemanticDigest'],
        reason: '$name first-migration semantic preservation',
      );
      expect(
        domain['oldAfterRollbackSemanticDigest'],
        domain['newAfterRemigrationSemanticDigest'],
        reason: name,
      );
      expect(domain['newWritesPreserved'], true, reason: name);
      expect(domain['duplicateAcceptedCount'], 0, reason: name);
      expect(domain['domainInvariantHeld'], true, reason: name);
    }

    for (final id in const [
      'capture-same-digest',
      'capture-different-digest',
      'capture-cancel-barrier',
      'capture-restart',
      'import-same-digest',
      'import-different-digest',
      'import-cancel-barrier',
      'import-parser-late',
      'import-restart',
      'link-same-digest',
      'link-different-digest',
      'link-cancel-barrier',
      'link-parser-late',
      'link-restart',
    ]) {
      final evidence = reportCase(result, id)['evidence'] as Map;
      expect(evidence['targetSchema'], isNot('hereiam-card-envelope-v1'));
      expect(evidence['hasMarkdown'], false);
      expect(evidence['targetRole'], contains('intake'));
      expect(evidence['zeroDownstream'], {
        'card': 0,
        'source': 0,
        'truth': 0,
        'index': 0,
      });
    }

    final inventory = reportCase(
      result,
      'migration-formal-32-object-inventory',
    )['evidence'] as Map;
    final catalog = (inventory['formalCatalog'] as List).cast<Map>();
    expect(catalog, hasLength(32));
    expect(
      catalog.map((entry) => entry['objectType']).toSet(),
      _p5FormalObjectTypes,
    );
    expect(
      SyntheticAuthorityRecoveryHarness.validateFormalCatalogForTest(catalog),
      true,
    );
    expect(
        catalog.every((entry) =>
            entry.keys.toSet().difference(const {
              'objectType',
              'classification',
              'stableIdMapping',
              'authority',
              'refs',
              'rollback',
              'deleteRecovery',
              'indexBackup',
              'blockedReason',
            }).isEmpty &&
            entry.length == 9),
        true);
    expect(
      catalog.every((entry) =>
          const {
            'objectType',
            'classification',
            'authority',
          }.every((key) => entry[key] is String && entry[key] != '') &&
          entry['stableIdMapping'] is Map &&
          (entry['stableIdMapping'] as Map)
              .keys
              .toSet()
              .containsAll(const {'entries'}) &&
          entry['refs'] is List &&
          (entry['refs'] as List).every((value) => value is String) &&
          entry['rollback'] is Map &&
          (entry['rollback'] as Map).keys.toSet().containsAll({
            'strategy',
            'preserveAcceptedNewWrites',
            'appendOnly',
            'reconstructFromAuthority',
          }) &&
          entry['deleteRecovery'] is Map &&
          (entry['deleteRecovery'] as Map).keys.toSet().containsAll({
            'strategy',
            'tombstoneBarrier',
            'physicalDeleteAllowed',
            'recoverySource',
          }) &&
          entry['indexBackup'] is Map &&
          (entry['indexBackup'] as Map).keys.toSet().containsAll({
            'rebuildFrom',
            'backupRequired',
            'excludedFromBackup',
          }) &&
          (entry['classification'] == 'blocked'
              ? entry['blockedReason'] is String && entry['blockedReason'] != ''
              : entry['blockedReason'] == '')),
      true,
    );
    Map rowFor(String objectType) => catalog.singleWhere(
          (entry) => entry['objectType'] == objectType,
        );
    expect(rowFor('rich_text_document'), {
      'objectType': 'rich_text_document',
      'classification': 'compatibility-only',
      'stableIdMapping': {
        'entries': [
          {
            'legacyKind': 'richtext_editor_cache',
            'targetKind': 'editor_cache',
            'mode': 'not_applicable',
            'sourceFields': ['card_id', 'revision_hash'],
            'targetField': 'not_applicable',
            'fallbackAlgorithm': '',
            'guard': 'cache never receives authoritative identity',
          },
          {
            'legacyKind': 'unclassified_richtext_element',
            'targetKind': 'richtext_compatibility_capsule',
            'mode': 'allocate_digest_if_missing',
            'sourceFields': ['card_id', 'revision_hash', 'raw_sha256'],
            'targetField': 'compatibility_capsules.capsule_id',
            'fallbackAlgorithm': 'deterministic_namespace_plus_payload_sha256',
            'guard':
                'only when complete reversible raw bytes are preserved; never body authority',
          },
        ],
      },
      'authority': 'markdown_revision_only',
      'refs': ['card_id', 'revision_hash', 'asset_id', 'linked_card_id'],
      'rollback': {
        'strategy':
            'rebuild compatibility RichText from accepted Markdown; preserve capsule bytes only',
        'preserveAcceptedNewWrites': false,
        'appendOnly': false,
        'reconstructFromAuthority': true,
      },
      'deleteRecovery': {
        'strategy':
            'delete/rebuild editor cache; capsule follows owning revision retention',
        'tombstoneBarrier': false,
        'physicalDeleteAllowed': true,
        'recoverySource':
            'accepted Markdown revision plus reversible compatibility capsule',
      },
      'indexBackup': {
        'rebuildFrom': ['card_revisions'],
        'backupRequired': ['compatibility_capsules'],
        'excludedFromBackup': [
          'richtext_editor_cache',
          'plain_text_cache',
        ],
      },
      'blockedReason': '',
    });
    expect(rowFor('domain_operation_receipt_change')['rollback'], {
      'strategy':
          'append compensating operation; never rewrite accepted operation/receipt/change',
      'preserveAcceptedNewWrites': true,
      'appendOnly': true,
      'reconstructFromAuthority': false,
    });
    expect(
      (rowFor('domain_operation_receipt_change')['stableIdMapping']
          as Map)['entries'],
      hasLength(3),
    );
    expect(rowFor('derived_index_cache'), {
      'objectType': 'derived_index_cache',
      'classification': 'derive',
      'stableIdMapping': {
        'entries': [
          {
            'legacyKind': 'derived_projection',
            'targetKind': 'derived_projection_key',
            'mode': 'derive_composite',
            'sourceFields': ['source_hash', 'source_version'],
            'targetField': 'derived_projections.rebuild_key',
            'fallbackAlgorithm': '',
            'guard':
                'source is accepted authority; projection cannot win migration',
          },
        ],
      },
      'authority': 'none_derived_only',
      'refs': ['accepted_revision_hash', 'domain_operation_id'],
      'rollback': {
        'strategy': 'drop and rebuild from accepted authority',
        'preserveAcceptedNewWrites': false,
        'appendOnly': false,
        'reconstructFromAuthority': true,
      },
      'deleteRecovery': {
        'strategy':
            'physical cache deletion allowed; stale source tombstone prevents resurrection',
        'tombstoneBarrier': false,
        'physicalDeleteAllowed': true,
        'recoverySource': 'accepted revision or domain operation',
      },
      'indexBackup': {
        'rebuildFrom': [
          'accepted_card_revisions',
          'accepted_domain_operations',
        ],
        'backupRequired': <String>[],
        'excludedFromBackup': [
          'fts',
          'backlinks',
          'previews',
          'embeddings',
          'richtext_editor_cache',
        ],
      },
      'blockedReason': '',
    });
    expect(rowFor('backup_manifest')['rollback'], {
      'strategy':
          'retain immutable recovery media by policy but never use it as writer or accepted online state',
      'preserveAcceptedNewWrites': false,
      'appendOnly': false,
      'reconstructFromAuthority': false,
    });
    expect(rowFor('backup_manifest')['deleteRecovery'], {
      'strategy':
          'retention may physically expire media; restore must apply manifest tombstone/journal barrier',
      'tombstoneBarrier': false,
      'physicalDeleteAllowed': true,
      'recoverySource': 'verified immutable backup manifest and objects',
    });
    expect(rowFor('backup_manifest')['indexBackup'], {
      'rebuildFrom': <String>[],
      'backupRequired': [
        'backup_manifests',
        'sqlite_snapshot',
        'vault_objects',
        'object_tombstones',
        'journal_watermark',
      ],
      'excludedFromBackup': [
        'fts',
        'backlinks',
        'previews',
        'embeddings',
        'richtext_editor_cache',
      ],
    });
    Map<String, dynamic> mutableRow(List<dynamic> rows, String objectType) =>
        rows.cast<Map<String, dynamic>>().singleWhere(
              (row) => row['objectType'] == objectType,
            );
    for (final mutation in <void Function(List<dynamic>)>[
      (rows) => (mutableRow(rows, 'rich_text_document')['rollback']
          as Map<String, dynamic>)['preserveAcceptedNewWrites'] = true,
      (rows) => (mutableRow(rows, 'domain_operation_receipt_change')['rollback']
          as Map<String, dynamic>)['appendOnly'] = false,
      (rows) => (mutableRow(rows, 'derived_index_cache')['indexBackup']
          as Map<String, dynamic>)['backupRequired'] = ['generic-backup'],
      (rows) => (mutableRow(rows, 'backup_manifest')['deleteRecovery']
          as Map<String, dynamic>)['tombstoneBarrier'] = true,
      (rows) {
        final stable = mutableRow(
          rows,
          'rich_text_document',
        )['stableIdMapping'] as Map<String, dynamic>;
        final last = (stable['entries'] as List).last as Map<String, dynamic>;
        last['fallbackAlgorithm'] = '';
      },
    ]) {
      final changed = jsonDecode(jsonEncode(catalog)) as List<dynamic>;
      mutation(changed);
      expect(
        SyntheticAuthorityRecoveryHarness.validateFormalCatalogForTest(
          changed,
        ),
        false,
      );
    }

    for (var index = 0; index < catalog.length; index++) {
      final changedActual = jsonDecode(jsonEncode(catalog)) as List<dynamic>;
      final changedLiteral = jsonDecode(jsonEncode(catalog)) as List<dynamic>;
      (changedActual[index] as Map<String, dynamic>)['authority'] =
          'synchronously-wrong-authority';
      (changedLiteral[index] as Map<String, dynamic>)['authority'] =
          'synchronously-wrong-authority';
      expect(
        changedActual,
        changedLiteral,
        reason: 'diagnostic copies intentionally match at row $index',
      );
      expect(
        SyntheticAuthorityRecoveryHarness.validateFormalCatalogForTest(
          changedActual,
        ),
        false,
        reason: 'frozen external contract must reject row $index',
      );
    }
    final wrongObjectType = jsonDecode(jsonEncode(catalog)) as List<dynamic>;
    (wrongObjectType.first as Map<String, dynamic>)['objectType'] =
        'user_truth_memory_card';
    expect(
      SyntheticAuthorityRecoveryHarness.validateFormalCatalogForTest(
        wrongObjectType,
      ),
      false,
    );
    final wrongShape = jsonDecode(jsonEncode(catalog)) as List<dynamic>;
    (wrongShape.first as Map<String, dynamic>)['refs'] = 'not-structured';
    expect(
      SyntheticAuthorityRecoveryHarness.validateFormalCatalogForTest(
        wrongShape,
      ),
      false,
    );
    final wrongEmptyReason = jsonDecode(jsonEncode(catalog)) as List<dynamic>;
    (wrongEmptyReason.first as Map<String, dynamic>)['blockedReason'] =
        'must-be-empty-for-nonblocked';
    expect(
      SyntheticAuthorityRecoveryHarness.validateFormalCatalogForTest(
        wrongEmptyReason,
      ),
      false,
    );
  });

  test('migration raw/hash/count/intake/RichText/crash tampering fails closed',
      () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (document) => caseById(document, 'richtext-paragraph')['input']['legacy']
          ['bytes'] = 'tampered legacy bytes',
      (document) => caseById(document, 'richtext-paragraph')['input']['legacy']
          ['headHash'] = 'tampered-legacy-head-hash',
      (document) => caseById(document, 'richtext-paragraph')['expected']
          ['target']['headHash'] = 'tampered-target-head-hash',
      (document) => caseById(document, 'richtext-paragraph')['expected']
          ['target']['classification'] = 'migrate',
      (document) => caseById(document, 'capture-same-digest')['expected']
          ['target']['targetRole'] = 'cards/card_revisions',
      (document) => caseById(
            document,
            'migration-formal-32-object-inventory',
          )['expected']['target']['catalog'][0]['targetRole'] = 'wrong-role',
      (document) => caseById(document, 'migration-body-conflict')['expected']
          ['target']['headHash'] = 'forged-blocked-head',
      (document) =>
          caseById(document, 'commit-crash-after-tx-b-commit')['expected']
              ['commit']['newManifest'][0]['hash'] = 'tampered-hash',
      (document) => caseById(document, 'migration-roundtrip-full')['expected']
          ['roundTrip']['remigrateDigest'] = 'tampered-digest',
      (document) => caseById(
            document,
            'commit-crash-after-activation-tx-commit',
          )['expected']['commit']['receiptCount'] = 2,
      (document) => caseById(document, 'capture-same-digest')['input']['legacy']
          ['details']['incomingDigest'] = 'tampered-dedupe',
      (document) => caseById(document, 'capture-cancel-barrier')['input']
          ['legacy']['details']['cancelled'] = false,
      (document) => caseById(document, 'import-parser-late')['input']['legacy']
          ['details']['parserCompleted'] = false,
      (document) => caseById(document, 'richtext-unknown-mark')['input']
          ['legacy']['details']['marks'][0]['type'] = 'bold',
      (document) => caseById(document, 'richtext-utf16-fingerprint')['input']
          ['legacy']['details']['utf16Fingerprint'] = 'tampered-fingerprint',
      (document) => caseById(document, 'asset-image')['input']['legacy']
          ['details']['asset']['actualHash'] = 'tampered-asset-hash',
      (document) => caseById(document, 'richtext-ime-defer')['input']['legacy']
          ['details']['imeCommitted'] = true,
      (document) => caseById(
            document,
            'commit-failure-external-third-hash-conflict-file-0',
          )['input']['transaction']['observedHash'] = 'tampered-third-party',
      (document) => caseById(
            document,
            'commit-crash-after-file-publish-0',
          )['input']['transaction']['crashPhase'] = 'before_file_publish:0',
    ];
    for (final mutate in mutations) {
      final copy = fixtureCopy(mutateScenarios: mutate);
      expect(
        () => harnessFor(copy.base).run(
          fixtureRoot: copy.fixture,
          outputRoot: output().path,
        ),
        _failure(FailureClass.inputRejected),
      );
    }
  });

  test('roundtrip and commit duplicate ledgers change actual to red', () {
    Map<String, dynamic> canonicalInput(String id) =>
        literalScenario(id)['input'] as Map<String, dynamic>;

    final injections = <String, Map<String, Object>>{
      'injectRoundTripDuplicateRecord': {
        'domain': 'operationLog',
        'duplicates': 1,
      },
      'injectRoundTripDuplicateStableId': {
        'domain': 'cardContent',
        'duplicates': 1,
      },
      'injectRoundTripDuplicateOperationId': {
        'domain': 'sourceAnchor',
        'duplicates': 1,
      },
      'injectRoundTripDanglingRef': {
        'domain': 'userTruthSet',
        'duplicates': 0,
      },
      'injectRoundTripDanglingUserTruthCardId': {
        'domain': 'userTruthSet',
        'duplicates': 0,
      },
      'injectRoundTripDanglingSourceVersionId': {
        'domain': 'sourceAnchor',
        'duplicates': 0,
      },
      'injectRoundTripDanglingRevisionParentId': {
        'domain': 'revisionHistory',
        'duplicates': 0,
      },
    };
    for (final injection in injections.entries) {
      final roundtripInput = canonicalInput('migration-roundtrip-full');
      (roundtripInput['legacy'] as Map<String, dynamic>)['details']
          [injection.key] = true;
      final roundtrip =
          SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
              'migration-roundtrip-full', roundtripInput);
      final evidence = roundtrip['evidence'] as Map;
      final domains = (evidence['fullRoundTrip'] as Map)['domains'] as Map;
      final domain = domains[injection.value['domain']] as Map;
      expect(roundtrip['actual'], 'migration_case_contract_violation',
          reason: injection.key);
      expect(domain['duplicateAcceptedCount'], injection.value['duplicates'],
          reason: injection.key);
      expect(domain['domainInvariantHeld'], false, reason: injection.key);
      expect(
        (evidence['fullRoundTrip'] as Map)['allSixRoundTripDomainsHeld'],
        false,
        reason: injection.key,
      );
      expect(
        (roundtrip['invariantResults'] as Map)['contractInvariantHeld'],
        false,
      );
      final comparator =
          SyntheticAuthorityRecoveryHarness.compareComputedMigrationForTest(
        roundtrip['computedActualForComparator'] as Map<String, dynamic>,
        literalScenario('migration-roundtrip-full')['expected']
            as Map<String, dynamic>,
        contractInvariantHeld: false,
      );
      expect(comparator.values.every((value) => value), false);
    }

    final driftInput = canonicalInput('migration-roundtrip-full');
    (driftInput['legacy'] as Map<String, dynamic>)['details']
        ['injectFirstMigrationSemanticDrift'] = true;
    final drift = SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
      'migration-roundtrip-full',
      driftInput,
    );
    final driftRoundTrip = (drift['evidence'] as Map)['fullRoundTrip'] as Map;
    final driftCard = (driftRoundTrip['domains'] as Map)['cardContent'] as Map;
    expect(
      driftCard['oldBaselineSemanticDigest'],
      isNot(driftCard['newAfterFirstMigrationSemanticDigest']),
    );
    expect(driftCard['domainInvariantHeld'], false);
    expect(driftRoundTrip['allSixRoundTripDomainsHeld'], false);
    expect(drift['actual'], 'migration_case_contract_violation');

    final derivedIndexDriftInput = canonicalInput('migration-roundtrip-full');
    (derivedIndexDriftInput['legacy'] as Map<String, dynamic>)['details']
        ['injectFirstMigrationDerivedIndexSemanticDrift'] = true;
    final derivedIndexDrift =
        SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
      'migration-roundtrip-full',
      derivedIndexDriftInput,
    );
    final derivedIndexDriftRoundTrip =
        (derivedIndexDrift['evidence'] as Map)['fullRoundTrip'] as Map;
    final derivedIndexDomain =
        (derivedIndexDriftRoundTrip['domains'] as Map)['derivedIndex'] as Map;
    expect(
      derivedIndexDomain['oldBaselineSemanticDigest'],
      isNot(derivedIndexDomain['newAfterFirstMigrationSemanticDigest']),
    );
    expect(derivedIndexDomain['domainInvariantHeld'], false);
    expect(derivedIndexDriftRoundTrip['allSixRoundTripDomainsHeld'], false);
    expect(derivedIndexDrift['actual'], 'migration_case_contract_violation');

    final futureIndexInput = canonicalInput('migration-roundtrip-full');
    (futureIndexInput['legacy'] as Map<String, dynamic>)['details']
        ['injectFirstMigrationDerivedIndexFutureOperation'] = true;
    final futureIndex =
        SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
      'migration-roundtrip-full',
      futureIndexInput,
    );
    final futureIndexRoundTrip =
        (futureIndex['evidence'] as Map)['fullRoundTrip'] as Map;
    final futureIndexStages =
        futureIndexRoundTrip['derivedIndexOperationIdsByStage'] as Map;
    expect(futureIndexStages['oldBaseline'], isNot(contains('future-op')));
    expect(futureIndexStages['firstMigration'], contains('future-op'));
    expect(futureIndexRoundTrip['allSixRoundTripDomainsHeld'], false);
    expect(futureIndex['actual'], 'migration_case_contract_violation');

    final commitInput =
        canonicalInput('commit-crash-after-activation-tx-commit');
    final initial = commitInput['transaction']['initialLedgers'] as Map;
    for (final name in const ['receipt', 'change', 'projection']) {
      initial[name] = [
        {'key': 'migration', 'digest': 'migration-digest'},
        {'key': 'migration', 'digest': 'migration-digest'},
      ];
    }
    final commit =
        SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
            'commit-crash-after-activation-tx-commit', commitInput);
    final commitEvidence = commit['evidence'] as Map;
    expect(commit['actual'], 'migration_case_contract_violation');
    expect(commitEvidence['commitLedgersExactlyOnce'], false);
    expect(commitEvidence['receiptCount'], 2);
    expect(commitEvidence['changeCount'], 2);
    expect(commitEvidence['projectionCount'], 2);
  });

  test('every migration crash boundary rejects phase substitution', () {
    final canonical = jsonDecode(
      File('$golden${Platform.pathSeparator}scenarios.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final commitScenarios = (canonical['scenarios'] as List)
        .cast<Map<String, dynamic>>()
        .where((scenario) => scenario['family'] == 'migration-recovery')
        .where((scenario) =>
            (scenario['input'] as Map<String, dynamic>)['objectType'] ==
            'domain_operation_receipt_change')
        .toList();
    final exactCrashScenarios = commitScenarios
        .where((scenario) =>
            (scenario['id'] as String).startsWith('commit-crash-'))
        .toList();
    final failureScenarios = commitScenarios
        .where((scenario) =>
            (scenario['id'] as String).startsWith('commit-failure-'))
        .toList();
    expect(exactCrashScenarios, hasLength(52));
    expect(failureScenarios, hasLength(26));
    expect(
      exactCrashScenarios
          .map((scenario) => scenario['input']['transaction']['crashPhase'])
          .toSet(),
      _p5ExactExpandedCrashPoints.toSet(),
    );
    expect(
      failureScenarios.map((scenario) {
        var token = (scenario['id'] as String)
            .substring('commit-failure-'.length)
            .replaceAll('-', '_');
        token = token.replaceFirst(RegExp(r'_file_[01]$'), '');
        return token;
      }).toSet(),
      _p5ExactFailurePoints.toSet(),
    );
    final result = harnessFor(sourceFixtureBase).run(
      fixtureRoot: golden,
      outputRoot: output().path,
    );
    expect(
        result.report['exactExpandedCrashPoints'], _p5ExactExpandedCrashPoints);
    expect(result.report['exactFailurePoints'], _p5ExactFailurePoints);
    final machine = result.report['stateMachineEvidence'] as Map;
    expect(machine['expandedCrashPointCaseCount'], 52);
    expect(machine['uniqueExpandedCrashPointCount'], 52);
    expect(machine['failurePointCaseCount'], 26);
    expect(machine['uniqueFailurePointCount'], 25);
    expect(machine['externalThirdHashConflictCrashBindings'], [
      'after_file_publish:0',
      'after_file_publish:1',
    ]);

    Map<String, dynamic> durable(String id) => Map<String, dynamic>.from(
          reportCase(result, id)['evidence']['durableStateAtCrash'] as Map,
        );

    final beforeStage0 = durable('commit-crash-before-stage-file-write-0');
    final beforeStage1 = durable('commit-crash-before-stage-file-write-1');
    final afterStageWrite0 =
        durable('commit-crash-after-stage-file-write-0-before-file-fsync');
    final afterStageFsync0 =
        durable('commit-crash-after-stage-file-fsync-0-before-directory-fsync');
    final afterStageWrite1 =
        durable('commit-crash-after-stage-file-write-1-before-file-fsync');
    expect(beforeStage0['stageWrites'], isEmpty);
    expect(beforeStage0['stageFsyncs'], isEmpty);
    expect(beforeStage1['stageWrites'], [0]);
    expect(beforeStage1['stageFsyncs'], [0]);
    expect(afterStageWrite0['stageWrites'], [0]);
    expect(afterStageWrite0['stageFsyncs'], isEmpty);
    expect(afterStageFsync0['stageWrites'], [0]);
    expect(afterStageFsync0['stageFsyncs'], [0]);
    expect(afterStageWrite1['stageWrites'], [0, 1]);
    expect(afterStageWrite1['stageFsyncs'], [0]);

    expect(
      durable('commit-crash-before-file-publish-0')['publishedFiles'],
      isEmpty,
    );
    expect(
      durable('commit-crash-before-file-publish-1')['publishedFiles'],
      [0],
    );
    expect(
      durable('commit-crash-after-file-publish-1')['publishedFiles'],
      [0, 1],
    );
    expect(
      durable('commit-crash-before-projection-rebuild-1')['projectionsStarted'],
      [0],
    );
    expect(
      durable(
          'commit-crash-before-projection-rebuild-1')['projectionsCompleted'],
      [0],
    );
    expect(
      durable('commit-crash-during-projection-rebuild-1')['projectionsStarted'],
      [0, 1],
    );
    expect(
      durable(
          'commit-crash-during-projection-rebuild-1')['projectionsCompleted'],
      [0],
    );
    expect(
      durable('commit-crash-after-projection-rebuild-1-before-cursor-commit')[
          'projectionsCompleted'],
      [0, 1],
    );
    expect(
        durable('commit-crash-during-cleanup-0')['cleanupCompleted'], isEmpty);
    expect(durable('commit-crash-during-cleanup-0')['cleanupInProgress'], [0]);
    expect(durable('commit-crash-during-cleanup-1')['cleanupCompleted'], [0]);
    expect(durable('commit-crash-during-cleanup-1')['cleanupInProgress'], [1]);

    final afterFile0 = durable('commit-crash-after-file-publish-0');
    final beforeFile1 = durable('commit-crash-before-file-publish-1');
    Map<String, dynamic> logicalCheckpoint(Map<String, dynamic> state) {
      final copy = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
      for (final key in const [
        'stagedHashes',
        'stageFsyncHashes',
        'rollbackCopyHashes',
        'rollbackFsyncHashes',
        'publishedHashes',
      ]) {
        copy.remove(key);
      }
      return copy;
    }

    expect(logicalCheckpoint(afterFile0), logicalCheckpoint(beforeFile1));
    expect(afterFile0['publishedFiles'], [0]);
    expect(afterFile0['publishedHashes'], hasLength(1));
    expect(
      afterFile0['publishedHashes'],
      [
        (reportCase(result, 'commit-crash-after-file-publish-0')['evidence']
            ['newManifest'] as List)[0]['hash'],
      ],
    );
    final afterObject0 = durable('commit-crash-after-object-publish-0');
    final beforeObject1 = durable('commit-crash-before-object-publish-1');
    expect(logicalCheckpoint(afterObject0), logicalCheckpoint(beforeObject1));
    expect(afterObject0['publishedObjects'], [0]);
    expect(afterObject0['publishedHashes'], hasLength(3));
    expect(
      afterObject0['publishedHashes'],
      (reportCase(result, 'commit-crash-after-object-publish-0')['evidence']
              ['newManifest'] as List)
          .map((entry) => entry['hash'])
          .take(3)
          .toList(),
    );
    final sameRawTransaction = jsonDecode(jsonEncode(
      literalScenario('commit-crash-after-file-publish-0')['input'],
    )) as Map<String, dynamic>;
    final sameInputAfterFile0 = SyntheticAuthorityRecoveryHarness
        .migrationDurableStateAtBoundaryForTest(
      'commit-crash-after-file-publish-0',
      sameRawTransaction,
      'after_file_publish:0',
    );
    final sameInputBeforeFile1 = SyntheticAuthorityRecoveryHarness
        .migrationDurableStateAtBoundaryForTest(
      'commit-crash-after-file-publish-0',
      sameRawTransaction,
      'before_file_publish:1',
    );
    expect(sameInputAfterFile0, sameInputBeforeFile1);
    expect(sameInputAfterFile0['publishedFiles'], [0]);
    expect(sameInputAfterFile0['publishedHashes'], hasLength(1));
    final sameInputAfterObject0 = SyntheticAuthorityRecoveryHarness
        .migrationDurableStateAtBoundaryForTest(
      'commit-crash-after-file-publish-0',
      sameRawTransaction,
      'after_object_publish:0',
    );
    final sameInputBeforeObject1 = SyntheticAuthorityRecoveryHarness
        .migrationDurableStateAtBoundaryForTest(
      'commit-crash-after-file-publish-0',
      sameRawTransaction,
      'before_object_publish:1',
    );
    expect(sameInputAfterObject0, sameInputBeforeObject1);
    expect(sameInputAfterObject0['publishedObjects'], [0]);
    expect(sameInputAfterObject0['publishedHashes'], hasLength(3));

    for (final scenario in exactCrashScenarios) {
      final id = scenario['id'] as String;
      final trace = (durable(id)['actionTrace'] as List).cast<String>();
      expect(trace, _p5MigrationActionOrder.take(trace.length).toList(),
          reason: id);
      expect(trace.toSet(), hasLength(trace.length), reason: id);
    }

    final representativeDigests = const [
      'commit-crash-before-stage-file-write-0',
      'commit-crash-before-stage-file-write-1',
      'commit-crash-after-stage-file-write-0-before-file-fsync',
      'commit-crash-after-stage-file-write-1-before-file-fsync',
      'commit-crash-before-file-publish-0',
      'commit-crash-before-file-publish-1',
      'commit-crash-during-projection-rebuild-0',
      'commit-crash-during-projection-rebuild-1',
      'commit-crash-during-cleanup-0',
      'commit-crash-during-cleanup-1',
    ]
        .map((id) =>
            reportCase(result, id)['evidence']['serializedBeforeRestartDigest'])
        .toSet();
    expect(representativeDigests, hasLength(10));

    const diagnosticId = 'commit-crash-after-file-publish-0';
    final diagnosticInput = jsonDecode(
      jsonEncode(literalScenario(diagnosticId)['input']),
    ) as Map<String, dynamic>;
    final diagnosticState =
        jsonDecode(jsonEncode(durable(diagnosticId))) as Map<String, dynamic>;
    expect(
      SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
        diagnosticId,
        diagnosticInput,
        diagnosticState,
      )['convergence'],
      'new',
    );
    final wholeBeforeIdentityState = SyntheticAuthorityRecoveryHarness
        .migrationDurableStateAtBoundaryForTest(
      diagnosticId,
      diagnosticInput,
      'before_identity_precheck',
    );
    expect(
      SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
        diagnosticId,
        diagnosticInput,
        wholeBeforeIdentityState,
      )['convergence'],
      'needs_resolution',
      reason: 'a valid state from another trace cannot replace this boundary',
    );
    final ghostBundle =
        jsonDecode(jsonEncode(diagnosticState)) as Map<String, dynamic>;
    final ghostInitial = <String, dynamic>{
      for (final ledger in const ['receipt', 'change', 'projection'])
        ledger: [
          {'key': 'ghost-$ledger', 'digest': 'ghost-digest'},
        ],
    };
    ghostBundle['initialLedgers'] = jsonDecode(jsonEncode(ghostInitial));
    ghostBundle['receiptLedger'] =
        jsonDecode(jsonEncode(ghostInitial['receipt']));
    ghostBundle['changeLedger'] =
        jsonDecode(jsonEncode(ghostInitial['change']));
    ghostBundle['projectionLedger'] =
        jsonDecode(jsonEncode(ghostInitial['projection']));
    expect(
      SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
        diagnosticId,
        diagnosticInput,
        ghostBundle,
      )['convergence'],
      'needs_resolution',
      reason: 'self-consistent ghost ledgers cannot replace input ledgers',
    );
    final malformedDurableLedgers =
        <String, void Function(Map<String, dynamic>)>{
      'missing-receipt-ledger': (state) => state.remove('receiptLedger'),
      'receipt-ledger-string': (state) => state['receiptLedger'] = 'corrupt',
      'receipt-ledger-string-element': (state) =>
          state['receiptLedger'] = ['corrupt'],
      'receipt-entry-missing-key': (state) => state['receiptLedger'] = [
            {'digest': 'migration-digest'},
          ],
      'receipt-entry-missing-digest': (state) => state['receiptLedger'] = [
            {'key': 'migration'},
          ],
      'receipt-entry-extra-key': (state) => state['receiptLedger'] = [
            {
              'key': 'migration',
              'digest': 'migration-digest',
              'extra': true,
            },
          ],
      'receipt-entry-empty-key': (state) => state['receiptLedger'] = [
            {'key': '', 'digest': 'migration-digest'},
          ],
      'receipt-entry-empty-digest': (state) => state['receiptLedger'] = [
            {'key': 'migration', 'digest': ''},
          ],
      'change-ledger-wrong-type': (state) => state['changeLedger'] = 7,
      'projection-ledger-wrong-type': (state) =>
          state['projectionLedger'] = {'key': 'not-a-list'},
      'embedded-initial-ledgers-wrong-type': (state) =>
          state['initialLedgers'] = 'corrupt',
      'embedded-initial-ledger-bad-element': (state) =>
          (state['initialLedgers'] as Map)['receipt'] = ['corrupt'],
      'embedded-initial-ledger-missing-domain': (state) =>
          (state['initialLedgers'] as Map).remove('projection'),
    };
    for (final corruption in malformedDurableLedgers.entries) {
      final changed =
          jsonDecode(jsonEncode(diagnosticState)) as Map<String, dynamic>;
      corruption.value(changed);
      expect(
        SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
          diagnosticId,
          diagnosticInput,
          changed,
        )['convergence'],
        'needs_resolution',
        reason: corruption.key,
      );
    }
    for (final corruption in <void Function(Map<String, dynamic>)>[
      (input) => input['transaction']['initialLedgers'] = 'corrupt',
      (input) => (input['transaction']['initialLedgers'] as Map)['receipt'] = [
            'corrupt'
          ],
      (input) =>
          (input['transaction']['initialLedgers'] as Map).remove('change'),
      (input) =>
          (input['transaction']['initialLedgers'] as Map)['projection'] = [
            {'key': '', 'digest': 'migration-digest'},
          ],
    ]) {
      final changedInput =
          jsonDecode(jsonEncode(diagnosticInput)) as Map<String, dynamic>;
      corruption(changedInput);
      expect(
        () => SyntheticAuthorityRecoveryHarness
            .recoverMigrationDurableStateForTest(
          diagnosticId,
          changedInput,
          diagnosticState,
        ),
        _failure(FailureClass.inputRejected),
      );
    }
    final tamperedPublished =
        jsonDecode(jsonEncode(diagnosticState)) as Map<String, dynamic>;
    (tamperedPublished['publishedHashes'] as List)[0] =
        'tampered-published-hash';
    expect(
      SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
        diagnosticId,
        diagnosticInput,
        tamperedPublished,
      )['convergence'],
      'needs_resolution',
    );
    final tamperedFsync =
        jsonDecode(jsonEncode(diagnosticState)) as Map<String, dynamic>;
    (tamperedFsync['stageFsyncHashes'] as List)[0] = 'tampered-fsync-hash';
    expect(
      SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
        diagnosticId,
        diagnosticInput,
        tamperedFsync,
      )['convergence'],
      'needs_resolution',
    );
    final pairedTampering = <String, void Function(Map<String, dynamic>)>{
      'clear-publish-ordinal-and-hash': (state) {
        state['publishedFiles'] = <int>[];
        state['publishedHashes'] = <String>[];
      },
      'clear-publish-phase-ordinal-and-hash': (state) {
        state['publishPhaseStarted'] = false;
        state['journalPhase'] = 'staged';
        state['publishedFiles'] = <int>[];
        state['publishedHashes'] = <String>[];
      },
      'preserve-trace-change-state': (state) {
        state['notificationSent'] = true;
      },
      'preserve-state-remove-trace-action': (state) {
        (state['actionTrace'] as List).removeLast();
      },
      'preserve-state-add-unknown-trace-action': (state) {
        (state['actionTrace'] as List).add('unknown_publish_action');
      },
      'clear-stage-fsync-ordinal-and-hash': (state) {
        state['stageFsyncs'] = <int>[];
        state['stageFsyncHashes'] = <String>[];
      },
      'forge-stage-fsync-ordinal-and-hash': (state) {
        state['stageFsyncs'] = <int>[0];
        state['stageFsyncHashes'] = <String>['forged-fsync-hash'];
      },
    };
    for (final mutation in pairedTampering.entries) {
      final changed =
          jsonDecode(jsonEncode(diagnosticState)) as Map<String, dynamic>;
      mutation.value(changed);
      expect(
        SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
          diagnosticId,
          diagnosticInput,
          changed,
        )['convergence'],
        'needs_resolution',
        reason: mutation.key,
      );
    }

    for (final scenario in exactCrashScenarios) {
      final id = scenario['id'] as String;
      final input =
          jsonDecode(jsonEncode(scenario['input'])) as Map<String, dynamic>;
      final originalPoint = input['transaction']['crashPhase'] as String;
      final originalState = SyntheticAuthorityRecoveryHarness
          .migrationDurableStateAtBoundaryForTest(
        id,
        input,
        originalPoint,
      );
      expect(
        SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
          id,
          input,
          originalState,
        )['convergence'],
        isIn(const ['old', 'new']),
        reason: '$id canonical durable state',
      );
      final replacementPoint = originalPoint == 'before_identity_precheck'
          ? 'after_identity_precheck_before_idempotency'
          : 'before_identity_precheck';
      final replacementState = SyntheticAuthorityRecoveryHarness
          .migrationDurableStateAtBoundaryForTest(
        id,
        input,
        replacementPoint,
      );
      expect(
        replacementState['actionTrace'],
        isNot(originalState['actionTrace']),
        reason: '$id replacement must use a different trace',
      );
      expect(
        SyntheticAuthorityRecoveryHarness.recoverMigrationDurableStateForTest(
          id,
          input,
          replacementState,
        )['convergence'],
        'needs_resolution',
        reason: '$id whole-state boundary substitution',
      );
    }

    for (var index = 0; index < exactCrashScenarios.length; index++) {
      final scenario = exactCrashScenarios[index];
      final input =
          jsonDecode(jsonEncode(scenario['input'])) as Map<String, dynamic>;
      final originalPoint = input['transaction']['crashPhase'] as String;
      input['transaction']['crashPhase'] = _p5ExactExpandedCrashPoints[
          (_p5ExactExpandedCrashPoints.indexOf(originalPoint) + 1) % 52];
      final changed =
          SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
        scenario['id'] as String,
        input,
      );
      expect(changed['actual'], 'migration_case_contract_violation',
          reason: scenario['id'] as String);
    }
    for (final scenario in failureScenarios) {
      final canonicalDetails =
          scenario['input']['legacy']['details'] as Map<String, dynamic>;
      expect(
        (canonicalDetails['failureFacts'] as Map).keys.toSet(),
        _migrationFailureFactKeys,
        reason: scenario['id'] as String,
      );
      expect(
        reportCase(result, scenario['id'] as String)['evidence']
            ['exactFailurePointExecuted'],
        scenario['expected']['commit']['failurePoint'],
        reason: scenario['id'] as String,
      );
      final input =
          jsonDecode(jsonEncode(scenario['input'])) as Map<String, dynamic>;
      final details = input['legacy']['details'] as Map<String, dynamic>;
      final facts = details['failureFacts'] as Map<String, dynamic>;
      if (facts['credential'] == 'stale') {
        facts['credential'] = 'current';
        facts['binding'] = 'mismatch';
      } else {
        facts['credential'] = 'stale';
        if (scenario['expected']['commit']['failurePoint'] ==
            'external_third_hash_conflict') {
          facts['observedHash'] = facts['oldHash'];
        }
      }
      final changed =
          SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
        scenario['id'] as String,
        input,
      );
      expect(changed['actual'], 'migration_case_contract_violation',
          reason: scenario['id'] as String);
    }

    final rawFactSource = failureScenarios.first;
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (facts) => facts['diskCapacity'] = 'not-an-int',
      (facts) => facts['credential'] = 'unknown-generation',
    ]) {
      final input = jsonDecode(jsonEncode(rawFactSource['input']))
          as Map<String, dynamic>;
      final facts =
          input['legacy']['details']['failureFacts'] as Map<String, dynamic>;
      mutate(facts);
      expect(
        () => SyntheticAuthorityRecoveryHarness.simulateMigrationRawForTest(
          rawFactSource['id'] as String,
          input,
        ),
        _failure(FailureClass.inputRejected),
      );
    }

    final precheckFailure = reportCase(
      result,
      'commit-failure-stale-credential-generation',
    )['evidence'] as Map;
    expect(precheckFailure['idempotencyLookupCount'], 0);
    expect(precheckFailure['businessReadCount'], 0);
    final duplicateSame = reportCase(
      result,
      'commit-failure-duplicate-key-same-digest',
    )['evidence'] as Map;
    expect(duplicateSame['idempotencyLookupCount'], 1);
    expect(duplicateSame['businessReadCount'], 0);
    expect(duplicateSame['idempotencyReused'], true);
    expect(duplicateSame['receiptCount'], 1);
  });

  test('manifest, allowlist, corrupt input, and unknown ids fail closed', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (manifest) => (manifest['exactExpandedCrashPoints'] as List).removeLast(),
      (manifest) => (manifest['exactExpandedCrashPoints'] as List)
          .add('unknown_coarse_stage'),
      (manifest) => (manifest['exactFailurePoints'] as List)
          .add(_p5ExactFailurePoints.first),
    ]) {
      final badExactCatalog = fixtureCopy(mutateManifest: mutate);
      expect(
        () => harnessFor(badExactCatalog.base).run(
          fixtureRoot: badExactCatalog.fixture,
          outputRoot: output().path,
        ),
        _failure(FailureClass.inputRejected),
      );
    }
    final badSchema = fixtureCopy(
      mutateManifest: (manifest) => manifest['schemaVersion'] = 99,
    );
    expect(
      () => harnessFor(badSchema.base).run(
        fixtureRoot: badSchema.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.unsupported),
    );

    final duplicateAllowlist = fixtureCopy(
      mutateManifest: (manifest) => manifest['declaredFiles'] = [
        'manifest.json',
        'scenarios.json',
        'manifest.json',
      ],
    );
    expect(
      () => harnessFor(duplicateAllowlist.base).run(
        fixtureRoot: duplicateAllowlist.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.inputRejected),
    );

    final extra = fixtureCopy(addExtraFile: true);
    expect(
      () => harnessFor(extra.base).run(
        fixtureRoot: extra.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.inputRejected),
    );

    final corrupt = fixtureCopy(corruptScenarios: true);
    expect(
      () => harnessFor(corrupt.base).run(
        fixtureRoot: corrupt.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.inputRejected),
    );

    final unknown = fixtureCopy(mutateScenarios: (document) {
      caseById(document, 'active-core-accept')['id'] = 'future-case';
    });
    expect(
      () => harnessFor(unknown.base).run(
        fixtureRoot: unknown.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.inputRejected),
    );
  });

  test('paths, non-empty output, production roots, and links are rejected', () {
    final harness = harnessFor(sourceFixtureBase);
    expect(
      () => harness.run(
        fixtureRoot: repositoryRoot,
        outputRoot: output().path,
      ),
      _failure(FailureClass.pathRejected),
    );
    expect(
      () => harness.run(
        fixtureRoot: golden,
        outputRoot: sourceFixtureBase,
      ),
      _failure(FailureClass.pathRejected),
    );

    final nonEmpty = output();
    File('${nonEmpty.path}${Platform.pathSeparator}existing')
        .writeAsStringSync('x');
    expect(
      () => harness.run(fixtureRoot: golden, outputRoot: nonEmpty.path),
      _failure(FailureClass.pathRejected),
    );

    final copy = fixtureCopy();
    final scenarioPath =
        '${copy.fixture}${Platform.pathSeparator}scenarios.json';
    File(scenarioPath).deleteSync();
    try {
      Link(scenarioPath).createSync(
        '$golden${Platform.pathSeparator}scenarios.json',
      );
    } on FileSystemException {
      markTestSkipped('platform cannot create a fixture link');
      return;
    }
    expect(
      () => harnessFor(copy.base).run(
        fixtureRoot: copy.fixture,
        outputRoot: output().path,
      ),
      _failure(FailureClass.pathRejected),
    );
  });
}

Matcher _failure(FailureClass expected) => throwsA(
      isA<HarnessFailure>().having(
        (failure) => failure.failureClass,
        'failureClass',
        expected,
      ),
    );

Matcher _failureMessage(String message) => throwsA(
      isA<HarnessFailure>()
          .having(
            (failure) => failure.failureClass,
            'failureClass',
            FailureClass.inputRejected,
          )
          .having((failure) => failure.message, 'message', message),
    );

String _canonicalDigestForTest(Object? value) => sha256
    .convert(utf8.encode(jsonEncode(_canonicalizeForTest(value))))
    .toString();

Object? _canonicalizeForTest(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalizeForTest(value[key])};
  }
  if (value is List) return value.map(_canonicalizeForTest).toList();
  return value;
}

class _FixtureCopy {
  const _FixtureCopy(this.base, this.fixture);
  final String base;
  final String fixture;
}
