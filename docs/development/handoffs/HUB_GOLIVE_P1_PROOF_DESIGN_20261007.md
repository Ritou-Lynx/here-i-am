# Hub Go-live P1 legacy capture ownership proof design（仅设计）

日期：2026-10-07
基线：`df35b8872b623a119f5131cbdc1997cb9262ec02`
状态：**接口与测试建议，未实现、未执行真实数据读取、未通过现场 Gate、不可据此上线。**

后续实现已另行记录于 `HUB_GOLIVE_P1_HOST_20261007.md` 和
`HUB_GOLIVE_P1_APP_20261007.md`。本篇保留为设计审查记录，部分草案未采用；
实际接口与验证结果以上述实现交接为准，尤其 Core 接受绑定使用 HMAC，
不把正文的普通哈希写入永久操作元数据。

本文只收敛 P1 的旧 `note -> capture -> card/finance` 接管证据。实现应留在现有非 `release_schema6` 模块；不修改 release、maintenance、生命周期启动器或现场清单。本设计不签发授权、不选择生产 owner、不读取真实 note、卡片、账本、配置或凭据。

## 1. 现有契约与缺口

可直接复用的边界：

- Core 的 `DomainStore.adoptLegacyRecord` 是本机专用入口，要求 `:adopt`、import actor/source、显式授权、同步 host verifier，稳定 op id 绑定 source/revision/batch/mapping；接受记录、receipt、change、op 结果同事务，丢回复后同 op 可恢复（`tools/i_core/domain_store.mjs:249-299`，`tools/i_core/domain_adoption.test.mjs:33-123`）。
- production acceptance receipt 已绑定 Core、principal、op、policy、目标 revision 和 change sequence，`receipt_auth` 覆盖整份 receipt；shadow 不产生 production receipt（`tools/i_core/domain_store.mjs:292-295`，`docs/development/I_CORE_DOMAIN_CONTRACT.md:167-169,251-255`）。
- 旧 note importer 的 durable receipt 保存 note id/revision、upsert/delete、card ids、slots/issues 和 projection source ref，且卡片/投影/receipt 在一个 App DB 事务中（`lib/data/memory_v3/notes/claude_web_note_importer.dart:82-154`）。
- 新 capture reconciler 已保存生成内容摘要、完整当前投影 fingerprint、来源独占检查和用户修改保护；缺 snapshot 的旧 slot 明确是 `legacy_generation_unverified`，不会用当前卡片反造 baseline（`lib/data/memory_v3/services/capture_card_reconciler.dart:21-110,137-226,246-364`）。
- capture finance 新路径使用 `captures:<id>` source ref、确定性 ledger id 和 `system:capture_bridge:<sourceRef>` writer marker；删除不信任可编辑的 `linked_fact_id`（`lib/data/services/ai_finance_service.dart:121-185`）。
- 所有权 lease/fence 已使用同一 App SQLite 状态、token 和 generation；切换时会核 Gate、note 映射和已存在 card id（`lib/data/personal_data_hub/capture_consumer_ownership.dart:29-215`）。

当前阻断点是 `selectCore` 只比较 old/new card ID 集合和一个自由字符串 `origin_proof`。这不能证明同 ID 的当前卡片确由旧 note 生成，也没有把 Core receipt 与本机 card/finance 的摘要和版本绑定（`capture_consumer_ownership.dart:146-214`；现有测试只覆盖同 ID 缺 lifecycle 时拒绝，见 `capture_consumer_ownership_test.dart:243-283`）。

## 2. 必须同时成立的证明不变量

每个最新旧 note revision 都要有一份 `LegacyCaptureProjectionManifestV1`。manifest 只能在 legacy owner lease 下构建，并在最终 owner 切换的 fenced SQLite 事务中重算。接受条件是以下四层全部成立：

