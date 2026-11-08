<!-- relay:contract v1 -->
# RELAY 2026-11-08 清理 A：删除模型用量/异步任务页/自定义 Agent/Skills

## 目标
彻底删除“设置 → 开发与诊断”里 4 个已废弃的旧 memex 功能（模型用量、异步任务列表、自定义 Agent、Skills）及只为它们存在的后端代码，不做其他重构。

## 完成标准
- [ ] `rg -n "ModelStatsPage|AsyncTaskListPage|AgentActivityWidget|CustomAgentConfig|SkillsManagementPage|LLMCallRecordService|PureSkillHostAgent|MemexSkillHostAgent|flutter_js|initCustomAgentHandler|registerBuiltInEventSerializers" lib test` 无结果。
- [ ] `flutter analyze` 无新增 error/warning（与 v3-lab 对比）。
- [ ] CI 的 Flutter 测试全绿；只删除测已删代码的测试，不许 skip 或改断言凑绿。
- [ ] 设置 → 开发与诊断 只剩：Dev Room、日志、重建搜索索引、重置本机数据。
- [ ] 数据库表定义、迁移、schemaVersion 不变。

## 具体删除清单
### 1. 设置入口
`lib/ui/settings/widgets/personal_center_screen.dart`：在 `PersonalCenterSection.advanced` 的“开发工具”组里删掉 `模型用量`、`异步任务`、`自定义 Agent`、`Skills` 4 个 `_Destination`，以及对应的 import（model_stats_page / async_task_list_page / custom_agent_config_page / skills_management_page）。**`Dev Room` 这一项保留**（B 组单独处理）。

### 2. 模型用量（连同用量记录一起停掉）
- 删文件：`lib/ui/settings/widgets/model_stats_page.dart`
- `lib/data/repositories/memex_router.dart`：删 `getAggregatedStatistics`、`getAgentUsages` 两个方法及不再使用的 import。
- `lib/agent/agent_controller.util.dart`：删除调用 `LLMCallRecordService.instance.recordCall(...)` 的那个 collector（整个注册函数如果只做这件事就整个删，并删掉调用它的地方）。
- `lib/data/services/task_handlers/analyze_assets_handler.dart`：删掉 `recordCall` 调用。
- `lib/data/repositories/card.dart`：删掉 “Get LLM call stats” 那段（计算 `llmStats`），`CardDetail` 不再传 llmStats。
- `lib/domain/models/card_detail_model.dart`：删 `llmStats` 字段、`LLMStats` 及只被它用的 `AgentStats` 等类（先确认没有其他引用）。
- 删文件：`lib/data/services/llm_call_record_service.dart`。`lib/utils/token_usage_utils.dart` 如果删完后没有任何引用也删掉。
- **数据库表定义和迁移不动**（不改 schemaVersion、不跑表删除迁移），旧表留在库里无害。

### 3. 异步任务列表页
- 删文件：`lib/ui/settings/widgets/async_task_list_page.dart`
- 删文件：`lib/ui/agent_activity/widgets/agent_activity_widget.dart`（全仓库没有任何地方实例化它），并删掉 `lib/main.dart` 里对它的 import。
- `memex_router.dart` 的 `getTasks` 如果只剩这个页面在用就删掉。
- **后台任务队列本身（LocalTaskExecutor、各 task handler、AgentActivityService）完全不动**，聊天委派、照片分析、购物都依赖它。

### 4. 自定义 Agent + Skills（两者是一套）
- 删文件：
  - `lib/ui/settings/widgets/custom_agent_config_page.dart`
  - `lib/ui/settings/widgets/skills_management_page.dart`
  - `lib/data/services/custom_agent_config_service.dart`
  - `lib/data/services/task_handlers/custom_agent_task_handler.dart`
  - `lib/domain/models/custom_agent_config.dart`
  - `lib/agent/pure_skill_host_agent/`（整个目录）
  - `lib/agent/memex_skill_host_agent/`（整个目录）
  - `lib/agent/flutter_js_runtime.dart`
- 删除调用：
  - `memex_router.dart` 初始化里的 `registerBuiltInEventSerializers();` 和 `await CustomAgentConfigService.instance.registerAll(userId);`
  - `lib/data/services/background_task_drain_runner.dart` 里的 `registerAll(userId)` 及 import
  - `lib/data/services/local_task_registry.dart` 里的 `initCustomAgentHandler();` 及 import
- `lib/data/services/file_system_service.dart`：`resolveSkillPath`、`syncSkillsIfNeeded`、`syncSkillsBack`、`SkillSyncResult` 等只给自定义 Agent 用的方法，确认无其他引用后删除。
- `pubspec.yaml`：删 `flutter_js` 依赖，运行 `flutter pub get` 更新 `pubspec.lock`。
- l10n：`customAgents` 等只被这些页面用的文案，若删完无引用，从 arb 源文件删除并重新生成（按仓库现有 l10n 生成方式）；如果仓库 l10n 是手写的 `app_localizations_ext_*.dart`，同样删掉无引用条目。不确定的文案宁可留着。
- **注意不要碰**：`lib/agent/skills/`（林埃内置技能，是代码，和 Skills 页无关）、`companion_delegation_handler.dart` 里的 skills。

## 允许修改的路径
- lib/（仅限上面清单涉及的文件，以及删除后因 import 失效必须跟着改的文件）
- test/（仅删除只测已删代码的测试）
- pubspec.yaml、pubspec.lock（删 flutter_js）
- lib/l10n/ 与 l10n 源文件（仅删无引用文案）

## 不做 / 边界
- 不动：Dev Room 相关代码（B 组另做）、`lib/agent/skills/`（林埃内置技能）、后台任务队列（LocalTaskExecutor/各 task handler/AgentActivityService）、聊天、GPT-Live、催睡、心率、饮食、记账、购物、tools/、.github/workflows、数据库 schema 与迁移。
- 不构建、不安装 App，不碰真实数据与账户。

## 验证命令
- `flutter pub get`
- `flutter analyze`
- `flutter test`（若本机超时，只跑 test/ui/settings 与 test/data/services 相关文件，以 CI 为准）

## 需要真人的部分
- 合并 PR；之后从 v3-lab 重装 App 时顺带确认设置页。
