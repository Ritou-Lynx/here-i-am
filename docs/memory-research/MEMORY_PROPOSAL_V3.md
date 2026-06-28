# Here I Am 记忆系统方案 V3

> 日期：2026-06-28
> 状态：综合 V2、Codex Memory Card 细化讨论、`MEMORY_CONSTELLATIONS_STUDY.md` 三方后的合并版
> 与 V2 关系：保留 V2 的契约和检索方向，重写数据模型，引入自动产物四层，重新定义 Insight 体系
> 适用范围：数据模型 + 概念边界。**可施工 spec 还需补第十四节"MVP 工程开口"。**

---

## 一、定位

故我在的记忆系统目标是：

**用户自然生活和聊天，I 在合适的时候理解、记住、提醒、帮忙，但不把用户变成数据库管理员。**

为此整个系统建立在三条契约上（见第二节），并按四层数据模型组织（见第三节）。

V3 不替换 PRD V2，是 PRD 记忆章节的工程蓝本。落地施工时 PRD 中关于"卡片捕获 / Dreaming / 记忆栈"的描述需要按 V3 重写。

---

## 二、核心契约

### 契约 1：User-truth 只由用户显式动作产生

普通聊天**不自动生成 User-truth**。用户必须通过下面任一动作才能产生 Memory Card：

- 消息级"记录"按钮
- 悬浮球保存
- 明确自然语言指令（"记一下"、"加到日程"等）
- 外部数据流（截图 OCR、健康同步、账单导入等明确功能入口）
- 在 Memory Review 里把某条 Episode 升格成 Memory Card

Dreaming 产生的 Fragment / Episode / Saga **不进入 User-truth**，它们属于 I 的关系记忆（Insight 体系），跟 User-truth 在数据库和呈现层都隔离。

### 契约 2：用户主权高于审计完整性

用户编辑/删除任何内容后：

- I 的检索只读当前有效投影
- append-only 操作日志只对用户在"修订历史"页面可见，**任何 I 工具都不能读取**
- 已删除内容不进入任何召回、索引、summary、成长材料
- 用户对 AI 派生物（Episode、Saga、Entity、Summary Card 等）的修正记入 `user_corrections` 表，方案换代时必须遵守

### 契约 3：按 affect 不按 engagement

记忆系统的触发、召回、主动陪伴都不优化留存指标。

- Dreaming 触发条件由情绪/事件密度决定，不由"用户多久没回来"决定
- 主动触达由内部状态（重要事件提醒、关心信号）触发，不为唤回用户而设计
- 拒绝 "farewell-guilt"、"streak"、"未读提醒堆积"等留存暗黑模式

这条来自 kimi-core 的 affect-driven 原则，单独抽出来作为硬约束。

---

## 三、数据模型四层

```
┌──────────────────────────────────────────────────────┐
│ 索引 / 召回辅助层                                       │
│ memory_embeddings · FTS5 索引 · memory_recall_events │
└──────────────────────────────────────────────────────┘
                          ▲
                          │
┌──────────────────────────────────────────────────────┐
│ 自动产物层（Dreaming · Insight 来源）                  │
│ memory_fragments · memory_entities                   │
│ memory_entity_links · memory_episodes · memory_sagas │
└──────────────────────────────────────────────────────┘
                          ▲
                          │
┌──────────────────────────────────────────────────────┐
│ 用户确认资料层（Memory Card · User-truth 主体）        │
│ memory_cards · memory_card_sources                   │
│ memory_card_structured_fields · memory_card_relations│
│ memory_card_assets                                   │
└──────────────────────────────────────────────────────┘
                          ▲
                          │
┌──────────────────────────────────────────────────────┐
│ 原始资料层（无损保留 · 剥离基础）                       │
│ chat_messages · assets · asset_analysis              │
│ user_corrections · memory_card_operations            │
└──────────────────────────────────────────────────────┘
```

字段约定：

- **所有派生物表**带 `schemaVersion`、`generatedByVersion`、`userCorrected`
- **所有原始资料表**带 `schemaVersion`，字段只能新增（nullable），不能删除或重命名

---

## 四、Memory Card 表族

### 4.1 `memory_cards`

主表，当前有效卡片本体。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | 稳定标识 |
| `memoryScope` | text | `user_truth` 或 `script_summary`，仅两个值 |
| `type` | text | `fact` / `event` / `task` / `schedule` / `plan` |
| `title` | text | 系统识别字段，Summary Card 不显示 |
| `dropletLabel` | text | 2-4 字极短识别词，用于水滴/密集/3D 视图 |
| `presentationModule` | text (JSON) | Memory Summary Card 的 block 列表 |
| `retrievalText` | text | 给 I / embedding 读取的自然语言 |
| `valence` | real | -1.0 ~ 1.0，情绪坐标 |
| `arousal` | real | 0.0 ~ 1.0，情绪坐标 |
| `confidence` | real | 默认 1.0；外部导入或 OCR 推断可低于 |
| `status` | text | 仅 task/schedule/plan 用：`active` / `completed` / `cancelled` |
| `needsFollowUp` | text (JSON) | nullable，待 I 主动追问的字段清单，例 `[{field, question}]` |
| `createdAt` / `updatedAt` | integer | 系统时间 |

**生成规则**：

- 必需字段缺失时不静默保存，提示整理失败或保存为最简卡片
- 普通事实/事件不需要 `status`，删除即从当前集合消失，不通过 status 表达
- Summary Card 不强制显示 `title`，主要由 `presentationModule.blocks` 承载内容

### 4.2 `memory_card_sources`

原始输入上下文，每张卡有一条对应记录。

| 字段 | 类型 | 说明 |
|------|------|------|
| `cardId` | text | 关联 memory_cards.id |
| `rawInput` | text | 原始输入内容 |
| `recordedAt` | integer | 记录时间 |
| `recordedPlace` | text | 记录时地点，可空（普通聊天消息不默认采集） |
| `sourceRef` | text | 指向 asset.id / chat_message.id / 外部批次 id |

`rawInput` 默认不可编辑。如需修改通过"替换原始输入"重新整理整张卡。

### 4.3 `memory_card_structured_fields`

可选，机器计算字段，每张卡 0 或 1 条。

| 字段 | 类型 | 说明 |
|------|------|------|
| `cardId` | text | |
| `structuredFieldsType` | text | `expense_entry` / `sleep_record` / `reading_item` / `outfit_log` / `shopping_order` / `route_plan` / ... |
| `fieldsJson` | text (JSON) | 具体字段，按 type 不同 |
| `userCorrected` | bool | 用户改过的不被自动重生成覆盖 |
| `createdAt` / `updatedAt` | integer | |

`structuredFieldsType` 由 AI 根据内容判断，不强求所有 Memory Card 都结构化。

