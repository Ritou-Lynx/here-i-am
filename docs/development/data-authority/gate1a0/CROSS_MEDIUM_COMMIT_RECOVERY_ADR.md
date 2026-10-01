# Gate 1A-0 ADR — 跨介质 commit、journal 与崩溃恢复

> 状态：**Gate 1A-0 已冻结并经 Lynx 真人 Gate 通过的目标合同；未实现**。
>
> 本文定义未来 1A-2 的唯一 commit/recovery 模型；当前 runtime 未实现。
> 本 Goal 不创建 journal 表、不写生产文件、不执行迁移或真实恢复。

## 1. 决策与原子边界

跨 Markdown、Source/object、operation log、SQLite catalog、FTS 和 Receipt 的写入由
`cross_medium_commit_journal` 统一协调。**SQLite 中的 journal row 是 phase/恢复决策权威**；
staging manifest 是按 hash 校验的介质证据，不可自行宣称 accepted。一个 Card 文件的原子 replace
只证明该文件没有半写，不能证明整批 Source + DB + operation + Receipt 已事务提交。

逻辑 acceptance 的唯一原子点是 SQLite **Activation Transaction**。该事务同时：

1. 激活新 Card/Source/relation/domain state 和 current revision/version pointer；
2. append operation、idempotency ledger、receipt/change；
3. 写 tombstone/delete barrier（如有）；
4. 写 projection invalidation marker；
5. 将 journal phase 从 `files_published` 改为 `db_activated`。

文件/object 必须在 activation 前全部按 manifest 发布并验证；FTS/preview/RichText cache 在 activation 后重建。
拒绝/rollback 不生成 acceptance receipt/change。accepted 后的 Undo 是一个新 inverse DomainCommand，
不能删除原 operation 或把 journal phase 倒退。

## 2. Journal 与 staging schema

`cross_medium_commit_journal` 位于 Core authority SQLite，与 catalog/operation/receipt 同一 WAL/恢复域。
最低字段如下；实现可以加列，不能删除这些语义：

| 字段 | 语义 |
|---|---|
| `intent_id TEXT PK` | stable idempotency key；重试必须复用。 |
| `intent_digest TEXT` | canonical command digest；同 key 不同 digest 永久冲突。 |
| `authority_id`, `core_instance_id`, `authority_epoch` | 绑定 active writer；恢复前先按 P2 校验。 |
| `phase TEXT` | 仅按本文有向状态机前进。 |
| `old_state_manifest_hash`, `new_state_manifest_hash` | 旧/new head、object、relation、tombstone 集合的 canonical manifest。 |
| `staging_relpath`, `rollback_relpath` | 只能是 Vault 管理根内相对路径；路径 escape/link 阻断。 |
| `expected_file_count`, `expected_object_count` | 防漏发布；实际集合必须精确相等。 |
| `operation_id`, `receipt_id?`, `change_id?` | receipt/change 只在 activation 后非空。 |
| `failure_code?`, `retry_count`, timestamps | 可审计恢复；failure 不是 accepted。 |

每个 staging manifest 包含 target relative path、media role、byte length、SHA-256、old hash/absence、
new hash、publish mode 与 rollback source。manifest 本身 canonical JSON + hash，并写到
`vault/.hereiam/staging/<intent_id>/manifest.json`；stage 中每个文件 fsync，随后 staging directory fsync。
SQLite journal 是 phase authority；没有 journal 的 stage 是 orphan，隔离后可 GC，绝不能自动 publish。

## 3. Phase 状态机

