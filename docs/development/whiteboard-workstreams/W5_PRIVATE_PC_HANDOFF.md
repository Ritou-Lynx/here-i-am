# W5 — 私人电脑接续交接

> 日期：2026-08-22
>
> 工作流：W5 / AI 原生工作台 × Codex Runtime
>
> 当前停点：私人电脑真实模型核心闭环已通过——受限读取选区、写入分组 / 连线、重开页面确认持久化、整批撤销并确认 Drift 无残留；输出质量仍差，普通聊天 / 关闭开关两条真人负路径与跨进程撤销仍待补验

## 1. 这次如何交接

事实状态以本文件和仓库内权威文档为准，启动提示词只负责让新 Codex 任务读取它们。不要把完整历史重新粘贴进新窗口，也不要让新窗口重新设计 Task Center、线程边界或 Runtime 架构。

私人电脑拉取 `origin/v3-lab` 后，至少应包含：

- `dc4e97c0 feat(workbench): add codex runtime whiteboard actions`
- `1b8722b7 feat(desktop): refine floating companion chat`

如果远端已有更新，以最新 `origin/v3-lab` 为准；上述两个提交只是本轮能力存在的最低基线，不要求把 HEAD 固定在该提交。

## 2. 已完成的产品能力

- 桌面白板把当前 board 与选区暴露为有界 surface context。
- 明确要求处理“所选卡片分组并连线”的消息进入 Codex App Server Runtime；普通林埃聊天继续走 Companion 原路径。
- Runtime 只能调用两个动态工具：读取当前选择，以及提交受限的 group / edge 计划。
- Here I am 持有授权、board / turn / batch 注入、Drift 事务写入、审计和整批撤销；模型不能直接写数据库。
- 聊天中会持久化结构化行动卡，显示进行中、完成、失败或撤销，并可查看产品审计摘要。
- Runtime adapter 保持 provider-neutral；Codex 是第一个 provider，不是林埃人格或产品对话真相。
- 实验入口默认关闭、只允许 loopback；关闭开关即可撤下，无 schema 回滚。

## 3. 已完成的验证

- Codex App Server Phase A 曾在工作电脑使用 ChatGPT Pro 真实通过认证、模型发现、thread / turn、steer、interrupt、审批拒绝、进程重启恢复和 Codex Desktop 同 ID 可见性。
- 当前完整纵切使用 fake App Server 通过 Bridge 33/33、Flutter 联合验收 45/45，并真实写入 / 撤销临时 Drift 数据。
- 新增范围精确 analyze 零问题。
- 私人电脑已使用真实 `gpt-5.6-sol` 跑通当前产品核心纵切；最终一轮选择 3 项，生成 1 个分组与 1 条连线，重开白板后仍存在，随后整批撤销成功，等待 7 秒后 Drift 中 group / member / edge 均为 0。
- 本轮新增的 Tool Host 与 coordinator 定向回归 12/12 通过；此前 Bridge deterministic 33/33 与 W5 Flutter 基线回归继续作为环境基线。

### 3.1 私人电脑真实验收记录（2026-08-22）

