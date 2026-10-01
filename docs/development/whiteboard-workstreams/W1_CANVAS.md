# W1 — 白板画布与交互

**状态**：UI-0 M3 全屏画布迁移与验收守门返修已由 W0 集成到 `v3-lab`（2026-08-20）；主线提交 `89d462d` + `13542fc`，Windows Debug 构建和真实窗口交互 / 退出 / 重启恢复 / 500 卡帧验收均通过
**权威范围**：引擎赛马、画布 adapter、viewport、选择 / 拖动 / 缩放 / 层级、删除摆放、撤销重做、快捷键、拖放 / 目标板选择、分组折叠、连线端点编辑、旋转手柄、500 卡性能（culling + LOD）
**拥有路径**：`lib/ui/whiteboard_canvas/`（画布 feature）、`test/whiteboard_canvas/`（画布 fixture / tests）、`docs/development/WHITEBOARD_ENGINE_SELECTION_ADR.md`
**共享契约**：只读消费；`BoardOperation.inverse` 标准 schema 仍为 W0 待决项（见下方契约变更提案）
**明确不做**：富文本 schema / 完整编辑器重构、网页解析、视频 provider、自动写入 User-truth、编排（W5）、语义双链

## Wave 1 第二轮验收返修（2026-08-22）

- 只读模式改成三层防线：画布 UI 不再打开快捷编辑、拖放 / 点击放卡、目标板选择、连线编辑或变更型右键项；`WhiteboardCanvasViewModel` 拒绝全部布局变更与 undo / redo；`FlutterCanvasAdapter` 再次拒绝 place / move / resize / remove / group / edge / z-index 等绕过调用。视口平移缩放仍作为只读浏览能力保留。
- 连线标签 / 方向更新与删除现在都以 logical action 包裹并 `await` 布局持久化；失败时恢复原 edge、undo/redo 和 operationLog，删除失败重新选中原 edge 并显示可见错误，失败草稿不会进入后续保存。
- 空白双击建卡不再用 `loadFromSnapshot` 做粗粒度回滚：Repository 建卡返回且页面仍有效后才开始局部 logical action；布局保存失败只撤销本次 Card 投影和 BoardItem，保留此前 undo/redo 与审计日志。若 soft delete 补偿失败，画布显示可重试清理条；这是进程内诚实恢复入口，没有新增表、文件或持久化体系。
- `createTextCard` 等待期间若页面销毁、ViewModel / Repository 切换、generation 失效或转为只读，已创建 Card 直接走补偿，不再触碰失效画布状态。
- 布局历史与内容真相正式分离：ViewModel 保存当前 Repository Card 投影；undo / redo / cancel 仅恢复历史布局并叠加最新 Card。快捷编辑保存后的标题 / 正文预览不会因之后撤销移动、缩放或连线而退回旧内容，复杂 `RichTextDocument` 仍由同一 Repository 保存，未压平。
- 验证：新增失败注入与生命周期场景后，`test/whiteboard_canvas` **144/144**；定向 analyze 零问题；`git diff --check` 通过。500 卡基准：cold load 8.1ms、JSON 往返 22.5ms、批移 100 卡 4.0ms、框选 2.8ms、1000 卡加载 1.4ms；500 可见卡 LOD 构建 full 353.886ms / minimal 135.358ms。
- 契约边界：未修改 schema、UnifiedCardRepository、路由或语义双链；`BoardEdge` 仍只是当前白板的视觉连线，不冒充 CardLink / Backlink。共享契约变更请求：无。

## W0 画布可操作性返修（2026-08-21）

