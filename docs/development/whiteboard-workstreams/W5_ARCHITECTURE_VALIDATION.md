# W5 架构验证报告

> 日期：2026-08-15
> 目的：验证 W5 AI 编排设计与现有 Memory V3、白板、聊天系统的兼容性

## 1. 验证结论

### ✅ 核心架构兼容

W5 设计与现有架构**整体兼容**，但需要注意以下几点：

1. **Memory V3 已有 Project Memory**：可以直接使用，不需要重新设计
2. **聊天系统已就绪**：`PersonaChatMessages` 可承载林埃对话
3. **任务房间需要新增**：当前没有 `TaskRooms` 表，需要新建
4. **白板是 Web 端**：需要通过 Bridge 访问 Flutter 的 Memory V3

## 2. 现有表结构分析

### 2.1 Memory V3 核心表（`lib/data/memory_v3/db/tables.dart`）

**已有且可直接使用：**

| 表名 | 用途 | W5 如何使用 |
|-----|------|-----------|
| `MemoryCards` | User-truth 卡片 | 读取用户已确认的事实/任务 |
| `MemoryCardSources` | 卡片来源 | 记录任务来源（chat / fab / 自然命令） |
| `ProjectMemoryItems` | 项目记忆投影 | **已存在！** 可直接用于外部工具 closeout |
| `ProjectMemorySources` | 项目记忆来源 | 记录 closeout 的 sourceTool / sessionId |
| `MemoryFragments` | Dreaming 碎片 | 不影响，继续保持隔离 |
| `MemoryEpisodes` | 经历凝结 | 不影响，继续保持隔离 |
| `Assets` | 媒体资产 | 任务产物（图片、截图）可存这里 |

**关键发现：`ProjectMemoryItems` 已存在！**

```dart
class ProjectMemoryItems extends Table {
  TextColumn get id => text()(); // stable Gateway event id
  TextColumn get projectId => text()();
  TextColumn get projectKey => text()();
  TextColumn get itemType => text().withDefault(const Constant('closeout'))();
  TextColumn get summary => text()();
  TextColumn get decisionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get openLoopsJson => text().withDefault(const Constant('[]'))();
  TextColumn get artifactRefsJson => text().withDefault(const Constant('[]'))();
  // ...
}
```

这是 iGateway Phase 3 已经建好的表，**用于外部工具 closeout 投影**。

### 2.2 聊天系统（`lib/db/tables.dart`）

**已有且可直接使用：**

| 表名 | 用途 | W5 如何使用 |
|-----|------|-----------|
| `PersonaChatMessages` | 用户与林埃的对话 | **核心表**，白板里的所有对话写这里 |
| `SyncOutboxMessages` | 跨设备同步待发送消息 | 支持多设备聊天同步 |
| `ConversationCaptureCursors` | 对话捕获游标 | 不影响（旧 V2 机制） |

**关键字段：**

```dart
class PersonaChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().nullable()(); // 跨设备稳定 ID
  TextColumn get characterId => text()(); // 林埃 ID
  BoolColumn get isFromCharacter => boolean()();
  TextColumn get content => text()(); // 对话内容
  TextColumn get messageType => text().withDefault(const Constant('chat'))();
  TextColumn get attachmentsJson => text().nullable()(); // 附件（图片等）
  DateTimeColumn get timestamp => dateTime()();
}
```

**问题：没有 `task_id` 字段！**

需要扩展来关联任务房间。

### 2.3 任务系统（`lib/db/tables.dart`）

**已有但不适用：**

```dart
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get payload => text().nullable()();
  TextColumn get status => text()(); // pending, processing, completed, failed
  // ...
}
```

这是**后台任务队列**（如 WorkManager 任务），不是我们需要的"任务房间"。

任务房间需要：
- 关联对话
- 记录 Agent 执行过程
- 保存产物（diff、生成的卡片）
- 记录用户决策

**结论：需要新建 `TaskRooms` 表族。**

## 3. 白板与 Memory V3 的访问方式

### 3.1 当前架构

```
桌面白板（Electron / Web）
    ├── 前端：desktop/whiteboard_mvp/src/app.mjs
    └── 后端：？
        ↓
    需要访问：
        - Memory V3（Flutter / Dart）
        - 聊天数据（Flutter / Drift）
```

### 3.2 现有 Dev Room Bridge

查看项目状态文档，Dev Room 已经有 Bridge：

```
手机 App（Memory V3）
    ↓ Tailscale HTTPS Bridge
开发机（Codex / Claude Code）
    ↓ MCP
读取 Project Memory
```

**关键问题：白板桌面端是否复用这个 Bridge？**

从文档看：
- `docs/companion-first/LIN_AI_CROSS_TOOL_CONTINUITY.md` 提到 Bridge 用于 Dev Room
- `docs/development/I_PROJECT_STATE.md` 提到 `bridge.example.com` 是真机 Bridge URL

