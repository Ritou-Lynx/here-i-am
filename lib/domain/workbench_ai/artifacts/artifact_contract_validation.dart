library;

import 'content_bundle_plan.dart';
import 'generated_artifact.dart';
import 'html_artifact_contract.dart';

class ArtifactContractIssue {
  const ArtifactContractIssue(this.code, {this.ref, this.detail});

  final String code;
  final String? ref;
  final String? detail;

  @override
  String toString() =>
      [code, if (ref != null) ref, if (detail != null) detail].join(':');
}

class ArtifactBudget {
  const ArtifactBudget({
    this.maxArtifactCount = 64,
    this.maxArtifactBytes = 20 * 1024 * 1024,
    this.maxBundleBytes = 100 * 1024 * 1024,
    this.maxOperations = 512,
  });

  final int maxArtifactCount;
  final int maxArtifactBytes;
  final int maxBundleBytes;
  final int maxOperations;
}

final RegExp _sha256 = RegExp(r'^[a-f0-9]{64}$');
final RegExp _safeObjectRef = RegExp(r'^[a-z0-9][a-z0-9._/-]*$');

List<ArtifactContractIssue> validateContentBundlePlan(
  ContentBundlePlan plan, {
  ArtifactBudget budget = const ArtifactBudget(),
}) {
  final issues = <ArtifactContractIssue>[];
  if (plan.schemaVersion != 1) {
    issues.add(const ArtifactContractIssue('unsupported_schema_version'));
  }
  if (plan.artifacts.length > budget.maxArtifactCount) {
    issues.add(const ArtifactContractIssue('artifact_count_exceeded'));
  }
  if (plan.batch.operations.length > budget.maxOperations) {
    issues.add(const ArtifactContractIssue('operation_count_exceeded'));
  }
  if (plan.batch.idempotencyKey.trim().isEmpty) {
    issues.add(const ArtifactContractIssue('idempotency_key_required'));
  }
  if (!_sha256.hasMatch(plan.batch.expectedStateHash)) {
    issues.add(const ArtifactContractIssue('expected_state_hash_invalid'));
  }

  final artifactIds = <String>{};
  final artifactsById = <String, GeneratedArtifact>{};
  var totalBytes = 0;
  for (final artifact in plan.artifacts) {
    final manifest = artifact.manifest;
    totalBytes += manifest.sizeBytes;
    if (!artifactIds.add(manifest.artifactId)) {
      issues.add(
        ArtifactContractIssue(
          'duplicate_artifact_id',
          ref: manifest.artifactId,
        ),
      );
    } else {
      artifactsById[manifest.artifactId] = artifact;
    }
    if (artifact.binding.artifactId != manifest.artifactId) {
      issues.add(
        ArtifactContractIssue(
          'artifact_binding_mismatch',
          ref: manifest.artifactId,
        ),
      );
    }
    issues.addAll(validateArtifactManifest(manifest, budget: budget));
  }
  if (totalBytes > budget.maxBundleBytes) {
    issues.add(const ArtifactContractIssue('bundle_bytes_exceeded'));
  }

  void duplicates(Iterable<String> ids, String code) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) issues.add(ArtifactContractIssue(code, ref: id));
    }
  }

  duplicates(
    plan.sources.map((value) => value.sourceId),
    'duplicate_source_id',
  );
  duplicates(
    plan.sourceVersions.map((value) => value.versionId),
    'duplicate_source_version_id',
  );
  duplicates(plan.cards.map((value) => value.cardId), 'duplicate_card_id');
  duplicates(plan.boards.map((value) => value.boardId), 'duplicate_board_id');
  duplicates(
    plan.boardItems.map((value) => value.itemId),
    'duplicate_board_item_id',
  );
  duplicates(plan.groups.map((value) => value.groupId), 'duplicate_group_id');
  duplicates(plan.edges.map((value) => value.edgeId), 'duplicate_edge_id');
  duplicates(
    plan.promotions.map((value) => value.promotionId),
    'duplicate_promotion_id',
  );
  duplicates(
    plan.batch.operations.map((value) => value.operationId),
    'duplicate_operation_id',
  );

  final sourceIds = plan.sources.map((value) => value.sourceId).toSet();
  final versionIds =
      plan.sourceVersions.map((value) => value.versionId).toSet();
  final cardIds = plan.cards.map((value) => value.cardId).toSet();
  final boardIds = plan.boards.map((value) => value.boardId).toSet();
  final itemIds = plan.boardItems.map((value) => value.itemId).toSet();
  final groupIds = plan.groups.map((value) => value.groupId).toSet();
  final sourcesById = {for (final value in plan.sources) value.sourceId: value};
  final versionsById = {
    for (final value in plan.sourceVersions) value.versionId: value,
  };
  final itemsById = {for (final value in plan.boardItems) value.itemId: value};
  final cardsById = {for (final value in plan.cards) value.cardId: value};

  for (final artifact in plan.artifacts) {
    final binding = artifact.binding;
    if (binding.sourceId != null && !sourceIds.contains(binding.sourceId)) {
      issues.add(ArtifactContractIssue(
        'artifact_binding_source_missing',
        ref: artifact.manifest.artifactId,
      ));
    }
    if (binding.sourceVersionId != null &&
        !versionIds.contains(binding.sourceVersionId)) {
      issues.add(ArtifactContractIssue(
        'artifact_binding_version_missing',
        ref: artifact.manifest.artifactId,
      ));
    }
    if (binding.cardId != null && !cardIds.contains(binding.cardId)) {
      issues.add(ArtifactContractIssue(
        'artifact_binding_card_missing',
        ref: artifact.manifest.artifactId,
      ));
    }
    if (binding.boardItemIds.any((value) => !itemIds.contains(value))) {
      issues.add(ArtifactContractIssue(
        'artifact_binding_item_missing',
        ref: artifact.manifest.artifactId,
      ));
    }
    final boundVersion = binding.sourceVersionId == null
        ? null
        : versionsById[binding.sourceVersionId];
    final boundCard = binding.cardId == null ? null : cardsById[binding.cardId];
    if (binding.sourceVersionId != null &&
        (binding.sourceId == null ||
            boundVersion == null ||
            boundVersion.sourceId != binding.sourceId)) {
      issues.add(ArtifactContractIssue(
        'artifact_binding_source_version_mismatch',
        ref: artifact.manifest.artifactId,
      ));
    }
    if (binding.cardId != null &&
        (binding.sourceId == null ||
            boundCard == null ||
            boundCard.sourceId != binding.sourceId)) {
      issues.add(ArtifactContractIssue(
        'artifact_binding_card_source_mismatch',
        ref: artifact.manifest.artifactId,
      ));
    }
    if (binding.cardId != null &&
        binding.boardItemIds.any(
          (value) =>
              itemsById[value] != null &&
              itemsById[value]!.cardId != binding.cardId,
        )) {
      issues.add(ArtifactContractIssue(
        'artifact_binding_item_card_mismatch',
        ref: artifact.manifest.artifactId,
      ));
    }
  }

  for (final version in plan.sourceVersions) {
    if (!sourceIds.contains(version.sourceId)) {
      issues.add(
        ArtifactContractIssue(
          'source_version_source_missing',
          ref: version.versionId,
        ),
      );
    }
  }
  for (final source in plan.sources) {
    final currentVersion = source.currentVersionId == null
        ? null
        : versionsById[source.currentVersionId];
    if (source.currentVersionId != null &&
        (currentVersion == null ||
            currentVersion.sourceId != source.sourceId)) {
      issues.add(ArtifactContractIssue(
        'source_current_version_missing',
        ref: source.sourceId,
      ));
    }
    if (currentVersion != null &&
        ((source.contentHash != null &&
                source.contentHash != currentVersion.contentHash) ||
            (source.objectRef != null &&
                source.objectRef != currentVersion.objectRef))) {
      issues.add(ArtifactContractIssue(
        'source_current_version_content_mismatch',
        ref: source.sourceId,
      ));
    }
  }
  for (final card in plan.cards) {
    if (card.sourceId != null && !sourceIds.contains(card.sourceId)) {
      issues.add(
        ArtifactContractIssue('card_source_missing', ref: card.cardId),
      );
    }
  }
  for (final item in plan.boardItems) {
    if (!boardIds.contains(item.boardId)) {
      issues.add(ArtifactContractIssue('item_board_missing', ref: item.itemId));
    }
    if (!cardIds.contains(item.cardId)) {
      issues.add(ArtifactContractIssue('item_card_missing', ref: item.itemId));
    }
  }
  for (final group in plan.groups) {
    if (!boardIds.contains(group.boardId)) {
      issues.add(
        ArtifactContractIssue('group_board_missing', ref: group.groupId),
      );
    }
  }
  for (final member in plan.groupMembers) {
    if (!groupIds.contains(member.groupId)) {
      issues.add(
        ArtifactContractIssue(
          'group_member_group_missing',
          ref: member.groupId,
        ),
      );
    }
    if (!itemIds.contains(member.itemId)) {
      issues.add(
        ArtifactContractIssue('group_member_item_missing', ref: member.itemId),
      );
    }
    final matchingGroups =
        plan.groups.where((value) => value.groupId == member.groupId);
    final group = matchingGroups.isEmpty ? null : matchingGroups.first;
    final item = itemsById[member.itemId];
    if (group != null && item != null && group.boardId != item.boardId) {
      issues.add(ArtifactContractIssue(
        'group_member_board_mismatch',
        ref: member.itemId,
      ));
    }
  }
  for (final edge in plan.edges) {
    if (!boardIds.contains(edge.boardId) ||
        !itemIds.contains(edge.fromItemId) ||
        !itemIds.contains(edge.toItemId)) {
      issues.add(
        ArtifactContractIssue('edge_reference_missing', ref: edge.edgeId),
      );
    } else if (itemsById[edge.fromItemId]!.boardId != edge.boardId ||
        itemsById[edge.toItemId]!.boardId != edge.boardId) {
      issues.add(ArtifactContractIssue(
        'edge_board_mismatch',
        ref: edge.edgeId,
      ));
    }
  }
  for (final promotion in plan.promotions) {
    if (promotion.authorizationId != plan.batch.authorizationId) {
      issues.add(
        ArtifactContractIssue(
          'promotion_authorization_mismatch',
          ref: promotion.promotionId,
        ),
      );
    }
    if (!artifactIds.contains(promotion.artifactId) ||
        !sourceIds.contains(promotion.sourceId) ||
        !versionIds.contains(promotion.sourceVersionId) ||
        !cardIds.contains(promotion.cardId)) {
      issues.add(
        ArtifactContractIssue(
          'promotion_reference_missing',
          ref: promotion.promotionId,
        ),
      );
    }
    final promotedArtifact = artifactsById[promotion.artifactId];
    final promotedVersion = versionsById[promotion.sourceVersionId];
    final promotedCard = cardsById[promotion.cardId];
    if (promotedVersion != null &&
        promotedVersion.sourceId != promotion.sourceId) {
      issues.add(ArtifactContractIssue(
        'promotion_source_version_mismatch',
        ref: promotion.promotionId,
      ));
    }
    if (promotedArtifact != null &&
        promotedVersion != null &&
        (promotedArtifact.manifest.sha256 != promotedVersion.contentHash ||
            promotedArtifact.manifest.objectRef != promotedVersion.objectRef)) {
      issues.add(ArtifactContractIssue(
        'promotion_manifest_version_mismatch',
        ref: promotion.promotionId,
      ));
    }
    if (promotedCard != null && promotedCard.sourceId != promotion.sourceId) {
      issues.add(ArtifactContractIssue(
        'promotion_card_source_mismatch',
        ref: promotion.promotionId,
      ));
    }
    final binding = promotedArtifact?.binding;
    if (binding != null &&
        (binding.status != ArtifactBindingStatus.promoted ||
            binding.taskArtifactId != promotion.taskArtifactId ||
            binding.sourceId != promotion.sourceId ||
            binding.sourceVersionId != promotion.sourceVersionId ||
            binding.cardId != promotion.cardId)) {
      issues.add(ArtifactContractIssue(
        'promotion_artifact_binding_mismatch',
        ref: promotion.promotionId,
      ));
    }
  }
  final promotedArtifactIds =
      plan.promotions.map((value) => value.artifactId).toSet();
  for (final artifact in plan.artifacts) {
    if (artifact.binding.status == ArtifactBindingStatus.promoted &&
        !promotedArtifactIds.contains(artifact.manifest.artifactId)) {
      issues.add(ArtifactContractIssue(
        'promoted_binding_without_promotion',
        ref: artifact.manifest.artifactId,
      ));
    }
  }
  for (final html in plan.htmlRuntimeBundles) {
    final rawArtifact = artifactsById[html.rawArtifactId];
    final runtimeArtifact = artifactsById[html.runtimeArtifactId];
    if (rawArtifact == null || runtimeArtifact == null) {
      issues.add(
        ArtifactContractIssue(
          'html_artifact_reference_missing',
          ref: html.rawArtifactId,
        ),
      );
    } else {
      issues.addAll(
        validateHtmlRuntimeBundleManifests(
          html,
          rawManifest: rawArtifact.manifest,
          runtimeManifest: runtimeArtifact.manifest,
        ),
      );
    }
    issues.addAll(validateHtmlRuntimeBundle(html));
  }
  final entityTargets = <String, Set<String>>{
    'artifact': artifactIds,
    'source': sourcesById.keys.toSet(),
    'source_version': versionIds,
    'card': cardIds,
    'board': boardIds,
    'board_item': itemIds,
    'group': groupIds,
    'edge': plan.edges.map((value) => value.edgeId).toSet(),
    'promotion': plan.promotions.map((value) => value.promotionId).toSet(),
    'html_runtime_bundle':
        plan.htmlRuntimeBundles.map((value) => value.runtimeArtifactId).toSet(),
  };
  for (final operation in plan.batch.operations) {
    final targets = entityTargets[operation.entityType];
    if (targets == null) {
      issues.add(ArtifactContractIssue(
        'operation_entity_type_unsupported',
        ref: operation.operationId,
      ));
    } else if (!targets.contains(operation.entityId)) {
      issues.add(ArtifactContractIssue(
        'operation_entity_missing',
        ref: operation.operationId,
      ));
    }
    final inverse = operation.inverse;
    if (inverse == null) {
      issues.add(
        ArtifactContractIssue(
          'operation_inverse_required',
          ref: operation.operationId,
        ),
      );
      continue;
    }
    if (inverse.entityType != operation.entityType ||
        inverse.entityId != operation.entityId) {
      issues.add(ArtifactContractIssue(
        'operation_inverse_target_mismatch',
        ref: operation.operationId,
      ));
    }
    final expectedInverseKind = switch (operation.kind) {
      DomainOperationKind.create ||
      DomainOperationKind.bind ||
      DomainOperationKind.promote =>
        DomainOperationKind.retract,
      DomainOperationKind.update ||
      DomainOperationKind.retract =>
        DomainOperationKind.update,
    };
    if (inverse.kind != expectedInverseKind) {
      issues.add(ArtifactContractIssue(
        'operation_inverse_kind_mismatch',
        ref: operation.operationId,
      ));
    }
    if (inverse.kind == DomainOperationKind.update && inverse.payload.isEmpty) {
      issues.add(ArtifactContractIssue(
        'operation_inverse_previous_state_required',
        ref: operation.operationId,
      ));
    }
  }
  return issues;
}

