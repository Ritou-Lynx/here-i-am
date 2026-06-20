# Here I Am 记忆系统方案 v1

> 作者：Claude（基于 17 篇社区调研 + 现有代码分析）
> 日期：2026-06-20
> 状态：初稿，待 Lynx 审阅

---

## 一、当前系统的问题

现有系统的底层（append-only 事件日志 + entity projection）设计合理，不需要推翻。问题出在三个地方：

**1. 写入端：自动捕获污染 User-truth**

ConversationCaptureService 在后台自动分析聊天，把它认为"有价值"的信息提取成 SharedLife entity。用户没有控制权，导致大量不准确、不完整、或用户根本不想记录的东西被写入。这是 2026-06-19 确认要停掉的。

**2. 检索端：只有关键词子串匹配**

`queryRelevantEntities` 的工作方式是：从数据库拉最近 60 条 entity，然后用正则拆出用户查询里的中文词/英文词，逐个看 title + entityType + stateJson 里有没有包含这个词。这意味着：

- "我上周吃了什么" 搜不到标题是 "和小明吃火锅" 的记录，因为没有共同关键词
- 不理解语义，"晚餐" 和 "吃饭" 是两个完全不同的词
- 只看最近 60 条，更早的记忆直接消失
- 没有按领域过滤的能力（健康相关的查询也会返回消费记录）

**3. 组织端：stateJson 是自由 JSON，没有结构约定**

每个 entity 的 `stateJson` 字段是完全自由的 JSON，没有 schema。同样是"吃饭"，不同次记录的字段名可能是 `location`、`place`、`地点`、`restaurant`。AI 写入时随心所欲，后续聚合分析（比如"这个月在外面吃了几次饭"）几乎不可能。

---

## 二、方案概述

保留 SharedLife 的 append-only 操作日志和 entity projection 作为底层。在此之上做三件事：给 entity 加领域 schema、加语义检索、加定期凝结。

整体分三层：

```
┌─────────────────────────────────────────────┐
│          凝结层（Consolidation）              │
│  定期把同领域 entity 聚合成领域摘要            │
│  "本周健康概况" / "6月消费统计"               │
└──────────────────┬──────────────────────────┘
                   │ 读取
┌──────────────────┴──────────────────────────┐
│          检索层（Retrieval）                  │
│  关键词匹配 + 语义向量 + 领域过滤 + 时间衰减   │
│  AI tool-call 的入口                         │
└──────────────────┬──────────────────────────┘
                   │ 读取
┌──────────────────┴──────────────────────────┐
│          存储层（Storage）                    │
│  SharedLife 操作日志 + Entity Projection      │
│  每个 entity 有 domain + 领域结构化字段        │
└─────────────────────────────────────────────┘
```

---

## 三、存储层改造

### 3.1 给 Entity 加 domain 字段

在 `SharedLifeEntities` 表增加 `domain` 列（text, not null, default 'general'）。domain 是固定枚举，不是用户自定义标签：

| domain | 含义 | 典型 entity_type |
|--------|------|-----------------|
| `health` | 运动、睡眠、饮食、体重、身体状况 | event, fact |
| `finance` | 消费、收入、转账 | event, fact |
| `schedule` | 日程、提醒、约会 | schedule, event |
| `task` | 待办、目标、计划 | task, plan |
| `social` | 和谁见面、社交活动 | event |
| `interest` | 阅读、观影、游戏、爱好 | event, fact, reading_item |
| `clothing` | 穿搭记录 | event, fact |
| `general` | 不属于以上任何领域 | fact |

domain 由 Record Organizer agent 在写入时判断，规则简单（一句话描述就能分类），不需要复杂推理。用户也可以在 UI 里手动改。

### 3.2 领域结构化字段（domain schema）

`stateJson` 仍然是自由 JSON，但为每个 domain 定义一组**推荐字段**，Record Organizer 写入时必须尽量使用这些字段名。这不是数据库层面的 schema 强制，而是 agent prompt 层面的约定。

示例：

