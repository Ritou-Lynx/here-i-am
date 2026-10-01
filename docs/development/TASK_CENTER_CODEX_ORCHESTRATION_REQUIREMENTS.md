# 任务中心 × Coding Harness 编排需求（历史评审稿）

> 文档状态：**已被取代，仅供历史追溯**
>
> 创建日期：2026-08-20
>
> 取代日期：2026-08-21
>
> 当前权威方案：[`AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md`](AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md)
>
> 取代原因：Codex 客户端已经提供子 Agent、话题分叉和任务执行可见性；继续建设 Planner / Executor / Reviewer 状态机与重型 Task Center 会重复运行时能力。当前方案改为 Here I am 持有 AI 操作入口、上下文、领域工具、权限、审计与结果落地，Codex 持有内部执行结构。本文件中的历史分析仍可作为决策依据，但不得继续作为实现要求。

## 1. 背景

当前复杂开发任务的实际工作流是：

1. 用户在一个 Codex 窗口中讨论目标、制定计划、验收标准和依赖图；
2. 用户把并行子任务提示词分别复制到多个新窗口；
3. 各窗口完成后，用户把结果复制回规划窗口；
4. 规划窗口审核并给出返修意见；
5. 用户再把返修意见复制回原执行窗口；
6. 在执行、审核、返修之间反复搬运，直至验收通过。

这个流程中的核心能力并不缺失：Codex 能读取本地项目、制定计划、修改代码、运行验证并审核差异。真正缺失的是一个稳定的任务身份、会话映射和异步交接机制。用户被迫充当消息总线和状态机，既重复又容易遗漏上下文。

任务中心的目标不是再创造一个比 Coding Agent 更弱的“总指挥模型”，而是把这些已有能力组织成一个可观察、可恢复、可审计的协作闭环。

## 2. 产品判断

### 2.1 必须纠正的假设

林埃当前依赖 API 模型，不能默认拥有：

- 对完整代码库的直接读取能力；
- Codex、Claude Code、OpenCode 等 harness 的本地工具能力；
- 足够稳定且经济的强模型额度，用于长期承担规划与最终验收；
- 对分支、worktree、测试、diff 和运行时环境的第一手证据。

因此，在 coding 场景中，林埃不得作为计划、验收标准、依赖图或最终代码审核的权威来源。便宜模型生成的自然语言可以帮助解释状态，但不能改变任务合同、判定验收通过或授权集成。

### 2.2 正确定位

| 角色 | 权威职责 | 不负责 |
|---|---|---|
| 用户 | 目标、重大取舍、危险操作、最终集成授权 | 跨窗口复制提示词和结果 |
| Planner Harness | 读取项目，产出任务合同、验收标准、依赖图、路径边界 | 调度所有会话的生命周期 |
| Executor Harness | 在隔离工作区内实现被分配的闭环并提供证据 | 擅自改变共享契约或扩大任务范围 |
| Reviewer Harness | 基于任务合同、diff、测试和产物独立验收，产出返修包 | 直接替执行者掩盖失败或无证据放行 |
| 林埃 / 任务中心 | 持有 `task_id`，映射会话，推进状态机，转交结构化产物，控制重试和权限，形成压缩感知 | 代替强 harness 规划、审查代码或读取全仓 |
| Dev Room Bridge | 运行真实 CLI、管理凭据、worktree、事件、审批和产物 | 决定产品任务的目标与优先级 |

一句话定义：**强 harness 负责思考和验证，Bridge 负责执行，任务中心负责秩序，林埃负责陪伴式呈现与真正需要用户决定时的沟通。**

## 3. 现在是否需要介入

### 3.1 结论

需要现在介入，但介入对象是 W5 的职责和集成契约，不是立即开发一套新执行器。

原因：

1. `TaskRooms`、`TaskArtifacts`、`TaskDecisions` 已存在，继续开发任务中心 UI 很快会固化它们的使用方式；
2. Dev Room / Bridge 已经能启动 Codex、保存 Session / Run / Event / Approval / Artifact，并为写任务创建隔离 worktree；
3. 两套系统之间尚无正式的一对多关系，当前只能靠 `executor` 字符串或 JSON 上下文临时猜测；
4. 现有 `LinAiOrchestrator` 仍采用“林埃分类 → 自己选择模型 → 固定路由 → 一次性完成”的同步思路，不适合规划、并行执行、审核、返修和恢复组成的长任务；
5. 如果等 UI 和真实 CodingAgent 接线完成后再纠正，返工会同时波及数据库、状态机、Bridge 接口和交互层。

