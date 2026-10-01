# P6 R7 Native Adapter Integration Audit

> 2026-09-12：本文所列窄 adapter、HTTP 生命周期与 Bridge 正常退出路径已实现为候选，并通过本地模拟资源/HTTP 测试；生产没有注入 native factory，`workbench_text_only_v1` 仍 available=false/fail_closed=true。真实 App、原生故障注入与真人 Gate 尚未通过。当前交付见 [生命周期候选交接](P6_R7_RUNTIME_LIFECYCLE_HANDOFF.md)。

## 审计范围和结论

审计覆盖：

- `tools/dev_agent_bridge/codex_app_server_adapter.mjs`
- `tools/dev_agent_bridge/experimental_runtime_api.mjs`
- `tools/dev_agent_bridge/workbench_text_only_profile.mjs`
- `tools/dev_agent_bridge/workbench_text_task_session.mjs`
- `tools/dev_agent_bridge/workbench_text_stop_receipt.mjs`
- `lib/data/workbench_ai/workbench_runtime_client.dart`

不能把 native task session 接入现有 `CodexAppServerAdapter`：

1. `requireSupportedRuntimeProfile` 目前对 `workbench_text_only_v1` 无条件拒绝，正确保持 fail-closed。
2. 通用 adapter 持有普通 App Server client；它不拥有每次 text task 的 native supervisor、attached transport 和 local broker。
3. 通用 `closeSession` 的 authority 是普通 provider terminal。它不能替代 native owner 的实际 close、broker revoke/drain 和 P6 stop receipt。

应增加一个仅服务 text task 的窄 adapter，并让实验 API 在创建 session 时按精确 profile 分派。普通 runtime API 保持原 adapter 路径；不能因 text task 引入而扩大普通会话的权限、工具或 provider 配置。

## Dart 已有的 HTTP schema 契约

Dart `WorkbenchTextTaskRuntimeClient` 已严格校验以下 v2 schema。native adapter 应精确产生这些字段，避免改变 Dart 接口。

### 创建 session

`POST /experimental/v1/runtime/sessions` 的 request 必须带：

```json
{
  "config": { "runtime_profile": "workbench_text_only_v1" },
  "context_manifest": {
    "execution_epoch": "bounded non-empty string"
  }
}
```

成功 response 至少为：

```json
{
  "session_id": "bridge-local-session-id",
  "status": "idle",
  "provider_metadata": {
    "provider": "codex",
    "provider_session_id": "provider-thread-id"
  },
  "execution_profile_receipt": {
    "profile": "workbench_text_only_v1",
    "version": 2,
    "local_session_id": "bridge-local-session-id",
    "execution_epoch": "request execution_epoch",
    "provider_thread_id": "provider-thread-id",
    "isolation_verified": true,
    "tools_disabled": true
  }
}
```

该 receipt 只能在本次 owner 已启动、attached client 已启动、严格 config/requirements 校验通过、认证模式与本次 native executor 匹配、并且 thread binding 已建立后产生。它不得包含账户值、路径、原始错误或 native diagnostics。

### 开始 turn

`POST /experimental/v1/runtime/sessions/{session_id}/turns` request：

```json
{ "input": "task text" }
```

成功 response：

```json
{
  "local_session_id": "bridge-local-session-id",
  "provider_thread_id": "provider-thread-id",
  "execution_epoch": "same epoch",
  "local_turn_id": "bridge-local-turn-id",
  "provider_turn_id": "provider-turn-id"
}
```

响应直接映射 `WorkbenchTextTaskSession.startTurn()` 的已绑定结果。native write timeout 或 response 不完整时，turn start 为 unknown；不能以随后到达的 dispatch acknowledgement 把它改写为 no-turn success。

### 读取 events

`GET /experimental/v1/runtime/sessions/{session_id}/events?after=N` 必须只映射该 session 的有序本地 events：

```json
{
  "status": "ready | closing | failed",
  "events": [
    {
      "sequence": 1,
      "turn_id": "bridge-local-turn-id or null",
      "kind": "message_delta | turn_status | error",
      "data": { "text": "..." }
    }
  ],
  "next_sequence": 1
}
```

不转发原始 App Server notification、host request、账户对象、路径或错误文本。

### 关闭 session

`DELETE /experimental/v1/runtime/sessions/{session_id}` 只有收到 P6 ledger 的完整 receipt 才能返回成功：

```json
{
  "status": "closed",
  "stop_receipt": {
    "profile": "workbench_text_only_v1",
    "version": 2,
    "local_session_id": "bridge-local-session-id",
    "execution_epoch": "same epoch",
    "provider_thread_id": "provider-thread-id",
    "local_turn_id": "bridge-local-turn-id or null",
    "turn_id": "provider-turn-id or null",
    "outcome": "closed | closed_without_turn",
    "interrupt_dispatched": true,
    "interrupt_dispatch_sequence": 12,
    "provider_terminal_confirmed": true,
    "provider_terminal_status": "completed | failed | interrupted",
    "provider_terminal_sequence": 13,
    "cancellation_confirmed": false,
    "local_child_close_observed": true,
    "proxy_drained": true
  }
}
```

`closed_without_turn` requires no dispatched/unknown turn outcome. A turn close requires matching provider terminal; interrupt ACK alone is never cancellation proof.

