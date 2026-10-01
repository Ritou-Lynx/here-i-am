# Gate 1A-0 — W0 修复后自动证据与真人审阅包

> Goal：[`GOAL-20260830-gate1a0-authority-recovery`](../../goals/GOAL-20260830-gate1a0-authority-recovery.md)
> 精确基线：`v3-lab@2edaf17a3f8bb733e6ac6f54024941267d7f32a4`
> 执行分支：`codex/gate1a0-authority-recovery`
> 审计状态：第八名全新独立 Sol 终审 `PASS`，未发现 P0/P1/P2
> 合同 / harness 本地候选提交：`8797adf84feca2610a9f348fcd040f7299d6ea4a`；未 push、未发布
> 控制面：候选之后只用 metadata-only 提交记录审阅与收口，不改变候选合同、fixture、harness或测试
> 真人 Gate：2026-08-30，Lynx 明确回复“通过”；A–E 五条时间线整体接受

旧 [`W0_AUTOMATIC_AND_HUMAN_GATE.md`](W0_AUTOMATIC_AND_HUMAN_GATE.md)、`eadf1c2c` 和
`a1b97319` 都是已撤回历史，不是本次验收输入。本文承载 Lynx 对 Gate 1A-0 目标合同的
审阅依据与最终结论；它不声称生产 writer、schema、SQLite、filesystem、设备或备份系统已经切换。

## 1. 本次冻结的合同

- [`Authority Root and Acceptance ADR`](AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md)：目标唯一 acceptance root、11 类对象的 accepted writer、pre-accept、receipt/change、delete owner 与 recovery source。
- [`Core Identity / Epoch / Fencing ADR`](CORE_IDENTITY_EPOCH_FENCING_ADR.md)：Core instance、installation、credential generation、probe lineage、worker fence 与旧 writer 返网顺序。
- [`Outbox / Cursor / Retention / Recovery ADR`](OUTBOX_CURSOR_RETENTION_RECOVERY_ADR.md)：outbox、acceptance receipt / refusal、cursor、retained watermark、认证 snapshot、删除与备份到期。
- [`Physical Schema / Markdown Dataflow ADR`](PHYSICAL_SCHEMA_AND_MARKDOWN_DATAFLOW_ADR.md)：中性 Card / User-truth 目标物理结构与 Markdown 唯一正文权威；RichText 只是可重建编辑缓存或可逆兼容 capsule。
- [`Formal Migration Matrix`](FORMAL_MIGRATION_MATRIX.md)：32 类对象的唯一九字段 exact literal；身份映射、引用、rollback、delete/recovery、index/backup逐行冻结。
- [`Cross-medium Commit / Recovery ADR`](CROSS_MEDIUM_COMMIT_RECOVERY_ADR.md)：Markdown、Source/object、operation log、SQLite、FTS/投影、Receipt 的 journal、commit、crash recovery 与旧→新→旧→新协议。

## 2. 自动 Gate 与独立终审证据

| Gate | 当前结果 |
|---|---|
| Format | 3 个目标 Dart 文件，`0 changed`。 |
| Analyze | 主窗 `dart analyze`：`No issues found!`。第八审独立进程在 Analysis Server shutdown 时因本机 Dart perf 文件清理失败，未冒充独立 analyze 通过；该环境异常没有代码 finding。 |
| Harness 专项 | `20/20`。 |
| 旧 preflight + 新 harness 组合 | `27/27`。 |
| Canonical report | `202/202`；`allInvariantsHeld=true`；`allSixRoundTripDomainsHeld=true`。 |
| Crash / failure | 52 个 crash case / 52 unique；26 个 failure case / 25 unique token。 |
| 双 CLI 确定性 | 两个全新 system-temp 空目录均输出 1,409,842 bytes；SHA-256 均为 `7E868CDDD330AE92A112A23405D6156EC006D294773FE3BD8741DD83739D78A3`，逐 byte 相同。 |
| Migration 边界 | `migrationSimulated=true`、`migrationExecuted=false`；只证明 synthetic validate/simulate。 |
| Formal32 | Markdown exact JSON 与 report 32 行 canonical equality；九个顶层 key、每个 identity entry 七 key；逐行 digest与特殊语义负控均红。 |
| Crash fail-closed | trace、boundary、原始 initial ledgers、完整 durable state 相互绑定；52 个错误 boundary 整态替换、ghost bundle、publish/fsync 成对篡改均为 `needs_resolution`。 |
| Malformed durable state | 缺字段、错类型、坏元素、extra/空/超长 ledger 值安全返回 `needs_resolution`；非法 input ledger明确 `inputRejected`，不抛 `TypeError`。 |
| 六域 roundtrip | Card、User-truth、Source/Anchor、operation、revision、derived index 各十字段；真实引用闭合；baseline/first 无未来 operation，post-cutover/rollback/remigration 保留新 operation。 |
| 范围 / 链接 / 隐私 | 生成本文前为 23 条批准路径；新增本文后仍只增加 Gate 目录内 1 条批准路径。生产 `lib/`、平台、schema、依赖、generated、device/config 为 0；changed Markdown 相对链接、secret/真实用户数据、`git diff --check` 均通过。 |