| Phase | 必须已经 durable | 允许的下一步 | 对普通 reader 的可见性 |
|---|---|---|---|
| `intent_durable` | journal key/digest、old/new manifest hash、旧 heads | build stage 或 fail/rollback | 只读完整旧 accepted state。 |
| `staged` | 所有 staged bytes/object + manifest hash/fsync 完成 | `publish_started` | 仍为旧 state；stage 不可索引。 |
| `publish_started` | rollback copies/old hashes已验证；journal 标记开始 | 幂等 atomic publish每个目标 | app reader 依据 catalog/journal 仍读旧 head；外部观察到的新 bytes 不等于 accepted。 |
| `files_published` | 每个目标在最终位置与 new hash相等，集合完整 | Activation Transaction | 尚无 receipt；Core writer必须立即 activation或启动恢复。 |
| `db_activated` | catalog/domain state、operation、idempotency、receipt/change、invalidation 与 phase 同一 DB commit | rebuild/publish notifications | 新 accepted state；response丢失可用原 key取同 receipt。 |
| `projections_rebuilding` | rebuild job/version、水位已登记 | verify/retry | 正文/领域新 state 可读；FTS/preview明确 stale，不可回写。 |
| `complete` | 所有必需 projection达到 source hash，通知已幂等发布 | 清理 stage/rollback（按保留策略） | 完整新 state。 |
| `rolled_back` | 旧 files/head 已逐项 hash 验证，refusal/problem result 可审计 | 清理 | 完整旧 state；无 acceptance receipt/change。 |
| `needs_resolution` | 无法证明 old 或 new manifest完整，冲突证据已保全 | 人工/受控 repair 新 intent | 隔离目标，不允许猜 winner。 |

phase 只能单调前进。`db_activated` 以后不能转 `rolled_back`；要回到旧内容必须产生新 revision/operation。

## 4. 写入算法

1. **Identity/authority precheck。** 先做 bounded protocol/envelope 校验，再依次校验 credential generation、
   caller binding、scope、active `core_instance_id`、authority epoch、worker fence（如适用）和 authority/
   credential lineage-state。这里的 lineage-state 只读 authority registration、credential/probe/worker状态，
   **不读取 parent revision、stable refs、目标对象或其他业务资源**。任一 stale/invalid precheck 立即拒绝：
   `idempotencyLookupCount=0`、`businessResourceReadCount=0`，且零 target/head/manifest/receipt/change/projection/downstream。
2. **Idempotency lookup。** 只有第 1 步全部通过后才按 immutable key 查账本。同 key+同 digest 的合法
   duplicate 直接返回原 acceptance receipt，`businessResourceReadCount=0`，不重读 parent/ref、不重建 stage。
   同 key+不同 digest 固定 `classification=blocked`（需要人工保全时可进入 `needs_resolution`），并断言
   `acceptedTarget=null`、`head=null`、`manifest=null`、`receiptCount=0`、`changeCount=0`、
   `projectionCount=0`、`downstreamCount=0`；它不能覆盖原 ledger或产生第二个 accepted target。
3. **Parent/ref/business validation。** 只有 key 未命中时才读取对象生命周期、delete barrier、parent revision、
   所有 stable refs及其他业务资源，计算 canonical envelope/object/new-state manifest。stale parent、dangling ref
   或业务冲突只能 blocked/`needs_resolution`，且不创建 accepted target/head/manifest publication/receipt/change。
4. **Intent durable。** SQLite Tx-A 插入 journal `intent_durable`。此事务不改对象、head、operation 或 receipt。
5. **Stage。** 写入管理根内专用目录；验证 bytes/hash/count，fsync files 与 directory；
   SQLite Tx-B 把 phase 改 `staged`。stage 失败保留旧 state并可 rolled_back。
6. **Prepare rollback。** 按 old manifest 保存受影响当前文件的 hash-verified rollback bytes；
   旧 bytes也可来自 immutable revision/object。无法证明 rollback source时，在 publish 前 fail closed。
7. **Atomic file publish。** 先 journal `publish_started`；每个文件在同卷临时名写完/fsync后 atomic replace，
   immutable object以 content hash路径 create-if-absent。每步重试先比 hash：已是 new hash即 duplicate；
   是 old hash才 replace；其他 hash是 external conflict，转 `needs_resolution`。全部完成后写 `files_published`。
