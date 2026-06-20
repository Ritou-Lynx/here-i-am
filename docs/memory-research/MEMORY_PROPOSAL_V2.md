# Here I Am 记忆系统方案 v2

> 日期：2026-06-20
> 状态：整合两份反馈后的修订版
> 变更：v1 → v2 的改动在每节末尾用 `[v2]` 标注

---

## 一、当前系统的问题

保留 v1 的诊断不变，补充一条：

**4. 证据模型只支持聊天消息**

`SharedLifeMemoryService.applyOperations` 要求 `sourceMessageIds`，且没有有效消息 ID 会丢弃操作。但产品规划的写入入口包括悬浮球、截图 OCR、健康数据导入，这些都没有 chat message ID。当前设计会逼着这些入口伪造消息 ID。`[v2]`

---

## 二、方案概述

保留三层架构（存储 + 检索 + 凝结），但修正两个原则：

1. **写入契约先于检索优化**——先把显式写入、证据模型、domain、时间字段这些基础钉住，embedding 和 summary 是后续增强。
2. **summary 是 derived artifact，不是 User-truth**——凝结产出与用户记录在语义上分开，检索时可以一起召回，但 UI 和导出里区分呈现。`[v2]`

```
┌─────────────────────────────────────────────┐
│          凝结层（Consolidation）              │
│  derived artifact，不混入 User-truth         │
│  domain + period 唯一，watermark 驱动        │
└──────────────────┬──────────────────────────┘
                   │ 读取（只读当前有效 entity）
┌──────────────────┴──────────────────────────┐
│          检索层（Retrieval）                  │
│  关键词 + 语义向量 + domain 过滤 + 时间过滤   │
│  按 entity_type 差异化排序策略               │
└──────────────────┬──────────────────────────┘
                   │ 读取
┌──────────────────┴──────────────────────────┐
│          存储层（Storage）                    │
│  操作日志 + Entity Projection                │
│  通用证据模型 + domain + 事件时间字段          │
│  用户可编辑/删除，角色只见当前有效版本         │
└─────────────────────────────────────────────┘
```

---

## 三、存储层

### 3.1 通用证据模型（Evidence / Source）`[v2 新增]`

替换当前 `sourceMessageIds` 的硬编码设计。每条操作携带的证据信息改为：

**在 `SharedLifeEventOperations` 表增加字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `sourceKind` | text, not null | 枚举：`chat_message` / `floating_ball` / `screenshot_ocr` / `health_import` / `manual_edit` / `record_button` / `external_share` |
| `sourceRef` | text, nullable | 通用引用 ID（chat message 就是 message id，截图就是文件路径，健康导入就是批次 ID） |
| `rawInput` | text, nullable | 用户原始输入文本（保留原貌，用于审计和溯源） |

原有的 `sourceMessageIds` 字段保留（向后兼容），但新代码不再依赖它做校验。`applyOperations` 里"没有有效 sourceMessageIds 就丢弃"的逻辑需要改为：有 `sourceKind` 即可通过。

### 3.2 Domain 字段 `[v2 改动：多 domain]`

**在 `SharedLifeEventOperations` 和 `SharedLifeEntities` 两个表都加 domain 字段。**

操作日志里的 domain 是写入时确定的，projection rebuild 时从操作日志恢复，不会丢失。

单一 domain 会丢信息（"和小明吃火锅花了 128" 同时涉及 social、finance、health）。改为：

| 字段 | 表 | 类型 | 说明 |
|------|-----|------|------|
| `primaryDomain` | 两个表都加 | text, not null, default 'general' | 主领域，Record Organizer 判断 |
| `facets` | 两个表都加 | text (JSON array), nullable | 次要领域，如 `["finance","health"]` |

检索时 domain 过滤支持：匹配 primaryDomain **或** facets 中包含目标 domain。这是软过滤（匹配 domain 加分），不是硬过滤（除非用户/AI 显式要求精确过滤）。

Domain 枚举：