List<ArtifactContractIssue> validateArtifactManifest(
  ArtifactManifest manifest, {
  ArtifactBudget budget = const ArtifactBudget(),
}) {
  final issues = <ArtifactContractIssue>[];
  if (manifest.sizeBytes < 0 || manifest.sizeBytes > budget.maxArtifactBytes) {
    issues.add(
      ArtifactContractIssue(
        'artifact_bytes_exceeded',
        ref: manifest.artifactId,
      ),
    );
  }
  if (!_sha256.hasMatch(manifest.sha256)) {
    issues.add(
      ArtifactContractIssue(
        'artifact_sha256_invalid',
        ref: manifest.artifactId,
      ),
    );
  }
  if ((manifest.kind == GeneratedArtifactKind.image &&
          !manifest.mimeType.startsWith('image/')) ||
      (manifest.kind == GeneratedArtifactKind.html &&
          manifest.mimeType != 'text/html' &&
          manifest.mimeType != 'application/vnd.hereiam.html-runtime+zip')) {
    issues.add(ArtifactContractIssue(
      'artifact_mime_kind_mismatch',
      ref: manifest.artifactId,
    ));
  }
  if (!_isSafeObjectRef(manifest.stagedObjectRef)) {
    issues.add(
      ArtifactContractIssue(
        'unsafe_staged_object_ref',
        ref: manifest.artifactId,
      ),
    );
  }
  if (!_isSafeObjectRef(manifest.objectRef)) {
    issues.add(ArtifactContractIssue(
      'unsafe_artifact_object_ref',
      ref: manifest.artifactId,
    ));
  } else if (!manifest.objectRef.contains(manifest.sha256)) {
    issues.add(ArtifactContractIssue(
      'artifact_object_ref_hash_mismatch',
      ref: manifest.artifactId,
    ));
  }
  return issues;
}