8. **Activate。** 重新执行第 1 步 authority precheck，再校验本 intent journal manifest 与每个最终 hash；
   执行唯一 Activation Transaction。这里查 journal 自身不等于重新查业务幂等账本；发现 epoch/fence stale时
   不读其他 intent或业务资源，按恢复协议保全 stage并停止为 `needs_resolution`。
   任何验证失败都不得产生 operation/receipt/change。
9. **Rebuild。** FTS、backlink、preview、RichText cache只消费新 revision hash。invalidation 与 activation 同事务，
   rebuild 可崩溃重试；cursor/watermark 只在对应 projection 与 source hash同事务持久后推进。
10. **Respond/notify。** 只发送已持久 receipt/change；通知用 `change_id` 幂等。响应丢失后原 key重试返回原 receipt。

本 ADR 对 P2 `lineage and state admissibility` 的消费边界固定为：authority registration、
credential/installation/probe/worker lineage、origin sequence、intent TTL 与 retention generation 等无需读取
目标业务对象即可判断的状态。Card/Source 等 target lifecycle、delete barrier、parent和stable refs属于第 3 步
business validation。合法 duplicate返回的是此前已经接受的同 digest receipt，不是对当前对象的新读写或重新接受；
因此它在第 2 步返回且不触发第 3 步。该拆分不得被解释为在 precheck失败后查询幂等或业务资源。

## 5. 启动恢复与确定性收敛

启动先恢复 journal，再开放 writer、watcher、FTS rebuild 或 client submission。每一行按 phase确定处理，
不能按文件修改时间、SQLite row count或“较新者”猜 winner。

| 崩溃/观察点 | 启动恢复动作 | 唯一允许收敛 |
|---|---|---|
| stage 写入前/中，journal=`intent_durable` | 删除/隔离不完整 stage；确认 catalog/files仍是 old；写 `rolled_back` | 完整旧；零 operation/receipt/change。 |
| stage 完成但 Tx-B 前 | manifest与journal phase不匹配，stage作为 orphan隔离；rollback | 完整旧。 |
| `staged` 后、publish 前 | manifest、stage 与 old hashes 全部有效时**必须 roll forward**；若校验在任何 final replace 前失败，则验证 old 后写 `rolled_back`；一旦已有 final replace，转下一行 | 完整新；或在零 final replace 时完整旧。不能由操作者临时选择方向。 |
| `publish_started`，0..N 文件已 replace | 对每项 old/new hash分类；stage完整则补齐所有 new。stage损坏时，只有 rollback manifest逐项有效才恢复全部 old；出现第三方 hash或新旧两套都不可完整证明则 `needs_resolution` | 纯 crash 只收敛完整新或完整旧；额外损坏/并发冲突明确隔离，不接受混合集合。 |
| 所有文件 new，但 `files_published` phase 未写 | manifest全量 hash验证后补记 `files_published` | 继续到完整新。 |
| `files_published` 后、Activation 前 | **必须 roll forward** Activation Tx；不能自动恢复旧文件，因为外部已可能观察到完整 new set | 完整新。 |
| Activation Tx 中 | SQLite原子性决定 old或new：若未 commit，仍 `files_published`并 roll forward；若 commit，phase=`db_activated` | 完整新；永无 ghost receipt。 |
| `db_activated` 后、rebuild/response 前 | 以 invalidation marker重建；同 key返回原 receipt；通知按 change id去重 | 新正文/状态 + 最终新 projection。 |
| cleanup 中 | old/new权威已确定；只幂等清理 stage/rollback，immutable revision按保留策略 | 不改变 accepted state。 |

如果 `publish_started` 遇到 final path既非 old hash也非 new hash，说明并发外部编辑；恢复必须保全第三份 bytes、
停止该对象为 `needs_resolution`。不得用 rollback/new 覆盖它，也不得把 mtime较新者接受。

## 6. External edit、delete 与多对象 batch

