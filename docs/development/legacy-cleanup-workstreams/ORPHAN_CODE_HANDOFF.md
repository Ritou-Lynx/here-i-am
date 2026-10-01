# GOAL-20260828-legacy-cleanup-wave1 — 工作包 O handoff

## 交付

- 工作包：O / 纯孤岛删除
- 分支 / Worktree：`codex/legacy-cleanup-wave1-orphans` / `.worktrees/legacy-cleanup-wave1-orphans`
- 派发基线：`69240138bed8ac36dba1a369d9f0a2cd5cfb25c5`（父基线 `v3-lab@53d2dc91668b6ca5ba82cf9f4688f1b3ea609dbc`）
- 生产删除 commit：`ddad32051edd2f221e7cad83b27a920d089576c1`；本 handoff 的 SHA 校正由紧随其后的仅文档提交承载。

## 删除簇与证据

### 1. MemorySync / MemoryAgent 自循环簇

- 删除前：全仓 Dart/YAML/Markdown 引用检索中，`MemorySyncService` 仅在 `memory_sync_service.dart` 自身出现，`MemoryAgent` 仅由该 service 调用且自身定义；没有生产注册或调用者。
- 变更：删除 `lib/data/services/memory_sync_service.dart` 与 `lib/agent/memory_agent/memory_agent.dart`。
- 删除后：检索 `MemorySyncService|MemoryAgent` 为零命中。
- 保留：没有修改任何用户数据；尤其没有读取、删除或修改 `_System/memory/memory_sync_pending.json`。

### 2. RelatedFactsList 与单卡链

- 删除前：`RelatedFactsList` 仅在自身定义中出现，唯一调用是其内部对 `MemexRouter.fetchTimelineCard` 的调用；`fetchTimelineCard` 唯一调用 `getTimelineCard`。
- 变更：删除 `lib/ui/core/widgets/related_facts_list.dart`、`lib/data/repositories/get_timeline_card.dart`，并从 `lib/data/repositories/memex_router.dart` 删除 `fetchTimelineCard` 和专属 import。
- 删除后：`RelatedFactsList`、`fetchTimelineCard` 与独立 `getTimelineCard` 均无引用。剩余 `getTimelineCards`、`fetchTimelineCards` 与 `ManageTimelineCardSkill.getTimelineCardMetadata` 均为不同的现役多卡/元数据路径。
- 保留：`CardCache`、`hydrate_card.dart`、`get_timeline_cards.dart`、`get_cards_by_ids.dart`、搜索 hydrate 入口均未改动。

### 3. UserKnowledge 未注册簇

- 删除前：`UserKnowledgeQueryTool` 与 `UserKnowledgeContextService` 没有生产注册；专属测试位于 `test/agent/user_knowledge_query_tool_test.dart`。
- 发现的跨包引用：`test/agent_refactor_functional_test.dart:8,336` 仍导入/调用 `UserKnowledgeContextService`。该文件由 T 工作包拥有，初始时停止删除并上报。
- 主窗裁决（2026-08-28）：T 已确认该引用只属于退役 knowledge-context 片段测试，T commit 将删除该综合测试/import；Tavern 覆盖将迁移至独立测试。集成顺序固定 T → O。
- 变更：删除 `lib/agent/built_in_tools/user_knowledge_query_tool.dart`、`lib/agent/context/user_knowledge_context_service.dart` 和专属测试 `test/agent/user_knowledge_query_tool_test.dart`。
- 删除后：唯一残留匹配是上述 T-owned、待 T 删除的 `test/agent_refactor_functional_test.dart:336`；没有 `lib/` 生产引用或注册。
- 保留：现役 `PkmSkill` 及 companion delegation 对它的使用未改动。

### 4. FileSystemSkillAgentHandler

- 删除前：`FileSystemSkillAgentHandler`、`handleFileSystemSkillAgentImpl` 与 `file_system_skill_agent_task` 仅在 handler 文件自身出现，没有 LocalTaskRegistry 注册。
- 变更：删除 `lib/data/services/task_handlers/file_system_skill_agent_handler.dart`。
- 删除后：上述 handler / task 检索为零命中。
- 保留：`AgentDefinitions.cardAgent`、`companion_delegation`、`handle_analyze_assets`、历史 `conversation_capture_task` no-op 注册与 handler 均仍存在。

## 验证

| 命令 / 检查 | 结果 |
|---|---|
| 删除前 `rg`（四簇符号、注册与调用） | 发现并记录各闭包；仅 UserKnowledge 有 T-owned 测试残留。 |
| 删除后 `rg`（四簇符号） | 三个已删除簇零命中；UserKnowledge 仅剩 `test/agent_refactor_functional_test.dart:336`，由 T 交付清除。`lib/` 无残留。 |
| 保留路径 `rg` | 多卡 timeline、CardCache、hydrate、PkmSkill、`companion_delegation`、`handle_analyze_assets`、`conversation_capture_task` 均命中。 |
| `git diff --check` | 通过。 |
| `flutter analyze --format machine lib/data/repositories/memex_router.dart test/agent/user_knowledge_query_tool_test.dart` | 未完成：Flutter 全局缓存锁持续占用，命令未返回。 |
| `D:\flutter\bin\cache\dart-sdk\bin\dart.exe analyze --format machine lib` | 未完成：此隔离 Worktree 不存在 `.dart_tool/package_config.json`；分析进程未能完成，已停止自身启动的挂起进程。 |
| `flutter test test/agent/user_knowledge_query_tool_test.dart` | 未完成：同一 Flutter 全局缓存锁与未初始化依赖阻断。 |

最终集成候选必须在 T → O 后执行全仓 analyzer 与相关组合测试；O 单包不能安全修改 T-owned 测试来消除这一预期中间状态。

## 修改文件

- 删除：7 个生产孤岛文件与 1 个专属测试文件。
- 修改：`lib/data/repositories/memex_router.dart`，仅移除 `fetchTimelineCard` 和其专属 import。

## 未完事项 / 风险

- 等待 T 的 commit 删除 `test/agent_refactor_functional_test.dart` 中的旧 UserKnowledge 引用；未完成前，全仓 analyzer 对该测试的报错是预期集成前差异。
- 当前 Worktree 未初始化 `.dart_tool` 且 Flutter 工具缓存锁占用，未取得 O 分支 analyzer/test 成功结果；这不是代码失败证据，需由控制 Worktree 的集成 Gate 重跑。
- 未改 schema、生成文件、依赖、SharedLife、CardCache、timeline/hydrate、多卡路径、`submitInput`、日程、P4/白板/Voice/i Gateway 或状态文件。