1. **历史生成证据**：card id 必须同时出现在该 note 最新 `external_note_import` receipt 和唯一的历史 `create` operation 中；create operation 的 `source_kind`、payload source kind/ref、card id 必须指向该 note。仅 ID 相同、文字相同、当前 source row 相同都不够。
2. **未修改证据**：从 create payload 中的原始 `OrganizedCard.toJson()` 生成规范化 `generated_card_digest`；当前 card、structured fields、semantic entity links、source 元数据必须与该生成对象逐字段相等，且无 user correction、`userCorrected` relation/field 或后续 update/delete/restore/correct/merge/split。再对当前完整受管投影计算 `live_projection_digest`。历史 witness 不完整或当前值不能精确重放时为 `unverified`，不能从当前值建立 baseline。
3. **finance 归属证据**：只有已证明的 finance card 才能关联账本。还必须存在与 card create/旧 note receipt 同事务形成的不可变 finance creation witness，至少绑定 ledger id、writer/version 和生成时 row digest。旧通用 bridge row 的 `character_id=system:card_bridge`、`linked_fact_id=card_id` 以及与 create payload 完全一致的金额、时间、用途等只是必要条件，不能单独证明它从未被修改。当前 `ai_finance_ledger` 没有自己的 append-only creation audit，旧 external-note receipt 也未保存 ledger id/digest；因此现存旧 finance row 若没有别的可信历史 witness，必须是 `finance_origin_unverified`，不能用今天的 row 现场补造 baseline。手工 row、重复候选、任何值变化或缺失同样阻断。未来 proof-capable legacy 写入应在原生成事务内落 witness；未来 capture projection 继续使用现有确定性 ID/writer marker。
4. **Core 接受证据**：production receipt 必须是当前 Core/principal/policy 下的 `accepted` 或同 op 的 `duplicate`，target 为相同 capture id/revision；receipt 中经 `receipt_auth` 认证的 adoption binding digest 必须等于本机 manifest version/digest、source revision、mapping version 和当前 `DomainBinding.forDomain('captures')` 的规范化摘要。shadow、needs_resolution、普通 create receipt、404、不可见或未认证字符串都不满足。

manifest 对 outputs 按 card id 排序，所有 JSON 使用现有 `canonicalJson` 规则。它保存摘要、版本、operation/receipt 标识和状态，不复制 note 正文、card 文本、模型 trace 或凭据。latest note 集合与 manifest 集合必须完全相等；mapping 必须一对一，墓碑也要有显式 Core tombstone receipt，不能把不可见/404 当删除。

建议的本机结构如下，字段名可按现有 Dart 风格调整，但语义不应缩水：

```text
LegacyCaptureProjectionManifestV1
  schema = 1
  note_receipt_id, note_id, note_revision, note_receipt_digest, op
  capture_id, capture_revision, mapping_version
  outputs[]
    card_id, create_operation_id
    generated_card_digest, live_projection_digest
    finance? { ledger_id, creation_witness_id, projection_version,
               generated_row_digest, live_row_digest }
  tombstone
  manifest_digest = sha256(canonical(all fields except manifest_digest))
```

`note_id`/card id 属于本机私有 proof，不进入 Git、CLI 普通输出或日志。CLI 只报 eligible/unverified/conflict 的数量和固定错误码。

## 3. Core worker 接口草案（p1_mcp）

在 `tools/i_core/domain_store.mjs` 的 local-only adoption options 增加严格对象，禁止 HTTP 普通 intent 传入：

```text
projectionProof
  format = legacy-capture-projection-v1
  manifest_version = 1
  manifest_digest = 64 lowercase hex
  consumer_binding_digest = 64 lowercase hex
```

`verifyLegacyAdoption` 收到冻结副本中的 `projectionProof`，只能返回同步 `true` 才继续。Core 把下列 canonical 对象的 SHA-256 放入 production receipt 的可选 `adoption_binding_digest`，并让现有 `receipt_auth` 覆盖它：

```text
{
  format, domain, core_instance_id, principal_id,
  accepted_op_id, target_id, target_revision,
  source_kind, source_record_id, source_revision,
  batch_id, mapping_version,
  manifest_version, manifest_digest, consumer_binding_digest
}
```