- watcher 读取稳定 Markdown 时先做 bounded read、YAML/schema/ID/hash检查。合法外部改动成为新 intent，
  parent 是最后 accepted head；原文件 bytes先保全到 stage。系统字段被改、重复 `card_id`、invalid YAML、
  并发 parent变化或文件缺失分别进入隔离/冲突/tombstone流程，不能覆盖最后有效 revision。
- 外部移动以 `card_id` 识别并 journal 更新 relpath；同 ID 出现两份且 hash不同为 duplicate-ID conflict。
  同 hash仅代表 bytes相同，不合并 Card identity。
- 外部删除先标 `externally_missing` 并保留 last valid revision；用户确认删除才产生 tombstone，选择恢复则原子发布最后有效版本。
- batch 的 manifest列出全部对象。Activation Tx全收或全拒；文件 publish可以逐个原子，但在 activation前
  app reader不将任何一个视作新 accepted。跨卷 rename不允许；必须先复制到目标卷stage并 fsync，再逐文件 atomic replace。

## 7. Projection、Receipt、backup 与删除

- projection invalidation 是 Activation Tx 成员；实际 FTS/backlink/preview rebuild异步。查询遇 stale source hash必须显示
  syncing/stale或回退直接读 accepted Markdown，不能回退旧索引并称最新。
- Receipt/change 与 revision/domain mutation同事务；单独存在 receipt或单独推进 change cursor均为 corruption，启动停为 `needs_resolution`。
- backup manifest只能在 journal水位处于 `db_activated` 以上且没有未解析 `publish_started` 行时封口；
  必备份 SQLite authority state、accepted Markdown revisions、objects、operations、receipts、tombstones与journal watermark。
- delete先在 Activation Tx写 tombstone/访问屏障/receipt，再异步移入回收站、清理index与未来backup；
  immutable backup按公开 retention到期。恢复先应用 tombstone ledger，不能从旧备份复活删除对象。

## 8. 可逆 migration 特例

旧→新、带新写的回滚、再新均使用同一 journal，不允许用目录 rename 或数据库快照覆盖代替迁移事务。

| 方向 | 必须 staging 的内容 | Activation |
|---|---|---|
| old → new | target catalog rows、Markdown envelopes/revisions、Source objects/mappings、operation/tombstone map、rebuild plan | 写 migration receipt、切 target read authority；legacy 保留只读。 |
| new → old | **包含切换后所有新写**的 legacy rows + RichText/plain compatibility files、完整 stable-ID/revision map | 校验每个 target head都可回投后切 legacy read authority；target 保留只读，不删新 revisions。 |
| old → new again | 读取永久 migration map，对比 legacy digest与既有 target hash，只stage真正新增差异 | duplicate不重发 receipt/event/truth；恢复相同 stable IDs并切回 target。 |

rollback window 内若某个新 Markdown feature不能回投，原保存必须在 acceptance 前 blocked；所以回滚不会通过
“恢复旧快照”丢新写。Gate 退出前必须证明 Card body、User-truth集合、Source/Anchor、operation、history、index
逐项 digest相等。

## 9. Harness 必需 crash schema

正式合成 harness 的 transaction fixture 每例至少包含：

```json
{
  "id": "publish_second_file_then_recover",
  "family": "cross_medium_commit_recovery",
  "schemaVersion": 1,
  "input": {
    "transactionIntent": {
      "intentId": "intent_syn_001",
      "intentDigest": "sha256...",
      "oldManifest": [
        {"path": "synthetic/a.md", "hash": "sha256-old-a..."},
        {"path": "synthetic/b.md", "hash": "sha256-old-b..."}
      ],
      "newManifest": [
        {"path": "synthetic/a.md", "hash": "sha256-new-a..."},
        {"path": "synthetic/b.md", "hash": "sha256-new-b..."}
      ]
    },
    "crash": {"point": "after_file_publish:1"},
    "observedHashes": {
      "published": ["sha256-new-a...", "sha256-new-b..."],
      "externalConflict": null
    },
    "initialLedgers": {"journal": [], "receipts": [], "changes": [], "projections": []}
  },
  "expected": {
    "target": {"acceptedHeadHash": "sha256-new-head..."},
    "roundTrip": {"oldDigest": "sha256-old-set...", "newDigest": "sha256-new-set..."},
    "commit": {
      "journalPhase": "complete",
      "convergence": "new",
      "receiptCount": 1,
      "changeCount": 1,
      "projectionSourceHash": "sha256-new-head..."
    },
    "result": {"status": "accepted", "blockedReason": null}
  }
}
```