List<ArtifactContractIssue> validateCommitJournal(
  ArtifactCommitJournal journal,
) {
  final issues = <ArtifactContractIssue>[];
  final staged = journal.stagedArtifactIds.toSet();
  final verified = journal.verifiedArtifactIds.toSet();
  final bound = journal.boundArtifactIds.toSet();
  if (!staged.containsAll(verified)) {
    issues.add(const ArtifactContractIssue('verified_without_staging'));
  }
  if (!verified.containsAll(bound)) {
    issues.add(const ArtifactContractIssue('bound_without_hash_verification'));
  }
  if (journal.phase == ArtifactCommitPhase.committed &&
      (staged.length != verified.length || verified.length != bound.length)) {
    issues.add(const ArtifactContractIssue('atomic_binding_incomplete'));
  }
  if (journal.phase == ArtifactCommitPhase.recoveryRequired &&
      (journal.failureCode == null || journal.recovery == null)) {
    issues.add(const ArtifactContractIssue('recovery_details_required'));
  }
  if (journal.phase != ArtifactCommitPhase.recoveryRequired &&
      journal.recovery != null) {
    issues.add(const ArtifactContractIssue('unexpected_recovery_plan'));
  }
  if (journal.phase == ArtifactCommitPhase.rolledBack && bound.isNotEmpty) {
    issues.add(const ArtifactContractIssue('rollback_left_bound_artifacts'));
  }
  if (journal.recovery != null) {
    for (final objectRef in journal.recovery!.stagedObjectRefsToDelete) {
      if (!_isSafeObjectRef(objectRef)) {
        issues.add(
          ArtifactContractIssue('unsafe_recovery_object_ref', ref: objectRef),
        );
      }
    }
  }
  return issues;
}