**业务时间字段统一通过 structuredFields 表达**，包括：

- `occurredAt` / `occurredEndAt`：事件发生时间
- `nextActionAt` / `nextActionDescription`：后续动作时间和说明（让 event 卡同时进 Schedule 面板）
- `dueAt`：task 截止
- `startAt` / `endAt` / `remindAt`：schedule 时间
- `paidAt`：expense 时间
- `sleepStart` / `sleepEnd` / `wakeDate`：睡眠时间

Schedule 面板的查询规则：**凡是 structuredFields 里包含未来时间字段（`nextActionAt` / `dueAt` / `startAt` / `remindAt`）的卡，都按时间排进 Schedule 面板**。一张 event 卡可以因此同时出现在 Memory Review（按时间倒序）和 Schedule 面板（按 nextActionAt）。

### 4.4 `memory_card_relations`

卡片之间显式关联，由用户或 AI 通过自然语言修正建立。

| 字段 | 类型 | 说明 |
|------|------|------|
| `fromCardId` | text | |
| `toCardId` | text | |
| `userCorrected` | bool | |
| `createdAt` | integer | |

关系不分类型。关联调整通过卡片页悬浮球自然语言完成，触发卡片重新整理流程。

### 4.5 `memory_card_assets`

Memory Card 与 Asset 多对多关系。

| 字段 | 类型 | 说明 |
|------|------|------|
| `cardId` | text | |
| `assetId` | text | |
| `role` | text | `source` / `evidence` / `display` |
| `createdAt` | integer | |

---

## 五、Dreaming 自动产物表族

### 5.1 `memory_fragments`

Dreaming 每次跑时从聊天里抽出的事实碎片，第三人称，单条原子。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `content` | text | ≤ 80 字 |
| `sourceMessageIds` | text (JSON) | 来源聊天消息 |
| `sourceScope` | text | `main_chat` / `script_session` |
| `emotionalWeight` | real | 0~1，用于检索权重和生命周期 |
| `status` | text | `active` / `consolidated` / `ignored` / `deleted` |
| `isUserTruthCandidate` | bool | Dreaming 觉得值得用户确认升格 |
| `generatedByVersion` | text | |
| `userCorrected` | bool | |
| `createdAt` | integer | |

**emotionalWeight 跟 valence/arousal 分开**：Fragment 数量大，单维度足够服务检索权重；Episode/Card 才打二维情绪坐标。

### 5.2 `memory_entities`

人物 / 地点 / 作品 / 项目 / 长期主题 / 设备。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `name` | text | 标准名 |
| `category` | text | `person` / `place` / `event` / `project` / `hobby` / `work` / `object` |
| `status` | text | `seed` / `active` / `merged` / `hidden` / `deleted` |
| `aliases` | text (JSON array) | |
| `overview` | text | 一句话概述 |
| `relationshipToUser` | text | `family` / `friend` / `colleague` / `self` / `other` |
| `firstMentionedAt` / `lastMentionedAt` | integer | |
| `fragmentCount` | integer | 证据数 |
| `mergedIntoId` | text | 被合并时指向新 entity |
| `generatedByVersion` | text | |
| `userCorrected` | bool | |

**seed → active 机制**：新名词先建 seed，证据累积到阈值（具体阈值见 MVP 工程开口）才毕业 active。孤立 seed 定期清理。避免随口提到的路人污染 entity 库。

### 5.3 `memory_entity_links`

Fragment / Memory Card / Episode 与 Entity 的多对多。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `sourceTable` | text | `memory_fragments` / `memory_cards` / `memory_episodes` |
| `sourceId` | text | |
| `entityId` | text | |
| `relation` | text | `mentioned` / `about` / `with` / `caused_by` / `located_at` |
| `confidence` | real | 链接置信度 |
| `createdAt` | integer | |

### 5.4 `memory_episodes`

同一 entity 下多个 fragment 凝结成的具体可回忆事件，第一人称叙事。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `primaryEntityId` | text | 主实体 |
| `narrative` | text | 第一人称叙事 |
| `sourceFragmentIds` | text (JSON) | 溯源 |
| `significance` | integer | 1-10 |
| `confidence` | text | `high` / `medium` / `low` |
| `valence` | real | -1.0 ~ 1.0 |
| `arousal` | real | 0.0 ~ 1.0 |
| `occurredAtRange` | text (JSON) | `{start, end}`，可空 |
| `status` | text | `active` / `hidden` / `stale` / `deleted` |
| `generatedByVersion` | text | |
| `userCorrected` | bool | |
| `createdAt` / `updatedAt` | integer | |

**生成条件**：某 entity 新增 active fragment ≥ 5，或 7 天保底（具体阈值见 MVP 工程开口）。

### 5.5 `memory_sagas`

跨 Episode 的长期叙事。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `title` | text | |
| `description` | text | 长期叙事 |
| `episodeIds` | text (JSON) | 来源 episode |
| `emotionalAxis` | text (JSON) | `{valence, arousal, connection}` 三维 |
| `status` | text | `active` / `hidden` / `merged` / `stale` / `deleted` |
| `generatedByVersion` | text | |
| `userCorrected` | bool | |
| `createdAt` / `updatedAt` | integer | |

`emotionalAxis.connection`：跟用户的情感连结强度 0~1，用于 Saga 在主动陪伴时的注入权重。

**Saga.description 的内容范围**包含两类，不局限于"趋势"：

- **状态趋势**：她的整体状态、关注点、行为模式怎么演变（如"最近她对通勤穿搭的关注在变多"）
- **互动模式**：她处理某类情境的方式 + 她希望 I 怎么回应（如"她说烦的时候更想被安静陪着，不要追问"）

后者是 I 学到的"应对参考"，**不进 User-truth**（不是用户确认的事实），但可以作为 Saga 内容的一部分被用户在 Memory Review 看到 / 编辑 / 删除。

一个主题可以有多条 Saga：状态 Saga 和互动 Saga 并存。

**生成条件**：新 episode ≥ 5 或每周一次。频率比 Episode 低，注入也罕见（只在反思 / 情绪 / 主动陪伴 / 深度谈话 / 睡前回顾时使用）。

Saga 被用户编辑/隐藏/删除后立即失效，相关召回不再返回。

---

## 六、原始资料与审计层

### 6.1 `chat_messages`

聊天消息流（继承现有结构）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `conversationId` | text | |
| `senderRole` | text | `user` / `I` |
| `content` | text | |
| `createdAt` | integer | |
| `attachmentAssetIds` | text (JSON array) | |
| `deletedAt` | integer | nullable |

普通消息**不默认采集地点**。仅在消息被保存为 Memory Card 时记录 `recordedPlace`。

### 6.2 `assets`

