# Here I am AI 原生工作台 × Codex 集成架构

> 状态：**已确认，作为当前权威方案**
>
> 确认日期：2026-08-21
>
> 适用范围：Here I am Desktop、林埃悬浮对话、白板 / 卡片 / 阅读器 AI 操作、Codex 与未来 Coding Harness 集成
>
> 取代：`TASK_CENTER_CODEX_ORCHESTRATION_REQUIREMENTS.md` 中以 Task Center 为独立编排中枢的方案，以及 `W5_AI_ORCHESTRATION.md` 中“意图分类 → 模型路由 → 固定执行器 → 同步完成”的主路径

## 1. 一句话决策

**不建设一套重复 Codex 的重型“任务中心”，而是在 Here I am 中建设统一的 AI 操作层。**

- Here I am 持有人格、连续对话、上下文、内容对象、权限、审计与结果落地；
- Codex 是第一种桌面工作运行时，负责推理、项目读取、工具使用、计划、子 Agent、分叉和验证；
- Here I am 不复制 Codex 的内部任务图、子 Agent 树、Planner / Executor / Reviewer 状态机或完整执行界面；
- 用户始终从林埃入口发起操作，只有需要决定、授权、查看依据或检查产物时才展开执行细节；
- 未来可替换为 Claude Code、OpenCode、Hermes 或 API Runtime，但不改变产品对话和内容身份。

所谓“后台复杂任务”不再作为独立产品类型。它只是：**某次运行仍未结束，即使用户关闭了对话面板。**

## 2. 产品形态

### 2.1 用户可见表面

桌面端只新增三种表面：

1. **林埃悬浮对话**：工作台中的统一自然语言入口；
2. **行动卡片**：显示执行中、等待决定、已完成、失败、可撤销；
3. **执行详情抽屉**：按需查看工具调用、受影响对象、审批、测试、diff、错误和产物来源。

不新增：

- 独立 Task Center 首页；
- Planner / Executor / Reviewer 看板；
- Here I am 自建依赖图编辑器；
- Codex 子 Agent 树的镜像；
- 第二套完整 Codex 聊天客户端；
- “简单任务 / 后台复杂任务”的用户分类入口。

### 2.2 两个运行配置，不是两个人格

同一个林埃可使用不同运行配置：

| 配置 | 适用范围 | 默认运行时 | 权限边界 |
|---|---|---|---|
| `companion` | 日常关系聊天、手机端、无工作区操作 | 当前 Companion Runtime / API | 无仓库 shell；记忆按现有工具契约召回 |
| `workbench` | 桌面白板、卡片、阅读和项目工作 | Codex App Server | Here I am 领域工具；coding 时按项目授予受限 workspace |

运行时变化不产生新角色。产品层仍是同一个 `conversation_id`、同一个林埃身份和同一条可恢复聊天时间线；执行详情必须诚实显示实际运行来源。

## 3. 职责边界

| 组件 | 权威职责 | 明确不负责 |
|---|---|---|
| Here I am 产品层 | `conversation_id`、PersonaChatMessages、页面和对象身份、权限、审计、撤销、结果卡片 | 模拟强模型规划、复制 Codex 任务图 |
| Context Assembler | 身份 Prompt、最近聊天、当前页面、按需召回结果、工具与授权说明 | 永久保存巨型编译 Prompt、替代 Memory V3 |
| Runtime Coordinator | 创建 / 恢复运行时 session、发送 turn、转向、停止、重连、事件投影 | 解释代码正确性、判定测试通过 |
| Codex Runtime | 推理、项目读取、计划、子 Agent、分叉、代码修改、测试和审核 | 直接写 Here I am 数据库、绕过产品权限 |
| Here I am Tool Host | 读取白板 / 卡片 / 记忆并执行领域操作 | 暴露裸 SQL、任意文件写入或 UI 点击模拟 |
| Permission Broker | 计算本轮授权、请求确认、记录来源、生成撤销批次 | 根据模型自述自动扩大权限 |
| Dev Agent Bridge | 进程、认证、适配器、流式事件、审批与原始产物 | 持有产品对话真相、发明 TaskRoom 语义 |

## 4. 系统架构

