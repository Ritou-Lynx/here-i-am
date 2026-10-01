# Gate 1A-0 ADR — 中性 Card 物理 schema 与 Markdown 数据流

> 状态：**Gate 1A-0 已冻结并经 Lynx 真人 Gate 通过的目标合同；未实现**。
>
> 本文只冻结 1A-1 / 1A-2 必须消费的目标合同与合成迁移判定；不创建生产表、
> 不写 migration、不切换当前 `MemoryCards` / `RichTextDocument` 运行权威，也不读取真实数据。
>
> 上位约束：[Product Roadmap](../../../companion-first/PRODUCT_ROADMAP.md)、
> [Authority Root ADR](AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md)、
> [preflight inventory](../../data-authority-preflight/A1_CURRENT_AUTHORITY_INVENTORY.md)、
> [whiteboard charter](../../WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md)。

## 1. 正式选择

1. **1A-1 新建中性 Card catalog，不演进 `memory_cards` 继续承载所有 Card。**
   `memory_cards.id` 与现有白板 `card_id` 原值保留为目标 `card_id`；User-truth 是独立、
   有自身稳定 ID、provenance 和生命周期的关系。普通 Card 永不因出现在白板、检索、
   TaskRoom 或 Memory Review 投影中而成为 User-truth。
2. **1A-2 以 UTF-8 Markdown/YAML envelope 及其不可变 revision 链作为 Card 当前正文唯一目标权威。**
   SQLite 只保存 head 指针、hash、领域状态、操作、关系、journal 与可重建目录；
   `RichTextDocument` 只可作 editor memory、由当前 revision 重建的可丢缓存或受控兼容输入，
   不能独立提交、分配 revision 或在重启后与 Markdown 竞争。
3. **SourceContent / SourceVersion、Anchor、EvidenceClaim、TaskArtifact 与 intake 对象保持结构化权威。**
   Markdown 只引用稳定 ID；大文件、selector、Claim、task 状态和 capture 状态不塞入正文。
4. **所有保存只经同一 DomainCommand。** 一个 accepted 保存产生一个新 envelope revision、
   一个 parent hash、一个 operation、一个 receipt/change；外部文件编辑也先成为候选 intent，
   通过同一协议后才成为 head。

本文中的表名是 Gate 1A-0 已选择的**目标物理 catalog 名称**。1A-1 可以按 Drift 命名约定
生成大小写类名，但不得改变字段语义、把正文复制回 SQLite，或把 truth 合并回 Card。

## 2. 目标物理 catalog

所有 ID 为不透明稳定字符串；时间为 UTC epoch milliseconds；`*_hash` 为小写 SHA-256 hex。
开放 token（如 `content_role`、`owner_space`）由版本化 registry 校验，不使用数据库 closed enum，
以允许增加类型而不迁移所有正文。未知 token fail closed，不回退成 `note` / `user_truth`。