- 环境：Codex CLI `0.147.0`，该机 ChatGPT 登录有效、订阅信息报告为 Pro；模型均从该机 `model/list` 读取，实际涉及 `gpt-5.6-sol`、`gpt-5.6-luna` 与 `gpt-5.4-mini`，未修改全局 Codex 配置。
- 基线：Bridge deterministic 回归 33/33；W5 Flutter 定向回归 52/52；相关范围 analyze 零问题。只读、临时的 `gpt-5.6-sol` App Server marker probe 成功完成。
- 首轮真实产品动作：选择卡片后发送“按主题分组并连线”，行动卡在原 `120 s` 截止时间内返回 `runtime_timeout`，白板安全保持不变。
- 协议定位：`gpt-5.6-luna` 的两工具合成探针最终按正确顺序完成读 selection 与提交计划，但耗时 `119067 ms`，已贴近产品 `120 s` 截止时间。
- 连接证据：`gpt-5.4-mini` 低推理量诊断在首个工具调用前连续收到可重试的 provider 连接错误与 `Reconnecting... 2/5` 至 `5/5`；约 `118682 ms` 才出现第一次工具调用。更小模型与更低推理量均未消除超时。
- 后续定位：当前网络上 App Server 会先经历约 `112 s` 的 WebSocket 重试，再自动退回 HTTPS；第一条有效动态工具响应约在 `126 s` 出现。产品截止时间据此从 2 分钟调整为 3 分钟，没有放宽权限、工具范围或全局 Codex 配置。
- 第二处失败：模型第一次提交计划时遗漏 1 个所选项，被 `groups_must_partition_selection` 正确拒绝。prompt 与动态工具说明现明确要求每个所选 item 必须且只能出现一次；无法拆成多个至少 2 项的主题组时，必须用一个宽泛组完整覆盖选择。
- 最终真实闭环：选择 3 项后，Runtime 先读取受限 selection，再提交 1 个组 / 1 条边；行动卡完成、重开白板后结果仍存在；点击整批撤销后行动卡为 `undone`，等待 7 秒后数据库中 group / member / edge 均为 0。
- 真人闭环同时发现并修复三类撤销误冲突：重开时仅刷新 `updated_at`、Drift 返回实体列表顺序变化、coordinator 仍持有已销毁旧页面的 reload。冲突哈希现忽略非语义时间戳并规范化实体顺序；撤销前后都以当前同 board surface 执行 flush / reload，恢复态再次 flush，避免旧页面把已撤销内容写回。
- 短口令 `按主题分组并连线` 现被明确动作 matcher 接管。此前它误落入普通 Companion，触发了手机模型配置页；曾误加的桌面设置入口与粘贴按钮已全部撤销，桌面不暴露手机模型配置，输入框继续使用系统原生 `Ctrl+V`。
- 当前 CLI 已把旧 Responses WebSocket feature flags 标为 removed；官方资料中也未找到受支持的 Codex App Server “关闭 WebSocket”配置，因此本轮没有写入隐藏开关或绕过协议。
- 安全性：成功与失败路径都保持 fail-closed；模型只经声明的两个动态工具读选择、提议受限计划，没有数据库或任意文件写权限；文档不记录账号、凭据、原始推理或私人卡片内容。
- 质量结论：当前输出满足完整划分和安全写入契约，但真人观感仍很差——3 个异质项经常被塞进一个宽泛组，只生成 1–2 条语义牵强的边。安全闭环已通过不等于规划质量合格，后续应单独改进主题判断与“宁可少连、不要乱连”的质量门槛。
- 并行噪声：测试期间手机 UI 分支的启动 / 销毁逻辑偶发桌面 widget lifecycle 异常，导致窗口导航失效；它不属于 W5 拥有路径，本轮没有改动这些手机 UI 文件。

## 4. 当前剩余验收

核心真人闭环已通过，后续不应重复扩张架构。剩余工作按边界补齐负路径与质量，不新增 schema、不扩大 Runtime 权限。

### 4.1 接续与基线检查

1. 切到 `v3-lab`，确认工作树干净。
2. `git fetch` 后使用 fast-forward-only 拉取 `origin/v3-lab`。
3. 确认上方两个最低基线提交存在。
4. 读取根 `AGENTS.md`、白板并行开发总纲、本文件及第 7 节权威资料。

如果私人电脑有未提交改动、分支分叉或无法 fast-forward，立即停止；不要自动 stash、reset 或 rebase。

### 4.2 Runtime 能力检查

1. 核对私人电脑的 Codex CLI / App Server 可启动，并使用该电脑自己的 ChatGPT 登录。
2. 读取该机 `model/list` 的真实结果，再选择模型；不要照抄工作电脑曾使用的 `gpt-5.5`，也不要修改全局 Codex 配置来迁就文档。
3. 先运行 deterministic Bridge 测试和 W5 Flutter 定向测试，确认拉取与依赖环境没有回归。
4. 需要时运行只读的真实 App Server probe，确认认证、模型和 thread 生命周期；不得借 probe 写项目文件。

### 4.3 剩余真人小样

在一个终端显式开启实验入口并启动 Bridge：

```powershell
$env:DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER="1"
$env:DEV_AGENT_EXPERIMENTAL_CODEX_MODEL="<model/list 返回的可用模型>"
powershell -File tools\dev_agent_bridge\start_bridge.ps1
```

在另一个终端运行 Windows 应用：

```powershell
flutter run -d windows
```

剩余验收步骤：