```text
Here I am Flutter Desktop
├─ 白板 / 卡片 / 阅读器
├─ 林埃悬浮对话
├─ 行动卡片
└─ 执行详情抽屉
            │ 版本化本机协议
            ▼
Dev Agent Bridge / i Agent Host
├─ Context Assembler
├─ Runtime Coordinator
├─ Permission Broker
├─ Event Projector
├─ Artifact Reference Store
└─ RuntimeAdapter
       ├─ CodexAppServerAdapter      ← MVP
       ├─ ClaudeCodeAdapter          ← 后续
       ├─ OpenCodeAdapter            ← 后续
       └─ HermesAdapter              ← 后续
            │
            ├──────── Codex App Server
            │          ├─ ChatGPT 登录
            │          ├─ thread / turn
            │          ├─ approvals / streamed events
            │          └─ Codex harness / subagents / worktrees
            │
            └──────── Here I am MCP / Tool Host
                       └─ Core API / 领域服务 / WhiteboardOperation
```

Flutter 客户端不直接管理 Codex 进程或凭据。Codex App Server 作为 Bridge 内部 adapter；Bridge 继续作为未来多运行时的稳定边界。

Codex App Server 是官方建议的富客户端嵌入接口，支持认证、线程历史、审批和流式 Agent 事件：<https://learn.chatgpt.com/docs/app-server>。

## 5. 一次工作台操作的完整数据流

用户在白板选中十张卡片并说：

> 按主题整理这些卡片，分组并连线。

系统按以下顺序运行：

1. Here I am 先把用户消息写入产品聊天时间线；
2. 客户端提交 `conversation_id`、页面类型、`board_id`、选中对象 ID 和本轮显式意图；
3. Context Assembler 生成本轮 Context Envelope；
4. Runtime Coordinator 判断复用当前 Codex thread，或为新的工作片段创建 thread；
5. Codex 通过只读工具获取卡片内容、白板关系和必要记忆；
6. Codex 调用写工具提交一批领域操作；
7. Permission Broker 根据用户原话、操作范围、可逆性和风险决定自动执行或请求确认；
8. Here I am 领域服务执行 `WhiteboardOperation`，形成可审计、可撤销的 operation batch；
9. Event Projector 将 Codex 原始事件压缩成行动卡片；
10. 最终自然语言回复写回产品聊天，完整工具事件和大产物只保留稳定引用。

结果卡片示例：

```text
已按 3 个主题整理 10 张卡片
新增 3 个分组、7 条连线

[撤销] [查看改动]
```

## 6. Context Envelope

### 6.1 默认注入

每个 workbench turn 默认只包含：

- 当前林埃全局 Prompt 的版本引用；
- 最近约 20 条产品聊天记录；
- 当前页面类型与稳定对象 ID；
- 当前选择集和必要的轻量对象摘要；
- 本轮权限声明；
- 可调用工具说明；
- 当前运行配置和项目根目录（仅 coding 场景）。

### 6.2 按需获取

以下内容不全量预加载，通过工具按需获取：

- Memory V3 相关事实；
- Project Memory；
- 完整卡片正文或 Source 内容；
- 大型白板快照；
- 仓库文件、diff 和测试日志；
- 历史执行产物。

Memory 数据库不是上下文本身；`memory_search` 是工具，返回的少量结果才成为当轮上下文。

### 6.3 Context Manifest

系统不持久化一份不断复制的巨型 Prompt。每个 turn 只保存可审计的 manifest：

- identity / prompt version；
- 最近消息截止位置；
- surface snapshot ref；
- memory query 与命中 ref；
- toolset version；
- permission profile；
- runtime / model / provider thread id。

Manifest 是运行收据，不是第二套记忆系统。

## 7. Thread 边界

### 7.1 三种身份

```text
Here I am conversation_id   产品连续性，长期稳定
RuntimeSessionBinding       一段连贯工作的运行绑定
Codex thread_id             Codex 工作内存，可替换
```

不得把 Codex `thread_id` 当作林埃身份或永久记忆。

### 7.2 复用规则

在以下条件同时成立时复用当前 Codex thread：

- 仍在同一个连贯主题；
- 当前页面 / 白板 / 项目范围没有实质变化；
- thread 可恢复且未出现明显上下文污染；
- 权限配置兼容。

