# 白板工作台 — 多 Session 并行执行提示词（v2：Task 0 瘦身 + 新增 Task S 桌面外壳）

> 日期：2026-08-15（v2 修订）
> 使用边界（2026-09-05）：以下任务与测试数量是当时阶段快照，不代表当前待办。续作必须先按当前 Goal / handoff 缩小范围；模型、权限、委派、状态归属和验证强度统一使用根 AGENTS.md 与现行协作协议，不重开已完成首轮。
> 前提：W0–W4 与 W5 Phase 1 数据层均已合入 `v3-lab`。
> **v2 关键修订**：原 Task 0 把"桌面首页工作台外壳"错当成已存在的地基塞了进去，导致任务过大、一下午跑不完，且现状桌面首页只是手机聊天页（`companion_first_shell.dart` 直接 return `PersonaChatScreen(embedded:true)`）套壳，违反 `whiteboard-ui-spine-contract.md` 3.2。v2 把 Task 0 瘦身为**纯管道**，把桌面外壳单独拆为 **Task S**。
> 依据：`WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`（总纲）、`docs/design/whiteboard-ui-spine-contract.md`（页面边界）、`docs/design/whiteboard-visual-rules.md`（灰纸+Palm 视觉）、`docs/design/whiteboard-requirements.md`、`WHITEBOARD_EXTERNAL_REFERENCE_HUABU.md`（Huabu 借鉴）、各 `W*` 状态页、根 `AGENTS.md`。
> 冲突热点（并行禁区，只能由 Task 0 集中改）：`lib/db/app_database.dart`、`*.g.dart`（build_runner）、`lib/routing/router.dart` + `routes.dart`、`pubspec.yaml/lock`。

---

## 依赖关系总览（v2）

```
Task 0（线性阻塞·纯管道，先做完并合入 v3-lab）
   └── 数据库迁移 + Drift 持久化桥 + 路由注册（目标页先占位）
        │
        ├── Task S（桌面首页工作台外壳，产品设计任务，可与并行组同时开，独立 worktree）
        │      按 spine-contract 3.2 重做桌面首页为模块网格，替换"手机聊天页套壳"
        │
        └─(并行, 各自 worktree, 从含 Task0 的 v3-lab 切)
           ├── Task A = W5 Phase 2 编排层（吸收 Huabu 命令架构 + Action Log）
           ├── Task B = W1 画布交互补全（吸收 Huabu 三层命令 + LOD）
           ├── Task C = W2 富文本补全
           ├── Task D = W4 桌面播放器闭环
           └── Task E = W3 安全收口 + UI 入口
```

- **Task 0 是唯一线性前置**，且已瘦身为纯管道（不含任何产品外壳/首页设计）。它动数据库迁移、路由表、pubspec、build_runner，集中一次做完。
- **Task S 是独立的产品设计任务**（桌面外壳/首页工作台），不碰迁移/pubspec，只碰首页 shell 与新首页模块目录，可与 A/B/C/D/E 并行。它依赖 Task 0 的路由注册（用白板入口路由）。
- **A/B/C/D/E 五个窗口路径互不重叠、共享契约只读**，可真正并行，均依赖 Task 0。
- 每个并行窗口用**隔离 worktree + 临时分支**（`git worktree add ../memex-<tag> -b <branch> v3-lab`），最终合并目标 `v3-lab`。
- 开工前核对任务指定的精确本地 `v3-lab` 基线及 Task0 前置，不擅自同步远端或切换承载其他修改的工作树；隔离方式按根 AGENTS。

---

## Task 0 — 生产集成基座 · 纯管道（线性阻塞 · 单窗口 · 先完成）

**是否线性**：是。所有并行任务的前置。必须先完成、验收、合入 `v3-lab`。
**是否新建分支**：是，`codex/whiteboard-w6-integration-base`（已存在，继续用）。完成后合回 `v3-lab`。
**v2 瘦身**：**移除**原第 4 步"首页入口/首页 shell 改造"与第 5 步的字体/视频依赖预声明中一切与产品外壳相关的内容。Task 0 只做"看不见的管道"。

