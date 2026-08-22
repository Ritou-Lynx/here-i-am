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
