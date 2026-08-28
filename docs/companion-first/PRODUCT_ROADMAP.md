# Here I Am Product Roadmap

> 状态：当前权威产品与执行路线
>
> 最后更新：2026-08-28
>
> 执行基线：`v3-lab`
>
> 审计状态：`authority-preflight` 临时 Goal 已关闭；Goal 1 的 UI-T 真人通过，但 P4 在合并后候选上暴露六类 DomainCommand 生产不可达并真人失败；当前活动 Goal 为 P4 生产接线窄返修，P5 / P6 与最终真人 Gate 继续阻塞

本文回答四个问题：Here I Am 最终是什么、数据以哪里为准、当前真实基线在哪里、下一阶段按什么 Gate 推进。它不是无限任务清单，也不替代阶段 Goal。每次只从本路线提出一个可验收 Goal；Goal 的规划、派发、等待、审计和集成遵守 [`COLLABORATION_EXECUTION_PROTOCOL.md`](../development/COLLABORATION_EXECUTION_PROTOCOL.md)。

领域路线可以细化 Memory V3、白板、阅读、跨设备、教师招聘和数据恢复，但不得覆盖本文已经确认的目标边界与优先级。本文规定目标状态，不会仅凭文字立即改变当前运行 schema：任何数据权威迁移在 ADR、兼容、试迁移、回滚和真人 Gate 通过前，仍以当前运行代码及现行共享契约为唯一运行依据。

2026-08-26 用户明确确认：Goal 1 不取消、不取代；`GOAL-20260826-authority-preflight` 已关闭后，仅恢复 UI-T、P4、P6 返修。三包现已完成隔离交付、审计、逐包本地集成、`108/108` 组合自动验证与 `v3-lab@fad8b736` 的 Windows Debug 集成构建；这不是最终真人通过。Goal 1 已按约回到阻塞态，P5、最终真人 Gate、W4 红灯、push、发布以及正式 Gate 1A-0 均未解锁。

2026-08-28 真人复验推翻了“P4 只差重开 Undo”的旧判断：合并后唯一候选 `v3-lab@53d2dc91` 中，手动六类操作仍绕过 Domain Receipt / 持久 Undo，桌面 Runtime 也没有注册或分发六类 DomainCommand。父 Goal 因此阻塞，用户已创建窄返修 Goal [`GOAL-20260828-p4-production-reachability-repair`](../development/goals/GOAL-20260828-p4-production-reachability-repair.md)；它只补人工 / Runtime 共用生产纵切与退出重开 Undo，不扩张 P5、P6、W4 或 Gate 1A。

2026-08-28 并行例外 Goal [`GOAL-20260828-legacy-cleanup-wave1`](../development/goals/GOAL-20260828-legacy-cleanup-wave1.md) 已验收通过并进入 `v3-lab@a29b212e`：第一批零注册 / 零调用孤岛与退役测试已删除，仍有效的 Tavern / Companion 覆盖已迁移或保留，全仓退役测试编译错误归零。该清理不改变产品路线、数据权威或 P4 主 Goal，也未触碰 SharedLife、CardCache、日程、UI 大簇、schema、依赖或用户数据。

---

## 1. 产品北极星与设备关系

Here I Am 是一个本地优先的 AI companion。用户自然生活、聊天、学习和工作；林埃在合适的时候理解、记住、提醒、回应并协助行动，但不把用户变成数据库管理员，也不把产品变成暴露内部 Agent 结构的任务管理器。

### 1.1 电脑是数据权威，不等于所有交互都必须发生在电脑

- 第一版由用户的主电脑持续运行 Here I Am Core，作为唯一权威写入者和数据恢复起点。
- 手机是同一个系统的便携前端，负责高频聊天、快捷记录和便捷查看；桌面负责深度阅读、白板组织、资料处理和长期任务。
- 日常使用哪一端更多取决于场景，不由数据权威关系决定。
- 当前开发优先级是桌面端；手机新功能开发暂停至 Gate 2 真人评审，或用户明确提出只能由移动场景完成的高频 companion 需求。暂停期间继续维护主聊天、语音、显式记录、近期查看、通知，以及必要的 Core 协议兼容、Android 系统兼容、安全和严重故障修复；不新增页面、完整卡片视图或新的数据产品面。
- 手机与桌面使用同一条主关系聊天、同一份 Memory V3 和同一个逻辑卡片库。白板悬浮球只是主聊天的桌面入口，不建立第二条关系聊天。
- TaskRoom 只服务真正的长期任务，过程与主关系聊天、Dreaming 隔离；主聊天只接收用户需要的目标、决定、依据和结果摘要。

### 1.2 正式产品表面

| 表面 | 当前职责 | 数据边界 |
|---|---|---|
| Here I Am Core（主电脑） | 权威数据、索引、Memory、调度、审计、备份与恢复 | SQLite 和权威文件只由 Core 直接访问 |
| Desktop AI Workbench | 卡片库、白板、阅读与资料处理、林埃入口 | 当前主力开发表面；经 Core 服务读写 |
| Mobile Companion | 主聊天、语音、快捷记录、近期查看与通知 | 便携客户端；不形成第二权威数据库 |

客户端不能通过网络挂载原始 SQLite，也不能各自运行一套需要事后合并的 Memory V3。Core 不可达时，手机只允许保留本地草稿和有界的待上传捕获队列；恢复连接后以幂等操作补交，它不是第二数据库或多主写入者。UI 必须区分 `pending / accepted / rejected / expired / needs_resolution`，不得把待提交内容显示为已经进入权威聊天、Memory 或 Card；依赖 Core 才能形成的关系回复、检索和权威写入等待 Core 恢复。

### 1.3 产品四层保持不变

| 层 | 作用 | 代表能力 |
|---|---|---|
| 角色关系层 | 用户与林埃持续相处 | 主聊天、语音、来电、关系记忆 |
| User-truth 层 | 用户主动确认的真实生活资料 | Memory Card、日程、任务、事实 |
| 生活产物层 | 从 User-truth 和外部数据形成可查看产物 | Memory Review、Schedule、Health、Interests、Project Memory |
| 主动陪伴层 | 林埃基于记忆与现实上下文主动触达 | Check-in、提醒、出门建议、睡前陪伴 |

---

## 2. 不可回退的产品与数据契约

### 2.1 记忆、聊天与事实写入

- 普通角色聊天默认不自动生成 User-truth。
- User-truth 只从消息级“记录”、悬浮球保存、明确自然语言指令、外部数据流和专门学习循环进入；当前唯一整理入口仍是 `RecordOrganizerServiceV3`。
- Dreaming 的 Fragment / Episode / Saga 属于关系记忆沉淀，不等同于 User-truth。
- Project Memory 是 Memory V3 的特殊 domain，不进入普通 User-truth，也不污染关系记忆。
- 林埃读取 User-truth、Project Memory 和卡片内容时按需检索，不把整库预加载进每轮对话。
- 对话中明确说“把这一段整理成日记”等指令，构成范围明确、可审计、可撤销的卡片创建授权；林埃完成后在主聊天中给出简短回应。

### 2.2 统一卡片库