### 可复制提示词（v2 · 瘦身版）
```
按《白板并行开发总纲》执行，你负责 W6 生产集成基座——注意这是 v2 瘦身版，范围比之前小：只做数据管道，不做任何首页/外壳/产品 UI。

第 0 步：核对已有 staged / unstaged 改动并保留；只在获授权的隔离工作树提交本工作包，不把用户现有修改一并 WIP 提交。

先读：总纲、docs/development/whiteboard-workstreams/W0_INTEGRATION.md / W1_CANVAS.md / W5_PHASE1_HANDOFF.md、lib/routing/router.dart、lib/routing/routes.dart、lib/db/app_database.dart、lib/data/memory_v3/db/tables.dart、lib/ui/whiteboard_canvas/whiteboard_snapshot_store.dart。给出不超过 8 行启动声明后动手。

本轮目标（一个可验证闭环，纯数据/路由层）：白板画布数据能存进 Drift（非文件 JSON），杀进程重启后能恢复；并为后续所有窗口预留白板生产路由和数据表，使它们无需再改迁移/路由/pubspec。

必须完成（仅三件，全是管道）：
1. 数据库迁移（唯一一次 bump schemaVersion）：在 lib/data/memory_v3/db/tables.dart（或按现有分层）新增白板生产表 Boards / BoardItems / BoardGroups / GroupMembers / BoardEdges；Source/SourceVersion 若 MemoryCardSources 无法承载则新增对应表；Card 身份优先复用 MemoryCards，不足处以关联表补。在 lib/db/app_database.dart onUpgrade 写迁移，字段先建后建索引。跑 build_runner 生成 .g.dart。写 test/db 迁移测试（空库直建 + 升级 + 索引校验）。
2. Drift 持久化桥：为 WhiteboardSnapshotStore 增加 Drift-backed 实现（保留文件实现供测试/fallback），WhiteboardCanvasViewModel 默认切到 Drift store；WhiteboardSnapshot ↔ Drift 表双向映射，保证 snapshot 往返与重启恢复。
3. 路由注册（唯一一次改 router.dart / routes.dart）：注册并预留全部白板生产路由——白板索引、全屏白板画布(boardId)、唯一卡片库、视频研读(sourceId)、卡片富文本编辑(cardId)、链接导入入口。目标 Screen 一律用【最小占位 Screen】（一块灰纸底 + 页名 + 返回，遵守 WhiteboardCanvasTokens），只把路由路径与参数签名一次定死；真实页面内容由后续窗口在占位 Screen 内填充，不再改 router.dart。

明确不做（v2 重点）：
- 不做首页工作台、不改 companion_first_shell.dart 的首页形态、不加首页入口按钮——桌面外壳是 Task S 的事。
- 不预声明字体/视频等产品依赖（除非迁移或 drift 本身需要）；pubspec 只改数据层真正需要的。
- 不实现 W1 新交互 / W2 富文本 / W3 DNS pin / W4 播放 / W5 orchestration。

共享契约：只读 W0 lib/domain/whiteboard/ 类型；如需变更在 W0_INTEGRATION.md 追加契约变更请求。

验证：flutter test（新迁移测试 + 既有 310 白板测试 + W5 数据层 28 测试无回归）；flutter analyze 目标目录零 error；真实桌面窗口验证画布落 Drift、杀进程重启后恢复（通过路由直接进入白板画布占位/真实页验证，不依赖首页入口）；git diff --check 干净。完成后更新 DEVLOG、I_PROJECT_STATE、handoff，执行 i closeout，提交到本分支（不 push、不自 merge），交集成确认后合入 v3-lab。
```