| 目标表 / 介质 | 最低字段与键 | 权威角色 |
|---|---|---|
| `cards` | `card_id TEXT PK`, `content_role TEXT`, `owner_space TEXT`, `created_by TEXT`, `lifecycle_state TEXT`, `current_revision_id TEXT`, `current_revision_hash TEXT`, `current_envelope_relpath TEXT`, `created_at`, `updated_at`, `deleted_at?`, `schema_version` | 中性 Card 身份、生命周期和当前 head 指针；**不存正文**。`lifecycle_state` 至少区分 active / trashed / externally_missing / purged_tombstone。 |
| `card_revisions` | `revision_id TEXT PK`, `card_id TEXT`, `parent_revision_hash TEXT?`, `envelope_hash TEXT`, `envelope_relpath TEXT`, `accepted_operation_id TEXT`, `author_kind TEXT`, `created_at`; `UNIQUE(card_id,envelope_hash)` | 不可变 revision 目录和 lineage。正文权威是对应 Markdown bytes；本表不能用 excerpt/body 替代文件。 |
| `user_truth_relations` | `truth_relation_id TEXT PK`, `card_id TEXT`, `truth_domain TEXT`, `provenance_id TEXT`, `status TEXT`, `accepted_operation_id TEXT`, `created_at`, `ended_at?` | User-truth 的独立领域权威。创建、纠正、撤销均需显式 accepted operation；删 Card 不暗自删 provenance。 |
| `provenance_records` | `provenance_id TEXT PK`, `source_kind TEXT`, `source_ref TEXT?`, `source_version_id TEXT?`, `origin_sync_id TEXT?`, `payload_digest TEXT`, `recorded_at`, `accepted_operation_id TEXT` | 不可变来源链。聊天本机整数只可保留在 legacy payload，跨端引用必须稳定。 |
| `source_contents` | `source_id TEXT PK`, owner/origin/provider/canonical identity, `current_version_id?`, lifecycle timestamps | 原件逻辑身份；不把原件正文或二进制放进 Card Markdown。 |
| `source_versions` | `source_version_id TEXT PK`, `source_id TEXT`, `content_hash TEXT`, `object_ref TEXT`, MIME/parser metadata, `created_at`; `UNIQUE(source_id,content_hash)` | 不可变可锚定版本；对象 bytes 由 hash 校验。 |
| `anchors` | `anchor_id TEXT PK`, `source_id TEXT`, `source_version_id TEXT`, `selector_kind TEXT`, `selector_json TEXT`, `quote/prefix/suffix?`, `fingerprint TEXT`, `resolution_status TEXT`, timestamps | selector + fingerprint 的结构化权威。必须绑定确切 SourceVersion；模糊重锚只进入待确认，不改旧 Anchor。 |
| `evidence_claims` | `evidence_id TEXT PK`, immutable claim payload/digest, `source_version_id TEXT`, `anchor_id TEXT`, `status TEXT`, `supersedes_evidence_id?`, `accepted_operation_id`, timestamps | 独立不可变 Claim ledger。修订通过 supersede/retract 新 operation，Card 只是投影。此表由后续 Evidence Gate 实施，但 schema 边界在 1A-0 已定。 |
| `task_artifacts` | 保留稳定 `task_artifact_id`、`task_room_id`、content/object ref、状态与 operation lineage | Task lane 权威；不能直接充当 Card / Source / User-truth。 |
| `artifact_promotions` | `promotion_id TEXT PK`, `task_artifact_id`, explicit authorization ref, requested targets, created `source_id?` / `source_version_id?` / `card_id?` / `truth_relation_id?`, status, receipt | 唯一 promotion 审计桥。每个目标是独立 accepted operation；User-truth 必须再有明确授权。 |
| `captures` | `capture_id TEXT PK`, origin installation, canonical digest, status, cancellation/failure, accepted operation | 只代表 intake。accepted capture 也不建 Card/Source/索引。 |
| `import_candidates` | `import_candidate_id TEXT PK`, `capture_id?`, normalized identity/digest, parser plan/status/attempt generation, cancellation/failure | 待解析/待导入状态；重启按持久 phase 恢复，不拿 parser 成功冒充 materialization。 |
| `link_inbox_items` | `link_inbox_item_id TEXT PK`, normalized URL, provider/note id, dedupe key, status, candidate ref, cancellation/failure | 稳定 inbox 身份；`UNIQUE(dedupe_key)` 的同 digest重试返回原 identity，不同 digest 冲突。 |
| `domain_operations` | `operation_id TEXT PK`, domain/object/action, intent key/digest, old/new revision refs, actor/scope, authority epoch, created_at | append-only 领域事实；legacy operation 可作为 `legacy_unbound_revision` 保全，但不能伪造 revision。 |
| `domain_receipts` / `domain_changes` | receipt/change ID、operation/object/revision、authority/core/epoch/sequence、digest | 与 accepted activation 同一 SQLite transaction 产生；无 receipt 的 staged 文件不是 accepted。 |
| `object_tombstones` | `tombstone_id TEXT PK`, object type/id, last valid revision/version, delete operation, recovery deadline/policy, purge state | 在线删除/外部缺失/永久删除的结构化屏障；恢复与备份必须先服从 tombstone。 |
| `cross_medium_commit_journal` | 见 [commit/recovery ADR](CROSS_MEDIUM_COMMIT_RECOVERY_ADR.md) | 跨 SQLite / Markdown / object / operation / Receipt 的唯一协调权威。 |
| `card_link_index`, `card_fts`, previews, RichText cache | source revision hash + rebuild version | 全部可重建；可删、可重建、不得写回正文或分配 receipt。普通 Card 正向链接以 Markdown 为权威，反链只派生。 |
| Vault backup manifest / immutable backup | authority epoch、journal watermark、SQLite digest、file/object hashes、retention policy | 恢复介质，不是 writer。manifest 必须含 operation/tombstone/journal 水位；FTS/RichText cache 可不备份。 |

