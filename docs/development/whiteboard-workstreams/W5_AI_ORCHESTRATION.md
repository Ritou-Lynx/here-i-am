# W5 — AI 编排与任务房间

> 工作流：W5 AI Orchestration
> 状态：原任务中心编排方向停止扩张；Phase A、R1–R3 与首个 Phase C Runtime → 白板行动纵切已集成，下一步做真人验收与持久恢复
> 创建日期：2026-08-15
> 依赖：W0 共享契约、Memory V3、iGateway Phase 3

> [!IMPORTANT]
> **2026-08-21 最终方向**：不再建设由 Here I am 复制 Planner / Executor / Reviewer、依赖图和子 Agent 状态的重型 Task Center。当前权威方案是 [`AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md`](../AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md)：Here I am 持有统一林埃入口、上下文、领域工具、权限、审计与结果落地；Codex 等 Runtime 持有内部执行结构。现有 `LinAiOrchestrator`、分类器、`ModelRouter` 与固定 `TaskRouter` 只保留为领域原型，不接真实 CodingAgent，不作为普通 workbench turn 的主路径。本文件下方旧阶段和接口仅供追溯，与权威方案冲突时不得执行。
>
> **Phase A 已通过**：Windows 本机已验证 ChatGPT Pro 认证、App Server 生命周期、thread 创建 / 恢复 / 分叉、turn 执行 / 转向 / 停止、真实审批拒绝、进程重启恢复，以及 Codex Desktop 同 ID 可见性。详见 [`W5_APP_SERVER_PHASE_A.md`](W5_APP_SERVER_PHASE_A.md)。
>
> **R1–R3 已随 `dc4e97c0` 合入并推送 `v3-lab`**：R1 冻结 provider-neutral RuntimeAdapter、Codex adapter 与默认关闭的 loopback 实验入口；R2 冻结 Context Envelope、RuntimeSessionBinding 与审计投影；R3 提供白板 Card / Source / Board 关系的有界只读 Tool Host。主工作区 Bridge 29/29、Runtime / Tool Host 与当前桌面 UI 联合测试 47/47、精确 analyze 零问题；没有 schema、真实模型调用或 UI 文件覆盖。交接分别见 [`W5_RUNTIME_ADAPTER_VERTICAL.md`](W5_RUNTIME_ADAPTER_VERTICAL.md)、[`W5_CONTEXT_BINDING.md`](W5_CONTEXT_BINDING.md)、[`W5_READ_ONLY_TOOL_HOST.md`](W5_READ_ONLY_TOOL_HOST.md)。
>
> **Phase C 可撤销写入基础已随 `dc4e97c0` 合入并推送 `v3-lab`**：新增产品签发、绑定 turn / board / 选区 / 能力 / 时效的一次性 Permission Broker，以及首个“选中项目分组并连线”写入 Tool Host；由 Here I am 从当前快照构造操作批次、一次事务落盘，并以完整快照哈希守卫整批撤销，拒绝覆盖后续用户修改。该基础交接当时联合回归 67/67、精确 analyze 零问题；没有 schema、真实模型调用或 UI 文件覆盖。权限、撤销令牌与幂等回执仍为进程内状态；Runtime transport 和行动卡片已由下一段纵切接通。详见 [`W5_REVERSIBLE_OPERATION_BATCH.md`](W5_REVERSIBLE_OPERATION_BATCH.md)。
>
> **Phase C 首个产品纵切已随 `dc4e97c0` 接通并推送 `v3-lab`**：Codex App Server dynamic tools 已投影为 provider-neutral `tool_call / tool_result`，Flutter 通过 loopback Runtime client 驱动只读 selection 与受限 group-and-connect；白板页面只暴露稳定 surface context，产品自行签发授权并持有写入。桌面林埃对话现在把明确白板动作持久化为结构化行动卡，可看详情和整批撤销；普通讨论仍走原聊天。Bridge 33/33、Flutter 联合验收 45/45、新增范围精确 analyze 零问题；修复 Drift 毫秒精度导致撤销误冲突的问题。仍未调用真实模型，实验入口默认关闭，跨重启撤销与 binding 持久化留后续。私人电脑真人验收接续见 [`W5_PRIVATE_PC_HANDOFF.md`](W5_PRIVATE_PC_HANDOFF.md)。

