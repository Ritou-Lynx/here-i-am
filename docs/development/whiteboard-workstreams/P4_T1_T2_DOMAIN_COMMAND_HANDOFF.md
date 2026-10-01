# P4-T1/T2 Domain Commands Handoff

## 2026-08-26 Persistent Undo 返修交付

- Goal / 工作包：`GOAL-20260824-ai-workbench-wave1` / `P4-T1/T2 Persistent Undo`。
- task：`/root/goal1_p4_repair`；分支 `codex/whiteboard-w0-goal1-p4-repair`；Worktree `D:\here-i-am\.goal-worktrees\goal1-p4-repair`；精确基线 `7f7af225fe401ce0d7c44964fd8afccb31f24077`。
- 审计结论：桌面行动卡的同步 `canUndo` 原来只读取 coordinator 的 legacy `_undoBindings`；Domain facade 虽支持 Drift restore 和 lazy undo restore，但桌面聊天初始化没有先 hydration，通用 `undo` 也没有路由到 `whiteboard_domain_commands`。
- 修复闭环：桌面浮动聊天在消息首次呈现前调用 `hydrateUndo(characterId)`；coordinator 只读一次真实 Drift action stream，按 `actionType` 分别恢复 `whiteboard_group_and_connect` 与 `whiteboard_domain_commands`，同步 `canUndo` 同时查询两类 binding，通用撤销进入对应 legacy host 或 provider-neutral Domain facade。
- 持久一致性：Domain restore 校验 action / batch / receipt / undo token / board / hash / command IDs 的一致性，并重新执行原 32 KiB inverse 上限；legacy restore 在解析 snapshot 前重新执行 128 KiB envelope 上限。畸形或超限历史行逐条 fail closed，不阻断其他 action。
- 冲突与幂等：Domain undo 冲突继续保留原 applied receipt，因而重启后仍可恢复重试；成功后移除可撤销 binding，重复点击不会投影第二次成功。成功撤销会请求当前已打开的同板画布 reload。
- 测试代码：补充真实文件 SQLite / Drift 关闭再开、新 coordinator、首次 hydration 后同步 `canUndo`、legacy/domain 两类路由、后续 snapshot hash 冲突、冲突后再次重启恢复、重复撤销，以及 malformed / oversized persisted record fail-closed；行动卡测试改用 Domain action addendum 覆盖通用 UI 回调。
- 当前未运行 Flutter / Dart 测试与 analyze：遵守本轮多个 worker 不并发占用 Flutter 工具链的约束。已运行 `git diff --check`，通过。
- W0 首次串行 Gate：coordinator / UI 已加载的 6 项用例通过，但 facade 测试文件在加载阶段失败；`isNull` 同时来自 Drift query builder 与 matcher，导致整包 Gate 失败，不能记为通过。
- 最小返修：重复 Undo 的空结果断言改为无歧义的 `equals(null)`，并修正 coordinator 新增测试中 `final finalCoordinator` 的多余缩进。SDK formatter 仅处理这两个 test 文件，实际报告 `Formatted 2 files`；随后因用户目录 Dart telemetry 文件无写权限返回 exit 1，无残留 Dart 进程，diff 仍只有上述两行。
- 主窗建议串行验证：`flutter test test/data/whiteboard/domain_commands/whiteboard_domain_command_facade_test.dart test/data/workbench_ai/whiteboard_workbench_coordinator_test.dart test/ui/desktop/workbench_action_card_test.dart`；随后对本提交 changed files 执行 analyze，并在唯一 Windows 候选上完成退出 / 重开后两类行动卡 Undo 真人 Gate。
- 范围与限制：未改 schema、依赖、Card / Board / DomainCommand wire identity、`desktop_persona_chat_view.dart`、P4-T3/T4、P5/P6、Goal/Roadmap/I_PROJECT_STATE/DEVLOG；本 worker 不宣称自动 Gate、构建或真人 Gate 已通过。

## 2026-08-24 历史交付证据

- 返修基线：`5ec47a94c418e25f704ec8cd062589f6e5ca33a1`；旧交付未沿用为验收结论。
- 契约判断：现有 `CardContract.body/tags` 与 `BoardItem.x/y/width/height`、稳定 ID、移除摆放不删 Card 的语义足够；未改 Card/Board 公共契约，未做 schema migration。
- 闭环：六类 provider-neutral `WhiteboardDomainCommand`（create card、edit body、set labels、move、resize、remove placement）统一进入 `WhiteboardDomainCommandFacade` / `WhiteboardDomainCommandExecutor`。
- 入口等价：直接用户入口 `executeUser` 与 Runtime 入口 `executeRuntime` 只在授权签发主体上不同；permission reserve/commit/release、Receipt、hash conflict、幂等、失败零残留和 Undo 共用同一执行路径。
- 生产桥接：`WhiteboardWorkbenchCoordinator` 通过同一个 lazy facade 暴露用户执行、Runtime 精确授权/执行与 Undo；调用方不能替换其中任一语义分支。
- 持久恢复：`WorkbenchActionProjection` 持久化 command batch、receipt 与 bounded undo receipt；`readPersistedWorkbenchActions` 从真实 Drift `persona_chat_messages` action 行读取，重建 DomainCommand/Receipt/Undo，不依赖本地 List。
- Undo 体积：新命令只保存受影响字段、单个 BoardItem 及必要 group/member/edge inverse；硬上限 32 KiB，超限在保存前以 `undo_payload_too_large` 拒绝。旧 group/connect `before_snapshot` 兼容路径新增 128 KiB 硬上限与保存前拒绝测试，避免无界复制。
- 范围排除：未新增建板、批量整理、group/connect/search 能力；既有 group/connect 兼容路径仅补持久 reader 与上限保护。
- 控制面：未改 `I_PROJECT_STATE.md`、`DEVLOG.md`、Roadmap 或 Goal；未 push。

## 自动验证

- `flutter test test/data/whiteboard/domain_commands/whiteboard_domain_command_facade_test.dart`：4/4 通过；覆盖六类正常执行、Runtime 拒绝零残留、保存失败零残留与诚实重试、幂等、expected-hash 冲突、32 KiB 拒绝、真实 SQLite 关闭重开后 command/receipt/undo 恢复及撤销。
- `flutter test test/data/whiteboard/ai_write_tools/whiteboard_ai_write_tool_host_test.dart`：12/12 通过；含旧整板 envelope 128 KiB 保存前拒绝。
- `flutter test test/data/workbench_ai/whiteboard_workbench_coordinator_test.dart`：3/3 通过；恢复用真实 Drift action reader。
- `flutter test test/domain/workbench_ai/permissions/whiteboard_permission_broker_test.dart test/domain/workbench_ai/action/workbench_action_projection_test.dart`：5/5 通过。
- changed-file `dart analyze`：通过，`No issues found!`。
- `git diff --check`：完成提交前复核。
- 环境记录：worktree 初始缺少 `.dart_tool/package_config.json`；offline 依赖解析已生成配置，但 Dart telemetry / Pub `active_roots` 写入用户目录被拒绝。改用 SDK 实际可执行文件后，分析与全部定向测试均正常完成。

## 待集成 / 人工 Gate

- W0 仍需在唯一 Windows 候选上走一次用户入口与 Runtime 入口的真人操作，并关闭、重开应用后执行 Undo；本 worker 不宣称真人 Gate 已通过。
- 无数据库迁移、依赖升级或共享 Card/Board 契约提案。