Board、BoardItem、BoardGroup/Member、BoardEdge、Dreaming 和 Project Memory 保持独立结构化域；
它们引用 `card_id`，不复制 Card 正文。现有白板表在 1A-1 只把 `card_id` 软引用目标从
`memory_cards` 改成 `cards`，稳定 board/item/group/edge ID 不变。

## 3. Vault envelope 与字段所有权

目标当前文件使用稳定可读路径：

```text
vault/cards/<bucket>/<readable-slug>--<card_id>.md
vault/.hereiam/revisions/cards/<card_id>/<revision_hash>.md
vault/.hereiam/objects/sha256/<prefix>/<content_hash>
vault/.hereiam/staging/<intent_id>/...
vault/.hereiam/rollback/<intent_id>/...
```

第一行 YAML delimiter 到第二个 delimiter，加 Markdown body，组成 canonical envelope。
UTF-8 必须有效；换行 canonicalize 为 LF；Unicode code points、variation selector 与组合序列不做
NFC/NFKC 改写。`revision_hash` 的 preimage 是 canonical envelope **移除该字段本身**后的 bytes，
从而避免自引用。hash 与 YAML 不匹配时文件只是损坏/外部候选，不能成为 head。

```yaml
---
schema_version: 1
card_id: card_01J...
revision_id: rev_01J...
parent_revision_hash: 9f...
revision_hash: a4...
title: 河边散步
content_role: note
owner_space: user
created_by: user
lifecycle_state: active
labels: [散步]
source_refs: [src_01J...]
anchor_refs: []
evidence_refs: []
x-user:
  mood-word: 清亮
---
今天沿河走了一段。
```

| 字段组 | 字段 | 编辑规则 |
|---|---|---|
| system read-only | `schema_version`, `card_id`, `revision_id`, `parent_revision_hash`, `revision_hash`, `created_by`, `lifecycle_state` | 外部修改必须隔离为 `invalid_system_metadata` / `needs_resolution`；不得静默重新分配 ID 或 history。 |
| validated user-editable | `title`, `content_role`, `owner_space`, `labels`, `source_refs`, `anchor_refs`, `evidence_refs`, Markdown body | 进入 DomainCommand 校验。引用不存在、scope 不允许或 target tombstoned 时不接受新 head。编辑这些字段不自动创建 truth/evidence/source。 |
| open user metadata | `x-user` 下任意 YAML-safe key/value（有版本化大小/深度限制） | 原样 round-trip；它不授予 schema、权限或领域状态。 |
| derived only | backlinks、FTS text、preview、embedding、board placement、parser status、receipt/cursor | 不写入 envelope；即使外部文件含同名键也作为 invalid system metadata 隔离。 |

