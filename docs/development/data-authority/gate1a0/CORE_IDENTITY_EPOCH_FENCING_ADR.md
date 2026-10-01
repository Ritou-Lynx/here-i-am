# ADR — Core 身份、epoch 与 fencing

> **状态：Gate 1A-0 已冻结并经 Lynx 真人 Gate 通过的目标合同；未实现。**
>
> **范围：** Core authority registration、设备/探针/worker 身份、凭据代际、灾难接管与旧 writer 返网隔离。本文不改变当前运行权威、生产 schema、设备、外部配置或 API。

## 1. 决策

每一个可接受写入只能由一个已注册、未撤销的 **active Core instance** 在一个持久化、严格递增的 **authority epoch** 中接受。该 Core 在完成本 ADR 指定的身份、代际、epoch 与 fencing 校验前，不得查询幂等记录、对象、cursor、snapshot 或任何可写资源。

接受者为 Core；device installation、probe 和 worker 都只提交有界 intent 或受限 workload 结果，不能自行分配权威 receipt、server sequence、projection、删除结果或新 epoch。任何校验失败都不产生 acceptance mutation；冲突只能明确 `reject` 或 `needs_resolution`，不能被“较新时间”“重试”“last writer wins”静默接受。

## 2. 当前事实与本 ADR 的目标边界

