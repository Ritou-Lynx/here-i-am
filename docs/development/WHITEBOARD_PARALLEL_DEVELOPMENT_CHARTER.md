# 白板并行开发总纲

> 状态：生效
> 日期：2026-08-14；2026-09-05 精简协作入口，领域契约与既有 Gate 保留。
> 作用：让多个 Codex / Claude Code / Hermes session 在无需重复转述产品历史的情况下，按同一套产品、视觉、数据和集成契约并行开发白板桌面能力。

本文件是白板专项协议。Roadmap、阶段 Goal、验收主窗、子 Agent / 独立任务选择、主动回收与统一验收遵守 `docs/development/COLLABORATION_EXECUTION_PROTOCOL.md`；本文件继续负责 W0–W4、白板共享契约、拥有路径、分支和领域 Gate。两者冲突时，根 `AGENTS.md` 与用户当次明确指令优先；一般协作生命周期用通用协议，白板产品 / 数据 / 视觉边界用本文件。

## 0. 一句话总指令

任何白板相关 session 收到“按白板并行开发总纲，负责 `Wn`”后，必须先读取本文件及其路由的权威文档，声明工作流、拥有路径、共享契约影响和不做事项，再开始实现；不得自行重做视觉方向、复制 Card 身份、把引擎私有格式升格为产品真相，或把任务过程 / 抓取内容自动写入 User-truth。

用户以后只需要说：

> 按白板并行开发总纲，负责 `W2 富文本编辑`，完成本工作流当前最小闭环。

无需再次解释配色、卡片库、白板层级、林埃、记忆或多任务背景。

## 1. 权威资料与冲突顺序

所有工作流先完整读取本文件；以下是冲突优先级，不是每次完整加载的清单：

1. 根 `AGENTS.md`：项目、分支、记忆、安全和 Flutter 架构最高约束；
2. `docs/design/whiteboard-ui-spine-contract.md`：页面边界、领域实体与操作契约；
3. `docs/design/whiteboard-component-spec.md`：组件规范 v0.2、层级、状态与目标白板选择；
4. `docs/design/whiteboard-visual-rules.md`：灰纸 + Palm 视觉规则与真实窗口验收；
5. `docs/design/whiteboard-requirements.md` 第一部分：现行产品需求；
6. `docs/development/WHITEBOARD_ENGINE_BAKEOFF_AND_VERTICAL_SLICE.md`：引擎赛马与第一条领域纵切；
7. 本工作流专属实现说明、测试和 handoff。

随后读取本工作流 handoff 和本轮触及的共享类型 / fixture。W1 涉及引擎时读赛马文档；W1/W2/W4 改 UI 时读脊柱、组件、视觉的相关章节；W3 改抓取时读 Source / Ingestion 与安全章节。当前任务已读过且未变化的资料不重复加载。

参考仓库只提供证据和实现思路，不高于以上契约。发现矛盾时暂停依赖该决定的修改，在 handoff 提出“契约变更请求”，由集成工作流决定；独立工作继续，不静默改写共享概念。

## 2. 已冻结的共同基线

### 2.1 产品表面

- 桌面端只有：首页、唯一卡片库、白板索引、全屏白板，以及按内容打开的阅读 / 视频等消费视图；不恢复双顶栏、最近白板 Tab 条或多个“资料库”。
- 全屏白板无常驻顶栏和聊天侧栏；导航、卡片库、工具、ContextDock 与林埃对话按需悬浮，关闭后完整退场。
- 卡片库只有一个，通过类型、来源、标签、时间和白板归属筛选。
- 林埃是唯一关系主体；Codex、Claude Code、OpenCode 等是任务房间中的可替换执行者，不成为新的产品人格。

### 2.2 视觉与组件

- 基底：Lieflat Mono `#F0EFEB` 灰纸 + 中性墨色；Palm 绿只用于动作、活动态和主数据，琥珀只用于单一焦点或警告。
- 字体：中文汇文明朝体；英文、数字、时间码和代码 Cascadia Code。生产资产仍需子集化和缺字检查。
- 层级：页面标题 24、模块标题 15、内容 / 正文 14、元信息 12、状态 11。
- 时间不是状态，优先级不是类型，`i 的观察`不是 badge。普通模块、类型标签、筛选基线和低值数据使用灰阶。
- 紧凑、低圆角、高密度；首页在常见桌面窗口内读懂全貌，不做手机式长页面。
- 侧栏展开 144–148px、可回收到 0；不用贯穿实线，只用留白、渐隐纸缝与活动水墨。
- 正式植物 `i` 标志来自 `assets/branding/hereiam_v3_logo/`，不得重新画一个圆圈字母占位。

