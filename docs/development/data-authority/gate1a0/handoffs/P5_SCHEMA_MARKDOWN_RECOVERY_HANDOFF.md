# 1A0-P5 Handoff — Schema、Markdown 与跨介质恢复

> 工作包：Gate 1A-0 返修 P5；分支 `codex/gate1a0-authority-recovery`；
> dispatched HEAD `a1b97319`。仅写本包四个文档路径；未 commit / push。

## 交付结论

P5 已把 preflight 的 options 正式收束为一套目标合同：1A-1 新建中性 `cards` catalog，
User-truth 用独立 relation + provenance；1A-2 以 Markdown/YAML envelope + immutable revision
作为唯一正文权威，RichText 只作 editor memory/cache/兼容输入；Anchor、Evidence、TaskArtifact、
Capture/ImportCandidate/Link Inbox 均保持结构化、不可借展示或解析自动升格。

跨介质提交选择 SQLite `cross_medium_commit_journal` 作为 phase/recovery 权威，配合 hash manifest、
managed stage/rollback、逐文件 atomic replace 和唯一 Activation Transaction。文件 publish不是整体事务；
只有 Activation 同时写 head/domain state、operation、receipt/change、tombstone与projection invalidation后才 accepted。

## 交付物

- [PHYSICAL_SCHEMA_AND_MARKDOWN_DATAFLOW_ADR](../PHYSICAL_SCHEMA_AND_MARKDOWN_DATAFLOW_ADR.md)：
  目标物理 catalog、Vault envelope、旧双表映射、RichText逐类映射、Anchor/Evidence/promotion/intake合同。
- [CROSS_MEDIUM_COMMIT_RECOVERY_ADR](../CROSS_MEDIUM_COMMIT_RECOVERY_ADR.md)：
  journal location/schema、phase、幂等、atomic activation、逐 phase crash收敛、external edit、round-trip。
- [FORMAL_MIGRATION_MATRIX](../FORMAL_MIGRATION_MATRIX.md)：
  覆盖 Card、truth、Source/Version、RichText、Board、Anchor、Evidence、Dreaming、Project Memory、Task、
  intake、chat/activity、operation/tombstone/index/backup 的正式逐行处理；无 unknown/other兜底。

## Harness 必须消费的 case schema

正式 corpus 只用 synthetic IDs/bytes/临时目录。每个 scenario 的顶层固定为
`id/family/schemaVersion/input/expected`：

- `input` 只含 raw facts：legacy bytes/tables/RichText、原始 transaction intent、crash point、observed hashes、
  initial ledgers；若涉及 intake，再含 stable identity、dedupe key/digest、cancel/failure/restart观测事实；
- `expected` 是与 `input` 同级的人工 literal oracle，按适用 case包含 `target/roundTrip/commit/result`；
  classification/head hash、convergence、journal phase、receipt/change/projection counts与零下游结果都只能放这里；
- 每案 `wholeInputDigest` 只 hash canonical `input` subtree，不含 `expected`；simulator只得到 input深拷贝，
  在整个生命周期没有 expected读取权限，也不能生成、补全或改写 expected；
- RichText input保留 raw schema/block/mark/asset/IME/history/Anchor，不先经过会吞 unknown 的 decoder；
- commit input保留 raw old/new manifest、每个 file/object observed hash与 initial journal/ledger，不混入预期结论。
- machine catalog必须逐 byte语义消费正式矩阵的 `Formal32 exact literals`：恰好 32 个 `objectType`，每行顶层
  恰好 `objectType/classification/stableIdMapping/authority/refs/rollback/deleteRecovery/indexBackup/blockedReason`
  九字段；nested entries与逐行 bool/arrays同样是 literal，不能用 constructor default生成。

迁移模拟报告必须同时断言 `synthetic=true`、`migrationExecuted=false`、
`migrationSimulated=true`。`migrationExecuted=false` 只说明没改生产；它不能证明模拟迁移发生。
只做合同 lint 的报告必须标 `migrationSimulated=false`，不能满足 P5 Gate。