### 3.3 白板的三种可能架构

**方案 A：复用 Dev Room Bridge**

```
白板（Web）→ HTTPS Bridge → 手机 Memory V3
```

优点：
- 复用现有 Bridge
- 可以访问完整 Memory V3

缺点：
- 依赖手机在线
- 网络延迟
- 需要手机运行 Bridge 服务

**方案 B：白板独立 Flutter Desktop**

```
白板（Flutter Desktop）→ 直接访问本地 Memory V3
```

优点：
- 无网络依赖
- 直接访问数据库
- 与手机 App 共享代码

缺点：
- 当前 MVP 是 Web 实现
- 需要重写

**方案 C：白板 + 本地 Bridge**

```
白板（Web）→ 本地 HTTP Server（Dart）→ Memory V3
```

优点：
- 保持 Web 前端
- 无网络依赖
- 可访问 Memory V3

缺点：
- 需要实现本地 Bridge
- 额外进程管理

## 4. W5 数据结构修正

### 4.1 任务房间表设计（新增）

基于现有架构，修正 W5 设计：

```dart
// 新增表：lib/data/memory_v3/db/tables.dart

/// 任务房间：用户与林埃的复杂任务协作空间
///
/// 与 Project Memory 的区别：
/// - TaskRooms 是白板内的原生任务，属于 Memory V3
/// - ProjectMemoryItems 是外部工具的 closeout 投影，来自 iGateway
class TaskRooms extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text()();
  TextColumn get goal => text()();
  TextColumn get taskType => text()(); // coding / content / media / whiteboard
  TextColumn get status => text(); // planning / running / waiting / completed / failed
  
  // 执行者
  TextColumn get executor => text().nullable()(); // claude-code / gpt-4v / self
  
  // 权限（JSON）
  TextColumn get permissionsJson => text().withDefault(const Constant('{}'))();
  
  // 上下文（JSON）
  TextColumn get contextJson => text().withDefault(const Constant('{}'))();
  
  // 进度
  IntColumn get progressPercent => integer().withDefault(const Constant(0))();
  TextColumn get currentStep => text().nullable()();
  
  // 关联
  TextColumn get conversationId => text().nullable()(); // 软引用到对话 ID
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get boardId => text().nullable()(); // 关联的白板
  
  // 时间
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get completedAt => integer().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

/// 任务产物：diff / 图片 / 生成的卡片 / 文件
class TaskArtifacts extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get taskId => text()(); // soft FK → task_rooms.id
  TextColumn get artifactType => text()(); // diff / image / card / file
  TextColumn get title => text().nullable()();
  
  // 内容存储
  TextColumn get contentPath => text().nullable()(); // 文件路径
  TextColumn get contentBlob => text().nullable()(); // 小内容直接存
  TextColumn get contentHash => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  
  // 关联
  TextColumn get assetId => text().nullable()(); // 软引用到 Assets
  TextColumn get cardId => text().nullable()(); // 软引用到 MemoryCards
  
  IntColumn get createdAt => integer()();
  
  @override
  Set<Column> get primaryKey => {id};
}

/// 任务决策记录：用户做的选择
class TaskDecisions extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get taskId => text()(); // soft FK → task_rooms.id
  TextColumn get decisionType => text()(); // user_choice / auto_resolved / fallback
  TextColumn get question => text()();
  TextColumn get optionsJson => text().nullable()(); // JSON array
  TextColumn get selectedValue => text().nullable()();
  TextColumn get decidedBy => text()(); // user / lin_ai
  IntColumn get decidedAt => integer()();
  
  @override
  Set<Column> get primaryKey => {id};
}
```

### 4.2 扩展 PersonaChatMessages

**方案 A：新增 task_id 字段（推荐）**

```dart
class PersonaChatMessages extends Table {
  // ... 现有字段 ...
  
  // 新增：关联任务房间
  TextColumn get taskId => text().nullable()(); // soft FK → task_rooms.id
}
```

**方案 B：通过关联表**

```dart
class ChatMessageTaskLinks extends Table {
  TextColumn get id => text()();
  IntColumn get messageId => integer(); // → persona_chat_messages.id
  TextColumn get taskId => text(); // → task_rooms.id
  IntColumn get createdAt => integer()();
  
  @override
  Set<Column> get primaryKey => {id};
}
```

推荐**方案 A**，因为更简单，且大多数消息不会关联任务（nullable）。

### 4.3 不需要新增的表

以下表**已存在**，W5 直接使用：

- `ProjectMemoryItems`：外部工具 closeout（如 VS Code 里的 Claude Code）
- `Assets`：任务产物中的媒体文件
- `MemoryCards`：任务完成后用户确认的 User-truth

## 5. 集成方案建议

### 5.1 Phase 1：最小可用架构