- 手机“记录”页与桌面“卡片库”最终是同一个逻辑卡片库的不同视图；手机 UI 的完整合并不属于近期 Gate。
- 所有可见内容使用同一种稳定 `Card` 身份。书籍、网页、图片、视频、摘录、日记、事实和普通笔记可以有不同预览与能力，但不建立彼此隔离的卡片数据库。
- Card 是中性内容身份，不天然等于 User-truth。事实确认、来源、所有者和审核状态是 Card 的元数据或领域关系；普通工作卡、AI 按用户要求创建的卡片和 Dreaming 观察不能因进入统一卡片库就被标成已确认事实。
- Gate 1A 的 ADR 必须定义最小中性 Card 语义、物理 schema 与迁移映射，但 Roadmap 不提前写死新表名或 `kind / owner / visibility / truth_status` 等枚举。至少必须覆盖稳定 `card_id`、内容角色、owner / created-by、生命周期、当前权威 revision，以及独立的 User-truth / provenance / Evidence 关系。
- 目标模型中，每张 Card 都有一份可读 Markdown envelope；YAML 保存稳定 `card_id`、权威 revision 和开放元数据，正文保存当前 Card 内容。系统只读字段、用户可编辑字段和派生字段必须有明确 schema；文件可由用户人工阅读和编辑。
- 原始书籍、PDF、图片、视频和网页快照属于 `SourceContent / SourceVersion`；Card 的 Markdown 保存其来源引用、用户正文与元数据，不把大文件二进制或整本书正文塞入 Markdown。
- 媒体原件、结构化 Anchor、Evidence Claim、任务回执和其他领域状态继续作为 Markdown 所引用的结构化对象，不要求把全部运行状态序列化进文件。
- SQLite 保存操作日志、白板与关系、同步状态、版本映射，以及可重建的 Card 目录和全文索引。操作日志与不可重建领域状态属于必须备份的结构化权威；目录、FTS 等投影可以重建；二者都不是 Card 当前正文的第二权威。
- 文件夹只表达用户定义的物理收藏位置，不承担固定产品分区语义。标签、双链、搜索与白板负责逻辑组织。
- 普通 Card-to-Card 语义链接以稳定 `card_id` 加可读标题表达；正向 Markdown 链接是这类关系的权威，反链由索引派生。Source/Version/Anchor、Evidence 引用、BoardGroup 和 `BoardEdge` 继续使用各自结构化权威；`BoardEdge` 不反向改写普通双链语义。

### 2.3 Board、Source、Anchor 与删除语义

- `BoardItem` 只表示某张 Card 在某张白板上的一次摆放，保存布局和局部视图状态；删除 BoardItem 不删除 Card。
- 同一卡片可在同一或不同白板出现多次，不复制正文或原件。
- Board 删除与 Card 删除是两条独立生命周期；删除白板不删除其中卡片。
- Card 删除把权威 Markdown 和受管理附件移入应用回收站并写 tombstone；外部删除进入待恢复状态，不伪造仍有正文的空卡片。
- 应用删除与外部删除都提供 30 天恢复窗口；恢复来自最后有效版本。批量或破坏性操作需要明确确认。
- “永久删除”只承诺从在线 Vault、索引和未来备份中移除；已经进入不可变备份的历史密文仍按保留政策到期，产品必须在确认前如实说明，不能暗示会立即从 WORM 历史版本消失。
- 右键菜单必须区分“从白板移除”和“删除卡片”；键盘 Delete 在白板内默认只移除 BoardItem。
- `Anchor` 必须绑定确切 `SourceVersion`。来源变化时只自动迁移精确匹配；模糊匹配待确认，无法匹配继续保留在旧版本。

### 2.4 编辑、版本、冲突与 AI 权限

- App 写入、用户直接编辑 Markdown 和导入文件都进入同一版本链与操作日志。
- 单文件保存使用原子替换；跨 Markdown、Source、operation log、SQLite、FTS 和 Receipt 的提交必须使用显式 intent/journal、revision hash 与启动恢复协议，不能把单文件原子替换误当成跨介质事务。
- 无效 YAML 不覆盖最后有效版本；App 与外部同时编辑时保留双方，不以最后写入静默覆盖。外部修改被接纳时也进入同一版本链，并生成可审计的外部编辑操作。
- 重命名和移动不改变 `card_id`；同哈希重复导入只复用既有 `SourceContent` / object blob，不自动合并逻辑 Card。重复 ID、不同版本、不同译本和用户有意创建的同内容卡片必须显式处理。
- 所有人工和 AI 写操作复用同一 `DomainCommand / Receipt / Undo` 语义，不允许 AI 专用旁路。
- 用户给出明确且有界的创建或编辑请求时，林埃可直接执行并返回回执与撤销；没有授权时只提出建议。破坏性批量操作仍需确认。
- AI 对白板的摆放默认靠近调用位置、选择范围或当前空白视口，并提供定位、高亮和整批撤销；不自动建立固定分区。

### 2.5 当前 Card 与 RichTextDocument 契约的迁移红灯

当前白板卡与 Memory Card 的物理复用可能把普通工作卡写成 `user_truth`；现有白板总纲又把 `RichTextDocument` 的 block tree / marks / asset refs 作为共享持久结构。本路线确认的目标模型是“中性 Card 身份 + Markdown/YAML Card 正文权威”，因此这里包含两项硬架构迁移，不是措辞调整。

在正式迁移 Gate 通过前：

1. 现有 `MemoryCards`、`RichTextDocument` 和当前持久化路径继续作为唯一运行权威，任何功能线不得提前双写或静默破坏调用者；
2. Gate 1A 的第一份 Goal 必须先完成对象盘点与迁移矩阵：现有 Memory Card、白板普通卡、Source、Annotation、Dreaming、Evidence 投影和 TaskArtifact 分别迁移成什么、是否属于 User-truth、由谁写入、正文或状态以哪里为准、如何回滚；
3. W0 必须提交中性 Card 语义与物理 schema、User-truth 关系、Record Organizer 写入边界、正文权威、双向兼容、旧数据迁移和回滚路径的 ADR；Roadmap 不预先决定新建 `cards` 表还是演进现有 schema；
4. 切换后的 Markdown envelope/revision 是 Card 当前正文唯一权威。`RichTextDocument` 若保留，只能作为从权威 revision 可确定性重建的编辑器内存态、可丢弃缓存或兼容输入；它不能独立提交并在重启后与 Markdown 竞争。所有保存只通过同一 DomainCommand 生成新的 Markdown revision、parent hash 和 Receipt；
5. ADR 必须提供现有 block / mark / asset / Anchor 到 Markdown 的映射表与 golden corpus，把每一项标为无损映射、受控扩展、降级保留或迁移阻断；未分类项阻断切换。语料必须覆盖中文 IME、嵌套列表与引用、重叠 marks、代码、图片/视频/附件、脚注候选、空块、历史版本和外部文件编辑；
6. 必须定义 Markdown、Source、operation log、SQLite、FTS 和 Receipt 的唯一 commit protocol，并对文件前后、日志前后、DB 前后、索引前后和回执前后逐点注入崩溃；重启后只能收敛到完整旧 revision 或完整新 revision；
7. 正式切换前必须具备最小外部编辑安全集：重复 ID 检测、无效 YAML 隔离、外部移动/删除、复制、App 与外部并发修改的双方保全，以及最后有效版本恢复；完整导入、搜索和交互体验继续留在 Gate 1B；
8. 旧路径、试迁移、新路径、回滚和再迁移都必须验证主聊天、消息级记录、悬浮球、“记一下”、Memory Review、更正与按需召回连续可用，且普通 Card 不会误入 User-truth；
9. 在任何真实迁移前先建立一份校验锁定、已完成恢复验证的离线救援快照。完成试迁移、保留迁移后新增写入的无损回滚、再迁移和真人签字后，才能切换运行权威。

