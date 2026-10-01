# Gate 1A-0 基线与合同差异清单

> Goal：[`GOAL-20260830-gate1a0-authority-recovery`](../../goals/GOAL-20260830-gate1a0-authority-recovery.md)
> 精确基线：`v3-lab@2edaf17a3f8bb733e6ac6f54024941267d7f32a4`
> 状态：P0 控制面输入；只描述事实与待冻结合同，不改变生产运行权威。

## 1. 证据层级

1. **当前运行事实**：可由基线代码、[`CORE_API_V0`](../../../companion-first/CORE_API_V0.md) 或 [`A1_CURRENT_AUTHORITY_INVENTORY`](../../data-authority-preflight/A1_CURRENT_AUTHORITY_INVENTORY.md) 直接证明。
2. **已确认产品决策**：Lynx 已在 MDA-0 真人 Gate 选择，但仍不等于已实现；来源是 [`RETENTION_DELETION_AND_TOPOLOGY`](../../activity/mda0/RETENTION_DELETION_AND_TOPOLOGY.md) 与 [`DEVICE_ACTIVITY_V1_ADR`](../../activity/mda0/DEVICE_ACTIVITY_V1_ADR.md)。
3. **Gate 1A-0 目标合同**：本 Goal 要冻结并用合成 harness 验证的语义；在后续实施 Gate 完成前不得写成 runtime capability。
4. **未知或 blocked**：没有代码、迁移或真实恢复证据；必须保留红灯，不能由文档推断补齐。

## 2. 当前事实与目标合同

| 议题 | 基线可证明的当前事实 | Gate 1A-0 要冻结的目标合同 | 实施/真人证据归属 |
|---|---|---|---|
| Authority Root | 当前对象仍分散在本机 SQLite、文件或服务专属表；Core API v0 只明确聊天同步 authority。 | Windows Core/desktop 是唯一权威根；客户端、probe 与 worker 只提交 intent 或生成候选，不能分配 accepted identity/receipt。 | 1A-1/1A-2/1A-3 与后续领域 Gate；本 Goal不切换运行权威。 |
| Chat | v0 支持配对、用户消息提交、change feed、ack；Core 分配 `server_sequence`。 | chat 有独立接受流、outbox、receipt、cursor 与恢复规则；activity/User-truth 不能借 chat 权限或 cursor。 | 1A-2 客户端同步、1A-3 安装身份。 |
| Worker 单执行 | 现有 lease 只处理**同一权威 Core 进程内** workload holder；v0 明确不包含多 Core 选主。 | 持久 Core instance + authority epoch + fencing；提升新 Core 后，旧 Core/holder/token/intent 返网都不能改变新 epoch。 | Gate 1C 实现与灾难恢复真人 Gate；不能拿现有 lease 代替。 |
| Device identity | v0 有 installation 配对、token 轮换与逻辑设备语义。 | device installation、probe lineage、worker holder、credential generation 与 scope 分离；撤销/重配对先于幂等和资源读取判定。 | 1A-3；activity probe 另在 MDA-1 后续 Gate。 |
| Cursor/resync | chat cursor 是不透明增量位置，ack 不控制是否可重读；当前没有 retained watermark。 | chat/activity cursor 分离；cursor 落后 retained watermark 返回 `resync_required`；仅在认证 snapshot 原子持久化后推进。 | 1A-2 与未来 activity ingress；本 Goal只做合成验证。 |
| Outbox | Core Sync Inventory 把离线 outbox 列为客户端持有；容量、TTL、过期、满载与冲突合同未闭合。 | 固定状态机、容量/TTL/满载、双幂等键、accepted 的 acceptance receipt 与拒绝/`needs_resolution` 的 refusal result；Core 不可用时不得伪造 accepted。 | 1A-2/1A-3；activity spool 后续另行实现。 |
| Activity | 当前 iCore 无 activity ingress、probe scope、activity projection/snapshot/delete API。 | Core 是唯一 activity accepted writer；probe write-only；Windows 不可用时远端 `unknown`；网络、heartbeat、silence、no reply、单 HR 都不作人态推断。 | MDA-1 只能在本 Goal 后另行提出；不得在此 Goal偷渡。 |
| Retention | 当前 BLE JSONL 为 14 天；没有统一 Core activity retention。 | raw event、device spool、BLE raw、最小诊断各 1 天；live HR 仅 current fresh snapshot；安全摘要/结论保留至用户删除。 | MDA-1 实现/真机；现有 14 天是明确迁移差距。 |
| Delete/backup | 各领域删除、恢复、回收站与对象级备份大量为 unknown；不可变备份即时物理删除无证据。 | 在线 revoke/delete 立即隔离；异步物理清理有 receipt；新备份排除；旧不可变历史按公开到期淘汰。 | 1A-1 与 Gate 1C 真实恢复/到期报告。 |
| Atomic acceptance | 既有领域各自事务边界不同，跨介质与统一 receipt 没有总合同。 | 任一崩溃点只能得到完整旧 accepted state 或完整新 accepted state；禁止 ghost accepted、重复 event、孤立 receipt、旧 fencing 写入。 | 本 Goal P4 合成 harness先固定语义；生产故障注入归实施 Gate。 |