- 用户实机验收确认：M3 把“可完全退场”错误固化成“默认完全隐藏”，并且只有选中两张卡后才会亮起的建组图标；连线引擎能力没有任何创建 UI。旧验收守门锁定了错误可用性标准。
- 现在导航与真实画布工具默认可见，仍可逐层收起到单一 launcher；卡片库始终可打开。
- 框选或 Shift/Ctrl+点击可多选；选中两张卡可创建有向/无向连线并填写可选标签；选中两张以上可命名建组。选择状态与触发条件直接显示在工具面。
- 分组标题提供真实「解散分组」入口；选中连线可从工具面删除，原有端点重定向、拖拽、旋转、缩放、撤销重做与保存路径保持不变。
- 本轮只补齐现有 ViewModel / engine 的交互入口，不改 Board / Group / Edge 数据语义、Repository、schema 或路由。
- 验证：完整 `test/whiteboard_canvas` 单线程 131/131；新增工具 Widget 路径与桌面 / 路由组合回归均通过。Windows 原生交互 / Drift 保存 / 退出 / 重启恢复 / 500 卡链 1/1，采集 92 帧，平均 build 25.64ms、raster 6.09ms。并发全套曾因性能测试资源争用出现两项瞬态失败，两组性能文件分别重跑通过，单线程完整目录最终全绿。

## UI-0 M3 — 全屏画布迁移（2026-08-20）

- 基线：隔离 worktree `codex/whiteboard-w1-ui0-m3` 固定在 `057da4b`，已验证包含 `a0e28893` 且开始时工作树干净；来源功能提交 `3f184af` 与返修 `19d2f58` 已由 W0 作为主线提交 `89d462d`、`13542fc` 集成。
- 画布从 `(0,0)` 覆盖完整窗口；默认无常驻顶栏、Tab、聊天侧栏或底部状态栏，只保留一个不占布局的画布控件入口。导航、编辑工具、视图工具与卡片库都是独立悬浮面，关闭后从 widget tree 完全移除；Esc 按 BoardTargetPicker → 卡片库 → 工具 → 导航 → 退出的顺序逐层退场。
- 画布展示色不再维护独立静态色板：交互画布、卡片库、BoardTargetPicker、网格、连线、分组与选中焦点均从 M0 `DesktopWorkspaceTokens.of(context)` 派生。路由 loading/error 壳仍使用与 M0 fallback 完全一致的兼容常量，未修改共享 token。
- 选中面 `#E3E5C9` 的 AARRGGBB 已从错误的 `0xE3E5C9FF` 修正为不透明 `0xFFE3E5C9`；选择状态仍只由 ViewModel 决定，未改变单选、多选、框选或选中数据语义。网格改为低对比暖灰圆点并合并为单次 `drawPoints`。
- 未修改 ViewModel、engine adapter、snapshot/domain、UnifiedCardRepository、WhiteboardDriftStore、router 或共享 token；布局保存仍只有 Board / BoardItem / Group / Edge / viewport，Card / Source 内容继续来自 UnifiedCardRepository；未引入 DOM 或 localStorage 行为。
- 守门回归：`test/routing/whiteboard_routes_test.dart` 已按新入口改为以 `wb_canvas_chrome_launcher` 出现且 loading 消失判定 ready，锁定标题、导航、工具与卡片库初始完全退场，并经 launcher →「画布工具」→ 保存验证原 Drift 落库断言，**8/8**；完整 `test/whiteboard_canvas` **128/128**，包含 1280×720、1440×900、snapshot roundtrip、重启恢复、source/card 路由、500 卡与全屏退场；M0 桌面共享壳 **6/6**。本次 500 卡基准：cold load 17.0ms、JSON roundtrip 70.5ms、批移 100 卡 12.9ms、框选 13.7ms，真实 Repository 500 卡 list 45ms。
- Windows 实窗：关键修复脚本 **3/3**，精确 analyze 零问题，`flutter build windows --debug` 成功生成 `build/windows/x64/runner/Debug/memex.exe`。`integration_test/whiteboard_interactions_loop_test.dart -d windows` 已改为按新悬浮入口操作并通过：初始可选 chrome 全退场；打开导航与工具；Ctrl+A、微移保存、旋转 90°、端点重连、折叠均落库；点击退出返回白板索引；关闭首个 Drift 连接后以同一文件重开窗口，位移 / 旋转 / 重连 / 折叠全部恢复；500 卡真实窗口采集 90 帧，avgBuild 37.20ms / avgRaster 7.03ms。
- 返修范围仅含路由测试、Windows 交互脚本与本 handoff；没有修改 M3 生产代码，也未触碰数据库、Repository、domain、router、共享 token、`DEVLOG.md` 或 `I_PROJECT_STATE.md`，不会把旧基线状态文件带入集成。
- 共享契约变更请求：无。

