# Wave 3 × W5 白板与 AI 工作台联合路线图

> 日期：2026-08-23
>
> 状态：Wave 3 × W5 G2/P1/P2/P3 已完成组合回归与 Windows 真人验收，并合入 `v3-lab@dd479858`
>
> 所有者：W0 集成窗口

## 1. 核心结论

AI 集成不等待 FlexNote 3.7 全清单完成。白板达到以下状态后即可进入 P4：

1. 对应 P4 tranche 触及的身份与删除语义稳定：T1/T2 只要求 Card/Board/BoardItem，T4 再要求 BoardGroup/GroupMember/BoardEdge；Source/Object/Anchor 只在媒体、生成与时间标注能力进入时成为前置；
2. 对应 tranche 的 Repository 与 Snapshot 在正常、失败和重启后只有一个产品真相；对象文件真相只约束会写 Source/Artifact 的能力；
3. 开发准入至少有人工等价契约测试，动作不只藏在 Widget 私有状态中；生产启用前必须有真实人工入口调用同一命令；
4. W0 已冻结可供人工 UI 和 Codex 共用的领域命令、授权、receipt、conflict guard 与 inverse；
5. 工具失败零残留，撤销不会覆盖用户后续修改；
6. 真实 Windows 组合验收证明普通对话、人工白板操作和 AI 操作互不回归。

因此采用“命令先冻结、人工与 AI 错峰消费、逐段汇合”，而不是以下任一极端：

- 等 Wave 3 全部完成后才开始 AI；
- Wave 3 与 P4 同时在 Canvas / Repository 内各写一套实现；
- 让 AI 直接调用 Widget、ViewModel、Drift 或任意文件。

## 2. 两条产品线的职责

| 线路 | 负责 | 不负责 |
|---|---|---|
| Wave 3 / FlexNote F | 人工可见交互：卡面、悬浮快捷栏、右键/更多、多选栏、BoardTargetPicker、打开方式、版本/导出、手绘 | Runtime、模型工具协议、模型权限、自建 AI 数据写入 |
| W0 共享命令脊柱 | 稳定 ID、领域命令、Repository 事务、receipt、conflict、inverse/retract、审计与跨模块 fixture | 页面细节、模型推理 |
| W5 / P4 | 将已冻结领域命令包装成受限 Codex 工具，组装授权和批次，返回产品 receipt | 复制人工 UI 逻辑、直接改数据库、重建白板模型 |
| W5 / P1/P2/P5/P6 | 正常 Codex 对话、搜索/上下文、Memory V3 只读人格连续性、长期任务生命周期 | FlexNote 视觉与 Canvas 手势 |

同一个动作只能有一条业务路径：

```text
人工快捷按钮 / 右键 / 快捷键 ─┐
                              ├─ DomainCommand → Repository → Receipt / Undo
Codex Domain Tool ────────────┘
```

## 3. AI 能力对白板成熟度的真实依赖

| AI 能力 | 需要 Wave 3 到什么程度 | 不必等待 |
|---|---|---|
| P1 正常 Codex 对话 | 不依赖白板 | FlexNote、媒体、双链 |
| P2 统一只读搜索 | 稳定对象 ID、只读 Repository facade、权限和输出预算 | 菜单、分组 UI、导出、手绘 |
| P5 Memory V3 人格连续性 | 不依赖白板写能力；只依赖 P1/P2 的 conversation/context 边界 | G2、P4；最终桌面接线放到 G2 后 |
| P6 长期任务队列 | queue core 只依赖 P1；生产写操作依赖 G3a；TaskArtifact 上板依赖 G3c + P4-T1 | FlexNote 全清单 |
| P4-T1 创建 Card 并放板 | Card、Board、BoardItem、原子创建/回滚、重启恢复 | Group、Edge、双链、完整右键 |
| P4-T2 编辑/标签/移动/缩放/移除 | Card revision/hash、RichText 保存、标签语义、BoardItem geometry、冲突撤销 | BoardTargetPicker、Group、Edge |
| P4-T3 建 Board 与批量摆放 | Board/BoardItem 稳定命令、批次回滚、可逆 retract | Group、Edge、双链 |
| P4-T4 分组/连线/搜索整理 | BoardGroup/Member、BoardEdge、anchor side、P2 SearchHitRef、批次撤销 | CardLink/BlockReference |
| P7 内容知识库 | 采集/规划依赖 P2+G3b/G3c；自动建板/分组/连线的原子提交依赖 Artifact Core + P4-T4 | 长期任务不是一次性生成的硬依赖 |
| P8 图片生成上板 | provider/validator 依赖 G3c；完整上板依赖 Artifact Core + P4-T1 与媒体卡 renderer | P4-T4、双链、FlexNote 长尾 |
| P9 HTML 生成查看 | scanner/bundle/CSP 依赖 G3c；完整上板依赖 Artifact Core + P4-T1 与安全 renderer | P4-T4、导出、手绘 |

