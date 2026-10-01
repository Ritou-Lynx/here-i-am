# P6-R5 停止证据最小修复交接

## 基线与拥有路径

- 工作包位于 `codex/whiteboard-w0-p6-r5-stop-receipts`，HEAD 为 `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`。
- 实际输入是主控覆入的 15 文件 overlay，并非纯 HEAD。比较应使用主控保存的 baseline；原有 AGENTS、协议、R4/profiles/API 输入不是本包改动。
- 本包只有 7 个拥有文件：`tools/dev_agent_bridge/codex_app_server_client.mjs`、`codex_app_server_client.test.mjs`、`codex_app_server_adapter.mjs`、`codex_app_server_adapter.test.mjs`、`workbench_stop_semantics_probe_contract.mjs`、私有 fixture `test_fixtures/stop_receipt_child.mjs`，以及本交接文件。
- 未提交、未改索引、未写主工作区、未运行真实 CLI/模型或既有 Bridge/App、未操作手机/真实队列、未构建 App；主控负责整合与全局状态。

## 行为及审计契约

1. client `stop()` 同步拒绝新工作，并共享并发停止 attempt。先等待 `stopTimeoutMs`，再尝试 kill，并最多额外等待 `killTimeoutMs`（默认与前者相同）。只有实际 child `close` 才 finalize、释放 child、发出 stopped。返回 `process_close_observed` 及 kill/退出证据。
2. 第二个等待窗口结束仍无 close：抛出 `CodexAppServerError(code=stop_close_unconfirmed)`，`data.process_close_observed=false`，状态 `stop_unconfirmed`，保留 child 及永久 close 观察能力。再次 stop 可重试清理；迟到 close 才转 stopped。kill false、抛错、error 事件均不冒充 close；每次 attempt 的监听器与定时器会清理。
3. adapter 只增加通用 `stop_evidence`，不签发 `stop_receipt`，也不添加 profile 字段。turn 级字段为 exact `provider_session_id` / `turn_id`、`interrupt_requested` / `interrupt_acknowledged`、`provider_terminal_confirmed` / `provider_terminal_status` / `provider_terminal_sequence`、`source`、`cancellation_confirmed`。
4. `interruptTurn()` 仍是 ACK 返回语义；重复/并发请求共享 ACK。`waitForTurnTerminal()` 是可选的独立等待入口。只有匹配 thread/turn、来自 `turn/completed` 且 status 为 completed/failed/interrupted 的通知可确认 provider 终态。`cancellation_confirmed` 还要求实际发出 interrupt 后收到 interrupted；failed/completed 不是取消确认。这里 provider 指 App Server 协议对端，不证明任意远端推理或工具子进程已停止。
5. unavailable close 将未终结 turn 本地记录为 unavailable，session close 仅表示本地 binding 已关闭。session `stop_evidence` 包含 `local_binding_closed`、所有 turns 的证据及非空全真汇总。空 turn 集合不会自动得到 provider confirmed。已关闭 binding 不接受迟到通知补签证据。
6. 关闭中的会话拒绝新的 start/steer；已在途 start 用占位 promise 保留，并有界等待。超时或启动结果未知时 close 抛错并保留 binding；迟到成功响应仍可跟踪并再次关闭。启动请求失败且无明确 turn id 时保持 unknown，不能把它当成空会话确认关闭。该保守状态仍可通过 adapter/client stop 清理运行时。
7. ACK-only、断线、错误/冲突终态、跨 thread/turn 均无目标假确认；已知终态后迟到 delta/重复 terminal 不再重写终态或追加运行正文。现有 text-only profile 仍在 start/resume 前拒绝，未改 Dart 专用 receipt gate。
8. 二审窄修：closing / closed / terminal 或失效 binding 不接收入站 approval / dynamic tool；直接 decline / fail，不发布可执行产品请求。公开答复入口在 provider send 前校验 current binding、close 状态及 turn 有效性，失效则报错；closing 但其余条件仍有效的回调保留给关闭清理发送 decline / failed，不能提前删除并丢失清理责任。closed / terminal 的残留无效回调仍删除且不发送成功。turn/completed 会清理该 turn 的 pending 回调，以 `turn_terminal` 记录本地清理而不补发 provider 结果。
9. 二审窄修：client interrupt 的可选 `onDispatched` 只在 `_write` 无抛错、请求交给 stdin 后触发，adapter 据此设置 `interrupt_requested`。这不是 provider 接收确认，后者仍需 ACK。同步不可写 / write 抛错不设置派发标记；已派发而 ACK 超时仍保留标记，因此可与后来匹配的 interrupted 终态分别审计。

## 验证

```powershell
& D:/Nodejs/node.exe --test tools/dev_agent_bridge/codex_app_server_client.test.mjs tools/dev_agent_bridge/codex_app_server_adapter.test.mjs tools/dev_agent_bridge/workbench_stop_semantics_probe_contract.mjs tools/dev_agent_bridge/experimental_runtime_api.test.mjs tools/dev_agent_bridge/workbench_text_only_profile.test.mjs tools/dev_agent_bridge/workbench_text_only_probe_contract.mjs
```

- 最终复核修复后的组合结果：64/64 通过（包含 1 个 probe contract 模块加载子测试），0 fail / cancelled / skipped。
- client、adapter、stop contract 专项覆盖 51 个测试；邻接 API/profile 及模块加载合计 13 个。
- 最后两条清理责任回归分别覆盖 approval / tool：close 同步建立后立刻尝试成功答复，入口拒绝但仍保留回调；fake provider 只有收到对应 decline / failed 才发 terminal。测试不从外部注入 terminal，实际验证 close pass 发出唯一负面答复并完成关闭。
- fake app-server 测试只启动测试自身的 Node fixture，新增异常/竞态 fixture 完全位于内存，不启动任何外部进程。`git diff --check` 通过。
- 关键代码入口：client `stop` / `_stopChild` / `_attachChild`；adapter `startTurn` / `_requestInterrupt` / `waitForTurnTerminal` / `_closeSession` / `_turnStopEvidence` / `_waitForTurnTerminal`。

最终回收冻结 SHA-256（相对首版需回收以下 3 个代码/测试文件及本交接）：

| 文件 | SHA-256 |
|---|---|
| codex_app_server_client.mjs | `CF125CEF1D55E8F7A592123261D46BA0A0DEBBC039A8058B9329B07D0E442F4F` |
| codex_app_server_adapter.mjs | `CBB3E7A6DBB2935E1B661FEF5F29B5925FD8133FF6DC6DD5F5DEC28AA0B562D9` |
| codex_app_server_adapter.test.mjs | `E67469D71EB05E1D68B228C950FB0E8F2DC80CD724C4BA49392224E807B46449` |

## 剩余边界

本包证明局部停止与回执契约，不证明进程树清理、远端提供商取消、生产工具隔离或真人 Gate。真实 CLI 合成 stop probe 和最终 overlay 复核由主控执行。生产 `workbench_text_only_v1` 继续禁止启用。