### 3.2 现在做什么

- 冻结本文件规定的职责边界和任务身份；
- 明确 `TaskRoom` 与真实执行会话的映射要求；
- 暂停把真实 CodingAgent 直接接入现有 `handleUserMessage()` 一次性闭环；
- 允许 Desktop 工作台与任务中心视觉继续推进，但 UI 只能依赖稳定的 TaskRoom 聚合接口；
- 先做一个无 UI、无 schema 变更的 Codex 垂直技术验证，再决定正式迁移和接口。

### 3.3 现在不做什么

- 不重写现有 Dev Room Bridge；
- 不把 Flutter 客户端直接接到 Codex 进程；
- 不为本需求改白板共享 Card / Source / Anchor / Snapshot 契约；
- 不抢占当前 Desktop Shell 的路由和视觉迁移；
- 不把 App Server 当成必须立即替换现有 `codex exec` 的新主线；
- 不自动 merge、push、发布或写入 User-truth。

## 4. 现状与可复用资产

### 4.1 Task Center / W5 已有能力

- `TaskRooms`：任务目标、类型、状态、执行者提示、权限、上下文、进度和当前步骤；
- `TaskArtifacts`：任务级 append-only 产物记录；
- `TaskDecisions`：任务级 append-only 决策及 supersede 关系；
- `PersonaChatMessages.taskRoomId`：对话与任务房间的软关联；
- `LinAiOrchestrator`：意图分类、路由、压缩和 TaskRoom 生命周期的领域原型；
- 桌面首页：已经能读取 TaskRoom 数量和状态；
- `/dev-room`：当前以“任务中心”名称进入旧 Dev Room 页面。

### 4.2 Dev Room / Bridge 已有能力

- `DevAgentSession`：持续会话身份和 provider session id；
- `DevAgentRun`：一次运行的 prompt、模型选项、worktree、分支和结果；
- Event / Approval / Artifact：流式事件、用户审批、diff、测试日志和构建结果；
- Codex、Claude Code、OpenCode 适配；
- 写任务的隔离 worktree；
- 运行中止、审批回复、产物读取、apply / discard / leave；
- Codex 模型、推理等级、service tier 和回答详细度配置；
- Bridge 持有凭据和 CLI 进程，客户端不保存工具密钥。

### 4.3 核心缺口

当前没有一个稳定关系表达：

```text
TaskRoom（产品任务）
  └─ TaskExecutionSessionLink（缺失）
       └─ DevAgentSession（工具会话）
            └─ DevAgentRun[]
                 ├─ Event[]
                 ├─ Approval[]
                 └─ Artifact[]
```

没有这层关系，任务中心无法可靠回答：哪个窗口是 Planner、哪个执行 W2、审核结论应该退回哪个原会话、一次重启后该恢复还是新建、某个 diff 属于哪一轮返修。

## 5. 核心对象与身份契约

### 5.1 TaskRoom

`TaskRoom` 是用户可见、跨多轮和多执行会话保持稳定的产品任务身份。它代表“要完成什么”，不是某个 Codex 窗口，也不是一次 CLI run。

要求：

- 一个 TaskRoom 可以拥有多个执行会话；
- TaskRoom 完成不等于某个 Run 成功，而是任务合同通过审核且达到集成条件；
- `TaskRooms.executor` 只能作为默认执行偏好或展示字段，不得作为真实会话映射的唯一依据；
- `contextJson` 不得继续承担不可查询、不可约束的主关联职责。

### 5.2 Task Contract

Planner Harness 必须先产出机器可校验的任务合同，最少包含：

- 合同版本、目标和明确不做事项；
- 项目基线、分支策略和上下文来源；
- 全局验收标准；
- 子任务 ID、目标、输入、产物和验证方式；
- 子任务依赖图；
- 每个子任务独占或可修改的路径；
- 共享契约变更请求及其集成负责人；
- 集成顺序、停止条件和需要用户决定的事项。

任务中心只验证结构完整性、无环依赖、路径所有权冲突和权限策略；它不得自行补写语义上缺失的验收标准。结构或语义不足时，应退回 Planner Harness 修订。

