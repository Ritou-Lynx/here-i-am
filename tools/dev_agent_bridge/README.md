# Dev Agent Bridge Prototype

Local bridge for the Here I am Dev Room.

It implements the app-facing protocol in
`docs/companion-first/DEV_AGENT_BRIDGE_PROTOCOL.md` and runs Claude Code or
Codex on the development machine. The phone remains a controller only.

## Status

- Phase: 0/1 prototype
- Mode: read-only only
- Storage: local state file at `tools/dev_agent_bridge/.state/runs.json`
- Agents:
  - `codex` via `codex exec --json --sandbox read-only`
  - `claude_code` via `claude -p --output-format stream-json`

### Codex App Server Phase A

The Bridge now contains an isolated App Server adapter and probe without yet
changing the Flutter protocol or replacing `codex exec` runs:

- `codex_app_server_client.mjs` manages the local process, JSON-RPC handshake,
  account source, thread lifecycle, turns, streamed notifications, approvals,
  steer / interrupt, and graceful shutdown.
- `codex_app_server_client.test.mjs` runs against a deterministic local fixture.
- `codex_app_server_probe.mjs` performs the real Windows ChatGPT-authenticated
  start → turn → process restart → thread resume → second turn → thread read
  acceptance path. It never writes to the repository through Codex.

Run the deterministic tests:

```powershell
node --test tools\dev_agent_bridge\codex_app_server_client.test.mjs
```

Run the real local probe (creates a named Codex thread for native-client
visibility verification):

```powershell
node tools\dev_agent_bridge\codex_app_server_probe.mjs --cwd D:\here-i-am --model gpt-5.5 --exercise-control --exercise-approval
```

Add `--archive` only after native-client visibility has been checked. The
generated report is written under ignored `build/` and excludes account email,
prompts, responses, credentials, and raw reasoning.

`--exercise-control` waits for the first generated-message event before
steering, then interrupts the same turn. A successful `turn/start` response by
itself does not prove that the turn is already steerable. `--exercise-approval`
uses an ephemeral read-only thread, declines the real command approval request,
and verifies that the probe file was not created.

The explicit model is intentional for the probe: it must be one of the IDs
returned by the installed App Server's `model/list`. If the computer's config
points at a model that requires a newer CLI, the report records that failure
instead of silently changing the user's global Codex configuration.

### Experimental RuntimeAdapter API

W5-R1 adds a provider-neutral JavaScript contract in `runtime_adapter.mjs`, a
Codex implementation in `codex_app_server_adapter.mjs`, and a loopback-only
experimental Bridge API. The existing `POST /v1/runs` Codex path remains
`codex exec --json`; enabling this API does not replace or change it.

The API is disabled by default. Enable it only for local integration work:

```powershell
$env:DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER="1"
$env:DEV_AGENT_EXPERIMENTAL_CODEX_MODEL="gpt-5.5"
powershell -File tools\dev_agent_bridge\start_bridge.ps1
```

The adapter starts App Server, reads `model/list`, and rejects an unavailable
requested model before creating or resuming a thread. It never edits the
global Codex configuration. `DEV_AGENT_EXPERIMENTAL_CODEX_MODEL` is optional;
when set, it must match an ID returned by the installed App Server.

All routes carry the `/experimental/v1/runtime` prefix and return the
`x-hereiam-experimental: runtime-adapter-v1` header:

```text
GET    /experimental/v1/runtime/auth
GET    /experimental/v1/runtime/capabilities
POST   /experimental/v1/runtime/sessions
POST   /experimental/v1/runtime/sessions/resume
POST   /experimental/v1/runtime/sessions/{session_id}/turns
GET    /experimental/v1/runtime/sessions/{session_id}/events?after={sequence}
POST   /experimental/v1/runtime/sessions/{session_id}/turns/{turn_id}/steer
POST   /experimental/v1/runtime/sessions/{session_id}/turns/{turn_id}/interrupt
POST   /experimental/v1/runtime/approvals/{request_id}
POST   /experimental/v1/runtime/tool-calls/{tool_call_id}
DELETE /experimental/v1/runtime/sessions/{session_id}
POST   /experimental/v1/runtime/host/stop-app-server
```

Session start accepts `{ "config": {...}, "context_manifest": {...} }`.
Turn start and steer accept `{ "input": "..." }`; approval answers accept
`{ "decision": "approved" }` or `{ "decision": "denied" }`. Event reads
return stable, cursor-addressable RuntimeAdapter events. Steering waits for an
item activity notification that proves the turn is active, closing the Phase A
race where `turn/start` had returned but `turn/steer` was still too early.
Experimental JSON request bodies are capped at 256 KiB; malformed or oversized
bodies and invalid steering timeouts return `invalid_request` / HTTP 400.

Session `config.dynamic_tools` contains provider-neutral `{ name,
description, input_schema }` definitions. Codex dynamic-tool requests are
projected as cursor-addressable `tool_call` events; the product host answers
the route above with `{ "success": true|false, "content_items": [{ "type":
"text", "text": "..." }] }`. The adapter validates definitions and bounded
text results, rejects duplicate or unknown call IDs, and never executes Here I
am domain tools inside the Bridge process.

`DELETE .../sessions/{session_id}` is fail-closed: pending approvals are
declined and removed first, then active turns are interrupted and observed at a
terminal state before the local binding closes. Closed-session event history
remains readable for audit. It is not a detach operation.

