# Gate 1A-0 — W0 旧自动证据包（独立终审已撤回）

> Goal：[`GOAL-20260830-gate1a0-authority-recovery`](../../goals/GOAL-20260830-gate1a0-authority-recovery.md)
> 基线：`v3-lab@2edaf17a3f8bb733e6ac6f54024941267d7f32a4`
> 执行分支：`codex/gate1a0-authority-recovery`
> 当前状态：候选提交 `eadf1c2c` / `a1b97319` 已被独立终审否决；本文不是当前真人审阅包。Goal 已返回返修，未 push、未发布。

> 2026-08-30 独立终审发现：Product Roadmap 1A-0 的物理 schema、Markdown/RichText、跨介质 commit/recovery 与 migration harness 尚未闭合；现有 P4 也可由 case 错配和结论式 crash input 假绿。下方自动结果仅保留历史证据，不得据此请 Lynx 通过。

## 1. 本次真正冻结了什么

- [`Authority Root and Acceptance ADR`](AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md)：Windows desktop Core 是目标唯一 acceptance root；11 类对象逐项定义 authority、accepted writer、pre-accept、receipt/change、delete owner、recovery source 与拒绝边界。
- [`Core Identity / Epoch / Fencing ADR`](CORE_IDENTITY_EPOCH_FENCING_ADR.md)：Core instance、installation、probe、worker 与 credential generation 分离；旧 identity/epoch/fence 在幂等和资源读取前拒绝。
- [`Outbox / Cursor / Retention / Recovery ADR`](OUTBOX_CURSOR_RETENTION_RECOVERY_ADR.md)：acceptance receipt 与 refusal result 分离；chat/activity cursor 分离；watermark resync、认证 snapshot、删除隔离、备份到期与接管边界闭合。
- [`Baseline and Contract Delta`](BASELINE_AND_CONTRACT_DELTA.md)：明确哪些是当前 runtime、哪些只是目标合同；现有 single-Core worker lease 不冒充跨 Core fencing，activity ingress 仍 unsupported。
- [`P4 synthetic harness handoff`](handoffs/P4_SYNTHETIC_HARNESS_HANDOFF.md)：47 条显式状态用例只做 validate/simulate，不执行 migration。

本 Goal 没有切换生产 writer、改变 schema、连接真实数据库/Vault/附件、配置设备/Tailscale/计划任务，也没有实现 activity ingress、推断、通知、来电或主动介入。

## 2. 自动 Gate 证据

| Gate | 结果 |
|---|---|
| P1–P3 词典交叉审计 | 首轮发现 P3 三处冲突并退回；修订后 `receipt/refusal`、旧 epoch 先于幂等、workload fence 作用域一致。 |
| P4 主窗代码审计 | 首版因 `_simulate()` 回显 `expected` 被拒收；第二次仍有 fallback，主窗接管后移除。47 条 fixture 现均有显式 `input`，规则引擎不读取 `expected`。 |
| 新 harness 专项 | `dart analyze` 无问题；6 个测试组通过，包含篡改 expected、改变 active Core 输入、manifest/文件/corpus/path/link fail-closed。 |
| 与旧 preflight 组合回归 | 13 个测试组全部通过。 |
| CLI 确定性 | 两次均 47/47、12,302 bytes；SHA-256 均为 `C25AA50191262C21470021627076CC4F4F331BBA0293311DA1C2FE52A33D88B4`。 |
| 报告边界 | `synthetic=true`、`mode=validate/simulate-only`、`migrationExecuted=false`；不含 fixture 输入、secret/lease token。 |
| 文档/范围 | 11 类矩阵恰为 11 行；47/47 fixture 显式输入；10 份 Gate Markdown 链接目标存在；17 个变更路径均在白名单；无生产 import；尾随空白与 `git diff --check` 通过。 |
| Flutter runner | `flutter test` 曾连续无输出并被终止，不能写成通过；同一 `package:test` 文件已由 Dart test runner明确执行通过。 |

## 3. 真人审阅的三条时间线

### A. 正常接受

1. Desktop/Android/probe 只能建立 `pending` intent。
2. 当前 active Windows Core 依次校验 credential generation、binding/scope、Core instance/epoch/fence，再查幂等与资源。
3. 只有原子提交 canonical change 后才产生 acceptance receipt；投影、索引、缓存和备份不能另立 writer。
4. 普通 chat 与 activity 永不自动生成 User-truth。

### B. Core 不可用

1. 客户端保留有界 pending，或按 Core 权威时钟到期为 `expired`。
2. 本地 optimistic、outbox、probe spool、网络/Tailscale/heartbeat 都不能变成 accepted。
3. 远端人态为 `unknown`；silence、no reply、单一 HR 不得推断 awake、quiet 或 sleep。

### C. 新 Core 接管与旧 writer 返网

1. 新 Core 必须先验证 authority recovery lineage，再新建 instance、提升持久 epoch 并生成 transition receipt。
2. 旧 Core、旧 worker lease、旧 credential generation、旧 cursor/snapshot 在幂等 lookup 前失败；不能靠旧 key 获知 duplicate/receipt。
3. 旧积压 intent 不自动改 epoch；只能 reject 或进入不产生 acceptance mutation 的 `needs_resolution`。
4. 删除先在线隔离并留下 receipt，再异步物理清理；新备份排除，旧不可变备份按公开期限到期，恢复时 tombstone 优先。

## 4. MDA-0 决策核对

- Windows 是唯一夜间活动 Core；睡眠、关机、注销或不可达时远端为 `unknown`。
- iPhone 保留 Tailscale 方向，但 activity ingress 当前仍 `unsupported`。
- raw event、device spool、BLE raw 与最小诊断目标保留均为 1 天；当前 BLE 14 天是待实现差距。
- live HR 只保留 current fresh snapshot；安全机器摘要/结论保留至用户删除。
- 不采集窗口/App 原名、按键、URL、屏幕、通知或聊天正文；不由 network/Core health/heartbeat/silence/no reply/single HR 推断人态。

## 5. 需要 Lynx 作出的决定

- **通过**：确认上述 authority、接管、resync、删除与 MDA 边界可作为后续实施合同。主窗随后只完成本 Goal 的本地收口；不会自动创建 MDA-1，也不会 push。
- **返修**：指出具体时间线或词典项；Goal 保持活动并只返修该边界。

自动结果不能代替这个决定。当前不构建产品候选，因为本 Goal 没有生产运行改动。
