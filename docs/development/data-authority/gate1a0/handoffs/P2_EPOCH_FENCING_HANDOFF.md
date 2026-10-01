# 1A0-P2 handoff — 身份、epoch/fencing 与旧 writer 返网

> **状态：已交付，等待 W0 审计。**
>
> **范围：** 仅冻结 Gate 1A-0 的目标合同；没有生产代码、schema、迁移、设备或外部配置变更。

## 结论

已冻结跨 Core authority fencing 的最小合同：Core instance、device installation、probe lineage、worker holder 与 credential generation 不能互相代替；持久化 authority registration 的 active instance/epoch 是唯一接受根。验证顺序强制为 credential/revoke/scope/epoch-fencing 先于 idempotency 与资源读取，因此旧 Core、旧 worker、旧 token、旧 epoch 和 revoked probe 既不能写入，也不能以 `duplicate` 探测原 receipt。

现有 iCore worker lease/fencing 仍只证明**单一 Core 内**一个 workload 的单执行。它不提供多 Core 选主、灾难接管或旧 writer 返网隔离；这一事实已在 ADR 明确保留，并由 Gate 1A-3 承担实现。

## 交付物

- [Core identity epoch fencing ADR](../CORE_IDENTITY_EPOCH_FENCING_ADR.md)：身份词典、registration、credential/revoke/re-pair、校验顺序、takeover、返网隔离、1A-3/1C 关系与 P4 用例。

## 关键审计点

1. `authority_epoch` 是 authority registration 的持久化单调代际；它不是 worker fencing token、cursor 或客户端时钟。
2. `core_instance_id` 每次恢复/接管新生；旧 instance 被 supersede 后无法借本地 lease 或旧 DB 重新写入。
3. re-pair 同一 installation 必须原子提升 credential generation 且立即失效旧 token；probe 是最小 write-only lineage scope，不能继承 chat/read/admin。
4. stale/revoked/auth binding/epoch/fence 全部在 idempotency lookup 前失败；`duplicate` 仅对当前有效身份、epoch 与 canonical digest 允许。
5. 新 epoch 中的旧 backlog 默认 `reject` 或 `needs_resolution`，绝不自动改 epoch/自动 accepted。`needs_resolution` 不产生 receipt、projection 或下游副作用。

## 供 P4 采用的合成用例

ADR 第 8 节给出 11 个命名用例及预期错误和零 mutation 断言。P4 至少覆盖：双 Core takeover、旧 epoch 先于幂等、revoke/re-pair 重放、跨设备冒充、旧 worker lease 跨 epoch、同 Core workload stale fence、积压 intent `needs_resolution`、不同 digest 冲突和恢复 lineage 不足。

P4 必须保持合成 ID、固定时钟、临时目录、确定性输出与 `migrationExecuted=false`；不得读取真实用户数据或连接生产 iCore/SQLite/Vault。

## 未决风险 / 必须保持红灯

- authority registration/epoch ledger 的具体生产 schema、事务和恢复介质尚未设计；不允许借此 ADR 创建 migration。
- key custody、credential 签发/轮换实现、Core health/snapshot 的签名与客户端持久化方式由 1A-3 明确。
- Gate 1C 的备份和恢复演练是本合同的证据依赖，不把 backup 文件自动等同 active Core 授权。
- offline intent 的人工 reconciliation policy 与 UI 仍未选定；安全默认只能 reject / `needs_resolution`。
- P1 的对象接受矩阵与 P3 的 outbox/cursor/删除恢复合同必须与本 ADR 交叉审计；出现词典冲突应退回相应工作包，不在 W0 静默改写第二份合同。

## 验证记录

- 已以 [Core API v0](../../../../companion-first/CORE_API_V0.md#L70-L100) 复核当前 worker lease 的单 Core 边界。
- 已以 [Device Activity ADR](../../../activity/mda0/DEVICE_ACTIVITY_V1_ADR.md#L13-L20) 和 [MDA-0 retention/topology](../../../activity/mda0/RETENTION_DELETION_AND_TOPOLOGY.md#L83-L91) 复核 activity ingress 与恢复/删除边界。
- 待 W0：检查相对链接、运行 `git diff --check --` 两个拥有路径，并与 P1/P3 词典交叉审计。

## 主窗下一动作

W0 先确认 P1 的 authority/object matrix 未把 worker lease 写成跨 Core 防护，再把本 ADR 第 8 节的命名用例交给 P4；P4 只在 P1–P3 审计词典一致后实现合成 harness。
