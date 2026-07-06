# Here I Am Product Roadmap

Last updated: 2026-06-19

本文档是 Here I Am 的权威产品路线图。2026-06-19 经全面整理，合并了功能梳理文档、旧 ROADMAP.md、PRD、UI 设计文档的内容，并落实了所有已确认的产品决策。

它的目标不是列出所有想做的功能，而是把混乱的功能点重新归入同一条产品主线：Here I Am 是一个以角色对话为入口、以生活记忆为底座、以主动陪伴为表达方式的本地优先 AI companion。

---

## 1. 当前总判断

### 1.1 产品主线

核心承诺：

> 用户自然生活和聊天；角色在合适的时候理解、记住、提醒、帮忙，但不把用户变成数据库管理员。

这条主线分成四层：

| 层 | 作用 | 代表能力 |
|---|---|---|
| 角色关系层 | 用户与某个角色持续相处 | chat、语音、来电、私密关系记忆 |
| User-truth 层 | 用户主动确认的真实生活资料 | 记忆卡、日程、任务、事实、穿衣历史 |
| 生活产物层 | 从 User-truth 和外部数据中形成可查看产物 | Memory Review、Schedule、Ledger、Health、Interests、Project Memory |
| 主动陪伴层 | 角色基于记忆和现实上下文主动触达 | checkin、提醒、出门建议、睡前陪伴、财务提醒 |

### 1.2 根本性修改：卡片不再由 AI 实时裁判生成

旧思路：

```text
所有聊天输入 -> AI 判断该不该记 -> 自动生成卡片 -> 用户错过 toast 就可能误记或漏记
```

新思路：

```text
角色聊天默认进入当前角色 sandbox
用户显式记录 / 悬浮球保存 / 专门 capture 流程 -> User-truth
User-truth 再生成 Memory Summary Card 和各类生活产物
```

这会砍掉或降级以下旧机制：

- 不再把普通角色聊天当成默认自动卡片来源。
- 不再依赖“AI 判断该不该记”的单一管道。
- 不在对话流里频繁弹出卡片确认。
- 不用 toast 作为“误记撤销”的主要保护。
- 角色扮演、私密对话、关系叙事默认留在该角色 sandbox，不污染 User-truth。

保留但重新定位：

- `SharedLifeMemoryService` 仍是 User-truth / 生活记忆的核心底座。
- `ConversationCaptureService` 需要从“自动裁判”转成“明确 scope 下的整理器”。
- 旧 Timeline/Card/Insight 能力保留为兼容基础设施和模块素材，不再主导 Here I Am 的新记忆卡视觉。

### 1.3 UI 的产品含义

新 UI 不是单纯换皮。它已经把产品逻辑定下来了：

- Chat 是主场，能力留在对话。
- 圆柱屏 / 观察面承载生活产物。
- Memory Review 不是无限 timeline，而是最近 1-2 天新记忆的质检台。
- Schedule 是独立观察面，不塞在旧 Life Space 三页签里。
- Personal / Settings 属于系统层，从 Chat 显式入口进入，不进入圆柱主屏。
- Memory Card 只有统一的凝露外壳，视觉差异来自内容板块组装，不回到旧 30 多种模板外壳。

---

## 2. 信息架构目标

### 2.1 主导航

第一版仍以点击为主，不强依赖 3D 手势。

| 区域 | 第一版目标 | 后续目标 |
|---|---|---|
| Chat home | 默认首页，保留现有文字、语音、图片、通话、任务胶囊、活动提示 | Presence ring、记忆沉淀、坠落入口 |
| 观察面 / Hall | 从 Chat 进入的生活产物集合 | 圆柱大厅、屏幕转身、空间层级 |
| Memory Review | 最近生成/提升的 User-truth 记忆质检台 | 与记忆云水珠联动 |
| Schedule | 日程、任务、提醒、出门前准备 | 更强的日程聚合和通勤推算 |
| Ledger | 财务记录和 AI 账本视图 | 角色财务意识和提醒 |
| Health / Body | 运动、睡眠、身体状态 | 长期趋势和主动建议 |
| Interests / Culture | 阅读、小红书、公众号、作品、兴趣 | 角色自然讲解与召回 |
| Project Memory | 项目进展、开发决策、模块状态和当前优先级；初期不做独立主入口 | 后续在 Dev Room / Observe 中查看项目时间线和当前态 |
| Settings / Personal | 模型、权限、连接、备份、角色管理 | 系统层清晰稳定 |