以下情况创建新 thread：

- 切换到不同项目或长期主题；
- 从白板受限模式切换到 coding workspace；
- thread 过长、异常或不可恢复；
- 需要隔离危险权限；
- 用户明确分叉。

新 thread 从产品数据重新组装 Context Envelope，不建立独立“线程压缩记忆库”。未完成工作的交接摘要可以存在 manifest 中，但必须可由聊天、状态和产物重新生成。

Codex 官方协议支持 `thread/start`、`thread/resume`、`thread/fork`、`turn/start`、`turn/steer` 与事件流：<https://learn.chatgpt.com/docs/app-server>。

## 8. Runtime Adapter 契约

产品层只依赖以下抽象能力：

```text
RuntimeAdapter
├─ getAuthStatus()
├─ listCapabilities()
├─ startSession(config, contextManifest)
├─ resumeSession(providerSessionId)
├─ startTurn(sessionId, input)
├─ steerTurn(sessionId, turnId, input)
├─ interruptTurn(sessionId, turnId)
├─ respondToApproval(requestId, decision)
├─ streamEvents(sessionId)
└─ closeSession(sessionId)
```

Provider 特有信息只进入 adapter 和 `provider_metadata`，不得泄漏为产品通用状态机。没有某项能力的运行时必须诚实声明不支持，不能靠 UI 模拟补齐。

MVP 的 `CodexAppServerAdapter` 使用 ChatGPT 登录，不把 ChatGPT 订阅当成通用 API Key。认证模式和实际 plan 由 App Server 回报，不由 Here I am 猜测。

## 9. Here I am Tool Host

### 9.1 MVP 只读工具

- `get_current_surface`
- `get_board_snapshot`
- `get_selected_cards`
- `read_card`
- `search_cards`
- `search_memory`
- `get_project_state`

### 9.2 MVP 写工具

- `apply_board_operations`
- `create_card`
- `update_card`
- `remove_board_items`
- `create_group`
- `create_edge`
- `undo_operation_batch`
- `record_explicit_memory`

### 9.3 工具约束

- 工具只接受稳定 ID 和结构化 payload；
- 不暴露 Drift、裸 SQL、数据库文件或 Flutter widget 操作；
- 所有写操作进入领域服务和审计日志；
- `remove_board_items` 只删除摆放，不删除 Card / Source；
- 删除 Card / Source 必须另设高风险工具，MVP 不开放；
- `record_explicit_memory` 只在用户明确说“记一下 / 保存为记忆”时可用；
- 原始聊天、任务日志、抓取内容和播放器进度不自动写入 User-truth。

Codex、ChatGPT 桌面客户端、CLI 和 IDE extension 可在同一 Codex host 上共享 MCP 配置，因此同一套 Here I am 工具未来可同时服务嵌入入口和原生 Codex：<https://learn.chatgpt.com/docs/extend/mcp?surface=cli>。

## 10. 权限、审计与撤销

| 操作 | 默认策略 |
|---|---|
| 读取当前页面、卡片、白板和本轮必要记忆 | 自动允许 |
| 用户原话明确要求、范围有限、可整体撤销的白板编辑 | 本轮授权 |
| 大批量修改、跨白板写入、权限范围扩大 | 执行前确认 |
| 删除 Card / Source、数据库迁移、依赖升级 | 必须单独确认 |
| User-truth 写入、外部发送、merge、push、发布 | 必须单独确认 |
| 破坏性文件操作或超出 workspace 的访问 | 默认拒绝；需要新的明确授权 |

每一批写操作必须记录：

- `operation_batch_id`；
- `runtime_turn_id`；
- 用户原始授权消息；
- 实际运行时和工具来源；
- 目标对象 ID；
- 操作前后摘要；
- inverse / undo token；
- 执行、失败或撤销时间。

模型提出操作不等于获得授权；权限由 Here I am 的确定性代码判定。

## 11. Coding 请求

用户仍从林埃悬浮入口发起 coding 请求。系统为 coding turn 使用项目 `cwd`、独立权限配置和需要时的 worktree。

Codex 内部自行管理：