### 验收标准（v2）
- [ ] schemaVersion 一次性 bump，迁移测试（空库直建 + 升级 + 索引）通过。
- [ ] 白板 6 类生产路由全部注册、参数签名冻结；目标页为最小占位 Screen（不含产品外壳）。
- [ ] 画布数据落 Drift，杀进程重启后白板可恢复（真实桌面验证，经路由直达）。
- [ ] 既有 310 + W5 28 测试零回归；analyze 零 error。
- [ ] **未触碰 companion_first_shell.dart 首页形态、未加首页入口**（那是 Task S）。
- [ ] `git diff --check` 干净；handoff / DEVLOG / I_PROJECT_STATE 更新。

---

## Task S — 桌面首页工作台外壳（产品设计任务 · 并行 · 依赖 Task 0 路由）

**为什么单列**：本项目桌面首页现状是 `companion_first_shell.dart` 直接 return `PersonaChatScreen(embedded:true)`——把手机聊天页拉大套壳，**违反 spine-contract 3.2**（首页应是可编排模块网格）和第 2.9 条（桌面与手机同源但改变呈现密度）。这不是"加个入口"能解决的，是真正的桌面产品外壳重做，需吃透 UI 设计规范，单独一个窗口做。
**是否线性**：否。依赖 Task 0 完成（用其白板入口路由）。可与 A/B/C/D/E 并行。
**是否新建分支**：是，`codex/whiteboard-s-desktop-shell`。
**拥有路径（不重叠）**：`lib/ui/companion/widgets/companion_first_shell.dart`（改造首页形态）、`lib/ui/home/`（新建桌面首页模块网格目录）、对应 test。**不碰** 迁移/路由表主体/pubspec/画布/富文本/视频/抓取/编排目录。

### 可复制提示词
```
按《白板并行开发总纲》与 docs/design/whiteboard-ui-spine-contract.md（第 3.2 节首页）+ whiteboard-visual-rules.md + whiteboard-requirements.md 执行，你负责 Task S 桌面首页工作台外壳。基线：含 W6 基座的 v3-lab（白板入口路由已注册，勿改 router 主体/迁移/pubspec）。

背景问题（务必理解）：当前桌面首页是 companion_first_shell.dart 直接返回 PersonaChatScreen(embedded:true)，等于把手机聊天页拉大，违反 spine-contract 3.2"首页是可编排模块网格"和第 2.9"桌面与手机同源但改变呈现密度"。你的任务是把桌面首页重做成符合规范的模块网格工作台，而不是手机聊天页套壳。

先读：spine-contract.md 全文（尤其 3.2 首页模块清单：林埃观察/日程与待办/今日总结/继续工作/继续阅读/待整理卡片/记忆回顾/后台任务）、whiteboard-visual-rules.md（灰纸 #F0EFEB + Palm 视觉、层级字号 24/15/14/12/11、紧凑高密度、1440×900 单屏无滚动读懂全貌）、companion_first_shell.dart 现状。给 8 行启动声明后动手。

本轮目标（一个可验证闭环）：桌面首页从"手机聊天页套壳"改造为 spine-contract 3.2 的模块网格工作台——首屏在常见桌面窗口（如 1440×900）内高信息密度读懂全貌、不做手机式纵向长页面；至少落地"继续工作（最近白板+活跃任务）"和"待整理卡片"两个有真实数据的模块（点击可进入对应白板/卡片库路由），其余模块可先留带真实/明确标注演示数据的占位卡但不放无行为的装饰按钮；桌面仍复用同一份核心身份与数据（不复制实体、不另造桌面专属数据）。林埃对话改为按需悬浮/可收起，不再常驻占满首页。

明确不做：不改数据库迁移/路由表主体/pubspec、不做白板画布交互（W1）、不做富文本/视频/抓取/编排、不复制内容实体、不把手机聊天页当首页、不恢复常驻顶栏或多卡片库。

共享契约：只读；数据来源用现有 repository/service，不新增数据表。

验证：真实桌面窗口 1440×900 首屏无滚动读懂全貌、各模块点击进入正确路由、林埃对话可悬浮可收起；Widget 测试覆盖模块网格渲染与入口跳转；flutter analyze 目标目录零 error；git diff --check 干净。更新 DEVLOG、handoff，提交 codex/whiteboard-s-desktop-shell，不 push 不自 merge。
```