### 2.2 旧 Life Space 处理

`CompanionLifeSpaceScreen` 当前是 Review / Schedule / Personal 三页签的过渡容器。目标是拆分：

- Personal / Settings 移出 Life Space。
- Memory Review 和 Schedule 进入观察面。
- 旧 Memex timeline 从主路径移除，只作为兼容入口或历史数据源。

---

## 3. 数据与记忆模型路线

### 3.1 四类持久内容

| 内容 | 来源 | 可见性 | 是否进 User-truth |
|---|---|---|---|
| 角色 sandbox | 每个角色聊天全量消息 | 用户可跨 sandbox 搜索；角色只能访问自己 | 默认不进 |
| 关系 insights | 单角色关系叙事总结 | 当前角色 | 不可 promote 到 User-truth |
| User-truth cards | 用户显式保存、提升或明确记录的事实 | 所有角色共享 | 是 |
| User-truth insights | 跨 User-truth 的分析洞察 | 给用户看 | 不直接作为角色上下文 |
| Project Memory | commit、DEVLOG、Dev Room、Codex/Claude Code closeout、项目状态文件、用户确认的项目决策 | 林埃和项目相关工具按需检索；普通生活聊天默认不注入 | 不进，属于 Memory V3 特殊 domain |

### 3.2 User-truth 写入入口

第一版建议只保留清晰入口：

1. 消息级“记录”按钮：把某条聊天消息提升为 User-truth。
2. 悬浮球“保存”：从任何场景快速保存事实/想法/计划。
3. 明确自然语言指令：用户说“记一下”“把这个作为事实”“这个加入日程”。
4. 外部数据流：阅读分享、账单截图、健康数据、天气/通勤结果等，在明确功能场景下入库。
5. 专门学习循环：如每日穿衣记录，用户回答后作为结构化偏好入库。

### 3.3 Conversation Capture 的新定位

短期不直接废弃现有捕获系统，但要收缩语义：

- 对普通角色聊天：只更新角色 sandbox 和必要的关系私密记忆候选。
- 对用户显式记录的内容：整理成 User-truth operation。
- 对外部 capture：在功能 scope 内提取结构化字段，例如 reading_item、finance ledger、outfit log。
- 对“可能影响真实生活”的推断：标记为需确认，不直接扩散到日程、账本或跨角色记忆。

### 3.4 Project Memory 特殊领域

Project Memory 不另起一套记忆系统，而是 Memory V3 里的特殊 domain。它解决的问题是：林埃需要知道 Here I am 项目的当前状态，但这些状态并不等同于用户的生活事实，也不应该污染关系记忆。

第一版只做数据和检索边界，不急着做独立 UI：

- **当前态**：`I_PROJECT_STATE.md` 保留短而新的项目快照，供林埃快速读取。
- **事件史**：commit、DEVLOG、Dev Room run、Codex/Claude Code closeout 形成可回溯项目事件。
- **检索边界**：只有项目相关问题、Dev Room 场景、收工检查和用户明确追问项目进展时才召回。
- **展示位置**：初期融合在 Dev Room / Observe / Memory Review 的项目过滤视图里；等数据稳定后再决定是否做独立 Project Memory 面板。

---

## 4. Memory Card 新规则

### 4.1 两层视图

| 视图 | 任务 |
|---|---|
| Memory Summary Card | 快速看懂这条记忆是什么，提供“聊聊”入口 |
| Full Detail View | 展示来源证据、结构化字段、相关实体、修订历史 |

Summary Card 不是旧 timeline card，也不是每条原始输入一张卡。它展示的是 User-truth 当前状态。

### 4.2 字段命名方向

| 概念 | 用途 |
|---|---|
| `dropletLabel` | 水珠上的 2-4 字短标识，不等于标签 |
| `memorySummary` | 用户可读、可修正的记忆主体 |
| `presentationModule` | 摘要的板块化呈现结果 |
| `sourceExcerpts` | 原始对话或外部来源证据 |
| `structuredFields` | 时间、地点、人物、金额、任务状态、健康指标等机器字段 |
| `emotionCoordinates` | `valence`（-1.0~1.0）+ `arousal`（0.0~1.0），记忆当下的情绪坐标，用于 Summary Card 情绪角晕和未来记忆云可视化 |
| `operationHistory` | create / append / update / correct / undo 等历史 |