List<ArtifactContractIssue> validateHtmlRuntimeBundle(
  HtmlRuntimeBundle bundle,
) {
  final issues = <ArtifactContractIssue>[];
  if (bundle.rawArtifactId == bundle.runtimeArtifactId) {
    issues.add(const ArtifactContractIssue('html_raw_runtime_must_differ'));
  }
  if (!_isSafeObjectRef(bundle.runtimeObjectRef)) {
    issues.add(const ArtifactContractIssue('unsafe_html_runtime_object_ref'));
  }
  if (!_sha256.hasMatch(bundle.runtimeSha256)) {
    issues.add(const ArtifactContractIssue('html_runtime_sha256_invalid'));
  }
  if (bundle.auditStatus != HtmlAuditStatus.accepted ||
      bundle.auditFindings.isNotEmpty) {
    issues.add(const ArtifactContractIssue('html_audit_not_clean'));
  }

  final policy = bundle.policy;
  const forbidden = {
    HtmlRuntimeCapability.forms,
    HtmlRuntimeCapability.clipboardWrite,
    HtmlRuntimeCapability.navigation,
    HtmlRuntimeCapability.downloads,
    HtmlRuntimeCapability.popups,
    HtmlRuntimeCapability.fileAccess,
    HtmlRuntimeCapability.localhostAccess,
    HtmlRuntimeCapability.broadBridge,
  };
  if (policy.capabilities.any(forbidden.contains)) {
    issues.add(const ArtifactContractIssue('html_forbidden_capability'));
  }
  final rawCsp = policy.csp;
  final csp = rawCsp.toLowerCase();
  final cspDirectives = <String, List<String>>{};
  final duplicateDirectives = <String>{};
  for (final rawDirective in rawCsp.split(';')) {
    final parts = rawDirective
        .trim()
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      final name = parts.first.toLowerCase();
      if (cspDirectives.containsKey(name)) {
        duplicateDirectives.add(name);
      } else {
        // Browsers honor the first occurrence. Keep it even though every
        // duplicate is rejected below, so validation can never observe a
        // safer last directive than the browser will enforce.
        cspDirectives[name] = parts.skip(1).toList();
      }
    }
  }
  for (final directive in duplicateDirectives) {
    issues.add(ArtifactContractIssue(
      'html_csp_duplicate_directive',
      ref: directive,
    ));
  }
  for (final directive in const [
    'default-src',
    'base-uri',
    'object-src',
    'frame-ancestors',
    'form-action',
  ]) {
    final sources = cspDirectives[directive];
    if (sources == null || sources.length != 1 || sources.single != "'none'") {
      issues.add(
        ArtifactContractIssue('html_csp_directive_missing', ref: directive),
      );
    }
  }
  if (csp.contains("'unsafe-inline'") ||
      csp.contains("'unsafe-eval'") ||
      csp.contains('*') ||
      csp.contains('file:') ||
      csp.contains('localhost') ||
      csp.contains('127.0.0.1') ||
      csp.contains('[::1]')) {
    issues.add(const ArtifactContractIssue('html_csp_unsafe'));
  }
  final networkGranted = policy.capabilities.contains(
    HtmlRuntimeCapability.network,
  );
  if (networkGranted != policy.allowedNetworkOrigins.isNotEmpty) {
    issues.add(
      const ArtifactContractIssue('html_network_declaration_mismatch'),
    );
  }
  for (final origin in policy.allowedNetworkOrigins) {
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        _isPrivateOrLocalHost(uri.host) ||
        origin.contains('*')) {
      issues.add(
        ArtifactContractIssue('html_network_origin_unsafe', ref: origin),
      );
    }
  }
  const supportedBridgeMethods = {
    'report_height',
    'open_stable_ref',
    'emit_user_intent',
  };
  if (policy.allowedBridgeMethods.any(
    (value) => !supportedBridgeMethods.contains(value),
  )) {
    issues.add(const ArtifactContractIssue('html_bridge_method_unsupported'));
  }
  final scriptsGranted = policy.capabilities.contains(
    HtmlRuntimeCapability.scripts,
  );
  if (scriptsGranted != policy.scriptHashes.isNotEmpty ||
      policy.scriptHashes.any(
        (value) => !RegExp(r"^'sha256-[A-Za-z0-9+/]{43}='$").hasMatch(value),
      )) {
    issues.add(const ArtifactContractIssue('html_script_hashes_invalid'));
  }
  final connectSources = cspDirectives['connect-src'] ?? const ["'none'"];
  if (networkGranted) {
    if (!_sameStrings(connectSources, policy.allowedNetworkOrigins)) {
      issues.add(const ArtifactContractIssue('html_csp_network_mismatch'));
    }
  } else if (!_sameStrings(connectSources, const ["'none'"])) {
    issues.add(const ArtifactContractIssue('html_csp_network_mismatch'));
  }
  final scriptSources = cspDirectives['script-src'] ?? const ["'none'"];
  if (scriptsGranted) {
    if (!_sameStrings(scriptSources, policy.scriptHashes)) {
      issues.add(const ArtifactContractIssue('html_csp_script_mismatch'));
    }
  } else if (!_sameStrings(scriptSources, const ["'none'"])) {
    issues.add(const ArtifactContractIssue('html_csp_script_mismatch'));
  }
  return issues;
}