## Native adapter lifecycle

`WorkbenchTextTaskRuntimeAdapter` owns one record per local session:

- native owner transport;
- attached `CodexAppServerClient`;
- one local `WorkbenchTextTaskBroker`;
- one `WorkbenchTextTaskSession`;
- immutable local session ID, execution epoch and provider thread ID;
- an idempotent close promise for that exact binding.

The creation sequence is:

1. Register the cleanup obligation synchronously, then start and listen on the broker.
2. Start the native owner in the dedicated authenticated mode, then await its startup frame.
3. Attach and start the App Server client through that owner.
4. Run strict `config/read` plus `configRequirements/read` verification.
5. Run `account/read` with token refresh disabled; only use the minimum account-type predicate needed for the authenticated boundary. Do not retain or return account data.
6. Start a fixed, ephemeral, read-only, no-tools thread using the startup-provided provider and working directory.
7. Construct `WorkbenchTextTaskSession` with a close callback that returns true only after the native owner supplies actual close evidence.
8. Publish the already-owned binding, then issue the execution-profile receipt.

A failure at any step after owner acquisition retains the ownership obligation. It must revoke the broker and retry/await the same owner close path; it must not replace the owner with a second process or issue a session receipt.

## HTTP disconnect ownership

`ExperimentalRuntimeApi.handle` now owns request cancellation through response finish/close. Only an explicitly injected host factory can create a native candidate adapter.

For session creation and turn start:

- use `req.aborted` and `res.close` only as cancellation signals when the response has not finished;
- specifically, normal `res.finish` / `res.writableFinished` ends cancellation ownership; `res.end` / `res.writableEnded` alone does not prove the response finished;
- if a session becomes available after the request was aborted, close that exact session through its idempotent native task close path;
- an abort may begin cleanup but cannot make an HTTP cancellation, a broker revoke, or an interrupt acknowledgement into a successful stop receipt;
- errors and aborts retain failed/unknown cleanup ownership for the same instance; a late creation is closed without publishing success. A request rejected before turn reservation must not close another active turn.

For an already-created session, client disconnect does not change its task state by itself. Only the request whose unfinished response owned a newly created or newly started attempt may trigger its scoped cleanup. This avoids treating an ordinary event-polling disconnect as a task cancellation.

## Bridge host stop and process exit

`ExperimentalRuntimeApi.stop()` now fences both ordinary and candidate starts and calls each native adapter's `closeAll()`, which:

1. prevents new native task starts;
2. invokes each registered `WorkbenchTextTaskSession.close()`;
3. revokes and drains each broker;
4. waits for each same-owner native close operation;
5. removes a record only after a valid receipt; records a failed/unknown result separately when receipt proof is absent.

The Bridge should expose one graceful shutdown path that first stops acceptance of new work, awaits `ExperimentalRuntimeApi.stop()` / native `closeAll()`, then closes the HTTP server. SIGINT and SIGTERM can invoke that path when the runtime permits asynchronous handling.

No code may claim a successful receipt just because the Bridge is exiting. SIGKILL, power loss, runtime crash, or an unawaitable forced exit cannot guarantee graceful cleanup. The native design's stdin EOF handling, supervisor lease/ownership checks and Job containment are the remaining containment mechanisms; their actual host-exit behavior requires a dedicated fault-injection acceptance run against the exact candidate.

## Implemented candidate scope

1. Add `tools/dev_agent_bridge/workbench_text_task_runtime_adapter.mjs`.
2. Add its deterministic test file.
3. Update `tools/dev_agent_bridge/experimental_runtime_api.mjs` and its tests for profile dispatch, per-session owner lookup and scoped request abort handling.
4. Update `tools/dev_agent_bridge/dev_agent_bridge.mjs` only to expose a testable graceful shutdown sequence.
5. Keep `tools/dev_agent_bridge/workbench_text_only_profile.mjs` fail-closed until separate candidate evidence is explicitly accepted.
6. Do not modify the ordinary `CodexAppServerAdapter` lifecycle to emulate native ownership.
7. Do not modify Dart if the above v2 schema is preserved. If schema changes become unavoidable, update `lib/data/workbench_ai/workbench_runtime_client.dart` and its focused test together.

## Required deterministic tests before any profile enablement

- A text profile session uses the dedicated adapter and never constructs the ordinary App Server transport.
- The adapter rejects resume, dynamic tools, steer, host requests, approvals and tool calls for text tasks.
- The exact session, turn and receipt schemas above are accepted by the existing Dart client fixture.
- A delayed session creation followed by HTTP request abort closes the created binding exactly once; a normal completed HTTP response does not close it.
- A delayed turn write/late dispatch acknowledgement never yields `closed_without_turn`.
- Native process error, invalid close proof, broker not drained, missing provider terminal, or unknown start prevents a stop receipt and leaves the task outcome unknown/failed as appropriate.
- Repeated DELETE and concurrent host shutdown share one native owner close operation; a failed close is retryable only against that same owned operation.
- Graceful Bridge shutdown awaits every currently owned session. A separate exact-candidate fault test covers host crash/forced termination and verifies the native stdin EOF, lease and Job behavior without describing that test as graceful shutdown proof.