Card-to-Card 正向语义链接统一写为 `[可读标题](hereiam-card:<card_id>)`；解析器以 `card_id`
定位，标题仅供人读。Source / Anchor / Evidence 使用 YAML 中稳定 ID 引用；BoardEdge 仍是结构化白板关系，
不会反向改写正文链接。

## 4. `memory_cards` / `whiteboard_card_extras` 正式迁移映射

1A-1 必须按下面规则生成 migration plan；任一行进入 blocked 都阻断该对象切换，不得默认选 winner。

| 旧字段 / 情形 | 目标 | 决定 |
|---|---|---|
| `memory_cards.id` / `whiteboard_card_extras.card_id` | `cards.card_id` | 原值精确保留；不同旧对象同 ID 且 payload 不同为 `duplicate_stable_id_conflict`，阻断。 |
| `memory_cards.title` | YAML `title` | 原样 UTF-8；与富文本首行投影冲突时保留两侧输入并阻断，不自动以较新时间覆盖。 |
| extras `card_kind` | `cards.content_role` | 经版本化 mapping registry 映射；未知 token 阻断，不回退 `note`。 |
| extras `owner_space` / `created_by` | catalog + YAML mirror | 已知 token精确迁移；未知或权限矛盾阻断。 |
| extras `body`、`memory_cards.retrieval_text`、RichText JSON | Markdown body | RichText plain projection 与 extras body 等价时转换 RichText；只有一个非空候选时采用该候选；两个非空且不同则 `body_authority_conflict`，保全输入并阻断。`retrieval_text` 只作对账/索引输入，不能覆盖正文。 |
| extras `tags_json` | YAML `labels` | 保序去重、原字节字符串保留；非字符串或无效 JSON 阻断。 |
| extras / Memory `presentation*` | `legacy_presentation` compatibility capsule 或派生 preview | 不进入正文真相；已分类可重建字段丢弃后重建，未知业务字段进入 capsule 并标 `degraded_preserved`，不得假装编辑器已支持。 |
| `memory_scope=user_truth` | 无直接映射 | **绝不单凭该值创建 truth relation。** 只有可核查的显式 record/correction/external-data provenance 创建 `user_truth_relations`；已知白板普通创建不创建；来源矛盾/缺失则对象阻断待人工分类。 |
| `MemoryCardSources` | `provenance_records` + 可选 Source ref | 稳定 `source_sync_id` 优先；本机整数仅入 legacy payload。`source_kind=system` 没有显式授权证据时不产生 truth。 |
| `MemoryCardStructuredFields` | 独立领域 projection / compatibility payload | `user_corrected=true` 的字段保全为领域 operation；机器字段只派生，不塞进 Markdown body。 |
| `MemoryCardRelations` | Markdown forward links | 从 `from_card_id` 的新 revision 生成 `hereiam-card:` link；缺任一 Card 阻断。切换后旧 relation 表只读，反链重建。 |
| `MemoryCardAssets.role=source/display` | provenance / asset reference | hash/object 存在才迁移；`role=evidence` 只保留 legacy evidence attachment 关系，**不能创建 EvidenceClaim**。 |
| `MemoryCardOperations` | `domain_operations` | ID、时间、action、payload digest 原样保留；能绑定 revision 的绑定，不能证明的标 `legacy_unbound_revision`，不伪造 parent。 |
| extras `deleted_at` | `object_tombstones` + `cards.lifecycle_state` | 创建可恢复 tombstone，最后有效 legacy snapshot 为恢复源；孤儿 extras 行隔离并阻断。 |
| `retrieval_text` / FTS / preview | 目标 index/projection | 从 accepted envelope rebuild；迁移后旧值只用于 equality audit，不参与 winner 选择。 |

## 5. RichText → Markdown 分类表

迁移器必须先检查原始 JSON，再调用会把未知 block 默认成 paragraph 的兼容 decoder。
每个元素只能得到以下结果之一：`deterministic`、`controlled_extension`、
`degraded_preserved`、`blocked`。报告缺少分类本身就是 `unclassified_element` 并阻断切换。

