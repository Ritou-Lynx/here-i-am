class FormalMigrationObjectSpec {
  const FormalMigrationObjectSpec(
    this.objectType,
    this.targetRole,
    this.migrationAction,
  );

  final String objectType;
  final String targetRole;
  final String migrationAction;
}

const formalMigrationObjectCatalog = <FormalMigrationObjectSpec>[
  FormalMigrationObjectSpec("neutral_card", "cards/card_revisions", "migrate"),
  FormalMigrationObjectSpec(
      "user_truth", "user_truth_relations/provenance_records", "migrate"),
  FormalMigrationObjectSpec(
      "card_forward_relation", "card_revision_markdown_link", "migrate"),
  FormalMigrationObjectSpec("memory_structured_correction",
      "domain_operation_projection", "preserve"),
  FormalMigrationObjectSpec("card_asset_provenance_relation",
      "asset_source_provenance_relation", "migrate"),
  FormalMigrationObjectSpec("source_content", "source_contents", "preserve"),
  FormalMigrationObjectSpec("source_version", "source_versions", "preserve"),
  FormalMigrationObjectSpec("rich_text_document",
      "editor_cache_compatibility_input", "compatibility-only"),
  FormalMigrationObjectSpec(
      "card_revision_history", "card_revision_lineage", "migrate"),
  FormalMigrationObjectSpec("board", "boards", "preserve"),
  FormalMigrationObjectSpec("board_item", "board_items", "preserve"),
  FormalMigrationObjectSpec(
      "board_group_membership", "board_groups/memberships", "preserve"),
  FormalMigrationObjectSpec("board_edge", "board_edges", "preserve"),
  FormalMigrationObjectSpec(
      "annotation_card", "cards/card_revisions+anchor_ref", "migrate"),
  FormalMigrationObjectSpec("anchor", "anchors", "migrate"),
  FormalMigrationObjectSpec("timed_text_media_selector",
      "source_version_timed_text_selector", "preserve"),
  FormalMigrationObjectSpec("evidence_claim",
      "evidence_proposal_or_claim_ledger", "degraded-preserved"),
  FormalMigrationObjectSpec(
      "dreaming_fragment", "dreaming_fragment_domain", "preserve"),
  FormalMigrationObjectSpec("dreaming_episode_saga",
      "dreaming_episode_saga_snapshot_domain", "preserve"),
  FormalMigrationObjectSpec(
      "memory_entity_link", "memory_entity_link_domain", "preserve"),
  FormalMigrationObjectSpec(
      "project_memory", "project_memory_domain", "preserve"),
  FormalMigrationObjectSpec(
      "task_room_decision", "task_room_decision_domain", "preserve"),
  FormalMigrationObjectSpec(
      "task_artifact", "task_artifact/promotion_ledger", "preserve"),
  FormalMigrationObjectSpec("capture", "captures_intake_ledger", "migrate"),
  FormalMigrationObjectSpec(
      "import_candidate", "import_candidate_intake_ledger", "migrate"),
  FormalMigrationObjectSpec(
      "link_inbox_item", "link_inbox_intake_ledger", "migrate"),
  FormalMigrationObjectSpec("chat_message", "core_chat_log", "preserve"),
  FormalMigrationObjectSpec(
      "activity_event_shadow", "activity_contract_only", "compatibility-only"),
  FormalMigrationObjectSpec("domain_operation_receipt_change",
      "domain_operation_receipt_change_ledgers", "preserve"),
  FormalMigrationObjectSpec(
      "tombstone_trash", "object_tombstones/managed_trash", "migrate"),
  FormalMigrationObjectSpec(
      "derived_index_cache", "derived_projection_cache", "derive"),
  FormalMigrationObjectSpec(
      "backup_manifest", "recovery_manifest_media", "preserve"),
];

