# Gate 1A-0 正式迁移矩阵

> 状态：**Gate 1A-0 已冻结并经 Lynx 真人 Gate 通过的目标矩阵；未执行**。本矩阵是 1A-1/1A-2 的强制输入，
> 不执行生产 migration。处理词只允许 `preserve`、`migrate`、`derive`、`compatibility-only`、
> `degraded-preserved`、`blocked`；没有 unknown / other 兜底。
>
> schema 与正文细节见 [Physical schema / Markdown ADR](PHYSICAL_SCHEMA_AND_MARKDOWN_DATAFLOW_ADR.md)，
> 原子性见 [cross-medium ADR](CROSS_MEDIUM_COMMIT_RECOVERY_ADR.md)。

## 判定规则

- `blocked` 是已经选定的 fail-closed 处理，不是待选方案：该对象不切换，保全全部输入并输出机器可读 reason。
- 旧 ID 原值保留；只有没有旧稳定身份的对象才按 deterministic namespace + payload digest 分配一次并写永久 migration map。
- migration/rollback 都是 DomainCommand + journal operation；不得 bulk copy 后直接改 feature flag。
- “备份”只表示 recovery media；正文、领域 operation、tombstone 等不可重建数据必须备份，index/cache 可重建。

## 全对象矩阵

| 对象 | 旧身份 / 存储 | 目标身份 / physical schema | 正文 / 状态权威 | 引用 | 迁移 / 回滚 | 删除 / 恢复 | 索引 / 备份 | blocked 条件 |
|---|---|---|---|---|---|---|---|---|
| Neutral Card | `memory_cards.id` + `whiteboard_card_extras.card_id` | 原 `card_id` → `cards`; head → `card_revisions` | 当前为双表/RichText路径；目标仅 Markdown head revision | Board/Source/Anchor/links 都用稳定 ID | migrate；按 body conflict规则；rollback回投双表且保留新 revision map | tombstone + 30天产品恢复策略；外删 `externally_missing` | FTS/backlink/preview derive；备份 envelope/revisions/catalog | duplicate ID不同 payload、正文冲突、unknown kind/owner、无 rollback表示 |
| User-truth / Memory Card | `memory_cards` + source/structured/operation 附表 | `user_truth_relations` + `provenance_records` 关联中性 `card_id` | truth relation/operation 是状态权威；Card正文不证明 truth | provenance、card、source/version | migrate 仅显式 record/correction/external-data evidence；rollback恢复 legacy Memory读取 | 独立 revoke/correct/restore，不随 BoardItem删除 | Memory Review/retrieval derive；truth/provenance/ops 必备份 | 只凭 `memory_scope`、来源矛盾、普通白板卡误升格 |
| Card forward relation | `memory_card_relations` | Markdown `hereiam-card:` link；`card_link_index` 派生 | 正向 Markdown | stable card_id + readable title | migrate 为 from-card新 revision；rollback重建 relation rows | 随 revision变化；target tombstone仍保留断链状态 | backlinks derive；revision备份即可 | dangling target、方向无法确定、重复 ID冲突 |
| Memory structured fields / corrections | JSON fields + `user_corrections` | 独立 domain operation/projection；user correction immutable op | accepted operation/领域记录 | card/truth/provenance | preserve user-corrected；machine fields derive；rollback按 operation回投 | correction 不物理覆盖历史 | projection rebuild；ops必备份 | 字段类型未知且无法完整 compatibility保全 |
| Card asset/provenance relation | `memory_card_assets`, `assets` | typed asset/source/provenance relation；asset stable ID/hash | object bytes + relation operation | card/source/version/object | source/display migrate；legacy evidence只作 proposal attachment | relation tombstone；object按引用/retention恢复 | previews derive；objects/manifests必备份 | missing bytes/ref/hash、把 evidence role升 Claim |
| SourceContent | `whiteboard_sources.id` | 原 `source_id` → `source_contents` | catalog状态 + current version；原件不进 Markdown | SourceVersion/Card | preserve/migrate列；rollback保留同 ID/object | tombstone/quarantine/restore verified version | OCR/preview derive；metadata+objects必备份 | canonical collision不同 bytes、对象不可验、placeholder Source |
| SourceVersion | `whiteboard_source_versions.id` | 原 `version_id` → `source_versions` immutable | content hash + object bytes | source/anchor/evidence | preserve ID/hash；同 bytes可去重object不合并逻辑版本 | immutable；Source删除不抹掉仍被Claim引用版本 | parser/search derive；version/object必备份 | hash mismatch、mutable bytes、missing source |
| RichTextDocument | v2 JSON file/cache + current repository path | 无独立正文表；仅 editor cache keyed by `(card_id,revision_hash)` | 目标 Markdown；RichText永不独立提交 | asset refs / card refs only | compatibility-only；按逐元素分类转换；rollback由 Markdown确定性重建 | cache可删重建 | plain text derive；不要求备份cache | unclassified block/mark/asset/schema、IME未commit、fingerprint mismatch |
| Saved Card history | RichText/operation/legacy snapshots，覆盖不完整 | immutable `card_revisions` + parent hash + operation | revision bytes/lineage | card/operation | migrate可证明历史；无法绑定者保全为 `legacy_unbound_revision` | history不可就地改；delete由tombstone屏障 | history必备份 | 伪造 parent、用mtime排序、遗漏已承诺revision |
| Board | `whiteboard_boards.id` | 原 `board_id`，保留结构化表 | Board status/layout域 | item/group/edge | preserve；只改 card ref target；rollback同 ID | 删除 Board不删 Card/Source；恢复板结构 | snapshot derive；board ops必备份 | 引用集合不闭合或board ID冲突 |
| BoardItem | `whiteboard_board_items.id` | 原 `item_id`，`card_id` 指向 `cards` | 布局/局部view结构化状态 | board/card | preserve exact placement；rollback不复制正文 | 删除 placement 不删 Card | viewport/snapshot derive；操作备份 | dangling card 在迁移结束仍未分类 |
| BoardGroup / GroupMember | group/member tables | 原 IDs / composite membership | 结构化白板状态 | board/item | preserve | 删除 group仅删membership | snapshot derive；ops备份 | dangling/重复membership无法确定 |
| BoardEdge | edge table | 原 `edge_id` | 结构化 edge，不改 Markdown语义链接 | board/from item/to item | preserve | tombstone/restore edge | snapshot derive；ops备份 | dangling item/direction unknown |
| Annotation Card | `CardKind.annotation` + Card body | 中性 Card + Markdown revision | Card Markdown；annotation owner/role metadata | anchor IDs | migrate Card；不并入 Source或另一个annotation | Card tombstone；Anchor独立保留 | text derive；revision备份 | owner冲突、body冲突、Anchor无有效版本 |
| Anchor | presentation JSON `anchor` | 原/确定性 `anchor_id` → `anchors` | exact SourceVersion + selector/fingerprint | source/version/annotation/evidence | migrate only valid tuple；ambiguous待确认；rollback重嵌 compatibility JSON | orphaned不是删除；旧版本保留可恢复 | location index derive；Anchor必备份 | missing version/selector/fingerprint、猜测重锚 |
| TimedText / media selector | track/cue/player领域结构 | SourceVersion scoped track/cue + Anchor selector | timed text/version domain | source version/anchor | preserve，不塞 Card正文 | 来源政策删除；annotation不覆盖track | cue search derive；合法原件/metadata备份 | 不可靠字幕伪装可靠、跨版本时间猜测 |
| EvidenceClaim | 当前无独立生产表；asset/evidence metadata不是Claim | stable `evidence_id` → immutable `evidence_claims` | Claim ledger + supersede/retract op | exact SourceVersion/Anchor | 现有 attachment只 degraded-preserved proposal；**不自动造 Claim**；后续 Gate新建 | retract不改旧Claim；恢复读lineage | Evidence Card/report derive；claims/provenance必备份 | 缺精确来源、把搜索/OCR/asset role升Claim、in-place edit |
| Dreaming Fragment | `memory_fragments.id` | 保留 fragment domain/stable ID | relationship-memory operation/status | stable chat sync IDs/entity | preserve；不转 Card/truth；rollback保留原表 | status delete/restore按Dreaming policy | FTS derive；fragments/source lineage备份 | 只有本机message int且无法保全/解析、自动truth promotion |
| Dreaming Episode / Saga / Snapshot | 独立 tables/IDs | 保留各稳定 ID/lineage | Dreaming domain；snapshot非Card正文 | fragment/entity/episode IDs | preserve | status/tombstone；snapshot不可覆盖current | FTS/summary derive；domain+snapshots备份 | dangling lineage无法隔离、误并入Card/truth |
| Memory Entity / Link | `memory_entities`, `memory_entity_links` | 保留关系记忆域 | domain operation/status | fragment/card/episode stable IDs | preserve并更新 card ref target | merge/delete有显式 op | graph index derive；entity/link ops备份 | local-only unresolved ref被当跨端证据 |
| Project Memory | `project_memory_*` | 保留 Memory V3特殊domain | Project Memory operation/projection | project/source/closeout refs | preserve；不转普通User-truth | 按项目policy | projection derive；accepted inputs/ops备份 | 跨项目污染或自动truth promotion |
| TaskRoom / TaskDecision | `task_rooms`, `task_decisions` | 保留 stable IDs/task lane | task operation/status | task/board | preserve | archive/delete/decision supersede显式 | task UI derive；ops/decisions备份 | 主聊天/Memory lane泄漏、archive冒充永久删除 |
| TaskArtifact | `task_artifacts.id` | 原 ID + `artifact_promotions` | task artifact状态 | task/storage ref | preserve；promotion单独 explicit intent；rollback保留promotion map | archive/delete不删已独立promote对象 | task search derive；artifact/ops备份 | 自动建Card/Source/truth、授权不明、partial promotion |
| Capture | 现有入口/临时payload，无统一权威表 | stable `capture_id` → `captures` | intake ledger状态 | installation / candidate | migrate已可证明pending；重试同 key；rollback不materialize | cancel/expire barrier；restart持久状态 | queue counts derive；accepted intake按policy备份 | Core接受前或intake接受后自动建下游；同 key异 digest固定 `classification=blocked` 且零 accepted target/head/manifest/receipt/change/projection/downstream |
| ImportCandidate | parser/导入临时状态 | stable `import_candidate_id` | candidate phase/attempt generation | capture/inbox | migrate pending only with完整payload；retry新attempt同candidate | cancel/failure终态；restart phase恢复 | diagnostics derive；accepted candidate/decision备份 | parser success冒充Source、迟到result越cancel、临时路径猜phase；同 key异 digest固定 blocked与零 target/head/manifest/receipt/change/projection/downstream |
| Link Inbox Item | URL/note临时抽取 | stable `link_inbox_item_id`, unique dedupe key | inbox ledger状态 | candidate/capture | canonical URL or provider note-id dedupe；rollback保留identity | cancel/remove/expire；failed/needs_screenshot诚实 | counters derive；accepted ledger备份 | hidden crawl/WebView fallback、接受前索引；同 key异 digest固定 blocked与零 target/head/manifest/receipt/change/projection/downstream |
| Chat message | `persona_chat_messages`, stable `sync_id`逐步补齐 | Core chat log（1A-3） | immutable chat change | sync_id/provenance | 不在1A-1/2改writer；稳定ref用于truth provenance | retract/delete按chat op | recent/search derive；accepted log备份 | ordinary chat自动truth、local int作为跨端证据 |
| Activity event / shadow | 当前ingress unsupported / device-local | future Core activity ledger | accepted raw evidence；shadow derive | event/device/probe | 1A-0只保留合同，不迁移生产 | retention/revoke按P3 | shadow derive；按1天policy备份/到期 | network/silence/HR推断状态、借本迁移启用ingress |
| Domain operation / Receipt / Change | `memory_card_operations`及各域零散日志 | append-only `domain_operations` + receipts/changes | 本身是结构化权威 | object/revision/epoch | preserve IDs/digests；无法绑定revision明确标 legacy | 不物理改历史；reversal新op | 全部必备份 | ghost receipt、重复change、伪造parent/epoch |
| Tombstone / app trash | extras `deleted_at`及各域status，语义不一 | `object_tombstones` + managed trash | delete barrier/last valid ref | object/revision/version | migrate可证明delete；rollback服从tombstone | 30天产品窗口；永久删除受backup policy | online index立即排除；tombstone必备份 | 外删造空Card、旧backup复活、缺last valid source |
| FTS / backlink / preview / embedding / RichText cache | 多处现有projection | derived tables keyed by source hash/version | 从不权威 | accepted revision/domain op | rebuild；不作为迁移winner | 随源失效/重建 | 可不备份 | stale projection覆盖正文、index先于acceptance |
| Vault/object/SQLite backup | 当前S3/快照能力不等于对象Gate | manifest绑定epoch/journal watermark/digests | recovery media | authority state/objects/tombstones | migration前离线救援快照；真实演练Gate 1C | 新backup排除deleted，旧immutable按policy到期 | 不索引为在线state | 把backup当writer、manifest缺tombstone/journal、声称已真实恢复 |