`host/stop-app-server` is a loopback-only lifecycle endpoint used by
`stop_bridge.ps1`. It waits for the App Server client to close stdin and for the
child process to exit before the script force-stops the Bridge parent. If the
endpoint is unavailable (for example a custom HTTPS binding), the script
recursively stops Bridge child processes before stopping the parent.

Run all deterministic Bridge tests without contacting a real model:

```powershell
node --test --test-concurrency=1 tools\dev_agent_bridge\codex_app_server_client.test.mjs tools\dev_agent_bridge\codex_app_server_adapter.test.mjs tools\dev_agent_bridge\experimental_runtime_api.test.mjs tools\dev_agent_bridge\codex_run_options.test.mjs tools\dev_agent_bridge\project_memory_closeout.test.mjs
```

### Codex controls

`POST /v1/runs` accepts an optional `codex_options` object for Codex runs:

```json
{
  "model": "gpt-5.6-terra",
  "reasoning_effort": "medium",
  "service_tier": "fast",
  "verbosity": "medium"
}
```

Each omitted value inherits the development computer's Codex configuration.
The legacy top-level `model` field and `DEV_AGENT_CODEX_MODEL` remain supported
for older App/Bridge combinations.

MyPilot is still the preferred long-term base for hooks, reconnects, and write
approvals, but the current global MyPilot install on this machine is broken
(`dist/backend/cli.js` is missing). This prototype lets the app and CLI event
normalization move forward without waiting for that reinstall/fork.

## Run Locally

```powershell
powershell -File tools\dev_agent_bridge\start_bridge.ps1
```

## Project Memory projection

`GET /v1/project-memory/projections?after=<ISO-8601>&limit=100` 从本机加密 i Gateway ledger 生成 Memory V3-safe 投影。只导出 Registry 中 `memory_v3=project_summary/redacted_summary` 的项目；`confidential_local`、`ephemeral`、`local_only` 和 `private` 不会返回。工作项目只返回脱敏通用摘要，不返回 decisions、open loops 或 artifact refs。

该端点沿用 Dev Room 的 Tailscale HTTPS / debug loopback 信任边界；不返回原始 ledger、diff、transcript 或凭据。

成功的 Dev Room run 会自动刷新项目 closeout：若 Codex / Claude Code 已通过 `i_close_session` 成功写入，Bridge 不重复；否则 Bridge 以不超过 2,000 字的最终摘要兜底。失败、中止、未注册或项目政策拒绝的 run 不写入。已注册的非 Git 文档项目也支持 Codex 只读 run。

Stop a background bridge left from local testing:

```powershell
powershell -File tools\dev_agent_bridge\stop_bridge.ps1
```

The stop script does not assume that force-stopping the Node parent will make
App Server exit. It first requests the explicit local cleanup path described
above, then performs descendant-process cleanup as a fallback.

Default URL:

```text
http://127.0.0.1:47831
```

Local health check:

```powershell
Invoke-RestMethod http://127.0.0.1:47831/v1/health
```

If local curl tests go through a proxy, bypass it:

```powershell
curl.exe --noproxy "*" -k https://127.0.0.1:47831/v1/health
```

The default state file is ignored by git. Override it when needed:

```powershell
$env:DEV_AGENT_BRIDGE_STATE="D:\path\dev-agent-runs.json"
powershell -File tools\dev_agent_bridge\start_bridge.ps1
```

## Phone Testing

For normal daily use, prefer Tailscale Serve:

```powershell
powershell -File tools\dev_agent_bridge\start_bridge.ps1
tailscale serve --https=443 http://127.0.0.1:47831
```

Then use the Tailscale HTTPS URL in Dev Room, for example:

```text
https://host.example.invalid
```

For quick USB fallback testing with the debug app, the Dev Room Bridge URL can
use the local HTTP bridge through adb reverse:

```powershell
powershell -File tools\dev_agent_bridge\start_bridge.ps1
adb reverse tcp:47831 tcp:47831
```

Then set the Dev Room Bridge URL on the phone to:

```text
http://127.0.0.1:47831
```

For HTTPS USB fallback testing with a local self-signed certificate:

```powershell
powershell -File tools\dev_agent_bridge\start_usb_bridge.ps1
```

Set the Dev Room Bridge URL on the phone to:

```text
https://127.0.0.1:47831
```

This script generates a local 30-day certificate, starts the bridge with HTTPS,
and configures `adb reverse tcp:47831 tcp:47831`. The app only accepts
loopback HTTP or self-signed localhost HTTPS in debug builds.

If you already have a trusted certificate and key:

```powershell
$env:DEV_AGENT_BRIDGE_HOST="0.0.0.0"
$env:DEV_AGENT_BRIDGE_PORT="443"
$env:DEV_AGENT_BRIDGE_CERT="D:\path\cert.pem"
$env:DEV_AGENT_BRIDGE_KEY="D:\path\key.pem"
node tools\dev_agent_bridge\dev_agent_bridge.mjs
```

## Start Run Probe

```powershell
powershell -File tools\dev_agent_bridge\probe_bridge.ps1
```

## Known Local Issues

- `mypilot` is installed as a command shim but its package contents are missing.
- `codex exec` currently fails on this machine with the configured default model
  requiring a newer CLI; setting `DEV_AGENT_CODEX_MODEL` may help after the
  account/model config is corrected.
- If the bridge restarts while a run is active, the CLI process cannot be
  resumed. The bridge marks that run as `failed` and keeps its prior events.
- The prototype intentionally does not create worktrees, write files, commit, or
  push. Those belong to Phase 2 after approval hooks are reliable.