### 5.3 TaskExecutionSessionLink

需要新增一个逻辑上的会话绑定层。正式表名和 migration 由 W0/W5 集成阶段决定，本需求不直接指定 schema。

最少需要表达：

- `task_id`；
- `dev_agent_session_id`；
- 会话角色：`planner` / `executor` / `reviewer` / `integrator`；
- 对应子任务 ID 和 attempt；
- 当前生命周期状态；
- 创建、恢复、结束时间；
- 上游依赖或来源会话；
- 幂等键，避免重试时重复创建窗口。

一个 DevAgentSession 在一个任务中只能拥有一个明确角色；同一子任务的返修默认回到原 Executor Session，除非原会话不可恢复或 Reviewer 明确要求更换。

### 5.4 Artifact Reference

Task Center 不复制全部日志、diff 和工具输出到 TaskRoom。`TaskArtifacts` 只保存稳定引用、类型、摘要、来源会话、来源 Run、内容 hash 和可用性状态。

原始执行产物继续由 Dev Room / Bridge 管理。这样可避免双份真相、数据库膨胀和敏感日志进入林埃的日常上下文。

## 6. 标准工作流

### 6.1 创建与规划

1. 用户向任务中心描述目标，系统创建稳定 `task_id`；
2. 任务中心选择一个具备完整项目访问能力的 Planner Harness；
3. Planner 读取仓库契约、当前项目状态和必要代码，产出 Task Contract；
4. 任务中心执行结构校验，并把合同来源标记为“Codex Planner / 对应 Session”；
5. 低风险、路径隔离且无共享契约变更的任务可按策略自动进入执行；存在歧义、数据库迁移、依赖升级、共享契约或危险动作时，必须先请求用户或 W0 裁决。

### 6.2 并行执行

1. 对所有依赖已满足的子任务创建或恢复 Executor Session；
2. 每个写任务进入独立 worktree，并收到自己的任务包、拥有路径和验收标准；
3. 执行会话通过 Bridge 持续上报状态、事件、审批请求和产物；
4. 任务中心只转发结构化任务包和稳定产物引用，不把整段聊天在窗口间复制；
5. 子任务完成后状态进入 `awaiting_review`，不直接计为整个 TaskRoom 完成。

### 6.3 审核与返修

1. Reviewer Harness 获取 Task Contract、相关 diff、测试结果、产物和已批准的契约变更；
2. Reviewer 输出结构化结论：`pass`、`revise` 或 `blocked`；
3. `revise` 必须包含证据、对应验收条款、目标子任务、可执行返修意见和需要复验的项目；
4. 任务中心把返修包退回同一 Executor Session，并增加 attempt；
5. Executor 完成后重新进入 Reviewer；
6. 默认最多自动返修 2 轮，超过预算、发生契约冲突或两次出现同类失败时，转为需要用户决定；
7. 只有 Reviewer 基于证据给出 `pass`，任务才进入 `verified`。

### 6.4 集成与完成

1. Integrator 或 W0 按合同中的集成顺序检查分支和共享契约；
2. apply / merge / push 均遵守独立权限策略，MVP 不自动执行；
3. 集成验证通过后 TaskRoom 才标记完成；
4. 任务中心生成一份压缩任务结晶：完成结果、关键决策、未完事项和稳定产物引用；
5. 结晶可供林埃理解当前项目工作，但不得自动变成 User-truth；是否进入 Project Memory 仍遵守现有项目 closeout / 投影政策。

## 7. 状态模型

现有 TaskRoom 状态可继续作为粗粒度列表状态，但必须补充可持久化的任务阶段或从绑定会话可靠投影，不能用最后一条聊天文本推断。

建议阶段：

```text
draft
  → planning
  → ready
  → dispatching
  → executing
  → reviewing
  → revising ───────┐
       └─────────────┘
  → verified
  → ready_to_integrate
  → integrating
  → completed
```

任意活动阶段还可进入：

- `waiting_decision`：等待用户或 W0 处理真实决策；
- `blocked`：外部条件或契约冲突；
- `failed`：已耗尽重试或不可恢复错误；
- `cancelled`：用户取消。

约束：