- 计划；
- 子 Agent；
- 话题分叉；
- 并行探索；
- 代码修改；
- 测试与审核；
- 返修循环。

Here I am 只投影：

- 当前可靠状态；
- 需要用户决定的问题；
- 权限和审批；
- 修改对象与产物引用；
- 最终结果和验证证据。

默认不复制 Codex 内部子 Agent 图。若 Codex 原生客户端能够稳定打开 App Server 创建的同一 thread，可提供“在 Codex 中查看”；否则由 Here I am 的详情抽屉显示必要证据。两者都不能成为产品正确性的前提。

## 12. 最小数据契约

### 12.1 `RuntimeSessionBinding`

```text
id                      Here I am 稳定 ID
conversation_id         产品对话
provider                codex / claude_code / opencode / hermes
provider_session_id     运行时 thread / session ID
profile                 companion / workbench / coding
scope_type              surface / board / project
scope_id                 稳定对象或项目 ID
status                   active / idle / interrupted / closed / unavailable
provider_metadata_json  provider 私有数据
created_at
last_active_at
closed_at
```

### 12.2 `RuntimeTurn`

```text
id
runtime_session_id
user_message_id
provider_turn_id
status                   queued / running / waiting_approval / completed / failed / interrupted
context_manifest_json
result_summary
error_code
started_at
completed_at
```

### 12.3 存储边界

- `PersonaChatMessages` 继续是用户可见聊天真相；
- Bridge 保存原始运行事件、diff、测试日志和大产物；
- Here I am 只保存稳定 artifact ref、hash、类型和摘要；
- `WhiteboardOperation.authorizationId` 或后续等价字段关联 `runtime_turn_id`；
- 普通悬浮对话不创建 TaskRoom；
- TaskRoom 保留给未来真正需要独立生命周期的定时、跨设备、队列型或多供应商异步工作。

正式 schema 与 migration 必须在 App Server 技术验证通过后由 W0 / W5 单独评审；本文件冻结语义，不预先强制表名。

## 13. 状态投影与界面文案

产品只投影以下状态：

| 状态 | 用户文案示例 |
|---|---|
| `running` | 正在整理卡片 / 正在检查项目 |
| `waiting_approval` | 需要你确认一项操作 |
| `waiting_input` | 有一个选择需要你决定 |
| `completed` | 已完成，可查看改动或撤销 |
| `failed` | 未完成，显示真实原因和可重试入口 |
| `interrupted` | 已停止，可继续或结束 |

不得把“进程退出 0”“某个子 Agent 完成”或模型声称“已经修好”直接投影为整个工作完成。完成状态必须基于实际工具结果和验证事件。

详情抽屉显示：

- 实际运行来源；
- 已读取 / 修改的对象；
- 工具调用及结果；
- 审批历史；
- 测试、diff 和产物引用；
- 错误与重试；
- 原始日志的按需入口。

不展示或声称展示模型私有思维过程。

## 14. 实施阶段

### Phase A — App Server 技术验证

> **状态：2026-08-21 已通过。** 实现与验收记录见
> [`whiteboard-workstreams/W5_APP_SERVER_PHASE_A.md`](whiteboard-workstreams/W5_APP_SERVER_PHASE_A.md)。

无产品 UI、无 schema 迁移，验证：

- Bridge 启动和关闭 App Server；
- ChatGPT 登录与实际认证模式回报；
- `thread/start / resume / fork`；
- `turn/start / steer / interrupt`；
- 消息、工具、审批和完成事件流；
- Bridge / App 重启后的恢复；
- 限额未知时诚实显示 unknown；
- App Server 创建的 thread 是否能在当前 Codex 客户端中发现或打开。

最后一项是可用性增强，不是架构阻塞条件。

本机验证同时确认：App Server 创建的持久 thread 与 Codex Desktop 使用同一任务存储，客户端可按同一 ID 发现并归档；临时 thread 可用于不污染任务历史的控制与审批探针。当前全局 Codex CLI `0.142.4` 的 `model/list` 只暴露 `gpt-5.5`、`gpt-5.4`、`gpt-5.4-mini`、`gpt-5.3-codex-spark`，因此适配器必须先校验实际模型列表，不得因桌面配置指向更新模型而静默修改用户全局配置。