| 输入 | 分类 | 唯一映射 / 处理 |
|---|---|---|
| paragraph、普通 UTF-8 text | deterministic | 原文写入段落；只规范 CRLF→LF，不规范 Unicode。 |
| heading 1–6 | deterministic | `#`–`######`；超界 level 阻断，不能 clamp 后假装无损。 |
| unordered / ordered list，depth 0–8，合法 children | deterministic | 2-space depth 与 `-` / `1.` canonical form；保留层级和顺序。未知 list attrs 阻断。 |
| quote 与嵌套 paragraph/list/quote | deterministic | 每层 `> `；空子块使用下述 empty marker。 |
| fenced code + language | deterministic | fence 长度取大于内容中最长 backtick run；正文逐字保留。 |
| empty paragraph/list/quote block | controlled_extension | `<!-- hereiam:empty-block block_id=<id> kind=<kind> -->`；不能靠空行猜回 block 数量。 |
| non-overlapping、properly nested bold/italic/strike/code/link | deterministic | CommonMark canonical delimiters；round-trip 后每个 mark 的 `start/end` 必须与输入 **UTF-16 code-unit range 精确相等**，不得扩到整词、grapheme 或相邻空白。若 delimiter 不能精确表达原 range，改用 `controlled_extension`，不能近似成功。link 只允许安全 scheme，`hereiam-card:` 保留稳定 Card ID。 |
| underline | controlled_extension | canonical `<u>`；同时在 YAML editor extension 记录 block fingerprint，防 sanitizer 静默删除。 |
| crossing/overlap marks | controlled_extension | YAML `x-hereiam-editor.inline_ranges` 记录 `block_id`, `offset_encoding=utf16_code_units`, exact ranges/attrs 与 text fingerprint；正文保持可读文本。fingerprint 不符时阻断应用 ranges。 |
| unknown mark、未知安全语义 attr、越界/collapsed range | blocked | `unsupported_mark` / `invalid_mark_range`；不得 drop style 后成功。纯展示 attrs 只有按下述 reversible capsule 保存原 bytes 后才是 `degraded_preserved`。 |
| image | deterministic | `![alt](hereiam-asset:<asset_id>)` + YAML asset manifest；必须有 stable ref、object hash、MIME。 |
| video / attachment | controlled_extension | `[caption](hereiam-asset:<asset_id>)` + typed asset manifest；播放器/附件状态仍结构化。 |
| missing asset ref、临时路径、base64、大对象 bytes、hash mismatch | blocked | 先修复/接管对象；不能生成空占位并宣称迁移。 |
| reference block 指向 Card | deterministic | `[label](hereiam-card:<card_id>)`；目标 tombstoned 时保留链接并显示状态，不改 ID。 |
| reference block 指向 Source/Anchor/Evidence | controlled_extension | 正文可读 label + YAML typed ID ref；结构化对象仍是权威。 |
| 当前已保存 revision/history | deterministic | 每个已提交版本一对一生成 immutable Markdown revision，保留 parent 与 operation；同内容 hash 可去重 bytes，不合并逻辑 revision。 |
| editor undo/coalescing snapshot、selection、composition | degraded_preserved / dropped cache | 不是 accepted history；不迁移为 revision。若产品承诺的未提交草稿存在，则另作 pending draft，不冒充 head。 |
| 中文 IME composition 未结束 | blocked save / deferred | 保存返回 `save_deferred_ime_composition`，等 composition commit 后按原 UTF-16 sequence 建 revision；绝不提交半个拼音/候选态。 |
| committed CJK、emoji、variation selector、combining sequence | deterministic | UTF-8 精确保留；mark offsets 仍显式注明旧模型的 UTF-16 code unit 编码。 |
| Anchor embedded in presentation | deterministic only when valid | 提取为 `anchors` 行，必须有 `anchor_id + source_id + source_version_id + selector + fingerprint`；Markdown 只放 `anchor_refs`。 |
| Anchor 缺版本、selector/fingerprint 非法 | blocked | 不按 duration、页码近似或当前 Source 猜测；保留旧 payload待解决。 |
| external footnote / GFM table / raw HTML outside current editor能力 | degraded_preserved | Markdown bytes 本身或 reversible capsule 必须保有原 bytes；编辑器用只读 raw block。若编辑器无法 byte-preserving round-trip，保存被阻断而非重写。 |
| unknown block type / unknown schema version | degraded_preserved or blocked | 仅当完整 raw serialized bytes 进入 reversible capsule时可 `degraded_preserved`；否则 `unsupported_richtext_schema` blocked。不得用 paragraph fallback，也不得只留 digest。 |