1. 发送一句普通讨论，确认没有被白板动作 matcher 接管；确定性 matcher 测试已有覆盖，但仍欠一次真人 UI 观察。
2. 关闭实验开关后发送明确动作，确认只得到“能力未开启”的失败行动卡且白板不变；确定性失败路径已有测试，但仍欠一次真人 UI 观察。
3. 若继续做质量迭代，使用不含私人内容的代表性选区，明确记录分组是否有解释力、连线是否必要；不得以“契约合法”替代真人质量验收。
4. 跨应用重启后的 undo token / binding 仍是 Phase D 能力，不把“结果能持久化”误写成“重启后仍可撤销”。

## 5. 本轮通过标准

核心成功闭环已经通过；只有以下全部成立，才把 W5 全部真人验收标为通过：

- 私人电脑 ChatGPT 认证和实际模型选择可解释，没有静默修改全局配置。
- 真实模型只通过声明的动态工具读取 / 提议，没有直接获得数据库或任意文件写权限。
- 成功路径产生可见行动卡、真实白板持久化和可用的整批撤销。
- 失败、关闭功能和普通聊天三条路径都不误写白板。
- Bridge 停止时 App Server 子进程被正确清理。
- 验收结果、模型 ID、Codex CLI 版本和发现的问题写回本 handoff、`I_PROJECT_STATE.md` 与 `DEVLOG.md`；不要记录账号、凭据、原始推理或私人卡片内容。

如果真实模型没有稳定调用工具，先保存标准事件与产品侧错误码并定位协议，不要靠放宽权限、把工具搬进 Bridge 或增加关键词特判掩盖问题。

本次根据实测 fallback 时序把截止时间调整为 3 分钟，使 HTTPS 自动降级有机会完成；这只是当前网络条件下的务实容错，不应继续无限延长。若要改善体验，应另开有边界的改动，把“正在重连 / 服务不可用”投影成更及时、可理解的行动状态，并保留现有安全失败语义。

## 6. 真人验收之后才考虑的工作

按优先级依次评估：

1. Bridge 自动启动、健康状态和用户可理解的不可用提示。
2. `RuntimeSessionBinding`、权限授权与撤销材料的跨应用重启持久化。
3. 从单一中文 matcher 升级为可审计的通用意图路由。
4. 第二个真正有价值的领域动作。
5. Coding 纵切与第二 provider。

不要恢复重型 Task Center，不复制 Codex 的计划、子 Agent、话题分叉或完整任务界面。只有定时、跨设备持续运行或多 provider 异步任务真正出现时，才重新评估 TaskRoom。

## 7. 权威资料

按顺序阅读：

1. `AGENTS.md`
2. `docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`
3. `docs/development/AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md`
4. `docs/development/whiteboard-workstreams/W5_RUNTIME_ACTION_VERTICAL.md`
5. `docs/development/whiteboard-workstreams/W5_APP_SERVER_PHASE_A.md`
6. `docs/development/whiteboard-workstreams/W5_RUNTIME_ADAPTER_VERTICAL.md`
7. `tools/dev_agent_bridge/README.md`

## 8. 可复制到私人电脑 Codex 的启动提示词

```text
继续 Here I am 的 W5「AI 原生工作台 × Codex Runtime」。先完整读取根 AGENTS.md、docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md，以及 docs/development/whiteboard-workstreams/W5_PRIVATE_PC_HANDOFF.md，并按其中第 7 节继续读取权威资料。

核心真人闭环已经完成：真实模型只经受限工具读取选择并提交计划，白板写入在重开后仍存在，整批撤销后 Drift 无残留。当前目标不是开发新架构，而是补一次普通讨论旁路和关闭 experimental Runtime 两条真人负路径，并把“整理很差”作为独立质量问题处理；跨应用重启后的撤销仍属于 Phase D。先确认分支为 v3-lab，检查本机 Codex / App Server 登录与 model/list，模型只选本机实际可用项，不修改全局配置；先跑 deterministic Bridge 与 W5 Flutter 定向回归，再进行最小真人验证。

开始实质操作前，按总纲给出不超过 8 行的工作流声明。不要重做 Task Center、线程边界或架构，不新增 schema，不扩大权限，不记录账号、凭据、原始推理或私人卡片内容。若拉取分叉、工作树不干净、模型不可用或真实工具调用失败，保留证据并报告，不要自动 stash/reset/rebase，也不要用权限放宽或关键词特判绕过。完成后把真实版本、模型、验收结果、问题和下一接入点更新到 W5_PRIVATE_PC_HANDOFF.md、I_PROJECT_STATE.md 与 DEVLOG.md；未经我明确要求不要 commit 或 push。
```