### 4.3 呈现规则

Memory Card = 统一凝露外壳 + 活动板块组装。

第一批活动板块：

- Text
- Quote
- SubjectReference
- Number
- Table
- Sparkline
- ProgressBar
- Media
- LinkAttachment

规则：

- 语义类型不直接决定视觉外壳。
- Event / Task / Reading / Finance / Health 等进入字段、tags、归属屏和检索。
- Summary Card 不做完整趋势图、饼图、雷达图、可交互 checklist。
- 聊天气泡里召回记忆时使用简化形态：去掉 Foot、状态块、情绪角晕，只保留活动板块。

### 4.4 修正方式

优先用“聊聊”修正：

- 用户自然语言说明哪里错了。
- 助手型角色同步修正摘要、字段、相关实体和必要 operation。
- 影响日程、任务、关联记忆、账本等跨实体内容时再确认。

手动编辑第一版只改 `memorySummary`，保存后标记结构复核。

---

## 5. 功能线整合

### 5.1 主动陪伴

已有基础：

- checkin service
- reminder queue
- foreground service / WorkManager 唤醒链路
- 高优先级通知频道
- 语音来电和语音通话

产品原则：

- 对外发声尽量由角色说，不做冷冰冰系统通知。
- 主动触达必须有明确上下文和频率边界。
- 主动建议不应频繁打断普通聊天。

近期优先级：

1. 稳定主动触达基础设施。
2. 把提醒结果写入聊天或角色可读记录。
3. 对每类主动功能设置冷却、安静时段、失败重试和用户关闭入口。

### 5.2 每日出门提醒

这是主动陪伴的优先新功能，不是普通天气助手。

核心差异：

> 通用天气助手说“25 度适合短袖”；Here I Am 应该说“你昨天短袖加薄外套觉得差不多，今天比昨天暖 4 度，可以少穿那件外套”。

#### 用户价值

用户对绝对温度无感，但能理解相对体感：

- 昨天穿了什么。
- 昨天是否冷/热/刚好。
- 今天比昨天冷几度或暖几度。
- 今天是否有雨、风、紫外线、通勤暴露时间。

#### 触发时机

第一版：

- 固定早晨提醒时间，例如用户设置的出门前 30-60 分钟。

第二版：

- 根据今日日程、通勤距离、当前位置、常用出发站点推算提醒时间。
- 示例：北京立水桥站通勤场景，结合通勤方式和天气暴露程度。

#### 数据源

| 数据 | 来源 |
|---|---|
| 实时天气 | 高德天气 API / 和风天气 API |
| 地理和通勤 | 高德地图 API |
| 今日日程 | User-truth / Schedule |
| 昨日穿着 | Outfit log |
| 体感反馈 | 用户早晨回复和晚间可选反馈 |

说明：实时天气不走 web_search，走正式 API。

#### 数据模型

建议新增 companion-owned 表或 SharedLife entity subtype：

| 字段 | 含义 |
|---|---|
| `date` | 日期 |
| `location` | 城市 / 区域 / 出发地 |
| `weatherSnapshot` | 温度、湿度、风力、降水、紫外线 |
| `outfitItems` | 短袖、外套、长裤、鞋、帽子等 |
| `subjectiveFeeling` | 冷 / 刚好 / 热 / 潮 / 晒 / 风大 |
| `commuteContext` | 步行、公交、地铁、打车、暴露时长 |
| `sourceMessageId` | 用户回复证据 |

第一版可以先用 `SharedLifeEntities` 的 `entityType = outfit_log` 或 `daily_preparation` 验证；稳定后再决定是否独立表。

#### 推送内容

由角色说，结构固定但语气角色化：

1. 天气简报：温度、雨、晒、风。
2. 装备清单：
   - 降水概率 > 30%：带伞。
   - 紫外线强：帽子 / 防晒。
   - 风力大：薄外套防风。
3. 交通建议：
   - 极端天气 / 高温 / 暴雨：建议公交或打车，别硬走。
4. 穿衣建议：
   - 以昨日穿着和昨日体感为锚点。
   - 输出相对变化，不输出泛泛“25 度穿短袖”。
5. 学习问题：
   - “你今天打算穿什么？”
   - 用户回复后入库，作为第二天锚点。

#### 分期