- CLI 子进程结束不等于 TaskRoom 失败或完成；
- Bridge / App 重启后必须根据持久化状态恢复，无法恢复时明确转为 `blocked` 或创建有来源记录的新 attempt；
- 不允许静默把失败的会话当作新任务重新执行；
- 所有状态推进必须幂等并记录触发来源。

## 8. 功能需求

### TC-01 任务创建

- 用户只需提供一次目标；
- 系统生成稳定 TaskRoom 和可追踪的 Planner Session；
- 任务列表显示目标、当前阶段、进度、最近活动、阻塞原因和下一责任方。

### TC-02 计划合同

- Planner 必须是已连接且具备项目读取能力的强 harness；
- 计划必须结构化、可版本化并保留来源；
- 计划更新不得覆盖旧版本，需能说明因何修订；
- 林埃生成的解释必须明确标注为摘要，不得伪装成 Planner 结论。

### TC-03 依赖和并发

- 任务中心校验依赖图无环；
- 只调度依赖已完成的子任务；
- 检测拥有路径重叠，冲突时不得并行写；
- 并发数量受 Bridge 能力、用户配置和工具额度共同限制。

### TC-04 会话派发与恢复

- 支持创建、恢复、终止 Planner / Executor / Reviewer / Integrator Session；
- provider session id、TaskRoom、子任务和 attempt 必须可双向追踪；
- 派发使用幂等键；
- App 或 Bridge 重启后不能丢失任务归属。

### TC-05 审核返修

- Reviewer 读取真实 diff、测试和产物，而不是只读 Executor 摘要；
- 返修意见以结构化 Repair Packet 回到原会话；
- 自动返修预算可配置，默认 2 轮；
- 通过结论必须引用验收条款和证据。

### TC-06 决策升级

以下情况必须创建 TaskDecision 并提示用户或 W0：

- 目标或验收标准存在关键歧义；
- 两个子任务需要修改同一拥有路径；
- 请求修改共享 Card / Source / Anchor / Snapshot / PlayerAdapter 语义；
- 数据库 migration、核心依赖升级或安全边界变化；
- 需要 merge、push、发布、删除数据或扩大权限；
- 超过自动返修预算；
- Planner 与 Reviewer 对任务合同本身有冲突。

### TC-07 林埃感知

- 林埃默认只读取任务索引和压缩结晶；
- 用户询问某任务时，再按 `task_id` 读取阶段、责任方、决策和产物摘要；
- 原始 shell 输出、完整 diff、凭据和大段日志不得进入普通角色上下文；
- 状态陈述必须区分“Planner 判定”“Reviewer 判定”“任务中心记录”和“林埃解释”。

### TC-08 权限与安全

- 凭据继续由 Bridge / CLI 管理，Here I am 不保存 Codex、Claude Code 或 OpenCode token；
- 写任务默认在隔离 worktree；
- 任务合同中的拥有路径是允许范围，不代表危险操作自动授权；
- MVP 禁止自动 merge、push、发布和破坏性文件操作；
- 不使用屏幕抓取、剪贴板模拟或 UI 自动点击作为窗口交接协议；
- 工具无法证明自身执行结果时必须诚实失败。

### TC-09 可观察性

- 任务中心展示每个角色当前在做什么、最后一次可靠事件和等待对象；
- 支持查看 Task Contract、Review Verdict、Repair Packet、Decision 和 Artifact Reference；
- UI 中“已完成”只用于验收通过的闭环，不把“进程退出 0”直接显示为完成；
- 所有自动动作可追踪到任务、会话、Run 和触发策略。

## 9. Task Center UI 最小范围

### 9.1 任务列表

每项至少展示：

- 标题和目标摘要；
- 当前阶段；
- 进度和并行子任务数；
- 当前责任方：Planner / Executor / Reviewer / 用户 / W0；
- 最近可靠事件；
- 是否存在待决策或超时；
- 实际工具来源，例如“Codex · 深入推理”，而不是笼统显示“林埃处理中”。

### 9.2 任务详情

建议分为：

1. **总览**：目标、当前阶段、下一步；
2. **计划**：任务合同、依赖图、路径所有权；
3. **会话**：按角色和子任务组织的 DevAgentSession / Run；
4. **审核**：结论、证据和返修历史；
5. **决策**：需要用户/W0 处理的事项；
6. **产物**：diff、测试、构建、文档等稳定引用；
7. **时间线**：仅展示结构化状态事件，不复制完整聊天日志。

### 9.3 过渡期路由