### 验收标准
- [ ] 桌面首页是 spine-contract 3.2 的模块网格，**不再是手机聊天页套壳**。
- [ ] 1440×900 首屏无滚动读懂全貌，高信息密度，非手机式长页面。
- [ ] 至少"继续工作""待整理卡片"两模块有真实数据且点击进入正确路由；无无行为装饰按钮。
- [ ] 林埃对话按需悬浮可收起；桌面与手机同源、不复制数据实体。
- [ ] 遵守灰纸+Palm 视觉与层级字号；Widget 测试 + analyze 零 error；handoff 更新。

---

## Task A — W5 Phase 2 AI 编排层（并行 · 吸收 Huabu 命令架构 + Action Log）

**是否线性**：否，与 B/C/D/E/S 并行。依赖 Task 0（用其已建 TaskRooms 表，本任务不新增表）。
**是否新建分支**：是，`codex/w5-orchestration`。
**拥有路径（不重叠）**：`lib/domain/whiteboard/orchestration/`（新建）、`lib/domain/whiteboard/agents/`（新建）、`test/domain/whiteboard/orchestration/`（新建）。**不碰** 迁移/路由/pubspec/其它 W 目录。

### 可复制提示词
```
按《白板并行开发总纲》与 docs/development/whiteboard-workstreams/W5_AI_ORCHESTRATION.md 执行，你负责 W5 Phase 2 编排层。基线：含 W6 基座的 v3-lab（TaskRooms/TaskArtifacts/TaskDecisions 表与 TaskRoomService 已就绪，禁止改数据库迁移）。

先读：W5_AI_ORCHESTRATION.md（第 5、6、9 节）、W5_PHASE1_HANDOFF.md、lib/data/memory_v3/services/task_room_service.dart、lib/data/memory_v3/models/task_room_enums.dart、docs/development/WHITEBOARD_EXTERNAL_REFERENCE_HUABU.md（第 1、2 节，重点借鉴）。给出 8 行启动声明后动手。

本轮目标（一个可验证闭环）：用户发一句"帮我生成一张关于X的卡片" → LinAiOrchestrator.classifyIntent 归类 → TaskRouter 固定路由表派发 → 创建 TaskRoom（走 TaskRoomService，状态机合法）→ 结果 compressResult 压缩 → 写回 Memory V3（ConversationTurn 摘要 + TaskRoom 记录 + Artifact），可在库中查到。

必须实现（纯 domain，无 UI）：lin_ai_orchestrator.dart、task_router.dart、model_router.dart（primary→fallback→local 选择 + 额度检查，配置读 ~/.hereiam/whiteboard/model_config.json）、intent_classifier.dart（规则+关键词）、result_compressor.dart（长输出→摘要+决策+产物引用）；agents/ 下用 Mock/接口占位 CodingAgent/ContentAgent（真实 Dev Room Bridge 接线留 Phase 3）。

借鉴 Huabu（设计约束，非复制代码）：
- 命令架构：林埃编排对画布的写操作必须产出 W0 的 WhiteboardOperation[]，走与用户操作同一条执行/撤销路径（未来 Task B 提供的执行器），不另造 AI 专用写路径；系统/agent 创建的节点保留用户现有选择、不抢焦点。
- Canvas Action Log：新增一个 append-only 用户画布行为流的接口设计（只存 NodeRef：id/type/label，绝不存节点内容），供编排/记忆策展消费；失败请求不计数；达阈值才触发一次压缩分析。本轮至少落地接口与写入契约 + 测试，消费端可留接口。

明确不做：不改数据库迁移/路由/pubspec、不实现真实 Coding Agent 执行器、不做任务中心 UI、不碰 W1/W2/W3/W4/S 目录、不自动写 User-truth。共享契约只读；Card/Board 只读用于任务上下文。

验证：test/domain/whiteboard/orchestration/ 单测（意图分类、fallback、路由派发、压缩、写回 Memory V3 端到端、Action Log 只存 NodeRef 不含内容的守卫测试）；至少 1 条跨边界契约测试；flutter analyze 目标目录零 error；不自动写 User-truth（守卫测试）。更新 W5 handoff/DEVLOG，提交 codex/w5-orchestration，不 push 不自 merge。
```