List<ArtifactContractIssue> validateHtmlRuntimeBundleManifests(
  HtmlRuntimeBundle bundle, {
  required ArtifactManifest rawManifest,
  required ArtifactManifest runtimeManifest,
}) {
  final issues = <ArtifactContractIssue>[];
  if (rawManifest.artifactId != bundle.rawArtifactId ||
      runtimeManifest.artifactId != bundle.runtimeArtifactId ||
      rawManifest.artifactId == runtimeManifest.artifactId) {
    issues.add(const ArtifactContractIssue('html_manifest_identity_mismatch'));
  }
  if (rawManifest.kind != GeneratedArtifactKind.html ||
      rawManifest.mimeType != 'text/html') {
    issues.add(const ArtifactContractIssue('html_raw_manifest_mismatch'));
  }
  if (runtimeManifest.kind != GeneratedArtifactKind.html ||
      runtimeManifest.mimeType != 'application/vnd.hereiam.html-runtime+zip') {
    issues.add(const ArtifactContractIssue('html_runtime_manifest_mismatch'));
  }
  if (runtimeManifest.objectRef != bundle.runtimeObjectRef) {
    issues.add(
      const ArtifactContractIssue('html_runtime_object_ref_mismatch'),
    );
  }
  if (runtimeManifest.sha256 != bundle.runtimeSha256) {
    issues.add(const ArtifactContractIssue('html_runtime_hash_mismatch'));
  }
  if (rawManifest.objectRef == runtimeManifest.objectRef) {
    issues.add(
      const ArtifactContractIssue('html_raw_runtime_object_ref_must_differ'),
    );
  }
  return issues;
}