## 1. 目标与范围

### 1.1 核心目标

在白板桌面端实现林埃的 AI 编排能力，让林埃能够：
- 理解用户意图并分解任务
- 根据任务类型选择合适的执行策略（自己做 / 派发给 Agent）
- 管理任务房间生命周期（创建、执行、压缩、完成）
- 根据模型能力和额度自动选择和 fallback 模型
- 将对话和任务结果直接写入 Memory V3（不经过 iGateway）

### 1.2 明确不做

- ❌ 不实现外部工具（Claude Code / Codex）的独立 closeout 回流（由 iGateway 处理）
- ❌ 不实现完整的多设备同步机制（Phase 4.5 职责）
- ❌ 不实现具体的 Coding Agent 执行器（复用现有 Dev Room Bridge）
- ❌ 不实现白板画布操作本身（W1 职责）
- ❌ 不实现卡片内容编辑器（W2 职责）
- ❌ 不实现视频播放器（W4 职责）

### 1.3 边界与依赖

**依赖项：**
- W0：`Card`、`Board`、`Anchor` 共享契约已定义
- Memory V3：`TaskRooms`、`ConversationTurns`、`Artifacts` 表结构
- iGateway Phase 3：外部工具 closeout 投影机制已就绪

**输出给其他模块：**
- W1/W2/W3/W4：提供统一的任务创建接口
- 林埃悬浮对话：提供任务状态查询接口
- 任务中心 UI：提供任务列表和详情接口

## 2. 核心设计决策

### 2.1 白板的双重身份

**决策：白板 = Here I am 桌面端，直接访问 Memory V3**

白板不是"另一个外部工具"，而是 Here I am 在桌面端的原生扩展：
- 用户和林埃的对话直接写入 Memory V3
- 林埃召唤的 Agent 是工具调用，结果直接返回给林埃
- 不需要通过 iGateway closeout 来回流自己的对话

**实现注意：** 白板是 Flutter Desktop 应用，与 Android App 共享同一套代码库：
- `ProjectMemoryItems` 已存在，用于外部工具 closeout
- `PersonaChatMessages` 可承载白板对话
- `TaskRooms` 已在 Phase 1 完成（Memory V3 原生表）
- 白板通过 Drift 直接访问 Memory V3 SQLite 数据库，**不需要 Bridge 或 HTTP Server**

### 2.2 iGateway 的定位

**决策：iGateway 只处理外部工具和跨项目访问**

iGateway 在以下场景使用：
1. 外部工具独立工作（VS Code 里的 Claude Code）
2. 跨项目查询（"论文项目进度怎么样？"）
3. 多设备同步传输包

白板内的任务编排不经过 iGateway。

### 2.3 任务房间归属

**决策：任务房间属于 Memory V3，不属于 iGateway**

```
Memory V3
├── ConversationTurns（对话记录）
├── TaskRooms（任务房间）
│   ├── task_id
│   ├── goal
│   ├── status
│   ├── permissions
│   └── artifacts
└── ProjectMemory（项目记忆）
```

任务房间是 Memory V3 的原生概念，记录：
- 用户和林埃的任务对话
- 林埃召唤的 Agent 及其结果
- 任务产物（diff、图片、生成的卡片）

### 2.4 压缩策略

**决策：Agent 长输出 → 林埃压缩 → Memory V3**

```
Coding Agent 返回：
- 完整 diff（可能几千行）
- 测试日志
- 文件变更列表

林埃压缩为：
- 一句话摘要："添加了导出功能"
- 关键决策：["选择 JSON Schema v2"]
- 产物引用：["diff-789.patch"]

写入 Memory V3：
- 对话：摘要版本
- Artifacts：完整 diff（可按需查看）
```

## 3. 架构设计

### 3.1 三层架构