// Frozen verbatim from FORMAL_MIGRATION_MATRIX.md. Runtime conversion consumes
// these row-local literals directly; no shared defaults or derived wrapper may
// participate in the inventory oracle.
const formalMigrationObjectLiteral = <Map<String, dynamic>>[
  {
    "objectType": "neutral_card",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "memory_card",
          "targetKind": "card",
          "mode": "preserve",
          "sourceFields": ["memory_cards.id"],
          "targetField": "cards.card_id",
          "fallbackAlgorithm": "",
          "guard":
              "id present and payload consistent; else blocked:duplicate_identity_payload_mismatch"
        },
        {
          "legacyKind": "legacy_card_body",
          "targetKind": "card_revision",
          "mode": "derive_composite",
          "sourceFields": ["card_id", "canonical_markdown_sha256"],
          "targetField": "card_revisions.revision_hash",
          "fallbackAlgorithm": "",
          "guard": "body classified and rollback representable"
        }
      ]
    },
    "authority": "markdown_head_revision",
    "refs": ["board_id", "source_id", "anchor_id", "linked_card_id"],
    "rollback": {
      "strategy":
          "project accepted heads to legacy dual tables and retain revision map",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "card tombstone plus 30-day recovery; external absence is externally_missing",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "last accepted card revision and tombstone ledger"
    },
    "indexBackup": {
      "rebuildFrom": ["card_revisions", "domain_operations"],
      "backupRequired": [
        "cards",
        "card_revisions",
        "markdown_envelopes",
        "domain_operations",
        "object_tombstones"
      ],
      "excludedFromBackup": [
        "fts",
        "backlinks",
        "previews",
        "editor_richtext_cache"
      ]
    },
    "blockedReason": ""
  },
  {
    "objectType": "user_truth",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "memory_card",
          "targetKind": "card",
          "mode": "preserve",
          "sourceFields": ["memory_cards.id"],
          "targetField": "cards.card_id",
          "fallbackAlgorithm": "",
          "guard": "card identity and explicit truth authorization verified"
        },
        {
          "legacyKind": "explicit_truth_evidence",
          "targetKind": "user_truth_relation",
          "mode": "derive_composite",
          "sourceFields": [
            "card_id",
            "provenance_digest",
            "truth_operation_kind"
          ],
          "targetField": "user_truth_relations.relation_id",
          "fallbackAlgorithm": "",
          "guard":
              "explicit record/correction/external-data evidence; else blocked:truth_authorization_missing"
        },
        {
          "legacyKind": "truth_provenance",
          "targetKind": "provenance_record",
          "mode": "derive_composite",
          "sourceFields": ["card_id", "provenance_digest"],
          "targetField": "provenance_records.provenance_id",
          "fallbackAlgorithm": "",
          "guard": "source/version provenance internally consistent"
        }
      ]
    },
    "authority": "user_truth_relation_and_operation",
    "refs": ["card_id", "provenance_id", "source_id", "source_version_id"],
    "rollback": {
      "strategy":
          "restore legacy Memory read projection from accepted truth operations",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "append revoke/correct/restore operation independent of BoardItem",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "truth operation and provenance lineage"
    },
    "indexBackup": {
      "rebuildFrom": ["user_truth_relations", "domain_operations"],
      "backupRequired": [
        "user_truth_relations",
        "provenance_records",
        "domain_operations"
      ],
      "excludedFromBackup": ["memory_review_projection", "retrieval_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "card_forward_relation",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "memory_card_relation",
          "targetKind": "markdown_card_link",
          "mode": "derive_composite",
          "sourceFields": ["from_card_id", "to_card_id", "relation_kind"],
          "targetField": "card_revision_markdown_link.link_identity",
          "fallbackAlgorithm": "",
          "guard": "direction and both stable card IDs verified"
        }
      ]
    },
    "authority": "forward_markdown_link",
    "refs": ["from_card_id", "to_card_id"],
    "rollback": {
      "strategy":
          "rebuild legacy relation rows from accepted from-card revisions",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "revision change removes active link while target tombstone preserves broken-link identity",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "from-card revision lineage and target tombstone"
    },
    "indexBackup": {
      "rebuildFrom": ["card_revisions"],
      "backupRequired": ["card_revisions", "markdown_envelopes"],
      "excludedFromBackup": ["card_link_index", "backlinks"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "memory_structured_correction",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "user_correction",
          "targetKind": "domain_operation",
          "mode": "preserve",
          "sourceFields": ["user_corrections.id"],
          "targetField": "domain_operations.operation_id",
          "fallbackAlgorithm": "",
          "guard": "correction ID and corrected field binding verified"
        },
        {
          "legacyKind": "structured_json_field",
          "targetKind": "structured_field_projection_key",
          "mode": "derive_composite",
          "sourceFields": ["card_id", "field_path"],
          "targetField": "structured_field_projection.projection_key",
          "fallbackAlgorithm": "",
          "guard": "field type classified; machine field remains derived"
        }
      ]
    },
    "authority": "accepted_correction_operation",
    "refs": ["card_id", "truth_relation_id", "provenance_id", "field_path"],
    "rollback": {
      "strategy":
          "project accepted correction operations to legacy structured fields",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "never overwrite correction history; append reversal or recovery operation",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "correction operation lineage"
    },
    "indexBackup": {
      "rebuildFrom": ["domain_operations"],
      "backupRequired": ["domain_operations", "user_corrections"],
      "excludedFromBackup": ["structured_field_projection"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "card_asset_provenance_relation",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "asset",
          "targetKind": "asset_object",
          "mode": "preserve",
          "sourceFields": ["assets.id"],
          "targetField": "asset_objects.asset_id",
          "fallbackAlgorithm": "",
          "guard": "bytes and declared hash verified"
        },
        {
          "legacyKind": "memory_card_asset_relation",
          "targetKind": "asset_source_provenance_relation",
          "mode": "derive_composite",
          "sourceFields": ["card_id", "asset_id", "source_version_id", "role"],
          "targetField": "asset_source_provenance_relations.relation_id",
          "fallbackAlgorithm": "",
          "guard": "role classified; evidence role remains proposal attachment"
        }
      ]
    },
    "authority": "object_bytes_and_relation_operation",
    "refs": ["card_id", "asset_id", "source_id", "source_version_id"],
    "rollback": {
      "strategy":
          "project accepted source/display relations without promoting evidence to Claim",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "relation tombstone; object recovery follows reference and retention policy",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "relation operation and verified object manifest"
    },
    "indexBackup": {
      "rebuildFrom": [
        "asset_source_provenance_relations",
        "asset_object_manifest"
      ],
      "backupRequired": [
        "asset_objects",
        "asset_object_manifest",
        "provenance_records",
        "domain_operations"
      ],
      "excludedFromBackup": ["asset_previews"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "source_content",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "whiteboard_source",
          "targetKind": "source_content",
          "mode": "preserve",
          "sourceFields": ["whiteboard_sources.id"],
          "targetField": "source_contents.source_id",
          "fallbackAlgorithm": "",
          "guard": "canonical identity has one verified byte lineage"
        }
      ]
    },
    "authority": "source_catalog_and_current_version",
    "refs": ["source_version_id", "card_id"],
    "rollback": {
      "strategy":
          "retain source ID and verified objects in legacy source projection",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "tombstone or quarantine and restore only a verified version",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "source catalog and immutable source versions"
    },
    "indexBackup": {
      "rebuildFrom": ["source_versions"],
      "backupRequired": [
        "source_contents",
        "source_versions",
        "object_manifest",
        "source_objects"
      ],
      "excludedFromBackup": ["ocr_index", "source_preview"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "source_version",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "whiteboard_source_version",
          "targetKind": "source_version",
          "mode": "preserve",
          "sourceFields": ["whiteboard_source_versions.id"],
          "targetField": "source_versions.version_id",
          "fallbackAlgorithm": "",
          "guard": "immutable bytes match content hash and source exists"
        },
        {
          "legacyKind": "source_object_bytes",
          "targetKind": "content_addressed_object",
          "mode": "derive_composite",
          "sourceFields": ["content_sha256"],
          "targetField": "object_manifest.object_id",
          "fallbackAlgorithm": "",
          "guard": "hash verified; logical versions are not merged"
        }
      ]
    },
    "authority": "immutable_source_version_bytes",
    "refs": ["source_id", "object_id", "anchor_id", "evidence_id"],
    "rollback": {
      "strategy":
          "retain immutable version ID/hash and legacy source-version projection",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "source deletion cannot erase a version referenced by Claim",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "immutable source version and object manifest"
    },
    "indexBackup": {
      "rebuildFrom": ["source_versions", "source_objects"],
      "backupRequired": [
        "source_versions",
        "object_manifest",
        "source_objects"
      ],
      "excludedFromBackup": ["parser_output", "source_search_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "rich_text_document",
    "classification": "compatibility-only",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "richtext_editor_cache",
          "targetKind": "editor_cache",
          "mode": "not_applicable",
          "sourceFields": ["card_id", "revision_hash"],
          "targetField": "not_applicable",
          "fallbackAlgorithm": "",
          "guard": "cache never receives authoritative identity"
        },
        {
          "legacyKind": "unclassified_richtext_element",
          "targetKind": "richtext_compatibility_capsule",
          "mode": "allocate_digest_if_missing",
          "sourceFields": ["card_id", "revision_hash", "raw_sha256"],
          "targetField": "compatibility_capsules.capsule_id",
          "fallbackAlgorithm": "deterministic_namespace_plus_payload_sha256",
          "guard":
              "only when complete reversible raw bytes are preserved; never body authority"
        }
      ]
    },
    "authority": "markdown_revision_only",
    "refs": ["card_id", "revision_hash", "asset_id", "linked_card_id"],
    "rollback": {
      "strategy":
          "rebuild compatibility RichText from accepted Markdown; preserve capsule bytes only",
      "preserveAcceptedNewWrites": false,
      "appendOnly": false,
      "reconstructFromAuthority": true
    },
    "deleteRecovery": {
      "strategy":
          "delete/rebuild editor cache; capsule follows owning revision retention",
      "tombstoneBarrier": false,
      "physicalDeleteAllowed": true,
      "recoverySource":
          "accepted Markdown revision plus reversible compatibility capsule"
    },
    "indexBackup": {
      "rebuildFrom": ["card_revisions"],
      "backupRequired": ["compatibility_capsules"],
      "excludedFromBackup": ["richtext_editor_cache", "plain_text_cache"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "card_revision_history",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "identified_revision_or_operation",
          "targetKind": "card_revision",
          "mode": "preserve",
          "sourceFields": ["legacy_revision_or_operation_id"],
          "targetField": "card_revisions.legacy_identity",
          "fallbackAlgorithm": "",
          "guard": "identity binds one card, parent and content digest"
        },
        {
          "legacyKind": "unidentified_legacy_snapshot",
          "targetKind": "legacy_unbound_revision",
          "mode": "allocate_digest_if_missing",
          "sourceFields": ["card_id", "parent_revision_hash", "content_sha256"],
          "targetField": "card_revisions.revision_hash",
          "fallbackAlgorithm": "deterministic_namespace_plus_payload_sha256",
          "guard":
              "card, parent and content digest all bind; else blocked:revision_lineage_unbound"
        }
      ]
    },
    "authority": "immutable_revision_bytes_and_lineage",
    "refs": ["card_id", "parent_revision_hash", "operation_id"],
    "rollback": {
      "strategy":
          "project provable lineage while retaining unbound legacy preservation records",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "history is immutable; card delete is represented by tombstone",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "revision lineage and card tombstone"
    },
    "indexBackup": {
      "rebuildFrom": ["card_revisions"],
      "backupRequired": [
        "card_revisions",
        "markdown_envelopes",
        "domain_operations"
      ],
      "excludedFromBackup": ["history_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "board",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "whiteboard_board",
          "targetKind": "board",
          "mode": "preserve",
          "sourceFields": ["whiteboard_boards.id"],
          "targetField": "boards.board_id",
          "fallbackAlgorithm": "",
          "guard": "board ID unique and reference set closed"
        }
      ]
    },
    "authority": "board_status_and_layout_domain",
    "refs": ["board_item_id", "board_group_id", "board_edge_id"],
    "rollback": {
      "strategy": "restore same board ID and accepted board state",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "board tombstone preserves recoverable structure without deleting Card/Source",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "board state operations and tombstone"
    },
    "indexBackup": {
      "rebuildFrom": ["boards", "board_operations"],
      "backupRequired": ["boards", "board_operations"],
      "excludedFromBackup": ["board_snapshot"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "board_item",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "whiteboard_board_item",
          "targetKind": "board_item",
          "mode": "preserve",
          "sourceFields": ["whiteboard_board_items.id"],
          "targetField": "board_items.item_id",
          "fallbackAlgorithm": "",
          "guard": "board and card references classified"
        }
      ]
    },
    "authority": "board_placement_state",
    "refs": ["board_id", "card_id"],
    "rollback": {
      "strategy": "restore exact accepted placement without copying Card body",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "placement tombstone never deletes referenced Card",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "board item operation and board tombstone"
    },
    "indexBackup": {
      "rebuildFrom": ["board_items", "board_operations"],
      "backupRequired": ["board_items", "board_operations"],
      "excludedFromBackup": ["viewport_cache", "board_snapshot"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "board_group_membership",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "board_group",
          "targetKind": "board_group",
          "mode": "preserve",
          "sourceFields": ["board_groups.id"],
          "targetField": "board_groups.group_id",
          "fallbackAlgorithm": "",
          "guard": "group ID and board binding verified"
        },
        {
          "legacyKind": "board_group_member",
          "targetKind": "board_group_membership",
          "mode": "derive_composite",
          "sourceFields": ["group_id", "item_id"],
          "targetField": "board_group_memberships.membership_id",
          "fallbackAlgorithm": "",
          "guard": "membership unique and both references valid"
        }
      ]
    },
    "authority": "structured_board_group_state",
    "refs": ["board_id", "group_id", "item_id"],
    "rollback": {
      "strategy": "restore accepted groups and exact composite memberships",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "group tombstone removes membership only, never BoardItem/Card",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "group and membership operations"
    },
    "indexBackup": {
      "rebuildFrom": ["board_groups", "board_group_memberships"],
      "backupRequired": [
        "board_groups",
        "board_group_memberships",
        "board_operations"
      ],
      "excludedFromBackup": ["board_snapshot"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "board_edge",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "board_edge",
          "targetKind": "board_edge",
          "mode": "preserve",
          "sourceFields": ["edge.id"],
          "targetField": "board_edges.edge_id",
          "fallbackAlgorithm": "",
          "guard": "from/to items and direction verified"
        }
      ]
    },
    "authority": "structured_board_edge_state",
    "refs": ["board_id", "from_item_id", "to_item_id"],
    "rollback": {
      "strategy": "restore same edge ID and accepted direction",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "edge tombstone and explicit restore",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "edge operation and tombstone"
    },
    "indexBackup": {
      "rebuildFrom": ["board_edges"],
      "backupRequired": ["board_edges", "board_operations"],
      "excludedFromBackup": ["board_graph_index", "board_snapshot"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "annotation_card",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "annotation_card",
          "targetKind": "card",
          "mode": "preserve",
          "sourceFields": ["memory_cards.id"],
          "targetField": "cards.card_id",
          "fallbackAlgorithm": "",
          "guard": "CardKind.annotation owner and body consistent"
        }
      ]
    },
    "authority": "card_markdown_and_annotation_role_metadata",
    "refs": ["anchor_id"],
    "rollback": {
      "strategy":
          "project accepted annotation Card revision without merging Source or another annotation",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "Card tombstone while Anchor remains independently recoverable",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "annotation Card revision and anchor catalog"
    },
    "indexBackup": {
      "rebuildFrom": ["card_revisions", "anchors"],
      "backupRequired": ["cards", "card_revisions", "anchors"],
      "excludedFromBackup": ["annotation_text_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "anchor",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "identified_anchor",
          "targetKind": "anchor",
          "mode": "preserve",
          "sourceFields": ["anchor_id"],
          "targetField": "anchors.anchor_id",
          "fallbackAlgorithm": "",
          "guard": "exact SourceVersion selector and fingerprint valid"
        },
        {
          "legacyKind": "anchor_without_id",
          "targetKind": "anchor",
          "mode": "derive_composite",
          "sourceFields": ["source_version_id", "selector_fingerprint"],
          "targetField": "anchors.anchor_id",
          "fallbackAlgorithm": "",
          "guard":
              "both fields exact; ambiguity blocked:anchor_retarget_ambiguous"
        }
      ]
    },
    "authority": "source_version_selector_fingerprint_tuple",
    "refs": [
      "source_id",
      "source_version_id",
      "annotation_card_id",
      "evidence_id"
    ],
    "rollback": {
      "strategy": "embed exact compatibility JSON without guessing re-anchor",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "orphan state is not deletion; retain old SourceVersion for recovery",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "anchor tuple and immutable source version"
    },
    "indexBackup": {
      "rebuildFrom": ["anchors", "source_versions"],
      "backupRequired": ["anchors", "source_versions"],
      "excludedFromBackup": ["anchor_location_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "timed_text_media_selector",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "timed_track_cue_selector",
          "targetKind": "source_version_timed_selector",
          "mode": "derive_composite",
          "sourceFields": [
            "source_version_id",
            "track_id",
            "cue_id",
            "selector_fingerprint"
          ],
          "targetField": "timed_text_selectors.selector_id",
          "fallbackAlgorithm": "",
          "guard":
              "track/cue/version binding reliable; no cross-version time guess"
        }
      ]
    },
    "authority": "timed_text_version_domain",
    "refs": ["source_version_id", "anchor_id", "track_id", "cue_id"],
    "rollback": {
      "strategy":
          "restore exact version-scoped track/cue selector outside Card body",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "source retention policy controls track; annotation cannot overwrite it",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource":
          "source version timed-text metadata and legal source object"
    },
    "indexBackup": {
      "rebuildFrom": ["timed_text_selectors", "source_versions"],
      "backupRequired": ["timed_text_metadata", "legal_source_objects"],
      "excludedFromBackup": ["cue_search_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "evidence_claim",
    "classification": "degraded-preserved",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "legacy_evidence_attachment",
          "targetKind": "evidence_proposal",
          "mode": "derive_composite",
          "sourceFields": [
            "asset_id",
            "source_version_id",
            "anchor_id",
            "role"
          ],
          "targetField": "evidence_proposals.proposal_id",
          "fallbackAlgorithm": "",
          "guard":
              "targetKind is proposal only; creating evidence_claim is blocked:evidence_claim_promotion_forbidden"
        }
      ]
    },
    "authority": "evidence_claim_ledger_only_after_future_explicit_gate",
    "refs": ["source_version_id", "anchor_id", "asset_id"],
    "rollback": {
      "strategy":
          "preserve proposal and any future explicit Claim lineage without attachment promotion",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "append retract/supersede; never edit immutable Claim in place",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "proposal or Claim lineage and exact source version"
    },
    "indexBackup": {
      "rebuildFrom": ["evidence_proposals", "evidence_claims"],
      "backupRequired": [
        "evidence_proposals",
        "evidence_claims",
        "provenance_records",
        "domain_operations"
      ],
      "excludedFromBackup": [
        "evidence_card_projection",
        "evidence_report_projection"
      ]
    },
    "blockedReason": ""
  },
  {
    "objectType": "dreaming_fragment",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "memory_fragment",
          "targetKind": "dreaming_fragment",
          "mode": "preserve",
          "sourceFields": ["memory_fragments.id"],
          "targetField": "dreaming_fragments.fragment_id",
          "fallbackAlgorithm": "",
          "guard": "fragment lineage and stable chat sync refs preserved"
        }
      ]
    },
    "authority": "dreaming_fragment_operation_and_status",
    "refs": ["chat_sync_id", "memory_entity_id", "episode_id"],
    "rollback": {
      "strategy":
          "retain original fragment domain and accepted relationship-memory operations",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "status delete/restore under Dreaming policy",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "fragment operation and source lineage"
    },
    "indexBackup": {
      "rebuildFrom": ["dreaming_fragments", "dreaming_operations"],
      "backupRequired": [
        "dreaming_fragments",
        "dreaming_operations",
        "source_lineage"
      ],
      "excludedFromBackup": ["dreaming_fts"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "dreaming_episode_saga",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "dreaming_episode",
          "targetKind": "dreaming_episode",
          "mode": "preserve",
          "sourceFields": ["episodes.id"],
          "targetField": "dreaming_episodes.episode_id",
          "fallbackAlgorithm": "",
          "guard": "episode lineage valid"
        },
        {
          "legacyKind": "dreaming_saga",
          "targetKind": "dreaming_saga",
          "mode": "preserve",
          "sourceFields": ["sagas.id"],
          "targetField": "dreaming_sagas.saga_id",
          "fallbackAlgorithm": "",
          "guard": "saga lineage valid"
        },
        {
          "legacyKind": "dreaming_snapshot",
          "targetKind": "dreaming_snapshot",
          "mode": "preserve",
          "sourceFields": ["snapshots.id"],
          "targetField": "dreaming_snapshots.snapshot_id",
          "fallbackAlgorithm": "",
          "guard":
              "snapshot binds episode/saga and never overwrites current state"
        }
      ]
    },
    "authority": "dreaming_episode_saga_domain",
    "refs": ["fragment_id", "memory_entity_id", "episode_id", "saga_id"],
    "rollback": {
      "strategy": "retain each accepted domain ID and lineage",
      "preserveAcceptedNewWrites": true,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "status/tombstone; immutable snapshot cannot overwrite current",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "episode/saga lineage and immutable snapshots"
    },
    "indexBackup": {
      "rebuildFrom": [
        "dreaming_episodes",
        "dreaming_sagas",
        "dreaming_snapshots"
      ],
      "backupRequired": [
        "dreaming_episodes",
        "dreaming_sagas",
        "dreaming_snapshots",
        "dreaming_operations"
      ],
      "excludedFromBackup": ["dreaming_summary_projection", "dreaming_fts"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "memory_entity_link",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "memory_entity",
          "targetKind": "memory_entity",
          "mode": "preserve",
          "sourceFields": ["memory_entities.id"],
          "targetField": "memory_entities.entity_id",
          "fallbackAlgorithm": "",
          "guard": "entity stable ID and scope valid"
        },
        {
          "legacyKind": "memory_entity_link",
          "targetKind": "memory_entity_link",
          "mode": "preserve",
          "sourceFields": ["memory_entity_links.id"],
          "targetField": "memory_entity_links.link_id",
          "fallbackAlgorithm": "",
          "guard": "both endpoint IDs and relation semantics valid"
        }
      ]
    },
    "authority": "memory_entity_operation_and_status",
    "refs": ["fragment_id", "card_id", "episode_id", "memory_entity_id"],
    "rollback": {
      "strategy":
          "retain entities/links and update only stable Card ref target",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "merge/delete/recover only by explicit domain operation",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "entity/link operation lineage"
    },
    "indexBackup": {
      "rebuildFrom": [
        "memory_entities",
        "memory_entity_links",
        "domain_operations"
      ],
      "backupRequired": [
        "memory_entities",
        "memory_entity_links",
        "domain_operations"
      ],
      "excludedFromBackup": ["memory_entity_graph_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "project_memory",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "project_memory_record",
          "targetKind": "project_memory_record",
          "mode": "preserve",
          "sourceFields": ["project_memory_stable_id"],
          "targetField": "project_memory_records.project_memory_id",
          "fallbackAlgorithm": "",
          "guard":
              "project space and source/closeout binding verified; missing stable ID blocked:project_scope_violation"
        }
      ]
    },
    "authority": "project_memory_operation_and_projection",
    "refs": ["project_id", "source_id", "closeout_id"],
    "rollback": {
      "strategy":
          "retain accepted project-memory inputs and operations without User-truth promotion",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "project policy expressed through scoped operation/tombstone",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "project-scoped operation lineage"
    },
    "indexBackup": {
      "rebuildFrom": ["project_memory_operations"],
      "backupRequired": [
        "project_memory_accepted_inputs",
        "project_memory_operations"
      ],
      "excludedFromBackup": [
        "project_memory_projection",
        "project_memory_index"
      ]
    },
    "blockedReason": ""
  },
  {
    "objectType": "task_room_decision",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "task_room",
          "targetKind": "task_room",
          "mode": "preserve",
          "sourceFields": ["task_rooms.id"],
          "targetField": "task_rooms.task_room_id",
          "fallbackAlgorithm": "",
          "guard": "task lane binding valid"
        },
        {
          "legacyKind": "task_decision",
          "targetKind": "task_decision",
          "mode": "preserve",
          "sourceFields": ["task_decisions.id"],
          "targetField": "task_decisions.decision_id",
          "fallbackAlgorithm": "",
          "guard": "decision binds stable task room"
        }
      ]
    },
    "authority": "task_operation_and_status",
    "refs": ["task_room_id", "task_id", "board_id"],
    "rollback": {
      "strategy": "retain task-room and decision IDs plus supersede operations",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "archive/delete/decision supersede is explicit operation",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "task operation and decision lineage"
    },
    "indexBackup": {
      "rebuildFrom": ["task_rooms", "task_decisions", "task_operations"],
      "backupRequired": ["task_rooms", "task_decisions", "task_operations"],
      "excludedFromBackup": ["task_ui_projection", "task_search_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "task_artifact",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "task_artifact",
          "targetKind": "task_artifact",
          "mode": "preserve",
          "sourceFields": ["task_artifacts.id"],
          "targetField": "task_artifacts.artifact_id",
          "fallbackAlgorithm": "",
          "guard": "artifact storage ref valid"
        },
        {
          "legacyKind": "explicit_artifact_promotion",
          "targetKind": "artifact_promotion",
          "mode": "derive_composite",
          "sourceFields": ["artifact_id", "promotion_intent_id", "target_kind"],
          "targetField": "artifact_promotions.promotion_id",
          "fallbackAlgorithm": "",
          "guard": "explicit authorization and atomic promotion complete"
        }
      ]
    },
    "authority": "task_artifact_status_and_promotion_ledger",
    "refs": ["task_room_id", "storage_ref", "promoted_object_id"],
    "rollback": {
      "strategy":
          "retain artifact and promotion map without deleting independently promoted object",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "artifact archive/delete does not delete promoted object",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "artifact status and promotion ledger"
    },
    "indexBackup": {
      "rebuildFrom": ["task_artifacts", "artifact_promotions"],
      "backupRequired": [
        "task_artifacts",
        "artifact_promotions",
        "artifact_objects",
        "task_operations"
      ],
      "excludedFromBackup": ["task_artifact_search_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "capture",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "capture_without_stable_id",
          "targetKind": "capture",
          "mode": "allocate_digest_if_missing",
          "sourceFields": [
            "installation_id",
            "intake_idempotency_key",
            "payload_digest"
          ],
          "targetField": "captures.capture_id",
          "fallbackAlgorithm": "deterministic_namespace_plus_payload_sha256",
          "guard":
              "allocate once and persist permanent map; same key different digest blocked:intake_key_digest_conflict"
        }
      ]
    },
    "authority": "capture_intake_ledger",
    "refs": ["installation_id", "import_candidate_id"],
    "rollback": {
      "strategy":
          "retain accepted/pending intake identity and never materialize downstream object",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "cancel/expire barrier persists across restart",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "capture intake ledger and permanent identity map"
    },
    "indexBackup": {
      "rebuildFrom": ["captures"],
      "backupRequired": ["accepted_capture_ledger", "capture_identity_map"],
      "excludedFromBackup": ["capture_queue_counts"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "import_candidate",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "import_candidate_without_stable_id",
          "targetKind": "import_candidate",
          "mode": "allocate_digest_if_missing",
          "sourceFields": [
            "installation_id",
            "intake_idempotency_key",
            "payload_digest"
          ],
          "targetField": "import_candidates.import_candidate_id",
          "fallbackAlgorithm": "deterministic_namespace_plus_payload_sha256",
          "guard":
              "allocate once and persist permanent map; same key different digest blocked:intake_key_digest_conflict"
        }
      ]
    },
    "authority": "import_candidate_phase_and_attempt_ledger",
    "refs": ["capture_id", "link_inbox_item_id"],
    "rollback": {
      "strategy":
          "retain candidate ID, attempt generations and terminal barriers without creating Source",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "cancel/failure terminal state; restart resumes persisted phase",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "candidate decision ledger and permanent identity map"
    },
    "indexBackup": {
      "rebuildFrom": ["import_candidates"],
      "backupRequired": [
        "accepted_candidate_ledger",
        "candidate_decisions",
        "import_identity_map"
      ],
      "excludedFromBackup": ["parser_diagnostics"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "link_inbox_item",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "provider_note_link",
          "targetKind": "link_inbox_item",
          "mode": "derive_composite",
          "sourceFields": ["provider_id", "provider_note_id"],
          "targetField": "link_inbox_items.link_inbox_item_id",
          "fallbackAlgorithm": "",
          "guard":
              "use when provider_note_id present; payload never participates in identity"
        },
        {
          "legacyKind": "canonical_url_link",
          "targetKind": "link_inbox_item",
          "mode": "derive_composite",
          "sourceFields": ["canonical_url"],
          "targetField": "link_inbox_items.link_inbox_item_id",
          "fallbackAlgorithm": "",
          "guard":
              "use only when provider note identity absent; same identity different digest blocked:intake_key_digest_conflict"
        }
      ]
    },
    "authority": "link_inbox_ledger",
    "refs": ["capture_id", "import_candidate_id"],
    "rollback": {
      "strategy": "retain canonical/provider identity and accepted inbox phase",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "cancel/remove/expire is persisted; failed/needs_screenshot remains honest",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "link inbox ledger"
    },
    "indexBackup": {
      "rebuildFrom": ["link_inbox_items"],
      "backupRequired": ["accepted_link_inbox_ledger"],
      "excludedFromBackup": ["link_inbox_counters", "preacceptance_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "chat_message",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "persona_chat_message_with_sync_id",
          "targetKind": "core_chat_message",
          "mode": "preserve",
          "sourceFields": ["persona_chat_messages.sync_id"],
          "targetField": "core_chat_log.sync_id",
          "fallbackAlgorithm": "",
          "guard": "sync_id present and unique"
        },
        {
          "legacyKind": "persona_chat_message_without_sync_id",
          "targetKind": "none",
          "mode": "blocked",
          "sourceFields": ["persona_chat_messages.local_int_id"],
          "targetField": "not_applicable",
          "fallbackAlgorithm": "",
          "guard":
              "local int/digest allocation forbidden; blocked:chat_sync_id_missing"
        }
      ]
    },
    "authority": "immutable_core_chat_change",
    "refs": ["sync_id", "provenance_id"],
    "rollback": {
      "strategy":
          "1A-1/2 does not change writer; retain accepted chat log and stable provenance refs",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "append retract/delete chat operation",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "immutable chat change lineage"
    },
    "indexBackup": {
      "rebuildFrom": ["core_chat_log"],
      "backupRequired": ["accepted_core_chat_log"],
      "excludedFromBackup": ["recent_chat_projection", "chat_search_index"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "activity_event_shadow",
    "classification": "compatibility-only",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "device_local_activity_event",
          "targetKind": "future_core_activity_event",
          "mode": "not_applicable",
          "sourceFields": ["device_local_event"],
          "targetField": "not_applicable",
          "fallbackAlgorithm": "",
          "guard": "production migration forbidden:activity_migration_forbidden"
        },
        {
          "legacyKind": "activity_shadow",
          "targetKind": "activity_shadow",
          "mode": "not_applicable",
          "sourceFields": ["accepted_raw_event"],
          "targetField": "not_applicable",
          "fallbackAlgorithm": "",
          "guard": "shadow is derived and never accepted authority"
        }
      ]
    },
    "authority": "contract_only_no_production_migration",
    "refs": ["event_id", "device_id", "probe_id"],
    "rollback": {
      "strategy":
          "no production migration; discard shadow and leave accepted raw event contract untouched",
      "preserveAcceptedNewWrites": false,
      "appendOnly": false,
      "reconstructFromAuthority": true
    },
    "deleteRecovery": {
      "strategy":
          "delete/rebuild shadow; raw event retention/revoke belongs to P3",
      "tombstoneBarrier": false,
      "physicalDeleteAllowed": true,
      "recoverySource": "accepted raw event when future Core exists"
    },
    "indexBackup": {
      "rebuildFrom": ["accepted_raw_activity_events"],
      "backupRequired": ["activity_contract"],
      "excludedFromBackup": ["activity_shadow"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "domain_operation_receipt_change",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "domain_operation",
          "targetKind": "domain_operation",
          "mode": "preserve",
          "sourceFields": ["memory_card_operations.id"],
          "targetField": "domain_operations.operation_id",
          "fallbackAlgorithm": "",
          "guard": "operation digest, object and revision binding verified"
        },
        {
          "legacyKind": "operation_receipt",
          "targetKind": "operation_receipt",
          "mode": "derive_composite",
          "sourceFields": ["operation_id", "authority_epoch", "receipt_kind"],
          "targetField": "operation_receipts.receipt_id",
          "fallbackAlgorithm": "",
          "guard": "one receipt identity per accepted operation/epoch/kind"
        },
        {
          "legacyKind": "domain_change",
          "targetKind": "domain_change",
          "mode": "derive_composite",
          "sourceFields": ["operation_id", "change_sequence"],
          "targetField": "domain_changes.change_id",
          "fallbackAlgorithm": "",
          "guard": "sequence stable and no duplicate change"
        }
      ]
    },
    "authority": "append_only_operation_receipt_change_ledgers",
    "refs": ["object_id", "revision_hash", "authority_epoch"],
    "rollback": {
      "strategy":
          "append compensating operation; never rewrite accepted operation/receipt/change",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "history has no physical delete; reversal is a new operation",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "append-only operation, receipt and change lineage"
    },
    "indexBackup": {
      "rebuildFrom": [
        "domain_operations",
        "operation_receipts",
        "domain_changes"
      ],
      "backupRequired": [
        "domain_operations",
        "operation_receipts",
        "domain_changes"
      ],
      "excludedFromBackup": ["change_feed_projection"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "tombstone_trash",
    "classification": "migrate",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "legacy_delete_status",
          "targetKind": "object_tombstone",
          "mode": "derive_composite",
          "sourceFields": ["object_id", "delete_operation_id"],
          "targetField": "object_tombstones.tombstone_id",
          "fallbackAlgorithm": "",
          "guard": "delete operation and last valid source verified"
        }
      ]
    },
    "authority": "delete_barrier_and_last_valid_reference",
    "refs": [
      "object_id",
      "revision_hash",
      "source_version_id",
      "delete_operation_id"
    ],
    "rollback": {
      "strategy":
          "rollback obeys accepted tombstone and never revives from stale backup",
      "preserveAcceptedNewWrites": true,
      "appendOnly": true,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy": "30-day recovery; permanent purge follows backup policy",
      "tombstoneBarrier": true,
      "physicalDeleteAllowed": false,
      "recoverySource": "object tombstone, managed trash and last valid source"
    },
    "indexBackup": {
      "rebuildFrom": ["object_tombstones", "managed_trash"],
      "backupRequired": [
        "object_tombstones",
        "managed_trash",
        "delete_operations"
      ],
      "excludedFromBackup": ["trash_view", "online_indexes_for_deleted_objects"]
    },
    "blockedReason": ""
  },
  {
    "objectType": "derived_index_cache",
    "classification": "derive",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "derived_projection",
          "targetKind": "derived_projection_key",
          "mode": "derive_composite",
          "sourceFields": ["source_hash", "source_version"],
          "targetField": "derived_projections.rebuild_key",
          "fallbackAlgorithm": "",
          "guard":
              "source is accepted authority; projection cannot win migration"
        }
      ]
    },
    "authority": "none_derived_only",
    "refs": ["accepted_revision_hash", "domain_operation_id"],
    "rollback": {
      "strategy": "drop and rebuild from accepted authority",
      "preserveAcceptedNewWrites": false,
      "appendOnly": false,
      "reconstructFromAuthority": true
    },
    "deleteRecovery": {
      "strategy":
          "physical cache deletion allowed; stale source tombstone prevents resurrection",
      "tombstoneBarrier": false,
      "physicalDeleteAllowed": true,
      "recoverySource": "accepted revision or domain operation"
    },
    "indexBackup": {
      "rebuildFrom": ["accepted_card_revisions", "accepted_domain_operations"],
      "backupRequired": [],
      "excludedFromBackup": [
        "fts",
        "backlinks",
        "previews",
        "embeddings",
        "richtext_editor_cache"
      ]
    },
    "blockedReason": ""
  },
  {
    "objectType": "backup_manifest",
    "classification": "preserve",
    "stableIdMapping": {
      "entries": [
        {
          "legacyKind": "recovery_snapshot",
          "targetKind": "backup_manifest",
          "mode": "derive_composite",
          "sourceFields": [
            "authority_epoch",
            "journal_watermark",
            "manifest_digest"
          ],
          "targetField": "backup_manifests.manifest_id",
          "fallbackAlgorithm": "",
          "guard": "all object/tombstone/journal hashes present and verified"
        }
      ]
    },
    "authority": "recovery_media_non_writer",
    "refs": [
      "authority_epoch",
      "journal_watermark",
      "object_id",
      "tombstone_id"
    ],
    "rollback": {
      "strategy":
          "retain immutable recovery media by policy but never use it as writer or accepted online state",
      "preserveAcceptedNewWrites": false,
      "appendOnly": false,
      "reconstructFromAuthority": false
    },
    "deleteRecovery": {
      "strategy":
          "retention may physically expire media; restore must apply manifest tombstone/journal barrier",
      "tombstoneBarrier": false,
      "physicalDeleteAllowed": true,
      "recoverySource": "verified immutable backup manifest and objects"
    },
    "indexBackup": {
      "rebuildFrom": [],
      "backupRequired": [
        "backup_manifests",
        "sqlite_snapshot",
        "vault_objects",
        "object_tombstones",
        "journal_watermark"
      ],
      "excludedFromBackup": [
        "fts",
        "backlinks",
        "previews",
        "embeddings",
        "richtext_editor_cache"
      ]
    },
    "blockedReason": ""
  }
];

