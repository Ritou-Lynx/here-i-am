# W5 Phase 1 Handoff — TaskRooms 数据层完成

> 工作流：W5 AI Orchestration Phase 1
> 状态：数据层完成，orchestration 层待实现
> 完成日期：2026-08-15
> 分支：codex/w5-task-rooms

## 1. 已完成交付

### 1.1 数据库迁移（schemaVersion 57 → 58）

**新增表：**

1. **TaskRooms** — 任务房间主表
   - 字段：id, title, goal, taskType, status, executor, permissionsJson, contextJson, progressPercent, currentStep, conversationId, parentTaskId, boardId, createdAt, updatedAt, completedAt
   - 索引：主键 (id)
   
2. **TaskArtifacts** — 任务产物表（append-only）
   - 字段：id, taskId, artifactType, title, contentJson, sizeBytes, mimeType, storageRef, createdAt
   - 索引：主键 (id), idx_task_artifacts_task_id (taskId, createdAt DESC)

3. **TaskDecisions** — 任务决策表（append-only）
   - 字段：id, taskId, decisionType, question, optionsJson, selectedOption, reasoning, decidedAt
   - 索引：主键 (id), idx_task_decisions_task_id (taskId, decidedAt DESC)

**表扩展：**

- **PersonaChatMessages** 新增 `taskRoomId: text().nullable()`
  - 索引：idx_persona_chat_task_room (taskRoomId) WHERE taskRoomId IS NOT NULL

**迁移文件：**
- `lib/db/app_database.dart` — `onUpgrade` 方法添加 v58 迁移逻辑
- `test/db/task_room_migration_test.dart` — 空数据库和 v57→v58 升级测试

### 1.2 类型安全 Enum 系统

**文件：** `lib/data/memory_v3/models/task_room_enums.dart`

**定义的 Enum：**

1. **TaskType** — 任务类型
   - coding, research, debugging, planning, other
   
2. **TaskStatus** — 任务状态（含状态机）
   - pending, running, blocked, completed, cancelled, archived
   - `isTerminal` getter — 判断是否为终态
   - `validTransitions` Map — 状态转移规则
   - `canTransitionTo(TaskStatus)` — 验证转移是否合法

3. **ArtifactType** — 产物类型
   - code_diff, analysis_result, error_log, test_result, screenshot, design_mockup, documentation, other

4. **DecisionType** — 决策类型
   - approach_choice, parameter_value, approval, prioritization, other

**状态转移规则：**
```dart
pending → {running, cancelled, archived}
running → {blocked, completed, cancelled, archived}
blocked → {running, cancelled, archived}
completed → {archived}
cancelled → {archived}
archived → {} // 终态，不可转移
```

### 1.3 TaskRoomService 完整实现

**文件：** `lib/data/memory_v3/services/task_room_service.dart`

**核心方法：**

**CRUD：**
- `createTaskRoom()` — 创建任务房间
- `getTaskRoom(id)` — 获取单个任务
- `listTaskRooms()` — 列出任务（支持 status/taskType/boardId 过滤和分页）
- `updateTaskStatus()` — 更新状态（含状态转移验证）
- `updateTaskContext()` — 更新上下文和权限
- `archiveTaskRoom(id)` — 软删除任务（标记为 archived）
- `permanentlyDeleteTaskRoom(id)` — 物理删除（@Deprecated，仅用于数据清除）

**产物管理：**
- `recordArtifact()` — 记录产物（含 100KB 大小验证）
- `getTaskArtifacts(taskId)` — 获取任务的所有产物
- `getArtifactsByType()` — 按类型过滤产物
- `retractArtifact()` — 追加撤销标记（append-only）
- `permanentlyDeleteArtifact(id)` — 物理删除（@Deprecated）

**决策管理：**
- `recordDecision()` — 记录决策
- `getTaskDecisions(taskId)` — 获取任务的所有决策
- `getDecisionsByType()` — 按类型过滤决策

**关联查询：**
- `getTaskRoomMessages(taskId)` — 获取任务关联的聊天消息
- `getTaskRoomFullContext(taskId)` — 获取完整上下文（⚠️ 仅供 UI 展示，禁止 Agent 注入）

**关键特性：**

1. **状态转移验证** — 非法转移抛出 `StateError`，提示有效转移列表
2. **产物大小限制** — contentJson 超过 100KB 且无 storageRef 时抛出 `ArgumentError`
3. **Soft Delete** — 默认使用 `archiveTaskRoom`，物理删除方法标记为 `@Deprecated`
4. **Append-Only** — 产物撤销通过追加 retraction marker 实现，不修改原记录