```
┌────────────────────────────────────────┐
│  用户层                                 │
│  - 林埃悬浮对话                         │
│  - 任务中心                             │
│  - 决策面板                             │
└──────────────┬─────────────────────────┘
               │
┌──────────────▼─────────────────────────┐
│  林埃决策层（Orchestrator）             │
│  - 意图分类                             │
│  - 任务路由                             │
│  - 模型选择与 fallback                  │
│  - 结果压缩                             │
│  - Memory V3 写入                       │
└──────────────┬─────────────────────────┘
               │
       ┌───────┼───────┬────────┐
       ▼       ▼       ▼        ▼
  ┌────────┐ ┌────┐ ┌──────┐ ┌──────┐
  │ Coding │ │内容│ │媒体  │ │白板  │
  │ Agent  │ │生成│ │分析  │ │操作  │
  └────────┘ └────┘ └──────┘ └──────┘
```

### 3.2 数据流

**场景：用户发起 Coding 任务**

```
1. 用户 → 林埃："帮我添加导出功能"

2. 林埃决策层：
   - classifyIntent() → type: 'coding'
   - createTaskRoom() → Memory V3
   - selectModel() → 'claude-code'
   - checkPermissions() → 允许读写 src/

3. 林埃 → Coding Agent：
   {
     task_id: "task-123",
     goal: "添加导出功能",
     permissions: { read: ["src/"], write: ["src/"] }
   }

4. Coding Agent → 工作...
   → 返回结构化结果：
   {
     status: "completed",
     summary: "已添加 JSON 和 Markdown 导出",
     files_changed: ["src/export.js", "src/app.js"],
     diff: "...(3000 行)",
     tests_passed: true
   }

5. 林埃决策层：
   - compressResult() → 提取摘要
   - 写入 Memory V3：
     * ConversationTurn: 摘要版本
     * TaskRoom: 完整记录
     * Artifacts: diff 文件

6. 林埃 → 用户：
   "导出功能已完成，支持 JSON 和 Markdown。
    改了 2 个文件，测试通过。"
```

## 4. 数据结构设计

### 4.1 任务房间（Memory V3 新表）

```sql
CREATE TABLE task_rooms (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  goal TEXT NOT NULL,
  status TEXT NOT NULL, -- 'planning' | 'running' | 'waiting' | 'completed' | 'failed'
  task_type TEXT NOT NULL, -- 'coding' | 'content' | 'media' | 'whiteboard'
  
  -- 权限
  permissions_json TEXT NOT NULL,
  
  -- 执行者
  executor TEXT, -- 'claude-code' | 'gpt-4v' | 'self' | null
  
  -- 时间
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER,
  
  -- 关联
  conversation_id TEXT,
  parent_task_id TEXT,
  
  -- 状态
  progress_percent INTEGER DEFAULT 0,
  current_step TEXT,
  
  FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE TABLE task_artifacts (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  artifact_type TEXT NOT NULL, -- 'diff' | 'image' | 'card' | 'file'
  title TEXT,
  content_path TEXT, -- 相对路径或 blob reference
  content_hash TEXT,
  size_bytes INTEGER,
  created_at INTEGER NOT NULL,
  
  FOREIGN KEY (task_id) REFERENCES task_rooms(id)
);

CREATE TABLE task_decisions (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  decision_type TEXT NOT NULL, -- 'user_choice' | 'auto_resolved' | 'fallback'
  question TEXT NOT NULL,
  options_json TEXT, -- [{ label, description, value }]
  selected_value TEXT,
  decided_at INTEGER NOT NULL,
  decided_by TEXT NOT NULL, -- 'user' | 'lin_ai'
  
  FOREIGN KEY (task_id) REFERENCES task_rooms(id)
);
```

### 4.2 模型配置（本地配置文件）

```json
// ~/.hereiam/whiteboard/model_config.json
{
  "schema_version": 1,
  "task_routing": {
    "planning": {
      "primary": {
        "model": "gpt-4o",
        "quota_key": "openai_main"
      },
      "fallback": {
        "model": "claude-opus-5",
        "quota_key": "anthropic_main"
      }
    },
    "coding": {
      "primary": {
        "model": "claude-code",
        "quota_key": "anthropic_main"
      },
      "fallback": {
        "model": "codex",
        "quota_key": "openai_main"
      }
    },
    "content_generation": {
      "primary": {
        "model": "claude-sonnet-4",
        "quota_key": "anthropic_main"
      },
      "fallback": {
        "model": "gemini-pro",
        "quota_key": "google_main"
      }
    }
  },
  "quotas": {
    "openai_main": {
      "total": 1000000,
      "used": 450000,
      "reset_at": "2026-09-01T00:00:00Z"
    },
    "anthropic_main": {
      "total": 2000000,
      "used": 1200000,
      "reset_at": "2026-09-01T00:00:00Z"
    }
  }
}
```

