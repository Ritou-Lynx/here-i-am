# Gate 1A-0 ADR — Outbox、Cursor、保留与恢复边界

> 状态：**Gate 1A-0 已冻结并经 Lynx 真人 Gate 通过的目标合同；未实现**。后续实现仍须由独立 Goal 授权。
>
> 范围：冻结未来 Core 接受路径的语义；不改变当前 runtime、SQLite/schema、设备或外部配置。
>
> 输入而非现状：[`CORE_API_V0.md`](../../../companion-first/CORE_API_V0.md)、[`CORE_SYNC_DATA_INVENTORY.md`](../../../companion-first/CORE_SYNC_DATA_INVENTORY.md)、[MDA-0 retention/topology](../../activity/mda0/RETENTION_DELETION_AND_TOPOLOGY.md)、[MDA-0 activity ADR](../../activity/mda0/DEVICE_ACTIVITY_V1_ADR.md)。

## 1. 结论与现状边界

未来唯一接受者是处于当前 authority epoch 的 Windows Core。设备只能提交有界、加密、耐久的 intent outbox；outbox 不是权威数据库，也不授权客户端直接写投影、User-truth、Card、Source、Evidence、Dreaming、TaskArtifact 或 activity summary。

当前 runtime 仅有 chat v0.1：消息 outbox 与 chat 行同事务双写、opaque chat change cursor 和 ack；它**没有** activity ingress、retained watermark、`resync_required`、按领域 cursor、认证 snapshot 原子提交、跨 Core epoch 或灾难接管。因此本文的全部新字段和步骤是目标合同，不能被宣称为已实现。

## 2. 角色、不变量与词典

| 词 | 目标定义 / 不变量 |
|---|---|
| intent | 设备提出但尚未由 Core 接受的不可变请求；不可触发下游副作用。 |
| acceptance receipt | 当前 active Core/epoch 在一个接受事务内持久写出的权威回执，绑定 `core_instance_id`、`epoch`、accepted operation/sequence 与 canonical idempotency key/digest；只适用于 `accepted` / 经授权验证后的 `duplicate`。 |
| protected acceptance proof | 在受保护的 acceptance/audit 路径中，证明会校验并绑定 device/probe generation；有 worker 时再校验其 workload fence。普通 domain receipt 不假设存在 workload fencing token，且绝不含 lease token、secret 或其他凭据。 |
| accepted / duplicate | acceptance receipt 与所接受事实/change 同时持久化；不能只有“已接受”响应或 ghost receipt。`duplicate` 只在当前有效 identity/generation、active Core/epoch 和 fencing 已通过后，才可返回原 acceptance receipt。 |
| rejected / expired / needs_resolution | refusal/problem result 或 decision record；可审计、可作为本地终态持久化，但不是 acceptance receipt，不生成 canonical domain change、projection 或权威 sequence。`needs_resolution` 要求用户或管理员明确处理。 |
| cursor | 某个**领域**的 opaque 已消费位置；客户端不可解析、构造、在 chat/activity 间复用。 |
| retained watermark | 该领域仍可增量读取的最早权威 sequence/位置；比它旧的 cursor 不能继续增量拉取。 |
| authenticated snapshot | Core 在当前 epoch 生成、签名/认证、范围受限的当前态包，带 snapshot id、base watermark、policy version 和 digest。 |

所有接受、重放、删除、读取和 ack 必须先校验 credential generation、设备/探针绑定、scope、Core instance/epoch 与 fencing；这些检查在任何 idempotency lookup、资源读取或投影写入之前发生。旧 token、旧 snapshot、旧 cursor 和旧 writer 均不得改变新 epoch。

## 3. Client outbox 合同

### 3.1 状态、容量与 TTL

每个 intent 必须有稳定 idempotency key（chat 使用 `sync_id`；activity 同时使用 `event_id` 和 `(device_id, probe_id, origin_sequence)`），canonical payload digest、创建时间、expiry、领域、目标 Core lineage/epoch 和状态：`pending`、`submitting`、`accepted`、`duplicate`、`rejected`、`expired`、`needs_resolution`。先通过当前有效 identity/generation、scope、active Core/epoch 与 fencing，才可查询幂等账本；之后同一 key 同 digest 重试只能返回同一 acceptance receipt，同一 key 不同 digest 必须 `idempotency_conflict`，不得覆盖旧行。旧 credential/generation/Core/epoch 必须在 lookup 前被拒，且不得获知 duplicate/receipt。

容量、每项/整批字节数、最长 TTL、重试退避和保留配额必须由后续实现 ADR 定为版本化常量并返回机器可读错误；本 ADR 不虚构数值。达到任一上限时：