`degraded_preserved` 表示**权威 Markdown 或 compatibility capsule 没有丢 bytes，但当前 editor 不能等价编辑**；
UI 和 report 必须显示降级，且无法 raw-preserving save 时保存按钮 fail closed。它不是“迁移成功但少一点格式”。

### 5.1 Reversible preservation capsule

凡 raw HTML、未知但可安全隔离的 block/attr、legacy presentation 或当前 editor 不理解的内容，
`degraded_preserved` capsule 至少必须携带：

```json
{
  "capsule_schema": 1,
  "source_schema": "rich_text_v2",
  "source_location": "blocks/3",
  "media_type": "application/json",
  "encoding": "base64",
  "raw_bytes_base64": "eyJ0eXBlIjoiLi4uIn0=",
  "raw_byte_length": 14,
  "raw_sha256": "..."
}
```

恢复时必须先 base64 decode，再同时核对 byte length 和 SHA-256，最后逐 byte 输出原内容。
只有 digest、摘要、重渲染后的 HTML、plain-text projection 或 parser AST 都**不算 preserved**。
capsule 缺 raw bytes、digest 不符或输出不逐 byte相等时 classification 必须为 `blocked`。

## 6. Anchor、Evidence、TaskArtifact 与 intake 数据流

### 6.1 Anchor / Evidence

- Anchor 的 target tuple 是 `(source_id, source_version_id, selector_kind, selector_json, fingerprint)`。
  exact match 可产生新版本的 re-anchor operation；ambiguous 保持旧版本并 `needs_resolution`；no match 为 orphaned。
- EvidenceClaim 必须引用已接受的 SourceVersion 和 Anchor/Unit。Claim payload immutable；更正创建新的 Claim
  并 `supersedes`，撤回写 operation/status。编辑 Evidence Card 正文不会改 Claim。
- `MemoryCardAssets.role=evidence`、搜索结果、OCR 或 AI 摘要只可成为 evidence proposal/provenance，
  不因迁移创建 Claim。

### 6.2 TaskArtifact promotion

TaskArtifact 保持 task-lane ID 与状态。promotion 必须是用户明确授权的单独 intent，并指定目标：

1. 文件/媒体产物先生成 SourceContent + immutable SourceVersion；
2. 需要可见内容时再创建/链接中性 Card；
3. 只有授权中明确包含“记录为事实/计划”等 truth 动作时才创建 User-truth relation；
4. 任一步失败不留下已接受的下游孤儿；重试复用同一 promotion id/digest。

### 6.3 Capture / ImportCandidate / Link Inbox Item