任何独立资源：图片、截图、音频、链接、健康同步批次、账单截图、订单。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `assetType` | text | `image` / `audio` / `link` / `health_sync` / `order` / `bill` / `file` |
| `storagePath` | text | 本地存储路径 |
| `url` | text | 外部 URL |
| `mimeType` | text | |
| `createdAt` | integer | |
| `deletedAt` | integer | nullable |
| `originatorRef` | text | 关联来源（聊天消息 id / 外部导入批次 id） |

**Asset 与 Memory Card 生命周期分开**：

- Asset 可以只存在聊天历史中，不进 Memory Card
- 删除 Memory Card 不删 Asset
- 删除聊天消息时如该 Asset 没有其他引用可一起删，否则提示联动影响
- Asset 删除主要通过自然语言命令完成，不提供常规独立删除按钮

### 6.3 `asset_analysis`

对 asset 的识别结果。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `assetId` | text | |
| `analysisType` | text | `image_label` / `ocr` / `audio_transcript` / `link_extract` / `link_summary` |
| `content` | text | |
| `modelProvider` / `modelName` | text | |
| `createdAt` | integer | |
| `userCorrected` | bool | |

挂在 asset 上而非 Memory Card 上，因为同一 asset 可能被多张卡引用。

### 6.4 `user_corrections`【剥离机制核心】

用户对任何 AI 派生物的修正记录。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `targetTable` | text | `memory_cards` / `memory_episodes` / `memory_entities` / `memory_sagas` / `asset_analysis` |
| `targetId` | text | |
| `field` | text | 改的字段名 |
| `oldValue` | text (JSON) | |
| `newValue` | text (JSON) | |
| `correctionType` | text | `edit` / `reject` / `merge` / `split` / `confirm` / `hide` |
| `createdAt` | integer | |

**这张表是"换方案不丢用户修正"的关键**。换代时新方案重生成派生物前必须先查这张表，对应字段有修正记录就用用户版本。

### 6.5 `memory_card_operations`

append-only 审计日志（继承现有 `SharedLifeEventOperations`，扩展字段）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `cardId` | text | |
| `operationType` | text | `create` / `update` / `delete` / `restore` / `correct` / `merge` / `split` / `derive` |
| `payload` | text (JSON) | |
| `sourceKind` | text | `tool_call` / `record_button` / `fab` / `natural_command` / `import` / `system` |
| `createdAt` | integer | |

**仅供修订历史页面、撤销、系统维护使用。I 的任何工具都不可读取。**

---

## 七、检索与召回

### 7.1 多路召回

| 路径 | 输入 | 输出 |
|------|------|------|
| FTS5 keyword | query | 命中文本的 cards / fragments / episodes / sagas |
| Vector similarity | query embedding | 语义相近的派生物 |
| Entity timeline | 提到的 entity | 该 entity 关联的所有内容时间线 |
| DB filter | type / time / status | 缩小候选集 |

### 7.2 Intent 驱动的融合排序

**核心原则：召回策略由 intent 决定，不是一套权重打天下。**

I 在执行 `memory_query` 前先根据当前对话上下文隐式判断 intent，按对应模板召回。intent 分类由 I 自己做，不暴露给用户作为显式参数。

**v1 四类 Intent**

| Intent | 触发示例 | 主注入 | 附带引用 | 二次取触发 | 召回风格 |
|--------|----------|--------|----------|------------|----------|
| **事实型** | "我妈住哪" / "我对花生过敏吗" | 1-2 条合并后的 Memory Card | 无 | 用户带情境追问 | 精准，不夹带 |
| **进度型** | "上次那个文章聊到哪" / "X 件事进展" | Memory Card + 相关 Episode | 关联 Asset | 用户要原文 | 中等聚焦 |
| **反思型** | "我最近是不是被 X 缠住了" / "我们关系怎么样" | Saga | Saga 引用的 Memory Cards / Episodes | 用户要具体细节 | Saga 为主，证据按需展开 |
| **情绪型** | "我今天有点烦" / "我有点累" | Memory Card + Episode + Saga + Fragment 全上 | 较少 | 用户深入追问 | 广度优先 |

**通用规则（所有 intent 共享）**

- 已删除 / `status=deleted` / `status=hidden` 内容硬过滤为 0
- 已合并的旧版本（Memory Card 在 merge 后旧 id）硬过滤为 0
- `userCorrected=true` 的字段优先于自动生成版本
- novelty penalty：频繁被命中的通用碎片降权（防止"妈妈住在杭州"在所有问题里都召回）
- 高 `emotionalWeight` 的 fragment 保留更久（生命周期慢衰减）

**主注入 vs 附带引用 vs 二次取**

为控制 token，召回结果分三层：

| 层 | 形式 | I 能看到 |
|----|------|----------|
| 主注入 | 完整内容（retrievalText / narrative / description） | 全文，可引用 |
| 附带引用 | `[id, title, scope, 一行摘要]` 列表 | 知道存在，看不到全文 |
| 二次取 | 不返回，只在 I 主动调用 `expand_memory(id)` 时给 | 按需展开 |

I 默认用主注入回答；如果用户追问具体细节、要原文、要数字，I 主动用 `expand_memory` 工具二次取。

**Saga 已吸收的低层证据默认不重复注入**

Saga 已经把它引用的 Episodes 和 Memory Cards 概括了。反思型 intent 下，Saga 进主注入，它的 episodeIds / 关联 cards 只进附带引用——不重复加载内容。

**类型差异化的时间衰减（在对应 intent 内生效）**

| 类型 | 时间衰减 |
|------|----------|
| `fact` | 几乎不衰减 |
| `event` | 中等衰减，但高 `emotionalWeight` 长期保留 |
| `schedule` | 看 upcoming proximity（未来越近排越前） |
| `task` | 看 due + status |
| `relationship episode` | 情绪 + significance 优先 |
| `saga` | 只在反思 / 情绪 / 主动陪伴 intent 下高权重 |

### 7.2.1 v2 / v3 检索差异

| 维度 | V2 | V3 |
|------|----|----|
| 排序模式 | 单一公式 + entity_type 权重 | 按 intent 切换模板 |
| Intent 判断 | 不存在 | I 隐式分类 |
| Saga 处理 | 跟 entity 并列召回 | Saga 已吸收的证据默认折叠为引用 |
| 注入分层 | 平铺 | 主注入 / 附带引用 / 二次取三层 |

### 7.3 注入格式

I 检索命中后注入时**分层标记来源**，每条带 ID：

```
[用户确认资料]
- 妈妈住在杭州，最近身体不太好。 #u123

[你们的关系记忆]
- 周三晚上她提到妈妈复查的事，话说到一半就停了。 #e456

[长期脉络]
- 最近两个月她对妈妈身体状况的关注一直在变重。 #s9
```

规则：