Oracle 也必须独立但遵守实际 fixture 布局：只读 `scenarios.json` 每案内含 input + literal expected；
manifest `scenarioSha` pin整文件，每案 `wholeInputDigest` 只 pin input subtree。production/simulator converter
只能生成 actual，禁止同一 converter/helper同时生成 expected和actual；comparator只在 actual后读取 expected。
`allInvariantsHeld` 必须由非空 cases 的逐案 `invariantResults` 全量聚合，不能 hard-code或回显 expected。

最低 case 组：

1. 双表 ordinary Card 防误 truth、显式 truth provenance、body/title/ID conflict；
2. paragraph/heading/list/quote/code/empty、nested与footnote/raw block；
3. nested marks、crossing overlap、underline、invalid/unknown mark与 UTF-16 offset fingerprint；
4. image/video/attachment正常与 missing/hash mismatch/temp/base64拒绝；
5. IME未commit defer、CJK/emoji/variation selector exact round-trip；
6. saved history/parent、editor cache不升revision、embedded Anchor提取/ambiguous/orphan；
7. Evidence attachment不升Claim、TaskArtifact显式promotion与partial failure；
8. Capture/ImportCandidate/Link Inbox同/异digest去重、cancel barrier、parser迟到、restart；
9. journal每个 phase、每个file publish、Activation/rebuild/response/cleanup crash，以及第三方hash冲突；
10. old→new→old（保留新写）→new，stable IDs、revision/operation/event/truth counts不重复。

Cross-medium ADR §9.1 的 exact crash/failure allow-list 必须逐项、逐 manifest ordinal展开，不能用粗 `stage`/
`publish` phase代替。当前 2 files / 2 objects / 2 rollback copies / 4 projections / 2 cleanup items
必须展开为 `52` unique crash points；failure allow-list仍为 `25` unique，third-hash虽逐 file有case但只算一个 failure token。
manifest必须以 `fixtureDimensions={files:2,objects:2,rollbackCopies:2,projections:4,cleanupItems:2}` 提供维度，
report原样回显并与之深相等；两者均须输出 expanded crash集合与failure集合，并和 template展开结果做 set深相等；
§9.2 full round-trip输出必须恰好分为 `cardContent`、`userTruthSet`、
`sourceAnchor`、`operationLog`、`revisionHistory`、`derivedIndex` 六域，并逐域输出四阶段 semantic digest、
new-write set、stable/operation ID set、preservation、duplicate count与计算所得 invariant。

## 第二次独立终审返修

1. Cross-medium写入顺序已统一为：credential generation/binding/scope/Core/epoch/fence/lineage-state precheck
   → idempotency lookup → parent/stable refs/业务资源读取 → journal/staging/commit。precheck失败零 lookup/资源读取；
   合法 duplicate同 digest可零资源读取返回原 receipt；异 digest固定 blocked/可保全 needs_resolution且零 accepted target。
2. RichText properly nested marks要求 exact UTF-16 ranges；不能精确使用 extension，禁止扩范围。
   raw HTML/未知可保全 block的 capsule必须包含 base64 raw bytes + length + SHA-256并验证逐 byte恢复；digest-only不算保全。
3. 正式 matrix 增加 exact 32-object machine catalog与每行八字段 Gate；三类 intake同 key异 digest固定
   `classification=blocked`，且 head/manifest/receipt/change/projection/downstream全为零。
4. Harness合同新增独立 pinned oracle、动态 `allInvariantsHeld`、精确 crash/failure catalog与六域 full round-trip schema。

## 第三窄修 — Fixture 形态与展开计数

1. Oracle 合同已对齐当前单一只读 `scenarios.json`：每案 literal expected可以与 input并列；
   `scenarioSha` pin整文件，每案 `wholeInputDigest` 只覆盖 input subtree。没有虚构 expected分文件。
2. `<n>` 明确只是 template。按当前 `2/2/2/4/2` fixture dimensions机器展开后是
   `52/52` unique crash points；failure allow-list保持 `25/25` unique。