## F1 — 白板画布产品闭环（2026-08-19）

- 正常 `/whiteboard` 索引的新建 / 打开仍进入冻结的 `/whiteboard/:boardId` 全屏路由；画布启动先读 Drift 布局，再只经 `WhiteboardDataBootstrap` / `UnifiedCardRepository` 装载真实 Card、Source 与当前 SourceVersion，不再用快照卡片、fixture 或演示卡兜底。
- 卡片库加载失败、白板失效引用、保存失败均为显式可重试状态；保存时强制剥离 Card / Source / SourceVersion，只写 Board、BoardItem、Group、Edge 与 viewport 布局。删除 BoardItem 后 Repository 中同一 Card 保持存在。
- 双击普通文字卡 / 批注卡进入 `/cards/:cardId`；带 `sourceId` 的来源 / 媒体卡进入 `/sources/:sourceId`。跳转前先保存，消费页使用 push，可返回原画布。
- 自动化新增真实临时 SQLite + 临时文件目录的产品闭环：Repository Card → 放入空白板 → 双击消费页 → 返回 → 保存 → 关闭数据库 → 新连接恢复 → 从板上移除但 Card 仍存在；另覆盖来源卡路由、失效 Card、Repository 加载失败、保存失败和布局-only 写入。
- 验证：画布与白板数据定向集合 229 项通过（原集合 228 项全绿，新增 500 Repository 卡性能守门后总数 229）；F1 产品闭环 5/5；定向 analyze 零问题。500 张真实 Repository Card 的 `listCards()` 为 25ms；引擎基准 cold load 7.9ms、JSON 往返 17.5ms、移动 100 卡 2.9ms、框选 2.6ms、1000 卡 load 1.5ms，未见明显退化。
- Windows：`verify_critical_fixes.ps1` 3/3，通过并成功生成 `build/windows/x64/runner/Debug/memex.exe`；`flutter test -d windows` 在启动驱动前因 `Nuget.exe not found` 退出，直接启动集成测试壳仅得到无窗口响应进程（`MainWindowHandle=0`），因此本轮不宣称实窗通过，也没有新的真实窗口帧数据。
- 契约变更请求：无。继续遵守 schema 60、BoardItem 只持布局、Card / Source / RichText 只经统一 Repository、删除摆放不删内容；既有 `BoardOperation.inverse` 提案保持原状。

### F1 消费路由返修（2026-08-19）

- 消费目标必须由 CardKind 决定，`sourceId` 只作为 Source Card 的必要参数：仅 `CardKind.source && sourceId.isNotEmpty` 进入 `/sources/:sourceId`；Note、Annotation、Reference、TaskArtifact 均进入 `/cards/:cardId`，带来源的 Annotation 也不例外；缺少 sourceId 的 Source Card 诚实降级到卡片页。
- 产品路由矩阵已锁定四例：Source Card → 来源页；带 Source 的 Annotation → 卡片页；缺 sourceId 的 Source Card → 卡片页；普通 Note → 卡片页。失效 Card 引用保持不可打开。
- 返修验证：F1 产品闭环 5/5，完整 `test/whiteboard_canvas` 123/123；未修改 Repository、schema、路由定义、画布快照或其他交互。

## 本轮目标（已达成）

在已接 Drift 的全屏画布上补齐生产级交互，全部可保存并在重启后恢复：
① 键盘快捷键；② 卡片库正式拖放 + `BoardTargetPicker`；③ 分组折叠 / 展开；④ 连线拖拽端点编辑；⑤ 旋转手柄。
Huabu 借鉴落地：UiIntent 与 WhiteboardOperation 分离、单逻辑动作合并为单 undo step、执行器为唯一写路径；LOD 分档渲染 + 迟滞。

## 本轮交付

### 1. 键盘快捷键（`WhiteboardCanvasScreen` 内 `CallbackShortcuts` + Focus）

- Ctrl+Z 撤销 / Ctrl+Y、Ctrl+Shift+Z 重做 / Del、Backspace 删除（先删选中连线，再删选中卡片）/ Ctrl+A 全选（排除折叠组隐藏成员）/ 方向键微移 8px、Shift+方向键 32px（每次按键 = 单 undo step）/ Ctrl+S 保存 / Esc 退出（卡片库打开时先关面板）。