## 4. AI 最小成熟度 M0-AI 与当前集成条件 J0-Media

M0-AI 是“AI 白板工具可以继续开发”的产品门槛，不是“Wave 3 产品全部完成”。J0-Media 则是当前分支已包含媒体改动后，为得到唯一、可合入候选 HEAD 必须完成的工程收口。两者不得混为同一依赖。

M0-AI 满足后，P4 的命令与工具开发在 G2 和对应 G3a/G3b tranche 后即可开始；当前仍选择先收口媒体再做 G2，是为了消除已经产生的分支重叠，不代表文本 Card、移动或分组在产品上依赖 Bilibili/XHS。

### 4.1 身份与数据真相

- 内容使用 `card_id`；摆放修改使用 `item_id`。同一 Card 的两个 BoardItem 互不误改。
- 移除 BoardItem 不删除 Card / Source；复制 Card 与复用 Card 有不同命令。
- Group/Edge 使用稳定实体；Edge 端点绑定 BoardItem + anchor side，不冒充 CardLink。
- Card、Board、BoardItem、Group、Edge 与 Snapshot 的失败补偿和重启恢复已有自动证据。
- 常规 Card/BoardItem Repository smoke 证明文本与布局操作不依赖媒体 adapter。

### 4.2 人工白板核心

- 首页、卡片库、白板打开/切换可用。
- 普通 Note 为单一无框连续卡面；空白建卡、原位编辑、中文 IME、保存/失败保持可验。
- 选择、移动、缩放、四向连线、撤销/重做、重启恢复稳定。
- 已经真人通过的卡面和连线不得倒退；视频单文档、双 Tab 与纵向笔记作为当前产品回归守门保留，但不是 P4 文本工具的业务依赖。

### 4.3 J0-Media 当前候选收口

- Card/Source/Version/Object 的 canonical、对象 journal、失败补偿与重启恢复形成一个产品真相。
- 当前图片/XHS/Bilibili 轮次形成一个干净、诚实标注能力级别的候选 HEAD；未完成字幕、登录、视频抽流不伪装完成。
- 当前媒体写入不能绕过统一 Repository/Object 生命周期；cached preview 在渲染时零网络、零数据写入。
- 这些条件决定当前分支何时可执行 G2，不决定 P4-T1/T2 的功能设计。

### 4.4 W5 有界闭环

- 普通消息与明确白板动作正确分流，不打开手机模型配置。
- 当前选择只读上下文使用稳定 ID、权限与 UTF-8/数量预算。
- 现有 `groupSelection + connectSelection` 批次原子、幂等、失败零残留、整批撤销、冲突时拒绝覆盖。
- 真人完成一次“选择 6–10 张卡 → 分组连线 → 行动卡 → 撤销”；超时、非法计划或 Runtime 中断时白板不变。这个现有动作是 grandfathered limited vertical；扩大成 P4-T4 前必须迁到 F2 与 P4 共用的 DomainCommand / receipt / inverse。
- 关闭并重开悬浮面板或白板 surface 后，本进程内 receipt 仍可诚实撤销；完整应用重启只要求白板结果恢复，旧行动卡在 receipt 未持久化时必须显示不可撤销。跨应用重启继续撤销留到持久化 receipt Gate。

### 4.5 汇合守门

- Wave 3 只有一个候选 HEAD 和完整 handoff；W5 G0/P1/P2/P3 各自保持独立提交。
- 组合测试覆盖 Card/Item/Edge/Group、Repository、Runtime、selection、flush/reload/undo。
- changed-file analyze、critical fixes、diff check、Windows Debug build 全部通过。
- 共享 schema、依赖、生成文件和身份语义只由 W0 修改。

## 5. 当前第一次 W0 语义汇合

当前两条候选线共同基线为 `427086ae`：

- Wave 3 产品外壳：`codex/whiteboard-wave3-acceptance@b81ba1cf`；
- 卡面/视频/Repository 安全线：`codex/whiteboard-wave3-final-integration@ae3644b5`。

两边架构兼容，但有 11 个重叠文件，禁止自动 ours/theirs 或直接互相 merge。W0 按以下顺序手工汇合：