| 阶段 | 目标 |
|---|---|
| O0 | 手动记录今日穿着，能查询昨日穿着 |
| O1 | 固定时间天气提醒 + 穿着提问 |
| O2 | 昨日锚点相对建议 |
| O3 | 结合日程和通勤推算提醒时间 |
| O4 | 多日学习，形成用户体感模型 |
| O5 | 极端天气交通建议和个性化冷暖阈值 |

### 5.3 Reading Companion

当前状态：主链路基本打通。

已具备：

- Chat message addenda 基础设施。
- 小红书 / 微信公众号 capture。
- reading_item entity。
- 正文抓取、封面、作者、摘要。
- LoadReadingContent tool。
- 角色可自然讲解，不需要按钮式 session。

后续重点：

1. 连续抓取失败后提示重新登录。
2. Reading card 合并进 Memory Summary Card / LinkAttachment 体系。
3. 在 Memory Review / Interests 屏里提供“聊聊”入口。
4. 支持对阅读内容生成用户自己的感受记忆，而不是只保存链接本体。

### 5.4 财务认知

目标不是自动支付，而是角色拥有“自己的账本意识”。

边界：

- 不接真实支付 / 转账 / 代扣。
- 所有钱仍然是用户的真实账。
- AI 账本是从真实账派生的角色视图。
- 角色可提醒“我攒到多少 / 欠你多少 / 该手动转账了”。

路线：

1. 统一收入 / 支出记录结构。
2. 支持 AI 相关标签和贡献比例字段。
3. 派生 AI ledger：结余 + 欠款两本，不用负数。
4. 角色查询工具读取账本并用人设口吻表达。
5. 达到阈值时由角色主动提醒。

### 5.5 语音与通话

已有基础：

- 语音输入。
- MiniMax / ElevenLabs TTS。
- 语音通话、系统级来电、后台追说。
- 蓝牙/媒体键相关路径。

路线：

1. 稳定 MiniMax TTS 中文音色和错误恢复。
2. 语音通话中复用最新记忆边界，不把所有通话内容默认进 User-truth。
3. 语音结束后按 scope 生成关系摘要或明确记录。
4. Live conversation 优先服务角色关系层，而不是做成通用助手语音搜索。

### 5.6 搜索与召回

旧需求：

- 聊天搜索：关键词、时间跳跃、语义搜索。
- PKM 混合检索：FTS5 + vector。

新定位：

- 用户可以跨 sandbox 搜索。
- 角色只能访问自己的 sandbox 和共享 User-truth。
- User-truth、Reading、Finance、Schedule 都需要统一检索入口。

分期：

1. 角色聊天 FTS 搜索。
2. User-truth / SharedLife FTS 搜索。
3. 时间跳跃。
4. 本地或自带 provider embedding 的混合检索。
5. Agent 工具只返回 narrow retrieval，不整库塞上下文。

### 5.7 健康、设备和行为辅助

已有能力：

- COROS / health data。
- phone usage。
- device app blocker / focus lock。
- 成人设备控制相关实验能力。

路线判断：

- Health / Body 是观察面候选，不急着视觉化。
- Focus / blocker 属于“行为辅助”，可以先放系统层设置和角色工具里。
- 设备控制能力必须维持明确用户授权和边界，不进入主动陪伴默认策略。

---

## 6. 阶段路线图

### Phase A：收束规则，停止继续扩散

目标：先让项目不再朝多个方向撕裂。

产出：

- 本 roadmap 成为后续决策入口。
- 明确“普通聊天默认不自动生成 User-truth 卡片”。
- 给当前 capture pipeline 加开关或 scope 策略。
- 标出旧 Card Agent / Timeline / Insight 在 Here I Am 里的兼容地位。

验收：

- 新功能能回答“它属于角色关系、User-truth、生活产物还是主动陪伴”。
- 新卡片能回答“它是 Summary Card、Full Detail View、聊天简化召回，还是 Insight Card”。

### Phase B：记忆契约重构

目标：实现角色 sandbox 与 User-truth 的明确边界。

任务：

- 每条角色聊天默认只进入对应 sandbox。
- 消息级“记录”入口。
- 悬浮球保存 / 发送的产品灰盒。
- Assistant character / 助手型角色概念。
- User-truth operation 支持显式 promote source。
- 关系 insights 与 User-truth insights 分离。

验收：

- 用户能把某条聊天显式记录成共享记忆。
- 普通私密/roleplay 聊天不会自动出现在 Memory Review。
- 角色不能跨 sandbox 读取其他角色私密内容。