## 5. 核心接口

### 5.1 LinAiOrchestrator

```typescript
interface LinAiOrchestrator {
  // 处理用户消息
  handleUserMessage(message: string): Promise<string>
  
  // 意图分类
  classifyIntent(message: string): Promise<TaskIntent>
  
  // 任务路由
  routeTask(intent: TaskIntent): Promise<TaskRouter>
  
  // 模型选择
  selectModel(taskType: string): Promise<ModelSelection>
  
  // 创建任务房间
  createTaskRoom(intent: TaskIntent): Promise<TaskRoom>
  
  // 执行任务
  executeTask(taskRoom: TaskRoom): Promise<TaskResult>
  
  // 压缩结果
  compressResult(result: any): Promise<CompressedResult>
  
  // 写入 Memory V3
  writeToMemory(conversation: ConversationTurn, task: TaskRoom): Promise<void>
}
```

### 5.2 TaskRouter

```typescript
interface TaskRouter {
  // 注册执行器
  registerExecutor(taskType: string, executor: TaskExecutor): void
  
  // 派发任务
  dispatch(task: Task): Promise<TaskResult>
  
  // 查询任务状态
  getTaskStatus(taskId: string): Promise<TaskStatus>
  
  // 取消任务
  cancelTask(taskId: string): Promise<void>
}
```

### 5.3 CodingAgent（接口，实现在 Dev Room Bridge）

```typescript
interface CodingAgent {
  // 执行 coding 任务
  execute(request: CodingRequest): Promise<CodingResult>
  
  // 查询进度
  getProgress(taskId: string): Promise<number>
  
  // 取消执行
  cancel(taskId: string): Promise<void>
}

interface CodingRequest {
  task_id: string
  goal: string
  permissions: {
    read: string[]
    write: string[]
    tools: string[]
  }
  context?: {
    board_id?: string
    card_ids?: string[]
    files?: string[]
  }
}

interface CodingResult {
  status: 'completed' | 'failed' | 'cancelled'
  summary: string
  decisions: string[]
  files_changed: string[]
  artifacts: Artifact[]
  error?: string
}
```

## 6. 实施阶段

### Phase 1：基础编排（3-4 天）

**目标：** 最小可用的任务编排，固定模型，无 fallback

**前置工作：**
- [x] 数据库迁移：在 `lib/data/memory_v3/db/tables.dart` 新增 TaskRooms / TaskArtifacts / TaskDecisions
- [x] 扩展 `PersonaChatMessages` 添加 `taskRoomId: text().nullable()`
- [x] 实现 TaskRoomService 完整 CRUD 接口
- [x] 基础单元测试（20+ 测试用例全部通过）
- [x] 增加状态/类型 enum 和状态转移规则验证
- [x] 实现产物大小限制（100KB）和存储引用模式

**核心交付：**
- [x] 任务房间 CRUD 接口（TaskRoomService）
- [x] 任务产物管理（recordArtifact / getArtifacts / retractArtifact）
- [x] 任务决策记录（recordDecision / getDecisions）
- [x] 状态转移验证（基于 enum 的状态机）
- [x] 软删除模式（archive / retract 替代物理删除）
- [ ] `LinAiOrchestrator` 基础实现
- [ ] `TaskRouter` 固定路由表
- [ ] 简单的意图分类（规则 + 关键词）

**验收：**
- [x] TaskRoomService 所有单元测试通过（20 项）
- [x] 产物大小限制测试通过（5 项）
- [x] 状态转移验证正常工作
- [ ] 白板通过 Drift 直接访问 Memory V3
- [ ] 用户说"帮我生成一张卡片"，林埃能创建任务房间
- [ ] 任务状态写入 Memory V3
- [ ] 可在数据库中查到任务记录
- [ ] `PersonaChatMessages` 能关联到 `taskRoomId`

**Phase 1 状态：** 数据层完成 ✅（见 W5_PHASE1_HANDOFF.md）
**Phase 2 状态：** 编排层完成 ✅（见 W5_PHASE2_HANDOFF.md），Phase 3 待实现

