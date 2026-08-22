import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/workbench_ai/artifacts/artifact_contracts.dart';

void main() {
  group('ContentBundlePlan', () {
    test('normal fixture describes one atomic knowledge-base bundle', () {
      final plan = _contentBundle('normal_content_bundle.json');

      expect(validateContentBundlePlan(plan), isEmpty);
      expect(plan.artifacts, hasLength(2));
      expect(plan.cards, hasLength(2));
      expect(plan.boardItems, hasLength(2));
      expect(plan.groups, hasLength(1));
      expect(plan.edges, hasLength(1));
      expect(plan.cards.first.cardKind, CardKind.taskArtifact);
      expect(plan.sources.single.mediaType, SourceMediaType.web);
    });

    test('JSON round-trip keeps references valid', () {
      final original = _contentBundle('normal_content_bundle.json');
      final decoded = ContentBundlePlan.fromJson(original.toJson());

      expect(validateContentBundlePlan(decoded), isEmpty);
      expect(decoded.bundleId, original.bundleId);
      expect(decoded.promotions.single.taskArtifactId, 'task_artifact_001');
      expect(decoded.batch.idempotencyKey, original.batch.idempotencyKey);
    });

    test('promotion requires the same explicit authorization as the batch', () {
      final json = _json('normal_content_bundle.json');
      final promotion = (json['promotions'] as List).single as Map;
      promotion['authorization_id'] = 'different_authorization';
      final issues = validateContentBundlePlan(
        ContentBundlePlan.fromJson(json),
      );

      expect(_codes(issues), contains('promotion_authorization_mismatch'));
    });

    test('dangling BoardItem and promotion references fail closed', () {
      final json = _json('normal_content_bundle.json');
      final item = (json['board_items'] as List).first as Map;
      item['card_id'] = 'missing_card';
      final promotion = (json['promotions'] as List).single as Map;
      promotion['source_version_id'] = 'missing_version';
      final issues = validateContentBundlePlan(
        ContentBundlePlan.fromJson(json),
      );

      expect(
        _codes(issues),
        containsAll(['item_card_missing', 'promotion_reference_missing']),
      );
    });

    test('every write operation carries an inverse', () {
      final json = _json('normal_content_bundle.json');
      final operation = (json['batch']['operations'] as List).first as Map;
      operation.remove('inverse');
      final issues = validateContentBundlePlan(
        ContentBundlePlan.fromJson(json),
      );

      expect(_codes(issues), contains('operation_inverse_required'));
    });

    test('operation target and structured inverse must match the plan entity',
        () {
      final json = _json('normal_content_bundle.json');
      final operation = (json['batch']['operations'] as List).first as Map;
      operation['entity_id'] = 'missing_source';
      final inverse = operation['inverse'] as Map;
      inverse['entity_id'] = 'different_source';
      inverse['kind'] = 'create';
      final issues =
          validateContentBundlePlan(ContentBundlePlan.fromJson(json));

      expect(
        _codes(issues),
        containsAll([
          'operation_entity_missing',
          'operation_inverse_target_mismatch',
          'operation_inverse_kind_mismatch',
        ]),
      );
    });

    test('hard delete operation is not part of the contract', () {
      final json = _json('normal_content_bundle.json');
      final operation = (json['batch']['operations'] as List).first as Map;
      operation['kind'] = 'delete';

      expect(
        () => ContentBundlePlan.fromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('hard delete inverse is not part of the contract', () {
      final json = _json('normal_content_bundle.json');
      final operation = (json['batch']['operations'] as List).first as Map;
      final inverse = operation['inverse'] as Map;
      inverse['kind'] = 'delete';

      expect(
        () => ContentBundlePlan.fromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('arbitrary non-empty inverse map cannot masquerade as recovery', () {
      final json = _json('normal_content_bundle.json');
      final operation = (json['batch']['operations'] as List).first as Map;
      operation['inverse'] = {'arbitrary': true};

      expect(
        () => ContentBundlePlan.fromJson(json),
        throwsA(anyOf(isA<TypeError>(), isA<ArgumentError>())),
      );
    });

    test('update inverse must preserve the previous state', () {
      final json = _json('normal_content_bundle.json');
      final operation = (json['batch']['operations'] as List).first as Map;
      operation['kind'] = 'update';
      final inverse = operation['inverse'] as Map;
      inverse['kind'] = 'update';
      inverse.remove('payload');
      final issues =
          validateContentBundlePlan(ContentBundlePlan.fromJson(json));

      expect(
        _codes(issues),
        contains('operation_inverse_previous_state_required'),
      );
    });

    test('idempotency key and conflict guard are mandatory', () {
      final json = _json('normal_content_bundle.json');
      final batch = json['batch'] as Map;
      batch['idempotency_key'] = '';
      batch['expected_state_hash'] = 'not-a-sha';
      final issues = validateContentBundlePlan(
        ContentBundlePlan.fromJson(json),
      );

      expect(
        _codes(issues),
        containsAll([
          'idempotency_key_required',
          'expected_state_hash_invalid',
        ]),
      );
    });
  });

  group('artifact staging and recovery', () {
    test('over-limit artifact is rejected before product binding', () {
      final manifest = ArtifactManifest.fromJson(
        _json('over_limit_manifest.json'),
      );

      expect(
        _codes(validateArtifactManifest(manifest)),
        contains('artifact_bytes_exceeded'),
      );
    });

    test('path traversal object reference is rejected', () {
      final manifest = ArtifactManifest.fromJson(
        _json('path_traversal_manifest.json'),
      );

      expect(
        _codes(validateArtifactManifest(manifest)),
        contains('unsafe_staged_object_ref'),
      );
    });

    test('partial hash failure has cleanup plan and no product binding', () {
      final journal = ArtifactCommitJournal.fromJson(
        _json('partial_failure_journal.json'),
      );

      expect(validateCommitJournal(journal), isEmpty);
      expect(journal.phase, ArtifactCommitPhase.recoveryRequired);
      expect(journal.boundArtifactIds, isEmpty);
      expect(journal.recovery!.stagedObjectRefsToDelete, hasLength(2));
    });

    test(
      'commit is atomic only when every staged artifact is verified and bound',
      () {
        const journal = ArtifactCommitJournal(
          batchId: 'batch_partial_commit',
          phase: ArtifactCommitPhase.committed,
          stagedArtifactIds: ['a', 'b'],
          verifiedArtifactIds: ['a'],
          boundArtifactIds: ['a'],
        );

        expect(
          _codes(validateCommitJournal(journal)),
          contains('atomic_binding_incomplete'),
        );
      },
    );

    test('rollback cannot claim live bound artifacts', () {
      const journal = ArtifactCommitJournal(
        batchId: 'batch_rollback',
        phase: ArtifactCommitPhase.rolledBack,
        stagedArtifactIds: ['a'],
        verifiedArtifactIds: ['a'],
        boundArtifactIds: ['a'],
      );

      expect(
        _codes(validateCommitJournal(journal)),
        contains('rollback_left_bound_artifacts'),
      );
    });

    test('receipt preserves idempotency key and inverse operations', () {
      final plan = _contentBundle('normal_content_bundle.json');
      final receipt = OperationReceipt(
        receiptId: 'receipt_001',
        batchId: plan.batch.batchId,
        idempotencyKey: plan.batch.idempotencyKey,
        status: OperationReceiptStatus.committed,
        beforeStateHash: plan.batch.expectedStateHash,
        afterStateHash:
            'abababababababababababababababababababababababababababababababab',
        committedOperationIds:
            plan.batch.operations.map((value) => value.operationId).toList(),
        inverseOperations: plan.batch.operations.reversed.toList(),
        occurredAt: DateTime.utc(2026, 8, 22, 12),
      );

      expect(receipt.toJson()['idempotency_key'], plan.batch.idempotencyKey);
      expect(receipt.toJson()['inverse_operations'], hasLength(3));
    });

    test('durable receipt round-trips for replay after restart', () {
      final plan = _contentBundle('normal_content_bundle.json');
      final receipt = OperationReceipt(
        receiptId: 'receipt_restart_001',
        batchId: plan.batch.batchId,
        idempotencyKey: plan.batch.idempotencyKey,
        status: OperationReceiptStatus.replayed,
        beforeStateHash: plan.batch.expectedStateHash,
        afterStateHash:
            'abababababababababababababababababababababababababababababababab',
        committedOperationIds:
            plan.batch.operations.map((value) => value.operationId).toList(),
        inverseOperations: plan.batch.operations.reversed.toList(),
        occurredAt: DateTime.utc(2026, 8, 22, 12),
      );

      final restored = OperationReceipt.fromJson(receipt.toJson());
      expect(restored.status, OperationReceiptStatus.replayed);
      expect(restored.idempotencyKey, plan.batch.idempotencyKey);
      expect(restored.inverseOperations, hasLength(3));
    });
  });

  group('HTML raw/runtime security boundary', () {
    test('normal fixture keeps original HTML and runtime bundle separate', () {
      final bundle = _contentBundle(
        'normal_content_bundle.json',
      ).htmlRuntimeBundles.single;

      expect(bundle.rawArtifactId, isNot(bundle.runtimeArtifactId));
      expect(bundle.auditStatus, HtmlAuditStatus.accepted);
      expect(validateHtmlRuntimeBundle(bundle), isEmpty);
    });

    test('runtime bundle cannot cross-replace raw and runtime manifests', () {
      final json = _json('normal_content_bundle.json');
      final bundle = (json['html_runtime_bundles'] as List).single as Map;
      final rawId = bundle['raw_artifact_id'];
      bundle['raw_artifact_id'] = bundle['runtime_artifact_id'];
      bundle['runtime_artifact_id'] = rawId;

      final issues =
          validateContentBundlePlan(ContentBundlePlan.fromJson(json));
      expect(
        _codes(issues),
        containsAll([
          'html_raw_manifest_mismatch',
          'html_runtime_manifest_mismatch',
          'html_runtime_object_ref_mismatch',
          'html_runtime_hash_mismatch',
        ]),
      );
    });

    test('dangerous first CSP directive cannot be hidden by safe duplicate',
        () {
      const bundle = HtmlRuntimeBundle(
        rawArtifactId: 'raw',
        runtimeArtifactId: 'runtime',
        runtimeObjectRef: 'objects/html/runtime.zip',
        runtimeSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        auditStatus: HtmlAuditStatus.accepted,
        policy: HtmlSandboxPolicy(
          policyVersion: 1,
          csp:
              "default-src *; default-src 'none'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'none'; connect-src 'none'; script-src 'none'",
        ),
      );

      expect(
        _codes(validateHtmlRuntimeBundle(bundle)),
        containsAll(['html_csp_duplicate_directive', 'html_csp_unsafe']),
      );
    });

    test(
      'dangerous capabilities, CSP, network, file and bridge are rejected',
      () {
        final bundle = HtmlRuntimeBundle.fromJson(
          _json('dangerous_html_bundle.json'),
        );
        final codes = _codes(validateHtmlRuntimeBundle(bundle));

        expect(
          codes,
          containsAll([
            'unsafe_html_runtime_object_ref',
            'html_forbidden_capability',
            'html_csp_unsafe',
            'html_network_origin_unsafe',
            'html_bridge_method_unsupported',
            'html_script_hashes_invalid',
          ]),
        );
      },
    );

    test(
      'raw inspection reports capabilities but never claims sanitization',
      () {
        const raw = '''
        <meta http-equiv="refresh" content="0;url=file://C:/private">
        <iframe src="http://127.0.0.1:9000"></iframe>
        <form action="https://example.com/upload"></form>
        <a download href="javascript:window.open('x')">x</a>
        <script>window.chrome.webview.postMessage('all')</script>
      ''';

        expect(
          inspectRawHtmlCapabilities(raw),
          containsAll([
            'script',
            'iframe',
            'form',
            'meta_refresh',
            'javascript_url',
            'file_url',
            'localhost',
            'popup',
            'download',
            'webview_bridge',
            'external_network',
          ]),
        );
      },
    );

    test('network grant requires exact public HTTPS origins', () {
      const bundle = HtmlRuntimeBundle(
        rawArtifactId: 'raw',
        runtimeArtifactId: 'runtime',
        runtimeObjectRef: 'objects/html/runtime.zip',
        runtimeSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        auditStatus: HtmlAuditStatus.accepted,
        policy: HtmlSandboxPolicy(
          policyVersion: 1,
          csp:
              "default-src 'none'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'none'",
          capabilities: {HtmlRuntimeCapability.network},
          allowedNetworkOrigins: ['https://api.example.com/v1'],
        ),
      );

      expect(
        _codes(validateHtmlRuntimeBundle(bundle)),
        contains('html_network_origin_unsafe'),
      );
    });

    test('explicit exact-origin network grant can pass policy validation', () {
      const bundle = HtmlRuntimeBundle(
        rawArtifactId: 'raw',
        runtimeArtifactId: 'runtime',
        runtimeObjectRef: 'objects/html/runtime.zip',
        runtimeSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        auditStatus: HtmlAuditStatus.accepted,
        policy: HtmlSandboxPolicy(
          policyVersion: 1,
          csp:
              "default-src 'none'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'none'; connect-src https://api.example.com; script-src 'none'",
          capabilities: {HtmlRuntimeCapability.network},
          allowedNetworkOrigins: ['https://api.example.com'],
        ),
      );

      expect(validateHtmlRuntimeBundle(bundle), isEmpty);
    });

    test('unconventional numeric hosts are rejected before DNS', () {
      for (final origin in const [
        'https://2130706433',
        'https://127.1',
        'https://0x7f000001',
        'https://0177.0.0.1',
        'https://127.0x0.0.1',
      ]) {
        final bundle = _networkBundle(origin);
        expect(
          _codes(validateHtmlRuntimeBundle(bundle)),
          contains('html_network_origin_unsafe'),
          reason: origin,
        );
      }
    });
  });

  group('promotion and binding relationships', () {
    test('promoted manifest must match the authoritative source version', () {
      final json = _json('normal_content_bundle.json');
      const otherHash =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      const otherRef = 'objects/html/raw/$otherHash.html';
      final version = (json['source_versions'] as List).single as Map;
      version['content_hash'] = otherHash;
      version['object_ref'] = otherRef;
      final source = (json['sources'] as List).single as Map;
      source['content_hash'] = otherHash;
      source['object_ref'] = otherRef;
      final issues =
          validateContentBundlePlan(ContentBundlePlan.fromJson(json));

      expect(_codes(issues), contains('promotion_manifest_version_mismatch'));
    });

    test('promotion source version must belong to the promoted source', () {
      final json = _json('normal_content_bundle.json');
      final promotion = (json['promotions'] as List).single as Map;
      promotion['source_id'] = 'source_other';
      (json['sources'] as List).add(_otherSource());
      final issues =
          validateContentBundlePlan(ContentBundlePlan.fromJson(json));

      expect(_codes(issues), contains('promotion_source_version_mismatch'));
    });

    test('promotion card and artifact binding must align with the source', () {
      final json = _json('normal_content_bundle.json');
      (json['sources'] as List).add(_otherSource());
      final card = (json['cards'] as List).first as Map;
      card['source_id'] = 'source_other';
      final artifact = (json['artifacts'] as List).first as Map;
      final binding = artifact['binding'] as Map;
      binding['task_artifact_id'] = 'different_task_artifact';
      final issues =
          validateContentBundlePlan(ContentBundlePlan.fromJson(json));

      expect(
        _codes(issues),
        containsAll([
          'promotion_card_source_mismatch',
          'artifact_binding_card_source_mismatch',
          'promotion_artifact_binding_mismatch',
        ]),
      );
    });

    test('binding source version and board item must align with source/card',
        () {
      final json = _json('normal_content_bundle.json');
      (json['sources'] as List).add(_otherSource());
      final artifact = (json['artifacts'] as List)[1] as Map;
      final binding = artifact['binding'] as Map;
      binding['source_id'] = 'source_other';
      binding['card_id'] = 'card_summary_001';
      binding['board_item_ids'] = ['item_artifact_001'];
      final issues =
          validateContentBundlePlan(ContentBundlePlan.fromJson(json));

      expect(
        _codes(issues),
        containsAll([
          'artifact_binding_source_version_mismatch',
          'artifact_binding_card_source_mismatch',
          'artifact_binding_item_card_mismatch',
        ]),
      );
    });
  });
}

ContentBundlePlan _contentBundle(String name) =>
    ContentBundlePlan.fromJson(_json(name));

Map<String, dynamic> _json(String name) {
  final file = File('test/domain/workbench_ai/artifacts/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Set<String> _codes(List<ArtifactContractIssue> issues) =>
    issues.map((value) => value.code).toSet();

HtmlRuntimeBundle _networkBundle(String origin) => HtmlRuntimeBundle(
      rawArtifactId: 'raw',
      runtimeArtifactId: 'runtime',
      runtimeObjectRef: 'objects/html/runtime.zip',
      runtimeSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      auditStatus: HtmlAuditStatus.accepted,
      policy: HtmlSandboxPolicy(
        policyVersion: 1,
        csp:
            "default-src 'none'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'none'; connect-src $origin; script-src 'none'",
        capabilities: const {HtmlRuntimeCapability.network},
        allowedNetworkOrigins: [origin],
      ),
    );

Map<String, dynamic> _otherSource() => {
      'source_id': 'source_other',
      'media_type': 'web',
      'title': 'Other source',
      'owner_space': 'user',
      'origin': 'generate',
      'created_at': '2026-08-22T12:00:00Z',
    };
