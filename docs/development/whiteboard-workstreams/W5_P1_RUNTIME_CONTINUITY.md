# W5-P1 — 桌面 Codex 普通对话与 Runtime 连续性

> 日期：2026-08-22；P1-R 韧性复核 2026-08-23
>
> 状态：P1-R 自动韧性闭环完成，待 W0 集成与真实 Windows / Codex 进程验收
>
> 分支：`codex/whiteboard-w5-runtime-continuity`

## 0. P1-R 韧性复核（2026-08-23）

P1-R 在既有普通对话纵切上补齐了此前只写在说明里的恢复边界：

- `WorkbenchConversationCoordinator` 不再把 provider 写死为 Codex；Runtime session 必须返回开放 provider key，resume 同时携带 provider 与 opaque provider session ID，provider 不一致时关闭新旧 local session 并 fail-closed。
- 新增 `WorkbenchRuntimeBindingStore` 与 `WorkbenchBindingDurability`。默认 `InMemoryWorkbenchRuntimeBindingStore` 明确只承诺 `processMemory`，关闭面板或重建 coordinator 可以恢复，应用进程退出后不能恢复；本轮没有新增 Drift 表或伪装持久化。
- store 只保存 `RuntimeSessionBinding`；local session ID、turn ID、事件 cursor 都仍是 transport 状态。重建 coordinator 后必须按 provider session resume 出新的 local session，closed binding 开新 provider session。
- 只有一条 `active` binding 而没有 turn projection / provider reconciliation 时返回 `runtime_recovery_requires_reconciliation`，并把 binding 降为 unavailable；不能把“有 thread ID”冒充“知道上个 turn 已结束”。
- stop 在 turn ID 尚未建立时保留 pending 请求，turn 建立后只发一次 interrupt；interrupt 失联返回 `runtime_stop_unconfirmed`，废弃并关闭 local session，不接受随后 completed 事件把 binding 重新标为可复用。
- turn 总超时现在同时约束单次挂死的 `readEvents`，不再只约束轮询次数；timeout、事件异常、resume 后 start 失败、provider mismatch、聊天终态或 binding store 写失败均走有界清理。
- binding store 在 session 建立或终态转移时失败会关闭无主 local session；最终回复已经可靠写入聊天但 continuity 写失败时，结果保留 completed 内容并标记 `runtime_continuity_degraded`，后续强制重新恢复。

### 跨应用持久化停点 / W0 精确变更请求

本轮只交付安全接口，没有创建 schema。要把 `applicationRestart` 变成真实承诺，W0 需要另行评审并完成：

1. 新增产品侧 runtime binding 持久表与 migration，以 `conversation_id` 唯一定位，保存严格 codec 的 `RuntimeSessionBinding` JSON / schema version / 更新时间；禁止保存 local session ID、active turn ID、原始 prompt、事件流、日志或凭据。
2. 提供注入式 Drift repository 实现 `WorkbenchRuntimeBindingStore`，事务写入 start / resume / 状态转移，并以 SQLite 重开测试证明 durability 后才返回 `applicationRestart`。
3. 若要恢复崩溃时的 active turn，必须同时持久化最小 `RuntimeTurnProjection` 并增加 provider reconciliation 能力；在这两者完成前，active binding 固定诚实降级，不自动启动新 turn。
4. 增加应用进程 A 写入 → 进程 B 读取 → provider resume → 新 local session 的集成 fixture，以及 corrupted / unsupported codec、provider mismatch、provider thread 已失效和 active-turn-conflict 回归。

现有 `DevAgentSessions.providerSessionId` 属于 Dev Room 多轮任务语义，不能挪作桌面 Persona conversation binding；复用它会混淆产品对话身份和任务房间身份。

## 1. 本轮闭环

桌面悬浮对话的普通文本不再回落手机 `CompanionAgent` 或手机模型配置。`PersonaChatScreen` 先把用户消息写入现有 `PersonaChatMessages`；明确“所选卡片分组并连线”仍交给 `WhiteboardWorkbenchCoordinator`，其余文本交给新的 provider-neutral `WorkbenchConversationCoordinator`。

普通对话经现有 loopback `WorkbenchRuntimeGateway` 创建 Codex App Server session / turn，消费 `message_delta` 并在界面显示流式文字；完成、停止或失败后都用 `PersonaChatService.addCharacterMessage` 写回同一角色聊天时间线。Runtime 不可用、实验入口关闭或未登录时只写诚实失败消息，绝不打开手机模型配置。

## 2. 连续性与停止