| domain | 含义 |
|--------|------|
| `health` | 运动、睡眠、饮食、体重、身体状况 |
| `finance` | 消费、收入、转账 |
| `schedule` | 日程、提醒、约会 |
| `task` | 待办、目标、计划 |
| `social` | 社交活动、人际关系 |
| `interest` | 阅读、观影、游戏、爱好 |
| `clothing` | 穿搭记录 |
| `general` | 不属于以上任何领域 |

### 3.3 事件时间字段 `[v2 新增]`

`createdAt` / `updatedAt` 是记录时间，不是事情发生的时间。用户可能晚上才记录早上的事。检索"上周发生了什么"如果靠 `createdAt` 会不准。

**在 `SharedLifeEntities` 表增加：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `occurredAt` | integer (microseconds), nullable | 事件发生时间（event、schedule 等），由 Record Organizer 从内容推断 |
| `occurredEndAt` | integer, nullable | 事件结束时间（可选，用于有时间跨度的记录） |

`occurredAt` 通过 patch 中的**保留字段**恢复，不做字段猜谜。Record Organizer 输出时统一写入以下下划线保留字段：

- `_occurredAt`：事件发生时间（ISO 8601 字符串，rebuild 时转为 microseconds）
- `_occurredEndAt`：事件结束时间（可选）
- `_timeConfidence`：时间推断置信度（`exact` / `inferred` / `unknown`）
- `_timeSourceText`：原始时间表述（如"今天中午"、"上周三"），用于审计

projection rebuild 只认 `_occurredAt` / `_occurredEndAt`，不扫描 domain schema 里的业务时间字段（`time_start`、`scheduled_time` 等仍可在 domain schema 中保留，但只服务于业务语义，不承担 projection 映射）。

所有下划线保留字段（`_occurredAt`、`_occurredEndAt`、`_timeConfidence`、`_timeSourceText`、`_primaryDomain`、`_facets`、`_valence`、`_arousal`、`_schemaVersion`）由 `DomainSchemaValidator` 集中管理：保留字段不进入 `extras`，也不允许普通 domain schema 覆盖。`[v2.1]`

对于 `fact` 类型（"我对花生过敏"），`_occurredAt` 可以不填，检索时不受时间过滤影响。

### 3.4 情绪坐标 `[v2 新增]`

服务于未来 3D 可视化。在 `SharedLifeEntities` 表增加：

| 字段 | 类型 | 说明 |
|------|------|------|
| `valence` | real, nullable | 愉悦度，-1.0（极不愉快）到 1.0（极愉快） |
| `arousal` | real, nullable | 唤醒度，0.0（平静）到 1.0（高度兴奋/紧张） |

由 Record Organizer 在写入时推断，不确定时留 null。`fact` 类型通常不打分。检索层和凝结层不依赖这两个字段。

情绪坐标存在 patch 里（`valence`、`arousal` 作为保留字段名），rebuild 时提升到 projection 列。

### 3.5 领域结构化字段（Domain Schema）`[v2 改动：加校验]`

保留 v1 的 domain schema 推荐字段设计，但加入 service 层校验：

**Schema 定义文件**：`lib/domain/models/domain_schemas.dart`

每个 domain 定义：
- 推荐字段名及类型（string / number / datetime / enum）
- 必填字段和可选字段
- enum 类型的合法值列表（如 finance 的 `direction: expense | income`）
- `schema_version`（整数，每次 schema 变更时递增）

**RecordOrganizerService 写入时**：
- agent 输出的 JSON 经过 `DomainSchemaValidator` 校验
- 字段名不在推荐列表里的，移入 `extras` 子对象（不丢弃，保留灵活性）
- 时间字段统一格式化为 ISO 8601
- 金额字段统一为 number（去掉"元""块"等文字）
- 校验失败不阻断写入，但标记 `needs_review: true`
- `schema_version` 写入 patch，未来 schema 升级时可做数据迁移

### 3.6 Entity Type

保留 v1 的 6 种：event, task, plan, schedule, fact, reading_item。

**不再把 summary 作为 entity_type**。凝结产出单独存储（见第五节）。`[v2]`

### 3.7 用户编辑与删除权 `[v2 新增]`