1. 新 intent 不得静默丢弃、挤掉未终态行或生成新 key；返回 `outbox_full` / `payload_too_large`，保留既有 pending 行。
2. 过期前可用原 key 重试；Core 按自己的权威时钟在接受前检查 TTL。
3. 过期时原子标为 `expired` 并保留 refusal/problem result/原因；不得因联网恢复补交，也不得据此推断用户状态。
4. 不可自动重试的 401、409、epoch/credential mismatch、scope 拒绝和 protocol incompatibility 进入 `needs_resolution` 或 `rejected`，并持久化不含私密正文/凭据的 refusal/problem result。

删除本地 outbox 行只允许在相同本地事务中已持久化 acceptance receipt，或已持久化 refusal/problem result 后按显式本地保留策略清除无须再重试的终态元数据。网络超时、进程崩溃和 HTTP 响应丢失绝不授权删除 pending 行。

### 3.2 接受事务与崩溃矩阵

下表是所有领域共用的接受边界；实现可以增加内部步骤，但不可暴露中间态。

| 阶段 | 单一原子单元 | 崩溃后允许状态 |
|---|---|---|
| A. 本地排队 | intent、稳定 key/digest、origin sequence 与本地 optimistic 表示 | 完整旧本地态，或完整 pending 新态；不得有无 key 的 optimistic 项。 |
| B. Core 预检 | 在任何幂等 lookup 前校验 credential generation/scope、active epoch/fencing；其后校验 TTL、大小、全部幂等键 | 完整拒绝/过期旧态加可审计 refusal/problem result，或继续；不得有部分 batch 接受、canonical change/projection/sequence 或资源读取副作用。 |
| C. Core 接受 | 事实/event、acceptance receipt、全局/领域 change、idempotency ledger、必要 projection invalidation | 完整旧 Core 态，或完整 accepted 新态；同一批全收或全拒。拒绝不进入此单元。 |
| D. 响应传输 | accepted/duplicate 只传 acceptance receipt；拒绝/过期/待解决只传 refusal/problem result；均不传推进 cursor 的许可 | C 的任一完整态；丢 accepted 响应后，只有通过当前有效 precheck 的原 key 重试可返回原 acceptance receipt。 |
| E. 客户端确认 | acceptance receipt 或 refusal/problem result 与 outbox 转终态/移除资格 | 完整 pending 旧态，或完整终态新态；不得“已删 outbox、无持久 acceptance receipt 或 refusal/problem result”。 |
| F. 变更应用 | 经认证的 change/snapshot 投影与同领域 cursor | 完整旧投影+旧 cursor，或完整新投影+新 cursor；不得 cursor 超前投影。 |

P4 必须对 A–F 每一阶段注入崩溃、重启和重放；所有结果只能收敛到表中完整旧态或完整新态。特别禁止 ghost accepted、重复 event、acceptance-receipt-only 写入、outbox 删除先于持久 acceptance receipt/refusal result、旧 fencing 写入和“已推进 cursor 但未持久化内容”。

## 4. chat/activity 分离 cursor、watermark 与 resync

`chat` 与 `activity` 是独立的 change namespace，至少各自按 `(core_instance_id, epoch, domain, consumer installation)` 存储 cursor、ack、retained watermark 和 snapshot lineage。chat cursor 绝不能确认 activity，activity cursor 绝不能拉取 chat；activity write-only probe 更绝不能读取 chat 或任意私密 feed。

对某一领域的 `GET changes`：

1. 若 caller cursor 属于当前 lineage 且不早于 retained watermark，返回该领域增量与 opaque `next_cursor`。
2. 若 cursor 缺失、来自旧 lineage/epoch、认证失败或早于 retained watermark，返回 `resync_required`，包含领域、当前 Core/epoch、最小 snapshot capability、snapshot base watermark 和无私密的原因码；不得静默从“最新”继续或伪造连续历史。
3. `resync_required` 后客户端先验证 snapshot 的 Core identity、epoch、scope、schema/policy version、expiry 与 digest；只在一个本地事务内持久化 snapshot 投影、snapshot receipt/id、base watermark 和新 cursor。认证失败或崩溃时保留旧 cursor/投影并继续显示同步未完成。
4. snapshot 提交成功后才可 ack 新 cursor；后续增量从 snapshot base watermark 继续。snapshot 是当前态恢复包，不能伪装已保留的 raw history。

retained watermark 的前移必须可审计，至少留下领域、旧/新 watermark、清理策略版本、执行 receipt 和可供用户导出的最小元数据。它受活跃 device ack、合法保留期限、删除命令和灾难恢复策略共同约束；任一条件不清楚时宁可延缓清理，不得静默制造不可恢复缺口。

## 5. 删除、撤销、备份与物理清理