### 2.3 数据身份

- `SourceContent`：原件身份；`SourceVersion`：可锚定版本。
- `Card`：内容在产品中的稳定身份；媒体预览、标题、正文和标签不因进入白板而复制。
- `Board`：白板；`BoardItem`：某张 Card 在某张 Board 上的一次出现，只保存布局与局部视图状态。
- 同一 Card 可产生多个 BoardItem，甚至在同一白板出现多次；删除 BoardItem 不删除 Card 或 Source。
- `BoardGroup / GroupMember / BoardEdge` 是显式实体，不把分组和连线塞进卡片正文。
- `Anchor` 描述原件中的稳定位置；用户批注与林埃批注是独立 Annotation Card，可以共享 Anchor，不能互相覆盖。
- 所有跨设备实体使用稳定字符串 ID；本机整数只作缓存索引。

### 2.4 记忆、任务与权限

- 普通聊天、抓取、播放器进度、编辑历史和任务日志都不自动写入 User-truth。
- 用户明确记录、保存或确认后，Record Organizer 才能整理为 Memory Card / User-truth。
- 多任务以稳定 `task_id` 隔离；任务房间保留完整过程，主聊天只接收用户选中的目标、决定、纠正、依据和结果压缩。
- 林埃对卡片、白板、原件和批注的写操作必须有明确授权、可审计、可撤销。

### 2.5 合规与外部内容

- 链接抓取保存用户有权保存的元数据、正文或快照；保留原 URL、抓取时间、解析器版本和失败原因。
- 视频目标是合规在线播放、时间轴与字幕研读，不以绕过平台限制、去水印或批量下载为产品能力。
- 小红书、哔哩哔哩、YouTube 可以使用不同 provider；正式支持的共同门槛是可读写播放时间、可靠字幕、双向时间跳转和可恢复 Anchor。
- 平台无可靠字幕时明确标记“需要字幕”，不伪造支持；字幕优先平台 / 创作者，其次用户导入 SRT / VTT，权利允许时才做本机 ASR。

## 3. 共享契约与变更纪律

以下属于集成契约，任何单一功能 session 不得单方面改名、改变身份语义或另建平行模型：

| 契约 | 最小稳定内容 | 所有者 |
|---|---|---|
| `CardContract` | card_id、类型、source_id、当前 source_version_id、标题 / 摘要 / 标签、创建与更新时间 | W0 集成 |
| `WhiteboardSnapshot` | boards、cards、boardItems、groups、groupMembers、edges、viewport | W0 + W1 |
| `WhiteboardOperation` | place / move / resize / remove / group / edge / viewport / undo 元信息 | W0 + W1 |
| `IngestionResult` | canonical_url、provider、source / version、媒体与正文能力、错误 / 权限状态 | W0 + W3 |
| `RichTextDocument` | schema_version、block tree、marks、asset refs、纯文本投影、迁移函数 | W0 + W2 |
| `PlayerAdapter` | load、play / pause、current / duration、seek、时间事件、能力声明 | W0 + W4 |
| `TimedTextTrack` | track_id、语言、来源、cue(start/end/text)、可靠性与版权状态 | W0 + W4 |
| `AnchorContract` | source_id、source_version_id、selector / start / end、指纹、解析状态 | W0 + W2 / W4 |

需要变更共享契约时：

1. 在本工作流 handoff 写出问题、提案、迁移影响和兼容方案；
2. 保持现有契约可运行，不先破坏调用者；
3. 由 W0 集成工作流更新权威文档 / schema；
4. 至少增加一个跨模块契约测试后，其他工作流再升级。

## 4. 并行工作流

### W0 — 集成与共享契约

职责：维护领域模型、schema、操作协议、fixture、跨模块契约测试和最终集成顺序；不代替各功能工作流做页面细节。

首要任务：把当前文档契约落成可测试的共享类型 / JSON fixture；完成白板引擎赛马 ADR；为 W2 / W3 / W4 提供不会随 UI 变化的接口。

### W1 — 白板画布与交互