**health domain:**
```json
{
  "activity_type": "sleep | exercise | meal | weight | symptom",
  "value": "7.5",
  "unit": "hours | kg | steps | ...",
  "time_start": "2026-06-20T23:00:00",
  "time_end": "2026-06-21T06:30:00",
  "note": "睡得不错",
  "tags": ["sleep"]
}
```

**finance domain:**
```json
{
  "direction": "expense | income",
  "amount": 128.0,
  "currency": "CNY",
  "category": "dining | transport | grocery | ...",
  "merchant": "海底捞",
  "time": "2026-06-20T19:00:00",
  "note": "和小明聚餐",
  "tags": ["dining"]
}
```

**schedule domain:**
```json
{
  "scheduled_time": "2026-06-21T10:00:00",
  "duration_minutes": 60,
  "location": "公司会议室",
  "participants": ["小明"],
  "reminder_minutes_before": 30,
  "recurring": null,
  "note": "周例会",
  "tags": ["work"]
}
```

每个 domain 的推荐字段定义放在一个独立的 Dart 文件里（`lib/domain/models/domain_schemas.dart`），Record Organizer 的 prompt 引用它。字段可以缺省，也可以有额外字段，但推荐字段的名称必须固定。

### 3.3 Entity type 精简

当前 entity_type 有 6 种：event, task, plan, schedule, fact, reading_item。保留不变，但明确语义：

- `event`：已发生的事（吃饭、运动、见面、购物）
- `task`：要做的事（有完成/取消状态）
- `plan`：较长期的意图（旅行计划、学习计划）
- `schedule`：有明确时间点的安排
- `fact`：持久性事实（"我对花生过敏"、"我的银行卡号"、"小明是我同事"）
- `reading_item`：阅读/收藏内容

entity_type 描述行为性质，domain 描述生活领域，两者正交。一个"和小明吃火锅"是 entity_type=event, domain=social（或 health，看用户关注点）。

---

## 四、检索层改造

### 4.1 三路召回 + 融合排序

AI 角色通过 tool-call 检索记忆时，同时走三条路，最后融合排序：

**路径 A：关键词匹配（保留现有逻辑，扩大范围）**
- 现有的 `_searchTerms` + 子串匹配，但去掉 60 条上限
- 改为先按 domain 过滤（如果查询能推断出 domain），再在过滤后的集合里做关键词匹配
- 速度快，精确匹配强

**路径 B：语义向量检索（新增）**
- 对每个 entity 生成 embedding（title + stateJson 的文本化摘要）
- 存储方案：SQLite 里加一个 `entity_embeddings` 表（entity_id, vector BLOB）
- embedding 生成：优先用 API（调用 LLM provider 的 embedding 接口），备选本地 bge-m3
- 查询时把用户问题也做 embedding，计算余弦相似度
- 解决"晚餐"搜到"吃火锅"的问题

**路径 C：时间范围过滤（新增）**
- 如果查询包含时间表达（"上周"、"昨天"、"这个月"），先解析出时间范围，只在范围内搜索
- 时间解析由 AI agent 在 tool-call 参数里显式给出（不靠规则解析自然语言）

**融合排序：**
```
final_score = 0.3 × keyword_score + 0.4 × semantic_score + 0.2 × recency_score + 0.1 × domain_match_score
```

recency_score 用时间衰减：`1.0 / (1 + days_ago / 30)`，30 天半衰期。

返回 top-K 结果（默认 K=8）。

### 4.2 改造 LifeMemoryQuery tool

当前 tool 只接受 `query`、`status`、`limit` 三个参数。改为：

```json
{
  "query": "上周吃了什么",
  "domain": "health",
  "time_start": "2026-06-13T00:00:00",
  "time_end": "2026-06-20T00:00:00",
  "entity_type": "event",
  "status": "active",
  "limit": 8
}
```

新增 `domain`、`time_start`、`time_end`、`entity_type` 四个可选过滤参数。AI 角色在理解用户意图后填入合适的参数，不需要用户手动指定。

### 4.3 凝结摘要也可被检索

凝结层产出的领域摘要（见第五节）也存为一种特殊 entity（entity_type=`summary`，新增），也有 embedding，也能被检索。这样"这个月花了多少钱"可以直接命中月度消费摘要，不需要遍历每条消费记录。