1. Repository、`RecoverableFileExchange`、Annotation Store 与对象恢复；
2. 视频 domain 与唯一 platform timed-text resolver；
3. Video ViewModel / Screen / Widget 的 capability、epoch、draft、focus 与安全错误；
4. Canvas 媒体导入、缩略图、失败补偿和原位卡面；
5. 双方测试证据并集；
6. 最后统一 `DEVLOG.md`、`I_PROJECT_STATE.md` 和 Wave 3 状态表。

关键取舍：

- `UnifiedCardRepository` 以 `ae3644b5` 的数据不变量为底稿，移植 Wave 3 的 cached thumbnail 与 XHS evidence versioning；
- 视频产品壳保留 Wave 3 的动态 capability handshake / source epoch / resolver，叠加安全线的原子 Annotation、整数毫秒、单文档草稿、焦点和失败脱敏；
- Canvas 以 Wave 3 媒体版为主，所有写入和回滚仍走统一 Repository 真相；
- Bilibili 只有 current/duration/seek readback handshake 成功后才升级时间研读能力；字幕、登录持久化与 XHS 视频可以在 G2 后继续。

## 6. 联合阶段与 Gate

### J0 — 当前轮次冻结

**Wave 3**：完成当前图片/XHS/Bilibili 轮次的真人结论，形成唯一候选 HEAD，不启动新的 FlexNote F 大包。

**W5**：P1/P2/P3 保持已审提交。W5 集成者先发布一个固定、只读的 staging commit（包含 P1→P2，记录基线与升级规则），P5/P6 才能从该 commit 分支；不接主 UI、不合 `v3-lab`，后续只选择性移植功能提交，不携带各自 staging 合并历史。

- P5 只拥有新的 Memory context adapter / tests；P2 Search/Context 与 Memory V3 核心只读。
- P6 只拥有新的 queue service/adapter / tests；TaskArtifact promotion、现有 Task domain 与 Drift 只读，变更交 W0。

退出条件：M0 候选输入齐全、工作树干净、handoff 与测试可复核。

### J1 — W0 第一次语义汇合与 G2

W0 从最新 `v3-lab` 建单一集成分支，先把两条 Wave 3 候选手工汇成一个 Wave 3 HEAD，再一次性合入含 W5 G0 的主基线。

退出条件：M0 全部通过，Windows 真人复核通过，主线冻结为后续命令基线。

### J2 — P1/P2/P3 合入与分层 G3

合并顺序固定：P1 Runtime → P2 Search/Context → P3 Artifact/Batch/HTML 契约。功能分支中的 `DEVLOG.md` / `I_PROJECT_STATE.md` 不自动选边，由 W0 根据 handoff 手工汇总。G3 拆为三个可独立退出的 Gate：

- **G3a 命令与可逆批次**：`DomainToolDescriptor / DomainToolRegistry / DomainOperationBatch / OperationReceipt / conflict guard / inverse / retract`。P4-T1/T2/T3/T4 都依赖对应实体的 G3a tranche；T4 的搜索整理另依赖 G3b。
- **G3b 搜索**：`SearchScope / SearchHitRef / provenance / permission lane`。P4-T4 的搜索整理和 P5/P7 依赖它。
- **G3c 产物与沙箱**：`GeneratedArtifact / ArtifactManifest / ArtifactBinding / ContentBundlePlan`、task artifact promotion 与 HTML sandbox。P7/P8/P9 和 P6 promotion 依赖它，P4-T1 不等待它。

退出条件：契约 fixture 与跨模块测试通过，无 UI/Drift 私有类型泄入 provider-neutral domain。

### J2.5 — 每个 P4 tranche 的固定合并协议

每个 T1–T4 都按同一顺序执行，禁止 F 与 P4 同时编辑共享命令或 Repository：

1. **W0-Cn**：W0 单独实现并合入本切片的 DomainCommand、fixture、Repository adapter、receipt/conflict/inverse；
2. **Human consumer**：W1/W2 从该 commit 创建分支，只把人工入口接到命令；共享命令和 Repository 只读；
3. **P4 consumer**：人工 consumer 或等价人工契约测试合入后，P4 从新基线创建分支，只写 Tool wrapper、授权组装和工具测试；
4. **生产启用**：至少一个真实人工入口已经调用同一 DomainCommand，组合验收通过后才在产品 Tool Registry 启用；
5. 进入下一 tranche 前，W0 发布新的唯一联合基线。

### J3 — FlexNote F1 与 P4-T1/T2 错峰并行

**Wave 3 F1**：单卡悬浮快捷栏、右键/更多的高频子集、颜色、标签、添加到白板、移除/软删、BoardTargetPicker；所有入口调用统一命令。