**目标：** 验证白板能访问 Memory V3

**实现：**
1. 白板 Web 前端保持不变
2. 创建本地 Dart HTTP Server（mini Bridge）
3. 暴露最小接口：
   - `POST /chat/send` — 发送消息到林埃
   - `GET /chat/messages` — 获取最近对话
   - `POST /task/create` — 创建任务房间
   - `GET /task/status/:id` — 查询任务状态

**数据库迁移：**
```dart
// 新增迁移：lib/data/memory_v3/migrations/
// 1. 添加 TaskRooms 表
// 2. 添加 TaskArtifacts 表
// 3. 添加 TaskDecisions 表
// 4. 扩展 PersonaChatMessages.taskId（nullable）
```

### 5.2 Phase 2-5：完整功能

基于 Phase 1 的基础，逐步添加：
- 模型路由与 fallback
- Coding Agent 集成
- 并行执行
- 完整 UI

### 5.3 与 iGateway 的边界

```
┌─────────────────────────────────────────┐
│  白板（Here I am 桌面端）                │
│                                          │
│  用户 ↔ 林埃 ↔ Agent                    │
│         ↓                                │
│    TaskRooms（Memory V3）               │
│    PersonaChatMessages                   │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  外部工具（VS Code / 终端）              │
│                                          │
│  用户 → Claude Code（独立工作）         │
│         ↓                                │
│    iGateway.closeSession()               │
│         ↓                                │
│    ProjectMemoryItems（Memory V3）      │
└─────────────────────────────────────────┘
```

**清晰边界：**
- 白板内任务 → `TaskRooms`
- 外部工具 closeout → `ProjectMemoryItems`
- 两者都在 Memory V3，但表分离，语义不同

## 6. 风险与缓解

### 6.1 白板访问 Memory V3 的延迟

**风险：** 如果通过网络 Bridge，可能有延迟

**缓解：**
- Phase 1 先用本地 Bridge
- 后续考虑 Flutter Desktop 重写

### 6.2 表结构变更影响现有功能

**风险：** 新增 `PersonaChatMessages.taskId` 可能影响现有聊天

**缓解：**
- 字段设为 nullable
- 现有代码不读这个字段，不受影响
- 添加迁移测试

### 6.3 任务房间与 Project Memory 混淆

**风险：** 用户/开发者可能混淆两个概念

**缓解：**
- 文档明确区分
- 代码注释说明用途
- UI 上不暴露底层表名

## 7. 下一步行动

### 立即可做

1. **确认白板访问方式**
   - 用户确认：复用 Dev Room Bridge 还是本地 Bridge？
   - 如果本地 Bridge，先实现最小 HTTP Server

2. **数据库迁移**
   - 在 `lib/data/memory_v3/db/tables.dart` 添加 3 张新表
   - 扩展 `PersonaChatMessages` 添加 `taskId`
   - 写迁移脚本和测试

3. **验证现有 Bridge 接口**
   - 查看 Dev Room Bridge 的具体实现
   - 确认是否支持我们需要的操作

### 待讨论

1. **白板是 Web 还是 Flutter Desktop？**
   - 当前 MVP 是 Web
   - 长期是否迁移到 Flutter Desktop？

2. **Coding Agent 如何接入？**
   - 复用 Dev Room 的 Claude Code 集成？
   - 还是独立实现？

## 8. 修正后的 W5 实施计划

基于验证结果，W5 实施计划需要调整：

**Phase 1：基础架构（3-4 天）**
- [ ] 数据库迁移：新增 TaskRooms / TaskArtifacts / TaskDecisions
- [ ] 扩展 PersonaChatMessages.taskId
- [ ] 实现本地 Bridge 或确认复用 Dev Room Bridge
- [ ] 基础 CRUD 接口测试

**Phase 2：林埃决策层（2-3 天）**
- [ ] LinAiOrchestrator 实现
- [ ] 意图分类（规则 + 关键词）
- [ ] TaskRouter 固定路由

**Phase 3：模型路由（2-3 天）**
- [ ] ModelRouter 实现
- [ ] 配置文件读取
- [ ] Fallback 链

**Phase 4：Agent 集成（3-4 天）**
- [ ] 确认 Coding Agent 接口
- [ ] 结果压缩器
- [ ] Artifact 存储

**Phase 5：UI 集成（2-3 天）**
- [ ] 任务中心 UI
- [ ] 决策面板
- [ ] 悬浮球状态

---

## 附录：关键文件路径

```
Memory V3 表定义：
  lib/data/memory_v3/db/tables.dart

聊天表定义：
  lib/db/tables.dart

白板 MVP：
  desktop/whiteboard_mvp/

Dev Room Bridge（待确认）：
  可能在 lib/data/services/ 或独立进程

跨工具连续性：
  docs/companion-first/LIN_AI_CROSS_TOOL_CONTINUITY.md
```
