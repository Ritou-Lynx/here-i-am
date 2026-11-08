<!-- relay:contract v1 -->
# RELAY 2026-11-08 清理 B：删除 Dev Room 与项目记忆

## 目标
彻底删除 App 里的 Dev Room（林埃在聊天里召唤 Codex/OpenCode 改项目的旧功能）以及与它绑定的“项目记忆”（Project Memory），连同电脑端只为它们存在的转发、保活与收尾代码。用户现在直接用官方远程连接；项目记忆删除是用户 11-07 已定的 M5 项。不做其他重构。A 组已在 #110 合并。

## 完成标准
- [ ] `git grep -nE "DevAgentBridgeService|dev_session_start_or_continue|DevSessionAddendum|devRoom|project_memory_query|ProjectMemoryService|ProjectMemoryIntentClassifier|syncConfiguredProjectMemory" -- lib test` 无结果。
- [ ] `git grep -nE "i_activity_store|i_activity_crypto|i_activity_key_provider|i_project_registry|project_memory_closeout" -- tools scripts .github` 无结果。
- [ ] `flutter analyze` 无新增 error/warning；CI 全绿，不许 skip 测试。
- [ ] 设置 → 开发与诊断 只剩“诊断”组：日志、重建搜索索引、重置本机数据。
- [ ] 数据库表定义、迁移、schemaVersion 不变；`tools/i_continuity_gateway/identity.default.json` 保留。

## 具体删除清单
（以下 1–6 为 App 侧，7 为电脑端）
### 1. Dev Room 界面与路由
- 删目录：`lib/ui/dev_agent/`（7 个文件）
- `lib/routing/routes.dart`：删 `devRoom` 常量；`lib/routing/router.dart`：删对应路由和 import。
- `lib/ui/desktop/widgets/global_desktop_chat_overlay.dart`：删 `AppRoutes.devRoom` 那一行。
- `lib/ui/settings/widgets/personal_center_screen.dart`：删 `Dev Room` 入口。删完后“开发与诊断”里“开发工具”组为空，把这个空组整段删掉，只留“诊断”组。

### 2. 聊天里的 Dev Session 工具和卡片
- 删文件：`lib/agent/built_in_tools/dev_session_tool.dart`、`lib/agent/built_in_tools/project_memory_query_tool.dart`
- `lib/agent/skills/character_tools_factory.dart`：删 `buildDevSessionStartOrContinueTool(...)` 和 project_memory_query 工具的注册。
- `lib/agent/skills/companion_agent/companion_agent_skill.dart`：删掉所有讲 `dev_session_start_or_continue`、Dev Room、`project_memory_query`、OpenCode/Codex 召唤的提示词行（约 154–162 行那几条），其他提示词一字不改。
- `lib/agent/companion_agent/companion_agent.dart`：删掉项目记忆注入那段（`ProjectMemoryIntentClassifier.isProjectIntent` 分支、`syncConfiguredProjectMemory`、`project_memory_context` system reminder），以及对应 import。
- 删文件：`lib/ui/character/widgets/addenda/dev_session_addendum_widget.dart`；`message_addendum_renderer.dart` 里 `dev_session` 类型的分支改成和“未知类型”一样不渲染（老消息里如果存着 dev_session 附件，不能崩溃）。
- `lib/data/services/persona_chat_service.dart`：删 `persistDevSessionDecision` 等只服务 dev_session 附件的方法。
- `lib/ui/character/widgets/persona_chat_screen.dart`：删 `_maybePollDevAgentRuns` 及调用、import。
- `lib/agent/companion_agent/companion_tool_permissions` 相关（如果有 dev_session/project_memory 工具名白名单）同步删掉。

### 3. Bridge 客户端与后台任务
- 删文件：`lib/data/services/dev_agent_bridge_service.dart`、`lib/data/services/task_handlers/dev_session_followup_handler.dart`、`lib/domain/models/dev_agent_codex_options.dart`
- `lib/data/services/local_task_registry.dart`：删 `handleDevSessionFollowup` / `handleDevSessionFollowupFailure` 的注册。
- `lib/data/repositories/memex_router.dart`：删 `DevAgentBridgeService` 初始化与 `syncConfiguredProjectMemory()` 调用。
- 全仓库搜 `DevAgentBridgeService.` 的其余调用点一并删除。