已确认的产品决策：append-only 降级为底层审计，用户面对的所有层面只呈现当前有效版本。

**实现方式**：

现有机制已基本支持：
- `LifeMemoryUpdate`：追加 `update` 操作，projection 自动 rebuild 为最新值
- `LifeMemoryDelete`：追加 `undo` 操作撤销所有操作，projection 行被删除
- `_rebuildEntity`：每次都从操作日志重放，自然只反映当前有效状态

需要补充的：
- **UI 层直接编辑**：前端调用一个新的 `editEntity` 方法，追加 `correct` 操作写入用户修改的字段。不走 agent，直接调 service。
- **embedding 同步失效**：entity 被 update/delete 后，对应的 embedding 标记为 stale（contentHash 不匹配），下次检索前重新生成。
- **导出只含当前有效版本**：导出接口读 projection 表，不读操作日志。
- **修订历史**：仅在用户主动查看某条记录的"历史"时，才从操作日志读出变更链。角色永远只看 projection。

---

## 四、检索层

### 4.1 多路召回 + 融合排序 `[v2 改动：按类型差异化]`

**路径 A：DB 级过滤（前置）**
- 按 domain 过滤（匹配 primaryDomain 或 facets）
- 按时间范围过滤（用 `occurredAt`，不是 `createdAt`）
- 按 entity_type 过滤
- 按 status 过滤
- 这一步在数据库层完成，缩小候选集

**路径 B：关键词匹配**
- 保留现有 `_searchTerms` + 子串匹配逻辑
- 去掉 60 条硬编码上限（由路径 A 的过滤结果决定候选集大小）
- 未来可升级为 SQLite FTS5

**路径 C：语义向量检索（阶段 4 加入）**
- 对每个 entity 生成 embedding
- 查询时计算余弦相似度
- **默认本地优先**（设备端轻量 embedding 模型，具体按 Android 包体、速度、内存和中文效果评估），API embedding 需用户配置同意。网络不可用时关键词 + FTS 仍可用。`[v2.1]`

**融合排序——按 entity_type 差异化** `[v2]`：

```
# event：时间衰减权重高
event_score = 0.3 × keyword + 0.35 × semantic + 0.25 × recency + 0.1 × domain_match

# fact：基本不做时间衰减（"我对花生过敏"十年前记的也很重要）
fact_score = 0.35 × keyword + 0.45 × semantic + 0.05 × recency + 0.15 × domain_match

# schedule：看未来时间、状态
schedule_score = 0.25 × keyword + 0.3 × semantic + 0.3 × upcoming_proximity + 0.15 × domain_match

# task：看状态和 due
task_score = 0.3 × keyword + 0.35 × semantic + 0.2 × urgency + 0.15 × domain_match
```

当查询包含明确时间范围时，时间是**硬过滤**（路径 A），不参与排序加分。`[v2]`

### 4.2 LifeMemoryQuery Tool 参数

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

`domain` 过滤默认为软过滤（匹配加分）。AI 角色可以传 `"domain_strict": true` 改为硬过滤。`[v2]`

---

## 五、凝结层（Consolidation）`[v2 重写]`

### 5.1 Summary 独立于 User-truth

凝结产出不是 User-truth，是 AI 派生的分析产物。

**新建 `SharedLifeSummaries` 表**（不混入 SharedLifeEntities）：

```dart
class SharedLifeSummaries extends Table {
  TextColumn get id => text()();
  TextColumn get domain => text()();              // 哪个领域的摘要
  TextColumn get period => text()();              // "2026-06-14/2026-06-20" 或 "2026-06"
  TextColumn get summaryText => text()();         // 自然语言摘要
  TextColumn get statsJson => text().nullable()(); // 结构化统计数据
  TextColumn get sourceEntityIds => text()();     // JSON array，来源 entity IDs
  TextColumn get sourceHash => text()();          // 来源 entities 的内容 hash，用于判断是否 stale
  TextColumn get generatedBy => text()();         // "consolidation_agent" / model name
  IntColumn get generatedAt => integer()();
  BoolColumn get isStale => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
```

