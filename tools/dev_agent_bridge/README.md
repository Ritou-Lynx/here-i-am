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

MyPilot is still the preferred long-term base for hooks, reconnects, and write
approvals, but the current global MyPilot install on this machine is broken
(`dist/backend/cli.js` is missing). This prototype lets the app and CLI event
normalization move forward without waiting for that reinstall/fork.

## Run Locally

```powershell
powershell -File tools\dev_agent_bridge\start_bridge.ps1
```

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

The Flutter app rejects plain HTTP Bridge URLs. For phone testing, expose this
local service over HTTPS.

For quick USB testing with the dev/debug app:

```powershell
powershell -File tools\dev_agent_bridge\start_usb_bridge.ps1
```

Then set the Dev Room Bridge URL on the phone to:

```text
https://127.0.0.1:47831
```

This script generates a local 30-day certificate, starts the bridge with HTTPS,
and configures `adb reverse tcp:47831 tcp:47831`. The app only accepts the
self-signed localhost certificate in debug builds and only for loopback hosts.

For normal daily use, prefer Tailscale Serve:

```powershell
powershell -File tools\dev_agent_bridge\start_bridge.ps1
tailscale serve --https=443 http://127.0.0.1:47831
```

Then use the Tailscale HTTPS URL in Dev Room, for example:

```text
https://host.example.invalid
```

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