| 对象 | stable identity / dedupe | 状态机与恢复 | 接受前及 queue-accept 后仍禁止 |
|---|---|---|---|
| Capture | client 生成 `capture_id`；幂等键 `(installation_id,capture_id)` + payload digest | `pending → accepted_intake → cancelled/expired`；响应丢失用原 key 查原 receipt | 不建 Card、Source、User-truth、FTS、通知或 parser side effect。 |
| Link Inbox Item | Core `link_inbox_item_id`；dedupe key = provider + canonical URL，provider 有稳定 note id 时优先 provider + note id | `pending → queued → parsing/needs_screenshot/failed/cancelled/materialization_ready`；每个 phase持久化，启动只恢复非终态且未取消项 | queued/parsed 都不等于 Source/Evidence/Card；不隐藏 WebView fallback，不自动爬取。 |
| ImportCandidate | `import_candidate_id` 绑定 capture/inbox；同 canonical digest 重试复用，parser attempt 另有 generation | failure 保留 reason/parser version；retry 是显式新 attempt；cancel barrier 必须先于 worker publish检查 | 不写对象存储正式 ref、Source、Card、FTS 或下游 event，直到独立 materialize command accepted。 |

同 dedupe key + 同 digest 返回既有 identity/状态；同 key + 不同 digest 是 `idempotency_conflict`，
其机器判定固定为 `classification=blocked`，并且 `acceptedTarget=null`、`head=null`、`manifest=null`、
`receiptCount=0`、`changeCount=0`、`projectionCount=0`、`downstreamCount=0`；只允许可审计 refusal/problem result，
不能覆盖。取消/删除先写 barrier；迟到 parser result 被拒绝。Core 重启从持久状态恢复，不能从临时文件名猜阶段。

## 7. 旧 → 新 → 旧 → 新合同

1. 迁移 map 永久记录 `(legacy_table, legacy_id, legacy_digest) → stable target id / revision hash`；重跑不得新生 ID。
2. 第一轮旧→新只在隔离 clone中生成 target catalog/envelope；完成逐对象 hash、引用、operation、tombstone、index audit 后才允许未来 cutover。
3. rollback window 内，所有新 Markdown 写入必须属于上表可确定性回投的兼容子集；否则保存为 pending/blocked，不能先接受再声称旧端“可能看不到”。
4. 新→旧 rollback 是一个 journaled migration operation：把 target head 投影回 legacy `memory_cards` + extras + RichText compatibility file，保留所有迁移后新 revision/operation 的稳定 mapping，再切 legacy read authority。不能简单恢复旧数据库快照覆盖新写。
5. 再新迁移复用原 `card_id`、revision hash、operation/idempotency mapping；已经迁过的 bytes 为 duplicate，不产生第二条 User-truth、Source、event 或 Receipt。
6. 任一对象不能无损回投时，rollback **阻断在切换前**，并保留新路径为当前权威；不得丢弃新写或制造双 head。

## 8. Golden corpus 与隔离 harness 的消费合同

P4/后续正式 harness 必须新增纯合成 `schema_markdown_recovery_v1` corpus；不得读取生产 SQLite、Vault、
附件、iCore 或凭据。现有只验证 authority 的绿色报告不能替代本 ADR 的迁移模拟。

每个模拟 case 至少包含：

```json
{
  "id": "rich_overlap_marks_roundtrip",
  "family": "schema_markdown_roundtrip",
  "schemaVersion": 1,
  "input": {
    "legacy": {
      "objectType": "card",
      "stableId": "card_syn_001",
      "tables": {},
      "richText": {}
    },
    "transactionIntent": {"intentId": "intent_syn_001", "intentDigest": "sha256..."},
    "crash": {"point": "none"},
    "observedHashes": {"legacy": "sha256..."},
    "initialLedgers": {"operations": [], "receipts": [], "changes": []}
  },
  "expected": {
    "target": {"classification": "controlled_extension", "headHash": "sha256..."},
    "roundTrip": {"legacyDigest": "sha256...", "targetDigest": "sha256..."},
    "commit": {"convergence": "new", "journalPhase": "complete"},
    "result": {"status": "accepted", "blockedReason": null}
  }
}
```

