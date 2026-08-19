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