## Machine catalog Gate

Harness 的 machine catalog 必须恰好包含下面 32 个 `objectType`，顺序可以变化，但不得缺失、重复或增加兜底：

```text
[
  neutral_card,
  user_truth,
  card_forward_relation,
  memory_structured_correction,
  card_asset_provenance_relation,
  source_content,
  source_version,
  rich_text_document,
  card_revision_history,
  board,
  board_item,
  board_group_membership,
  board_edge,
  annotation_card,
  anchor,
  timed_text_media_selector,
  evidence_claim,
  dreaming_fragment,
  dreaming_episode_saga,
  memory_entity_link,
  project_memory,
  task_room_decision,
  task_artifact,
  capture,
  import_candidate,
  link_inbox_item,
  chat_message,
  activity_event_shadow,
  domain_operation_receipt_change,
  tombstone_trash,
  derived_index_cache,
  backup_manifest
]
```

### Exact nested schema

每个 row 顶层必须**恰好**包含以下九个 key；原八个 machine field保留，`objectType` 是 Formal32 identity：

```text
objectType
classification
stableIdMapping
authority
refs
rollback
deleteRecovery
indexBackup
blockedReason
```

逐层 exact validation：

1. `classification` allow-list恰为 `preserve|migrate|derive|compatibility-only|degraded-preserved|blocked`。
2. `stableIdMapping` 恰为 `{entries:[...]}`；`entries` 非空，每项恰含
   `legacyKind,targetKind,mode,sourceFields,targetField,fallbackAlgorithm,guard`。`mode` allow-list恰为
   `preserve|derive_composite|allocate_digest_if_missing|not_applicable|blocked`。