### 2. 卡片库拖放 + BoardTargetPicker

- 卡片库行 = `Draggable<WhiteboardCardDragData>`（记录指针抓取偏移，落点精确在指针下）；画布 = `DragTarget`，落下经 `screenToCanvas` 换算后走 `placeCardOnBoard`（唯一写路径）。
- 每行「放入白板…」打开 `BoardTargetPicker`（`lib/ui/whiteboard_canvas/widgets/board_target_picker.dart`）：最近白板（按 updatedAt 排序，当前板标「当前」）、搜索、新建白板；选择后只新增 `BoardItem`，不复制 Card（组件规范 §5.1）。新建白板 = `vm.createBoard`（snapshot 级操作，不发审计操作）+ 随后 `placeCard`（发 `place` 审计）。

### 3. 分组折叠 / 展开

- 点击分组标题区域切换；折叠后成员卡片从画布卸载（不渲染、不参与框选/全选、选中项被清除），分组缩成带头像图标的紧凑条（名称 + 张数）；painter 跳过被隐藏端点的连线。折叠状态走 `BoardGroup.collapsed` 持久化，重启恢复。

### 4. 连线拖拽端点编辑

- 点击连线（点到线段 ≤10px）选中；选中连线高亮 + 两端圆形手柄；拖动手柄实时预览（painter 画预览线 + 端点圆点），松开落到卡片上即重定向该端点，落到空白处取消（`cancelLogicalAction`：零状态变化、零审计、零 undo）。`retargetEdge` 拒绝自环与未知端点；删卡自动清除关联连线与选中态。

### 5. 旋转手柄

- 选中卡片顶部圆形手柄，拖拽绕卡片中心旋转（角度 = atan2(指针-中心)），`BoardItem.rotation`（度）落盘；手柄与缩放角柄为画布级兄弟节点（放在卡片 bounds 外仍可命中），位置随卡片旋转同步。缩放角柄保留原行为。

### 6. Huabu 三层命令（`docs/development/WHITEBOARD_EXTERNAL_REFERENCE_HUABU.md` §1）

- `interactions/ui_intent.dart`：`UiIntent` sealed 层级（选择 / 框选 / 移动 / 微移 / 删除 / 旋转 / 缩放 / 折叠 / 重定向 / 边选择等），纯 UI 瞬态手势语义，不直接改状态、不拥有 undo 快照。
- `WhiteboardCanvasViewModel.handleIntent(UiIntent)`：resolver + 执行器边界，把 intent 解析为 adapter 的 `WhiteboardOperation` 序列——用户与未来林埃编排（W5 直接产 adapter 操作）共用同一条写路径，天然获得审计 + 整体撤销。
- 逻辑动作分组：`beginLogicalAction / endLogicalAction / cancelLogicalAction`——拖拽 / 缩放 / 旋转 / 端点拖拽期间产生的全部操作缓冲，结束时合并为**单 undo step**（合并审计条目带 `merged_count`）；失败或取消时恢复基线快照，且从审计日志中移除缓冲操作（零副作用）。

### 7. 语义缩放 LOD（Huabu §5）

- `interactions/lod.dart`：`LodTier.full / minimal`，按 卡宽×zoom 对比 140 / 150px 边界切换，10px 迟滞防抖；纯函数可单测。
- 全屏画布在 viewport culling 之上逐卡计算 LOD 档（瞬态渲染态，绝不写进快照——有测试断言快照不变）。minimal 档 = 标题单行 + 收紧 padding，无正文 / 标签 / 失效详情。
- 覆盖全部现有卡片类型（当前画布卡片均为文本预览；未来媒体卡按需扩展）。

### 8. 其他

- 浮层统一近不透明 `panelSurface` token（popover / 底栏 / 拖拽反馈，视觉规则 §7.3 保证文字对比）。
- 底部栏提示与按钮 tooltip 已同步快捷键。

## 测试与验证