同一对象也进入不可变 op metadata；request digest 必须覆盖完整 `projectionProof`。`getOperation` 继续按现有 scope/source/principal 规则返回原结果，供丢回复恢复。不要用 `batchId`、`mappingVersion`、`authorizationRef` 或自由字符串承载摘要，也不要把 shadow result 包装成 receipt。

Core 单元测试至少增加：

- 精确 proof 首次接受及同 op 重放返回同 receipt/binding；manifest/binding/version 任一变化触发 idempotency conflict。
- receipt target/source revision/core/principal 与 binding 对齐；篡改任何 adoption binding 字段后 `receipt_auth` 不再有效。
- host verifier 收到不可变对象；false/非 boolean、缺 proof、错格式/摘要均 fail closed。
- shadow 无 production receipt，off/frozen 不 apply；needs_resolution 不能生成 proof。
- 每个 precommit fault barrier 后没有半份 record/receipt/op/binding；commit 后丢回复并 reopen 能以同 op 恢复。

## 4. App worker 接口草案（p1_app）

建议在 `lib/data/personal_data_hub/` 增加独立 proof builder/verifier，例如 `capture_adoption_proof.dart`，复用 reconciler 的 canonical digest/fingerprint 规则；不要把 proof 逻辑塞进 UI 或启动器。

把当前自由字符串式 `CoreCaptureTakeover` 收紧为结构化请求：

```text
CoreCaptureTakeoverV2
  gate_ref
  binding_fingerprint = canonicalJson(DomainBinding.forDomain('captures'))
  mapping_version
  items[]
    note_id, note_revision, capture_id, capture_revision
    manifest_version, manifest_digest
    adoption_op_id, receipt_id
```

`verifyCoreGate` 不再只返回 bool；返回经过当前连接重新读取和认证的 typed claims，至少含 Core/principal/policy、receipt target、accepted op、adoption binding digest 和 target state。`selectCore` 不信任调用者传入的 receipt/body/auth 字符串。

建议两阶段执行，避免网络期间持有 SQLite writer transaction：

1. `prepare`：`runLegacy` 取得 lease；读取 latest note receipts，严格解析；构建 manifest；调用 Core adoption（稳定 op id）；未知结果只查询/重试同 op。每完成一项，将 Core receipt identity 与 manifest digest 写入本机 `prepared` proof 行，但 owner 仍是 legacy。
2. `commit`：再次 `runLegacy`；先在线重验当前 Core receipt claims，再进入 `lease.fenced`。事务内重读 latest receipts、重算全部 manifest、核 exact set/injective mapping/当前 binding，再一次性写 durable cutover proof 和 `owner=core`。proof 行、owner、lease generation 属于同一事务。

owner 已是 core 且 proof digest 完全一致时允许幂等返回；不同 proof、binding 或 item 集合必须拒绝。owner 为 core 后不提供隐式 reverse transition。

App 单元测试至少增加：

- 唯一 create audit + note receipt + exact source/current projection 才 eligible；同 card id 的 user/其他 source 内容拒绝。
- create payload 缺失/重复、receipt 形状错误、card/current projection 不同、user correction、后续 mutation、asset/relationship 无法重放均拒绝，不静默 skip。
- finance 只有 immutable creation witness + exact bridge row 才可进入 manifest；仅有当前精确 row 仍拒绝。手工同 `linked_fact_id`、重复 row、金额/时间/用途/marker 被改、缺 row均拒绝；不能现场制造 baseline。
- Core receipt 的 target/revision/op/core/principal/policy/manifest/binding 任一不符均拒绝；401/403/404 和不可见保持 legacy 且标 unknown/unverified。
- 两个 DB connection 同时 prepare/commit 只有一个 generation 可提交；失效 lease 即使 proof 正确也不能写 owner。
- manifest 构建后 note receipt、card、finance 或 binding 改变，commit 重算失败；owner 和 proof 不变。
- owner 写入前/后注入故障：前者完整回滚并保持 legacy，后者重启可读到同一 durable core owner/proof，不出现半状态。

