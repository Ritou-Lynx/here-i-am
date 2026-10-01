# GOAL-20260828-legacy-cleanup-wave1 — 旧代码清理第一波

> 状态：已完成（验收通过并进入 `v3-lab`）
> 验收主窗 task/thread ID：`01a047e8-6690-7c71-ba54-18a9be9e0058`
> 并行 Goal：`GOAL-20260828-p4-production-reachability-repair`（不得触碰）
> Roadmap：`docs/companion-first/PRODUCT_ROADMAP.md`
> 基线：`v3-lab@53d2dc91668b6ca5ba82cf9f4688f1b3ea609dbc`
> 当前对齐基线：`v3-lab@07db173b0ba277a653a389f4507944c7cb90ac01`
> 落地主线：`v3-lab@a29b212e779a3ca9dcbc28c1316034f24228fdc9`
> 控制分支 / Worktree：`codex/legacy-cleanup-wave1-control` / `.worktrees/legacy-cleanup-wave1-control`
> 提出日期：2026-08-28
> 确认日期：2026-08-28

## 最终结果

在不改变现役产品行为、数据和公开契约的前提下，移除第一批已证实纯孤岛代码，迁移仍有价值的退役测试覆盖，并使全仓 analyzer 的测试编译错误从 23 个归零。

## 进入条件

- 用户明确授权本 Goal 作为与 P4 并行的例外任务。
- 验收主窗只做控制面、审计、集成和验收，不直接实现工作包。
- 两个写工作包使用独立分支与 Worktree；主工作区现有未提交改动不进入本 Goal。
- 基线审计已确认 23 个 analyzer error 只来自 4 个退役测试文件；拟删除生产簇均为零注册、零调用或仅自循环引用。

## 完成定义

- [x] 仍有效的 Tavern 角色导入、Companion 权限/记忆冻结与 Companion live smoke 覆盖得到保留或迁移。
- [x] 退役 Comment/PostComment/CharacterMemory 测试不再制造编译错误。
- [x] 已证实纯孤岛生产簇及其专属测试/单卡入口被完整删除，无悬空 import、注册或调用。
- [x] `dart analyze --format machine` 的 ERROR 数为 0；新增 warning 不超过基线。
- [x] 工作包专项测试、相关组合回归、`scripts/verify_critical_fixes.ps1` 与 `git diff --check` 通过。
- [x] 形成唯一候选 commit；完成 `hereIAmV3` debug APK 构建验证。
- [x] 主窗逐包审计 diff、关键断言、越界情况和 handoff。
- [x] 用户授权验收主窗复审后代为作出通过结论。
- [x] Goal 页与 i closeout 已更新。
- [x] 候选进入 `v3-lab`，`I_PROJECT_STATE.md`、Roadmap 与 DEVLOG 同步收口；不 push。

## 明确不做

- 不触碰 P4、白板、Voice / i Gateway 相关代码或状态文件。
- 不删除或重构 SharedLife fallback、CardCache、`submitInput`、日程断链、`sceneDirective` 或主界面/Persona UI 大簇。
- 不修改数据库 schema、生成文件、依赖版本、用户数据或 `_System/memory/memory_sync_pending.json`。
- 不恢复旧自动捕获、Comment Agent、旧 Card Agent 产品能力；不扩大当前 Goal。
- 不安装、不发布、不 push；设备真人交互不作为本轮清理 Gate。

## 工作包状态

| ID / 名称 | 执行方式 | agent ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T / 退役测试迁移 | 子 Agent + 隔离 Worktree | `/root/legacy_tests` | `69240138` | `codex/legacy-cleanup-wave1-tests` / `.worktrees/legacy-cleanup-wave1-tests` | 已集成 | `ae526f5e` + `35bab558` | `docs/development/legacy-cleanup-workstreams/TEST_DEBT_HANDOFF.md` | 主窗与独立审计通过 | 相关测试 `5/5`；全仓 ERROR `0` | 不单独验收 | 完成 |
| O / 纯孤岛删除 | 子 Agent + 隔离 Worktree | `/root/legacy_orphans` | `69240138` | `codex/legacy-cleanup-wave1-orphans` / `.worktrees/legacy-cleanup-wave1-orphans` | 已集成 | `ddad3205` + `d31dab59` + `ebc73fd2` | `docs/development/legacy-cleanup-workstreams/ORPHAN_CODE_HANDOFF.md` | 主窗与独立审计通过 | 精确残留 `0`；任务组合 `14/14`；全仓 ERROR `0` | 不单独验收 | 完成 |
| I / 集成与验收 | 验收主窗 | `01a047e8-6690-7c71-ba54-18a9be9e0058` | 两包已审计 commit | `codex/legacy-cleanup-wave1-control` | 已完成 | `a29b212e`（落地主线；构建源码 `ee77d213`） | 本页 | 通过 | 自动 Gate 全绿；APK 构建成功 | 用户授权主窗复审后通过 | 完成 |