### 验收标准
- [ ] classifyIntent / routeTask / selectModel(含fallback) / compressResult 全有单测。
- [ ] 端到端：一句用户消息 → 创建 TaskRoom + 写 ConversationTurn 摘要 + 存 Artifact，库中可查。
- [ ] 状态转移全经 TaskRoomService 状态机；非法转移被拒。
- [ ] **Huabu 借鉴**：编排写操作产出 WhiteboardOperation[]（同一执行路径）；Action Log 只存 NodeRef 不含内容（守卫测试）。
- [ ] 不自动写 User-truth（守卫测试）；不改迁移/路由/pubspec；≥1 跨边界契约测试；analyze 零 error；handoff 更新。

---

## Task B — W1 画布交互补全（并行 · 吸收 Huabu 三层命令 + LOD）

**是否线性**：否。依赖 Task 0（用其 Drift store 与路由）。
**是否新建分支**：是，`codex/whiteboard-w1-interactions`。
**拥有路径（不重叠）**：`lib/ui/whiteboard_canvas/`、`lib/ui/whiteboard_canvas/engine/`、`test/whiteboard_canvas/`。**不碰** 迁移/路由/pubspec/富文本/视频/抓取/编排目录。

### 可复制提示词
```
按《白板并行开发总纲》与 docs/development/whiteboard-workstreams/W1_CANVAS.md 执行，你负责 W1 画布交互补全。基线：含 W6 基座的 v3-lab（画布已接 Drift store 与生产路由，勿改迁移/路由）。

先读：W1_CANVAS.md 未完事项、lib/ui/whiteboard_canvas/ 全部文件、docs/design/whiteboard-component-spec.md（拖放与 BoardTargetPicker 契约）、whiteboard-visual-rules.md、docs/development/WHITEBOARD_EXTERNAL_REFERENCE_HUABU.md（第 1、5 节）。给 8 行启动声明后动手。

本轮目标（可验证闭环）：在已接 Drift 的全屏画布上补齐生产级交互——① 键盘快捷键（Ctrl+Z/Y 撤销重做、Del 删除、Ctrl+A 全选、方向键微移）；② 卡片库到画布的正式拖放 + BoardTargetPicker（最近白板/搜索/新建）；③ 分组折叠/展开 UI；④ 连线拖拽端点编辑；⑤ 旋转手柄（BoardItem.rotation 已可序列化）。每项都要保存并重启恢复。

借鉴 Huabu（设计约束，非复制代码）：
- 三层命令：把手势解析（UiIntent，依赖选择/剪贴板/viewport 的临时态）与可序列化操作（W0 WhiteboardOperation）彻底分离；一个逻辑动作跨多操作时合并成单个 undo step；操作失败返回不改状态、无副作用。让这个执行器成为"用户和未来林埃编排共用"的唯一写路径。
- 语义缩放 LOD：在现有 viewport culling 之上，加"按 卡宽×缩放 对比屏幕宽度边界切 full/minimal 两档渲染 + 10px 迟滞防抖"，先覆盖文本/图片/网页类卡片，解决 500 卡性能。

明确不做：不改数据库迁移/路由/pubspec、不做富文本编辑器内部、不做视频、不做抓取、不做编排、不改 W0 共享契约（如需变更走 W0_INTEGRATION 契约变更请求）。

验证：test/whiteboard_canvas/ 交互 + 快照往返测试；500 卡 viewport culling + LOD 无回归且有帧率/物化数量对比；真实桌面窗口验收每类交互 + 重启恢复；flutter analyze 目标目录零 error；git diff --check 干净。更新 W1 handoff/DEVLOG，提交 codex/whiteboard-w1-interactions，不 push 不自 merge。
```