### Phase 2：模型路由与 Fallback（2-3 天）✅ 2026-08-16

**目标：** 根据任务类型选择模型，额度耗尽时自动 fallback

**交付：**
- [x] `ModelRouter` 实现
- [x] 模型配置文件读取（`~/.hereiam/whiteboard/model_config.json`，缺文件给出创建指引）
- [x] 额度检查机制（used >= total 视为耗尽；无 quota_key 的模型 fail-open）
- [x] Fallback 链（primary → fallback → local；全耗尽抛 `ModelUnavailableException`，编排器降级 `unconfigured-local` 不阻塞闭环）
- [x] 用户通知（fallback 时回复附加「备用模型」提示；任务房间 context 记录实际模型与层级）

**附带交付（Phase 2 范围扩展，见 W5_PHASE2_HANDOFF.md）：**
- [x] `LinAiOrchestrator` 基础实现（classifyIntent / routeTask / selectModel / compressResult / handleUserMessage）
- [x] `TaskRouter` 固定路由表 + 按名注册执行器 + InlineSelfExecutor
- [x] 意图分类（规则 + 关键词打分，平局优先级裁决）
- [x] `ResultCompressor` 长输出压缩（摘要 + 决策 + 产物引用）
- [x] CodingAgent / ContentAgent 接口 + Mock 占位（真实 Dev Room Bridge 接线留 Phase 3）
- [x] Canvas Action Log 接口与写入契约（只存 NodeRef，失败不计数，阈值触发一次消费；持久化与记忆策展留 Phase 3）
- [x] Memory V3 写回：PersonaChatMessages 对话摘要（taskRoomId 软引用）+ TaskRoom + TaskArtifact
- [x] 编排产出 `WhiteboardOperation[]`（actor=i / authorizationId=taskId），走与用户操作同一条执行路径

**验收：**
- [x] 白板通过 Drift 直接访问 Memory V3（沿用 W5 Phase 1 决策，编排经 TaskRoomService 写回）
- [x] 用户说"帮我生成一张卡片"，林埃能创建任务房间并完成闭环
- [x] 任务状态写入 Memory V3
- [x] 可在数据库中查到任务记录（对话回合 / 房间 / 产物）
- [x] `PersonaChatMessages` 能关联到 `taskRoomId`

### Phase 3：Coding Agent 集成（3-4 天）

**目标：** 接入现有 Dev Room Bridge，支持真实 coding 任务

**交付：**
- [ ] `CodingAgent` 接口实现
- [ ] Dev Room Bridge 适配层
- [ ] 结果压缩器（长 diff → 摘要）
- [ ] Artifact 存储（diff 文件保存）
- [ ] 任务房间 UI（查看任务详情）

**验收：**
- 用户说"帮我添加导出功能"
- 林埃创建任务、调用 Claude Code
- Agent 完成后，林埃返回压缩摘要
- 用户可查看完整 diff

### Phase 4：并行执行与决策树（3-4 天）

**目标：** 支持多个 Agent 并行、需要用户决策时暂停

**交付：**
- [ ] 并行执行引擎
- [ ] 决策面板 UI
- [ ] 用户选择保存到任务记录
- [ ] 任务中心 UI（多任务状态）

**验收：**
- 同时运行 3 个任务（分析图片、生成卡片、coding）
- Agent 遇到两种方案时弹出决策面板
- 用户选择后继续执行

### Phase 5：完整集成与优化（2-3 天）

**目标：** 与白板其他模块集成，优化体验

**交付：**
- [ ] 林埃悬浮球状态指示
- [ ] 任务完成通知
- [ ] 错误处理与重试
- [ ] 性能优化（大 diff 处理）
- [ ] 完整测试覆盖

**验收：**
- 端到端场景测试通过
- 错误情况有友好提示
- 任务房间能正确恢复

## 7. 拥有路径