final formalMigrationObjectKinds = Set<String>.unmodifiable(
  formalMigrationObjectCatalog.map((spec) => spec.objectType),
);

class MigrationCaseDefinition {
  const MigrationCaseDefinition(
    this.id,
    this.objectType,
    this.feature, {
    this.flags = const [],
    this.crashPhase = 'none',
    this.commitCase = false,
  });

  final String id;
  final String objectType;
  final String feature;
  final List<String> flags;
  final String crashPhase;
  final bool commitCase;

  bool get isFailureCase => id.startsWith('commit-failure-');
}

const exactExpandedMigrationCrashPoints = <String>[
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

const exactMigrationFailurePoints = <String>[
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

const _failureCrashBindings = <String, String>{
  'stale_credential_generation': 'before_identity_precheck',
  'identity_binding_mismatch': 'before_identity_precheck',
  'scope_denied': 'before_identity_precheck',
  'stale_core_instance': 'before_identity_precheck',
  'stale_authority_epoch': 'before_identity_precheck',
  'stale_worker_fence': 'before_identity_precheck',
  'lineage_state_rejected': 'before_identity_precheck',
  'duplicate_key_same_digest': 'after_identity_precheck_before_idempotency',
  'duplicate_key_different_digest':
      'after_identity_precheck_before_idempotency',
  'stale_parent_revision': 'after_idempotency_before_business_read',
  'dangling_stable_ref': 'after_idempotency_before_business_read',
  'disk_full_during_stage': 'before_stage_file_write:0',
  'disk_full_during_publish': 'before_file_publish:0',
  'permission_denied_during_stage': 'before_stage_file_write:0',
  'permission_denied_during_publish': 'before_file_publish:0',
  'invalid_yaml': 'before_journal_tx_a',
  'source_object_hash_mismatch': 'before_stage_file_write:0',
  'external_move': 'before_file_publish:0',
  'external_delete': 'before_file_publish:0',
  'activation_constraint_failure': 'during_activation_tx_before_commit',
  'projection_rebuild_failure': 'during_projection_rebuild:0',
  'notification_failure': 'after_cursor_commit_before_notification',
  'rollback_manifest_corrupt': 'before_rollback_copy:0',
  'staging_manifest_corrupt': 'after_stage_directory_fsync_before_tx_b',
};

String _caseSuffix(String value) => value
    .replaceAll(':', '-')
    .replaceAll('_', '-')
    .replaceAll(RegExp('-+'), '-');

List<MigrationCaseDefinition> buildMigrationCaseDefinitions() {
  final cases = <MigrationCaseDefinition>[
    const MigrationCaseDefinition(
        'migration-ordinary-card-no-truth', 'neutral_card', 'ordinary_card'),
    const MigrationCaseDefinition(
        'migration-explicit-truth-provenance', 'user_truth', 'explicit_truth'),
    const MigrationCaseDefinition(
        'migration-body-conflict', 'neutral_card', 'body_conflict'),
    const MigrationCaseDefinition(
        'migration-title-conflict', 'neutral_card', 'title_conflict'),
    const MigrationCaseDefinition(
        'migration-id-conflict', 'neutral_card', 'id_conflict'),
    const MigrationCaseDefinition(
        'richtext-paragraph', 'rich_text_document', 'block_paragraph'),
    const MigrationCaseDefinition(
        'richtext-heading', 'rich_text_document', 'block_heading'),
    const MigrationCaseDefinition(
        'richtext-list', 'rich_text_document', 'block_list'),
    const MigrationCaseDefinition(
        'richtext-ordered-list', 'rich_text_document', 'block_ordered_list'),
    const MigrationCaseDefinition(
        'richtext-quote', 'rich_text_document', 'block_quote'),
    const MigrationCaseDefinition(
        'richtext-code', 'rich_text_document', 'block_code'),
    const MigrationCaseDefinition('richtext-code-backticks',
        'rich_text_document', 'block_code_backticks'),
    const MigrationCaseDefinition(
        'richtext-empty', 'rich_text_document', 'block_empty'),
    const MigrationCaseDefinition(
        'richtext-empty-list', 'rich_text_document', 'block_empty_list'),
    const MigrationCaseDefinition(
        'richtext-empty-quote', 'rich_text_document', 'block_empty_quote'),
    const MigrationCaseDefinition(
        'richtext-nested', 'rich_text_document', 'block_nested'),
    const MigrationCaseDefinition(
        'richtext-nested-quote', 'rich_text_document', 'block_nested_quote'),
    const MigrationCaseDefinition(
        'richtext-footnote', 'rich_text_document', 'block_footnote'),
    const MigrationCaseDefinition(
        'richtext-gfm-table', 'rich_text_document', 'block_gfm_table'),
    const MigrationCaseDefinition(
        'richtext-raw', 'rich_text_document', 'block_raw'),
    const MigrationCaseDefinition('richtext-reference-card',
        'rich_text_document', 'block_reference_card'),
    const MigrationCaseDefinition('richtext-reference-source',
        'rich_text_document', 'block_reference_source'),
    const MigrationCaseDefinition('richtext-reference-anchor',
        'rich_text_document', 'block_reference_anchor'),
    const MigrationCaseDefinition('richtext-reference-evidence',
        'rich_text_document', 'block_reference_evidence'),
    const MigrationCaseDefinition(
        'richtext-nested-marks', 'rich_text_document', 'mark_nested'),
    const MigrationCaseDefinition(
        'richtext-crossing-marks', 'rich_text_document', 'mark_crossing'),
    const MigrationCaseDefinition(
        'richtext-underline', 'rich_text_document', 'mark_underline'),
    const MigrationCaseDefinition(
        'richtext-strike', 'rich_text_document', 'mark_strike'),
    const MigrationCaseDefinition(
        'richtext-inline-code', 'rich_text_document', 'mark_code'),
    const MigrationCaseDefinition(
        'richtext-link-https', 'rich_text_document', 'mark_link_https'),
    const MigrationCaseDefinition(
        'richtext-link-card', 'rich_text_document', 'mark_link_card'),
    const MigrationCaseDefinition(
        'richtext-invalid-mark', 'rich_text_document', 'mark_invalid'),
    const MigrationCaseDefinition(
        'richtext-unknown-mark', 'rich_text_document', 'mark_unknown'),
    const MigrationCaseDefinition('richtext-utf16-fingerprint',
        'rich_text_document', 'utf16_fingerprint'),
    const MigrationCaseDefinition(
        'asset-image', 'card_asset_provenance_relation', 'asset_image'),
    const MigrationCaseDefinition(
        'asset-video', 'card_asset_provenance_relation', 'asset_video'),
    const MigrationCaseDefinition('asset-attachment',
        'card_asset_provenance_relation', 'asset_attachment'),
    const MigrationCaseDefinition(
        'asset-missing', 'card_asset_provenance_relation', 'asset_missing'),
    const MigrationCaseDefinition('asset-hash-mismatch',
        'card_asset_provenance_relation', 'asset_hash_mismatch'),
    const MigrationCaseDefinition(
        'asset-temp-path', 'card_asset_provenance_relation', 'asset_temp_path'),
    const MigrationCaseDefinition(
        'asset-base64', 'card_asset_provenance_relation', 'asset_base64'),
    const MigrationCaseDefinition(
        'richtext-ime-defer', 'rich_text_document', 'ime_uncommitted'),
    const MigrationCaseDefinition('richtext-cjk-emoji-variation',
        'rich_text_document', 'cjk_emoji_variation'),
    const MigrationCaseDefinition('richtext-combining-sequence',
        'rich_text_document', 'combining_sequence'),
    const MigrationCaseDefinition(
        'history-parent', 'card_revision_history', 'history_parent'),
    const MigrationCaseDefinition(
        'editor-cache-no-revision', 'rich_text_document', 'editor_cache'),
    const MigrationCaseDefinition('anchor-exact', 'anchor', 'anchor_exact'),
    const MigrationCaseDefinition(
        'anchor-ambiguous', 'anchor', 'anchor_ambiguous'),
    const MigrationCaseDefinition('anchor-orphan', 'anchor', 'anchor_orphan'),
    const MigrationCaseDefinition('evidence-attachment-no-claim',
        'evidence_claim', 'evidence_attachment'),
    const MigrationCaseDefinition(
        'task-promotion-authorized', 'task_artifact', 'task_promotion'),
    const MigrationCaseDefinition('task-promotion-partial-failure',
        'task_artifact', 'task_partial_failure'),
    const MigrationCaseDefinition(
        'capture-same-digest', 'capture', 'capture_same_digest'),
    const MigrationCaseDefinition(
        'capture-different-digest', 'capture', 'capture_different_digest'),
    const MigrationCaseDefinition(
        'capture-cancel-barrier', 'capture', 'capture_cancel'),
    const MigrationCaseDefinition(
        'capture-restart', 'capture', 'capture_restart'),
    const MigrationCaseDefinition(
        'import-same-digest', 'import_candidate', 'import_same_digest'),
    const MigrationCaseDefinition('import-different-digest', 'import_candidate',
        'import_different_digest'),
    const MigrationCaseDefinition(
        'import-cancel-barrier', 'import_candidate', 'import_cancel'),
    const MigrationCaseDefinition(
        'import-parser-late', 'import_candidate', 'import_parser_late'),
    const MigrationCaseDefinition(
        'import-restart', 'import_candidate', 'import_restart'),
    const MigrationCaseDefinition(
        'link-same-digest', 'link_inbox_item', 'link_same_digest'),
    const MigrationCaseDefinition(
        'link-different-digest', 'link_inbox_item', 'link_different_digest'),
    const MigrationCaseDefinition(
        'link-cancel-barrier', 'link_inbox_item', 'link_cancel'),
    const MigrationCaseDefinition(
        'link-parser-late', 'link_inbox_item', 'link_parser_late'),
    const MigrationCaseDefinition(
        'link-restart', 'link_inbox_item', 'link_restart'),
    const MigrationCaseDefinition(
        'migration-roundtrip-full', 'neutral_card', 'roundtrip_full'),
    const MigrationCaseDefinition('migration-formal-32-object-inventory',
        'backup_manifest', 'formal_inventory'),
  ];
  for (final phase in exactExpandedMigrationCrashPoints) {
    cases.add(MigrationCaseDefinition(
      'commit-crash-${_caseSuffix(phase)}',
      'domain_operation_receipt_change',
      'exact_crash_point',
      crashPhase: phase,
      commitCase: true,
    ));
  }
  for (final failure in exactMigrationFailurePoints) {
    if (failure == 'external_third_hash_conflict') continue;
    cases.add(MigrationCaseDefinition(
      'commit-failure-${_caseSuffix(failure)}',
      'domain_operation_receipt_change',
      'exact_failure_point',
      crashPhase: _failureCrashBindings[failure]!,
      commitCase: true,
    ));
  }
  for (var fileOrdinal = 0; fileOrdinal < 2; fileOrdinal++) {
    cases.add(MigrationCaseDefinition(
      'commit-failure-external-third-hash-conflict-file-$fileOrdinal',
      'domain_operation_receipt_change',
      'exact_failure_point',
      crashPhase: 'after_file_publish:$fileOrdinal',
      commitCase: true,
    ));
  }
  return List.unmodifiable(cases);
}

final migrationCaseDefinitions = buildMigrationCaseDefinitions();