### 验收标准
- [ ] 快捷键、拖放+BoardTargetPicker、分组折叠、连线拖拽、旋转手柄五项全部可用且可持久化恢复。
- [ ] **Huabu 借鉴**：UiIntent 与 WhiteboardOperation 分离；单个逻辑动作合并成单 undo step；执行器为用户/编排共用写路径。
- [ ] **Huabu 借鉴**：LOD 分档渲染 + 迟滞，500 卡性能有对比数据、无回归。
- [ ] 真实桌面窗口逐项验收 + 重启恢复；不改迁移/路由/pubspec；共享契约只读；analyze 零 error；handoff 更新。

---

## Task C — W2 富文本补全（并行）

**是否线性**：否。依赖 Task 0。
**是否新建分支**：是，`codex/whiteboard-w2-richtext-plus`。
**拥有路径（不重叠）**：`lib/ui/whiteboard/editor/`、`lib/domain/whiteboard/rich_text_*.dart`、`lib/ui/whiteboard/fonts.dart`、对应富文本 test。**不碰** 迁移/路由/pubspec/画布/视频/抓取/编排/外壳。

> 注意：v2 中生产字体资产不再由 Task 0 预声明。若本任务需要生产字体进 pubspec，先在 W0_INTEGRATION 追加契约变更请求，由集成窗口统一处理 pubspec，避免与并行窗口冲突。

### 可复制提示词
```
按《白板并行开发总纲》与 docs/development/whiteboard-workstreams/W2_RICH_TEXT.md 执行，你负责 W2 富文本补全。基线：含 W6 基座的 v3-lab（勿改迁移/路由；如需生产字体进 pubspec，先在 W0_INTEGRATION 追加契约变更请求，不自行改 pubspec）。

先读：W2_RICH_TEXT.md 未完事项与接入点、lib/domain/whiteboard/rich_text_document.dart / rich_text_controller.dart、lib/ui/whiteboard/editor/ 全部、lib/ui/whiteboard/fonts.dart。给 8 行启动声明后动手。

本轮目标（可验证闭环）：从画布双击卡片进入 CardRichTextEditorScreen，补齐：① 列表嵌套缩进（Tab/Shift-Tab）；② 引用块 children 编辑；③ 图片/附件真实导入（AssetRef 接对象存储路径）；④ 生产字体真机混排渲染（汇文明朝体正文 + Cascadia Code 代码/数字，缺字回退链）；⑤ 编辑保存后 toPlainText() 投影可被卡片库搜索。全程可序列化、可迁移、可恢复。

明确不做：不改迁移/路由、不自行改 pubspec（走契约变更请求）、不决定画布引擎、不做抓取/视频/编排/外壳、不把编辑内容自动升 User-truth、用户批注与林埃批注保持独立归属。共享契约 RichTextDocument 如需升级走 W0 契约变更请求并保持 v1/v2 fixture 可解析。

验证：富文本单测（缩进/引用/AssetRef/字体混排 Widget 测试/纯文本投影/旧 schema 迁移）；中文 IME 真实桌面窗口验收；flutter analyze 目标目录零 error；git diff --check 干净。更新 W2 handoff/DEVLOG，提交 codex/whiteboard-w2-richtext-plus，不 push 不自 merge。
```

### 验收标准
- [ ] 列表嵌套缩进、引用块编辑、图片/附件导入、生产字体混排、纯文本搜索投影全部可用。
- [ ] v1/v2 fixture 仍可解析；旧 schema 迁移测试通过。
- [ ] 中文 IME 真实桌面验收；不改迁移/路由；pubspec 变更走契约请求；批注归属独立。
- [ ] Widget/单元测试通过；analyze 零 error；handoff 更新。

