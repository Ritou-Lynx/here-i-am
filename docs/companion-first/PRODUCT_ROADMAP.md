# Here I Am Product Roadmap

> 状态：当前权威产品与执行路线
>
> 最后更新：2026-08-24
>
> 执行基线：`v3-lab`
>
> 规划跨度：未来 1–4 周的推进顺序 + 更长期产品方向

本文档回答三个问题：Here I Am 最终是什么、当前真实基线在哪里、接下来按什么顺序推进。它不是任务清单，也不替代阶段 Goal；每次只从本路线提出一个可验收 Goal，Goal 的规划、派发、等待、审计和集成遵守 [`COLLABORATION_EXECUTION_PROTOCOL.md`](../development/COLLABORATION_EXECUTION_PROTOCOL.md)。

领域路线可以细化 Memory V3、AI Workbench、白板、阅读和跨设备，但不得覆盖本文档的产品边界、优先级和 Gate。若领域文档与本文冲突，以本文和 `AGENTS.md` 为准。

---

## 1. 产品北极星

Here I Am 是一个本地优先的 AI companion。用户自然生活、聊天和工作；林埃在合适的时候理解、记住、提醒、帮忙，但不把用户变成数据库管理员，也不把产品变成一个暴露内部 Agent 结构的任务管理器。

产品分成两个正式表面：

| 表面 | 核心任务 | 当前边界 |
|---|---|---|
| Android Companion | 关系对话、语音、显式记录、生活记忆、主动陪伴、生活观察面 | 主力移动产品；包名固定为 `com.memexlab.hereiam.v3` |
| Desktop AI Workbench | 同一个林埃入口、卡片库、白板、资料研读、受限 AI 操作 | 独立桌面信息架构和视觉；不复制手机页面 |

两端共享林埃身份以及明确约定的 Card / Source / Board / Memory / Project 等内容对象，但不共享页面结构，也不强行共用同一套视觉皮肤。

长期能力仍按四层组织：

| 层 | 作用 | 代表能力 |
|---|---|---|
| 角色关系层 | 用户与林埃持续相处 | Chat、语音、来电、关系记忆 |
| User-truth 层 | 用户主动确认的真实生活资料 | Memory Card、日程、任务、事实、穿衣历史 |
| 生活产物层 | 从 User-truth 和外部数据形成可查看产物 | Memory Review、Schedule、Ledger、Health、Interests、Project Memory |
| 主动陪伴层 | 林埃基于记忆和现实上下文主动触达 | Check-in、提醒、出门建议、睡前陪伴 |

---

## 2. 不可回退的产品契约

### 2.1 记忆与身份

- 普通角色聊天默认不自动生成 User-truth。
- User-truth 只从消息级“记录”、悬浮球保存、明确自然语言指令、外部数据流和专门学习循环进入。
- Dreaming 的 Fragment / Episode / Saga 属于关系记忆整理，不等同于 User-truth。
- Project Memory 是 Memory V3 的特殊 domain，不进入普通 User-truth，也不污染关系记忆。
- 跨工具 closeout 先进入用户级隔离 Project Space；只有政策允许的投影才进入 Here I Am。
- 林埃读取 User-truth 和 Project Memory 时按需检索，不把整库预加载进每轮对话。

### 2.2 UI 与产品表面

- Chat 是 Android 首页；Observe / Life Space 承载 Memory Review、Schedule、Health、Ledger、Interests 等生活产物。
- 手机当前唯一主力视觉是“春雨昼眠”。旧记忆云、圆柱大厅、坠落动画、暮雨玫瑰和 R0–R7 时辰色板均只作历史追溯。
- Desktop 是独立产品表面，只保留首页、卡片库、白板和林埃入口；不得把手机生活页面和 Spring Rain 视觉整套搬过去。
- 主题修复优先在主题边界统一收口，不在几十个调用点逐个补色。

### 2.3 AI Workbench

- Here I Am 持有产品上下文、权限、审计、撤销和结果落地；Codex App Server 是首个 RuntimeAdapter，不是第二人格。
- 普通短 turn 不创建 TaskRoom。TaskRoom 只用于真正需要排队、暂停、恢复、取消、重试或跨时段运行的长期任务。
- 模型 payload 不能扩权；搜索和白板写入能力由产品侧按 turn 授权。
- 白板写操作必须复用人工入口的 DomainCommand / Receipt / Undo 语义；不能建立 AI 专用旁路。
- 共享 schema、依赖升级、生成文件和跨领域语义由集成主窗裁决。

### 2.4 工程与发布