## 工作包边界

### T — 退役测试迁移

- 拥有：`test/agent/comment_tool_factory_test.dart`、`test/agent_refactor_functional_test.dart`、`test/data/repositories/post_comment_test.dart`、`test/live_agent_eval_test.dart`，以及新增的 Tavern 角色导入专属测试。
- 必须迁移并保留仍有效的 Tavern 角色导入测试；Comment/PostComment/CharacterMemory/assembler/compressor 退役覆盖可删除。
- Companion live smoke 仅保留为显式环境型 smoke；无密钥时必须正常 skip/return，不得默认失败。
- 不修改生产代码，不修改 `test/agent/user_knowledge_query_tool_test.dart`。

### O — 纯孤岛删除

- 拥有：MemorySync/MemoryAgent 自循环簇、`RelatedFactsList` 单卡链、未注册 UserKnowledgeQuery 簇及专属测试、未注册 `FileSystemSkillAgentHandler`。
- `MemexRouter` 只允许删除 `fetchTimelineCard` 及其专属 import；多卡 timeline、CardCache、hydrate 路径必须保留。
- 必须保留 `AgentDefinitions.cardAgent`、`PkmSkill`、`analyze_assets`、`conversation_capture_task` 和用户数据文件。
- 不修改 T 工作包拥有的测试。

## 依赖与集成顺序

1. T 与 O 从同一基线并行执行，禁止跨包写入。
2. 主窗先审计并集成 T，确认活跃测试覆盖未丢失。
3. 主窗再审计并集成 O，处理专属测试删除并核对引用闭包。
4. 统一跑 analyzer、专项/组合测试、关键修复检查、diff 检查和可行的唯一候选构建。
5. 仅在当前 `v3-lab` 并行改动可安全对齐后，才把候选交给用户决定是否进入日常分支；本 Goal 不自行 push。

## 决策与变更请求

- 2026-08-28：用户明确授权“并行例外任务”；因此允许本 Goal 与 P4 同时活动，但使用独立控制分支/Worktree，且 P4 为硬边界。
- 2026-08-28：主工作区存在其他任务未提交改动，Goal 控制面暂不写主工作区的 Roadmap、`I_PROJECT_STATE.md`、DEVLOG；最终集成前统一对齐并收口，避免覆盖并行成果。
- 2026-08-28：O 在旧综合测试发现 UserKnowledge 引用。T 证明该引用只属于将删除的退役 knowledge-context 测试，Tavern 覆盖独立迁移且不携带该依赖；因此批准 O 删除 UserKnowledge 孤岛，并固定集成顺序为 T → O。
- 任何扩大删除范围、出现真实调用者、测试语义不明或公共契约变化，都必须退回验收主窗，不得由 worker 自行决定。

## 集成记录

