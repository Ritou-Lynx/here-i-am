# Task S — 桌面首页工作台外壳 handoff

> **现状修订（2026-08-22）**：本文件记录 2026-08-16 的历史实现，不再代表当前 Desktop 首页。真人验收后的当前方案见 `WAVE1_DESKTOP_SHELL_HOME.md`：首页使用 Card / Source / Board 的六块真实数据模块（30 天活动、角色/媒介构成、上板比例、白板增长、最近白板、待整理卡片），不再保留下述八模块、演示数据或手机生活空间入口；`/`、`/cards`、`/whiteboard` 现共用持久 Desktop Shell。

> 工作流：Task S（白板并行开发总纲首轮 Task 分片 · 桌面首页外壳）
> 状态：完成（2026-08-16）
> 分支：`codex/whiteboard-s-desktop-shell`（未 push、未 merge，交集成确认后合入 `v3-lab`）
> 基线：`v3-lab` @ d6910cdc（含 W6 集成基座 919a1c54，路由/迁移/pubspec 冻结）

## 1. 交付闭环

桌面首页从「手机聊天页套壳」（`companion_first_shell.dart` 直接返回 `PersonaChatScreen(embedded:true)`）改造为 spine-contract §3.2 模块网格工作台：

1. `CompanionFirstShell` 桌面分支（Windows/Linux/macOS）→ `DesktopWorkbenchShell`；手机路径零改动。
2. 工作台 = 144px 可回收侧栏（短横线+文字导航，活动项淡绿水墨笔触）+ 4 列 × 2 行模块网格，1440×900 一屏读懂全貌。
3. 林埃对话按需悬浮：右下中性悬浮球 ↔ 400px 右侧覆盖面板，复用与手机完全相同的 `PersonaChatScreen(embedded:true)`（同一份关系主对话数据）。
4. 「继续工作」真实数据：最近白板（`WhiteboardDriftStore.listBoards`）→ `/whiteboard/:boardId` 画布路由；活跃任务房间（`TaskRoomService` pending/running/blocked/waiting_for_user）→ `/dev-room`。
5. 「待整理卡片」真实数据：`MemoryCards`（scope=`user_truth`、type=`note`）中未被任何 `WhiteboardBoardItems` 引用的最近卡 → `/cards` 卡片库路由。
6. 其余模块同源真实数据或明确标注演示数据，全部有可执行去向（日历/记忆中心/任务中心/生活空间/卡片库），无无行为装饰按钮。
7. 填充 Task S 专属占位 `WhiteboardIndexScreen`：真实板列表（Drift）+ 新建白板 → 直达画布（W6 handoff 指定的 Task S 接入点）。

## 2. 拥有路径

| 路径 | 内容 |
|---|---|
| `lib/ui/desktop/`（新建） | `desktop_workbench_shell.dart`、`view_models/desktop_home_view_model.dart`、`widgets/desktop_module_grid.dart`、`widgets/desktop_sidebar.dart`、`widgets/desktop_chat_overlay.dart` |
| `lib/ui/companion/widgets/companion_first_shell.dart` | 桌面分支接线（手机路径未动） |
| `lib/ui/whiteboard/whiteboard_index_screen.dart` | Task S 占位填充（真实板列表 + 建板） |
| `test/ui/desktop/desktop_workbench_shell_test.dart`（新建）、`test/ui/whiteboard/whiteboard_index_screen_test.dart` | 测试 |

## 3. 共享契约影响

**只读，零契约变更请求。**

- 未改 `router.dart` / `routes.dart` / 迁移（schemaVersion 58→59 保持唯一 bump）/ `pubspec`。
- 未新增数据表；数据全部走现有 service（`WhiteboardDriftStore` / `TaskRoomService` / `MemoryCardQueryService`），未复制内容实体。
- 「待整理卡片」判定是**查询语义**（card 未被 board item 引用），与 W6「删除 BoardItem 不删除 Card」一致，不改变任何存储语义。
- 视觉实现直接使用 `SpringRainUiTokens.daylight` 语义 Token（visual-rules §4.1 指定），未复制裸色值。

## 4. 测试与验证

- **新增**：`test/ui/desktop/desktop_workbench_shell_test.dart` 6 项（8 模块渲染 / 继续工作→画布路由 / 待整理卡片模块作用域断言 + →卡片库 / 空态诚实展示 / 悬浮对话开合 / 侧栏折叠，固定 1440×900 视口）；`test/ui/whiteboard/whiteboard_index_screen_test.dart` 重写为 4 项（列表 / 空态 / 跳转画布 / 新建流程）。
- **回归**：`test/routing/whiteboard_routes_test.dart`（6 项）、`test/ui/companion`、`test/ui/whiteboard` 全部通过；workbench + index + routing + companion + whiteboard UI 合计 56 项全过。
- **analyze**：目标目录（lib/ui/desktop、companion_first_shell、whiteboard_index_screen、对应测试）零 error/零 warning（全仓 analyze 中本分支改动路径同样零问题；schedule_widgets_test 等既有 error 属基线）。
- **全量测试**：1086 过 / 29 失败——失败项（agent 工具调用、sleep companion、state_util、input_sheet 超时等）在未改动的 `v3-lab` 基线同样失败（已在 `D:\memex` 主工作树逐项复核），非本分支回归。
- `git diff --check` 干净。

## 5. 关键决策

1. **待整理卡片语义**：未被任何 BoardItem 引用的最近 note 卡（scope=user_truth）。诚实且零新表；若后续需要「待确认/待分类」显式状态，应作为 W0 契约变更提出（加状态字段或操作类型），不在本层造表。
2. **林埃对话复用 PersonaChatScreen(embedded:true)**：同一条关系主对话、同一份消息数据，桌面只换呈现密度（spine-contract §2.9），不另造聊天数据或 UI 副本。
3. **悬浮球不带假状态**：只用中性材质 + 小状态点，无装饰按钮；「今日总结」的「继续对话」是唯一显式开窗动作。
4. **林埃观察模块**：只放真实计数 + 诚实说明（「洞察判断由观察面板接入」），不虚构林埃判断；去向为真实生活空间屏幕。
5. **继续阅读模块**：阅读进度接线前用明确标注「演示数据」的行 + 卡片库去向，遵守「数据必须真实或明确标注演示」。

## 6. 未实现范围 / 风险 / 下一接入点

- 「继续工作」活跃任务目前去向 `/dev-room`（Dev Room 现有屏幕）；TaskRooms 专属任务中心/任务房间 UI 未建，属后续窗口（W5 已备 TaskRoomService 数据层）。
- 「继续阅读」真实进度接线（阅读进度/视频位置数据源）待做；「林埃观察」洞察判断渲染待做。
- 悬浮对话面板目前固定 400px 右侧覆盖；面板位置记忆/可拖动留待后续。
- 侧栏导航用 `GoRouterState.of(context)` 判断活动项，与冻结路由表只读匹配；后续新一级工作面路由加入时需在 `_navItems` 增补（仅桌面壳内数据，不动 router）。
- 真实桌面窗口 1440×900 人工视觉检查建议在合并后由集成 session 与截图一起做（本轮已用 1440×900 widget 测试锁定布局与不滚动）。

## 7. 待集成提交

- 本分支 `codex/whiteboard-s-desktop-shell`（含 DEVLOG / I_PROJECT_STATE / 本 handoff）。
- 合并顺序建议沿用 W6：Task 0（已入 v3-lab）→ Task S（本分支）→ E/A/C/B/D，每步全量测试；集成时注意 DEVLOG / I_PROJECT_STATE 顶部条目冲突按根 AGENTS 契约处理。