3. `sourceFields` 是字符串数组；其他 entry字段均为非 null字符串。仅 `allocate_digest_if_missing` 的
   `fallbackAlgorithm` 可为 `deterministic_namespace_plus_payload_sha256`；其他 mode必须是空字符串。
   `preserve` 必须原值映射；`derive_composite` 必须具名列全组成字段；`blocked/not_applicable` 不能产 target ID。
4. `rollback` 恰含 `strategy,preserveAcceptedNewWrites,appendOnly,reconstructFromAuthority`；后三项必须是 literal bool，
   不得由共用 constructor默认填充。`reconstructFromAuthority=true` 只允许 cache/index projection。
5. `deleteRecovery` 恰含 `strategy,tombstoneBarrier,physicalDeleteAllowed,recoverySource`；两项 bool逐行 literal。
   cache/media的 physical delete不代表允许越过 source/object tombstone恢复旧权威。
6. `indexBackup` 恰含 `rebuildFrom,backupRequired,excludedFromBackup`，三个值都必须是字符串数组；空数组是明确的
   “无”，不能替换成 null、`contract-bound` 或 prose default。
7. `refs` 是逐行 literal字符串数组。所有 object、entry、array都拒绝 extra/missing key、null、unknown/default。
8. 非 blocked row 的 `blockedReason` 必须是空字符串；blocked row必须非空且来自下面 exact allow-list：

```text
[
  duplicate_identity_payload_mismatch, body_conflict, unsupported_kind_or_owner, rollback_unrepresentable,
  truth_authorization_missing, provenance_conflict, dangling_reference, relation_direction_undetermined,
  structured_field_unclassified, asset_bytes_missing, asset_hash_mismatch, evidence_role_escalation,
  source_canonical_collision, source_version_mutable, source_version_missing, richtext_element_unclassified,
  ime_composition_uncommitted, richtext_fingerprint_mismatch, revision_lineage_unbound,
  board_reference_set_not_closed, board_item_reference_unclassified, membership_identity_ambiguous,
  anchor_tuple_invalid, anchor_retarget_ambiguous, timed_selector_unreliable,
  evidence_claim_promotion_forbidden, dreaming_lineage_unresolved, project_scope_violation,
  task_lane_leak, artifact_promotion_unauthorized, artifact_promotion_partial,
  intake_key_digest_conflict, intake_payload_incomplete, intake_cancel_barrier,
  parser_result_after_cancel, link_fetch_fallback_forbidden, chat_sync_id_missing,
  activity_migration_forbidden, operation_lineage_unbound, ghost_receipt, duplicate_change,
  tombstone_source_missing, projection_before_acceptance, backup_manifest_incomplete,
  backup_restore_unproven
]
```

### Formal32 exact literals

下列 JSON 是上方九列矩阵按原顺序的一对一 machine transcription，也是 harness必须复制并 pin digest的唯一 literal；
prose table与 literal冲突时 Gate立即红，不能由 converter自行选一边。