**P4-T1**：创建文本 Card + 指定 BoardItem。

**P4-T2**：编辑正文/标签、移动/缩放/移除摆放。标签工具必须等 F1 标签命令冻结；已有人工动作可先接其它子项。

每个工具的退出模板：稳定 ID、授权范围、成功、越界拒绝、失败零残留、幂等、冲突、撤销、重启、真实窗口。

### J4 — FlexNote F2 与 P4-T3/T4 错峰并行

**Wave 3 F2**：多选就地栏、聚焦、明确对齐、分组及二级操作、跨板复制/复用、批量标签。

**P4-T3**：建 Board、批量摆放。

**P4-T4**：Group/Member、Edge、搜索整理。现有“分组并连线”保留为有限动作；扩大成通用工具前，必须与 F2 共用命令和撤销语义。

### J5 — 独立 AI 线路

- P5：P1+P2 后即可开发只读 recall/context；G2 后接桌面 UI 和真人验收。
- P6：P1 后开发 queue core；G3a 后开放 enqueue/pause/resume/cancel/retry；G3c + P4-T1 后允许 TaskArtifact promotion 上板。
- **Artifact Core（唯一所有者：W0）**：先基于 G3c 实现 staging/object store、`ContentBundlePlan` executor、promotion/binding、Source/Version/Card/BoardItem 原子落地与恢复；P7/P8/P9 对这些路径只读。
- P8/P9：G3c 后并行各自 provider/validator/scanner；Artifact Core + P4-T1 后完成上板纵切。通用 Canvas artifact host / LOD 由 W1 提案、W0 集成；HTML renderer 由 P9 提案、Windows 依赖由 W0 集成。
- P7：P2+G3b/G3c 后做 knowledge plan、provenance 与 orchestration；外部 URL 获取只调用 W3 提供的只读 `Ingestion` facade，不实现 provider/network/canonicalization。Artifact Core + P4-T4 后完成知识库原子提交。

### J6 — FlexNote 长尾与高级语义

`WAVE3_ACCEPTANCE_MASTER_PLAN.md` §3.7 与 `WAVE3_ACCEPTANCE_STATUS.md` §8 始终是 FlexNote 完整权威清单。J3/J4/J6 只是交付顺序，不取消、合并或改写其中任何条目。特别继续追踪：

- 单卡放大；复制完整 Card；复制稳定卡片链接；
- ContextDock / Pop / 新标签或全屏三种打开方式；
- 卡片信息、历史版本、完整删除影响与危险确认；
- 多选分别修改填充色、文字色、文字背景色；
- 分组改色/重命名/跨板/解除；跨板复制与复用；批量标签；
- 全局悬浮栏的通用文本建卡；
- Markdown / PDF / Word 导出和完整手绘闭环。

这些保留需求，但不反向阻塞 P4 起跑：

- E：CardLink / BlockReference / permanent block id / 反链；
- 历史版本差异与恢复；
- Markdown / PDF / Word 导出；
- Pop、ContextDock、新标签/全屏的完整打开方式；
- Stroke 身份、画笔、荧光笔、橡皮擦与重启恢复；
- Bilibili 登录/自动字幕、XHS 视频、媒体视觉精修。

对应 AI 工具只能在各自共享契约冻结后开放，不能用 BoardEdge、临时 JSON 或 Widget 点击模拟。

## 7. “可以交给 P4”的单项判定

某个人工功能不需要等整个 F 阶段结束，但“允许开发”和“允许生产启用”是两个 Gate。

### 7.1 P4 开发准入

1. 领域对象与目标 ID 已冻结；
2. 有 provider-neutral 命令，不依赖 Widget/BuildContext；
3. 人工等价契约测试已使用该命令；
4. Repository 正常/失败/重启闭环通过；
5. receipt、conflict 和 inverse/retract 明确；
6. 权限范围和批量上限明确；
7. W0 已将该命令合入联合基线并发布 tranche commit。

未满足任一项，P4 只能写 ADR/fixture，不得落生产写工具。

### 7.2 生产启用

- 至少一个真实人工入口已经调用同一个 DomainCommand；
- 人工操作与工具操作产生等价领域结果和 receipt；
- 组合 Windows 验收通过；
- grandfathered `groupSelection + connectSelection` 可继续有限使用，但扩大或注册通用工具前必须满足本节。

## 8. 合并纪律

