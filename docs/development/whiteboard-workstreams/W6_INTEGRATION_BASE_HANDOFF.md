# W6 v2 — 生产集成基座（纯数据管道）handoff

> 工作流：W6 生产集成基座（v2 瘦身版）
> 状态：完成（2026-08-15）
> 分支：`codex/whiteboard-w6-integration-base`（未 push、未 merge，交集成确认后合入 `v3-lab`）
> 范围：只做数据管道（迁移 / Drift 持久化桥 / 路由与占位 Screen）；**首页外壳归 Task S，未触碰**

## 1. 交付闭环（真实桌面验证通过）

**入口 → 持久化 → 恢复**（`integration_test/whiteboard_desktop_loop_test.dart`，Windows 真实窗口）：

1. 应用启动（真实 Drift 库 `memex_local_<userId>.sqlite`）
2. 经冻结路由直达 `/whiteboard/:boardId`（深链接，不依赖任何首页/外壳入口）
3. 全屏画布打开（无常驻顶栏）→ 点保存 → 数据写入 Drift 表
4. 同文件新连接重读 → 白板完整恢复（`All tests passed`）

进程级"杀进程重启恢复"由数据层单测覆盖（`whiteboard_drift_store_test.dart` 的 close+reopen 同一文件用例）。

## 2. 交付内容

### 2.1 数据库迁移（schemaVersion 58 → 59，唯一一次 bump）

`lib/data/memory_v3/db/tables.dart` 新增 8 张白板生产表（见文件"十、白板生产表族"注释）：

| 契约类型 | 生产表 |
|---|---|
| Board（含 viewport 列） | `WhiteboardBoards` |
| BoardItem | `WhiteboardBoardItems`（只存布局，不含卡内容） |
| BoardGroup | `WhiteboardGroups` |
| GroupMember | `WhiteboardGroupMembers` |
| BoardEdge | `WhiteboardEdges` |
| SourceContent | `WhiteboardSources`（MemoryCardSources 按 card_id 主键无法承载 source 身份/版本化） |
| SourceVersion | `WhiteboardSourceVersions` |
| CardContract 附加字段 | `WhiteboardCardExtras`（身份复用 `MemoryCards`：scope=`user_truth`、type=`note`） |

`lib/db/app_database.dart`：8 表注册进 `@DriftDatabase`；`onCreate`/`onUpgrade` v59 块 `_createTableIfMissing` 幂等建表 + `_createWhiteboardIndices()`（7 个索引，字段先建后建索引）。`.g.dart` 已由 build_runner 生成。

### 2.2 Drift 持久化桥

`lib/data/whiteboard/whiteboard_drift_store.dart`：

- 与 W1 文件 store（`WhiteboardSnapshotStore`，保留供测试/fallback）同 API：`save / load / exists / delete`，另加 `listBoards / createBoard`。
- `WhiteboardSnapshot ↔ Drift 表`双向映射；save 语义 = 全量快照真相（布局行整体替换、卡/源 upsert、卡永不因快照缺失被删）。
- 目标板 viewport 存在 `WhiteboardBoards` 行上；`updated_at` 按保存时点归一化（Board 实体时间戳与 snapshot 时间戳一致时可字节级往返）。
- load 后跑 `validateSnapshotIntegrity`，悬空引用以 integrity 报告（画布 orphaned 态由 W1 处理）。
- **接线位置**：`WhiteboardCanvasRouteScreen`（路由加载壳）构造 VM 并默认把 `onSaveRequested` 接到 Drift store——生产默认即 Drift。VM 本体（W1 拥有路径）未改，避免与 W1 并行窗口产生合并面。

### 2.3 路由注册（唯一一次改 router.dart / routes.dart，签名冻结）

`AppRoutes`（`lib/routing/routes.dart`）6 条生产路由 + 3 个路径展开辅助：

| 路由 | 路径 | 参数 | 目标 Screen（v2 = 最小占位，灰纸底 + 页名 + 返回） |
|---|---|---|---|
| 白板索引 | `/whiteboard` | — | `WhiteboardIndexScreen`（占位；真实列表/建板归 Task S 与后续窗口） |
| 全屏白板画布 | `/whiteboard/:boardId` | boardId | `WhiteboardCanvasRouteScreen`（真实加载壳：Drift 读取 → VM → W1 画布） |
| 唯一卡片库 | `/cards` | — | `CardLibraryScreen`（占位） |
| 卡片富文本编辑 | `/cards/:cardId` | cardId | `CardRichTextEditorScreen`（占位） |
| 视频/内容研读 | `/sources/:sourceId` | sourceId | `SourceStudyScreen`（占位） |
| 链接导入 | `/import` | — | `LinkImportScreen`（占位） |