```json
[
  {
    "objectType": "neutral_card", "classification": "migrate",
    "stableIdMapping": {"entries": [
      {"legacyKind":"memory_card","targetKind":"card","mode":"preserve","sourceFields":["memory_cards.id"],"targetField":"cards.card_id","fallbackAlgorithm":"","guard":"id present and payload consistent; else blocked:duplicate_identity_payload_mismatch"},
      {"legacyKind":"legacy_card_body","targetKind":"card_revision","mode":"derive_composite","sourceFields":["card_id","canonical_markdown_sha256"],"targetField":"card_revisions.revision_hash","fallbackAlgorithm":"","guard":"body classified and rollback representable"}
    ]},
    "authority":"markdown_head_revision", "refs":["board_id","source_id","anchor_id","linked_card_id"],
    "rollback":{"strategy":"project accepted heads to legacy dual tables and retain revision map","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"card tombstone plus 30-day recovery; external absence is externally_missing","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"last accepted card revision and tombstone ledger"},
    "indexBackup":{"rebuildFrom":["card_revisions","domain_operations"],"backupRequired":["cards","card_revisions","markdown_envelopes","domain_operations","object_tombstones"],"excludedFromBackup":["fts","backlinks","previews","editor_richtext_cache"]}, "blockedReason":""
  },
  {
    "objectType":"user_truth", "classification":"migrate",
    "stableIdMapping":{"entries":[
      {"legacyKind":"memory_card","targetKind":"card","mode":"preserve","sourceFields":["memory_cards.id"],"targetField":"cards.card_id","fallbackAlgorithm":"","guard":"card identity and explicit truth authorization verified"},
      {"legacyKind":"explicit_truth_evidence","targetKind":"user_truth_relation","mode":"derive_composite","sourceFields":["card_id","provenance_digest","truth_operation_kind"],"targetField":"user_truth_relations.relation_id","fallbackAlgorithm":"","guard":"explicit record/correction/external-data evidence; else blocked:truth_authorization_missing"},
      {"legacyKind":"truth_provenance","targetKind":"provenance_record","mode":"derive_composite","sourceFields":["card_id","provenance_digest"],"targetField":"provenance_records.provenance_id","fallbackAlgorithm":"","guard":"source/version provenance internally consistent"}
    ]},
    "authority":"user_truth_relation_and_operation", "refs":["card_id","provenance_id","source_id","source_version_id"],
    "rollback":{"strategy":"restore legacy Memory read projection from accepted truth operations","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"append revoke/correct/restore operation independent of BoardItem","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"truth operation and provenance lineage"},
    "indexBackup":{"rebuildFrom":["user_truth_relations","domain_operations"],"backupRequired":["user_truth_relations","provenance_records","domain_operations"],"excludedFromBackup":["memory_review_projection","retrieval_index"]}, "blockedReason":""
  },
  {
    "objectType":"card_forward_relation", "classification":"migrate",
    "stableIdMapping":{"entries":[
      {"legacyKind":"memory_card_relation","targetKind":"markdown_card_link","mode":"derive_composite","sourceFields":["from_card_id","to_card_id","relation_kind"],"targetField":"card_revision_markdown_link.link_identity","fallbackAlgorithm":"","guard":"direction and both stable card IDs verified"}
    ]},
    "authority":"forward_markdown_link", "refs":["from_card_id","to_card_id"],
    "rollback":{"strategy":"rebuild legacy relation rows from accepted from-card revisions","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"revision change removes active link while target tombstone preserves broken-link identity","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"from-card revision lineage and target tombstone"},
    "indexBackup":{"rebuildFrom":["card_revisions"],"backupRequired":["card_revisions","markdown_envelopes"],"excludedFromBackup":["card_link_index","backlinks"]}, "blockedReason":""
  },
  {
    "objectType":"memory_structured_correction", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"user_correction","targetKind":"domain_operation","mode":"preserve","sourceFields":["user_corrections.id"],"targetField":"domain_operations.operation_id","fallbackAlgorithm":"","guard":"correction ID and corrected field binding verified"},
      {"legacyKind":"structured_json_field","targetKind":"structured_field_projection_key","mode":"derive_composite","sourceFields":["card_id","field_path"],"targetField":"structured_field_projection.projection_key","fallbackAlgorithm":"","guard":"field type classified; machine field remains derived"}
    ]},
    "authority":"accepted_correction_operation", "refs":["card_id","truth_relation_id","provenance_id","field_path"],
    "rollback":{"strategy":"project accepted correction operations to legacy structured fields","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"never overwrite correction history; append reversal or recovery operation","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"correction operation lineage"},
    "indexBackup":{"rebuildFrom":["domain_operations"],"backupRequired":["domain_operations","user_corrections"],"excludedFromBackup":["structured_field_projection"]}, "blockedReason":""
  },
  {
    "objectType":"card_asset_provenance_relation", "classification":"migrate",
    "stableIdMapping":{"entries":[
      {"legacyKind":"asset","targetKind":"asset_object","mode":"preserve","sourceFields":["assets.id"],"targetField":"asset_objects.asset_id","fallbackAlgorithm":"","guard":"bytes and declared hash verified"},
      {"legacyKind":"memory_card_asset_relation","targetKind":"asset_source_provenance_relation","mode":"derive_composite","sourceFields":["card_id","asset_id","source_version_id","role"],"targetField":"asset_source_provenance_relations.relation_id","fallbackAlgorithm":"","guard":"role classified; evidence role remains proposal attachment"}
    ]},
    "authority":"object_bytes_and_relation_operation", "refs":["card_id","asset_id","source_id","source_version_id"],
    "rollback":{"strategy":"project accepted source/display relations without promoting evidence to Claim","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"relation tombstone; object recovery follows reference and retention policy","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"relation operation and verified object manifest"},
    "indexBackup":{"rebuildFrom":["asset_source_provenance_relations","asset_object_manifest"],"backupRequired":["asset_objects","asset_object_manifest","provenance_records","domain_operations"],"excludedFromBackup":["asset_previews"]}, "blockedReason":""
  },
  {
    "objectType":"source_content", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"whiteboard_source","targetKind":"source_content","mode":"preserve","sourceFields":["whiteboard_sources.id"],"targetField":"source_contents.source_id","fallbackAlgorithm":"","guard":"canonical identity has one verified byte lineage"}
    ]},
    "authority":"source_catalog_and_current_version", "refs":["source_version_id","card_id"],
    "rollback":{"strategy":"retain source ID and verified objects in legacy source projection","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"tombstone or quarantine and restore only a verified version","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"source catalog and immutable source versions"},
    "indexBackup":{"rebuildFrom":["source_versions"],"backupRequired":["source_contents","source_versions","object_manifest","source_objects"],"excludedFromBackup":["ocr_index","source_preview"]}, "blockedReason":""
  },
  {
    "objectType":"source_version", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"whiteboard_source_version","targetKind":"source_version","mode":"preserve","sourceFields":["whiteboard_source_versions.id"],"targetField":"source_versions.version_id","fallbackAlgorithm":"","guard":"immutable bytes match content hash and source exists"},
      {"legacyKind":"source_object_bytes","targetKind":"content_addressed_object","mode":"derive_composite","sourceFields":["content_sha256"],"targetField":"object_manifest.object_id","fallbackAlgorithm":"","guard":"hash verified; logical versions are not merged"}
    ]},
    "authority":"immutable_source_version_bytes", "refs":["source_id","object_id","anchor_id","evidence_id"],
    "rollback":{"strategy":"retain immutable version ID/hash and legacy source-version projection","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"source deletion cannot erase a version referenced by Claim","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"immutable source version and object manifest"},
    "indexBackup":{"rebuildFrom":["source_versions","source_objects"],"backupRequired":["source_versions","object_manifest","source_objects"],"excludedFromBackup":["parser_output","source_search_index"]}, "blockedReason":""
  },
  {
    "objectType":"rich_text_document", "classification":"compatibility-only",
    "stableIdMapping":{"entries":[
      {"legacyKind":"richtext_editor_cache","targetKind":"editor_cache","mode":"not_applicable","sourceFields":["card_id","revision_hash"],"targetField":"not_applicable","fallbackAlgorithm":"","guard":"cache never receives authoritative identity"},
      {"legacyKind":"unclassified_richtext_element","targetKind":"richtext_compatibility_capsule","mode":"allocate_digest_if_missing","sourceFields":["card_id","revision_hash","raw_sha256"],"targetField":"compatibility_capsules.capsule_id","fallbackAlgorithm":"deterministic_namespace_plus_payload_sha256","guard":"only when complete reversible raw bytes are preserved; never body authority"}
    ]},
    "authority":"markdown_revision_only", "refs":["card_id","revision_hash","asset_id","linked_card_id"],
    "rollback":{"strategy":"rebuild compatibility RichText from accepted Markdown; preserve capsule bytes only","preserveAcceptedNewWrites":false,"appendOnly":false,"reconstructFromAuthority":true},
    "deleteRecovery":{"strategy":"delete/rebuild editor cache; capsule follows owning revision retention","tombstoneBarrier":false,"physicalDeleteAllowed":true,"recoverySource":"accepted Markdown revision plus reversible compatibility capsule"},
    "indexBackup":{"rebuildFrom":["card_revisions"],"backupRequired":["compatibility_capsules"],"excludedFromBackup":["richtext_editor_cache","plain_text_cache"]}, "blockedReason":""
  },
  {
    "objectType":"card_revision_history", "classification":"migrate",
    "stableIdMapping":{"entries":[
      {"legacyKind":"identified_revision_or_operation","targetKind":"card_revision","mode":"preserve","sourceFields":["legacy_revision_or_operation_id"],"targetField":"card_revisions.legacy_identity","fallbackAlgorithm":"","guard":"identity binds one card, parent and content digest"},
      {"legacyKind":"unidentified_legacy_snapshot","targetKind":"legacy_unbound_revision","mode":"allocate_digest_if_missing","sourceFields":["card_id","parent_revision_hash","content_sha256"],"targetField":"card_revisions.revision_hash","fallbackAlgorithm":"deterministic_namespace_plus_payload_sha256","guard":"card, parent and content digest all bind; else blocked:revision_lineage_unbound"}
    ]},
    "authority":"immutable_revision_bytes_and_lineage", "refs":["card_id","parent_revision_hash","operation_id"],
    "rollback":{"strategy":"project provable lineage while retaining unbound legacy preservation records","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"history is immutable; card delete is represented by tombstone","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"revision lineage and card tombstone"},
    "indexBackup":{"rebuildFrom":["card_revisions"],"backupRequired":["card_revisions","markdown_envelopes","domain_operations"],"excludedFromBackup":["history_index"]}, "blockedReason":""
  },
  {
    "objectType":"board", "classification":"preserve",
    "stableIdMapping":{"entries":[{"legacyKind":"whiteboard_board","targetKind":"board","mode":"preserve","sourceFields":["whiteboard_boards.id"],"targetField":"boards.board_id","fallbackAlgorithm":"","guard":"board ID unique and reference set closed"}]},
    "authority":"board_status_and_layout_domain", "refs":["board_item_id","board_group_id","board_edge_id"],
    "rollback":{"strategy":"restore same board ID and accepted board state","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"board tombstone preserves recoverable structure without deleting Card/Source","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"board state operations and tombstone"},
    "indexBackup":{"rebuildFrom":["boards","board_operations"],"backupRequired":["boards","board_operations"],"excludedFromBackup":["board_snapshot"]}, "blockedReason":""
  },
  {
    "objectType":"board_item", "classification":"preserve",
    "stableIdMapping":{"entries":[{"legacyKind":"whiteboard_board_item","targetKind":"board_item","mode":"preserve","sourceFields":["whiteboard_board_items.id"],"targetField":"board_items.item_id","fallbackAlgorithm":"","guard":"board and card references classified"}]},
    "authority":"board_placement_state", "refs":["board_id","card_id"],
    "rollback":{"strategy":"restore exact accepted placement without copying Card body","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"placement tombstone never deletes referenced Card","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"board item operation and board tombstone"},
    "indexBackup":{"rebuildFrom":["board_items","board_operations"],"backupRequired":["board_items","board_operations"],"excludedFromBackup":["viewport_cache","board_snapshot"]}, "blockedReason":""
  },
  {
    "objectType":"board_group_membership", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"board_group","targetKind":"board_group","mode":"preserve","sourceFields":["board_groups.id"],"targetField":"board_groups.group_id","fallbackAlgorithm":"","guard":"group ID and board binding verified"},
      {"legacyKind":"board_group_member","targetKind":"board_group_membership","mode":"derive_composite","sourceFields":["group_id","item_id"],"targetField":"board_group_memberships.membership_id","fallbackAlgorithm":"","guard":"membership unique and both references valid"}
    ]},
    "authority":"structured_board_group_state", "refs":["board_id","group_id","item_id"],
    "rollback":{"strategy":"restore accepted groups and exact composite memberships","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"group tombstone removes membership only, never BoardItem/Card","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"group and membership operations"},
    "indexBackup":{"rebuildFrom":["board_groups","board_group_memberships"],"backupRequired":["board_groups","board_group_memberships","board_operations"],"excludedFromBackup":["board_snapshot"]}, "blockedReason":""
  },
  {
    "objectType":"board_edge", "classification":"preserve",
    "stableIdMapping":{"entries":[{"legacyKind":"board_edge","targetKind":"board_edge","mode":"preserve","sourceFields":["edge.id"],"targetField":"board_edges.edge_id","fallbackAlgorithm":"","guard":"from/to items and direction verified"}]},
    "authority":"structured_board_edge_state", "refs":["board_id","from_item_id","to_item_id"],
    "rollback":{"strategy":"restore same edge ID and accepted direction","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"edge tombstone and explicit restore","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"edge operation and tombstone"},
    "indexBackup":{"rebuildFrom":["board_edges"],"backupRequired":["board_edges","board_operations"],"excludedFromBackup":["board_graph_index","board_snapshot"]}, "blockedReason":""
  },
  {
    "objectType":"annotation_card", "classification":"migrate",
    "stableIdMapping":{"entries":[{"legacyKind":"annotation_card","targetKind":"card","mode":"preserve","sourceFields":["memory_cards.id"],"targetField":"cards.card_id","fallbackAlgorithm":"","guard":"CardKind.annotation owner and body consistent"}]},
    "authority":"card_markdown_and_annotation_role_metadata", "refs":["anchor_id"],
    "rollback":{"strategy":"project accepted annotation Card revision without merging Source or another annotation","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"Card tombstone while Anchor remains independently recoverable","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"annotation Card revision and anchor catalog"},
    "indexBackup":{"rebuildFrom":["card_revisions","anchors"],"backupRequired":["cards","card_revisions","anchors"],"excludedFromBackup":["annotation_text_index"]}, "blockedReason":""
  },
  {
    "objectType":"anchor", "classification":"migrate",
    "stableIdMapping":{"entries":[
      {"legacyKind":"identified_anchor","targetKind":"anchor","mode":"preserve","sourceFields":["anchor_id"],"targetField":"anchors.anchor_id","fallbackAlgorithm":"","guard":"exact SourceVersion selector and fingerprint valid"},
      {"legacyKind":"anchor_without_id","targetKind":"anchor","mode":"derive_composite","sourceFields":["source_version_id","selector_fingerprint"],"targetField":"anchors.anchor_id","fallbackAlgorithm":"","guard":"both fields exact; ambiguity blocked:anchor_retarget_ambiguous"}
    ]},
    "authority":"source_version_selector_fingerprint_tuple", "refs":["source_id","source_version_id","annotation_card_id","evidence_id"],
    "rollback":{"strategy":"embed exact compatibility JSON without guessing re-anchor","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"orphan state is not deletion; retain old SourceVersion for recovery","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"anchor tuple and immutable source version"},
    "indexBackup":{"rebuildFrom":["anchors","source_versions"],"backupRequired":["anchors","source_versions"],"excludedFromBackup":["anchor_location_index"]}, "blockedReason":""
  },
  {
    "objectType":"timed_text_media_selector", "classification":"preserve",
    "stableIdMapping":{"entries":[{"legacyKind":"timed_track_cue_selector","targetKind":"source_version_timed_selector","mode":"derive_composite","sourceFields":["source_version_id","track_id","cue_id","selector_fingerprint"],"targetField":"timed_text_selectors.selector_id","fallbackAlgorithm":"","guard":"track/cue/version binding reliable; no cross-version time guess"}]},
    "authority":"timed_text_version_domain", "refs":["source_version_id","anchor_id","track_id","cue_id"],
    "rollback":{"strategy":"restore exact version-scoped track/cue selector outside Card body","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"source retention policy controls track; annotation cannot overwrite it","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"source version timed-text metadata and legal source object"},
    "indexBackup":{"rebuildFrom":["timed_text_selectors","source_versions"],"backupRequired":["timed_text_metadata","legal_source_objects"],"excludedFromBackup":["cue_search_index"]}, "blockedReason":""
  },
  {
    "objectType":"evidence_claim", "classification":"degraded-preserved",
    "stableIdMapping":{"entries":[{"legacyKind":"legacy_evidence_attachment","targetKind":"evidence_proposal","mode":"derive_composite","sourceFields":["asset_id","source_version_id","anchor_id","role"],"targetField":"evidence_proposals.proposal_id","fallbackAlgorithm":"","guard":"targetKind is proposal only; creating evidence_claim is blocked:evidence_claim_promotion_forbidden"}]},
    "authority":"evidence_claim_ledger_only_after_future_explicit_gate", "refs":["source_version_id","anchor_id","asset_id"],
    "rollback":{"strategy":"preserve proposal and any future explicit Claim lineage without attachment promotion","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"append retract/supersede; never edit immutable Claim in place","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"proposal or Claim lineage and exact source version"},
    "indexBackup":{"rebuildFrom":["evidence_proposals","evidence_claims"],"backupRequired":["evidence_proposals","evidence_claims","provenance_records","domain_operations"],"excludedFromBackup":["evidence_card_projection","evidence_report_projection"]}, "blockedReason":""
  },
  {
    "objectType":"dreaming_fragment", "classification":"preserve",
    "stableIdMapping":{"entries":[{"legacyKind":"memory_fragment","targetKind":"dreaming_fragment","mode":"preserve","sourceFields":["memory_fragments.id"],"targetField":"dreaming_fragments.fragment_id","fallbackAlgorithm":"","guard":"fragment lineage and stable chat sync refs preserved"}]},
    "authority":"dreaming_fragment_operation_and_status", "refs":["chat_sync_id","memory_entity_id","episode_id"],
    "rollback":{"strategy":"retain original fragment domain and accepted relationship-memory operations","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"status delete/restore under Dreaming policy","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"fragment operation and source lineage"},
    "indexBackup":{"rebuildFrom":["dreaming_fragments","dreaming_operations"],"backupRequired":["dreaming_fragments","dreaming_operations","source_lineage"],"excludedFromBackup":["dreaming_fts"]}, "blockedReason":""
  },
  {
    "objectType":"dreaming_episode_saga", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"dreaming_episode","targetKind":"dreaming_episode","mode":"preserve","sourceFields":["episodes.id"],"targetField":"dreaming_episodes.episode_id","fallbackAlgorithm":"","guard":"episode lineage valid"},
      {"legacyKind":"dreaming_saga","targetKind":"dreaming_saga","mode":"preserve","sourceFields":["sagas.id"],"targetField":"dreaming_sagas.saga_id","fallbackAlgorithm":"","guard":"saga lineage valid"},
      {"legacyKind":"dreaming_snapshot","targetKind":"dreaming_snapshot","mode":"preserve","sourceFields":["snapshots.id"],"targetField":"dreaming_snapshots.snapshot_id","fallbackAlgorithm":"","guard":"snapshot binds episode/saga and never overwrites current state"}
    ]},
    "authority":"dreaming_episode_saga_domain", "refs":["fragment_id","memory_entity_id","episode_id","saga_id"],
    "rollback":{"strategy":"retain each accepted domain ID and lineage","preserveAcceptedNewWrites":true,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"status/tombstone; immutable snapshot cannot overwrite current","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"episode/saga lineage and immutable snapshots"},
    "indexBackup":{"rebuildFrom":["dreaming_episodes","dreaming_sagas","dreaming_snapshots"],"backupRequired":["dreaming_episodes","dreaming_sagas","dreaming_snapshots","dreaming_operations"],"excludedFromBackup":["dreaming_summary_projection","dreaming_fts"]}, "blockedReason":""
  },
  {
    "objectType":"memory_entity_link", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"memory_entity","targetKind":"memory_entity","mode":"preserve","sourceFields":["memory_entities.id"],"targetField":"memory_entities.entity_id","fallbackAlgorithm":"","guard":"entity stable ID and scope valid"},
      {"legacyKind":"memory_entity_link","targetKind":"memory_entity_link","mode":"preserve","sourceFields":["memory_entity_links.id"],"targetField":"memory_entity_links.link_id","fallbackAlgorithm":"","guard":"both endpoint IDs and relation semantics valid"}
    ]},
    "authority":"memory_entity_operation_and_status", "refs":["fragment_id","card_id","episode_id","memory_entity_id"],
    "rollback":{"strategy":"retain entities/links and update only stable Card ref target","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"merge/delete/recover only by explicit domain operation","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"entity/link operation lineage"},
    "indexBackup":{"rebuildFrom":["memory_entities","memory_entity_links","domain_operations"],"backupRequired":["memory_entities","memory_entity_links","domain_operations"],"excludedFromBackup":["memory_entity_graph_index"]}, "blockedReason":""
  },
  {
    "objectType":"project_memory", "classification":"preserve",
    "stableIdMapping":{"entries":[{"legacyKind":"project_memory_record","targetKind":"project_memory_record","mode":"preserve","sourceFields":["project_memory_stable_id"],"targetField":"project_memory_records.project_memory_id","fallbackAlgorithm":"","guard":"project space and source/closeout binding verified; missing stable ID blocked:project_scope_violation"}]},
    "authority":"project_memory_operation_and_projection", "refs":["project_id","source_id","closeout_id"],
    "rollback":{"strategy":"retain accepted project-memory inputs and operations without User-truth promotion","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"project policy expressed through scoped operation/tombstone","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"project-scoped operation lineage"},
    "indexBackup":{"rebuildFrom":["project_memory_operations"],"backupRequired":["project_memory_accepted_inputs","project_memory_operations"],"excludedFromBackup":["project_memory_projection","project_memory_index"]}, "blockedReason":""
  },
  {
    "objectType":"task_room_decision", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"task_room","targetKind":"task_room","mode":"preserve","sourceFields":["task_rooms.id"],"targetField":"task_rooms.task_room_id","fallbackAlgorithm":"","guard":"task lane binding valid"},
      {"legacyKind":"task_decision","targetKind":"task_decision","mode":"preserve","sourceFields":["task_decisions.id"],"targetField":"task_decisions.decision_id","fallbackAlgorithm":"","guard":"decision binds stable task room"}
    ]},
    "authority":"task_operation_and_status", "refs":["task_room_id","task_id","board_id"],
    "rollback":{"strategy":"retain task-room and decision IDs plus supersede operations","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"archive/delete/decision supersede is explicit operation","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"task operation and decision lineage"},
    "indexBackup":{"rebuildFrom":["task_rooms","task_decisions","task_operations"],"backupRequired":["task_rooms","task_decisions","task_operations"],"excludedFromBackup":["task_ui_projection","task_search_index"]}, "blockedReason":""
  },
  {
    "objectType":"task_artifact", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"task_artifact","targetKind":"task_artifact","mode":"preserve","sourceFields":["task_artifacts.id"],"targetField":"task_artifacts.artifact_id","fallbackAlgorithm":"","guard":"artifact storage ref valid"},
      {"legacyKind":"explicit_artifact_promotion","targetKind":"artifact_promotion","mode":"derive_composite","sourceFields":["artifact_id","promotion_intent_id","target_kind"],"targetField":"artifact_promotions.promotion_id","fallbackAlgorithm":"","guard":"explicit authorization and atomic promotion complete"}
    ]},
    "authority":"task_artifact_status_and_promotion_ledger", "refs":["task_room_id","storage_ref","promoted_object_id"],
    "rollback":{"strategy":"retain artifact and promotion map without deleting independently promoted object","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"artifact archive/delete does not delete promoted object","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"artifact status and promotion ledger"},
    "indexBackup":{"rebuildFrom":["task_artifacts","artifact_promotions"],"backupRequired":["task_artifacts","artifact_promotions","artifact_objects","task_operations"],"excludedFromBackup":["task_artifact_search_index"]}, "blockedReason":""
  },
  {
    "objectType":"capture", "classification":"migrate",
    "stableIdMapping":{"entries":[{"legacyKind":"capture_without_stable_id","targetKind":"capture","mode":"allocate_digest_if_missing","sourceFields":["installation_id","intake_idempotency_key","payload_digest"],"targetField":"captures.capture_id","fallbackAlgorithm":"deterministic_namespace_plus_payload_sha256","guard":"allocate once and persist permanent map; same key different digest blocked:intake_key_digest_conflict"}]},
    "authority":"capture_intake_ledger", "refs":["installation_id","import_candidate_id"],
    "rollback":{"strategy":"retain accepted/pending intake identity and never materialize downstream object","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"cancel/expire barrier persists across restart","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"capture intake ledger and permanent identity map"},
    "indexBackup":{"rebuildFrom":["captures"],"backupRequired":["accepted_capture_ledger","capture_identity_map"],"excludedFromBackup":["capture_queue_counts"]}, "blockedReason":""
  },
  {
    "objectType":"import_candidate", "classification":"migrate",
    "stableIdMapping":{"entries":[{"legacyKind":"import_candidate_without_stable_id","targetKind":"import_candidate","mode":"allocate_digest_if_missing","sourceFields":["installation_id","intake_idempotency_key","payload_digest"],"targetField":"import_candidates.import_candidate_id","fallbackAlgorithm":"deterministic_namespace_plus_payload_sha256","guard":"allocate once and persist permanent map; same key different digest blocked:intake_key_digest_conflict"}]},
    "authority":"import_candidate_phase_and_attempt_ledger", "refs":["capture_id","link_inbox_item_id"],
    "rollback":{"strategy":"retain candidate ID, attempt generations and terminal barriers without creating Source","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"cancel/failure terminal state; restart resumes persisted phase","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"candidate decision ledger and permanent identity map"},
    "indexBackup":{"rebuildFrom":["import_candidates"],"backupRequired":["accepted_candidate_ledger","candidate_decisions","import_identity_map"],"excludedFromBackup":["parser_diagnostics"]}, "blockedReason":""
  },
  {
    "objectType":"link_inbox_item", "classification":"migrate",
    "stableIdMapping":{"entries":[
      {"legacyKind":"provider_note_link","targetKind":"link_inbox_item","mode":"derive_composite","sourceFields":["provider_id","provider_note_id"],"targetField":"link_inbox_items.link_inbox_item_id","fallbackAlgorithm":"","guard":"use when provider_note_id present; payload never participates in identity"},
      {"legacyKind":"canonical_url_link","targetKind":"link_inbox_item","mode":"derive_composite","sourceFields":["canonical_url"],"targetField":"link_inbox_items.link_inbox_item_id","fallbackAlgorithm":"","guard":"use only when provider note identity absent; same identity different digest blocked:intake_key_digest_conflict"}
    ]},
    "authority":"link_inbox_ledger", "refs":["capture_id","import_candidate_id"],
    "rollback":{"strategy":"retain canonical/provider identity and accepted inbox phase","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"cancel/remove/expire is persisted; failed/needs_screenshot remains honest","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"link inbox ledger"},
    "indexBackup":{"rebuildFrom":["link_inbox_items"],"backupRequired":["accepted_link_inbox_ledger"],"excludedFromBackup":["link_inbox_counters","preacceptance_index"]}, "blockedReason":""
  },
  {
    "objectType":"chat_message", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"persona_chat_message_with_sync_id","targetKind":"core_chat_message","mode":"preserve","sourceFields":["persona_chat_messages.sync_id"],"targetField":"core_chat_log.sync_id","fallbackAlgorithm":"","guard":"sync_id present and unique"},
      {"legacyKind":"persona_chat_message_without_sync_id","targetKind":"none","mode":"blocked","sourceFields":["persona_chat_messages.local_int_id"],"targetField":"not_applicable","fallbackAlgorithm":"","guard":"local int/digest allocation forbidden; blocked:chat_sync_id_missing"}
    ]},
    "authority":"immutable_core_chat_change", "refs":["sync_id","provenance_id"],
    "rollback":{"strategy":"1A-1/2 does not change writer; retain accepted chat log and stable provenance refs","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"append retract/delete chat operation","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"immutable chat change lineage"},
    "indexBackup":{"rebuildFrom":["core_chat_log"],"backupRequired":["accepted_core_chat_log"],"excludedFromBackup":["recent_chat_projection","chat_search_index"]}, "blockedReason":""
  },
  {
    "objectType":"activity_event_shadow", "classification":"compatibility-only",
    "stableIdMapping":{"entries":[
      {"legacyKind":"device_local_activity_event","targetKind":"future_core_activity_event","mode":"not_applicable","sourceFields":["device_local_event"],"targetField":"not_applicable","fallbackAlgorithm":"","guard":"production migration forbidden:activity_migration_forbidden"},
      {"legacyKind":"activity_shadow","targetKind":"activity_shadow","mode":"not_applicable","sourceFields":["accepted_raw_event"],"targetField":"not_applicable","fallbackAlgorithm":"","guard":"shadow is derived and never accepted authority"}
    ]},
    "authority":"contract_only_no_production_migration", "refs":["event_id","device_id","probe_id"],
    "rollback":{"strategy":"no production migration; discard shadow and leave accepted raw event contract untouched","preserveAcceptedNewWrites":false,"appendOnly":false,"reconstructFromAuthority":true},
    "deleteRecovery":{"strategy":"delete/rebuild shadow; raw event retention/revoke belongs to P3","tombstoneBarrier":false,"physicalDeleteAllowed":true,"recoverySource":"accepted raw event when future Core exists"},
    "indexBackup":{"rebuildFrom":["accepted_raw_activity_events"],"backupRequired":["activity_contract"],"excludedFromBackup":["activity_shadow"]}, "blockedReason":""
  },
  {
    "objectType":"domain_operation_receipt_change", "classification":"preserve",
    "stableIdMapping":{"entries":[
      {"legacyKind":"domain_operation","targetKind":"domain_operation","mode":"preserve","sourceFields":["memory_card_operations.id"],"targetField":"domain_operations.operation_id","fallbackAlgorithm":"","guard":"operation digest, object and revision binding verified"},
      {"legacyKind":"operation_receipt","targetKind":"operation_receipt","mode":"derive_composite","sourceFields":["operation_id","authority_epoch","receipt_kind"],"targetField":"operation_receipts.receipt_id","fallbackAlgorithm":"","guard":"one receipt identity per accepted operation/epoch/kind"},
      {"legacyKind":"domain_change","targetKind":"domain_change","mode":"derive_composite","sourceFields":["operation_id","change_sequence"],"targetField":"domain_changes.change_id","fallbackAlgorithm":"","guard":"sequence stable and no duplicate change"}
    ]},
    "authority":"append_only_operation_receipt_change_ledgers", "refs":["object_id","revision_hash","authority_epoch"],
    "rollback":{"strategy":"append compensating operation; never rewrite accepted operation/receipt/change","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"history has no physical delete; reversal is a new operation","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"append-only operation, receipt and change lineage"},
    "indexBackup":{"rebuildFrom":["domain_operations","operation_receipts","domain_changes"],"backupRequired":["domain_operations","operation_receipts","domain_changes"],"excludedFromBackup":["change_feed_projection"]}, "blockedReason":""
  },
  {
    "objectType":"tombstone_trash", "classification":"migrate",
    "stableIdMapping":{"entries":[{"legacyKind":"legacy_delete_status","targetKind":"object_tombstone","mode":"derive_composite","sourceFields":["object_id","delete_operation_id"],"targetField":"object_tombstones.tombstone_id","fallbackAlgorithm":"","guard":"delete operation and last valid source verified"}]},
    "authority":"delete_barrier_and_last_valid_reference", "refs":["object_id","revision_hash","source_version_id","delete_operation_id"],
    "rollback":{"strategy":"rollback obeys accepted tombstone and never revives from stale backup","preserveAcceptedNewWrites":true,"appendOnly":true,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"30-day recovery; permanent purge follows backup policy","tombstoneBarrier":true,"physicalDeleteAllowed":false,"recoverySource":"object tombstone, managed trash and last valid source"},
    "indexBackup":{"rebuildFrom":["object_tombstones","managed_trash"],"backupRequired":["object_tombstones","managed_trash","delete_operations"],"excludedFromBackup":["trash_view","online_indexes_for_deleted_objects"]}, "blockedReason":""
  },
  {
    "objectType":"derived_index_cache", "classification":"derive",
    "stableIdMapping":{"entries":[{"legacyKind":"derived_projection","targetKind":"derived_projection_key","mode":"derive_composite","sourceFields":["source_hash","source_version"],"targetField":"derived_projections.rebuild_key","fallbackAlgorithm":"","guard":"source is accepted authority; projection cannot win migration"}]},
    "authority":"none_derived_only", "refs":["accepted_revision_hash","domain_operation_id"],
    "rollback":{"strategy":"drop and rebuild from accepted authority","preserveAcceptedNewWrites":false,"appendOnly":false,"reconstructFromAuthority":true},
    "deleteRecovery":{"strategy":"physical cache deletion allowed; stale source tombstone prevents resurrection","tombstoneBarrier":false,"physicalDeleteAllowed":true,"recoverySource":"accepted revision or domain operation"},
    "indexBackup":{"rebuildFrom":["accepted_card_revisions","accepted_domain_operations"],"backupRequired":[],"excludedFromBackup":["fts","backlinks","previews","embeddings","richtext_editor_cache"]}, "blockedReason":""
  },
  {
    "objectType":"backup_manifest", "classification":"preserve",
    "stableIdMapping":{"entries":[{"legacyKind":"recovery_snapshot","targetKind":"backup_manifest","mode":"derive_composite","sourceFields":["authority_epoch","journal_watermark","manifest_digest"],"targetField":"backup_manifests.manifest_id","fallbackAlgorithm":"","guard":"all object/tombstone/journal hashes present and verified"}]},
    "authority":"recovery_media_non_writer", "refs":["authority_epoch","journal_watermark","object_id","tombstone_id"],
    "rollback":{"strategy":"retain immutable recovery media by policy but never use it as writer or accepted online state","preserveAcceptedNewWrites":false,"appendOnly":false,"reconstructFromAuthority":false},
    "deleteRecovery":{"strategy":"retention may physically expire media; restore must apply manifest tombstone/journal barrier","tombstoneBarrier":false,"physicalDeleteAllowed":true,"recoverySource":"verified immutable backup manifest and objects"},
    "indexBackup":{"rebuildFrom":[],"backupRequired":["backup_manifests","sqlite_snapshot","vault_objects","object_tombstones","journal_watermark"],"excludedFromBackup":["fts","backlinks","previews","embeddings","richtext_editor_cache"]}, "blockedReason":""
  }
]
```