`id/family/schemaVersion/input/expected` 是 case 顶层固定形状。`input` 只能承载 simulator 可见的原始事实；
所有 literal oracle 值只能在同级 `expected` 中。每案 `wholeInputDigest` 只 hash canonical `input` subtree，
不 hash `expected`；digest 不扩展 simulator 的能力面，后者仍只能获得 input深拷贝。

报告顶层必须同时给出：

- `synthetic=true`；
- `migrationExecuted=false`：没有修改生产权威；
- `migrationSimulated=true`：确实执行了内存/临时目录中的迁移与 round-trip 模拟；
- contract version、fixture digest、case counts 与逐项 classification。

Formal inventory case必须直接消费 [Formal Migration Matrix](FORMAL_MIGRATION_MATRIX.md) 的
`Formal32 exact literals`：32行九个顶层 exact key、nested identity entries、逐行 rollback/delete/index-backup literal
都参与 pinned canonical digest。converter不得用通用 fallback、rollback或tombstone默认值重造这份 catalog；复合
objectType少任一 identity entry即失败。

### 8.1 Harness oracle 独立性

正式 harness 必须把 input、literal expected 与 simulator 隔离：

1. 受控 fixture 可以采用当前实际布局：一个只读 `scenarios.json`，每个 case 内并列保存 `input` 与人工审阅的
   literal `expected` section；不强制拆成独立 expected 文件。manifest 的 `scenarioSha`
   固定整个 `scenarios.json` canonical raw bytes；每案 `wholeInputDigest` 只对该案 canonical `input` subtree bytes
   计算，不包含 expected。report 必须回显 `scenarioSha` 与每案 digest，loader 检测不符即 fail closed。
2. production converter 与 simulator converter 都不能生成、补全、改写或 normalization literal expected；
   simulator 调用只获得 case `input` 的深拷贝，其整个生命周期没有同案 expected section 的读取权限。
3. oracle comparator 只能在 actual 已生成后，从只读 scenario加载 literal expected 做结构化比较；禁止同一个 converter、mapping table
   实例或 helper 同时生成 expected 和 actual。production converter 也不得被导入合成 harness充当 oracle。
4. 独立 comparator 每案输出 `invariantResults` map，其中每个值都是 actual 与 literal expected 的独立比较结果；顶层
   `allInvariantsHeld = cases.isNotEmpty && cases.every(case => case.invariantResults.values.every(v => v == true))`。
   该值必须由逐案结果聚合，不能 hard-code、以 `passedCount == caseCount` 代替，或从 fixture 的 expected 布尔值回显。
5. negative controls 必须先把 `scenarios.json` 复制到受控临时目录，再分别篡改 pinned input bytes、literal expected、
   simulator input和一个 per-case invariant，并要求 scenarioSha/wholeInputDigest/oracle/allInvariantsHeld 在正确边界失败。

只做 schema lint、没有模拟迁移的报告必须是 `migrationSimulated=false`，不得拿它满足本包 Gate。
至少覆盖：普通 Card 防误升格、显式 truth、双表冲突、所有 block/mark/asset/IME/history/Anchor 类别、
footnote/empty/外部编辑、Evidence 非升格、TaskArtifact promotion、三类 intake 的 dedupe/cancel/failure/restart、
旧→新→旧保留新写→再新，以及 commit ADR 的每个 crash phase。

## 9. Gate 分界与剩余红灯

- **1A-0 在本文内不再保留 schema / Markdown / mapping 选项。** 真人 Gate 只决定接受或退回这套选择。
- **1A-1 红灯：** 生产表/migration、Record Organizer 与旧调用者适配、真实数据 clone 验证尚未实施。
- **1A-2 红灯：** Vault writer/watcher、外部编辑安全、迁移/rollback 与 crash injection 尚未实施。
- **1A-3 红灯：** Core API、epoch/fencing/outbox 仍是目标合同。
- Evidence 生产与真实灾难恢复分别属于后续 Evidence Gate / Gate 1C；这不构成 1A-0 的未决 schema 选项。
