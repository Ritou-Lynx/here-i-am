# Dev Agent Bridge Protocol

Status: Draft for Phase 0/1

This document defines the app-facing protocol for Dev Room. The bridge may be a
MyPilot fork, a Codex-only shim, or a combined adapter, but the Flutter app
should depend on this stable shape rather than on one agent's raw stream.

## Decision

Start with one bridge contract and let the bridge normalize Claude Code and
Codex events.

- App stores projects, runs, events, and approvals locally.
- Bridge owns tokens, CLI processes, worktrees, GitHub access, and provider
  credentials.
- Phase 1 is read-only. `permission_tier` defaults to `read_only` and the app
  must not expose `danger-full-access`.
- Bridge URLs must be HTTPS or a Tailscale HTTPS endpoint. Plain HTTP is not
  accepted by the app.

## Current Local Prototype

`tools/dev_agent_bridge/dev_agent_bridge.mjs` implements the Phase 0/1 contract
as a project-local bridge:

- `codex` runs through `codex exec --json --sandbox read-only`.
- `claude_code` runs through `claude -p --output-format stream-json` with
  read-oriented tools.
- Runs, events, and artifacts are stored in a local state file by default.
- Active CLI processes cannot be resumed after a bridge restart; the prototype
  marks those runs as failed while preserving prior events.
- It exposes HTTP for local curl probes, but phone testing still needs HTTPS
  via Tailscale Serve or a trusted certificate.
- It does not create worktrees, write files, commit, push, or perform real
  approval-gated writes.

This is a stepping stone while the MyPilot fork path is repaired. The global
`mypilot` command on the current Windows machine points to a missing
`dist/backend/cli.js`, so MyPilot cannot yet satisfy Phase 0 endpoint probing.

## Endpoints

### Health

`GET /v1/health`

Response:

```json
{
  "ok": true,
  "bridge_id": "devbox-main",
  "version": "0.1.0",
  "agents": ["claude_code", "codex"]
}
```

### Start Run

`POST /v1/runs`

Request:

```json
{
  "client_run_id": "uuid-created-by-app",
  "project": {
    "id": "uuid",
    "name": "Here I am",
    "root_path": "D:\\claude-workspace\\memex",
    "default_branch": "personal-lab",
    "permission_tier": "read_only"
  },
  "agent_type": "codex",
  "prompt": "Read the project and summarize current risks.",
  "mode": "read_only"
}
```

Response:

```json
{
  "run_id": "bridge-run-id",
  "session_id": "provider-session-id",
  "status": "running"
}
```

### Poll Run

`GET /v1/runs/{bridge_run_id}`

Response:

```json
{
  "run_id": "bridge-run-id",
  "status": "running",
  "summary": null,
  "branch": null,
  "worktree_path": null
}
```

### Poll Events

`GET /v1/runs/{bridge_run_id}/events?after=42`

The bridge returns events with monotonically increasing bridge-side sequence
numbers. The app stores the normalized payload in `DevAgentEvents.payloadJson`.

```json
{
  "events": [
    {
      "seq": 43,
      "ts": 1782020000,
      "kind": "text",
      "payload": {
        "text": "I am reading the repository structure."
      }
    }
  ]
}
```

### Abort Run

`POST /v1/runs/{bridge_run_id}/abort`

Response:

```json
{ "ok": true, "status": "aborted" }
```

### Respond To Approval

`POST /v1/runs/{bridge_run_id}/approvals/{approval_id}`

Request:

```json
{
  "decision": "approved",
  "responded_at": 1782020300
}
```

Response:

```json
{ "ok": true, "status": "approved" }
```

The bridge must treat missing, denied, or expired approvals as rejected. The app
does not support batch approval.

### List Artifacts

`GET /v1/runs/{bridge_run_id}/artifacts`

Response:

```json
{
  "artifacts": [
    {
      "id": "diff-final",
      "kind": "diff",
      "title": "Final diff",
      "content": "diff --git ...",
      "created_at": 1782020400
    }
  ]
}
```

## Event Kinds

| Kind | Purpose |
|---|---|
| `text` | User-visible progress or final output chunk |
| `tool_call` | Agent is invoking a tool or command |
| `tool_result` | Tool or command completed |
| `file_change` | File path changed, created, or deleted |
| `test` | Verification command status |
| `approval_request` | Bridge is blocked waiting for user approval |
| `error` | Recoverable or terminal failure |
| `status` | Run status update |

## Artifacts

Artifacts are durable run outputs that are too large or too important to live
only in the event stream.

| Kind | Purpose |
|---|---|
| `diff` | Unified diff or summarized file diff |
| `test_log` | Verification output |
| `review` | Reviewer notes |
| `build` | APK, bundle, or build metadata |
| `link` | PR, CI run, or external page URL |

## Normalized Payloads

`text`:

```json
{ "text": "short progress text", "role": "assistant" }
```

`tool_call`:

```json
{
  "name": "Read",
  "description": "Read lib/db/app_database.dart",
  "risk": "low"
}
```

`tool_result`:

```json
{
  "name": "Read",
  "ok": true,
  "summary": "Read 260 lines"
}
```

`file_change`:

```json
{
  "path": "lib/db/dev_agent_tables.dart",
  "change": "created",
  "lines_added": 62,
  "lines_removed": 0
}
```

`approval_request`:

```json
{
  "approval_id": "uuid",
  "kind": "command",
  "title": "Run flutter analyze",
  "command": "flutter analyze",
  "reason": "Verify generated database changes",
  "risk": "medium"
}
```

`status`:

```json
{
  "status": "done",
  "summary": "Read the project and found the Dev Room entry points."
}
```

## Security Rules

- The app never stores Claude, OpenAI, GitHub, or shell credentials.
- The app rejects plain `http://` bridge URLs.
- Phase 1 sends `mode=read_only` even if a project row is edited manually.
- Every approval event is represented by a single `DevAgentApprovals` row.
- Dev Room process data must not be written to `CardCache`, PKM tables, or
  `SharedLifeEntities`. Phase 3 coding logs are the only exception.