---

## 五、凝结层（Consolidation）

### 5.1 为什么需要凝结

用户用了三个月后可能有上千条 entity。AI 角色没法每次都遍历全量数据来回答"最近身体怎么样"。需要一个定期把原始记录聚合成摘要的过程。

这就是社区里反复出现的"做梦"（Dreaming）模式——Anthropic 官方、塔楼、Kiwi-Mem、EbbingFlow 都有类似设计。

### 5.2 凝结触发机制

不用定时（凌晨 3 点），改用**阈值触发**：

- 某个 domain 下新增或更新的 entity 数量达到 N（N=10 起步，可调），触发该 domain 的凝结
- 同时也支持手动触发（用户说"帮我总结一下这周的健康情况"）

阈值触发的好处：用户不活跃时不浪费资源，高频记录时及时凝结。

### 5.3 凝结产出

每次凝结产出一个 `summary` entity，内容是该 domain 在指定时间窗口内的结构化摘要。

示例（health domain, 2026-06-14 ~ 2026-06-20）：
```json
{
  "domain": "health",
  "period": "2026-06-14/2026-06-20",
  "summary_text": "本周睡眠平均 7.2 小时，比上周少 0.3 小时。周三有一次失眠（入睡时间推迟到凌晨 2 点）。运动 3 次，都是跑步，累计 15 公里。体重稳定在 72kg。周五感觉嗓子不舒服，可能有点感冒前兆。",
  "stats": {
    "sleep_avg_hours": 7.2,
    "exercise_count": 3,
    "exercise_total_km": 15
  },
  "source_entity_ids": ["uuid1", "uuid2", "..."],
  "generated_by": "consolidation_agent",
  "generated_at": "2026-06-20T03:00:00"
}
```

凝结由一个轻量 agent 完成（用便宜模型如 DeepSeek），不需要主角色模型。

### 5.4 凝结的层级

短期只做一层凝结（周度/阈值触发的 domain 摘要）。未来数据量大了可以加月度摘要、季度摘要，形成类似 EbbingFlow 的 Event → Episode → Saga 层级，但现在不需要过度设计。

---

## 六、写入端改造（Record Organizer）

### 6.1 ConversationCaptureService → RecordOrganizerService

停止自动捕获。新的 RecordOrganizerService 只在以下场景触发：

1. **用户通过 tool-call 显式记录**：角色调用 LifeMemoryCreate（已有，保留）
2. **用户点击消息级"记录"按钮**：前端提交选中的消息给 RecordOrganizerService
3. **悬浮球保存**：用户输入文本，RecordOrganizerService 解析并写入
4. **外部数据流**：截图识别、健康数据导入等

RecordOrganizerService 的职责：
- 接收原始输入（一段文字、一条消息、一张截图的 OCR 结果）
- 判断 domain
- 按 domain schema 提取结构化字段
- 生成 title
- 调用 SharedLifeMemoryService.applyOperations 写入
- 如果输入内容涉及多个 entity（"今天中午吃了麻辣烫花了 28 块，下午跑了 5 公里"），拆分成多条

### 6.2 Record Organizer Agent 的 prompt 要点

- 你是一个事实记录整理器，不是聊天助手
- 用户给你的内容是他们明确想记录的事实
- 你的任务：判断 domain → 按 domain schema 提取字段 → 生成 title → 输出结构化结果
- 字段名必须严格使用 domain schema 定义的名称
- title 要简短、客观、以事实为主（"6月20日跑步5公里"，不是"今天运动啦"）
- 一条输入可能包含多个事实，全部拆分
- 如果信息不完整（只说了"吃饭"没说吃什么），也记下来，缺失字段留空
- 不要推测、不要补充用户没说的信息

---

## 七、数据库变更清单

### 7.1 SharedLifeEntities 表增加 domain 列

```sql
ALTER TABLE shared_life_entities ADD COLUMN domain TEXT NOT NULL DEFAULT 'general';
```

对应 Drift 表定义：
```dart
TextColumn get domain => text().withDefault(const Constant('general'))();
```