### 2.6 AI Workbench、权限与视觉边界

- Here I Am 持有产品上下文、权限、审计、撤销和结果落地；Codex App Server 是首个 RuntimeAdapter，不是第二人格。
- 模型 payload 不能扩权；搜索、卡片、白板和文件能力由产品侧按 turn 授权。
- 普通短 turn 不创建 TaskRoom。主聊天与 Dreaming 的生产查询必须排除 TaskRoom lane；若当前实现仍有泄漏，作为数据边界缺陷修复，不能把旧行为提升为产品语义。
- 手机当前唯一主力视觉仍是“春雨昼眠”；Desktop 保持独立信息架构和 `DesktopWorkspaceTheme`，不复制手机页面或整套视觉。
- 记忆云、圆柱大厅、坠落动画、暮雨玫瑰和 R0–R7 时辰色板只作历史追溯。

### 2.7 外部平台内容采集契约

- Here I Am 不使用非官方工具运营用户的平台账号；不得把只读、研究或临时试点包装成账号自动化的生产授权。
- 用户分享链接、截图或文件，只授权处理该项内容，不授权搜索相关 Feed、评论区、用户主页或推荐内容。
- 除非平台提供正式 API 和明确权限，否则禁止登录态自动搜索、翻页和批量读取；登录门槛、验证码或风控状态不是待绕过的技术故障。
- 不通过随机等待、降低频率、UA、浏览器指纹、隐藏 WebView 或模拟真人操作绕过反爬与平台限制。
- 捕获与解析分离：多链接可以在本地提取、规范化、去重并进入 Link Inbox；网络解析只按来源能力逐项、显式执行。待解析项不是 Card、Source 或 User-truth，解析成功并经确认前不得显示成已入库内容。

### 2.8 工程与发布

- 唯一日常开发与集成分支是 `v3-lab`；并行工作使用隔离 worktree 和临时 `codex/*` 分支。
- 同一时刻只有一个活动 Goal、一个验收主窗和一个唯一构建候选。
- 阻塞 Goal 可以保留其历史与未完 Gate，但不得同时派发、集成或构建；只有用户明确确认的、依赖与拥有路径完全隔离的临时 Goal 可以在此期间成为唯一活动 Goal。
- 阶段完成必须经过：工作包交付 → 主窗审计 → 选择性集成 → 统一回归 → 真人验收 → 用户确认 push。
- Android 只构建和安装 `hereIAmV3`；push、发布和破坏性操作不由“执行并派发”自动授权。

---

## 3. 2026-08-26 真实基线

| 领域 | 已建立 | 尚未闭环 |
|---|---|---|
| 已恢复的 AI 工作台 Goal | UI-T 已真人通过；P4 已有六命令 facade / executor、真实 action reader 与重开 hydration 的自动证据；P6 已补 host-owned 生产 Runtime 队列入口；合并后候选 `53d2dc91` 的 exact Goal 组合串行 `112/112`、Windows Debug 构建成功 | P4 真人复验确认人工 UI 与桌面 Runtime 均未接入六命令生产纵切，现由 `GOAL-20260828-p4-production-reachability-repair` 返修；P5 / P6 真人 Gate、W4 红灯仍未通过，构建不等于完成，也未授权 push / 发布 |
| 已关闭的临时预备 Goal | `GOAL-20260826-authority-preflight` 已通过用户真人审阅并关闭，只使用代码实况与合成数据 | 已交付对象盘点、迁移矩阵、golden corpus 与隔离 harness 骨架；没有切换生产权威，也不证明 Gate 1A-0 通过 |
| Desktop Whiteboard | Card/Source/Board/Anchor 骨架、卡片库、画布、链接入库、视频研读、通用命令基础 | Markdown 权威迁移、完整删除/恢复、文件导入与外部编辑冲突、生产搜索和灾难恢复尚未形成统一 Gate |
| Memory / Chat lanes | Memory V3、Dreaming、显式 Record Organizer、Project Memory 与 TaskRoom 数据层已存在 | 中性 Card 与 User-truth 尚未拆清；主聊天和 Dreaming 对 TaskRoom lane 的过滤必须复核，不能假设隔离已经实现 |
| Cross-device Core | 私人电脑唯一权威核心方向、稳定消息 ID、核心 API/change feed、手机 outbox 与部分同步链已存在 | 仍有旧“双机整包往返/last-writer-wins”验收叙事；需统一为单权威 Core、仅提交意图的客户端 outbox 和可防双活的灾难接管 |
| Backup / Restore | 配置加密、S3 推拉、记忆整包快照与恢复前 safety snapshot 已实现 | 现有实现不满足不可变 S3、四份副本、外部资料根、分阶段恢复、密钥恢复和真实灾难演练 |
| Teacher Recruitment | 历史 Phase 0 试点证明登录、检索和查询拆分在技术上曾可运行；教材包已完成 OCR、结构、知识树与查询接口。该试点保留为“技术验证完成、产品路线失效”的历史证据 | 2026-08-26 账号违规预警已推翻登录态 discovery 的生产可用性，登录态小红书 MCP 正式退役。当前可用基线是用户人工选材、链接导入、匿名单篇解析和教材 OCR；尚缺 Link Inbox、本地去重、逐项解析及 `needs_screenshot` 等诚实状态，也尚未建立正式 Source/Evidence/Batch 数据层、全深圳轻量普查、深样本、看板和真人 Pilot Gate |
| Reading / Co-reading | 小说/漫画阅读、Topic Thread、划线批注基础和新调研输入已存在 | 统一 ReadingPackage、白板阅读窗、稳定跨格式 Anchor 与真实作品验收未闭环；主动品味系统明确延期 |
| Mobile Companion | 主聊天、语音、显式记录、Memory V3 与便携捕获能力存在 | 手机新功能开发暂停；Android FGS、数据安全和严重故障修复仍按证据处理，统一卡片库移动视图和 Core 完整切换以后再做 |