在线 revoke/delete 的顺序是硬约束：在同一权威事务中使 credential generation/subject tombstone 生效、阻断该 subject 的读写和重放、从在线 read summary/投影隔离并写 delete/revoke receipt；之后才异步物理清理 raw、projection、对象、索引、spool 与允许删除的备份副本。异步 job 必须有可追踪 job id、范围、开始/完成/失败/重试状态、删除证明或原因，且不暴露私密正文。

之后生成的备份 manifest 必须排除已删对象及已撤销 credential 可访问的内容。已生成的不可变/离线备份不能承诺即时物理抹除：它们必须携带公开的 retention/expiry policy 与版本，在到期时以可审计清理运行淘汰；恢复流程不得因旧备份而复活在线已删对象或已撤销凭据。若恢复映像含 tombstone，tombstone 优先；缺少可验证 tombstone/删除 ledger 时恢复必须停为 `needs_resolution`，不得默认复活。

MDA-0 的已确认保留语义在未来 activity 域中保持不变：raw event、device spool、BLE raw 与最小诊断默认 **1 天**；live heart-rate 只保存 **current fresh snapshot**，不得回填为历史；受约束的机器摘要/结论保留至用户删除。用户确认的结论走独立 User-truth 生命周期。现有 14 天 BLE JSONL 是待实现差距，不是本 ADR 授权的现状变更。

## 6. Core 不可用、灾难恢复与新 Core 接管

Windows Core 是唯一夜间接受者。它不可用时，远端的 activity/person state 是 `unknown`；客户端可保留边界明确的 pending 或 TTL 到期为 `expired`，但不能成为第二权威，也不能从 silence、no reply、heartbeat、network、Core health 或单个 HR 样本推断醒着、安静、休息或睡眠。`network_only` 只说明可达性；`quiet_observed` 仅可由新鲜连续 coverage 的无交互区间进入；live HR 必须新鲜且正值才是 current snapshot，永不单独推断健康/睡眠状态。

新 Core 接管是 Gate 1C 的真实恢复演练边界；本 Goal 只冻结防双活语义：恢复者必须取得新的 durable `core_instance_id`/epoch 和 fencing lineage，发布接管 receipt 与 change-feed epoch，轮换/撤销旧 credential generation，并以认证 snapshot 让客户端 resync。旧 Core、旧 worker、旧 credential/generation、旧 cursor、旧 snapshot 与积压 intent 返网时，必须在 idempotency lookup 前拒绝，不能写新 epoch，也不能获知 duplicate 或原 acceptance receipt。只有当前有效 identity + generation 且 active Core/epoch 已通过 fencing 的请求，才可按同 key+digest duplicate 返回原 acceptance receipt；其余冲突、过期、删除对象或旧 lineage 的 intent 只返回 `rejected` / `expired` / `needs_resolution` refusal/problem result。本 ADR 不声称已完成真实硬盘、S3、新电脑或四副本恢复。

## 7. P4 合成用例

P4 只可使用合成 fixtures 与临时目录，必须 `migrationExecuted=false`、可重复、无真实用户数据。至少覆盖：

1. chat 与 activity cursor/ack 隔离，activity write token 读取 chat 被拒。
2. pending 写入、Core 已接受但响应丢失、重试返回同 receipt/duplicate，且不重复 event。
3. outbox 满载、超大 payload、TTL 到期、401/409/协议不兼容；既有 pending 不丢，终态可核查。
4. A–F 各阶段 crash injection；只得到完整旧态或完整新态。
5. cursor 早于 retained watermark、旧 epoch cursor、损坏/未认证 snapshot 与 snapshot 落盘中断；均不推进 cursor，合法 snapshot 后原子恢复。
6. revoke/delete 后重放：先拒绝、在线隔离，再异步清理可追踪；新备份排除，旧不可变备份按公开 expiry。
7. MDA-0 1 天 raw/spool/diagnostics、fresh-only HR snapshot、长期可删结论；无 coverage/silence/heartbeat/network/single HR 始终不能生成 awake/quiet/sleep 结论。
8. 双 Core / 新 epoch 接管 / 旧 writer 或旧 token 返网 / 旧 snapshot 恢复；没有旧 fencing 写入、没有自动复活或第二权威。

## 8. 未决风险与退出条件

- 容量、TTL、重试、batch byte limit、snapshot 签名格式、watermark 前移与不可变备份的实际公开期限尚未定值；实施前必须版本化并纳入协议/隐私审阅。
- Core instance/epoch、credential generation、scope、fencing 的精确数据模型由 P2 统一词典决定；若冲突，返回 P2/P3，不得在实现中双定义。
- activity ingress 仍是 MDA-1 以后的能力；iPhone ingress 当前 `unsupported`。本 ADR 不批准 probe、token、collector、健康推断或通知。
- 真实灾难恢复、四副本和新电脑演练属于 Gate 1C；本 ADR 的合成故障证明不能替代真人 Gate。
