# 1A0-P3 Handoff — Outbox / Cursor / Retention / Recovery

> 工作包：`1A0-P3`；基线：`v3-lab@2edaf17a3f8bb733e6ac6f54024941267d7f32a4`。
>
> 范围：仅 Gate 1A-0 文档合同；未修改生产 Dart/Flutter/SQLite/schema/依赖、设备或外部配置，未读取真实用户数据，未创建 migration。

## 交付

- [`OUTBOX_CURSOR_RETENTION_RECOVERY_ADR.md`](../OUTBOX_CURSOR_RETENTION_RECOVERY_ADR.md)：冻结 client intent outbox、receipt、acceptance crash matrix、chat/activity 分离 cursor、watermark/resync、认证 snapshot、删除/备份和接管边界。
- 保留 MDA-0 已确认决策：Windows 唯一夜间 Core；其不可用时远端 `unknown`；raw event/device spool/BLE raw/minimal diagnostics 1 天；live HR 只 current fresh snapshot；安全机器摘要/结论保留至用户删除；禁止由 silence/no reply/heartbeat/network/single HR 推断人状态。

## 核心决定

1. 当前 Core API 0.1 的 chat cursor/ack 不被误写成 retained watermark、`resync_required`、activity ingress 或 epoch takeover 已实现；新增语义均标为目标合同。
2. 接受的最小原子单元是“事实/event + acceptance receipt + change + idempotency ledger + 必要 projection invalidation”；拒绝/过期/待解决仅返回 refusal/problem result，不生成 canonical change/projection/sequence。客户端只有在认证 snapshot/change 与 cursor 同事务落盘后才推进/ack cursor。
3. revoke/delete 先在线隔离与阻断重放，再异步物理清理；新备份排除，旧不可变备份按公开期限到期，缺 tombstone 的恢复停止为 `needs_resolution`。
4. 旧 credential/generation/Core/epoch 必须在幂等 lookup 前拒绝，不能获知 duplicate/receipt；只有当前有效 identity/generation + active Core/epoch fencing 后，同 key+digest 才可返回原 acceptance receipt。普通 domain receipt 不含泛化 workload fencing token；device/probe generation 与 worker workload fence 只在受保护 acceptance/audit proof 中校验/绑定。
5. Core 接管防双活是本 Goal 的合同冻结；真实磁盘/S3/新电脑/四副本演练仍属 Gate 1C，不能以 P3/P4 合成测试冒充通过。

## P4 接口

按 ADR 第 7 节建立合成 fixture/harness，特别核验 A–F 崩溃阶段、outbox 满载/TTL、watermark resync、snapshot 原子性、revoke replay、备份期限和旧 Core 返网。所有 harness 必须 `migrationExecuted=false`，使用临时目录和合成数据。

## 未决冲突 / 风险

- 容量/TTL/重试/批大小、snapshot 认证格式、水位清理条件和不可变备份实际期限尚未设定数值；不得自行实现默认值。
- 本次 W0 退回的 receipt/refusal、lookup 前拒绝与 workload-fence 泛化三项冲突已按 P1/P2 强制词典修订；epoch、core identity、credential generation、scope、fencing 的其余精确词典仍以 P2 审计版为准，发现新增不一致应退回 P2/P3 合同审计。
- 当前 activity ingress/iPhone webhook 仍 `unsupported`；本文不授权任何 collector、token、schema 或外部配置。

## 验证与主窗下一动作

- 已检查相对 Markdown 链接目标均在仓库路径内；待 W0 与 P1/P2 交叉审计术语冲突。
- 已运行 `git diff --check --` 于两份拥有文件；预期必须为零输出/零退出。
- W0：复核 P2 的 epoch/fencing 名词与本 ADR 一致后，派发 P4 仅按第 7 节写合成用例；随后运行链接、diff、隐私/越权与禁止范围审计，再交 Lynx 真人审阅。