当前状态以 [`GOAL-20260824-ai-workbench-wave1.md`](../development/goals/GOAL-20260824-ai-workbench-wave1.md)、[`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md) 和当前可达提交为证据。Roadmap 不把“代码存在、自动 Gate 通过或已经 push”写成“真人通过”。

Android 严重崩溃、Memory 真实误召回、数据损坏、安全漏洞和 Project Memory 权威对账属于持续可信性维护，不因桌面优先而失效。它们由真实证据触发；若需要中断当前 Goal，必须由用户按协作协议明确取代，而不是静默插队。

---

## 4. 固定执行顺序：从安全底座进入真实需求

### Gate 0 — 关闭当前活动 Goal

[`GOAL-20260824-ai-workbench-wave1`](../development/goals/GOAL-20260824-ai-workbench-wave1.md) 在合并后候选 `53d2dc91` 上通过 exact Goal 组合串行 `112/112`、关键守门 `3/3` 与 Windows Debug 构建；UI-T 真人结论继续有效。P4 真人复验随后确认六类 DomainCommand 没有生产调用者，人工 UI 与 Runtime 都未复用同一 Receipt / Undo，因此父 Goal 重新阻塞，并由 [`GOAL-20260828-p4-production-reachability-repair`](../development/goals/GOAL-20260828-p4-production-reachability-repair.md) 接管这一个窄返修。

历史失败与当前未完 Gate 为：

- UI-T：真实系统剪贴板、回复期间编辑、`Win + H` 与菜单主题真人通过；Typeless 2.3.1 不向 Flutter Windows 输入框注入，保留为非阻断外部兼容红灯；
- P4：手动 UI 基础操作流畅，但不产生 Domain Receipt / 持久 Undo；桌面 Runtime 六命令未注册 / 分发，打开白板后仍不可达，当前返修 Goal 必须补生产纵切后重验；
- P5：真实人格 / 长期关系 Memory V3 代码已返修和自动验证，仍须等待 P4 后做真实命中、空、失败和扩权拒绝真人 Gate；
- P6：受控生产 Runtime 入口与全生命周期已经接入；仍须等待 P4 / P5 后做真实 Bridge / App 重启与生命周期真人 Gate。

W4 匿名字幕 `0/18`、第二个 WebView2 播放器重建超时和时间轴拖动消失等缺陷继续作为非阻断红灯，不伪称通过，也不阻塞与视频无关的返修。

**退出条件**：当前 Goal 状态页、`I_PROJECT_STATE.md`、DEVLOG、唯一候选和真人结果全部收口；未通过则返修或由用户正式取代，不能静默进入下一 Goal。

#### 已关闭的临时例外 — Authority Preflight

用户已明确确认 [`GOAL-20260826-authority-preflight`](../development/goals/GOAL-20260826-authority-preflight.md) 曾在 Goal 1 阻塞期间成为唯一活动 Goal，并于 2026-08-26 真人通过、关闭。它只允许：

- 基于当前代码与权威文档盘点 Card、User-truth、Source、Dreaming、Evidence、TaskArtifact 等对象；
- 用合成、无隐私数据建立迁移矩阵、golden corpus 和隔离 harness 骨架；
- 把 P4 / P5 / P6 及其他未通过事实明确标为 unresolved input，而不是假设成立。

它不得修改生产 schema、默认读写权威、Runtime / Memory 接线或真实用户数据，不得把输出称为正式 ADR 通过，也不解锁 Gate 1A-0、1A-1 或后续 Gate。临时 Goal 关闭后，Gate 0 仍须回到 Goal 1 返修与真人验收。

### Phase 1 — Desktop Data-Safe & Basic Operations MVP

这是所有需求驱动开发之前的新硬阶段。它由三个连续 Gate 组成，不得打包成一个无法独立验收的巨型 Goal，也不等同于“已有 S3 按钮能用”或“能创建几张卡片”。

**未来 1–4 周执行窗口**：只承诺完成 Gate 0，并在其关闭后提案 Gate 1A-0；是否能在该窗口内继续进入 1A-1，取决于 ADR、真实数据 fixture、迁移红灯与真人验收。Gate 1B、1C 和 Gate 2 是后续条件式阶段，不以未经验证的“1–2 周”估算作工期承诺。

#### Gate 1A — 数据权威与可逆 Vault 迁移

Gate 1A 是阶段 Gate，不是一个 Goal。它至少拆成以下连续停止点，任何时刻仍只创建一个活动 Goal：

1. **1A-0 — Authority ADR & Migration Harness**：完成权威对象盘点、Card / User-truth / Source / Evidence / Dreaming / TaskArtifact / Capture / ImportCandidate / Link Inbox Item 迁移矩阵、Markdown / RichText 数据流、物理 schema 比较、跨介质 commit/recovery 协议、golden corpus 和隔离迁移 harness；不切换默认运行权威；
2. **1A-1 — Neutral Card & User-truth Decoupling**：落地中性 Card catalog、User-truth 领域关系、Record Organizer 兼容和旧调用者适配；普通工作卡对 User-truth 检索必须零误升格；
3. **1A-2 — Reversible Markdown Vault Cutover**：完成 Markdown revision、外部编辑最小安全集、历史/索引一致性、旧 → 新 → 旧 → 新无损往返和可恢复切换；
4. **1A-3 — Core Intent, Epoch & Fencing Integration**：主电脑 Core 成为唯一权威写入者；客户端只通过版本化 API 提交意图并读取 accepted 状态。outbox 是有界、加密、耐久的提交日志，不是权威数据库；ADR 必须定义对象范围、容量/TTL、满载行为、幂等键、拒绝/过期/人工处理、协议版本以及 Core 接受前不得触发的下游事件。持久 Core epoch / instance id、fencing token、租约或权威登记位置、重新配对、change-feed epoch 和旧 token 失效必须通过故障注入与集成演练。

每个停止点必须独立验收；任一项失败都保持当前停止点为红，返回同一 Goal 返修，不得启动下一项：

`Capture / ImportCandidate / Link Inbox Item` 是捕获与待处理对象，不是 Card、Source 或 User-truth。1A-0 必须定义它们的稳定身份、URL / note id 去重、幂等、取消、失败、重启恢复、Core 接受边界，以及 Core 接受前不得触发的建卡、Source 入库、索引和下游事件；只交付 ADR、fixtures 与迁移盘点，不实现导入 UI，也不扩大成新功能 Goal。

- **1A-0 通过**：ADR 已选择唯一正文权威、操作/领域状态边界和 commit/recovery 模型；迁移矩阵无未分类对象；golden corpus 与隔离 harness 可重复运行；生产运行权威未切换；
- **1A-1 通过**：普通工作卡进入 User-truth 检索或召回的误升格为零；显式记录、主聊天、Memory Review 与既有召回契约连续；
- **1A-2 通过**：锁定的真实数据克隆完成“旧 → 新 → 回滚至旧（保留新路径期间新增写入）→ 再迁移到新”，逐 phase crash matrix 全部收敛，历史、索引与双方冲突内容可核对；
- **1A-3 通过**：指定断网、重放、Core 重启、模拟旧主机返网和 token 过期故障下注入后，无旧 epoch 写入或重复 event，pending / accepted / rejected / expired / needs_resolution 均可核对。

Gate 1A 只验证接管协议与防双活机制；从真实硬盘/S3恢复到新电脑、再让旧主机返网的灾难接管真人演练属于 Gate 1C，避免两个 Gate 重复交付同一闭环。

**Gate 1A 退出条件**：对版本锁定的跨模块 fixtures 与一份经用户批准、校验锁定的真实数据克隆完成“旧路径运行 → 试迁移 → 新路径读写 → 保留新增写入的回滚 → 再迁移”。Card 内容、User-truth 集合、Source/Anchor、operation log、历史和索引逐项核对；全部 crash matrix 收敛；客户端 pending/accepted/rejected 状态诚实；无双重正文权威、重复事件或旧 epoch 延迟写入。不得在唯一生产副本上做首次迁移演练。

#### Gate 1B — 基本操作与外部文件闭环

- 创建、打开、编辑、保存、标签、普通双链、搜索、移动、重命名和导入；
- 外部拖入 Markdown 原子补齐缺失 ID；重复 ID、无效 YAML、文件被删和同哈希导入不静默覆盖；同哈希只复用 Source/object blob，不自动合并 Card；
- 导入明确区分三种模式：复制进受管理 Vault、只读 KnowledgePackage、外部链接。默认受管理复制；外部链接只保存指纹和重新绑定信息，除非另有独立备份证明，否则不计入四副本恢复承诺；
- 从白板移除、删除卡片、回收站、30×24 小时恢复和永久删除确认；应用回收站是用户操作保证，备份保留是另一条灾难恢复政策；
- App/外部并发编辑保留双方；版本历史、Receipt、Undo/Redo、重启恢复和冲突提示可核查；
- 右键菜单和键盘语义与 Card / BoardItem 生命周期一致；
- 搜索覆盖标题、正文、YAML 开放字段、标签与路径，并提供过滤、片段和可重建索引；
- 原始 Vault、便携包、JSONL/CSV 和灾难备份四类导出边界清楚。

一个真实的小型验收纵切使用日记，但不建立日记专用数据库或页面：

- 用户每次记录生成一张独立普通 Card，只通过“日记”标签聚合；
- 用户直接写卡片时林埃不自动插话；
- 用户在主聊天明确委托整理时，林埃创建日记 Card、保留来源并给出简短回应；
- 首页的日/周/月聚合与观察模块不属于本 Gate。

**Gate 1B 退出条件**：用户能在真实 Vault 中完成一次自写日记、一次聊天整理日记、一次外部 Markdown 导入/编辑、一次删除恢复、一次并发冲突保全、一次完整搜索和一次重启后撤销；全过程无静默丢失、事实误升格或不可解释覆盖。

#### Gate 1C — 四副本灾难恢复

Gate 1C 可以由连续子 Goal 交付，但只有三段全部通过才算 Gate 变绿：

1. **1C-a — Manifest & Recoverable A/S3 Pipeline**：冻结全部权威根和外部根证明，接通硬盘 A 与 S3，完成 manifest/schema/hash、可见告警、staging restore 和失败不覆盖现有数据；
2. **1C-b — Offline & Immutable Recovery**：加入硬盘 B、S3 versioning + Object Lock/WORM 或等效不可变策略、最小权限上传/恢复凭据、纸质恢复卡、密钥轮换和随机历史版本恢复；
3. **1C-c — New Core Takeover Drill**：完成原主机不可用、新 Core 恢复与接管、全部旧 device token 失效、可信重新配对、旧主机返网仍被 fencing 的真人演练。

三个子 Gate 也必须分别验收；任何一次 manifest、恢复、凭据、密钥或 fencing 验证失败都保持对应子 Gate 为红并返修，不得把部分演练计为整体通过：

- **1C-a 通过**：硬盘 A 与 S3 都能生成并校验 manifest/schema/hash，从各自副本完成 staging restore；失败路径产生可见告警且不覆盖当前可用数据；
- **1C-b 通过**：硬盘 B 与随机 S3 历史版本均完成隔离恢复，不可变保留和最小权限经反向验证，纸质恢复卡与密钥轮换演练可独立完成；
- **1C-c 通过**：原主机不可用时新 Core 可恢复并接管，旧 device token 全部拒绝，可信设备重新配对成功，旧主机返网后仍不能形成双活或写入新 epoch。

1C-a 只是恢复管线的阶段证明，不解锁 Gate 2；过渡期可继续使用现有 `.memexdata` 手动导出/导入作为救援工具，但它不满足四副本、不可变备份或 RPO 承诺，也不能替代任一 1C Gate。

第一版采用四份副本：

1. 主电脑权威数据；
2. 常连接硬盘 A 的小时级备份；
3. 平时断开的硬盘 B，每周冷备，并尽量与主电脑和硬盘 A 分开存放；
4. 加密、不可变、版本化的 S3 异地备份。

备份清单必须明确覆盖 Vault、SQLite/operation log、受管理 Source objects、外部受管根或其独立备份证明、配置，以及恢复所需的密钥材料；不能只备份旧 `.memexdata`。

目标：

- 数据发生变化后，硬盘 A 与 S3 两份独立备份均须在 1 小时内完成 manifest/schema/hash 验证，才能声明 `RPO ≤ 1 小时`；产品显示最近成功时间、实际数据年龄、磁盘未挂载与网络离线状态，不能把任务已启动或过渡期 `RPO ≤ 24 小时` 当成最终达标；
- S3 使用 versioning 与 Object Lock/WORM 或等效不可变策略；备份凭据不能删除历史对象，`latest` 同步对象不充当备份库；
- 用户级灾难恢复在新电脑准备好后 `≤ 24 小时`；硬件采购/准备时间与应用恢复时间分开记录；
- 默认保留 72 个小时版本、30 个日版本、12 个月版本；硬盘 B 每周更新。该保留政策不替代应用回收站的 30×24 小时保证；永久删除进入不可变历史后只能等待保留到期，用户确认时必须可见；
- 任一副本失败必须有可见告警、最近成功时间和人工处置路径，不以任务已启动代替成功；
- 恢复先进入 staging，完成 manifest/hash/schema/来源根检查后原子切换；失败不得覆盖当前可用数据；
- 提供纸质恢复卡，密钥恢复不以密码管理器为前提，也不能把唯一密钥只放在主电脑或同一个 S3 bucket；
- 每月自动在隔离目录执行恢复测试；初次上线以及备份格式、数据库或权威模型重大变化后执行真人完整恢复演练。

**Gate 1C 退出条件**：从硬盘 A、硬盘 B 和随机一个 S3 历史版本分别完成隔离恢复；再以“原主机不可用 → 新 Core 接管 → 旧主机重新联网”完成真人演练。任一恢复、密钥或 fencing 验证失败都保持本 Gate 为红。

只有 Gate 1A、1B、1C 全部通过，才进入需求驱动纵线。

### Gate 2 — 首个需求驱动纵线：深圳教师招聘 Evidence Pilot

Gate 1 通过后，不继续抽象建设泛化内容平台；直接围绕“拿到深圳初中语文教师编制”验证第一条真实纵线。

#### 2A. 范围

- 只做采集 → SourceVersion → 原子 Evidence Claim → RecruitmentBatch / AssessmentEvent → 教材映射 → 档案与证据看板；
- 使用官方来源、用户在小红书官方 App 中人工发现并主动交付的第一手经验链接 / 截图 / 导出材料、其他可信考情来源和人工补充；小红书仍是重要证据来源，但 Here I Am 不自动搜索；
- `D:\textbook` 作为只读 `KnowledgePackage` 接入，不复制 2160 个节点为 Card，不重建稳定 node_id；
- 默认映射到可靠 section/subsection，只有原文明确时才下钻 concept；
- 招聘批次是统计去重单位，帖子数量只增加证据支持强度，不增加考试发生次数。
- `EvidenceClaim` 是引用 source/version/unit/anchor 的不可变结构化领域记录；需要在卡片库显示时，Evidence Card 只保存 `evidence_id` 和可读投影，不复制一份可独立编辑的 claim 真相。Knowledge、Strategy 与统计同样只引用 Evidence IDs。

#### 2B. 采集与样本

- 先对深圳市直属及各区最近两届开展轻量官方普查，只建立候选总体与覆盖/缺失清单：招聘主体、年份、批次标识、学科、公告 URL、可获取状态、考试结构线索和缺失原因；普查阶段不要求全文抽取。官方网站和明确允许自动访问的公开来源可以使用搜索矩阵；
- 小红书搜索矩阵只作为用户在官方 App 内的人工检索清单，不交给 Here I Am、MCP 或隐藏浏览器自动执行；
- Here I Am 负责从用户主动交付的分享文案中进行多链接本地提取、规范化、URL / note id 去重并进入 Link Inbox；捕获成功不等于解析或入库成功；
- 网络解析采用无登录态、单项、显式触发；评论只有在用户主动交付，或匿名公开页面直接提供时才处理。遇到登录门槛、验证码、风控或访问限制立即停止，转为请求截图、复制正文或人工摘录；
- 再按考试结构、招聘主体、年份、区域和学科差异选择 5–8 个最大差异深样本；不预先指定行政区或每主体帖子配额。每个深样本至少包含一个官方 `SourceVersion`；第一手经验按独立 URL / note id 去重，帖子数量不充当批次覆盖度；
- 连续两个按差异分层选择的深样本，不再产生新的高影响 `EvidenceClaim` 类型、`AssessmentEvent` 结构、教材映射规则或冲突结论时，可以报告“暂时饱和”；否则必须记录缺口和继续条件，由用户决定是否扩样；新官方规则会重新打开相应分层；
- Gate 2 Goal 在采集前必须声明用户人工选材数量、待解析数量、时间预算、OCR/PDF 与 `D:\textbook` 的复用边界和人工补录路径。多链接可以批量本地入队，但不批量并发访问小红书，不设置“多少条绝对安全”的伪阈值，不后台长跑、不自动重试；达到资源上限即停止并报告覆盖不完整。

#### 2C. Evidence 与输出

- 每条 Evidence 是可回到 SourceVersion、SourceUnit 和精确 Anchor 的具体陈述；Source 原文与 EvidenceClaim 分别承担来源权威和声明权威，普通 Card 不因展示 Evidence 就自动成为 User-truth；
- 保留 A/B/C/D 证据等级、抽取置信度、第一手、官方确认、审核状态和冲突组；
- `EvidenceClaim` 不原地改写真相；纠错以 supersede / retract 等新记录表达，并保留原 claim 与理由；
- 冲突证据全部保留，未解决冲突不进入确定性统计；
- 统计同时给出 batch frequency、source support、firsthand support、official support 和近期批次频率；
- 输出每个 Batch 的档案、整体证据看板、知识 × 考核矩阵、来源下钻、数据空白和可解释的候选重点；
- 白板不采用固定资料分区。林埃只需明确说明整理结果在哪里，并对生成、摆放和连线提供回执与整批撤销。

#### 2D. 明确不做

- 不生成 S/A/B/C 学习优先级、“必背知识”和每日计划；
- 不自动修改教材知识树或把可能映射强行挂到 concept；
- 不把 187 个未验证选项顺序的题页自动变成题库；
- 不一次抓全网，不以漂亮百分比掩盖样本偏差；
- 不恢复登录态小红书 MCP，不重新连接用户账号；
- 不自动搜索、翻页、展开评论或读取推荐 Feed；
- 不以降低频率、随机等待、UA / 指纹或模拟真人作为合规依据；
- 不把待解析链接提前创建成成功 Card / Source，也不让失败项伪装成已入库内容；
- 不在 Pilot 完成后自动进入下一阶段。

**退出条件**：端到端 Pilot 报告能够回答样本各自考什么、证据是否一致、哪些模块出现于多少真实批次、哪些材料可映射教材、哪些仍冲突，以及数据模型需要如何调整。用户还必须能用真实资料完成四个任务：比较两个招聘批次的考核差异、把一个候选重点追溯到精确来源、识别一个证据不足而不应行动的信息空白；以及把一组日常刷到的小红书分享文案快速入队，由系统本地提取并去重，在白板通过“解析下一条”逐项处理，关闭重开后队列与状态仍准确，无法访问的项目明确请求截图。该任务验证导入快捷性与状态诚实性，不考验爬虫吞吐量。记录完成时间、错误归因和是否改变下一步人工备考选择；完成后必须暂停，由用户真人评审。

### Gate 3 — Pilot 后重新选择，而不是自动续跑

用户评审 Gate 2 后，再根据当时最紧迫问题只选择一个下一 Goal：

- 扩展到深圳近 2–3 届主要招聘并形成频率矩阵；或
- 将成熟 Evidence 映射为学习、复习和考核闭环；或
- 优先进入试讲材料与训练；或
- 选择移动端统一卡片只读视图、主聊天/Core 同步或其他高频 companion 场景；或
- 处理当时出现的其他真实需求。

Roadmap 不提前承诺 Gate 3 的具体顺序。

---

## 5. 需求出现后启用的能力

### 5.1 学习与试讲

- 教材搜索结果是临时结果；放上白板时才创建稳定 Source Card，保留 package/node/chunk/page/anchor。
- AI 可生成“重点知识白板”，但教材结构重点与招聘 Evidence 提示分开呈现，不制造神秘总分。
- 每日学习计划是引用既有 Cards 的动态队列，不复制卡片或强制创建新白板。
- Practice Card 与 ReviewAttempt 分离；复习选择需解释用户固定、到期、薄弱、章节连续性和成熟 Evidence。
- 语音学习由 Here I Am StudySession 持有状态；实时语音模型只听说并调用受控工具，本地 KnowledgePackage 和 Cards 仍是知识来源。
- 试讲白板支持 PDF、Office、图片、音频、视频和网页的能力级预览；受管理复制为默认，大文件可外部链接，断连后进入重新绑定而不是删除。

### 5.2 用户主动发起的共读

- 导入 TXT/EPUB/PDF 后保留原件，并为某个确切 `SourceVersion` 确定性生成可重建 `ReadingPackage`：章节、段落、稳定 ID、offset/hash、页码或 EPUB spine 和全文索引。Package identity 至少包含 `source_version_id`、parser/deriver version 与 package hash；它不是第二原件或 Card 正文。
- 每轮只在用户允许的 spoiler 边界内按需读取原文；模型预训练知识不能充当书中证据。
- 一张普通书籍 Card 连接原件与 ReadingPackage；在白板上可从收起卡片展开为嵌入式阅读窗。局部阅读位置可以进入 BoardItem `viewState`，但全局阅读进度、正文、Highlight/Annotation 和 SourceVersion 关系不得进入 BoardItem。
- 纯划线只保存 Highlight + Anchor；写批注或明确摘录才创建 Excerpt Card。所有 Anchor 继续指向确切 SourceVersion 与稳定 selector，ReadingPackage 重建不能改变既有 Anchor 的解释；拖出阅读窗时在白板放置同一张卡，不重复生成。
- 思维导图继续使用普通 Cards、Markdown 双链、BoardEdges 和可撤销布局，不创建 Markmap 或特殊地图卡。
- 微信读书不恢复为核心依赖；未来最多提供显式、单向、可失败的导入 provider。

### 5.3 手机统一卡片视图

- 当桌面 Vault 与 Core Gate 稳定、Gate 2 已完成真人评审且用户把移动场景选为下一 Goal 后，手机“记录”页再接入完整统一卡片库；
- 手机允许查看电脑端全部卡片、显式创建和编辑，但仍通过 Core API，不直接持有第二权威 Vault；
- 手机旧卡片设计如何适配桌面能力需要单独 UI 设计，不阻塞当前桌面 Gate。

### 5.4 论文与通用写作

- 近期只复用来源卡、摘录、双链、白板和普通正文卡，不建立论文专用数据库；
- Here I Am 负责研究、论证、材料组织与草稿，Word 负责最终排版与提交；
- 普通“论文大纲”Markdown 卡用有序链接组稿的方案保留为后续候选；
- 脚注、参考文献样式、DOCX 编译与 Word 修改回收只在真实写作瓶颈出现时立项。

---

## 6. 明确暂停与 Parking Lot

### 6.1 等待专题讨论，不进入近期实现

- Desktop 首页完整 dashboard：先盘点所有模块，再分别确定实时、日、周、月等时间尺度、来源、更新节奏和持久化；此前关于“今日总结/今日观察”、0:00 生成、临时保留和沉淀卡片都只是候选。
- 林埃自主预读大多数书籍、形成自己的划线/批注、注意模式和品味轮廓，并据此主动推荐。该系统必须等白板工具流程完成后单独讨论。
- 论文专用组稿、复杂脚注、DOCX 双向同步和 Word 替代。
- 白板范围或整板导出 PDF/图片；保留需求，不占当前 Gate。

### 6.2 明确后置

- 微信读书双向同步、登录 Cookie 字幕增强、本机 ASR 主路径、直播、视频下载和 DRM 内容；
- 泛化 Task Center、完整 Agent 树、自动项目经理和模型自行扩权；
- 在没有真实纵线需求时独立推进 P8 图片生成上板、P9 HTML 原生展示或 FlexNote 长尾；
- 固定白板资料分区、Markmap 特殊卡、知识树自动改写；
- iOS、手机新功能扩张和公开发布准备；
- 记忆云、圆柱大厅、坠落动画和高成本 3D 空间化；
- 自动支付、真实转账或默认设备控制。

除紧急安全、兼容或数据损坏修复外，重新启动暂停项必须满足：当前 Goal 已关闭、依赖 Gate 已绿、用户重新提升优先级，并先更新本 Roadmap。紧急事项若需插队，也必须由用户按协作协议显式取代当前 Goal。

---

## 7. 固定依赖与红灯

| 上游 Gate / 决策 | 解锁 | 红灯处理 |
|---|---|---|
| 当前 AI 工作台 Goal 真人通过 | Gate 1A-0：ADR、盘点与迁移 harness | 自动测试或 push 不能替代真人签字；1A-0 不切换运行权威 |
| Gate 1A-0 真人通过 | Gate 1A-1：中性 Card / User-truth 解耦 | schema、对象映射、RichText 数据流或事务协议未决时不得迁移 |
| Gate 1A-1 真人通过 | Gate 1A-2：可逆 Markdown Vault 切换 | 普通 Card 误升格、旧调用者破坏或双写都会阻断 |
| Gate 1A-2 真人通过 | Gate 1A-3：Core intent / epoch / fencing | 外部编辑、崩溃恢复或无损回滚未绿时不得接管权威 |
| Gate 1A 整体真人通过 | Gate 1B：基本操作与外部文件完整闭环 | 迁移未绿前维持旧读取路径，不形成双重权威 |
| Gate 1B 真人通过 | Gate 1C-a → 1C-b → 1C-c | 无法稳定写入、冲突保全或撤销时，不在其上建立备份承诺；1C-a/b 不提前解锁 Pilot |
| Gate 1A、1B、1C 全部真人通过 | 深圳教招 Evidence Pilot | 任何静默丢失、覆盖、双活或无法恢复都阻断需求纵线 |
| 单权威 Core 与幂等 API已绿，且 Gate 2 真人评审后用户选择移动场景 | 手机完整统一卡片视图 | 禁止 raw SQLite 共享与多主覆盖，也不得绕过 Pilot 后重新选择 |
| SourceVersion / Anchor / provenance | Evidence、阅读摘录、教材回源 | 无原文、无版本或无 Anchor 的判断不得伪装成确定证据 |
| 外部平台账号边界与 Link Inbox 状态诚实性 | 用户选材后的逐项解析与 Gate 2 Evidence Pilot | 任何登录态或隐藏 WebView discovery、自动搜索 / 翻页 / 评论 / 推荐 Feed、验证码或风控后继续绕过，以及待解析项提前写成 Card / Source，均为固定红灯 |
| Gate 2 教招 Evidence Pilot 真人评审 | Gate 3 中按需选择频率矩阵、学习/试讲、移动端 companion 或其他真实需求 | Pilot 完成后必须停止，不自动进入 Gate 3 的任何实现 |
| W4 匿名 Bilibili 字幕严格 Gate `0/18` | 依赖匿名字幕的能力 | 与字幕无关的卡片、Evidence、阅读和数据安全工作可继续 |

---

## 8. 当前活动 Goal 与下一候选

### 阻塞 Gate

父 Goal 的 P5 / P6 真人 Gate、最终收口与正式 Gate 1A-0 都等待 P4 生产接线返修通过。W4 匿名字幕 `0/18`、第二个 WebView2 重建和时间轴缺陷仍是非阻断红灯，不进入本轮返修。

### 当前活动 Goal

当前唯一活动 Goal 是 [`GOAL-20260828-p4-production-reachability-repair`](../development/goals/GOAL-20260828-p4-production-reachability-repair.md)，执行与派发已经用户授权，正在固化不含主工作区 Voice 并行改动的控制面基线。它只把人工与 Runtime 的 create / edit / labels / move / resize / remove 接入同一 DomainCommand / Receipt / Undo，并完成应用退出重开的真人 Gate；不实现 P5、P6、W4 或 Gate 1A。父 [`GOAL-20260824-ai-workbench-wave1`](../development/goals/GOAL-20260824-ai-workbench-wave1.md) 在此期间保持阻塞。

### 下一正式 Goal 候选（尚未创建）

> **Gate 1A-0 — Authority ADR & Migration Harness：完成权威对象盘点、Card / User-truth / Source / Evidence / Dreaming / TaskArtifact / Capture / ImportCandidate / Link Inbox Item 迁移矩阵、Markdown / RichText 数据流、物理 schema 比较、跨介质 commit/recovery 协议、golden corpus 和隔离迁移 harness；不切换默认运行权威，也不实现导入 UI。**

该候选只覆盖 Gate 1A 的第一个正式停止点，不承诺落地中性 Card schema、切换 Markdown 运行权威、完成 Core 接管、基本操作或四副本灾难恢复。它仍需在 Goal 1 通过或被用户正式取消 / 取代、临时预备 Goal 关闭后，由新的验收主窗提出并等待用户确认；`authority-preflight` 的材料可以复用，但不能替代正式 1A-0 Gate。1A-1/1A-2/1A-3、Gate 1B 与 Gate 1C 只在前一停止点真人通过后依次提案，不提前打包。

---

## 9. 已完成交叉审核与持续自查清单

2026-08-26 的产品、架构和执行交叉审核已经完成，用户已确认将审计结论并入本版。以下问题继续作为每个相关 Goal 的硬自查；它们不是留给未来泛泛讨论的开放问题。第 1–4、10–12 项必须由 Gate 1A 的 ADR、fixtures 与连续性 Gate 给出证据，第 5–6 项由 Gate 1C 给出恢复证据，第 7–8、12–15 项还必须由 Gate 2 给出 Pilot 证据：

1. 中性 Card catalog、User-truth 状态和现有 MemoryCards 之间的迁移边界是否清楚？是否仍有把“所有卡片”误当 User-truth 的隐性耦合？
2. Markdown/YAML 作为 Card 正文权威，是否能无损覆盖现有 RichTextDocument、附件、中文 IME、版本和 Anchor？迁移与回滚是否充分？
3. 单权威 Core、客户端待上传队列和灾难接管之间是否仍存在隐含多主或 split-brain？
4. Card Markdown、原始 Source、操作日志和 SQLite 投影的事务边界是否会产生“文件已写但日志未写”或反向不一致？
5. 四份备份是否真正覆盖 Vault、SQLite 操作日志、Source、外部受管根、配置和密钥，而不是只备份旧 `.memexdata`？
6. `RPO ≤ 1 小时`、30 天删除恢复和 72/30/12 保留策略之间是否一致？恢复演练能否证明，而非只证明上传成功？
7. Teacher Recruitment 的 Source / Evidence / Batch / AssessmentEvent / Mapping 是否保持分层，同时避免形成与统一 Card/Source 相冲突的第二内容权威？
8. 全深圳轻量普查和最大差异深样本能否减少样本偏差？“模型饱和”的停止标准是否可操作？
9. 白板嵌入式阅读窗是否继续遵守 BoardItem 只存布局/局部视图、原文归 ReadingPackage/Source 的边界？
10. 当前活动 Goal 的产物有哪些可复用，哪些会被 Markdown Vault 迁移推翻？是否存在不必要返工？
11. 暂停首页、手机扩张、主动品味与论文组稿后，近期路线是否仍能形成可被用户每天真实使用的产品闭环？
12. 待解析 Capture / ImportCandidate / Link Inbox Item 是否被误写成 Source / Card，或在 Core 接受前触发了索引与下游事件？
13. 是否存在任何登录态、隐藏 WebView 或自动 discovery 回退，包括自动搜索、翻页、评论展开和推荐 Feed 读取？
14. 多链接入口是否只做本地提取、规范化、去重和入队，没有把批量收件偷换成批量网络访问？
15. 登录门槛、验证码、风控或匿名访问失败时，是否诚实请求截图、复制正文或人工摘录，而不是继续绕过？

任何一项没有可复核答案时，对应 Gate 保持红。后续修改权威 Roadmap、取消活动 Goal 或创建下一 Goal，仍需用户确认。

---

## 10. Roadmap 维护规则与待对齐文档

在以下时机更新本文：

- 一个阶段 Goal 完成真人验收；
- 产品优先级改变；
- 重大基线、平台事实或依赖被推翻；
- 交叉审核发现经用户确认的缺口；
- 专项 Roadmap 已无法解释真实工作。

普通 bug、单次 handoff 和单个 worker 进度只更新 Goal 状态表、`I_PROJECT_STATE.md` 或 DEVLOG，不重写总路线。

本次重排后，以下文档含有待后续 Goal/ADR 对齐的旧契约或旧优先级；在正式迁移前仍可作为当前实现说明，但不得覆盖本文方向：

- [`CROSS_DEVICE_I_WHITEBOARD_MVP_ROADMAP.md`](CROSS_DEVICE_I_WHITEBOARD_MVP_ROADMAP.md)：统一单权威 Core、灾难接管与手机开发优先级；
- [`MEMORY_DATA_SYNC_ACCEPTANCE.md`](../development/MEMORY_DATA_SYNC_ACCEPTANCE.md)：旧两电脑 `.memexdata` / last-writer-wins 验收，不再作为日常 Core 同步或客户端合并契约；
- [`WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`](../development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md)：RichTextDocument → Markdown 权威迁移，并补充平台账号自动化、登录态 discovery 与反爬绕过禁令；
- [`whiteboard-ui-spine-contract.md`](../design/whiteboard-ui-spine-contract.md)：首页完成定义与白板内阅读窗；
- [`whiteboard-requirements.md`](../design/whiteboard-requirements.md)：首页、日记、论文导出与旧 Draft 优先级；
- [`teacher-recruitment/phase0/ARCHITECTURE.md`](../development/teacher-recruitment/phase0/ARCHITECTURE.md)：删除第 99 行“浏览器、WebSearch 或外置小红书 MCP 找链接”的现行建议；第 310 行起的 MCP 选择与真人试点章节整体改为历史试点、账号预警和退役原因；同时对齐 Evidence Pilot、样本选择与停止 Gate；
- [`teacher-recruitment/phase0/XHS_MCP_READONLY_PILOT.md`](../development/teacher-recruitment/phase0/XHS_MCP_READONLY_PILOT.md)：标记为“历史技术验证完成、产品路线失效，禁止重新连接用户账号”；保留实验结果，不再作为生产接入依据；
- [`WAVE1_LINK_IMPORT.md`](../development/whiteboard-workstreams/WAVE1_LINK_IMPORT.md)：从“多个链接选一个”升级为本地提取、URL / note id 去重并进入待解析 Link Inbox；
- [`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md) 与 [`DEVLOG.md`](../../DEVLOG.md)：**本次已同步**账号预警、登录态 discovery 退役、Link Inbox 边界和后续待对齐事项；
- [`BOOK_READER_TTS_ANNOTATION_PLAN.md`](BOOK_READER_TTS_ANNOTATION_PLAN.md)：ReadingPackage、摘录卡与主动阅读延期。

领域权威索引：

- 协作生命周期：[`COLLABORATION_EXECUTION_PROTOCOL.md`](../development/COLLABORATION_EXECUTION_PROTOCOL.md)
- Memory V3：[`MEMORY_V3_ROADMAP.md`](MEMORY_V3_ROADMAP.md)
- AI 工作台架构：[`AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md`](../development/AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md)
- 当前工作台执行路线：[`AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md`](../development/whiteboard-workstreams/AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md)
- 白板并行契约：[`WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`](../development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md)
- 跨工具连续性：[`LIN_AI_CROSS_TOOL_CONTINUITY.md`](LIN_AI_CROSS_TOOL_CONTINUITY.md)
- 当前项目态：[`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md)