这里同样固定为顶层 `id/family/schemaVersion/input/expected`。`input` 只含原始 intent/crash/观测 hash/
初始 ledger 等事实；literal target/round-trip/commit/result 只在同级 `expected`。`wholeInputDigest` 只对
canonical `input` subtree计算，simulator 只能收到该 subtree 的深拷贝。

### 9.1 Exact crash/failure catalog

Harness manifest 必须包含下面**完整精确 allow-list**；少一项、额外 unknown项或只用 `stage` / `publish`
等粗 phase替代细点，均为 Gate failure。`<n>` 必须展开为 manifest 中每一个 file/object 的 0-based ordinal，
不能只抽第一个或最后一个：

```text
crashPoints = [
  before_identity_precheck,
  after_identity_precheck_before_idempotency,
  after_idempotency_before_business_read,
  before_journal_tx_a,
  after_journal_tx_a_commit,
  before_stage_file_write:<n>,
  after_stage_file_write:<n>_before_file_fsync,
  after_stage_file_fsync:<n>_before_directory_fsync,
  after_stage_directory_fsync_before_tx_b,
  after_tx_b_commit,
  before_rollback_copy:<n>,
  after_rollback_copy:<n>_before_rollback_fsync,
  after_rollback_fsync:<n>,
  before_publish_started_phase,
  after_publish_started_phase,
  before_file_publish:<n>,
  after_file_publish:<n>,
  before_object_publish:<n>,
  after_object_publish:<n>,
  before_files_published_phase,
  after_files_published_phase,
  before_activation_tx,
  during_activation_tx_before_commit,
  after_activation_tx_commit,
  after_invalidation_before_rebuild,
  before_projection_rebuild:<n>,
  during_projection_rebuild:<n>,
  after_projection_rebuild:<n>_before_cursor_commit,
  after_cursor_commit_before_notification,
  after_notification_before_response,
  after_response_before_cleanup,
  during_cleanup:<n>
]

failurePoints = [
  stale_credential_generation,
  identity_binding_mismatch,
  scope_denied,
  stale_core_instance,
  stale_authority_epoch,
  stale_worker_fence,
  lineage_state_rejected,
  duplicate_key_same_digest,
  duplicate_key_different_digest,
  stale_parent_revision,
  dangling_stable_ref,
  disk_full_during_stage,
  disk_full_during_publish,
  permission_denied_during_stage,
  permission_denied_during_publish,
  invalid_yaml,
  source_object_hash_mismatch,
  external_move,
  external_delete,
  external_third_hash_conflict,
  activation_constraint_failure,
  projection_rebuild_failure,
  notification_failure,
  rollback_manifest_corrupt,
  staging_manifest_corrupt
]
```

当前 synthetic fixture 的 manifest 必须含以下实际字段和值，report 必须原样回显同一对象：

```json
{
  "fixtureDimensions": {
    "files": 2,
    "objects": 2,
    "rollbackCopies": 2,
    "projections": 4,
    "cleanupItems": 2
  }
}
```

按 `<n>` 所属 `fixtureDimensions` 集合逐 ordinal 展开后，
`expandedCrashPoints` 必须是 **52 unique**；上面的 `<n>` template 行不能自己算一个 runtime point。
`failurePoints` 仍是 **25 unique**。`external_third_hash_conflict` 必须分别与
`after_file_publish:0`、`after_file_publish:1` 组成独立 case，但它在 failure allow-list 中仍只出现一次。