### 7.2 新增 EntityEmbeddings 表

```dart
class EntityEmbeddings extends Table {
  TextColumn get entityId => text().references(SharedLifeEntities, #id)();
  BlobColumn get vector => blob()();  // Float32 array serialized as bytes
  IntColumn get modelVersion => integer().withDefault(const Constant(1))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {entityId};
}
```

### 7.3 entity_type 新增 'summary'

在 `_supportedEntityTypes` 集合里加入 `'summary'`。

---

## 八、迁移路径

### 阶段 0：停血（最紧急）
- 关闭 ConversationCaptureService 的自动触发
- 只保留 tool-call 路径（LifeMemoryCreate 等）
- 这一步不需要新代码，只需要在 capture service 的入口加开关

### 阶段 1：加 domain + schema 约定
- 加 domain 列，跑一次迁移给现有 entity 补 domain（用 LLM 批量分类）
- 写 domain schema 定义文件
- 更新 LifeMemoryCreate tool 的 prompt，要求 agent 指定 domain 和使用标准字段名

### 阶段 2：加语义检索
- 加 EntityEmbeddings 表
- 实现 embedding 生成（先用 API，后续可换本地模型）
- 改造 queryRelevantEntities 为三路召回 + 融合排序
- 更新 LifeMemoryQuery tool 参数

### 阶段 3：加凝结层
- 实现阈值触发的 domain 凝结
- summary entity 生成和存储
- 凝结摘要可被检索

### 阶段 4：Record Organizer
- 实现消息级"记录"按钮的后端
- 实现悬浮球保存的后端
- RecordOrganizerService 替代 ConversationCaptureService

---

## 九、调研来源对照

这个方案从哪些调研材料里借鉴了什么：

| 借鉴点 | 来源 |
|--------|------|
| domain schema（固定字段名） | 3nvoy "存事实不存指令"原则 + 自有 SharedLife 反思 |
| 语义向量 + 关键词混合检索 | AI陪伴记忆架构v3（Conway叙事记忆）的 hybrid retrieval benchmark |
| 凝结/做梦机制 | Anthropic Dreaming + 塔楼 nightly dreaming + Kiwi-Mem |
| 时间衰减排序 | EbbingFlow 遗忘曲线 |
| 便宜模型做后台整理 | 3nvoy "管家" + 柴一 DeepSeek 写摘要 |
| 阈值触发而非定时 | Kiwi-Mem v1.3.0（从关键词触发改为模型自主判断） |
| summary 可检索 | 柴一双层检索（搜摘要省 token，搜原文获全量） |
| 用户显式写入、不自动捕获 | 记忆契约（已确认决策） |
| domain 过滤减少噪音 | ai-companion-runtime 5 层记忆中 User Profile 层的分类思路 |

---

## 十、没有采纳的设计及原因

- **知识图谱（KG）**：3nvoy 方案用了 entity-relation-observation 三元组。对于生活事实记录来说过重，实体之间的关系大多是隐含的（时间相近、同一个人、同一个地点），不需要显式建模。如果未来需要，可以在凝结层通过 LLM 提取关系，不需要在存储层引入图数据库。

- **8 维驱动系统**：CC 的方案（好奇心、关怀、幽默等 8 个维度阈值触发主动行为）。这是角色记忆/性格系统，不是事实记忆，放到角色层去做。

- **5 层 L0-L4 记忆**：ai-companion-runtime 的设计（Working → Session → Profile → Vector → Archive）。这是对话记忆的分层，我们的事实记忆不需要 Working Memory 和 Session Summary（那是聊天上下文管理的事），Vector 和 Archive 的思路已经吸收进检索层和凝结层。

- **P.A.R.A. 目录结构**：知识管理方法论，对 AI 可操作但与生活事实记录的场景不匹配。

- **Ebbinghaus 遗忘曲线的严格实现**：EbbingFlow 用指数衰减决定记忆是否"遗忘"。我们用了简化版的时间衰减排序，但不会真的删除或隐藏老记忆——用户的事实记录不应该被遗忘，只是检索时排序靠后。