---

## Task D — W4 桌面播放器闭环（并行）

**是否线性**：否，但内部含小前置：先定桌面播放器 ADR（Web IFrame / webview_windows / 外部降级）。若 ADR 结论需新依赖，先在 W0 追加契约变更请求，不在本分支改 pubspec。
**是否新建分支**：是，`codex/whiteboard-w4-desktop-player`。
**拥有路径（不重叠）**：`lib/domain/whiteboard/video/`、`lib/ui/whiteboard/video/`、`test/domain/whiteboard/video/`、`test/ui/whiteboard/video/`、`docs/development/WHITEBOARD_ENGINE_ADAPTER_ADR.md`（仅追加视频播放 ADR 段）。**不碰** 迁移/路由/pubspec 主体/其它目录。

### 可复制提示词
```
按《白板并行开发总纲》与 docs/development/whiteboard-workstreams/W4_VIDEO.md 执行，你负责 W4 桌面视频真实在线播放闭环。基线：含 W6 基座的 v3-lab（如 ADR 需新依赖，先在 W0 追加契约变更请求，不在本分支改 pubspec）。

先读：W4_VIDEO.md（返修后能力矩阵与"真实桌面在线播放未完成"结论）、lib/domain/whiteboard/video/ 与 lib/ui/whiteboard/video/ 全部、DEVLOG 中 W4 桌面 IFrame 相关提交。给 8 行启动声明后动手。

本轮目标（可验证闭环）：先在 ADR 定桌面播放器路线，再用 YouTube provider（能力矩阵中唯一 supported 可控接口）打通真实桌面在线播放：load → play/pause → current/duration → seek → 字幕 cue 点击跳转 → 播放反向高亮 → 创建时间 Anchor + VideoAnnotation Card → 重启恢复。补 YouTube 平台字幕自动获取（timedtext），无字幕时诚实标记"需要字幕"不伪造。

明确不做：不改数据库迁移/路由、不在本分支改 pubspec（超预声明的走 W0）、不绕过 DRM/登录/付费、不做无授权下载、不把逐条播放事件写聊天/记忆、不另建视频卡片库、Bilibili/小红书维持诚实 link-only 占位、不做外壳/编排。共享契约 PlayerCapability 结构只读；time_range positionSpec 提案走 W0。

验证：W4 领域+UI 测试无回归；YouTube 真实在线播放桌面窗口验收（seek/字幕跳转/反向高亮/Anchor/重启恢复）；能力矩阵一致性测试通过；flutter analyze 目标目录零 error；git diff --check 干净。更新 W4 handoff/ADR/DEVLOG，提交 codex/whiteboard-w4-desktop-player，不 push 不自 merge。
```

### 验收标准
- [ ] 桌面播放器 ADR 落定并记录选型理由。
- [ ] YouTube 真实在线播放全链路（seek/字幕跳转/反向高亮/Anchor/重启恢复）桌面验收通过。
- [ ] YouTube 字幕自动获取可用；无字幕诚实标记；Bilibili/小红书维持诚实 link-only。
- [ ] 能力矩阵一致性测试通过；不改迁移/路由、不越权改 pubspec；handoff/ADR 更新。

---

## Task E — W3 安全收口 + UI 入口（并行）

**是否线性**：否。依赖 Task 0（用其链接导入路由入口占位 Screen）。
**是否新建分支**：是，`codex/whiteboard-w3-security-ui`。
**拥有路径（不重叠）**：`lib/data/whiteboard/ingestion/`、`test/data/whiteboard/ingestion/`、Task0 预留的链接导入占位 Screen（仅填充内容，不改 router.dart）。**不碰** 迁移/路由表/pubspec/画布/富文本/视频/编排/外壳。