## 5. 攻击与故障矩阵

| 场景 | 必须观测 | 期望收敛 |
|---|---|---|
| 用户卡片恰好使用同 ID | 无匹配 note create audit/source chain | `unverified`，legacy owner 不变 |
| 用户改过旧生成卡 | correction/userCorrected/operation chain 或 current digest 不同 | 保留用户内容，阻止接管 |
| 当前卡片伪装成生成结果 | create payload 缺失或不能精确重放 | 不从当前行建立 baseline |
| 手工账本 row 复用 card id | writer marker或确定性字段不符 | 不归 capture 所有，不删不改，阻止接管 |
| 旧 finance row 当前完全吻合但无 creation witness | 无法证明历史未修改 | `finance_origin_unverified`，禁止用当前 row 补 baseline |
| 旧 finance row 已被编辑 | witness、row digest或确定性投影不符 | `finance_origin_unverified`，阻止接管 |
| note/capture/card 多对一 | mapping 或 output 集合非 injective | 整批拒绝 |
| shadow receipt 冒充正式 | 无 production acceptance receipt/binding | 拒绝 |
| receipt 重放到另一 Core/principal/install/generation/view | Core claims 或 consumer binding digest 不同 | `binding_changed`/proof reject |
| Core 接受后响应丢失 | 同 op 查询或重试返回同 receipt | owner 仍 legacy，恢复后继续 prepare |
| Core 返回未知、401/403/404 | 无可认证 acceptance | 不把不可见当未提交/删除；保留 prepared/legacy，等待显式恢复 |
| App 在 Core commit 后崩溃 | Core 有 receipt，本机无 owner flip | 重启以同 op/manifest 恢复，禁止新 op 重导 |
| App 在本机 fenced commit 前崩溃 | SQLite 没有 owner/proof 半写 | legacy 继续 |
| App commit 后立刻崩溃 | owner/proof 同事务已 durable | 重启只允许 core consumer，旧消费者被 owner mismatch 阻止 |
| 两进程同时切换 | 同 DB lease token/generation | 一方成功；另一方 busy/fenced/mismatch，无双消费 |
| lease 到期后旧进程回写 | generation/token 失效 | fenced，不能推进 receipt/cursor/owner |
| commit 前 note/card/ledger 又变化 | 最终事务重算 manifest 不同 | 回滚，legacy owner 不变 |
| Core 已接收但本机最终验证失败 | 不删除 Core record、不伪称 rollback | freeze/停止新源并向前对账；不得自动双开旧/新消费者 |
| Core owner 后请求回切 | 现有代码无 reverse proof | 拒绝；逐记录和队列对账需另行设计、授权和 Gate |

## 6. 验收边界与 worker 对接

p1_mcp 交付 Core adoption binding、严格 shape、签名 receipt 和丢回复/故障测试；p1_app 交付历史 proof builder、finance verifier、结构化 takeover、同 DB 最终 revalidation 和并发/崩溃测试。两边用固定合成 manifest fixture 对齐 canonical digest；fixture 不含真实正文、ID、路径、配置或凭据。

只有以下证据同时完成，才能把代码候选描述为“可进入现场 Gate”：Core 单元测试通过、App 单元/多连接故障测试通过、跨语言 canonical fixture digest 一致、现有 capture lifecycle/finance/ownership 测试无回归。它仍不等于 production Gate、真实数据迁移授权、消费者切换批准或可上线结论。

历史记录若缺唯一 create audit或无法精确重放，必须报告 aggregate blocker count。历史 finance row 缺同事务 immutable creation witness 时也必须单独计入 blocker；精确匹配当前 bridge 规则不能消除这个缺口。尤其不能为了完成接管而把今天的 card/ledger 行哈希后称为“generated baseline”。