| 项目 | 当前可核查事实 | 本 ADR 冻结的目标合同 |
|---|---|---|
| Core identity | 当前 iCore store 首次创建并持久化 `node_id`；health 返回节点身份。[Core API v0](../../../companion-first/CORE_API_V0.md#L20-L23) | 注册表中的 `core_instance_id` 是一次具体权威安装/恢复实例，不等同于主机名、地址或旧 `node_id`。 |
| device pairing | pairing code 注册 installation ID；同 installation 再配对轮换 token，且 pairing code 单次消费。[Core API v0](../../../companion-first/CORE_API_V0.md#L29-L36) | installation、credential generation、scope、revoke 与 re-pair 作为持久 authority registration 的独立记录。 |
| worker lease | 同一 Core 内每 workload 只有一个 holder；workload fencing token 递增并拒绝迟到写。[Core API v0](../../../companion-first/CORE_API_V0.md#L70-L100) | 所有 worker proof 还必须绑定 Core instance + authority epoch；lease 不能选主，也不能跨 Core 证明 holder 有效。 |
| multi-Core | API v0 明确不含多 Core 选主，现有 lease 只解决一个权威 Core 进程内单执行。[Core API v0](../../../companion-first/CORE_API_V0.md#L150-L151) | 灾难接管必须创建/激活新 instance 并提升 epoch；旧 Core 永远不能凭本地 lease 或旧 token 恢复写入。 |

因此，现有 `worker_leases` 的 `fencing_token` 不是跨 Core fencing，也不是灾难恢复证明；它仅是当前单 Core 的 workload-local 防护。本 ADR 不把它追溯宣称为已具备的 protection。

## 3. 身份词典与不可混用的命名

| 名称 | 稳定性 / 产生者 | 绑定关系 | 禁止替代 |
|---|---|---|---|
| `authority_id` | 一个用户权威域，创建时固定 | 关联 authority registration 与 epoch ledger | 不是 Core 主机、设备或数据库文件路径。 |
| `core_instance_id` | 每次新 Core 安装、从恢复介质激活或灾难接管时新生 | 绑定一个 `authority_id`；可在多个 epoch 的历史记录中出现 | 不是 hostname、Tailscale DNS、IP、进程 PID 或 worker ID。 |
| `authority_epoch` | authority registration 持久化分配，严格递增、不可回退 | 一个 epoch 只有一个 active `core_instance_id` | 不是 worker fencing token、cursor、时间戳或 schema version。 |
| `device_installation_id` | app 安装生成并安全保存；重装/安全存储丢失后为新 ID | 注册到 authority；显示名可变 | 不是用户 ID、硬件指纹或 device credential。 |
| `probe_lineage_id` | Core 注册的采集器身份；由 installation 或受管主机承载 | scope、generation、撤销与 `(probe, origin_sequence)` 单调序列均归此 lineage | 不是 event ID、source 名称或 app capability claim。 |
| `worker_holder_id` | 一个 workload execution holder 的稳定实例 ID | 只在特定 Core instance、epoch 与 workload lease 内有效 | 不是 Core instance、device installation 或长期账号。 |
| `credential_generation` | registration 中单调递增代际 | 每次 re-pair / rotate / revoke 后旧代际永久失效 | 不是 epoch；轮换设备 token 不提升 authority epoch。 |
| `workload_fencing_token` | active Core 为一个 workload lease 发放，workload-local 严格递增 | proof 必须同时携带 instance + epoch + holder + lease | 不能独立授权跨 Core 写入。 |

所有 identity fields 由 Core 或受认证的 registration ceremony 分配/确认；客户端提供的 display name、platform、capabilities 或 hostname 都是声明，不能成为 authority identity。

## 4. 持久化 authority registration 与 credential 合同

这是目标数据合同，不是本 Goal 的 schema 设计。实现必须在同一可恢复的 authority state 中持久化下列最小记录，且备份/恢复保留其单调性：

| 记录 | 最低字段 | 不变量 |
|---|---|---|
| `authority_registration` | `authority_id`、active `core_instance_id`、active `authority_epoch`、状态、变更 receipt/reference | epoch 只能上升；任意时刻恰有一个 active Core。 |
| `core_instance_registration` | `core_instance_id`、所属 authority、创建来源（initial/recovery/takeover）、激活/撤销 epoch、恢复 manifest reference | 被 supersede/revoke 的 instance 不可重新 active。 |
| `device_installation_registration` | installation ID、状态、当前 credential generation、允许 scopes、paired Core/epoch、撤销原因/时间 | 一台安装仅有一个 active generation；同 installation re-pair 必须失效旧 generation。 |
| `probe_registration` | probe lineage、承载 installation、最小 source capability、write-only scopes、当前 generation、状态 | probe 不继承 chat/read/admin 或其他 probe scope；被撤销 lineage 不能换 ID 重放旧 intent。 |
| `worker_registration/lease` | workload、holder、Core instance、authority epoch、lease token digest、workload fencing token、到期 | worker proof 只能在其绑定的 Core + epoch + active lease 上成立。 |
| `epoch_transition_receipt` | from/to epoch、old/new Core instance、原因、authority-state revision/manifest、完成时间 | takeover 是可审计的单一状态迁移，不是两个 Core 并行启动。 |

### 4.1 凭据 generation、scope、revoke 与 re-pair

1. 配对只在明确、短时的 pairing ceremony 内发生；pairing code 是一次性 bootstrap secret，消费记录必须持久化，不能因服务重启复用。
2. 成功 re-pair 同一 `device_installation_id` 时，Core 原子地提升该 installation 的 `credential_generation`，签发仅含批准 scopes 的新 credential，并立即撤销旧 generation；不得留下两个有效 token。
3. 普通 device credential 默认仅具其已注册 submission/read scope。probe credential 必须是 write-only、lineage-bound 的最小 scope；worker credential 与 device/probe credential 分离，且不因 holder 获取 lease 而越权。
4. revoke、forget installation、forget probe、Core supersede 和 epoch takeover 都是同步 access-control 状态变更：旧 credential/generation 的验证必须先失败，随后才可异步清理 outbox、projection、物理数据或备份副本。
5. credential 绝不进入日志、同步配置、snapshot payload、whiteboard、fixture 或 receipt 明文；receipt 只可引用 opaque credential/registration ID 与 generation。

## 5. 强制校验顺序

所有 mutation endpoint、worker publication、activity/probe ingress、cursor/snapshot acknowledgement 与删除/恢复动作必须遵循此顺序。失败立即终止，不读取幂等或业务资源，也不写 receipt、cursor、sequence、projection 或 lease side effect。

1. **Protocol/envelope bounds：** 版本、大小、allow-list、必填字段和 canonicalization。
2. **Credential proof：** 验签/哈希比较、credential type、registration existence、credential generation、revoke/expiry。
3. **Caller binding and scope：** authenticated identity 等于 payload 的 installation/probe/holder 声明，且 scope 允许该 endpoint 和对象域。
4. **Authority fencing：** target `authority_id`、`core_instance_id` 与 `authority_epoch` 必须等于持久化 active registration；worker 额外验证 workload、holder、lease token、lease expiry 和 workload fencing token。
5. **Lineage and state admissibility：** probe/installation 未 forgotten，origin sequence 的允许前进规则、intent TTL/retention generation、对象状态与 delete/recovery barrier；不满足时 `reject` 或 `needs_resolution`。
6. **Only then idempotency lookup：** 以 canonical digest 查询 immutable key；同 digest 才能 `duplicate` 返回原 receipt，任何不同 digest 都是 `idempotency_conflict`。
7. **Only then resource read and atomic acceptance：** 读取允许对象、应用一个完整事务、分配 Core-owned receipt/sequence，并记录绑定 epoch 的 acceptance reference。

这条顺序意味着旧 token、撤销 probe、旧 epoch、旧 Core 或 stale worker 不得利用已有 `sync_id` / `event_id` 得到 `duplicate`，更不得藉此发现资源或 receipt；其结果是认证/epoch/revocation 拒绝，而非幂等结果。

## 6. Epoch transition 与旧 writer 返网隔离

### 6.1 灾难接管的唯一流程

新 Core 只能在经验证的可恢复 authority state/manifest 上启动接管 ceremony：

1. 读取恢复介质，验证其 authority identity、完整性与最后已提交 authority-state revision；无法证明 lineage 时停止为 `needs_resolution`，不得以空库自封 authority。
2. 在受控、可审计的 transition 中创建新的 `core_instance_id`，将 `authority_epoch` 原子提升为 `E+1`，并写入 `epoch_transition_receipt`。
3. 同一 transition 使旧 active Core instance、全部其 worker leases 与其 worker proofs 失效；服务端必须持久化这一结论，即使旧 Core 当时离线。
4. 新 Core 在新 epoch 重新签发/确认所需 device、probe 与 worker credential generations。旧 generation 默认不能跨 epoch继续有效；若产品将来允许受控 re-authorization，必须是显式新 generation，而非接受旧 token。
5. 新 Core 提供带 `authority_id`、`core_instance_id`、epoch、transition receipt reference 的 health/snapshot metadata。客户端只在认证并持久化该 metadata 后更新本地 authority binding/cursor。

没有可验证恢复介质、无原子 registration state、或无法防止旧 Core仍对同一存储写入时，接管必须停止；“两个 Core 都先启动，再靠最后请求赢”是禁止的 split-brain 路径。

### 6.2 旧 writer / 旧 token / 积压 intent

| 返网对象 | 必须结果 | 禁止结果 |
|---|---|---|
| 旧 Core process | `core_instance_superseded` / `stale_authority_epoch`；不得接受、分配 receipt 或续 worker lease | 读到本地旧 DB 后重新成为 active，或向新 Core 复制其未审计写入。 |
| 旧 worker holder/lease | `stale_authority_epoch` 或 `stale_worker_fence`；旧 lease 永远不可 renew | 仅因 workload fencing token 数字更大/相等就放行跨 Core publication。 |
| 旧 device/probe credential | `credential_revoked` / `credential_generation_stale`，在幂等 lookup 前失败 | 用旧 event ID 得 `duplicate`、泄露 receipt 或触发投影。 |
| 新 credential 携带旧 epoch 的积压 intent | `stale_authority_epoch`；客户端不得自行改写 epoch 后重发 | 将 intent 自动归入新 epoch。 |
| 新 credential 的合格旧时点 intent | 仅在显式 re-submission/reconciliation API 中，连同原 epoch、原 canonical digest、origin sequence 和用户/策略允许的 reconciliation proof 进入 `needs_resolution` 或明确 `reject` | 自动回放为新 epoch accepted，或仅凭客户端时间排序覆盖新状态。 |

`needs_resolution` 是保全而非接受：保存最小不可变冲突证据与原因，不能生成对象变更、projection、notification、worker side effect 或权威 receipt。仅经未来明确的人工/规则化 reconciliation 产生一条新的、可追溯 intent，才能进入完整校验流程。

## 7. 与 1A-3 和 Gate 1C 的关系

- **Gate 1A-3：** 负责把本 ADR 的 Core intent、authority epoch、fencing、registration、接管 API 与客户端绑定落到实现；在 1A-3 真人通过前，本文件不能被解释为 iCore 已具备跨 Core 防护。
- **Gate 1C：** 负责可恢复 manifest、备份副本、恢复演练与物理到期证据。它不授予一个恢复副本自动成为新 Core 的权限；必须先走本 ADR 的 epoch transition。逻辑删除/撤销先阻断在线访问，历史备份只按公开保留期物理到期。[MDA-0 retention contract](../../activity/mda0/RETENTION_DELETION_AND_TOPOLOGY.md#L83-L91)
- **MDA-0：** activity probe 只提交 intent；Core 才能接受并分配 projection。MDA-0 提案也把 durable epoch、registration、fencing 和 takeover invalidation 列为 activity ingress 的前置条件。[Device Activity ADR](../../activity/mda0/DEVICE_ACTIVITY_V1_ADR.md#L13-L20)

## 8. P4 合成测试词典

P4 只能使用 synthetic IDs、临时目录和确定性时钟；每例必须断言 `migrationExecuted=false`，并验证无 acceptance mutation（无新 receipt/sequence/projection/cursor/lease side effect），除非预期明确为 accepted。

| 用例 | 输入概述 | 预期错误 / 不变量 |
|---|---|---|
| `active_core_accepts_bound_intent` | active `(core-A,E7)`、有效 `(device-A,g3)` 与匹配 epoch intent | `accepted`；receipt 绑定 `core-A,E7,g3`。 |
| `superseded_core_cannot_accept` | `(core-A,E7)` 被 `(core-B,E8)` 接管后旧 Core 写入 | `core_instance_superseded` 或 `stale_authority_epoch`；零 mutation。 |
| `old_epoch_checked_before_idempotency` | 已 accepted ID 被 `(core-A,E7)` 或 payload `E7` 重放到 active `E8` | `stale_authority_epoch`，**不是** `duplicate`；不得读取/泄露原 receipt。 |
| `revoked_generation_checked_before_idempotency` | revoked `(device-A,g3)` 使用原 event/sync ID | `credential_revoked` 或 `credential_generation_stale`，不是 `duplicate`；零 mutation。 |
| `re_pair_invalidates_single_installation_token` | 同 installation re-pair `g3→g4` 后同时用两 token | `g3` 被拒，`g4` 可走后续校验；注册中至多一个 active generation。 |
| `cross_device_impersonation` | token 属于 device A，payload 声明 device B 或 probe B | `identity_binding_mismatch` / `scope_denied`，在 idempotency/resource read 前失败。 |
| `old_worker_lease_cannot_cross_epoch` | E7 worker lease/fence 对 E8 publish/renew | `stale_authority_epoch`；E7 lease 不可在 E8 reuse。 |
| `workload_fence_stale_within_active_core` | 同 E8 workload holder A 过期，holder B 获取更高 fence | `stale_worker_fence`；这是单 Core lease 证据，不等价于前一例。 |
| `backlog_requires_resolution` | 新 generation 带旧 epoch、未接受的 offline intent | `needs_resolution` 或 policy `reject`；绝不 silent accept 或改写 epoch。 |
| `same_key_different_digest_after_all_fences` | 当前有效 identity/epoch，immutable key digest 不同 | `idempotency_conflict`；无替换、无部分接受。 |
| `takeover_requires_recovery_lineage` | 新候选 Core 无法验证 manifest/authority revision | `needs_resolution` / `recovery_lineage_unverified`；不提升 epoch、不激活 Core。 |

## 9. Consequences / open risks

- 需要未来 1A-3 明确 authority-state 的原子存储、签名/密钥轮换、跨介质恢复和 health/snapshot payload；本 ADR 故意不选择生产 schema。
- 设备重装、安全存储丢失、Core 已损坏但仍可联网、以及“保留的离线 intent 是否允许人工重放”的 UX/治理规则尚未实现；默认安全结果是 reject 或 `needs_resolution`。
- 所有活动、聊天、User-truth 与 worker domain 的对象接受矩阵由 1A0-P1 冻结；本文不越权重定义对象 authority。