- User-truth 用事实口吻
- Relationship episode 用第一人称叙事
- Saga 只在必要时出现，不每轮注入
- 每条带 ID，模型可追溯
- I 不能把"关系记忆"或"长期脉络"误用为"已确认事实"

### 7.4 `memory_recall_events`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text | |
| `targetTable` | text | `memory_cards` / `memory_episodes` / `memory_sagas` |
| `targetId` | text | |
| `chatMessageId` | text | 哪次召回 |
| `query` | text | |
| `score` | real | |
| `createdAt` | integer | |

用于 novelty penalty 和"最近被想起"分析。

### 7.5 `memory_embeddings`

| 字段 | 类型 | 说明 |
|------|------|------|
| `targetTable` | text | |
| `targetId` | text | |
| `vector` | blob | |
| `provider` | text | |
| `model` | text | |
| `dimension` | integer | |
| `contentHash` | text | 用于失效判断 |
| `updatedAt` | integer | |

内容变更或模型切换时根据 contentHash 标 stale 并重算。

### 7.6 FTS5 索引

对以下字段各建一个 FTS5 表：

- `memory_cards.retrievalText`
- `memory_episodes.narrative`
- `memory_sagas.description`
- `memory_fragments.content`

---

## 八、呈现层

### 8.1 概念边界

用户面对的世界只有两类内容：

| 类别 | 是什么 | 谁产生 | 视觉容器 |
|------|--------|--------|----------|
| **User-truth** | Memory Card | 用户主动确认 | Summary Card |
| **Insight** | 一切 AI 自动整理出来的观察/叙事/聚合 | I 自动生成 | 各自专用容器 |

### 8.2 Memory Review

**仅放 Memory Card**，使用 Summary Card 呈现。

- 默认按 `updatedAt` 倒序
- 是"我确认过的事实质检台"
- 点击进入 Full Detail View
- 不混 Episode / Saga / Entity 详情

### 8.3 Insight 体系

**所有 AI 生成的非用户确认产物归 Insight。** 包括：

- 时间趋势（Schedule 面板）
- 财务统计（Ledger 面板）
- 健康分析（Health 面板）
- 阅读 / 兴趣聚合（Reading 面板）
- **Entity 详情**（按人物/地点/项目聚合 User-truth + Episode + Saga + Asset）
- **Episode**（关系经历，第一人称日记片段感）
- **Saga**（长期叙事，长篇形态）

Insight 各产物有自己的视觉容器，**不复用 Memory Summary Card**。具体设计待 MVP 阶段单独讨论。

入口：

| 想看什么 | 从哪进 |
|----------|--------|
| 我确认过的事实 | Memory Review / 各功能面板 / Memory Space 3D |
| 关于妈妈的所有内容 | 在 Memory Card / 聊天里点 entity 标签进入 entity 详情 |
| 上次牙医那件事 | 在 entity "牙医" 详情里，或聊天里召回时附显示 Episode |
| 这段时间的关系脉络 | Insight 面板里的 Saga 列表，或 I 在睡前陪伴主动提及 |
| 最近 I 是怎么理解我们的 | Insight 面板 / 主动陪伴时 I 引用 |

Entity / Episode / Saga 没有独立主导航 tab，都从内容关联或 Insight 面板进入。

### 8.4 Memory Space 3D

**只渲染 `memory_cards`**。

| 轴 | 来源 |
|----|------|
| Z 轴 | `source.recordedAt`（记录时间） |
| X 轴 | `arousal`，渲染时映射：`x = (arousal - 0.5) * 2` |
| Y 轴 | `valence` |

- 不存空间坐标，运行时计算
- `dropletLabel` 用于空间点的极短识别
- Episode / Saga 不进 3D 空间

### 8.5 Full Detail View

Memory Card 详情页应含：

- Memory Summary Card 内容编辑区
- 原始输入区（`rawInput` + `recordedAt` + `recordedPlace` + `sourceRef`）
- 外部内容识别结果区（`asset_analysis`，可展开）
- structuredFields 编辑区（按 `structuredFieldsType` 渲染对应业务表单）
- 情绪定位编辑区（二维面板拖动，不显数字）
- 相关内容区（横向展示相关 Memory Summary Card）
- 操作历史区

### 8.6 卡片页悬浮球

- 一个悬浮球，一个输入框
- 不让用户预先选择"修正 / 聊天"
- 默认语义：对当前 Memory Card 说话
- 系统判断：修正 / 补充 / 关联调整 / 聊天 / 新建另一张卡
- 修改后给轻反馈，意图不明确时再追问

---

## 九、Record Organizer 实现规范

Record Organizer 是 Memory Card 的写入端实现。所有显式记录入口（消息记录按钮 / 悬浮球 / 自然语言 "记一下" / 外部数据流）的整理都由它执行。

### 9.1 身份与边界

- Record Organizer 是事实记录整理器，不是聊天助手
- 用户已经显式决定要记录这条 input，Record Organizer **不判断要不要记，只判断怎么记**
- 工作产物是结构良好的 Memory Card，包含完整字段、entity links、必要的合并 / 拆分判断

### 9.2 核心约束

| 约束 | 说明 |
|------|------|
| 不验证真伪 | 不核实 raw input 客观真假，措辞保留传闻语境（用"她说"，不去掉限定词） |
| 不补充推测 | 用户没说的信息不补全，不脑补 |
| 不静默猜测 | 关键字段缺失时写入 `needsFollowUp`，由 I 后续追问 |
| 主语不限 | 用户显式记录的内容不论关于谁都进 User-truth |

### 9.3 字段决策规则

**`type` 五选一**：
- `fact`：稳定事实（"妈妈住杭州"）
- `event`：发生过的事（"今天汇报被批评"）
- `task`：用户要做的事（含"记住 X"这类）
- `schedule`：有明确时间的日程
- `plan`：尚未落实成 task / schedule 的意向

**`title`**：截原文或简化，不必精心润色（用户看不到，给 AI 检索用）

**`dropletLabel`**：2-4 字，**抽事件本质而非泛化**（"汇报打回" 不是 "工作"）

**`presentationModule`**：根据内容组织 text / quote / number / table / media / linkAttachment 等 block，**不强制显示 title**

**`retrievalText`**：自然语言一段，给 I 检索命中后阅读，**保留传闻语境**

**`valence` / `arousal`**：v1 用绝对打分；v2 阶段补 `user_emotion_baseline` 做相对校准（MVP 不做）

**`structuredFieldsType` + `structuredFields`**：
- 内容明显属于某领域（消费 / 睡眠 / 阅读 / 穿衣 / 购物 / 路线）时设置
- 业务时间字段（`occurredAt` / `nextActionAt` / `dueAt` / `startAt` / `paidAt` / `sleepStart` 等）统一放这里
- event 卡里如果有后续动作（"下周再汇报"），用 `nextActionAt` + `nextActionDescription` 表达，**不拆卡**