- 2026-08-28：从 `v3-lab@53d2dc91` 创建隔离控制分支与 Worktree，尚未集成代码。
- 2026-08-28：控制面提交为 `69240138`；T、O 两包均从该提交建立隔离 Worktree，并分别派发给 `/root/legacy_tests`、`/root/legacy_orphans`。
- 2026-08-28：O 交付 `ddad3205` + `d31dab59`。主窗复核变更文件、基线符号闭包、`MemexRouter` 最小 diff、删除后残留与保留路径，静态审计通过；因独立 Worktree 缺 package config 且 Flutter 缓存锁占用，analyze/test 留给集成 Gate。
- 2026-08-28：独立审计确认 O 无 P0–P2 发现；发现 handoff 将 7 个生产删除误写为 8 个，原 worker 已在 `ebc73fd2` 修正。
- 2026-08-28：T 交付 `ae526f5e` + `35bab558`。主窗与独立审计确认 Tavern 覆盖完整且加强、live smoke 默认无网络、两项活跃回归字节级未改；共享 Flutter runner 挂起，test/analyze 留给集成 Gate。
- 2026-08-28：按 T → O 顺序无冲突集成；控制分支构建源码候选为 `ee77d213`。主工作区仍有 P4/Voice 并行未提交状态，因此未改 `v3-lab`、Roadmap、`I_PROJECT_STATE.md` 或 DEVLOG，避免吸收/覆盖并行成果。
- 2026-08-28：全仓 analyzer 为 `ERROR 0 / WARNING 42 / INFO 328`（基线为 `ERROR 23 / WARNING 42 / INFO 332`）；warning 未增加。Tavern、默认离线 live smoke、Companion 权限、memory-freeze 共 `5/5`，LocalTaskExecutor 组合 `14/14`，关键修复守门 `3/3`，最终 diff check 通过。
- 2026-08-28：`hereIAmV3` debug APK 构建成功；Android NDK 版本与旧 Java/Kotlin 插件提示为既有非阻断警告，本 Goal 未修改平台配置或依赖。构建后自动触碰的三个 Windows 生成文件已恢复，候选工作树干净。
- 2026-08-28：精确孤岛符号在 `lib/` / `test/` 中为零命中；`fetchTimelineCards`、hydrate、CardCache、PkmSkill、`AgentDefinitions.cardAgent`、companion delegation、`analyze_assets` 与历史 capture no-op 均保留。
- 2026-08-28：额外探索性全量 `flutter test` 到达 `1849 passed / 16 skipped / 21 failed` 后，未改的 `input_sheet_test.dart` 长时间不收敛；带 30 秒单测上限的 machine 复跑仍无法在有界时间结束，两次均只终止本验收窗启动的 runner。已观测红灯包括未初始化 SharedPreferences plugin、睡眠提示词旧标签断言、Personal Center SVG / 文案 / Material 断言，均位于本 Goal 未改路径。该探索不冒充全量通过，也不覆盖已通过的范围专项、组合 Gate、全仓编译与零引用闭包证据。
- 2026-08-28：把当前已提交的 `v3-lab@07db173b` 合入隔离控制分支，生成候选 `be4154da`。基线增量仅为 P4 的五份 Goal / Roadmap / 状态文档，无生产或测试代码变化；合并无冲突，`git diff --check` 通过，清理差异闭包不变。P4 验收任务与主工作区未提交 Voice 改动均未触碰。
- 2026-08-28：用户明确授权验收主窗“再审查一遍，没有问题就通过并提交”。主窗重新核对 17 文件完整 diff、删除 / 保留符号闭包和并行路径交集；独立 Terra 复审无 P0–P3，建议通过；fresh analyzer 仍为 `ERROR 0 / WARNING 42 / INFO 328`，关键守门仍为 `3/3`。定向 Flutter 复跑因共享 SDK 锁持续等待而由主窗只终止本次 runner，未产生失败结果或工作树变更；`lib`、`test`、`android` 与 `pubspec.yaml` 和已通过 `19/19` 定向测试的构建源码对象级一致，原测试证据继续有效。
- 2026-08-28：落地前确认候选 17 个路径与主工作区 18 个既有脏路径交集为 0，且 `v3-lab@07db173b` 是候选祖先；随后以 `--ff-only` 把候选安全快进到 `v3-lab@a29b212e`。Voice / i Gateway、P4 与共享文档的既有未提交内容均原样保留，没有被暂存、覆盖或吸收。

## 真人验收

- 候选 commit / 产物：`v3-lab@a29b212e`（构建源码 `ee77d213`）；`build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`，407177559 bytes，SHA-256 `FD923E15D10D5DA8A05B6A6FEC96F202BFBDB3B735A5F65DB009D2EBFF3E8FB6`
- 场景：审阅删除清单、保留覆盖与自动 Gate 结果；本轮无设备 UI 操作要求。
- 结果：通过。用户授权验收主窗依据复审证据代为作出最终判断；未发现阻断项。
- 未完事项：探索性全量套件的既有 21 个失败 / 长时不收敛留作独立测试债，不能在本 Goal 越界修复。P4 与所有明确不做项继续由各自 Goal 管理。

## Goal 结论

- 完成时间：2026-08-28
- 最终基线：`v3-lab@a29b212e779a3ca9dcbc28c1316034f24228fdc9`（本页及共享状态收口由后续文档提交完成）
- push：未授权
- 下一 Goal 候选：不在本 Goal 内提出