/// Reports capabilities present in authored HTML. It does not rewrite input.
Set<String> inspectRawHtmlCapabilities(String html) {
  final lower = html.toLowerCase();
  final findings = <String>{};
  void detect(String code, Pattern pattern) {
    if (lower.contains(pattern)) findings.add(code);
  }

  detect('script', '<script');
  detect('iframe', '<iframe');
  detect('object_or_embed', '<object');
  detect('object_or_embed', '<embed');
  detect('form', '<form');
  detect('meta_refresh', 'http-equiv="refresh"');
  detect('meta_refresh', "http-equiv='refresh'");
  detect('javascript_url', 'javascript:');
  detect('file_url', 'file://');
  detect('localhost', 'localhost');
  detect('localhost', '127.0.0.1');
  detect('localhost', '[::1]');
  detect('popup', 'window.open');
  detect('download', ' download');
  detect('webview_bridge', 'chrome.webview');
  if (RegExp(r'''(?:src|href)\s*=\s*["']https?://''').hasMatch(lower)) {
    findings.add('external_network');
  }
  return findings;
}

bool _isSafeObjectRef(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith('\\') ||
      value.contains('..') ||
      value.contains('://') ||
      value.contains(':') ||
      value.contains('\\') ||
      !_safeObjectRef.hasMatch(value)) {
    return false;
  }
  return true;
}