**`needsFollowUp`**：JSON `[{field, question}]`，关键字段缺失时填，由 Chat agent 下次接话时查询并追问

### 9.4 拆分规则

单 input 默认生成一张卡。仅在以下情况拆成多张：

- 内容明显是多个**语义独立**的事实（不同主题、不同 entity、不同后续可能性）
- 例："午饭跟小红吃了麻辣烫花了 78，她跟我说她男朋友要外派了" → 两张：午饭消费 + 小红的事

拆出的多张卡之间**不自动建** `memory_card_relations`，除非确实有强引用关系（用户明确说"那件事的后续"等）。

### 9.5 Entity 处理

抽取**稳定存在的实体**作为 entity：

- ✅ 人物、地点、作品、项目、长期主题、设备、疾病
- ❌ 临时行为 / 一次性事件（"复查" 不算，"高血压" 算）

**用户显式记录关联的 entity 默认 `status=active`**，绕过 seed 阶段。Dreaming 自动产出的 entity 才默认 seed。

用 `memory_entity_links` 把 Memory Card 直接 link 到 entity，**不需要走 fragment 中间层**。区分 relation 类型（`mentioned` / `about` / `with` / `caused_by` / `located_at`）。

### 9.6 合并 / 去重

写入前用 retrievalText embedding + entity 重叠度检索已有 Memory Card。

发现同一事实的旧版本（如"妈妈住杭州" vs "妈妈住杭州西湖区文一路"）：

- **不自动合并**
- 把合并建议写入下次 Chat 上下文，由 I 在下次接话时把建议提给用户
- 用户确认后才执行合并操作（`operationType=merge` 写入 operations，旧卡 status=deleted）

### 9.7 Followup 机制

`memory_cards.needsFollowUp` JSON 字段，结构 `[{field, question}]`。

**同步路径**（chat 内触发的记录）：
- Record Organizer 发现缺失 → 直接把信息抛回 chat 上下文 → I 立即追问 → 用户答 → 再调 Record Organizer 补字段 → 保存
- 不需要落 `needsFollowUp` 字段（同步完成即可）

**异步路径**（悬浮球记录 / 外部数据流）：
- Record Organizer 保存为带 `needsFollowUp` 的卡
- Chat agent 每次接话前 query `needsFollowUp != null` 的最近 N 张卡，挑一条追问
- 用户答了就调 Record Organizer 补字段，清空对应条目

### 9.8 边界情况

- **信息密度极低的 raw input**（"周末" / "今天"）：保存为低 confidence Memory Card + `needsFollowUp` 追问"你是想记什么具体的事吗？"，不静默丢弃
- **纯抽象状态**（"今天有点累"，且没有具体事件）：用户既然显式记录就保存，作为 event 类型 + valence 偏负，retrievalText 直接用原文；如果之前有相关事件背景可在 retrievalText 里补充
- **input 极短 + entity 不明 + 无业务字段**：标 `confidence < 0.7`，等用户后续编辑或追问后再提升

### 9.9 v1 → v2 优化清单（暂不做）

- `user_emotion_baseline`：维护用户最近 N 条卡的 valence / arousal 均值 / 方差，校准 Record Organizer 的绝对打分
- 自动合并阈值：当 embedding cosine > 阈值 + entity 重叠 > 阈值时，跳过"询问用户"步骤直接合并
- 跨 input 的事件去重：连续两次 input 内容相同（误操作）自动 dedupe

---

## 十、Dreaming 后台任务设计

### 10.1 四层触发

| 层 | 频率 | 任务 | LLM | 成本 |
|----|------|------|-----|------|
| Immediate | 用户保存立即触发 | Record Organizer / projection 重建 / 索引更新 | 是 | 中 |
| Lightweight tick | 前台 / 后台短任务 | FTS 更新 / 状态过期 / 字面 entity 链接 / stale 标记 / novelty 计数 | 否 | 极低 |
| Daily Dreaming | 每日夜间 / 充电时 / 用户空闲 | Fragment 抽取 / Episode 凝结 / entity overview 更新 | 是 | 中 |
| Deep Dreaming | 每周或阈值 | Saga 编织 / 长期关系模式 / entity 概述再生成 | 是 | 高 |

### 10.2 关键原则

- LLM 调用集中到低频批处理，控制成本和耗电
- Daily/Deep Dreaming 优先在充电 + Wi-Fi + 夜间 + 用户空闲时跑
- 任何一次 Dreaming 失败不影响下次重试
- Lightweight tick 任何环境都可以跑，因为不调 LLM
- 触发不由 engagement 信号驱动（契约 3）

### 10.3 模型配置

按功能切分（不按 agent），跟用户配置体系对齐：

| 功能配置入口 | 用在 |
|---|---|
| **记忆抽取** | Fragment 抽取、Record Organizer 的字段提取 |
| **记忆叙事** | Episode 凝结、Saga 编织 |

默认推荐：
- 记忆抽取：便宜模型（DeepSeek / Gemini Flash 类）
- 记忆叙事：主模型（叙事质量影响 I 的人格连续性）

用户可在配置中改任一项。具体配置 UI 由 PRD 模型配置章节决定。

### 10.4 Fragment 抽取边界

- **AI 自己的发言**：只抽 I 对用户 / 关系的观察、担忧、强烈情感；不抽普通回应、信息转述、工具调用确认
- **高情绪信号优先**：检测到强情绪关键词的对话段单独优先抽取，`emotionalWeight` 标高
- **单批上限**：60 条 / 最多连续 5 批（控制成本和请求体大小）
- **抽取前先检索已有 fragments**：避免重复写入

### 10.5 Episode 凝结边界

- **默认单 entity**：按主 entity 凝结
- **允许跨 entity 例外**：LLM 判断"本质是一次具体事件"时允许（如"她跟小红那次推心置腹"），多 entity 都通过 `memory_entity_links` 关联
- **凝结后 fragment 状态**：标 `consolidated`，仍可被检索但权重降低（保留以备 Episode 写歪时核对）
- **叙事口吻**：默认写实型，必要时加反思型；**不写抒情型**
- **保留 sourceFragmentIds**：完整溯源

### 10.6 Saga 编织边界

- **一个主题允许多条 Saga 并存**：状态趋势 Saga / 互动模式 Saga / 重要事件叙事 Saga 等可同时存在
- **更新策略**：增量改写当前 Saga（覆盖 description），同时把旧版复制到 `memory_saga_snapshots` 表存档（不参与检索，只在用户查看历史时拉出）
- **时间跨度无硬上限**：但 description 必须带"覆盖时段"（如"这一段叙事覆盖 2026-04 到 2026-07"）
- **写歪防护**：Saga 写完后给 I 一个 sanity check prompt，问"这段叙事是否违反 affect-driven 契约 / 是否在替用户做决定 / 是否把 I 的推测说成事实"

