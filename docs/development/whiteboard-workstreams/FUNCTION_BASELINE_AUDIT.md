# 白板 Desktop 功能基线审计

> 日期：2026-08-18
>
> 审计对象：`v3-lab` @ `94ce290f` 及当前未提交的测试/状态文档修正
>
> 结论：当前是“W0–W6 代码聚合版本”，**不是可冻结的功能基线**。

## 判定口径

一项能力只有同时满足以下四点，才记为“产品功能已完成”：

1. 实现代码存在，并非占位或 Mock；
2. 使用生产数据源，且与卡片 / Source / 白板的唯一身份一致；
3. 用户能从正常界面找到入口，不需要手输路由或运行独立 Demo；
4. 能完成“进入 → 操作 → 保存 → 退出 → 重启恢复”的真实闭环。

单元测试、Widget 测试或独立 Demo 通过，只能证明模块内部能力，不能代替产品接线验收。

## 总体结果

| 工作流 | 代码实现 | 正常入口 | 统一生产数据 | 当前判定 |
|---|---:|---:|---:|---|
| W0 共享契约 | 是 | 不适用 | 是 | 通过（基础设施） |
| W1 白板画布 | 是 | 是 | 大部分 | 部分通过 |
| W2 富文本 | 是 | 基本不可达 | 否 | 未通过 |
| W3 链接抓取 | 是 | 隐藏路由 | 否 | 未通过 |
| W4 视频 / 字幕 / Anchor | 模块与 Demo 存在 | 否 | 否 | 未通过 |
| W5 TaskRoom / 编排 | 数据层与 Mock 编排存在 | 否 | 部分 | 未通过 |
| W6 数据 / 路由集成 | 是 | 部分 | 未收口 | 部分通过 |
| Task S 桌面首页 | 是 | 是 | 部分 | 部分通过 |

## 逐项审计

### W0 — 共享契约

已具备 Card、Source / SourceVersion、Board / BoardItem、Anchor、RichTextDocument、PlayerAdapter、Snapshot 等领域类型、fixture 和完整性测试。它是基础设施，不对应直接可见页面。

结论：保留，可作为后续收口的契约基础。

### W1 — 白板画布与交互

正常路径可进入：白板索引 → 新建 / 打开白板 → 全屏画布。画布具备选择、框选、拖动、缩放、旋转、分组、连线、撤销重做、快捷键、卡片拖放、BoardTargetPicker、LOD 和 Drift 保存恢复。

缺口：

- 画布卡片没有双击进入 `/cards/:cardId` 富文本编辑器的接线；
- 画布内卡片库直接读取 `MemoryCards(memory_scope=user_truth)`，与顶层卡片库不是同一个查询实现；
- 卡片统一按 `CardKind.note` 映射，媒体类型与 `WhiteboardCardExtras` 没有完整参与预览；
- 仍有生产 `print('DEBUG: ...')`；
- 历史测试 / 手工验收写入的 MemoryCard 会在画布卡片库出现，缺少测试数据隔离与清理入口。

结论：画布本体可用，但“卡片内容进入 / 编辑 / 消费”的产品闭环未完成。

### W2 — 卡片富文本

编辑器代码具备 block tree、marks、列表缩进、引用 children、图片 / 附件对象存储、粘贴清洗、撤销重做、IME、保存恢复和未保存退出提示；`/cards/:cardId` 路由也能打开编辑器。

缺口：

- 顶层卡片库空查询时只显示“输入关键词搜索”，不会列出 Drift 卡片；
- 只有已经存在于 `whiteboard/rich_text/card_<id>/rich_text.json` 的文档，输入命中关键词后才会出现；
- 没有“新建文字卡片”入口，也没有从白板双击进入编辑器；
- 编辑器保存只写 RichText JSON，不同步 `MemoryCards` / `WhiteboardCardExtras` 的标题、正文投影和更新时间；
- 汇文明朝体资产已注册；Cascadia Code 在本次审计时尚未入库（后续已由 2026-08-21 M5B-5 以 Microsoft 官方资产 + OFL 许可完成接入）。

结论：编辑器模块存在，但普通用户几乎无法到达，且与生产卡片身份未完成持久化收口。

### W3 — 普通链接抓取

`/import` 页面具备 URL 规范化、安全请求、DNS pin、四态展示、显式建卡、去重、版本化和恢复。

缺口：

- 侧栏、首页和卡片库均没有链接导入入口，只能手输 `/import`；
- `LinkIngestionService` 使用 `appSupport/whiteboard/ingestion` 下的独立 JSON `IngestionStore`；
- “存入卡片库”只写该 JSON store，不写 W6 的 Drift `MemoryCards / WhiteboardCardExtras / WhiteboardSources / WhiteboardSourceVersions`；
- 因而抓取成功后跳到 `/cards`，顶层卡片库仍可能完全看不到这张卡。

结论：抓取模块内部闭环成立，产品级“抓取 → 唯一卡片库 → 白板”闭环不成立。

### W4 — 视频、字幕与时间标注

领域层和 `VideoStudyScreen` 具备 YouTube IFrame 播放、字幕导入 / 获取尝试、cue 跳转、反向高亮、时间 Anchor、标注与会话恢复；Bilibili / 小红书按能力矩阵诚实降级。

缺口：