- **test/whiteboard_canvas 共 117 项**（原 80 + 新增 37）：
  - 24 项交互测试（`whiteboard_canvas_interactions_test.dart`）：快捷键（Ctrl+Z/Y/Shift+Z/A、Del、方向键、Esc）、库内拖放落点、BoardTargetPicker（选板 / 搜索 / 新建）、分组折叠与选中清理、连线选择 / 重定向 / 空白取消 / Del 删线、旋转手柄与撤销、拖拽与缩放各 = 单 undo step、VM 逻辑动作分组 / 取消 / intent 路由 / 自环拒绝 / 跨板放置不抢选中 / 只读拒绝。
  - 13 项 LOD 测试（`whiteboard_canvas_lod_test.dart`）：纯函数档位与迟滞、widget 层迟滞防抖、minimal 无正文无标签、LOD 不污染快照、500 卡低倍率全 minimal + culling 不破、**500 可见卡 full vs minimal 构建耗时对比：349.3ms → 149.0ms（2.3×）**。
  - 5 项快照往返测试（`whiteboard_canvas_snapshot_roundtrip_test.dart`）：旋转 / 折叠 / 重定向经文件 store 与 JSON 契约往返无损，往返后 `validateSnapshotIntegrity` 有效。
  - 原有 80 项全部保持通过（无回归）。
- **回归**：test/domain/whiteboard（W0 契约）+ test/data/whiteboard（Drift store）+ test/routing 共 229 项全通过。
- **真实桌面窗口（Windows）**：
  - `integration_test/whiteboard_interactions_loop_test.dart`（hermetic，真实 Drift 临时库，不经 app.main）：Ctrl+A 已选 3 → 方向键 x=8 落库 → 旋转 90.0° 落库 → 连线重定向到 C 卡落库 → 折叠落库 → 同文件第二连接重启恢复全部验证 → **500 卡板真实窗口 92 帧：avgBuild 20.4ms / avgRaster 3.6ms**（viewport culling + LOD 全程生效）。
  - `integration_test/whiteboard_desktop_loop_test.dart`（W6 管线闭环）保持通过。
- **analyze**：`lib/ui/whiteboard_canvas`、`test/whiteboard_canvas`、`lib/ui/whiteboard`、`lib/data/whiteboard`、`lib/domain/whiteboard`、integration_test 新增文件零 error；全仓 whiteboard 相关文件零 error（全仓 153 个 error 均为基线遗留的其他模块测试文件，与本轮无关）。
- `git diff --check` 干净。

## 引擎选型与已交付闭环（第一阶段，保持不变）

见上文「引擎赛马选型」与 `docs/development/WHITEBOARD_ENGINE_SELECTION_ADR.md`；Flutter 原生画布 adapter、ViewModel、快照 store、边界状态覆盖、语义不变式等第一阶段结论继续有效（详见 git 历史与前一版 handoff）。

## 未完事项

- **真实桌面渲染帧率 profile（DevTools Performance / frame timeline）**：本阶段已用 `SchedulerBinding` timings 回调在真实窗口采集 92 帧（build 20.4ms / raster 3.6ms 平均）；如需逐帧火焰图仍建议用 DevTools 在真机窗口 profile。Windows 需管理员开启 Developer Mode 后使用 DevTools。
- **拖入其他白板的落点语义**：当前跨板放置落在"当前视口中心"（另一块板用户不一定马上看到）；后续可改为落目标板自身 viewport（需要 per-board viewport 进入快照，属 W0 契约变更请求）。
- **undo 后 Drift 侧板残留**：新建白板 → 放入 → undo（snapshot 移除新板）→ 保存后 Drift 仍保留空板行（save 只 upsert 不删除 board 行）。用户流不受影响，后续可考虑 delete 语义。
- **卡片库拖放反馈**：当前有拖拽预览卡，未做落点幽灵高亮；需要时补。
- **批量放入 / 批量操作**：本轮为单卡选择 + 单选板，批量流程留待后续窗口。

## W5 集成边界（如何调用画布）

以下类型与最小调用参数供后续工作流（W5 及消费视图返回定位）调用，不依赖主路由 / 首页 / 依赖注册，全部在 `lib/ui/whiteboard_canvas/` 内。