### 1.4 完整测试覆盖

**测试文件：**

1. **`test/data/memory_v3/services/task_room_service_test.dart`** — 20 项测试
   - CRUD 基础（创建、读取、列出、更新、归档、删除）
   - 状态转移验证（含非法转移测试）
   - 产物管理（记录、查询、撤销、删除）
   - 决策管理（记录、查询、按类型过滤）
   - 集成测试（完整上下文、错误处理）

2. **`test/data/memory_v3/services/task_room_artifact_size_test.dart`** — 5 项测试
   - 小产物（< 100KB）无 storageRef 正常存储
   - 大产物（> 100KB）无 storageRef 抛出错误
   - 大产物有 storageRef 正常存储
   - sizeBytes 默认值计算
   - 显式 sizeBytes 覆盖计算值

3. **`test/db/task_room_migration_test.dart`** — 3 项测试
   - 空数据库创建（v58 直接创建）
   - v57→v58 升级测试
   - 索引创建验证

**测试结果：** 全部 28 项测试通过 ✅

### 1.5 文档更新

**文件：** `docs/development/whiteboard-workstreams/W5_AI_ORCHESTRATION.md`

**更新内容：**
- 明确白板是 Flutter Desktop 应用，通过 Drift 直接访问 Memory V3
- 删除"需要 Bridge 或 HTTP Server"的过时描述
- 更新 Phase 1 完成状态（数据层完成，orchestration 层待实现）

---

## 2. 架构决策记录

### 2.1 白板身份确认

**决策：** 白板 = Flutter Desktop 应用，与 Android App 共享同一套 Memory V3 代码库。

**影响：**
- ✅ 不需要 Bridge 或 HTTP Server
- ✅ 直接通过 Drift ORM 访问 SQLite 数据库
- ✅ TaskRoomService 可在 Android/Desktop 两端复用

### 2.2 Enum 优先的类型安全

**决策：** 使用 Dart enum 定义任务类型、状态、产物类型、决策类型，而非字符串常量。

**优势：**
- 编译期类型检查，杜绝拼写错误
- IDE 自动补全和重构支持
- 状态机逻辑内聚在 enum 定义中
- 数据库存储仍为字符串（`.value`），保持灵活性

### 2.3 Soft Delete 为默认

**决策：** 任务和产物默认使用软删除（archive / retract），物理删除标记为 `@Deprecated`。

**理由：**
- 符合 append-only 原则
- 保留完整的任务演化历史
- 支持审计和回溯
- 用户隐私清除作为专门流程，不混入日常操作

### 2.4 产物大小分级存储

**决策：** 100KB 作为 contentJson 内联存储上限，超过必须提供 storageRef 外部引用。

**实现：**
- `recordArtifact` 方法在插入前验证内容大小
- 超过限制且无 storageRef 时抛出 `ArgumentError` 并提示
- `sizeBytes` 字段记录原始大小，支持监控和清理

---

## 3. 未完成事项（Phase 2+ 待实现）

### 3.1 Orchestration 层

**待实现文件：**
```
lib/domain/whiteboard/orchestration/
├── lin_ai_orchestrator.dart
├── task_router.dart
├── model_router.dart
├── intent_classifier.dart
└── result_compressor.dart
```

**核心功能：**
- 意图分类（用户消息 → 任务类型）
- 任务路由（任务类型 → Agent 选择）
- 模型选择与 fallback（primary / fallback / local）
- 结果压缩（Agent 长输出 → 摘要）
- Memory V3 写入（对话 + 任务 + 产物）

### 3.2 Agent 集成

**待实现：**
- CodingAgent 接口（复用 Dev Room Bridge）
- ContentAgent（内容生成）
- MediaAgent（图片/视频分析）
- WhiteboardTool（画布操作）

### 3.3 UI 集成

**待实现：**
- 任务中心 UI（任务列表和详情）
- 决策面板（Agent 提供多方案时）
- 林埃悬浮球状态指示（任务执行进度）
- 任务完成通知

### 3.4 模型配置

**待实现文件：** `~/.hereiam/whiteboard/model_config.json`

**配置内容：**
- 任务类型 → 模型映射（primary / fallback）
- 额度管理（total / used / reset_at）
- Fallback 链配置

---

## 4. 关键文件清单

### 4.1 新增文件