- 正式 `/sources/:sourceId` 仍是明确写着“由 W4 填充”的占位页；
- 完整体验只由 `video_study_demo.dart` 独立入口承载，不属于主 App；
- 没有从视频卡片 / Source 打开研读页的正常产品入口；
- 标注卡尚未写入真实 Drift 卡片库 / 白板；
- Windows 原生 App 与当时验收的 Flutter Web IFrame Demo 没有完成产品路由接线。

结论：能力模块和验证 Demo 存在，Desktop 产品功能未集成。

### W5 — TaskRoom 与 AI Orchestration

TaskRooms / TaskArtifacts / TaskDecisions、状态机、append-only 决策和 `LinAiOrchestrator` 领域代码均存在。

缺口：

- CodingAgent、ContentAgent 和 self executor 仍是 Mock / 占位；
- `LinAiOrchestrator` 没有接入主对话或桌面悬浮对话；
- 编排产出的 `WhiteboardOperation[]` 没有接到 W1 的生产执行器；
- Action Log 只有内存接口，没有生产持久化和消费端；
- 桌面“任务中心”打开的是旧 `DevRoomScreen`，不是 TaskRoom 列表 / 房间 / 决策 / 产物界面；
- 首页只读取 TaskRoom 数量和状态，不能进入对应 TaskRoom。

结论：W5 当前是数据层 + 领域原型，不是可用的 AI 协作产品功能。

### W6 与 Task S

W6 已铺设 Drift 表、六条冻结路由和桌面启动 gating；Task S 已提供模块化首页、白板入口、卡片库入口及全局悬浮对话。

缺口：

- 六条路由“存在”不等于页面均已填完：SourceStudy 仍是占位；LinkImport 隐藏；CardEdit 缺业务入口；
- 首页“继续阅读”为演示数据；“待整理卡片”来自 Drift，但点击后进入的是另一套 RichText 文件搜索页；
- “后台任务 / 活跃任务”进入旧 Dev Room，并非 W5 TaskRoom UI。

结论：外壳和路由骨架成立，但它放大了下游模块没有统一接线的问题。

## 卡片为何两处显示不一致

当前至少有三套彼此独立的存储 / 查询路径：

| 场景 | 数据源 | 直接后果 |
|---|---|---|
| 首页待整理卡片、白板内卡片库 | Drift `MemoryCards`（白板另有 Extras） | 能看到数据库里的旧卡 / 测试卡 |
| 顶层卡片库、富文本编辑器 | `whiteboard/rich_text/card_<id>/rich_text.json` | 空查询不列卡；没有富文本文件的 Drift 卡永远不显示 |
| 链接导入 | `whiteboard/ingestion` JSON store | 点击“存入卡片库”后仍不会出现在前两套视图 |

所以这不是一个展示 bug，而是尚未完成的存储整合问题。

## 冻结功能基线前必须完成

### P0：唯一数据真相与入口闭环

1. 建立统一 `CardRepository / CardLibraryQuery`：卡片身份以 Drift `MemoryCards + WhiteboardCardExtras` 为准；富文本对象与抓取全文可以保留文件存储，但必须通过同一 cardId/sourceId 关联。
2. 重做顶层卡片库的数据层：默认列出全部卡片，支持类型筛选与搜索；媒体为主体预览；不再把 RichTextSearchIndex 当成卡片库本体。
3. 富文本编辑保存同步 Card 投影；卡片库点击与画布双击都能进入编辑器；提供新建文字卡片入口。
4. 链接导入写入统一 Source / SourceVersion / Card 仓库；保存后在卡片库和白板卡片面板立即可见。
5. 清理 / 标记历史测试数据，集成测试全部改用临时数据库，禁止再污染用户生产库。

### P1：消费视图产品接线

6. 用真实 `VideoStudyScreen` 替换 `SourceStudyScreen` 占位，并从媒体卡片进入；建立字幕、Anchor、标注卡与真实 Source/Card 的保存闭环。
7. 在侧栏或卡片库提供链接导入入口；所有隐藏路由均有正常可发现入口。

### P1：任务房间最小可用闭环

8. 新建 TaskRoom 列表 / 房间详情 / 决策 / 产物界面，首页任务行进入具体 taskId，而不是旧 Dev Room。
9. 把主对话 / 悬浮对话接到 `LinAiOrchestrator`；至少接通一个真实执行器，并把授权、进度和最终压缩结果写回房间。
10. 编排画布操作接入 W1 唯一写路径，保留审计和撤销语义。

### 基线验收门槛

- 用一套新建的干净用户数据完成：新建文字卡 → 富文本编辑 → 卡片库可见 → 放入白板 → 双击再编辑 → 重启恢复。
- 完成：导入网页 → 卡片库可见 → 放入白板 → 打开来源 → 重启恢复。
- 完成：打开真实视频 → 字幕跳转 / 反向高亮 → 建 Anchor / 标注卡 → 卡片库与白板可见 → 重启恢复。
- 完成：对林埃发起任务 → TaskRoom → 决策 / 产物 → 压缩结果 → 可回到关联白板。
- 全程不手输路由、不运行 Demo、不借测试 fixture；真实 Windows App 验收并有自动化回归。

只有以上闭环通过后，才建立“功能基线”提交并开始 HTML 视觉迁移。