### 特殊行解释

- `rich_text_document` 的 cache entry是 `not_applicable`；只有完整 raw bytes可逐 byte恢复的 compatibility capsule
  才能 allocate。capsule不是正文、head或独立提交权威。
- `domain_operation_receipt_change` 的三种身份分别编码；rollback/delete都只能 append compensating/reversal op。
- `derived_index_cache` 的 composite是 rebuild key，不是新权威 ID；cache本体可删且不备份。
- `backup_manifest` 的 composite绑定 epoch/watermark/digest；它是不可变恢复介质，不是 writer、在线 state或索引。
- `preserveAcceptedNewWrites=false` 仅出现在 RichText compatibility、activity shadow、derived cache、backup media
  四类非 writer/derived对象；它不授权丢弃其所引用的 Card/Source/operation等权威写。

## 矩阵完整性 Gate

正式 harness 必须同时验证：原九列表恰好 32 行；Formal32 literal恰好 32 个 unique `objectType`；二者按上述
固定顺序/映射一一对应；每行通过 exact nested schema；literal canonical digest与 pinned expected相等。
fixture出现未知对象类型立即 `unsupported` 并使 Gate 红，不得落入“其他”。任何 field缺失/extra、null、空泛 prose、
非法 mode/fallback组合、复合身份少 entry、共用 bool/default、32项 set不等、blockedReason不一致都使 Gate 红。

本矩阵的 `blocked` 条件只能通过修复 fixture/数据或用户明确 resolution消除；不能由 migration代码改名为 warning。
生产实施和真实数据结果仍是后续 Gate红灯，但 1A-0的对象分类、复合身份与逐行 recovery选择已闭合。