### 可复制提示词
```
按《白板并行开发总纲》与 docs/development/whiteboard-workstreams/W3_LINK_INGESTION.md 执行，你负责 W3 抓取安全收口 + 真实 UI 入口。基线：含 W6 基座的 v3-lab（链接导入路由已注册，你只填占位 Screen 内容，勿改 router.dart/迁移/pubspec）。

先读：W3_LINK_INGESTION.md（未实现/风险/下一接入点，尤其 DNS rebinding 未 pin）、lib/data/whiteboard/ingestion/ 全部（SafeHttpClient、canonicalizer、LinkIngestionService）。给 8 行启动声明后动手。

本轮目标（可验证闭环）：① 完成 DNS rebinding 防御——把连接 pin 到已验证的 IP（解析→校验私网/元数据/.local→用同一已验证 IP 建连，重定向逐跳复查），不再只做时点校验；② 用 Task0 预留入口做真实 UI：用户粘贴 URL → 调 LinkIngestionService 抓取 → 展示 IngestionResult（正常/失败/权限/不支持四态诚实呈现）→ 显式建 Card 进卡片库。全程可重启恢复。

明确不做：不改数据库迁移/路由表/pubspec、不做视频下载/去水印、不做画布/富文本/视频/编排/外壳、不自动写 User-truth、抓取只输出 IngestionResult 由应用层显式建 Card、去重优先新 SourceVersion 不静默复制 Card。

验证：DNS pin 单测（rebinding 攻击被阻断）+ 既有 W3 68 测试无回归；真实 example.com 抓取/幂等重导/失败态本机通过；UI 四态桌面验收；flutter analyze lib/data/whiteboard/ 零 error；git diff --check 干净。更新 W3 handoff/DEVLOG，提交 codex/whiteboard-w3-security-ui，不 push 不自 merge。
```

### 验收标准
- [ ] DNS rebinding 连接 pin 到已验证 IP，rebinding 攻击测试被阻断；重定向逐跳复查。
- [ ] 真实 UI：粘贴 URL → 抓取 → 四态诚实呈现 → 显式建 Card → 重启恢复。
- [ ] 既有 W3 68 测试无回归；不改迁移/路由表/pubspec；去重不静默复制 Card。
- [ ] analyze 零 error；handoff 更新。

---

## 合并顺序（集成窗口，Task0 之后）

Task0 合入后，各并行窗口按以下顺序合入 `v3-lab`（数据/安全先、依赖/UI 重的后，降低冲突面）：

1. **E**（W3 安全，纯 data 层）
2. **A**（W5 编排，纯 domain 层）
3. **C**（W2 富文本）
4. **B**（W1 画布交互）
5. **D**（W4 视频，可能触及依赖，最后合便于统一验收）
6. **S**（桌面外壳，产品外壳最后合，前面页面都就位后外壳的入口最完整）

每步集成后运行覆盖改动的专项检查，跨模块或共享契约影响再扩大回归；阶段已确认的全量 Gate 仍须完成。共享契约/迁移冲突交 W0 修复，不靠临时 JSON 或 UI 特判绕过。

---

## v2 变更记录（相对 v1）

- **Task 0 瘦身**：移除首页入口/首页 shell 改造（原第 4 步）和产品字体/视频依赖预声明；Task 0 只保留数据库迁移 + Drift 桥 + 路由注册（目标页占位）三件纯管道。
- **新增 Task S**：桌面首页工作台外壳，专做符合 spine-contract 3.2 的模块网格首页，替换"手机聊天页套壳"现状。
- **字体/依赖策略调整**：不再由 Task 0 预声明；需要时由各窗口走 W0 契约变更请求，集成窗口统一改 pubspec。
- **Huabu 借鉴注入**：Task A 加"命令架构 + Action Log"，Task B 加"三层命令 + LOD"，作为设计约束写进提示词与验收。
- **合并顺序**：末尾追加 S。