bool _isPrivateOrLocalHost(String host) {
  final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized.endsWith('.localhost')) {
    return true;
  }
  // V1 rejects every IPv6 literal. Hostnames and public IPv4 origins remain
  // expressible, while a later network host may add DNS pinning before
  // broadening this contract.
  if (normalized.contains(':')) return true;
  final parts = normalized.split('.');
  final numericLabels = parts.every(
    (value) => RegExp(r'^(?:0x[0-9a-f]+|[0-9]+)$').hasMatch(value),
  );
  if (!numericLabels) return false;
  // WHATWG / OS URL stacks historically accept a single 32-bit decimal,
  // shortened dotted IPv4, hexadecimal, octal and mixed-radix forms. Reject
  // every non-canonical numeric spelling rather than trying to emulate each
  // platform's conversion rules.
  if (parts.length != 4 ||
      parts.any(
        (value) =>
            value.startsWith('0x') ||
            (value.length > 1 && value.startsWith('0')),
      )) {
    return true;
  }
  final bytes = parts.map(int.tryParse).toList();
  if (bytes.any((value) => value == null || value < 0 || value > 255)) {
    return true;
  }
  final first = bytes[0]!;
  final second = bytes[1]!;
  return first == 0 ||
      first == 10 ||
      first == 127 ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168) ||
      first >= 224;
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}