**新增文件：**
```
lib/domain/whiteboard/orchestration/    # ✅ Phase 2 已落地
├── lin_ai_orchestrator.dart            # ✅
├── task_router.dart                    # ✅
├── model_router.dart                   # ✅
├── intent_classifier.dart              # ✅
├── result_compressor.dart              # ✅
└── canvas_action_log.dart              # ✅ Phase 2 扩展（Huabu 借鉴 § 2）

lib/domain/whiteboard/agents/           # ✅ 接口 + Mock 占位
├── coding_agent.dart                   # ✅（真实实现接 Dev Room Bridge，Phase 3）
└── content_agent.dart                  # ✅（真实 LLM 接线 Phase 3）

lib/data/memory_v3/services/            # ✅ 对话写回
└── orchestration_chat_writer.dart      # ✅ PersonaChatLogWriter

lib/data/memory_v3/task_rooms/
├── task_room_service.dart              # ✅（Phase 1，已合入 v3-lab）
├── task_artifact_service.dart
└── task_decision_service.dart

desktop/whiteboard_mvp/src/orchestration/
├── orchestrator.mjs
├── task-router.mjs
├── model-router.mjs
└── agents/
    ├── coding-agent.mjs
    └── content-agent.mjs
```

**修改文件：**
```
lib/data/memory_v3/
├── memory_v3_service.dart（新增任务房间方法）
└── database_schema.dart（新增任务表）

desktop/whiteboard_mvp/src/
├── app.mjs（集成 orchestrator）
└── components/
    ├── i-popover.mjs（接入任务状态）
    └── task-center.mjs（新增）
```

**不修改：**
- W0 共享契约（`lib/domain/whiteboard/`）
- W1 画布代码
- W2 富文本编辑器
- W3 链接抓取
- W4 视频播放器

## 8. 共享契约影响

### 8.1 只读契约

- `Card`、`Board`、`Anchor`：只读，用于任务上下文
- `WhiteboardSnapshot`：只读，用于理解当前白板状态

### 8.2 新增契约（申请）

**`TaskRoom` 契约：**
```typescript
interface TaskRoom {
  id: string
  title: string
  goal: string
  status: 'planning' | 'running' | 'waiting' | 'completed' | 'failed'
  task_type: string
  permissions: TaskPermissions
  executor?: string
  artifacts: Artifact[]
  decisions: Decision[]
  created_at: number
  updated_at: number
}
```

**集成点：**
- W1 画布操作：可通过 `TaskRoom` 批量创建卡片
- W2 卡片生成：可通过 `TaskRoom` 创建富文本卡片
- W3 链接抓取：可通过 `TaskRoom` 批量导入链接
- W4 视频分析：可通过 `TaskRoom` 创建视频批注

### 8.3 变更请求

**需要 W0 集成确认：**
1. Memory V3 新增任务房间表（不影响现有 `MemoryCards`）
2. `ConversationTurn` 新增 `task_id` 字段（nullable，向后兼容）
3. 新增 `Artifact` 存储机制（独立于 `SourceContent`）

## 9. 测试策略

### 9.1 单元测试

```dart
// test/domain/whiteboard/orchestration/
test('LinAiOrchestrator 能分类用户意图', () {
  final orchestrator = LinAiOrchestrator();
  final intent = await orchestrator.classifyIntent('帮我生成一张卡片');
  expect(intent.type, equals('content_generation'));
});

test('ModelRouter 在额度耗尽时 fallback', () async {
  final router = ModelRouter(quotas: {'gpt-4': 0, 'claude-opus': 100});
  final model = await router.selectModel('planning');
  expect(model.model, equals('claude-opus'));
  expect(model.fallback, isTrue);
});

test('TaskRouter 能正确派发任务', () async {
  final router = TaskRouter();
  router.registerExecutor('coding', MockCodingAgent());
  final result = await router.dispatch(Task(type: 'coding', goal: 'test'));
  expect(result.status, equals('completed'));
});
```

### 9.2 集成测试

```dart
test('端到端：用户发起 coding 任务', () async {
  // 1. 用户消息
  final message = '帮我添加导出功能';
  
  // 2. 林埃处理
  final orchestrator = LinAiOrchestrator(memoryV3, modelRouter);
  final response = await orchestrator.handleUserMessage(message);
  
  // 3. 验证任务创建
  final tasks = await memoryV3.getTaskRooms();
  expect(tasks.length, equals(1));
  expect(tasks[0].goal, contains('导出功能'));
  
  // 4. 验证对话写入
  final conversation = await memoryV3.getLatestConversation();
  expect(conversation.turns.last.assistant, isNotEmpty);
  
  // 5. 验证 artifact 保存
  final artifacts = await memoryV3.getTaskArtifacts(tasks[0].id);
  expect(artifacts.any((a) => a.type == 'diff'), isTrue);
});
```