第八审还重新核证：raw HTML 使用真实非 UTF-8 bytes `FF FE 3C 00 41 80` 的
base64/length/SHA/bytewise 链路；failure token 从 raw facts 推导；snapshot unchanged 与原
cursor/state 比较；20 种 operation 都有 actual-state 负控；fixture、scenario 与 202 个 input
digest 均被 pin。

## 3. Lynx 真人核对时间线

### A. 正常写入

1. Desktop、Android 或 probe 只能提交带稳定幂等 key 的 intent；本地状态至多是 `pending`。
2. active Windows Core 在资源读取和幂等 lookup 前先校验 credential generation、binding/scope、Core instance、epoch 与 fence。
3. 只有 Core 原子提交 canonical domain change 后，才签发 acceptance receipt/change；Markdown、SQLite projection、FTS、缓存、客户端或备份都不能另立 writer。
4. 普通 chat 与 activity 不自动生成 User-truth；User-truth 仍需显式记录、修正或受权外部数据路径。

### B. Core 不可用

1. 客户端只保留有界 pending，或按 Core 权威时钟得到 `expired / rejected / unknown`。
2. optimistic UI、outbox、probe spool、网络、Tailscale、heartbeat 或 worker lease 都不是 acceptance。
3. Windows Core 不可用时，人态保持 `unknown`；silence、no reply、单一心率或 Core health 不得推断 awake、quiet 或 sleep。

### C. 新 Core 接管与旧 writer 返网

1. 新 Core 先验证 authority recovery lineage，再创建新 instance、持久提升 epoch并签发 transition receipt。
2. 旧 Core、旧 worker fence、旧 credential generation、旧 snapshot/cursor 在幂等 lookup 和资源读取前失败；旧 writer不能靠旧 key探知或复活新 epoch状态。
3. 旧积压 intent 不自动换 epoch；只能拒绝，或进入不产生 acceptance mutation 的 `needs_resolution`。

### D. Watermark resync

1. cursor 落后 retained watermark 时必须显式返回 `resync_required`，不能伪造连续增量。
2. 客户端验证 snapshot 的身份、epoch、watermark、digest 与引用闭包，并原子持久化完整 snapshot 后，才推进 cursor。
3. 旧 snapshot、错误 epoch、损坏 digest或未闭合引用都不能覆盖本地已接受状态。

### E. 删除与恢复

1. 删除先由 Core 接受 tombstone/delete operation，在线读面立即隔离；异步物理清理可追踪但不是新的 truth writer。
2. 新备份不再包含已删除对象；旧不可变历史按已公开期限到期；恢复时 tombstone barrier优先，不能因旧备份重建已删对象。
3. cache/index 可物理删除并从 accepted authority重建；不可重建的权威对象必须保留对应恢复源和稳定身份。

## 4. MDA-0 决策保持不变

- Windows 是唯一夜间活动 Core；睡眠、关机、注销或不可达时远端为 `unknown`。
- iPhone 保留 Tailscale 方向，但 activity ingress 当前仍是 `unsupported`。
- raw event、device spool、BLE raw 与最小诊断的目标保留为 1 天；当前 BLE 14 天是后续实现差距。
- live HR 只保留 current fresh snapshot；安全机器摘要/结论保留至用户删除。
- 不采集窗口/App 原名、按键、URL、屏幕、通知或聊天正文；不由网络/Core health/heartbeat/silence/no reply/single HR 推断人态。

## 5. 真人决定

- **通过**：确认 A–E 时间线、Formal32、单写者、resync、删除/恢复与 MDA-0 边界可作为后续实现合同。主窗随后只关闭本 Goal；不会自动创建 MDA-1，也不会 push。
- **返修**：指出具体时间线、对象或字段；Goal 保持活动，只返修该边界。

自动 Gate 与第八审 PASS 不能代替 Lynx 的决定。本 Goal没有生产运行改动，因此不构建或安装产品候选。

## 6. 真人 Gate 结果

- 2026-08-30，Lynx 对本审阅包明确回复“通过”。
- 通过范围：A 正常写入、B Core 不可用、C 新 Core 接管与旧 writer 返网、D watermark resync、E 删除与恢复，以及 Formal32、单写者和 MDA-0 保留边界。
- 结论：Gate 1A-0 目标合同真人 Gate `PASS`，本 Goal 可关闭。
- 此结论不表示生产 writer、schema、SQLite、filesystem、设备、网络或备份系统已经迁移、构建、安装或发布；后续实现必须另行提出并确认 Goal。
- 未授权 push、发布或创建 MDA-1；主窗在记录本结果后停止。