检索层可以同时搜索 SharedLifeEntities 和 SharedLifeSummaries，但 UI 上区分展示（summary 带"AI 分析"标记），导出时可选是否包含。

### 5.2 凝结触发：watermark + 阈值 + 保底 `[v2]`

| 条件 | 说明 |
|------|------|
| 阈值 | 某 domain 自上次凝结以来新增/修改 ≥ 10 条 entity |
| 保底 | 某 domain 超过 7 天未凝结，且有 ≥ 1 条新增/修改 |
| period 唯一 | 同一 domain + 同一 period 只有一条 summary，触发时覆盖旧的 |
| watermark | 记录每个 domain 上次凝结的最后一条 entity 的 updatedAt |
| stale 标记 | source entity 被用户编辑/删除后，相关 summary 标记 `isStale = true` |

凝结使用便宜模型（DeepSeek / Gemini Flash），不用主角色模型。

### 5.3 凝结层级

短期只做周度摘要。未来可加月度、季度，但现在不做。

---

## 六、写入端：RecordOrganizerService

### 6.1 定位

替代 ConversationCaptureService。**只处理用户显式要求记录的内容。**

### 6.2 写入入口

| 入口 | 阶段 | 说明 |
|------|------|------|
| Tool-call（LifeMemoryCreate 等） | 已有 | 角色聊天中用户说"记一下" |
| 消息级"记录"按钮 | 阶段 1 | 用户选中一条消息，点记录 |
| 悬浮球保存 | 阶段 4 | 快速输入文本保存 |
| 外部数据流（截图 OCR、健康导入等） | 阶段 4 | 后台处理 |

### 6.3 RecordOrganizerService 职责

接收原始输入 → 判断 domain（primary + facets）→ 按 domain schema 提取结构化字段 → 通过 DomainSchemaValidator 校验 → 生成 title → 推断 occurredAt → 推断 valence/arousal → 调用 SharedLifeMemoryService 写入

如果输入包含多个事实（"中午吃了麻辣烫花了 28 块，下午跑了 5 公里"），拆分成多条。

### 6.4 Record Organizer Agent Prompt 要点

- 你是事实记录整理器，不是聊天助手
- 判断 primaryDomain 和 facets
- 字段名严格使用 domain schema 定义
- title 简短客观（"6月20日跑步5公里"，不是"今天运动啦"）
- 推断 occurredAt（"今天中午" → 具体时间戳）
- 推断 valence/arousal（不确定就留空）
- 一条输入可拆多条 entity
- 信息不完整也记，缺失字段留空
- 不推测、不补充用户没说的

---

## 七、数据库变更清单

### 7.1 SharedLifeEventOperations 新增字段

```dart
// 证据模型
TextColumn get sourceKind => text().withDefault(const Constant('chat_message'))();
TextColumn get sourceRef => text().nullable()();
TextColumn get rawInput => text().nullable()();
// Domain（跟随操作，rebuild 时恢复到 projection）
TextColumn get primaryDomain => text().withDefault(const Constant('general'))();
TextColumn get facets => text().nullable()();  // JSON array
```

### 7.2 SharedLifeEntities 新增字段

```dart
// Domain
TextColumn get primaryDomain => text().withDefault(const Constant('general'))();
TextColumn get facets => text().nullable()();  // JSON array
// 事件时间
IntColumn get occurredAt => integer().nullable()();
IntColumn get occurredEndAt => integer().nullable()();
// 情绪坐标
RealColumn get valence => real().nullable()();
RealColumn get arousal => real().nullable()();
// Schema 版本
IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
```

### 7.3 新增 EntityEmbeddings 表

```dart
class EntityEmbeddings extends Table {
  TextColumn get entityId => text()();
  BlobColumn get vector => blob()();
  TextColumn get provider => text()();        // "local_bge_m3" / "openai" / ...
  TextColumn get model => text()();           // 具体模型名
  IntColumn get dimension => integer()();     // 向量维度
  TextColumn get contentHash => text()();     // 内容 hash，判断是否需要重算
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {entityId};
}
```

embedding 元数据足够支持：模型切换时批量重算、内容变更后失效重算。`[v2]`