**数据层：**
- `lib/data/memory_v3/models/task_room_enums.dart`
- `lib/data/memory_v3/services/task_room_service.dart`

**测试：**
- `test/data/memory_v3/services/task_room_service_test.dart`
- `test/data/memory_v3/services/task_room_artifact_size_test.dart`
- `test/db/task_room_migration_test.dart`

**文档：**
- `docs/development/whiteboard-workstreams/W5_AI_ORCHESTRATION.md`
- `docs/development/whiteboard-workstreams/W5_ARCHITECTURE_VALIDATION.md`
- `docs/development/whiteboard-workstreams/W5_PHASE1_HANDOFF.md` (本文件)

### 4.2 修改文件

**数据库：**
- `lib/data/memory_v3/db/tables.dart` — 新增 3 个表定义
- `lib/db/tables.dart` — PersonaChatMessages 新增 taskRoomId
- `lib/db/app_database.dart` — schemaVersion 58 + migration
- `lib/db/app_database.g.dart` — 代码生成（自动）

**Service 初始化：**
- `lib/data/repositories/memex_router.dart` — 添加 TaskRoomService.init()

---

## 5. 验收清单

### Phase 1 数据层（已完成）

- [x] TaskRooms / TaskArtifacts / TaskDecisions 表创建
- [x] PersonaChatMessages.taskRoomId 字段添加
- [x] 所有索引正确创建
- [x] 数据库迁移测试通过（空数据库 + v57→v58）
- [x] TaskRoomService 完整实现
- [x] 状态转移验证正常工作
- [x] 产物大小限制测试通过
- [x] 单元测试覆盖率（28 项测试全部通过）
- [x] Service 初始化接线（MemexRouter）
- [x] 文档更新（明确白板 = Flutter Desktop）

### Phase 2 Orchestration（待实现）

- [ ] LinAiOrchestrator 基础实现
- [ ] TaskRouter 固定路由表
- [ ] 意图分类（规则 + 关键词）
- [ ] 模型选择与 fallback
- [ ] 端到端测试（用户消息 → 任务创建）

---

## 6. 下一步行动

### 6.1 立即可做

1. **集成到 v3-lab 主分支**
   ```bash
   # 在 worktree 中提交
   git add -A
   git commit -m "feat(memory-v3): W5 Phase 1 - TaskRooms data layer"
   
   # 切回主工作目录
   cd ../../..
   git merge codex/w5-task-rooms
   ```

2. **验证 Android App 兼容性**
   - 构建 hereIAmV3 flavor
   - 验证数据库升级
   - 检查 TaskRoomService 初始化

### 6.2 Phase 2 启动准备

**前置依赖：**
- 确认白板 Desktop 应用启动流程
- 确认林埃聊天 UI 入口（PersonaChatScreen）
- 确认现有 Agent 调用模式（Companion / RecordOrganizer）

**首个里程碑：** 固定模型的简单任务创建
- 用户说"帮我生成一张卡片"
- LinAiOrchestrator 分类为 `content_generation`
- 调用固定模型（如 Claude Sonnet）
- 创建 TaskRoom，记录过程
- 返回压缩摘要

---

## 7. 已知限制与风险

### 7.1 技术限制

1. **大 diff 处理** — contentJson 有 100KB 限制，超大 diff 需要 storageRef 机制
2. **并发安全** — 当前 Service 无锁机制，多 Agent 并行写入需要测试
3. **查询性能** — 大量任务累积后，listTaskRooms 需要分页和索引优化

### 7.2 产品限制

1. **UI 未实现** — 用户暂时无法可视化查看任务房间
2. **Agent 未接入** — 无法真实执行 coding / content / media 任务
3. **模型配置未落地** — fallback 链和额度管理尚未实现

### 7.3 缓解措施

- 大 diff 限制已在文档和测试中明确说明
- 并发测试列入 Phase 3 验收标准
- UI 和 Agent 接入作为 Phase 3-4 重点

---

## 8. 参考资料

- `docs/development/whiteboard-workstreams/W5_AI_ORCHESTRATION.md` — 完整设计文档
- `docs/memory-research/MEMORY_PROPOSAL_V3.md` — Memory V3 架构权威文档
- `docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md` — 白板并行开发总纲
- `lib/data/memory_v3/services/task_room_service.dart` — Service 实现参考
- `test/data/memory_v3/services/task_room_service_test.dart` — 测试用例参考

---

**Phase 1 数据层完成标记：2026-08-15**
**下一阶段：Phase 2 — Orchestration 层实现**
