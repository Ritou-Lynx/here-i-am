# MDA-2 A2 — Android 持久队列与恢复权威

> 2026-09-13；W0 task `01a0917d-17fa-7bf3-a282-fd4c551d93b2`。
> 当前接续基线：`v3-lab@b55386cfc896c98376a071009f349dcbc88dc84b`。
> 本包只形成本地、可复核的持久 outbox 候选；不接入 Android 系统事件，不修改设备或运行态。
> 独立任务：`01a09933-d22f-7b53-9144-395a7a7ae6e8`，host `local`；Worktree `C:/Users/ExampleUser/.codex/worktrees/9a29/memex`；分支 `codex/mda2-a2-android-durable-20260913`；创建回执 `client-new-thread:3cdc2833-eed2-4ca8-9e1c-e2ee6bd401f3`。实际 rollout 已核实为 `gpt-5.6-sol / high`。`01a09933-96e1-72c3-bd09-90e8088d9580` 是创建动作的自动审批审计，不是worker task。

## W0 回收状态

- 首个固定提交 `7d0494436d55578d6388b12e69080a7741e4dc9d` 的范围审计通过：父项为 `b55386cf`，仅新增 12 个拥有路径，没有修改共享 Core、Android/Manifest、依赖、DI/UI 或全局状态文件。
- W0 独立语义审计发现 stale-owner 接管存在 TOCTOU：恢复者释放旧 lease 后才递归删除 owner 目录，旧 authority 可删除另一恢复者刚创建的新 owner。该问题违反“只替换精确 stale owner”的恢复契约，因此此提交不进入复跑与本地集成。
- 已将原任务退修，要求用稳定 OS 锁句柄覆盖二次 owner/anchor 核对与 owner 替换，并新增确定性双恢复者竞态负例。修订提交仍须经 W0 固定字节、范围审计和完整独立复跑后才能决定集成。
- `SOURCE_MANIFEST.json` 中共享 `activity_control_plane.test.mjs` 的首版 SHA 是 CRLF 工作区字节；其 Git LF blob 未变。修订收据必须分开标记两种口径，避免把工作区哈希误称为 Git 原始字节哈希。
- R1 提交 `47adfbf69baecea40e60bbeb8c8659ed4af32b1b` 关闭了双恢复者 TOCTOU；W0 在 Git 导出的干净副本独立复跑 A1 `56/56`、A2 `28/28`、双目录 analyze 和 wire/Core `20/20` 均通过。但 `_removeOwnLock` 删除 `owner.json` 抛错时未用 `finally` 释放 gate，关闭及 create/open 清理可遗留活锁。该 P1 继续阻断集成，已退回原任务补确定性删除故障测试和最小 R2 修复。
- 最终 R2 `ae9bfea023776e28b835633d74053194debf9b5c` 用 `finally` 无条件释放 gate，删除失败保留可核对 owner、poison 旧实例并要求精确 authority；close/open 两项故障注入已覆盖。W0 最终干净导出复跑 A1 `56/56`、A2 `30/30`、双 analyze 与 wire/Core `20/20` 全部通过，独立范围和语义复核无 P0/P1/P2，接受为可选择性本地集成的合成候选。A3 仍未授权。

## 路由裁决

原 A1 task `01a09464-0249-7f01-88d6-2b8067553ecd` 位于 `aa86/memex`，仍是基线 `1b6a2961` 上的八个未提交新增文件，尚未进入主线。A1-R1 的纯 Dart 归一化、每 source 独立 binding/sequence、不可变事件字节、冻结语义和 56 个合成用例可作为受审输入；其内存 ownership-transfer snapshot 明确不是磁盘持久化或生产恢复。

因此本阶段拆成两个串行包：

1. **A2（本包）**：导入并重新绑定 A1-R1，完成持久 outbox、恢复权威、并发 owner/fence 和可注入 sender 边界；只做本地文件/合成 Core 验证。
2. **A3（后续，未授权/未派发）**：在 A2 通过主窗验收并选择性集成后，才规划 Kotlin 平台采集、Channel/Manifest、真实权限与短场景设备 Gate。

现有 `PhoneUsageChannelHandler.kt` 查询聚合包名和应用名，不能作为 A2 输入，也不能绕过隐私边界复用。W3 的不可变字节、fence、退出证明原则可供审查；其 Node/Windows 存储、DPAPI、进程与 Job 实现不移植到 Android，也不继承其保护结论。

## 接受输入与固定边界

- 唯一 wire 仍是现有 `device.activity.v1` / `schema_version: 1`，由当前主线 `tools/i_core/activity_control_plane.mjs` 验证；不新增 endpoint、wire kind、响应 schema 或第二套 validator。
- C2 CR-01-A 至 E 保持已接受：never_sent 与 attempted_unknown 分开；原采集年龄最多 24 小时；每 source 独立配对/lineage；缺少恢复权威时冻结；手机含义保持 unknown，不把网络或队列状态冒充活动。
- 每个合法逻辑事件只材料化一次完整 JSON 字节。持久化、重试、进程重建和回执丢失不得重造时间、序号、ID 或 payload。
- A2 的私有持久 record 可以有本地版本，但只能包裹固定 wire bytes 与最少恢复元数据；它不是共享协议。
- A1 测试常量不提升为生产 SLO、容量、TTL 或保留政策。需要参数时保持可注入，并在交接中逐项标明测试值。