职责：引擎赛马、适配层、viewport、选择 / 框选、多选、拖动、缩放、层级、分组、连线、撤销重做、快捷键和 500 卡性能。

必须遵守：引擎私有节点 ID 只存在于适配映射；卡片内容不写进画布 JSON；删除摆放不删除 Card；全屏无常驻栏；林埃批量操作带审计与整体撤销。

不做：富文本内部编辑、网页解析器、视频 provider、Memory 自动写入。

建议拥有路径：未来画布 feature 目录、引擎 adapter、画布 fixture / tests；修改共享 Card / Anchor 前提交契约变更请求。

### W2 — 卡片富文本编辑

职责：`RichTextDocument`、block / inline mark、输入法、粘贴、链接、图片 / 附件引用、撤销重做、纯文本投影、版本迁移和卡片编辑 UI。

必须遵守：富文本是 Card 内容或 Source 派生内容，不包含白板 x / y / size；媒体卡仍以媒体为主体；编辑器输出可序列化、可迁移、可安全渲染；用户批注与林埃批注保持独立归属。

不做：决定白板引擎、直接抓取任意网页、实现视频播放、把编辑内容自动提升为 User-truth。

首轮验收：中文 IME、混排字体、粘贴清洗、链接 / 图片引用、重启恢复、旧 schema 迁移、纯文本搜索投影。

### W3 — 普通链接抓取与内容入库

职责：URL canonicalization、provider 识别、重定向、安全请求、元数据、正文 / 图片能力、SourceContent / SourceVersion 创建、重复链接合并、失败与重试。

可参考：`feitangyuan/kankan-shoucang` 的小红书链接收集思路，但复制代码前必须核对许可证、依赖与平台约束。

必须遵守：抓取器只输出 `IngestionResult`，由应用层决定是否建 Card；不直接写白板布局；同一 canonical URL 的重复导入优先形成新 SourceVersion 或复用 Source，不静默复制 Card；SSRF、超时、体积、内容类型和重定向必须有限制。

不做：视频下载 / 去水印、白板交互、富文本编辑器内部状态、Memory 自动写入。

### W4 — 视频链接、播放器、字幕与时间 Anchor

职责：小红书、哔哩哔哩、YouTube provider；`PlayerAdapter`、播放器壳、播放位置、字幕轨、双向跳转、点 / 区间 Anchor、VideoAnnotation Card 与恢复。

必须遵守：平台能力可以不同，但 UI 只读取能力声明；拿不到可控时间轴或可靠字幕的平台不得伪装成“完整支持”；播放器是主体，字幕 / 标注使用可右 / 下停靠的 ContextDock，默认约 65:35 且未来可拖动保存比例。

不做：绕过 DRM / 登录 / 付费限制、无授权下载、把逐条播放事件写入主聊天或 User-truth、另建视频专用卡片库。

首轮验收：至少一个 provider 的真实在线播放、current / duration / seek、字幕 cue 点击跳转、播放反向高亮、创建 Anchor + Annotation Card、重启恢复。

## 5. 并行方式与 Git / 工作区纪律

- **概念上分 session 不等于可以在同一工作目录同时写文件。** 如果多个 session 共享 `D:\memex`，只能顺序写或严格拥有互不重叠路径；不要同时运行格式化、build_runner、git add、commit 或全仓替换。
- 真正并行必须使用隔离 worktree。用户明确以本总纲启动某个白板并行工作流时，允许临时分支 `codex/whiteboard-w0-*`、`codex/whiteboard-w1-*`、`codex/whiteboard-w2-*`、`codex/whiteboard-w3-*`、`codex/whiteboard-w4-*`；它们只用于隔离开发，最终集成目标仍是 `v3-lab`，不得长期分叉或直接替代 `v3-lab`。
- 每个 worktree 从工作包指定的精确 `v3-lab` 基线开始，不自行 pull 或追逐移动中的 HEAD，不得顺带修改其它脏工作树的用户变更。
- 每个工作流只提交自身范围；共享契约、数据库迁移、依赖升级和根配置由 W0 或明确指定的集成 session 合并。
- worker 只更新自身 handoff；W0 在实际集成后统一更新 `DEVLOG.md` / `I_PROJECT_STATE.md`，保留实质结果与候选边界，避免并行写全局文档。用户明确要求 worker 更新全局状态时按其指定范围执行。