## 3. 对象覆盖路由

| 对象/领域 | 当前事实输入 | 本 Goal必须给出的分类 | 当前红灯 |
|---|---|---|---|
| Card | `memory_cards` + `whiteboard_card_extras` 拆分表示 | 中性 Card 权威、accepted writer、revision/投影/删除/恢复 | 普通 Card 当前可能落入 `user_truth`；物理迁移方案未选。 |
| User-truth / Memory Card | `RecordOrganizerServiceV3` 显式写入；Memory V3 表 | 显式 promotion/record 才可接受；chat/activity 不自动写入 | 回收站、备份与跨端接受尚未闭合。 |
| Source / SourceVersion / Anchor | Source/Version Drift 元数据与 `objectRef`；Anchor 嵌入 Card presentation | 原件、不可变版本、selector 与 Card 展示的权威边界 | 跨介质提交、恢复、Anchor 迁移 blocked。 |
| Evidence | 没有独立生产 `EvidenceClaim` 表 | Source 不等于 Evidence；Evidence 不等于 User-truth；目标只可声明未来 accepted writer | schema 与生命周期 blocked，归 Gate 2。 |
| Dreaming | 独立 Fragment/Episode/Saga；关系记忆，非 User-truth | 保持独立域与显式跨域 promotion | 恢复/备份 unknown。 |
| TaskArtifact | TaskRoom 独立表与服务 | artifact 不是 Card/Source/User-truth；promotion 需明确接受操作 | archive restore、备份 unknown。 |
| Capture / ImportCandidate / Link Inbox Item | Authority Preflight 已盘点现有暂存/候选入口 | 必须保持 pre-accept；只有权威接受操作可晋升 | 不能把采集成功、解析成功或索引命中当 accepted。 |
| chat | Core API v0 | 独立 accepted stream 与 device cursor | 多 Core fencing、retention resync 未实现。 |
| activity | MDA-0 proposed/confirmed input | 独立 write-only probe 与 activity cursor/snapshot | 整个 ingress/runtime 仍 unsupported。 |

P1 必须为上表每一行补齐 authority、accepted writer、pre-accept、receipt/change、delete owner 与 recovery source；没有“其他”兜底分类。

## 4. MDA-0 输入与版本化边界

- 基线内已版本化的 MDA-0 Goal、6 份活动合同文档与 5 个 JSON fixture 是本 Goal 可引用的受控输入。
- `D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md` 在本 Goal 创建时只存在于主工作区的未跟踪文件，**不在精确 Git 基线内**。本 Goal不得把它当权威来源，也不得从另一个工作树拷入后静默纳入。
- 本 Goal 以基线内 MDA-0 文档中的已确认决策为准。若后续确需纳入该 Roadmap，必须单独审计来源、与 `PRODUCT_ROADMAP.md` 的重叠及版本化归属，再由 Lynx 明确确认。

## 5. Gate 之间的硬边界

- **本 Goal（1A-0）**：设计与合成验证；无生产 migration、权威切换、设备或外部配置。
- **1A-1**：落地中性 Card catalog、User-truth 独立关系、Record Organizer 兼容与旧调用者适配；必须消费本 Goal正式 schema/迁移矩阵。
- **1A-2**：实施可逆 Markdown Vault 切换、外部编辑最小安全、历史/索引一致性与旧→新→旧→新无损往返；不得自行另立正文权威或 commit/recovery 语义。
- **1A-3**：实施 Core intent、唯一 accepted writer、outbox/cursor、installation identity、credential generation、epoch/fencing、重配对与旧 writer 拒绝；必须消费本 Goal P1–P3 合同。
- **Gate 1B**：来源、Evidence、检索与 promotion；不得把搜索命中自动升格。
- **Gate 1C**：持续运行、worker lease、备份与灾难恢复；必须提供真实旧 writer 返网和备份到期证据。
- **MDA-1**：activity ingress/fixtures/设备管线的后续候选；Gate 1A-0 通过后也只能另行提出，不自动创建。

## 6. P0 结论

精确基线能证明“现有聊天 Core API、单 Core worker lease、分散对象存储与大量恢复 unknown”，不能证明“统一 authority root、跨 Core epoch/fencing、activity ingress、retained watermark、统一 delete receipt 或灾难恢复”。后续 ADR 与 harness 的所有绿色结果都只代表合同闭合，直到对应实施与真人 Gate完成前仍不得宣传为生产能力。