- 唯一日常开发与集成分支是 `v3-lab`；并行工作使用隔离 worktree 和临时 `codex/*` 分支。
- 同一时刻只有一个活动 Goal、一个验收主窗和一个唯一构建候选。
- 阶段完成必须经过：工作包交付 → 主窗审计 → 选择性集成 → 统一回归 → 真人验收 → 用户确认 push。
- Android 只构建和安装 `hereIAmV3`；push、发布和破坏性操作不由“执行并派发”自动授权。

---

## 3. 2026-08-24 真实基线

| 领域 | 已建立 | 尚未闭环 |
|---|---|---|
| Companion Chat / Voice | Chat 首页、文字/图片/语音、流式回复、来电与主动触达基础、春雨昼眠 Chat 首版 | Android 14/15 FGS 修复仍需最终真机 crash-signature Gate；部分语音和 UI 体验继续按真实 bad case 收口 |
| Memory V3 / Dreaming | Memory Card 数据底座、Fragment / Episode / Saga、FTS 与 fallback、召回 trace、Project Memory 查询；显式 User-truth 写入已统一到 `RecordOrganizerServiceV3` | 根据真实 bad case 继续收口召回反馈的跨话题误伤与排序质量，不再以 2026-07-13 的“重新积累 20 条聊天”事故清单作为当前产品 Gate |
| Desktop Whiteboard | F0–F4 数据、卡片库、画布、链接入库、视频研读；UI-0 与安全恢复基线 | Bilibili 匿名字幕严格 Gate 仍为 0/18；平台不暴露匿名轨时必须诚实降级 |
| AI Workbench Phase 1 | 普通 Runtime 对话、stop/resume、受限搜索、选区读取、分组连线与整批撤销、Artifact Core 最小恢复执行器均已合入 `v3-lab` | 通用卡片写工具、Memory V3 人格上下文、长期队列、Artifact 生产 adapter/renderer 尚未完成 |
| TaskRoom 数据层 | TaskRooms / TaskArtifacts / TaskDecisions 和 service 已存在 | 旧 handoff 中的通用 Orchestrator / Agent 树不再作为方向；数据层只服务后续 P6 长任务队列 |
| i / Project Memory | 加密 closeout、幂等、Activity Index、项目隔离和 Dev Room closeout 闭环已建立 | commit / DEVLOG 对账、Review 展示和稳定的跨设备验收仍待推进 |
| 阅读与共读 | 小说/漫画阅读、Topic Thread、划线批注基础版、Kokoro R0 音色实验室 | 真实作品共读验收、真机音色赛马、统一字符定位、可靠续播仍待完成 |
| 配置与数据同步 | 配置加密文件、S3 推拉、记忆数据整包快照和恢复前 safety snapshot 已实现 | 私人电脑 → 工作电脑 → 私人电脑的真人往返尚未签字 |
| 视觉一致性 | 手机全局主题已迁移到春雨昼眠；桌面有独立 `DesktopWorkspaceTheme` | 桌面主题只覆盖部分 `colorScheme`，SnackBar、Dialog、按钮、输入框和菜单仍可能继承紫色全局主题 |