## 6. 每个 session 的启动声明

每个新工作包开始写代码前给一次简短边界声明，任务说明已经明确的字段可直接引用；普通续作不重复播报。与通用协议共用这一份声明：

```text
工作流：Wn / 名称
本轮目标：一个可验证闭环
拥有路径：准备修改的目录 / 文件组
读取契约：本总纲 + 哪些权威文档
共享契约：只读 / 申请变更哪一项
范围边界：本轮真正相关的限制
验证：准备运行的测试与真实界面检查
```

如果无法说清拥有路径或共享契约影响，不开始写代码。

## 7. 完成定义与 handoff

新功能纵切完成时交付下列证据；文档、局部修复按本轮触及的边界校准验证，不重跑整条首次纵切。已有阶段 Goal / 真人 Gate 不因本规则而取消：

1. 一个从入口到持久化 / 恢复的最小闭环，不只是一组孤立组件；
2. 正常、空、失败、权限 / 不支持状态；
3. 领域或 adapter 单元测试，以及至少一条跨边界契约测试；
4. 真实桌面窗口或目标平台验证，不只检查静态 HTML；
5. 未实现范围、风险、依赖和下一接入点；
6. `docs/development/whiteboard-workstreams/<stream-id>.md` handoff，记录结果、契约影响、测试和待集成 commit；
7. 由 W0 在集成后统一更新项目状态与 DEVLOG；独立已注册项目任务按根 AGENTS 执行自己的 i closeout，只记录工作包交付，不提前声称已集成或真人通过。

禁止以“页面看起来完成”“能打开一个 demo”或“库已经安装”作为完成。

## 8. 推荐的第一轮并行顺序

第一轮分两拍启动，合并顺序固定：

1. W0 先发布共享 Card / Source / Anchor / Snapshot fixture；
2. W0 基础提交合入 `v3-lab` 后，W1–W4 才从该基线创建各自 worktree；提前打开的 session 只能阅读、列计划和提出契约疑问，不得另造共享类型；
3. W1 做引擎赛马和画布 adapter，不直接锁生产引擎；
4. W2 以共享 Card / Anchor fixture 做富文本与批注编辑闭环；
5. W3 以 `IngestionResult → Source / Card` fixture 做普通链接闭环；
6. W4 以 `PlayerAdapter / TimedTextTrack / Anchor` fixture 做一个 provider 闭环；
7. W0 按契约测试依次集成 W3 → W2 → W1 / W4，最后才把真实 Card 放进生产白板。

并行的目的是缩短探索时间，不是让四条实现同时争夺数据库、Card schema 和导航壳。

## 9. 用户可直接使用的启动句

以下短句适合继续已有工作流；需要指定首轮范围、基线与提交授权时，使用 `docs/development/WHITEBOARD_SESSION_PROMPTS.md` 的模板。当前 Gate/handoff 已有更窄范围时以它为准，不重开历史首轮。

```text
按《白板并行开发总纲》执行。你负责 W1 白板画布与交互：先声明拥有路径和共享契约影响，再完成当前最小闭环，不扩张到富文本、抓取或视频。
```

```text
按《白板并行开发总纲》执行。你负责 W2 卡片富文本编辑：围绕 RichTextDocument、中文输入、粘贴清洗、持久化与迁移完成最小闭环。
```

```text
按《白板并行开发总纲》执行。你负责 W3 普通链接抓取：围绕 canonical URL、IngestionResult、SourceVersion、去重与失败状态完成最小闭环。
```

```text
按《白板并行开发总纲》执行。你负责 W4 视频与字幕：先选择一个 provider，围绕 PlayerAdapter、TimedTextTrack、双向跳转、Anchor 与标注恢复完成最小闭环。
```

## 10. 集成停点

出现任一情况时暂停受影响的集成并回到 W0；继续不依赖该问题的已授权工作：

- 两个工作流对同一 ID、字段或删除语义给出不同定义；
- 某个第三方引擎要求 Card 内容服从其私有文档树；
- 抓取 / 播放能力需要绕过平台授权或安全边界；
- 一个功能必须自动写 User-truth 才能成立；
- 500 卡、中文输入、重启恢复或快照往返无法通过；
- 为兼容某个模块需要恢复常驻顶栏、多个卡片库或复制 Card。

此时不靠临时 JSON、重复表或 UI 特判继续堆功能，先修共享契约。