3. manifest和report必须分别输出 expanded crash set与failure set，并与 loader由 template/dimensions生成的
   expected set做无序深相等；遗漏、重复、未展开 token、legacy/coarse额外 phase一律失败。

## 第四窄修 — Scenario input/expected 边界

1. Physical、Cross 与本 handoff 的 case合同统一为顶层 `id/family/schemaVersion/input/expected`；input仅 raw facts，
   literal `target/roundTrip/commit/result` 只在同级 expected，`wholeInputDigest` 仅 hash input subtree。
2. simulator只消费 input；expected既不混入 transaction/legacy输入，也不由 converter生成、补全或改写。
3. manifest维度字段正式固定为 `files/objects/rollbackCopies/projections/cleanupItems = 2/2/2/4/2`，
   report必须原样回显该对象；展开计数仍为 52 crash / 25 failure。

## 第五窄修 — Formal32 nested machine contract

1. 原九列矩阵已增加 32-row exact JSON literal并保持逐行一对一。每行 stable identity拆成一个或多个 entry，
   exact mode/source/target/fallback/guard不再由通用 `legacy.id -> target.id`字符串猜测。
2. 已冻结复合身份：truth relation、forward relation、correction、asset relation、history、Anchor、timed selector、
   Evidence proposal、Dreaming、entity/link、task room/decision、operation/receipt/change都分别编码；chat缺 sync_id直接
   blocked，Link Inbox禁止 payload fallback，activity不迁移，cache/backup不成为 writer。
3. rollback/delete/index-backup均为逐行 literal。`preserveAcceptedNewWrites=false`恰好用于
   `rich_text_document/activity_event_shadow/derived_index_cache/backup_manifest`；reconstruct仅用于 RichText cache、
   activity shadow和derived cache；非 blocked catalog row的 `blockedReason`固定为空字符串。

## 边界与仍留红

- 本包没有生产 schema/migration/Dart、Vault writer、设备、配置、真实数据、Goal/P0–P4、状态页或 DEVLOG修改。
- 仍红只属于后续实施/真实 Gate：1A-1 生产解耦与旧调用者适配；1A-2 文件 watcher、真实迁移/rollback与crash；
  1A-3 Core intent/epoch/fencing；Gate 1C真实硬盘/S3/新机恢复；Evidence production属于后续 Evidence Gate。
- P5 合同内没有保留“选新表还是演进旧表”“Markdown还是RichText”“journal放哪里/如何恢复”等未决项。

## 验证

- 四个拥有文件均为新文档，owned-path scope检查没有本包对其他路径的修改。
- 四文件相对链接 target检查通过；untracked-file `git diff --no-index --check` 零 whitespace error。
- 正式矩阵有 32 个对象行；合同 token检查覆盖 Card/truth/Source/Version/RichText/Board/Anchor/
  Evidence/Dreaming/Task/intake/operation/tombstone/index/backup、journal phases与双迁移标志。
- 第二次终审 machine audit通过：写入顺序位置严格为 precheck < idempotency < business read < journal；
  machine catalog `32/32` unique object types；template按当前 fixture维度展开为 `52` unique crash points、
  `25` failure points、`6/6` round-trip domains，均无重复；四文件仍是本包仅有 owned changes。
- 第四窄修全文审计：旧 scenario 字段与旧 dimension字段均为零残留；两个 JSON示例均为
  `id/family/schemaVersion/input/expected` 同级形状，manifest维度为实际五字段且 report必须深相等回显；
  32 templates仍精确展开为 52 unique crash points，failure仍为 25 unique。
- 第五窄修 machine audit：Formal32 JSON可解析，`32/32` objectType unique；每行九个顶层 exact key、每 entry七个
  exact key，非法 fallback组合、null/default、非空 baseline blockedReason均为零；四个非 writer/derived row的
  rollback bool与三个 reconstruct row集合精确匹配本合同。
- 本包是文档合同，没有运行 Dart/Flutter测试。主窗仍需把 P5 case schema接入 P4 合成 harness；
  现有 `migrationExecuted=false` 的 47-case authority报告不含本包迁移模拟，不能被追溯解释为 P5 已通过。