```dart
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_snapshot_store.dart';

// 1) 打开画布（ViewModel + Screen）
final vm = WhiteboardCanvasViewModel(
  initialSnapshot: snapshot, // WhiteboardSnapshot，来自 W0 契约
  boardId: 'board_xxx',       // 稳定的 board_id
);
vm.onSaveRequested = () {
  store.save(boardId, vm.exportForSave()); // 持久化
};
WhiteboardCanvasScreen(viewModel: vm, onExit: ...); // 全屏无常驻顶栏

// 2) 消费视图返回时定位
vm.focusItem('item_xxx'); // viewport 中心对齐到该 item

// 3) 从持久化恢复
final store = WhiteboardSnapshotStore(baseDir);
final result = store.load(boardId); // SnapshotLoadResult
// result.isSuccess / result.snapshot / result.error / result.integrity

// 4) 只读 / 授权边界
vm.setReadonly(true); // 清除选择并禁用写操作
```

所需参数：`WhiteboardSnapshot initialSnapshot`、`String boardId`（ViewModel 构造必需）；`WhiteboardSnapshotStore.baseDir`（持久化目录）；`onExit`（返回回调）。Adapter 可直接以 `FlutterCanvasAdapter(snapshot)` 独立使用，供无 UI 的后台逻辑操作快照。

**本轮仍未修改**主路由（`lib/routing/`）、首页、`lib/config/dependencies.dart` 依赖注册；W5 接入时按 W0 集成顺序处理，不私自接线。

**本轮唯一生产接线点**：W6 的 `WhiteboardCanvasRouteScreen`（Drift 默认保存目标）保持不变，画布交互全部在该壳下工作。

## 语义不变式（已由测试守护）

- 删除 BoardItem 不删除 Card / Source（`removeItems` 只删摆放，测试断言 Card 计数不变）。
- 卡片内容不进入画布布局 JSON（`BoardItem.toJson` 只含布局 + `card_id`，跨边界契约测试断言）。
- 产品稳定 ID 不被引擎私有 ID 替换（adapter ID 映射恒等，测试断言无私有空间）。
- 全屏白板无常驻顶栏（widget 测试 `find.byType(AppBar)` 为空）。
- 单逻辑动作 = 单 undo step（拖拽 / 缩放 / 旋转 / 端点拖拽各自合并为一步，测试断言一次撤销即回基线）。
- 失败 / 取消的手势零副作用（重定向落到空白处：状态、审计、undo 栈全部不变）。
- 折叠是视图态不是数据删除（快照中 boardItems / groupMembers 数量不变）。
- LOD 是渲染态不是数据（快照 JSON 在 LOD 档位切换前后逐字节不变）。

## 引擎选型（第一阶段，保持不变）

见 `docs/development/WHITEBOARD_ENGINE_SELECTION_ADR.md`：三候选（AFFiNE 可复用部分 / BlockSuite / tldraw）均为 JS 引擎需 WebView 桥接，与"卡片内容不写进画布 JSON"硬约束冲突；追加候选 **Flutter 原生画布**（`CustomPainter` + `Transform` + `GestureDetector`）零外部依赖、产品 item_id 即引擎 ID、快照往返零损耗，加权评分 86/100 采用。

## 契约变更提案（提交给 W0，延续第一轮）

1. **`WhiteboardOperation.inverse` 标准 schema**（W0 待决项，本轮新增映射）：`rotate` 复用 `resize` kind（payload/inverse 含 `rotation`）；`setGroupCollapsed` 复用 `group` kind（payload/inverse 含 `collapsed`）；`retargetEdge` 复用 `edge` kind（payload/inverse 含 `from_item_id / to_item_id`）。均为既有 kind 的 payload 扩展，不改枚举。
2. **`WhiteboardSnapshot.copyWith`**（建议新增）：各工作流仍在自建克隆；建议 W0 提供不可变 copyWith。
3. **`Board` 创建不入操作枚举**：BoardTargetPicker 新建白板通过 adapter.addBoard 直写快照，不产生审计操作（空板创建非内容变更），随后 placeCard 产生标准 `place` 审计。

## 待集成提交

- 临时分支：`codex/whiteboard-w1-interactions`
- 建议合并到 `v3-lab` 前由 W0 评审契约变更提案，再合入。