- 当前“任务中心”仍指向旧 `DevRoomScreen` 是已知过渡态；
- 在 TaskRoom 列表和详情可用前，不为追求命名一致而提前删除 Dev Room；
- 新 UI 以 TaskRoom 为顶层入口，Dev Room 会话作为任务详情中的执行层；
- Dev Room 仍可保留“直接启动单个工具会话”的高级入口，但这类会话只有显式关联后才属于某个 TaskRoom。

## 10. Codex 接入策略

### 10.1 当前首选：复用 Bridge + Codex CLI

当前 Bridge 已经具备多工具适配、worktree、审批、事件和产物能力，应先在这条链路完成 MVP，不另建平行执行基础设施。

实现前必须验证：

- Bridge 启动的 Codex CLI 使用哪种认证方式，是否实际继承用户的 ChatGPT Pro 登录；
- 模型、推理等级和 service tier 的实际生效值能否回报；
- provider session id 与 `resume` 在 Windows 上能否稳定恢复；
- 同一项目的两个隔离 worktree 能否并发运行并保持路径所有权；
- Reviewer 能否只读获取其他会话的 diff、测试和任务合同；
- 返修能否回到原 Executor Session；
- App / Bridge 重启后的运行状态如何诚实恢复；
- 使用量或限额无法准确获取时，系统是否以“未知”呈现，而不是伪造额度。