### Phase C：Memory Card 体系落地

目标：用新 Memory Summary Card 替换”旧 timeline 卡片思维”。

任务：

- 定义 `presentationModule` 数据结构。
- 实现 Text / Quote / Number / Table / Media / LinkAttachment 第一批板块。
- Summary Card 完整形态。
- 聊天召回简化形态。
- Full Detail View 展示来源和历史。
- 悬浮球修正入口（悬浮球在卡片页面自动关联当前卡片上下文，替代独立”聊聊”按钮）。
- **情绪坐标标注**：RecordOrganizerAnalyzer 在产出 `memorySummary` / `structuredFields` 时同时输出 `valence` / `arousal`，落入已有的 `SharedLifeEntities.valence` / `arousal` 字段。可视化留到 Phase G，但每条新记忆从 Phase C 开始就带坐标，避免历史空窗。

验收：

- 一条 User-truth 能在 Review 中以凝露卡显示。
- 同一条记忆被角色召回时能用简化卡显示。
- 用户能进入详情看到来源证据，而不是只看到 AI 改写。

### Phase D：UI 第一版产品化

目标：把 UI 设计从文档推进到可用页面。

任务：

- HereIam 主题 token。
- Presence ring。
- Chat surface。
- Memory Review item。
- Dew Card。
- Settings hatch entry。
- 拆分旧 Life Space。

验收：

- Chat 仍保留所有现有功能。
- Personal / Settings 不再塞在生活空间三页签。
- Memory Review 和 Schedule 有明确入口。

### Phase E：主动陪伴第一批闭环

目标：让主动功能从“能推送”变成“懂上下文、有学习循环”。

设计细节见：`docs/companion-first/MAP_WEATHER_COMPANION_PLAN.md`。

优先功能：

1. 每日出门提醒 / 地图与天气陪伴。
2. 睡前 / 起床类陪伴。
3. 财务阈值提醒。
4. 日程提醒和 schedule chip。

每日出门提醒是本阶段样板，因为它同时验证：

- API 数据接入。
- User-truth 学习循环。
- 相对体感模型。
- 角色语气推送。
- 日程和通勤上下文。

地图与天气能力的产品承诺：

- 记忆卡片来源地点 tag 默认走轻量 OSM / Nominatim，不追求高精度；实时地址解析失败时可用高德 Key 兜底。
- 高德地图 API 用于门到门路线规划、公交地铁陪跑、POI、周边推荐和国内网络下的实时地址解析兜底。
- 天气提醒不做全天播报，只在影响出门、带伞、温差、暴晒、长步行等行动决策时介入。
- 角色用自然聊天语气表达路线和天气建议，不把用户推到系统式报告里。

验收：

- 用户连续记录几天穿着后，系统能基于昨日锚点给出相对建议。
- 提醒里能区分天气装备、交通建议、穿衣建议。
- 用户回复“今天穿什么”后能入库并被第二天使用。
- 用户说从某个大厦到某个小区，角色能规划门到门路线，而不只处理公交地铁报站。
- 用户出门前若返程时段有雨、温差大或路线有长步行，角色能自然提醒带伞、外套或调整交通方式。

### Phase F：垂直生活面补齐

目标：让生活产物真正分屏沉淀。

任务：

- Schedule：日程、任务、提醒、出门准备。
- Ledger：真实账 + AI 账本视图。
- Interests：Reading Companion 入口。
- Health / Body：运动、睡眠、身体状态。
- Search：跨 User-truth 和 sandbox 的用户搜索。

验收：

- 每个生活面有清楚的数据来源和入口。
- 不再把所有产物塞进无限 timeline。

### Phase G：高级空间化

目标：核心流程稳定后再做高成本沉浸。

任务：

- 圆柱大厅正式化。
- 记忆云。
- 气泡水珠。
- 坠落 / 回程动画。
- 情绪坐标可视化（坐标本身在 Phase C 已开始标注，这里做记忆云、角晕等空间化呈现）。

约束：

- 不牺牲 Chat 主流程。
- 不牺牲设置和列表可读性。
- 必须有低性能降级版本。

---

## 7. 优先级建议

### 现在最应该做

1. 确认记忆契约重构为最高优先级。
2. 在代码层给 capture pipeline 加 scope 边界，避免继续扩大“自动记卡片”。
3. 先做 Memory Card 数据结构和 Summary Card 最小实现。
4. 把每日出门提醒作为第一个“主动陪伴 + 学习循环”样板。