manifest 与 report 必须分别输出：

```text
fixtureDimensions
expandedCrashPoints
failurePoints
```

loader 依据本文 template + manifest `fixtureDimensions` 独立生成 expected expanded set；report 回显的
`fixtureDimensions` 必须与 manifest 对象深相等，且 manifest 的
`expandedCrashPoints` / `failurePoints`、report 的实际覆盖集合都必须分别与 expected set做无序集合深相等。
缺项、重复、extra legacy token、未展开 `<n>`、或额外粗 `stage` / `publish` phase 都使 Gate failure；
不得只比较 count。

precheck failure cases必须同时断言零 idempotency lookup与零业务读取；合法 duplicate同 digest必须零业务读取并返回
原 receipt；异 digest必须使用前述 blocked零目标断言。failure/crash组合至少覆盖每个 failure单例，并让
`external_third_hash_conflict` 分别落在每个 `after_file_publish:<n>` 后。

### 9.2 Full round-trip 六域 exact output

`fullRoundTrip.domains` 必须**恰好**含以下六个 key，不能合并成一个 `content` digest：

```text
[
  cardContent,
  userTruthSet,
  sourceAnchor,
  operationLog,
  revisionHistory,
  derivedIndex
]
```

每域必须输出相同 schema：

```json
{
  "oldBaselineSemanticDigest": "...",
  "newAfterFirstMigrationSemanticDigest": "...",
  "postCutoverNewWriteSetDigest": "...",
  "oldAfterRollbackSemanticDigest": "...",
  "newAfterRemigrationSemanticDigest": "...",
  "stableIdSetDigest": "...",
  "operationIdSetDigest": "...",
  "newWritesPreserved": true,
  "duplicateAcceptedCount": 0,
  "domainInvariantHeld": true
}
```

`domainInvariantHeld` 必须由 baseline→first migration 等价、rollback/remigration都包含 new-write set、stable ID不变、
operation不重复和该域专属引用完整性逐项计算。顶层
`allSixRoundTripDomainsHeld = domains.keys == exactSixKeys && domains.values.every(domainInvariantHeld)`，不得 hard-code。
其中 `derivedIndex` 的 semantic digest 必须由对应 accepted revision/domain state重建后计算，不能复用旧索引 bytes。

### 9.3 Oracle 与聚合

fixture 使用一个只读 `scenarios.json`：manifest `scenarioSha` pin整个文件的 canonical raw bytes，
每案 `wholeInputDigest` 只 pin同案 canonical input subtree，不含并列的 literal expected section。
production/simulator converter 只能生成 actual，不能生成或改写 expected；同一 converter/helper/mapping实例不得同时参与两边。
simulator只接收 input深拷贝，其整个生命周期的能力面不包含 expected。
comparator只在 actual完成后读取 literal expected。
每案输出逐项 `invariantResults`，report 的
`allInvariantsHeld` 必须由非空 case集合中所有 invariant literal comparison聚合，禁止 hard-code或回显 expected。

每例断言：

1. `synthetic=true`, `migrationExecuted=false`, `migrationSimulated=true`；
2. 只收敛完整 old 或完整 new；第三方冲突只能 `needs_resolution`；
3. accepted 恰有一个 operation/receipt/change，rollback 为零；
4. 无 partial batch、ghost receipt、重复 event/truth、cursor超前、staged object被索引或旧 file 覆盖新 head；
5. 第二次运行字节级确定，fixture 与仓库零修改。

## 10. Gate 分界

本文已经选择 journal authority/location、phase、幂等、startup recovery、rollback 和 round-trip 规则；
它们不再是 1A-0 未决项。生产 Drift schema/file writer、OS 级 fsync/atomic replace验证、真实数据 clone迁移、
真实 crash injection与真人 rollback属于 1A-1/1A-2；跨 Core writer/epoch实现属于 1A-3；
真实硬盘/S3/新机恢复与不可变备份到期证据属于 Gate 1C。