认证和计费不得靠产品假设。Codex 官方说明区分 ChatGPT 订阅登录与 API Key 按量计费；技术验证必须记录实际认证路径。参考：[Codex CLI](https://learn.chatgpt.com/docs/codex/cli)、[Codex pricing](https://learn.chatgpt.com/docs/pricing)。

### 10.2 候选增强：Codex App Server

Codex App Server 官方定位是把 Codex 的认证、线程、审批和流式事件嵌入产品，并支持 thread start / resume / fork / read / status。它可能比解析 CLI JSON 更适合长期会话编排。参考：[Codex App Server](https://learn.chatgpt.com/docs/app-server)。

但当前不应让 Flutter 客户端直接绕过 Bridge 连接 App Server。正确的评估方式是：

- 把 App Server 作为 Bridge 内部的一个 Codex adapter 候选；
- 优先评估本地 stdio JSONL，不把实验性 WebSocket 当生产前提；
- 只有在它显著改善会话恢复、事件语义或审批一致性时才迁移；
- 保留 Bridge 对 Codex、Claude Code、OpenCode 的统一产品接口；
- 不因 App Server 引入第二套 TaskRoom、Artifact 或权限模型。

### 10.3 不接受的接入方式

- 让林埃 API 模型读取一小段摘要后自行生成权威计划；
- 在 Here I am 内保存用户的工具凭据；
- 用剪贴板、窗口标题或屏幕识别判断会话归属；
- 每次返修都新开无上下文会话；
- 把 Codex App Server 和现有 Bridge 同时当作产品真相源。

## 11. MVP 范围

首个闭环只验证一个真实场景：

- 单项目：Here I am；
- 单机：Windows；
- 一个 Codex Planner Session；
- 两个互不冲突的 Codex Executor Session 并行；
- 一个独立 Codex Reviewer Session；
- 至少一个子任务经历一次返修并回到原 Executor Session；
- 任务中心自动完成计划转交、结果收集、审核转交和返修转交；
- 用户全程不复制粘贴提示词、diff 或返修意见；
- merge / push 仍由用户明确批准或手动执行。

MVP 暂不要求：

- 自动选择所有 coding 工具；
- Planner 与 Executor 跨供应商混编；
- 多电脑同时执行；
- 通用工作流市场或插件系统；
- 让林埃 API 模型参与代码审查；
- 自动集成和自动发布。

## 12. 验收标准

### 12.1 产品闭环

- 用户输入一次目标后，可完成“规划 → 两路并行执行 → 审核 → 一次返修 → 复验”；
- 中途不需要用户在窗口间复制任何内容；
- 只有真实决策、权限审批或重试耗尽时打扰用户；
- Task Center 能准确显示当前责任方和下一步。

### 12.2 可追踪性

- 每个 TaskRoom 都能追踪到 Planner、Executor、Reviewer Session；
- 每个 Review Verdict 和 Repair Packet 都能追踪到来源 Run 和目标子任务；
- 每个 TaskArtifact 都能追踪到原始 Bridge Artifact；
- 同一幂等请求不会创建重复会话或重复执行。

### 12.3 恢复性

- 关闭并重启 Here I am 后，TaskRoom、依赖状态、会话角色、attempt 和待决策不丢失；
- Bridge 重启导致子进程不可恢复时，UI 明确显示失败原因并提供恢复或重试选择；
- 不把未知或失联显示为仍在运行。

### 12.4 安全与边界

- 无任务自动 merge、push 或发布；
- 无执行会话修改其拥有路径以外的文件，若发生则 Reviewer 必须阻断；
- 无工具凭据写入 Here I am 数据库或日志；
- 无原始 coding 日志自动进入 User-truth 或普通角色聊天上下文；
- 林埃不会把自己的摘要描述成 Planner 或 Reviewer 的原始判断。

## 13. 实施门槛与顺序

### Gate A：认证与额度事实

验证 Codex CLI 的真实登录路径、Pro 订阅继承、模型配置和限额呈现。失败则停止自动编排实现，保留手动 Dev Room。

### Gate B：会话恢复

验证 start / resume / provider session id / Bridge 重启行为。不能恢复时先设计诚实的 attempt 恢复语义。

### Gate C：结构化任务合同

用真实仓库让 Planner 产出两路并行合同，验证依赖、拥有路径和验收条款能被机器校验且质量足够。

### Gate D：并行与审核

验证两个 worktree 并行、Reviewer 只读审核、Repair Packet 回原会话和最多两轮重试。

### Gate E：数据契约

由 W0/W5 决定 TaskExecutionSessionLink 的正式 schema、迁移和聚合接口；不得用临时 JSON 直接进入生产。

### Gate F：任务中心 UI

在上述状态可持久化和恢复后，再实现 TaskRoom 列表/详情并替换“任务中心打开旧 Dev Room”的过渡态。

## 14. 对现有 W5 的影响

以下内容仍可复用：

- TaskRoom / Artifact / Decision 数据层；
- append-only 决策与产物思想；
- ResultCompressor 的压缩方向；
- Agent 接口抽象；
- 白板操作权限和 Action Log 边界；
- 不自动写 User-truth 的守门。

以下内容需要降级或重构：

- `IntentClassifier`：只能辅助判断入口，不产生权威任务合同；
- `ModelRouter`：不再决定 coding Planner / Reviewer 的模型能力，真实选择应来自 Dev Room / Bridge 配置与可用性；
- 固定 `TaskRouter`：从“一次任务选一个 executor”改为“按 Task Contract 调度多个角色会话”；
- `InlineSelfExecutor`：不得承接 coding 规划、实现或验收；
- `LinAiOrchestrator.handleUserMessage()`：保留简单白板动作的价值，但不能作为长周期 coding orchestration 的生产入口；
- 同步完成语义：必须改为可持久化、事件驱动、可恢复的多阶段状态机。

## 15. 待 W0 / W5 确认的决策

1. TaskExecutionSessionLink 独立表，还是扩展现有 DevAgentSession 增加软引用；**建议独立表**，避免执行层反向拥有产品任务；
2. Task Contract 存入 TaskArtifact 还是独立版本表；**MVP 建议版本化 TaskArtifact，稳定后再评估专表**；
3. Planner 与 Reviewer 是否允许同一 provider/model；**允许，但必须是独立 Session 和独立上下文角色**；
4. 低风险隔离写任务是否可在计划结构校验后自动启动；**建议允许，集成仍需审批**；
5. 自动返修预算；**建议默认 2 轮，可按项目覆盖**；
6. App Server 是否替换 Codex CLI JSON 适配；**先做 Bridge 内部技术验证，不现在决定迁移**；
7. Task Center 与旧 Dev Room 的导航关系；**建议 Task Center 聚合在上，Dev Room 作为任务内执行详情和高级直接入口保留**。

## 16. 成功定义

成功不是“林埃学会管理多个窗口”，也不是“增加一个聊天机器人角色”。

成功是：**用户只表达目标和做真正的决定；强 Codex harness 继续使用完整项目认知完成规划与验收；不同执行会话之间的上下文、产物、审核和返修由任务中心可靠交接；林埃知道工作正在发生什么，却不冒充自己拥有并未实际拥有的代码能力。**