### 10.7 触发阈值

**Daily Dreaming**：
```
触发 = (charging AND wifi AND idle > 30min)
     OR (idle > 4 hours)
优先时间窗 = 22:00-06:00
频率上限 = 1 次/天
```

**Lightweight tick**：
```
前台每 15 分钟 + 用户消息后立即触发一次
后台不跑
```

**Entity seed → active**：
```
seed → active = (fragmentCount >= 3)
              AND (lastMentionedAt - firstMentionedAt >= 2 days)
用户显式记录关联的 entity 直接 active，跳过 seed
```

**Episode 凝结**：
```
凝结 = (entity.newActiveFragments >= 5)
     AND llm.judge("are these fragments about one specific event?") == true
     AND llm.score(significance) >= 5
```

**Saga 编织（Deep Dreaming）**：
```
编织 = (theme.newEpisodes >= 5)
     AND (timeSpan >= 14 days)
     AND (lastSagaUpdate < (now - 7 days))
```

### 10.8 Dreaming 处理流程

```
Daily Dreaming run:
  1. 读取上次 Dreaming watermark 之后的 chat_messages
  2. Fragment 抽取（便宜模型）→ memory_fragments
  3. Entity 链接（轻量 LLM 或规则）→ memory_entity_links
  4. seed entity 评估：达到阈值 → active
  5. Episode 凝结判断：active entity 下新增 fragment ≥ 阈值且属于同一具体事件 → 写入 memory_episodes
  6. 已凝结 fragments 标记 status=consolidated
  7. 更新 watermark
```

```
Deep Dreaming run（每周或阈值）：
  1. 扫描 active entities 的最近 episodes
  2. Saga 编织：发现长期主题 / 模式变化 → 写入或更新 memory_sagas
  3. entity overview 重写
  4. 失效 episode / saga 标 stale
```

---

## 十一、用户修正与数据剥离

### 11.1 剥离对象

| 层 | 是否可剥离 | 处理 |
|----|------------|------|
| 原始资料（chat_messages / assets / asset_analysis） | 无损保留 | 字段只能新增 nullable |
| 用户修正记录（user_corrections） | 无损保留 | 完整迁移 |
| 用户确认资料（memory_cards 及表族） | 部分剥离 | 用户编辑过的字段保留，AI 派生字段可重生成 |
| 自动产物（fragments / entities / episodes / sagas） | 完全可重生成 | 换代时全部丢弃重跑 |
| 索引（embeddings / FTS / recall_events） | 完全可重生成 | 不导出，重建即可 |

### 11.2 导出格式

```
export/
  原始资料/                     # 永远无损
    chat_messages.jsonl
    assets.jsonl
    asset_analysis.jsonl
    user_corrections.jsonl
    memory_card_operations.jsonl
    media/                     # 实际媒体文件
  
  用户确认资料/                  # 可选
    memory_cards.jsonl
    memory_card_sources.jsonl
    memory_card_structured_fields.jsonl
    memory_card_relations.jsonl
    memory_card_assets.jsonl
  
  自动产物/                     # 可选，可重生成
    memory_fragments.jsonl
    memory_entities.jsonl
    memory_entity_links.jsonl
    memory_episodes.jsonl
    memory_sagas.jsonl
```

每个 jsonl 头部带 schemaVersion 注释。

### 11.3 换方案重生成流程

```
1. 导出 portable 数据包（原始资料 + user_corrections）
2. 新方案部署，schemaVersion = N+1
3. Record Organizer / Dreaming 跑新方案重建：
   - 读 portable 数据包
   - 对每条 Memory Card / Episode / Saga 生成前查 user_corrections
   - 对应字段有修正记录 → 用用户版本
   - 其余字段按新方案生成
4. 旧派生物（schemaVersion=N）可选保留只读或删除
```

---

## 十二、v2 → v3 主要变更

| 类别 | V2 | V3 | 原因 |
|------|----|----|------|
| Memory Card 内部结构 | 单 `narrative` + `structuredData` | `presentationModule` + `retrievalText` + `structuredFields` 独立表 + `dropletLabel` | Codex 讨论：展示 / 检索 / 计算 / 极短识别职责分离 |
| Asset 层 | 无，原始材料绑在 sourceRef | 独立 `assets` + `asset_analysis` + `memory_card_assets` | 多卡共享同一图片、删除联动、导出迁移 |
| `domain` 字段 | 核心字段（primaryDomain + facets） | 取消，由 type + structuredFieldsType + panel 派生 | 面板未来会变，硬绑死会伤数据 |
| 自动产物 | 没有 Fragment / Entity / Episode / Saga 分层 | 全部引入（来自 MEMORY_CONSTELLATIONS_STUDY） | 单层 Dreaming 太抽象，缺中间粒度 |
| 凝结产物 | `SharedLifeSummaries` 单一表 | 拆为 Episode（具体经历） + Saga（长期叙事） | Episode 服务"我们经历过什么"，Saga 服务"长期主题" |
| Insight 定义 | V2 没明确 | 所有 AI 生成的非用户确认产物（含 Episode / Saga / Entity 详情 / 各面板分析） | 用户面对的世界只两类：User-truth 和 Insight |
| `user_corrections` 表 | 无 | 新增，剥离基础 | 让"换方案不丢用户判断"在工程上可实现 |
| `memory_recall_events` 表 | 无 | 新增，novelty penalty | 避免通用碎片污染所有查询 |
| Saga 可见性 | summary 给用户看（带"AI 分析"标记） | Saga 可见可改 | 初期需要看着没跑偏，AI 私密日记不是当前阶段重点 |
| `timeConfidence` 等冗余字段 | V2 保留 | 取消 | 字段只服务 AI 工作；模糊就保持模糊 |
| `tags` | V2 部分保留 | 完全不做 | 用户不该被迫维护标签；AI 整理用内部分类 |
| 触发分层 | 三层（阈值 + 保底） | 四层（Immediate + Lightweight tick + Daily + Deep） | 移动端必须分轻重 |
| 注入格式 | 未明确 | 分层标注来源 + 带 ID | 防止模型把推测当事实 |
| `memoryScope` 字段 | 无 | `user_truth` / `script_summary` 两值 | 契约层的字段保障 |
| `confidence` 字段 | 无 | 有 | 区分用户确认资料与外部导入推断 |
| affect vs engagement | 未提 | 写入契约 3 | 借鉴 kimi-core，陪伴 app 行业默认陷阱 |

---

## 十三、不在本次范围