- 功能分支不直接合 `v3-lab`；W0 只接收干净 commit、handoff、测试和未完事项。
- Wave 3 不修改 Runtime/Search/Tool Host；P4 不修改 Canvas 手势、RichText 内部状态或 Repository 语义。
- 共享 Card/Source/Board/Anchor/Snapshot/Operation、Drift migration、依赖、routing 与 Windows 配置只由 W0 合并。
- Desktop chat UI 由 P1 提案、W0 在 G2/J2 集成；P5/P6 不直接改该 UI。
- Memory adapter 由 P5 拥有，Memory V3 核心只读；Task queue adapter 由 P6 拥有，TaskRoom/TaskArtifact 共享语义与 schema 由 W0。
- Artifact Core 只由 W0 实现。P7 只拥有 knowledge-plan/provenance/orchestration adapter；外部 URL/provider、SafeHttp、canonicalization 与 XHS/Bilibili/YouTube ingestion 继续由 W3 提供只读 facade。P8 只拥有图片生成 provider 与生成 bytes validator；P9 只拥有 HTML 生成/scanner/runtime 提案。跨域接线由 W0。
- Canvas artifact host / LOD 由 W1 提案，W0 集成；P8/P9 不直接并行修改 Canvas screen 或平台依赖。
- `DEVLOG.md`、`I_PROJECT_STATE.md` 与总 roadmap 由 W0 裁决；功能分支保留自身 handoff，状态文件在集成时手工汇总。
- 每个 checkpoint 最多保留一个 Wave 3 候选 HEAD 和一个 W5 联合集成 HEAD，避免再次长期分叉。
- 真实 Windows 同时只运行一个 `memex.exe`；Flutter 全局工具链串行使用。

## 9. 最近两步

1. 以最新 `v3-lab` 为唯一基线，按 `AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md` 启动首批 W4 字幕、Artifact Core、P2 Runtime 搜索接线与 P1 韧性窗口；
2. 字幕抓取升为当前最高产品优先级；W7 一起看视频进入 Parking Lot。P4/P5/P6 只在各自 Gate 合入后进入第二波，不再一次性无依赖并发。

## 10. 当前执行状态（2026-08-23）

- Wave 3 真人产品线：`codex/whiteboard-wave3-acceptance@01213198`，第五轮真人验收已通过；产品代码截止 `b4ced67f`。
- Wave 3 安全线：`codex/whiteboard-wave3-final-integration@ae3644b5`，保留 Repository journal、canonical/objectRef 并发、整数毫秒、对象真实路径 containment、固定错误文案与原子 Annotation。
- W0 唯一 G2 候选：`codex/whiteboard-w0-g2@77facee0`。采用安全线为底，按顺序语义移植产品提交；95 个变更 Dart 文件 direct-dart analyze 零问题，关键修复 3/3，diff check 通过。
- W5 联合 staging 最终 HEAD：`codex/w5-g2-staging@dd479858`。P1、P2、P3 均按“基础提交→加固提交”完整重放，并已快进合入 `v3-lab`。
- 动态 Gate：G2 白板组合回归 269/269 通过；W5 P1→P2→P3 专项回归 117/117 通过。最初 Flutter 无输出的根因是受限环境不能写 SDK cache lock，不是另一开发窗口。
- 构建 Gate：关键修复守门 3/3 后，Windows Debug 联合构建成功，产物为 `build/windows/x64/runner/Debug/memex.exe`。
- 真人入口返修：首个联合候选误显示手机全局记录球且桌面聊天球因重复角色解析消失；现已将记录球限制为 Android/iOS，并把桌面聊天球绑定固定角色 `i`。用户确认桌面入口存在且普通回复正常。
- 真人动作返修：选区整理发送后的 Windows 原生闪退已由 WER + Flutter PDB 定位到无障碍父节点访问冲突；动作前先跨帧释放中文 IME，动作后复用既有画布 ViewModel 原地重载，新增定向回归 2 条，同一选区命令真人复测已正常完成。
- 分组交互返修：真人随后发现 AI 建组后不能整体移动；首轮返修又暴露拖动同时叠加框选、缩放后标题压卡、长名仍溢出及折叠控件错位。现标题完整命中区不再启动 marquee，展开/折叠统一使用固定屏幕像素布局，标题高 30px、卡片间距 16px、最小可用宽 220px，长名只占剩余空间省略，按钮与计数同中线；拖动全部成员仍为一次撤销。完整白板 188/188，Windows 真人确认四项均无问题。
- Gate 结论：同版真人联合验收已完成，最终 Windows Debug 构建成功，候选已合入 `v3-lab@dd479858`。新的生产白板写工具仍须按 P4 与 G3/Artifact Core 边界逐项开放。
