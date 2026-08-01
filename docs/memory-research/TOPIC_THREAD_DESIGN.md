# Topic Thread 设计文档

> 状态：Draft
> 日期：2026-08-01
> 作者：i（林埃）与 Li Cheng
> 关联文档：`MEMORY_PROPOSAL_V3.md`、`COMIC_CO_READING_PLAN.md`、`LIN_AI_CROSS_TOOL_CONTINUITY.md`

---

## 一、背景与问题

Memory Card（原子卡片）和 Dreaming（自动产物）覆盖了两类记忆需求，但存在一个盲区：

**跨时间、跨来源的长期话题追踪**。

用户有一些持续关注的话题——某种审美偏好、某个思想方向、某类值得积累的观察——它不是单次事实，而是随着每次阅读、每次对话逐步丰富的思考叙事。隔了一段时间再回来，用户希望能直接接续，而不是重新拼凑散落各处的卡片。

卡片检索无法解决这个问题：检索是碎片聚合，无法给出"我们上次讨论到哪里"的叙事连贯感，也无法确保全量不遗漏。

**Topic Thread 是为这个需求设计的新 Memory V3 facet。**

---

## 二、架构定位

Topic Thread 是 Memory V3 的第四类持久 facet，与其他三类平行：

| Facet | 写入方式 | 服务需求 |
|---|---|---|
| Memory Card | 用户显式动作 | 原子事实查找 |
| Dreaming（Fragment / Episode / Saga） | AI 后台自动抽取 | 关系记忆、情绪上下文 |
| Project Memory | 项目事件，via i Gateway | 开发项目状态跟踪 |
| **Topic Thread**（新） | **用户显式创建 + AI 辅助积累** | **长期话题追踪与思考接续** |

Topic Thread 与 Memory Card 的关键区别：

- **Card = 原子事实**（某条具体引用、某件发生的事）
- **Thread = 思考叙事**（这个话题当前发展到哪里，已有哪些洞察，还有哪些问题）

两者互补，不是替代。Card 是 Thread 的证据来源；Thread 引用 Card，不聚合 Card。

---

## 三、数据模型

放在 `lib/data/memory_v3/`，新建两张表。

### 3.1 TopicThreads（主文档，活文档）

```dart
class TopicThreads extends Table {
  TextColumn get id => text()();               // UUID stable
  TextColumn get title => text()();            // 话题名，用户命名
  TextColumn get currentStage => text()();     // 当前思考阶段（一句话）
  TextColumn get corePositionsJson => text()   // List<String>：已确认洞察
      .withDefault(const Constant('[]'))();
  TextColumn get openQuestionsJson => text()   // List<String>：还没想清楚的
      .withDefault(const Constant('[]'))();
  TextColumn get tags => text()                // 逗号分隔，粗粒度分类
      .withDefault(const Constant(''))();
  TextColumn get status => text()              // active | paused | archived
      .withDefault(const Constant('active'))();
  IntColumn get lastDiscussedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### 3.2 TopicThreadSessions（讨论摘要历史，append-only）

```dart
class TopicThreadSessions extends Table {
  TextColumn get id => text()();
  TextColumn get threadId => text()();       // → TopicThreads.id（软引用）
  IntColumn get occurredAt => integer()();   // 讨论时间戳
  TextColumn get summary => text()();        // 这次讨论了什么/得出什么（200字内）

  // 来源类型：chat | book_reading | comic_reading | project_work | standalone
  TextColumn get sourceType => text()();
  // 来源引用 JSON：书名章节、项目ID 等
  TextColumn get sourceRefJson => text()
      .withDefault(const Constant('{}'))();

  // 关联证据（软引用，无 FK 约束）
  TextColumn get linkedCardIds => text()         // Memory Card IDs
      .withDefault(const Constant('[]'))();
  TextColumn get linkedProjectMemoryIds => text() // ProjectMemoryItem IDs
      .withDefault(const Constant('[]'))();