后续窗口只填占位 Screen 内容，**不再改 router.dart / routes.dart**。

### 2.4 桌面启动 gating（main.dart，纯管道必需）

真实桌面窗口暴露的移动端插件缺口，一次性 gating（`isDesktop = Windows/Linux/macOS`）：

- `Workmanager().initialize`、`VoiceSessionRouter.init`、`NotificationService.initialize`、通知 tap/冷启动恢复、CallKit 全套、QuickActions、MainScreen 的 checkin/dreaming WorkManager 注册 → 全部 `if (!isDesktop)` 包裹。
- `NotificationService.cancelAgentNotification`：非 Android 直接 return（桌面下 flutter_local_notifications 平台接口 late 实例未注册，cancel 会崩）。
- `DreamingSchedulerService`：orchestrator 改懒解析（桌面下 shell 构造早于 MemexRouter init 的竞态）。

**明确不做**：首页入口、shell 形态（Task S）。

## 3. 测试与验证

- **新增**：`test/db/whiteboard_migration_test.dart`（空库直建 59 / v58→v59 升级含数据保留 / 半成品自愈 / 7 索引校验）、`test/data/whiteboard/whiteboard_drift_store_test.dart`（fixture 字节级往返、空板、覆盖语义、卡不删、viewport 分板、悬空 integrity、listBoards 排序、软删、MemoryCards+Extras 落库、close+reopen 重启恢复）、`test/routing/whiteboard_routes_test.dart`（6 路由解析 + 画布直达 + 保存落库）、`test/ui/whiteboard/whiteboard_index_screen_test.dart`（占位渲染）、`integration_test/whiteboard_desktop_loop_test.dart`（真实桌面闭环）。
- 更新 `test/db/task_room_migration_real_test.dart` 两处 58→59 断言（W5 测试随 bump 收敛）。
- **结果**：白板 + W5 数据层全量 351 项通过（含 W0 26 / W1 80 / W3 68 / W5 28 零回归）；桌面集成测试 1 项通过；analyze 目标目录零 error（仅剩 W4 自有 `lib/ui/whiteboard/video/` 历史 info）；`git diff --check` 干净。

## 4. 契约变更请求（W0 集成工作流评审）

已在 `W0_INTEGRATION.md` 追加，摘要：

1. **Card 身份**：按任务指示"复用 MemoryCards + 关联表补"实现（`memory_scope='user_truth'`、`type='note'` + `WhiteboardCardExtras`）。风险：MemoryCards 的全局消费者（Memory Review / recall）会看到白板卡；如后续要隔离，应在查询层按 scope 过滤（改动在查询服务，不碰本迁移）。
2. **VM 接线**：Drift 默认接线放在路由加载壳而非 VM 构造器（W1 拥有路径零改动）。
3. **updatedAt 归一化**：目标板行 `updated_at` = snapshot 保存时点（文件 store 语义），非目标板保留实体值。
4. **W3 建议的独立 `whiteboard_cards` 表未采用**（与任务指示冲突时以任务为准），保留 `WhiteboardCardExtras.source_id` 软引用以支持"来源→卡片"检索。

## 5. 未完事项 / 下一接入点

- `WhiteboardCanvasRouteScreen` 与占位 Screen 的"返回"在无导航栈时（深链接直达）不可见——桌面 Task S 提供外壳后会自然获得返回语义。
- 集成测试在桌面用户库留下 `桌面集成验证板` 测试板（无害，可手动清）。
- 桌面真实帧率 profile、W1 交互补全、W2/W3/W4 占位填充 = 后续并行窗口（提示词见 `W6_INTEGRATION_AND_PARALLEL_PROMPTS.md`）。
- 合并顺序建议：本分支（Task 0 管道）→ Task S（外壳）→ E/A/C/B/D，每步全量测试。

## 6. 待集成提交

- `codex/whiteboard-w6-integration-base`：WIP 存档 `bea90fa6` + 剥离 `971ccb64` + 本收尾提交（迁移 / drift store / 路由 / 占位 Screen / gating / 测试 / 文档）。
