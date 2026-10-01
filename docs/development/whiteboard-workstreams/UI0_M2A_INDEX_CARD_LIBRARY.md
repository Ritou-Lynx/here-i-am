# UI-0 — Whiteboard Desktop M2A 白板索引与卡片库 handoff

> 工作流：UI-0 / M2A（白板索引、唯一卡片库、目标白板选择）
> 状态：完成并由 W0 集成到 `v3-lab`（2026-08-20）；统一安全缩略图于 M5B-4 补齐（2026-08-21）
> 隔离分支：`codex/whiteboard-ui0-m2a`
> 统一基线：`057da4b`；已验证包含 M0 `88a6b5b`

## 1. 交付闭环

1. `/whiteboard` 在 M0 桌面共享壳内使用 Lieflat Palm 纸面缩略网格；列表、新建、打开继续只走 `WhiteboardDriftStore`。缩略图按真实 `BoardItem` 空间关系绘制，不带 HTML mock 或 localStorage 数据。
2. `/cards` 仍只有一个生产卡片库，查询与新建继续走 `UnifiedCardRepository` / `CardLibraryQuery`；关键词、类型、来源、标签、已上板 / 未上板可组合。
3. 文字卡正文为预览主体；媒体卡保持 70/30 主从比例。M5B-4 后，卡片进入 Grid / List 构建范围才经 `UnifiedCardRepository` 请求可信内容寻址缓存；raw metadata URL、绝对路径和伪封面仍不进入 ImageProvider，任何失败继续显示类型化缺失态。
4. 独立卡片库复用 `BoardTargetPicker`，支持最近 5 张白板、搜索全部白板和新建白板。
5. 确认目标后从 Drift 全量快照追加一个只引用 `cardId` 的 `BoardItem`；不复制 Card。同一 Card 可进入多个白板，删除一个 BoardItem 后 Card 身份仍保留。
6. M0 `DesktopPageTitle` 与桌面 token 只在共享壳注入 `DesktopWorkspaceTokens` 时由索引、卡片库消费；无该作用域时保留 Spring Rain 移动端标题、色彩与列表布局。冻结路径与参数未变。

## 2. 审计返修（2026-08-20）

1. `BoardTargetPicker` 的“创建白板 → 放入卡片”现在是覆盖两个异步阶段的完整 single-flight；busy 从创建开始前持续到放置结束，且内部放置不再被自身 busy 守门短路。
2. busy 期间关闭按钮、搜索、新白板名称输入、Enter 提交、新建入口和白板列表操作全部禁用。
3. 新增延迟创建的快速双触发回归，确认最终只创建一个 Board、追加一个 BoardItem。
4. 新增索引与卡片库平台作用域回归，确认桌面共享壳继续使用 M0 token / 标题 / 网格，非桌面作用域不被 Desktop token 或布局覆盖。

## 3. 契约与边界

- 共享契约请求：无。
- 未修改 router、pubspec、`UnifiedCardRepository`、repository/domain、Drift schema、迁移或任何生成文件。
- 未带入 HTML localStorage、初始 mock 数据、远程图片旁路或新的卡片身份。
- `BoardTargetPicker` 保留原 `WhiteboardCanvasViewModel` 构造方式；新增 external callback 入口供独立卡片库持久化，既有画布调用者无需迁移。

## 4. 验证

- M2A 索引：6/6，通过真实临时 SQLite 覆盖空态、平台作用域、纸面网格、新建、打开与数据库重启。
- M2A / F2 卡片库：10/10，覆盖平台作用域、正文预览、70/30 缺图安全态、组合筛选、新建文字卡、来源路由、最近 / 全部搜索 / 新建目标、同 Card 多白板和移除 BoardItem 不删 Card。
- F0/F2 历史提交覆盖的原 12 份回归文件：107/107（含新增 single-flight 与卡片库平台作用域回归）。
- M0 共享桌面壳：6/6。
- 六个改动 / 测试文件精确静态检查：No issues found；关键修复守门 3/3；`git diff --check`：通过。

## 5. 集成结果与未完事项

- 隔离分支提交已由 W0 作为主线提交 `381f938`（功能）与 `14a3fbd`（返修）集成；未 push。
- M2A 当时保留的统一安全缩略图已由 W0 在 M5B-4 补齐：复用 F3 SafeHttp 边界，校验 / 静态化 / 内容寻址后才把本地 File 交给 UI；不修改 Card / Source 身份或 Drift schema。
- M5B-4 已在真实 Windows runner 中复跑 1440×900、1280×720、1024×768，并逐张复核卡片库可信缩略图、70/30 比例和网格换列；截图只在忽略的 `build/`。