- coordinator 以产品 `conversation_id`（当前最小映射为 `persona:<character_id>`）持有进程内 binding；关闭和重开悬浮面板不会销毁它。
- 同一 conversation 的后续普通 turn 复用本地 runtime session；若 Bridge 已丢失本地 session，使用 opaque `provider_session_id` 调用 resume，并继续绑定同一产品 conversation。
- 产品 binding 与 Codex thread 身份分离；provider ID 不进入人格、普通消息或 Memory。
- 桌面回复期间发送按钮切换为停止按钮；停止在 turn 尚未拿到 ID 时也会记为 pending stop，turn 建立后立即 interrupt，最终写入“已停止”状态消息。
- 明确白板动作仍使用原有一次性、受限 action session，不共享普通对话工具权限。
- turn 建立后，只有 provider 已 `completed` / `interrupted` 且终态消息成功落库才继续复用本地 session；本地超时、事件读取异常、provider 失败或终态落库异常均 best-effort interrupt + close，并把 binding 标为 `unavailable`，下一轮必须按 provider thread resume。
- cleanup 的 interrupt / close 失败不会覆盖最初的 timeout / provider / persistence 错误，也不会把可能仍活动的 local session 重新标为可复用。
- 普通 conversation API 移除了未落入任何审计结构的 `userMessageId` 参数；用户消息身份仍由先行落库的 `PersonaChatMessages` 持有，后续正式 `RuntimeTurn` 持久化需由 W0 评审 schema。
- 桌面图片输入本轮明确不支持：发送会 fail-closed，显示提示并保留文字草稿与所选图片，不会静默丢附件或降级到手机模型。

## 3. 修改范围

- 新增 `lib/data/workbench_ai/workbench_conversation_coordinator.dart`
- 扩展 `lib/data/workbench_ai/workbench_runtime_client.dart`：可选空工具 session、provider session resume、turn interrupt
- 最小接线 `lib/ui/character/widgets/persona_chat_screen.dart`
- 桌面输入 `lib/ui/desktop/widgets/desktop_persona_chat_view.dart` 增加运行中停止态
- 新增 fake Runtime 测试并补桌面停止按钮测试

未修改白板 UI、Card / Source / Board schema、Drift migration、Memory V3、TaskRoom、手机设置页、生成能力或 Bridge JavaScript。

## 4. 验证

- P1-R coordinator + Runtime binding contract：33 / 33 通过；与原白板 coordinator + 桌面 overlay 联合回归：27 / 27 通过。
- 新增覆盖：provider-neutral binding、coordinator 重建只 resume provider、不恢复 local session、closed / active stored binding 分流、pending stop 去重、stop 失联、单次 readEvents 挂死总超时、provider mismatch、resume 后 start 冲突、store 初始 / 终态写失败、unavailable → fresh idle 恢复。
- 7 个改动 Dart 文件精确 analyze：`No issues found`；`git diff --check` 通过。
- 本轮没有调用真实模型、停止真实 Bridge 或启动真实 Windows App；这些进程事实留给 W0 合入后的串行真人验收。

## 5. 恢复与限制

- 删除 P1 coordinator 接线即可恢复旧行为；无 schema 或数据迁移需要回滚。
- 默认 binding store 只在 Flutter 进程内，durability 明确为 `processMemory`。它能跨面板关闭 / 重开，并能在应用仍存活时恢复 Bridge / App Server session；应用完全退出后不会恢复 binding，这是明确 open loop，不能因 codec 可序列化就声称已经持久化。
- terminal 回复目前完成后一次写库；流式 delta 只用于当前界面，不逐 token 持久化。面板关闭期间 turn 继续，完成后最终文本仍会落库。
- 暂未实现重试按钮、跨应用重启 turn 恢复、Context Envelope / Memory V3 注入、图片消息、工具搜索或长期任务。
- 若最终回复的数据库写入本身失败，coordinator 会返回 `chat_persistence_failed` 并清理 Runtime，但当前最小 UI 没有第二条可靠存储通道；W0 真人验收时应决定是否增加非持久 toast / 状态投影。
- Runtime 实验入口仍需按现有 W5 方式开启并保持 Bridge 可用；P1 不新增手机配置入口或静默修改 Codex 全局配置。

## 6. 集成建议

W0 合入时先处理 `persona_chat_screen.dart` 与 Wave3 / 手机 UI 的文本冲突，只保留 `_sendDesktopMessage` 的平台专用分流，不把普通手机聊天改到 Codex。随后在真实 Windows 窗口验收：普通两轮对话、关闭 / 重开面板后第三轮连续、停止、Bridge 重启后恢复，以及原“按主题分组并连线”动作仍完整可撤销。