基线事实以 [`AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md`](../development/whiteboard-workstreams/AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md)、[`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md) 和相应 handoff 的最新验收记录为证据；Roadmap 不把“代码存在”写成“真人通过”。

---

## 4. 未来 1–4 周执行路线

这里的周数是容量估计，不是发布日期。任何波次只有在前一 Gate 真实通过后才进入下一波；如果真人验收暴露 blocker，路线按证据重排。

### Wave 1 — AI 工作台基础能力波次（当前活动 Goal，已构建待真人验收）

目标：让林埃在桌面上从“能对话、能做一个固定白板动作”升级为“能安全操作通用卡片、按需读人格记忆、管理真正的长期任务”，同时清掉桌面主题泄漏。

| 工作包 | 闭环 | 依赖与边界 |
|---|---|---|
| W0 集成与验收 | 冻结基线、派发、主动回收、审计、选择性集成、唯一 Windows 候选、真人 Gate | 不在主窗临时替 worker 补功能 |
| UI-T Theme Integrity | 在 `DesktopWorkspaceTheme` 补全 SnackBar、Input、Outlined/Filled/Text/Icon Button、Dialog、PopupMenu 主题并回归九类泄漏路径 | 以 [`COLOR_LEAK_HANDOFF.md`](../development/whiteboard-workstreams/COLOR_LEAK_HANDOFF.md) 为准；不迁移手机视觉，不逐点打补丁 |
| P4-T1/T2 | 创建卡片、编辑正文、标签、移动、缩放和移除摆放；复用 DomainCommand / Receipt / Undo | 退出画布后 Undo 历史丢失必须诚实收口或明确 Gate，不宣称跨 route 持久化已完成 |
| P5 Memory V3 | 将人格与长期关系的只读 recall/context 接入桌面 Runtime | 复用已合入的受限搜索；不写 User-truth，不自动生成记忆卡 |
| P6 Queue Core | enqueue / pause / resume / cancel / retry / status 的长期任务队列 | 复用既有 TaskRoom 数据层和 P1 韧性；普通短 turn 不创建 TaskRoom，TaskArtifact 上板等待 P4 与 Artifact 生产链 |

并行关系：UI-T、P4、P5、P6 可从同一干净 `v3-lab` 基线进入不同 worktree；共享语义变更先回 W0。固定依赖为“已合入搜索 → P5”“已合入 Runtime 韧性 → P6 恢复验收”“Artifact Core + P4 命令 → TaskArtifact/生成物上板”。

退出条件：

- 四个工作包都有 commit、定向测试、changed-file analyze、handoff 和未完事项。
- 主窗完成组合回归、`git diff --check`、唯一 Windows Debug 构建。
- 真人确认九类桌面次级界面不再漏紫色。
- 真人完成至少一次通用卡片操作及撤销/冲突路径。
- P5 能命中和空结果诚实返回，且不能写 User-truth 或通过 payload 扩权。
- P6 能完成排队、暂停/恢复、取消、重试和重启后的诚实状态，不把普通聊天污染成任务。
- W4 字幕红灯继续单列，不被本波次伪装为通过。

### Wave 2 — Companion 可信性与数据恢复波次

目标：把已经存在的 Memory、后台任务和跨设备能力从“实现完成”推进到“真实生活可相信”。

优先闭环：

1. 基于真实 recall trace、用户反馈和已出现的跑题 bad case，收口反馈 penalty 不区分话题造成的跨语境误伤；没有新证据不拍脑袋改阈值。
2. 按 `MEMORY_DATA_SYNC_ACCEPTANCE.md` 完成私人电脑 → 工作电脑 → 私人电脑的配置与记忆数据往返，验证 safety snapshot 和失败恢复。
3. 真机复核 Android 14/15 FGS 三类历史 crash signature 不再出现；失败时回到平台修复 Goal，不以“能安装”代替通过。
4. Project Memory 接 commit / DEVLOG 对账和 Review 展示，保持 Dev Room > Project Memory > Dreaming 的项目事实权威顺序。

退出条件：真实样本与跨设备往返有验收记录；不存在已知静默丢数据、静默误记或恢复覆盖风险；Android 候选完成唯一 `hereIAmV3` 构建与真人签字。

### Wave 3 — 内容生成与白板组织波次

依赖 Wave 1 的 P4 与 Artifact 生产 Gate。目标是让林埃能把资料变成可追溯、可恢复、可编辑的白板产物。

顺序：

1. P4-T3/T4：建白板、批量摆放、分组、连线和搜索整理。
2. P7 内容知识库：采集、来源追踪、多卡生成、建板、建组和连线；只调用既有 ingestion facade。
3. P8 图片生成上板：provider → bytes 校验 → Artifact Core → 图片卡渲染。
4. P9 HTML 原生展示：scanner、离线 runtime bundle、CSP/sandbox 和聚焦交互。

P7/P8/P9 可以分别准备 provider、validator 和 scanner，但任何直接上板都必须等待 Artifact Core 生产 adapter/renderer 和对应 P4 命令。失败恢复、hash、provenance、权限与撤销是完成定义的一部分。

### Wave 4 — 阅读与主动陪伴产品化

目标：选少量高价值生活闭环做真实长期使用，不同时铺开所有观察面。

候选顺序：

1. 小说/漫画各选一部真实作品完成 Topic Thread 共读接续验收。
2. 完成 R0 真机音色赛马，再按“统一字符定位 → 前台听书 → 后台可靠续播 → 划线批注增强”推进。
3. 继续每日出门提醒的相对体感学习闭环，验证穿衣反馈、天气和日程上下文，而不是新增泛天气播报。
4. Memory Review / Schedule / Health / Interests 只围绕已有真实数据收口；Ledger 等尚无稳定数据闭环的页面不抢先做重视觉。

---

## 5. 固定依赖与红灯

| 上游 Gate | 解锁 | 红灯处理 |
|---|---|---|
| Phase 1 Runtime 搜索已合入并通过真实授权拒绝 | P5 Memory V3 只读上下文 | 任何 payload 扩权都直接拒绝 |
| P1 stop/resume 与 provider thread resume 已通过 | P6 长任务恢复 | 没有持久证据时不得显示“仍在运行” |
| Artifact Core 最小执行器已通过；生产 adapter/renderer 待补 | P4 生产写入、P7/P8/P9 上板 | 只有契约或 staging 不得写成产物已落地 |
| P4-T1 卡片命令和 Receipt/Undo | TaskArtifact 上板、批量组织 | AI 不能绕过人工入口和撤销语义 |
| W4 匿名 Bilibili 字幕严格 Gate 0/18 | 自动字幕依赖功能 | 与字幕无关的 P4/P5/P6 可继续；登录 Cookie 需单独隐私 ADR |
| Dreaming 真实 bad case 与 recall trace | 参数调优与更主动的关系召回 | 旧“20 条新聊天”清单只作首次安装回归，不再充当当前阶段 Gate |
| 双机记忆数据往返 | 自动同步、增量合并 | 当前禁止两端离线并发写后互相覆盖 |

---

## 6. 未来方向与 Parking Lot

### 本路线之后

- Memory Card 与 Observe 各生活面形成稳定产品入口。
- 主动陪伴建立频率、安静时段、失败重试和用户关闭边界。
- i / Project Memory 形成可靠的项目 Review，而不是另一套 User-truth。
- Desktop 支持更多 RuntimeAdapter，但继续复用同一权限、审计与结果协议。
- Android 稳定后再推进 iOS 与公开发布准备。

### 明确后置

- W7 一起看视频、Spoiler Gate、模型共同观看会话。
- 登录 Cookie 字幕增强、本机 ASR 主路径、直播、视频下载和 DRM 内容。
- 记忆云、圆柱大厅、坠落动画和高成本 3D 空间化。
- 泛化 Task Center、完整 Agent 树、自动项目经理和模型自行扩权。
- 自动支付、真实转账或默认设备控制。
- FlexNote 长尾、导出、手绘和高级双链。

重新启动 Parking Lot 项目必须满足：当前主 Goal 已通过、依赖 Gate 已绿、用户重新提升优先级，并先更新本 Roadmap。

---

## 7. 当前活动 Goal

用户已于 2026-08-24 按修订确认并激活：

> **[`GOAL-20260824-ai-workbench-wave1`](../development/goals/GOAL-20260824-ai-workbench-wave1.md)：完成 UI-T、P4-T1/T2、P5、P6 的独立交付、W0 选择性集成、统一 Windows 构建和真人验收。**

该 Goal 以 `v3-lab@f88537d72d08531252e2050784d71deba36a517f` 为 B0。状态页已创建，但派发仍等待用户最终授权；W4 字幕 0/18 只登记为非阻断红灯。

如果用户决定先处理 Android 稳定性或 Memory 真实数据验收，必须先取消或取代当前 Goal，并在本路线记录优先级调整；不要在活动 Goal 中静默换方向。

---

## 8. Roadmap 维护规则

在以下时机更新本文：

- 一个阶段 Goal 完成真人验收；
- 产品优先级改变；
- 重大基线、平台事实或依赖被推翻；
- 专项 Roadmap 已无法解释真实工作。

普通 bug、单次 handoff 和单个 worker 进度只更新 Goal 状态表、`I_PROJECT_STATE.md` 或 DEVLOG，不重写总路线。Roadmap 只保留当前真实基线、未来 1–4 周顺序、长期方向和 Parking Lot，不积累流水账。

---

## 9. 领域权威文档

- 协作生命周期：[`COLLABORATION_EXECUTION_PROTOCOL.md`](../development/COLLABORATION_EXECUTION_PROTOCOL.md)
- Memory V3：[`MEMORY_V3_ROADMAP.md`](MEMORY_V3_ROADMAP.md)
- AI 原生工作台架构：[`AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md`](../development/AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md)
- 当前工作台执行路线：[`AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md`](../development/whiteboard-workstreams/AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md)
- 白板并行契约：[`WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`](../development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md)
- 跨工具连续性：[`LIN_AI_CROSS_TOOL_CONTINUITY.md`](LIN_AI_CROSS_TOOL_CONTINUITY.md)
- 阅读器：[`BOOK_READER_TTS_ANNOTATION_PLAN.md`](BOOK_READER_TTS_ANNOTATION_PLAN.md)
- 主动出门陪伴：[`MAP_WEATHER_COMPANION_PLAN.md`](MAP_WEATHER_COMPANION_PLAN.md)
- 当前项目态：[`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md)