- **Insight 各产物的具体展示设计**（Episode 卡 / Saga 卡 / Entity 详情卡 / 各面板图表）
- **游戏 / 剧本存档结构**（独立 save file，不复用 Memory Card）
- **Memory Space 3D 渲染细节**（视觉、交互、性能）
- **观察面板的具体功能**（Schedule / Ledger / Health / Reading 等）
- **主动陪伴层**（check-in、call、Saga 何时注入）
- **现有 ConversationCaptureService 的完整重构方案**（仅在第十四节点出方向）

---

## 十四、MVP 工程开口（待讨论）

V3 是数据模型 + 概念边界，**不是可施工 spec**。下面是开 MVP 之前必须补的工程决策，按缺口大小排序。

### A. 大缺口（不补无法开始 MVP）

1. **检索融合 v1 公式（骨架已定，权重值待定）**
   - ✅ 骨架已定：Intent 驱动的四类召回模板（见 § 7.2），主注入 / 附带引用 / 二次取三层
   - ⏳ 还需补：每类 intent 内的具体权重值（关键词 / 向量 / entity timeline / 时间衰减 / 情绪权重 / novelty penalty）
   - ⏳ 还需补：Intent classifier 的实现方式（独立模型 prompt？还是写进 memory_query 工具描述让 I 自己判断？）
   - ⏳ 还需补：不同 type（fact / event / schedule / task）的时间衰减系数

2. **Record Organizer 的 prompt 草案（规范已定，prompt 落地待写）**
   - ✅ 规范已定：见 § 9 完整实现规范（type 决策、拆分规则、entity 处理、合并去重、followup 机制、边界情况）
   - ⏳ 还需补：把 § 9 翻译成实际的系统提示词文本
   - ⏳ 还需补：用真实样例对 prompt 做迭代调优

3. **Dreaming agent 的 prompt + 模型选择（规范已定，prompt 落地待写）**
   - ✅ 规范已定：见 § 10.3–10.6（模型配置、Fragment / Episode / Saga 三段边界）
   - ⏳ 还需补：把规范翻译成实际 Dreaming agent 系统提示词文本（Fragment / Episode / Saga 三套）
   - ⏳ 还需补：用真实聊天数据做 prompt 迭代

4. **触发条件具体阈值（已定）**
   - ✅ 完整阈值见 § 10.7：Daily Dreaming / Lightweight tick / Entity seed→active / Episode 凝结 / Saga 编织
   - ⏳ MVP 早期实测后可能调整数值

5. **现有 `SharedLifeEntities` → `memory_cards` 的迁移路径（已定）**
   - ✅ 完整迁移与目录组织策略见 § 15：物理隔离 + 渐进切换 + 不迁移历史数据 + 6 阶段切换顺序 + roadmap 末期清扫
   - ⏳ 还需补：具体的 Drift migration 代码 + ConversationCaptureService 关闭的 PR

### B. 中等缺口（可以 MVP 早期补，但要先决定方向）

6. **本地 embedding 在 Android 上的实测可行性**
   - bge-m3 / 其他轻量模型在 Android 包体多大、首次加载多久、推理速度
   - 不行就要做云 API 兜底方案
   - 工程探索题，要先做技术验证

7. **Insight 体系最小集**
   - MVP 要不要 Saga？还是只做 Fragment + Episode？
   - 要不要 Entity 详情视图？
   - 主动陪伴时 Saga 注入要不要做？
   - Memory Review 里"待审"信号怎么呈现

8. **Memory Card 里 "提到的 entity" 怎么呈现**
   - 标签？高亮？hover 卡片？
   - 直接决定 entity 入口好不好用

9. **暴露给用户后的"待审"信号设计**
   - 哪些情况需要在 Memory Review 高亮？（低 confidence？AI 不确定？关联未确认 entity？）
   - 用户怎么知道 I "理解错"了

### C. 小缺口（V3 文档里直接定，或在 MVP 实现时一次性决定）

10. `memory_cards.confidence` 不同 sourceKind 的默认值（record_button / fab / natural_command / health_import 各自给什么）
11. `memory_episodes.occurredAtRange` 怎么从 fragments 推断（最早 + 最晚的 fragment recordedAt？还是 LLM 推断？）
12. `memory_entities.relationshipToUser` 枚举范围是否够（家人 / 朋友 / 同事 / 自己 / 其他）
13. 已删除内容如何确保不进入任何召回（在 SQL 层加 status filter，还是在投影层删除？）
14. Asset 删除时如何回收存储（立即删 / 标记后定期清理）
15. 用户编辑 `presentationModule` 后 `retrievalText` 重新生成的具体触发点

---

## 十五、迁移与目录组织

不新建仓库，不重命名磁盘文件夹。记忆系统在现有代码库内重写，**物理隔离 + 渐进切换**，过渡期间新旧并存。

### 15.1 目录组织

新的记忆系统全部在 `lib/data/memory_v3/` 下：

```
lib/
  data/
    services/
      shared_life_memory_service.dart    # 旧，@deprecated，逐步删除
      conversation_capture_service.dart  # 旧，@deprecated，逐步删除
      record_organizer_service.dart      # 旧版（如有），@deprecated
      ...
    memory_v3/                            # 新目录，所有 V3 代码
      README.md
      models/                             # Dart 数据模型
      db/                                 # Drift 表定义 + DAO
        tables.dart
        dao/
      services/                           # 业务服务层
        record_organizer_service.dart
        dreaming_orchestrator_service.dart
        memory_query_service.dart
        user_correction_service.dart
      agents/                             # AI agent 实现
        record_organizer_agent/
        dreaming_agent/
        prompts/
      retrieval/                          # intent classifier + 排序 + embedding
```

### 15.2 数据库共存策略

- 旧表（`SharedLifeEntities` / `SharedLifeEventOperations` / `KnowledgeInsights` 等）保留
- **不迁移历史数据**——用户已清空旧记忆，V3 从零开始
- 新表（`memory_cards` / `memory_episodes` 等）作为 Drift migration 加入现有 db
- 两套表共存到所有 UI 切换完成

### 15.3 渐进切换顺序

按依赖关系切：

1. **Asset 层**（最底层）
2. **Memory Card 写入端**（Record Organizer + 记录入口）
3. **检索端**（Memory Card 召回 + intent 模板）
4. **Memory Review UI**
5. **Dreaming 自动产物**（Fragment / Episode / Saga）
6. **Insight 体系 UI**

每切完一段，旧的对应代码可以删。

### 15.4 仓库与本地路径