### 9.3 真实场景验证

**场景 1：简单内容生成**
```
用户："帮我生成一张关于现代主义建筑的卡片"
预期：
- 林埃分类为 content_generation
- 调用 Claude Sonnet
- 返回卡片内容
- 可在白板上看到新卡片
```

**场景 2：Coding 任务**
```
用户："帮我把这个导出功能加上，支持 JSON 格式"
预期：
- 林埃创建任务房间
- 调用 Claude Code
- Agent 改代码、写测试
- 林埃返回压缩摘要
- 用户可查看完整 diff
```

**场景 3：模型 Fallback**
```
设置：GPT-4 额度耗尽
用户："分析这张图片"
预期：
- ModelRouter 检测额度耗尽
- 自动切换到 Gemini Vision
- 显示提示："当前使用 Gemini Vision"
- 正常返回分析结果
```

## 10. 风险与缓解

### 10.1 Memory V3 表结构变更

**风险：** 新增任务表可能影响现有 Memory V3 查询性能

**缓解：**
- 任务表独立索引
- 不与现有 `MemoryCards` JOIN
- 分离 FTS（任务单独建 FTS）

### 10.2 大 diff 处理

**风险：** Coding Agent 返回几千行 diff，可能导致 Memory 膨胀

**缓解：**
- Artifact 存储为独立 blob
- 只在 ConversationTurn 存摘要
- 提供"查看完整 diff"按需加载

### 10.3 模型切换透明度

**风险：** 用户不知道用了哪个模型，可能对结果质量有疑惑

**缓解：**
- 模型切换时明确提示
- 任务房间记录实际使用的模型
- 设置界面显示各模型剩余额度

### 10.4 任务房间过多

**风险：** 长期使用后任务房间累积，影响查询性能

**缓解：**
- 自动归档 30 天前的已完成任务
- 提供任务清理工具
- 重要任务标记为"不归档"

## 11. 下一步接入点

完成 W5 后，其他模块可以：

**W1 画布：**
```typescript
// 批量创建卡片
await orchestrator.executeTask({
  type: 'whiteboard',
  goal: '把这 5 张图分析后放到白板上',
  context: { board_id: 'board-123', image_urls: [...] }
})
```

**W2 富文本：**
```typescript
// 生成富文本内容
await orchestrator.executeTask({
  type: 'content_generation',
  goal: '写一篇关于现代主义建筑的长文',
  output_format: 'rich_text'
})
```

**W3 链接抓取：**
```typescript
// 批量导入链接
await orchestrator.executeTask({
  type: 'link_ingestion',
  goal: '分析这 10 个链接并创建卡片',
  urls: [...]
})
```

**W4 视频分析：**
```typescript
// 视频字幕分析
await orchestrator.executeTask({
  type: 'media_analysis',
  goal: '提取这个视频的关键时间点',
  video_url: '...'
})
```

## 12. 参考资料

- `docs/companion-first/LIN_AI_CROSS_TOOL_CONTINUITY.md` — iGateway 架构与 Memory V3 关系
- `docs/design/whiteboard-requirements.md` — 任务房间产品定义
- `docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md` — 白板开发规范
- 白板并行开发 W0-W4 已有 handoff

---

## 附录：启动声明模板

```text
工作流：W5 AI 编排与任务房间
本轮目标：Phase 1 基础编排闭环
拥有路径：lib/domain/whiteboard/orchestration/、lib/data/memory_v3/task_rooms/、desktop/whiteboard_mvp/src/orchestration/
读取契约：白板并行开发总纲、LIN_AI_CROSS_TOOL_CONTINUITY.md、Memory V3 现有表结构
共享契约：申请新增 TaskRoom / TaskArtifact / TaskDecision 表；只读 Card / Board / Anchor
明确不做：外部工具 closeout 回流（iGateway）、多设备同步、具体 Coding Agent 实现、白板画布操作
验证：Memory V3 数据库迁移、任务创建与查询单元测试、端到端场景测试（内容生成 + coding 任务）
```