### 7.4 新增 SharedLifeSummaries 表

见第五节。`[v2]`

### 7.5 entity_type 不再新增 'summary'

Summary 走独立表。`[v2]`

---

## 八、迁移路径 `[v2 重排]`

### 阶段 0：停血（最紧急，1-2 天）
- 关闭 ConversationCaptureService 的自动触发入口
- 删除/修改 companion agent prompt 里"后台整理会静默运行"的描述
- 只保留 tool-call 路径（LifeMemoryCreate 等）作为临时写入入口

### 阶段 1：写入基础设施（核心，1-2 周）
- RecordOrganizerService 基础版
- 通用证据模型（sourceKind / sourceRef / rawInput）
- domain（primaryDomain + facets）加入操作日志和 projection
- 事件时间字段（occurredAt / occurredEndAt）
- 情绪坐标字段（valence / arousal）
- Domain schema 定义 + DomainSchemaValidator
- **消息级"记录"按钮**（保证过渡期有两个写入入口）
- 用户编辑/删除机制（UI 层直接调 service）
- `_rebuildEntity` 改造：从操作日志恢复 domain、occurredAt、valence/arousal

### 阶段 2：检索改进（1 周）
- LifeMemoryQuery 新增 domain / time_start / time_end / entity_type 参数
- DB 级过滤（domain、时间、类型、状态）
- 去掉 60 条硬编码上限
- 按 entity_type 差异化排序策略
- 可选：SQLite FTS5 替代子串匹配

### 阶段 3：语义检索（1 周）
- EntityEmbeddings 表
- 本地优先 embedding 生成（设备端轻量模型，bge-m3 仅作服务器/桌面参考），API 为可选配置 `[v2.1]`
- 融合排序（关键词 + 语义 + 时间/紧急度 + domain）
- entity 变更后 embedding 自动失效重算

### 阶段 4：凝结层 + 扩展写入（2 周）
- SharedLifeSummaries 表
- 凝结触发（watermark + 阈值 + 7 天保底）
- 凝结 agent（便宜模型）
- summary stale 标记（source entity 变更时只标 `isStale=true`，不立即重算；等下次凝结触发时顺手重算，检索时降权或隐藏 stale summary）`[v2.1]`
- 悬浮球保存入口
- 外部数据流（截图 OCR、健康导入等）

---

## 九、调研来源对照

| 借鉴点 | 来源 |
|--------|------|
| domain schema + 字段校验 | 3nvoy "存事实不存指令" + Codex 反馈 |
| 多 domain / facets | Codex 反馈 #3 |
| 通用证据模型 | Codex 反馈 #6 |
| 事件时间 vs 记录时间分离 | Codex 反馈 #5 |
| 语义 + 关键词混合检索 | AI陪伴记忆架构v3 hybrid retrieval |
| 按类型差异化排序 | Codex 反馈 #9 |
| 凝结/做梦 + watermark | Anthropic Dreaming + 塔楼 + Kiwi-Mem + Codex 反馈 #8 |
| summary 独立于 User-truth | Codex 反馈 #7 |
| 便宜模型做后台整理 | 3nvoy 管家 + 柴一 DeepSeek |
| 本地优先 embedding | Codex 反馈 #10 |
| 用户编辑删除权 | 产品决策（CLAUDE.md）+ 反馈文件 #1 |
| 情绪坐标 | 反馈文件 #2 |
| 消息记录按钮前置 | 反馈文件 #3 |
| 凝结保底机制 | 反馈文件 #4 |

---

## 十、没有采纳的设计及原因

保留 v1 的列表，补充：

- **严格 Ebbinghaus 遗忘**：用户事实不应被遗忘。时间衰减只影响检索排序，且 fact 类型基本不衰减。
- **知识图谱**：生活事实间的关系大多隐含（时间相近、同一个人、同一个地点），不需要显式三元组。未来凝结层可以提取关系作为 summary 的一部分。
- **P.A.R.A.**：知识管理方法论，场景不匹配。
- **全自动会话捕获**：记忆契约明确禁止。