### 暂时不要投入太深

- 完整 3D 圆柱大厅。
- 完整记忆云。
- 大量新卡片外壳。
- 自动支付或任何真实资金动作。
- 泛化过度的 agent 自动规划系统。

### 可以保留但降级为基础设施

- 旧 Memex timeline card templates。
- Insight chart templates。
- P.A.R.A / PKM。
- Card Agent 自动类型匹配。
- Comment Agent，后续更多服务 Moments 或社交表面。

---

## 8. 新功能归属规则

以后新增功能先问四个问题：

1. 它产生的长期产物是什么？
2. 产物应该进入哪个层：角色 sandbox、User-truth、Insight、Schedule、Ledger、Health、Interests？
3. 它是否需要角色主动触达？如果需要，触发条件和冷却是什么？
4. 它的 UI 是 Chat 中的能力、观察面中的产物，还是系统层设置？

示例：

| 功能 | 长期产物 | 归属 | 主动触达 |
|---|---|---|---|
| 每日出门提醒 | 穿衣历史、体感偏好、通勤上下文 | Schedule + User-truth | 是 |
| Reading Companion | reading_item、读后感、摘录 | Interests + User-truth | 低频，可被动召回 |
| AI 财务认知 | AI ledger 派生视图、提醒阈值 | Ledger | 是 |
| 睡前陪伴 | 关系互动、睡眠状态候选 | 角色 sandbox + Health | 是 |
| 小红书抓取 | 链接、正文、摘要、用户感受 | Interests | 否，除非用户要求 |

---

## 9. 已确认决策（2026-06-19 整理会议）

以下问题已在 2026-06-19 的产品整理中确认：

| 问题 | 决定 |
|---|---|
| 首页形态 | 聊天为首页，不做联系人列表 |
| 角色切换交互 | 聊天主界面左右滑动切换角色，所有启用角色参与，按最近聊天排序 |
| 记忆契约 | **最高优先级**。普通聊天不自动生成 User-truth，只处理用户显式记录 |
| 悬浮球 vs “聊聊” | 悬浮球替代”聊聊”按钮，在卡片页面自动关联上下文 |
| 角色访问全局记忆 | 通过 tool-call 按需检索 User-truth，不预加载 |
| Agent 架构 | Capture + Card 合并为 Record Organizer；Insights 改 scope；PKM/旧Card 冻结 |
| 模型配置 UI | 按任务类型分组（聊天/记忆整理/日程/内容分析），不按 Agent 名 |
| 设置页清理 | 删除：memex洞察评论（含代码）、本地ASR开关、微信读书连接 |
| 设置页整合 | 语音相关合并为”语音设置”；定位相关合并为”位置服务” |
| 备份系统 | 完整备份（含角色头像/背景）+ 数据导出（User-truth JSON/CSV） |
| 悬浮球保存/发送 | 默认保存（一键），长按/上滑切换为发送给助手角色 |

## 10. 仍待确认问题

- 角色记忆方案选型（需调研小红书等方案后决定）
- 知识管理方案：P.A.R.A. 已放弃，标签保留，具体组织方式待定
- `SharedLifeEntities.entityType` 是否扩展为 `outfit_log` / `daily_preparation`，还是新增独立穿衣表
- 助手型角色默认指派规则
- User-truth insights 是否进入角色上下文，还是仅给用户看
- Memory Card 的 `presentationModule` 是否缓存，还是运行时从 stateJson 生成
- 每日出门提醒第一版选高德还是和风天气作为默认 API
- 通勤推算是否先只支持用户设置的固定地点，不做自动定位
- **聊天消息环境元数据（候补，未排期）**：在每条用户消息气泡下附"时间 · 地点"标签。
  时间来自 `PersonaChatMessage.timestamp`（已有，免费）。地点需要：
  发消息时记录 GPS → 优先用 OpenStreetMap Nominatim 反向地理编码成地名，
  失败且用户配置高德 Key 时用高德兜底 → 缓存复用。
  涉及位置权限、网络节流（公共 Nominatim 1 req/s）、隐私权衡和服务商兜底透明展示。
  价值：给角色一种"知道你在哪"的环境感，比强制用户写地点自然。
  开口要谨慎，建议先做用户开关 + 同地点 dedup 才开放。