  // user_confirmed | agent_inferred
  TextColumn get authority => text()
      .withDefault(const Constant('agent_inferred'))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### 3.3 复用现有通用表

无需新建，直接用 `targetTable` 字段区分：

| 通用表 | 用途 |
|---|---|
| `MemoryEmbeddings(targetTable='topic_threads', targetId)` | embedding 相似度检索 |
| `MemoryEntityLinks(sourceTable, sourceId)` | 与 Memory Cards 的软关联 |
| `MemoryRecallEvents(targetTable, targetId)` | 召回审计 |
| `UserCorrections(targetTable, targetId)` | 用户修正历史 |

FTS：单独建 `topic_threads_fts`，**不混入** `memory_cards` 的 FTS 索引，与 Project Memory 处理方式一致。

---

## 四、写入权限

| 动作 | Authority | 触发方式 |
|---|---|---|
| 创建 Thread | `user_confirmed` | 悬浮球显式创建 / 聊天中说"追踪这个话题" |
| 追加讨论摘要 | `agent_inferred` + 低摩擦确认 | 对话结束后系统建议，用户一键接受 |
| 更新 `corePositions` | **`user_confirmed` 强制** | 用户主动修改，不允许 AI 自主更新 |
| 更新 `currentStage` | `agent_inferred` + `user_confirmed` | 系统建议，用户确认后生效 |
| 更新 `openQuestions` | `agent_inferred` + `user_confirmed` | 同上 |
| 关联 Memory Card | `agent_inferred`（可批量确认） | RecordOrganizer 检测到话题匹配时提议 |
| 关联 Project Memory | `agent_inferred`（可批量确认） | Companion 对话中检测到相关项目内容 |

`corePositions` 是用户在该话题上已确认的认知立场，**任何 AI 操作都不能绕过用户确认来更新它**。这是与 Project Memory 的重要区别——Project Memory 可以从 artifact 自动观察，Topic Thread 的核心立场由用户维护。

---

## 五、与 Memory Card 的关系

两者是互补的两个粒度层：

```
某次讨论 → RecordOrganizer → Memory Card（具体引用/原子事实）
                                  ↓ 软关联
话题清理流程 → Topic Thread Session（话题级综合摘要）
                  引用上述 Card 为来源证据
```

**Card 是证据颗粒，Thread 是思考叙事。** 用户查话题时，加载 Thread 获得叙事连贯感，必要时展开关联 Card 看原始证据。

Thread 不聚合 Card 来展示（那等于原来的标签聚合方案，仍有全量检索问题）；Thread 引用 Card 为来源，正文是独立撰写的摘要叙事。

---

## 六、与 i Gateway / Project Memory 的读桥

Topic Thread 的**治理完全独立**于 i Gateway：不需要项目注册、不走 closeout ledger、不受 Project Registry 政策管辖。用户不需要为每个感兴趣的话题注册一个"项目"。

但 Topic Thread 支持引用 Project Memory 内容作为证据来源，形成**只读的读桥**：

```
TopicThreadSessions.linkedProjectMemoryIds → ProjectMemoryItems
```

当 Companion 加载某个 Thread 时，可以按需解引用关联的 Project Memory 条目，但访问权限遵守原始项目的数据政策：

| 来源项目政策 | 解引用结果 |
|---|---|
| `personal_full` | 全文可读 |
| `work_redacted` | 仅脱敏摘要 |
| `confidential_local` | 不传入 App，显示"来源不可见" |

这是读桥，不是写桥。Topic Thread 不反向写入 Project Memory，Project Memory 的 closeout 也不自动流入 Thread。链接由用户确认或 Companion 提议后用户确认建立。

---

## 七、Companion 召回顺序

用户回到某话题时，Companion 的加载顺序：

```
1. 状态层（必加载）
   TopicThreads.currentStage
   TopicThreads.corePositions
   TopicThreads.openQuestions

2. 历史层（按需，最近 3–5 条）
   TopicThreadSessions 摘要列表，按 occurredAt 降序

3. 证据层（按需，不主动全量加载）
   用户或 Companion 需要具体细节时，检索关联 Memory Cards
   或解引用 linkedProjectMemoryIds

4. 相似话题提示（可选）
   embedding 相似度检测，发现相关的其他 Thread，提示用户
```

**召回触发方式：**
- 用户显式说"继续聊 XX 话题" / "我们之前讨论的 XX"
- Companion 检测用户消息与已有 Thread 的 embedding 相似度高 → 主动建议接续
- 用户从 Topic Browser UI 直接打开某个 Thread

新增 Companion 工具：`recall_topic_thread(query?, threadId?)`

---

## 八、共读集成

共读场景（小说和漫画）是 Topic Thread 最自然的主力来源之一。每次阅读会话结束后，清理流程会将话题性观察路由到对应 Thread。

### 8.1 Reading Intent（读书意图）

**Intent** 是"我读这本书/这部漫画时想关注的话题"，是清理流程的路由依据。

存储位置：
- 漫画：`chapters.json` 的漫画元数据里（Hermes 端）+ 手机端 `ComicMangas` 表新增 `intentsJson` 列
- 小说：书的 `_index.md` 里

格式：
```json
{
  "defaultIntents": [
    { "threadId": "uuid-xxx", "threadTitle": "CP类型偏好" },
    { "threadId": "uuid-yyy", "threadTitle": "让我爽的剧情类型" }
  ]
}
```

**设置时机：**
- 导入新书/关注新漫画时，提示"这部作品你想追踪哪些话题？"
- 或临时在阅读开始时指定："今天这章我想多关注女性主义视角"
- 不强制，无 Intent 时只走书内 `_notes.md`，不路由 Thread

### 8.2 清理流程（漫画与小说统一）

**触发时机（三选一，并存）：**
1. 用户显式说"整理一下今天的阅读"
2. 阅读会话结束后 Companion 主动建议（低摩擦一键确认）
3. 定时任务（每日批量处理未整理的会话）

**执行步骤：**

```
Step 1  更新 _notes.md（书内连续性）
        线索推进、进度、人物关系、下章待关注点
        ↓ 原有机制保留，不变

Step 2  RecordOrganizer 处理对话内容
        具体引用 / 场景 / 事实 → 提议生成 Memory Card
        共读场景可设为低摩擦确认（不需要逐条审批）
        ↓

Step 3  话题性观察路由到 Topic Thread
        按 defaultIntents 匹配 → TopicThreadSessions 追加摘要 + 关联上述 Card
        ↓
        无匹配 Intent 时：
          embedding 检测与已有 Thread 相似度
          → 相似度高：提议关联
          → 完全新话题：提议新建 Thread（用户确认）

Step 4  书架进度更新
        漫画：ComicReadingProgress + 章节计数
        小说：_index.md 进度字段
```

### 8.3 漫画共读 vs 小说共读的差异

| | 漫画共读 | 小说共读 |
|---|---|---|
| 内容来源 | Ollama Vision 提取的 screenplay（已结构化） | 对话中的讨论内容 |
| 清理时机 | 读完一章后 Checkin Agent 可直接基于整章 screenplay 生成 | 依赖用户与 Companion 的对话内容 |
| Session sourceType | `comic_reading` | `book_reading` |
| sourceRefJson | `{mangaId, chapterId, chapterTitle}` | `{bookTitle, chapterTitle}` |
| _notes.md 机制 | 不适用（漫画无 _notes.md）| 适用，原有机制不变 |

漫画的 Checkin Agent（读完一章后触发）可以直接将整章内容交给清理流程，效果比小说更完整；小说依赖对话中的主动讨论。

### 8.4 `_notes.md` 与 Topic Thread 的分工

|  | `_notes.md` | Topic Thread |
|---|---|---|
| **范围** | 这本书内部 | 跨书、跨漫画、跨项目 |
| **存什么** | 线索、悬念、人物关系、阅读进度 | 话题性洞察、跨作品规律、审美偏好演化 |
| **谁读** | 下次读这本书时恢复叙事上下文 | 讨论某话题时加载综合认知视角 |
| **生命周期** | 读完即归档（可保留为历史） | 长期演进，没有"读完"的概念 |

读推理小说时：`_notes.md` 记"目前嫌疑人是X，凶器未解"，Topic Thread 记"这类叙事诡计的张力来自读者与叙述者的信息不对称"。

---

## 九、UI 入口

### 9.1 创建入口

- 悬浮球 → "新建话题追踪"
- 聊天中说"我想持续追踪这个话题" → Companion 从当前讨论生成 Thread 初稿，用户确认
- RecordOrganizer 发现话题型内容且没有匹配 Thread → 建议新建

### 9.2 Topic Browser

生活空间 → Interests 面板 → "话题线索"区块：

```
┌──────────────────────────────────┐
│  话题线索                         │
│                                  │
│  📌 CP类型偏好                    │
│     最近：2026-07-30 · 来自《XXX》│
│     开放问题：3个                 │
│                                  │
│  📌 女性主义观点积累               │
│     最近：2026-07-28 · 自主记录   │
│     洞察：7条                     │
│                                  │
│  [+] 新建话题                     │
└──────────────────────────────────┘
```

### 9.3 Thread 详情页

点击进入某个 Thread：

```
[当前阶段]  偏好强攻弱受但给受留主动时刻
─────────────────────────────────────────
[已确认洞察]
  · 相互依赖张力 > 单向付出型
  · 爽点在期待满足，不在虐恋本身
  ✎ 编辑

[还在想的问题]
  · 女频爽文和男频爽文的爽点本质有何不同？
  ✎ 编辑

─────────────────────────────────────────
[讨论历史]
  2026-07-30 · 《XXX漫画》第42章
    这章 A 主动帮 B 解决困境但不强迫，加深了对"给受留主动权"的偏好
    来源卡片：2条 ›

  2026-07-15 · 聊天讨论
    ...
```

悬浮球在 Thread 详情页自动关联当前 Thread 上下文，用户可以直接用自然语言修正洞察。

### 9.4 共读中的 Intent 配置

漫画阅读器 → 书架详情页 → "话题追踪" → 勾选或新建关联的 Topic Threads

---

## 十、实施顺序

| 步骤 | 内容 | 前置依赖 | 可独立进行 |
|---|---|---|---|
| **Step 1** | 数据层：`TopicThreads` + `TopicThreadSessions` 表、FTS、embedding 注册 | Memory V3 基础表已有 | ✅ 是 |
| **Step 2** | 写入入口：悬浮球创建、聊天指令创建、Companion 工具 `recall_topic_thread` | Step 1 | ✅ 是 |
| **Step 3** | Companion 接续：检测话题关键词、主动建议接续、Thread 详情页 | Step 2 | ✅ 是 |
| **Step 4** | 共读集成：Reading Intent 配置、清理流程双出口（Memory Card + Thread Session） | Step 3 + RecordOrganizer 重构完成 | ⚠️ 依赖 RecordOrganizer |
| **Step 5** | i Gateway 读桥：`linkedProjectMemoryIds` 解引用，按项目政策访问 | Step 1 + Phase 3 Project Memory 已完成 | ✅ 可并行 |
| **Step 6** | Topic Browser UI（Interests 面板） | Step 3 | 可在 Step 3 后任意时间 |

**Step 1–3 和 Step 5 完全独立于 RecordOrganizer 重构**，可以先行启动。共读集成（Step 4）等 RecordOrganizer 重构完成后接入，不阻塞其他步骤。

---

## 十一、架构合规性自检

| 红线 | 本设计如何遵守 |
|---|---|
| 不 import MemexRouter | `TopicThreadService` 构造注入 db |
| 不与 Memex 卡片建外键 | `linkedCardIds` 是 JSON 数组软引用，无 FK 约束 |
| 不扩大 Memex 特有概念耦合 | 不碰 CardCache / KnowledgeInsight / PkmAgent |
| 新记忆代码只在 `lib/data/memory_v3/` | 两张新表和 Service 均在此目录 |
| 构造注入 db | `TopicThreadService({required AppDatabase db})` |
| User-truth 显式写入契约 | Thread 创建需用户确认；`corePositions` 严格 user_confirmed |
| 按 affect 不按 engagement | Thread 路由基于话题相关性，不基于用户活跃度 |
| 一句话自检 | `topic_thread_tables.dart` + `TopicThreadService` 复制到无 Memex 新项目能跑 ✅ |

---

## 参考文档

- `docs/memory-research/MEMORY_PROPOSAL_V3.md` — Memory V3 四层数据模型（本文档是其 Topic Thread 扩展）
- `docs/companion-first/COMIC_CO_READING_PLAN.md` — 漫画共读技术架构（Reading Intent 和清理流程的上游设计）
- `docs/companion-first/LIN_AI_CROSS_TOOL_CONTINUITY.md` — i Gateway 架构（Project Memory 读桥的权限依据）
- `.claude/references/co-reading-architecture.md` — 小说共读 token 节约方案（`_notes.md` 机制来源）