### Phase B — 只读工作台闭环

林埃能够基于当前白板回答：

- 选中了哪些卡片；
- 卡片内容和来源是什么；
- 当前分组与连线关系；
- 相关 Memory / Project Memory（按需召回）。

不得产生白板写操作。

### Phase C — 第一个可撤销写闭环

唯一验收场景：

> 选中若干卡片 → 对林埃说“按主题分组并连线” → Codex 读取内容 → 形成操作批次 → Here I am 执行 → 显示结果 → 整批撤销 → 重启后状态仍一致。

### Phase D — 恢复、权限与详情

- 对话面板关闭后 turn 可继续；
- 重启后恢复 session / turn；
- 审批、停止、重试；
- operation batch 审计与撤销；
- 详情抽屉显示真实工具、产物和错误。

### Phase E — Coding 纵切

从林埃入口发起一个真实 Here I am 仓库任务：

- Codex 读取项目契约；
- 在受限 workspace / worktree 中修改；
- 运行定向测试；
- Here I am 投影状态、审批和结果；
- 用户无需复制提示词、diff 或返修意见；
- merge / push / 发布仍需明确授权。

### Phase F — 第二运行时

只在 Codex 纵切稳定后，用同一 `RuntimeAdapter` 契约接入一个非 Codex 运行时，验证产品层未绑定 provider 私有状态。

## 15. MVP 验收标准

### 15.1 产品闭环

- 用户从林埃悬浮入口完成一次真实白板 AI 操作；
- 不打开 Coding 工具、不复制提示词；
- 可看到正在做什么、是否等待自己、最终改了什么；
- 操作可整体撤销；
- 关闭并重开 Here I am 后聊天、运行绑定和白板状态一致。

### 15.2 身份与上下文

- 产品对话不依赖单个 Codex thread 永久存在；
- 新 thread 能从 Here I am 数据恢复必要上下文；
- 运行时变化不改变林埃身份；
- Memory 只按需召回，普通操作不写 User-truth。

### 15.3 安全

- Codex 不直接写 Drift 或白板文件；
- 所有写操作通过领域工具、权限检查和审计；
- 高风险操作不能因模型自述而获得授权；
- 原始日志、凭据和完整 diff 不进入普通聊天上下文；
- 无法证明的执行结果不得显示为成功。

### 15.4 开放性

- 产品数据库不依赖 Codex 专有状态名；
- provider thread ID 只存在于 binding；
- 工具、权限、内容对象和产品聊天均由 Here I am 持有；
- 替换 RuntimeAdapter 不需要迁移林埃身份或用户内容。

## 16. 旧模块处理

现阶段不删除已有代码，但停止沿旧方向扩张：

- `LinAiOrchestrator`：保留为领域原型，不接真实 CodingAgent；
- `IntentClassifier`：不得成为所有对话的强制前置分类器；
- `ModelRouter`：不负责选择 ChatGPT 订阅内的 Codex 模型或伪造额度；
- 固定 `TaskRouter`：不再作为 coding 主调度器；
- TaskRoom：普通 workbench turn 不创建，留给未来真正的独立异步任务；
- 当前 Dev Room：继续作为高级工具会话入口，直到新的 RuntimeAdapter 纵切稳定；
- 当前“任务中心”路由：不再扩建重型任务中心 UI，后续根据真实使用决定保留、降级或更名。

任何清理、重命名、schema 迁移和路由调整必须另开实现 session，并先完成 Phase A。

## 17. 技术验证后的唯一实施入口

Phase A 通过后，不重新讨论产品形态，直接按以下顺序推进：

```text
RuntimeAdapter + CodexAppServerAdapter
        ↓
Context Envelope + RuntimeSessionBinding
        ↓
只读 Here I am Tool Host
        ↓
可撤销 WhiteboardOperation batch
        ↓
行动卡片 + 详情抽屉
        ↓
Coding 纵切
        ↓
第二 provider 验证开放性
```

如果 Phase A 证明 App Server 在当前 Windows / 认证环境中不可用，只替换 `CodexAppServerAdapter` 的实现方式，不推翻 Here I am 持有上下文、权限、工具和产品连续性的上层架构。
