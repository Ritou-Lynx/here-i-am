# GOAL-20260828-legacy-cleanup-wave1 — T 退役测试迁移 Handoff

## 真实闭环

- 删除只覆盖已退役 CommentTool / PostComment 的测试：
  `test/agent/comment_tool_factory_test.dart`、
  `test/data/repositories/post_comment_test.dart`。
- 删除退役综合测试 `test/agent_refactor_functional_test.dart`，没有迁移其中
  CharacterMemory、assembler、compressor、Comment 或 UserKnowledge 覆盖。
- 将原文件的 Tavern JSON/PNG preview、导入、重名冲突、world book 写入和非法格式
  覆盖迁移为 `test/data/services/tavern_character_import_service_test.dart`。
- 将 `test/live_agent_eval_test.dart` 收窄为 Companion 专属 smoke；只有
  `MEMEX_RUN_LIVE_AGENT_SMOKE=true` 且 `OPENAI_BASE_URL` 与
  `OPENAI_API_KEY` 都存在时才会调用网络，其他情形正常提前返回。

## 保留 / 删除的覆盖

- 保留：Tavern 角色卡导入的 JSON、PNG、映射后的 persona、PNG avatar、冲突、
  world entries 与错误格式路径；Companion 的显式 live smoke。
- 删除：Comment 保存/回复路由、PostComment 完成等待、CommentAgent live、
  CharacterMemory CRUD/timeline、context assembler/compressor、UserKnowledge
  snippet 的退役测试。
- 未修改：`test/agent/companion_tool_permissions_test.dart`、
  `test/agent/character_tools_factory_memory_freeze_test.dart`。

## 验证证据

- `git diff --check`：通过。
- 已尝试 `D:\\flutter\\bin\\flutter.bat test` 运行 Tavern 新测试、无密钥 live
  smoke 和两项活跃回归。测试 runner 在本工作树无输出且超过有界等待时间；只终止
  本任务启动的 PID 40240，没有影响全局缓存或其他进程。因此没有可声明的 pass/fail。
- 已尝试 `D:\\flutter\\bin\\dart.bat analyze` 仅分析本任务拥有的两个保留测试；同样
  无输出超过有界等待时间，终止本任务 PID 43500。因此该 analyze Gate 未取得结果。

## 未完事项 / 移交控制 Worktree

1. 在可完成 Flutter runner 的环境重新运行：
   `flutter test test/data/services/tavern_character_import_service_test.dart test/live_agent_eval_test.dart test/agent/companion_tool_permissions_test.dart test/agent/character_tools_factory_memory_freeze_test.dart`。
2. 重新运行：
   `dart analyze test/live_agent_eval_test.dart test/data/services/tavern_character_import_service_test.dart`。
3. 合并后由控制 Worktree 做全仓 analyzer、组合回归与 Goal 级 Gate。

## 交付

- Goal / 工作包：`GOAL-20260828-legacy-cleanup-wave1` / `T`。
- task/thread：`/root/legacy_tests`。
- 分支 / Worktree：`codex/legacy-cleanup-wave1-tests` /
  `.worktrees/legacy-cleanup-wave1-tests`。
- 基线：`69240138bed8ac36dba1a369d9f0a2cd5cfb25c5`
  （父基线 `v3-lab@53d2dc91`）。
- 测试迁移交付 commit：`ae526f5ebd75a555118a31037e323fcadf3d083a`。
- 共享契约影响：无生产代码、数据 schema、公开 API 或活跃权限 / memory-freeze
  覆盖的改动。
- 工作树：交付提交后应为干净；未 push。