### 4. 项目记忆（App 内）
- 删文件：`lib/data/memory_v3/services/project_memory_service.dart`、`lib/data/memory_v3/retrieval/project_memory_intent_classifier.dart`
- `lib/data/workbench_ai/search/existing_search_adapters.dart`：删 `ProjectMemoryWorkbenchSearchAdapter` 及其注册处。`SearchScope.projectMemory` / `SearchPermissionLane.projectMemory` 等契约枚举：如果删掉只牵涉少量代码和测试就删；如果会波及大量契约测试，就保留枚举值并在 PR 描述说明。
- `lib/data/memory_v3/services/memory_recall_trace_service.dart`：删 project memory 的解析分支（遇到旧 trace 里的该表名时按“未知来源”处理，不崩溃）。
- `lib/db/daos/search_dao.dart`：删 `upsertProjectMemoryFts`、`deleteProjectMemoryFts`、`searchProjectMemory` 方法（建 FTS 虚表的 SQL 可以保留，避免改迁移）。

### 5. 数据库
**表定义和迁移一律不动**：`dev_agent_tables.dart`、`dev_agent_artifact_tables.dart`、`ProjectMemoryItems`/`ProjectMemorySources`、`app_database.dart` 里的 `@DriftDatabase` 表列表、`_createDevAgent*` 迁移函数、schemaVersion 都保持原样（老库升级路径要能编译和运行）。只删 DAO/服务层的读写。`topic_thread_service.dart` 的 `linkedProjectMemoryIds` 列也保留。

### 6. 测试
删除只测试已删代码的测试：`test/ui/dev_agent/codex_options_editor_test.dart`、`test/data/services/dev_agent_bridge_service_test.dart`、`test/domain/models/dev_agent_codex_options_test.dart`、`test/data/memory_v3/services/project_memory_service_test.dart`。
`test/db/dev_agent_codex_options_migration_test.dart` 和 `test/db/fixtures/b3_schema62.sql` 是迁移测试，**保留**（如果它 import 了已删的 model，改成直接断言表列，不许删测试凑绿）。
`companion_tool_permissions_test.dart`、`workbench_*search*_test.dart`、`context_envelope_test.dart` 里涉及 dev_session/project memory 的断言，按删除后的真实行为更新，并在 PR 描述逐条说明改了什么。

### 7. 电脑端（tools / scripts）
- 删文件：`scripts/devroom_tailscale_keepalive.ps1`
- `tools/comic_server/install_comic_autostart.ps1`：删掉注册 `tailscale serve --https=443 → 127.0.0.1:47831`（DevRoom Bridge）的那段和注释，漫画服务本身的注册不动。脚本保持 UTF-8 带 BOM、CRLF。
- `tools/dev_agent_bridge/`：只删项目记忆收尾：`project_memory_closeout.mjs`、`project_memory_closeout.test.mjs`，并从 `dev_agent_bridge.mjs` 去掉对它的 import/调用。目录里的其他文件（phone_memory_usb、workbench/windows_text_gate 等实验代码）**这次不动**，另行审计。
- `tools/i_continuity_gateway/`：删 `i_activity_store.mjs`、`i_activity_crypto.mjs`、`i_activity_key_provider.mjs`、`i_project_registry.mjs` 及它们的 `.test.mjs`（唯一使用者就是上面的 project_memory_closeout）。**`identity.default.json` 必须保留**（生产 i MCP 在读）。README 里对应那行改成“已随清理 B 删除”。
- 先 `git grep -nE "i_activity_store|i_activity_crypto|i_activity_key_provider|i_project_registry|project_memory_closeout" tools scripts` 确认删除后无残留引用。

## 允许修改的路径
- lib/、test/（仅限清单涉及的文件，以及删除后因 import 失效必须跟着改的文件）
- scripts/devroom_tailscale_keepalive.ps1（删除）
- tools/comic_server/install_comic_autostart.ps1（只删 DevRoom :443 段）
- tools/dev_agent_bridge/dev_agent_bridge.mjs、project_memory_closeout*.mjs
- tools/i_continuity_gateway/（删 i_activity_* 与 i_project_registry*，改 README）
- .github/workflows/ci.yml（仅当某个已删测试被显式点名时删那一行）

## 不做 / 边界
- 不动：tools/i_remote_mcp、tools/i_core、tools/i_memory（生产 i MCP）、tools/agent_relay、tools/dev_agent_bridge 里除项目记忆收尾外的其他文件、聊天/GPT-Live/催睡/心率/饮食/记账/购物业务代码、数据库 schema 与迁移。
- 不构建、不安装 App，不碰真实数据、账户与本机计划任务。

## 验证命令
- `flutter analyze`
- `flutter test`（本机超时则跑 test/agent、test/data、test/ui/character、test/ui/settings、test/db，全量以 CI 为准）
- `cd tools/dev_agent_bridge && node --test $(ls *.test.mjs | grep -v '^windows_text_gate_' | grep -v '^workbench_text_task_product_host.test.mjs$')`
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_continuity_gateway/*.test.mjs`（后者删完若无测试文件则跳过）

## 需要真人的部分
- 合并 PR。之后 Claude 会用只读脚本轮检查电脑上是否还有 bridge/保活自启任务，需要停用时再走 write 脚本轮请你点 👍。