- **本地文件夹保持 `D:\memex\`**——重命名代价大（影响 `.claude` session、memory、scheduled tasks、Codex 项目数据）
- **git remote 改为 hereiam 独立仓库**：
  ```
  git remote rename origin memex-fork
  git remote add origin <hereiam-url>
  git push -u origin personal-lab:main
  ```
- **保留 Memex upstream remote**（只读），需要时手动 cherry-pick 基础设施 fix
- 仓库身份从 Memex fork 升级为独立产品 Here I am

### 15.5 防止 AI 写代码污染旧路径

在 CLAUDE.md 加硬规则：

> **任何新增记忆相关代码只允许在 `lib/data/memory_v3/` 下；旧 `lib/data/services/shared_life_*.dart` 和 `conversation_capture_service.dart` 等只能改 @deprecated 标记或删除，不允许扩展功能。**

旧文件加文件头注释 `// LEGACY - 不再扩展，逐步删除`。

### 15.6 旧代码清理（roadmap 最后阶段）

所有 UI 入口切换到新系统后，一次性删除：

- `lib/data/services/shared_life_*.dart`
- `lib/data/services/conversation_capture_service.dart`
- 旧版 `record_organizer_service.dart`（如有）
- `lib/agent/conversation_capture_agent/`
- `lib/agent/card_agent/`（已冻结）
- 旧 Drift 表通过 migration 删除（或保留只读 view 防误访问）

---

## 十六、参考与吸收来源

| 借鉴点 | 来源 |
|--------|------|
| Memory Card 内部分层 | Codex Memory Card 讨论（2026-06-28） |
| Asset 独立层 | Codex 讨论 |
| Fragment / Entity / Episode / Saga 四层 | `MEMORY_CONSTELLATIONS_STUDY.md`（吸收 ClaraShafiq/MemoryConstellations） |
| 轻量 tick + 深循环 | MEMORY_CONSTELLATIONS_STUDY |
| Entity seed → active | MEMORY_CONSTELLATIONS_STUDY |
| 检索分层注入 + 带 ID | MEMORY_CONSTELLATIONS_STUDY |
| `memory_recall_events` + novelty penalty | MEMORY_CONSTELLATIONS_STUDY |
| `user_corrections` 表 | 本次讨论（"剥离"诉求） |
| affect vs engagement 契约 | kimi-core / `20260619-记忆系统架构开源-kimi-core.md` |
| 便宜模型做后台整理 | 3nvoy / `20260619-给机搭建记忆库思路分享.md` |
| `memoryScope` 字段 | 本次合并 |
| 通用证据模型（sourceKind / sourceRef / rawInput） | 继承 V2 |
| 情绪坐标 valence / arousal | 继承 V2，Codex 讨论里精细化 |
| 多路召回 + 融合排序 | 继承 V2 + MEMORY_CONSTELLATIONS_STUDY |
| 凝结 watermark + 阈值 + 保底 | 继承 V2 |
| 本地优先 embedding | 继承 V2 |
| Saga 可见可改 | MEMORY_CONSTELLATIONS_STUDY（反驳了讨论中期一度选定的"AI 私密日记"立场） |

---

## 十七、决策日志（仅记本次合并新增的关键决策）

- 取消 V2 的 `domain` 作为核心字段
- 取消 `timeConfidence` / 标签系统
- Memory Review 仅放 Memory Card，Episode / Saga 走 Insight 体系
- `memoryScope` 仅 `user_truth` 和 `script_summary` 两值（Episode/Saga 不进 memory_cards）
- Insight 定义扩展：含 Entity 详情 / Episode / Saga / 各面板分析
- Saga 用户可见可改，初期不做"AI 私密日记"
- 不采用 kimi-core 的 affect-driven daemon 完整模式，仅吸收"按 affect 不按 engagement"作为契约
- `emotionalWeight`（Fragment 单维）跟 `valence` / `arousal`（Card / Episode 二维）分开，不强行统一
- 写入入口收敛为三个主路 + 一个升格路：消息记录按钮 / 悬浮球 / 自然语言指令 / Episode 升格成 Card

**2026-06-28 检索方案决策**：

- 检索按 intent 切换模板，不用单一公式（事实型 / 进度型 / 反思型 / 情绪型，共 4 类）
- Intent 由 I 隐式分类，不暴露为显式参数
- 召回结果分三层注入：主注入（全文）/ 附带引用（id + 一行摘要）/ 二次取（按需 `expand_memory(id)`）
- Saga 已吸收的低层证据默认折叠为引用，不重复注入
- 同一事实的多次记录应该被合并：Record Organizer 记录时检测 + Daily Dreaming 期间补救
- Saga.description 内容范围扩展：包含状态趋势 + 互动模式（"她希望 I 怎么回应"），但互动模式不进 User-truth

**2026-06-28 Dreaming agent 完整规范决策**（见 § 10.3–10.7）：

- 模型按功能配置：记忆抽取（便宜） / 记忆叙事（主模型），用户可改
- Fragment 抽 AI 自己关于用户/关系的观察，不抽普通回应；高情绪优先
- Episode 默认单 entity，必要时跨 entity；凝结阈值 ≥ 5 fragments + LLM 判同事件 + significance ≥ 5
- Episode 叙事默认写实型，必要时加反思型，不写抒情
- Saga 允许一个主题多条并存（状态 / 互动 / 重要事件叙事），增量改写 + 旧版进 `memory_saga_snapshots`
- Saga 编织阈值：5 episodes + 跨度 ≥ 2 周 + 每周最多 1 次
- 触发分层：Daily Dreaming 在充电+Wi-Fi+空闲>30min 跑，优先夜间；Lightweight tick 前台 15 分钟 + 消息事件驱动
- Entity seed→active 阈值：3 fragments + 跨 2 天
- Saga 写完跑 sanity check（不违反 affect-driven / 不替用户决定 / 不把推测说成事实）

**2026-06-28 Record Organizer 完整规范决策**（见 § 9）：

- 单 input 默认生成一张 Memory Card，仅在语义独立时拆多张
- title 不必精心润色，截原文或简化即可
- dropletLabel 抽事件本质而非泛化（"汇报打回" 不是 "工作"）
- event 卡的后续动作通过 structuredFields 的 `nextActionAt` 表达，不拆卡
- Schedule 面板查询规则：凡 structuredFields 含未来时间字段的卡都进 Schedule 面板
- 关键字段缺失时不静默猜测，写入 `memory_cards.needsFollowUp`，Chat agent 下次接话时追问
- valence / arousal v1 绝对打分，v2 补 calibration
- 不验证传闻真伪，措辞保留传闻语境（"她说"不去掉）
- 用户显式记录的内容不限主语，关于任何人都进 User-truth
- entity 识别只抽稳定实体，不抽临时行为（"高血压"算，"复查"不算）
- 用户显式记录关联的 entity 默认 `status=active`，跳过 seed
- Memory Card 直接 link 到 entity，不走 fragment 中间层
- 不引入 owner 字段，task 本质就是用户的事
- 同事实多次记录的合并不自动执行，由 I 提建议给用户确认