## 拥有路径

独立任务只写：

- `lib/data/services/activity/mda2_android/**`
- `test/data/services/activity/mda2_android/**`
- `docs/development/activity/mda2/android/a2/**`

从冻结 A1 逐文件导入前先记录八个交付路径及 SHA；不得修改 `aa86` 原树。共享 Core/validator、数据库 schema、根依赖、`android/**`、Manifest、ChannelRegistrar、PhoneUsageChannelHandler、DI、UI、BLE、前台服务及全局状态文档均不在 worker 拥有范围。发现必须改共享文件时，只提交变更请求给 W0，不自行扩大。

## 实现闭环

1. **持久存储接口与实现**：定义注入式 `ActivityOutboxStore`；每 source 独立保存 binding/lineage、下一序号、固定事件字节、原采集年龄证明、attempt/receipt/freeze 和格式版本。写入须先验证、再原子提交；不允许半分配序号或队列记录。
2. **恢复权威**：进程重建保留相同 lineage、sequence 和 wire bytes。缺文件、损坏、未知版本、回滚快照、锁丢失、多个 owner、年龄证明无效或 binding 不一致时 fail closed；不得补号、转绑、重造或从自洽快照推断可信。
3. **发送与回执边界**：sender 只接受已固定字节；同一 source 单 owner 串行结算。丢回执/模糊异常保持 attempted_unknown；accepted/duplicate 和终态拒绝沿用 Core 含义。冻结发生时，已在途 attempt 只按实际回执结算，后续记录仍 pending 且不增加 attempt。
4. **容量与保留**：满载在分配新序号前拒绝并暴露 gap；原 raw 期限到达后停止放出并执行可证明的本地清理。没有可证明的物理删除能力时必须在支持矩阵标为未支持，不能仅删索引就称硬删除。
5. **隐私**：持久记录、sender 参数、错误和日志拒绝或不保存包名、应用名、窗口/正文、位置、BLE/健康 raw、客户端 `received_at_ms` 及任意额外 payload。日志只记录固定错误码和非敏感计数/状态。

## 必须通过的本地验收

- A1-R1 原 56 项语义保持，并新增持久化专项；所有拥有路径 `dart analyze --fatal-infos` 无问题。
- 原子 allocate/commit 各中断点：重开后只有完整前态或完整后态，不出现消耗序号但无记录、记录存在但序号未推进。
- 进程重建、同 source 双 owner 锁竞争、旧 owner 晚回执、重复发送、回执丢失、终态拒绝、冻结时 inflight 结算均按上方边界。
- TTL 精确边界、墙钟回退、原采集年龄 24 小时、容量满、raw 期限后不再放出；事件 bytes/seq/lineage 全程逐项比较。
- permission denied/revoked/recover、scope/capability/binding mismatch 后保持 unknown 与冻结；恢复不补造缺口期间活动。
- 损坏、截断、未知版本、回滚快照、交换 source 文件和伪造年龄证明全部拒绝；清理测试只作用于任务自建 scratch。
- A1 实际 Dart 序列化样例继续通过主线既有 validator 与全内存 `ActivityControlPlane`；不复制或修改 Core。测试前后固定共享输入和拥有源码 SHA。
- 独立源码/范围审计无未关闭 P1/P2；实际测试进程 exit0，任务创建的临时目录和锁均清理或明确保留证据。

## 明确不做

不读取真实 UsageEvents，不订阅屏幕广播，不请求或改变 UsageAccess，不运行 adb，不碰手机，不连接真实 Core/凭据/网络，不修改 Kotlin/Manifest/Channel/DI/UI/BLE/FGS，不构建或安装 APK，不启用调度/自启，不访问真实数据库，不部署、push 或开始一晚 Gate。A2 通过只表示本地持久队列候选可进入主窗验收。

## 回收与下一步

worker 必须提交独立 commit 和 `docs/development/activity/mda2/android/a2/HANDOFF.md`，列出基线、A1来源 SHA、实际 diff、测试命令/退出码、故障矩阵、保护能力与未支持项。W0固定 commit 后重新导出、复跑、独立审计，再决定是否选择性本地集成。

worker 不拥有三份全局状态文档。为得到可回收的独立提交，允许仅在该 worker 最终提交命令临时设置 `SKIP_PROJECT_STATE=1`，随后立即清除并在 handoff 记录；主窗后续若集成，仍必须正常更新项目状态并运行守门，不继承此例外。

A2 完成且合入后，W0才提出 A3 平台接线包：Kotlin UsageEvents/屏幕信号、权限生命周期、Doze/强停/重启、BLE 共存、最小缺口呈现和唯一 hereIAmV3 短场景 Gate。A3 不由本任务自动启动。
