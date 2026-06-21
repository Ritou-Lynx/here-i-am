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

`tools/dev_agent_bridge/dev_agent_bridge.mjs` implements the Phase 0–2 contract
as a project-local bridge:

- `codex` runs through `codex exec --json` with sandbox `read-only` or
  `workspace-write` depending on run mode.
- `claude_code` runs through `claude -p --output-format stream-json` with the
  tool set and permission mode matched to the run mode (read-only → `plan` +
  Read/Grep/Glob/LS; write → `acceptEdits` + Read/Grep/Glob/LS/Edit/Write/MultiEdit).
- Workspace-write runs get an isolated `git worktree` at
  `{rootPath}/.dev-agent/worktrees/{shortRunId}` on branch
  `dev-agent/{shortRunId}` before the agent process starts. Read-only runs
  execute directly in the project root.
- When a write-mode run finishes cleanly the bridge auto-runs
  `git add -A && git commit` in the worktree (skipping if nothing changed),
  then stores a `diff` artifact comparing the dev branch to `default_branch`.
  Without the auto-commit, `apply` (which uses `git merge --ff-only`) would
  have no commit to merge.
- Decisions are real: `discard` runs `git worktree remove --force` + branch
  delete; `apply` runs `git checkout {default} && git merge --ff-only
  {devBranch}` then cleans up; `leave` keeps the worktree for later.
- Runs, events, and artifacts are persisted to a local `runs.json` state file.
  Bridge restart preserves history; in-flight CLI children cannot be resumed
  and those runs are marked failed.
- It exposes HTTP for local curl probes, but phone testing still needs HTTPS
  via Tailscale Serve, cloudflared tunnel, or a trusted certificate.
- Debug/dev app builds may use `https://127.0.0.1:<port>` with `adb reverse`
  and a self-signed localhost certificate for USB-only testing. This exception
  is limited to loopback hosts and does not allow plain HTTP.
- It does not yet do commit/push to remote, PR open, mid-run command
  approvals, or release_ops handling — those land in later phases.

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

### Decide Run

`POST /v1/runs/{bridge_run_id}/decision`

Sent after a run reaches a terminal status (`done` / `failed` / `aborted`) so
the user can tell the bridge what to do with whatever the run produced. The
app never executes git/shell — it only forwards the decision. The bridge owns
worktrees and is responsible for actually applying or discarding changes.

Request:

```json
{
  "decision": "leave",
  "responded_at": 1782020500
}
```

`decision` must be one of:

| Decision | Meaning |
|---|---|
| `leave` | Keep the worktree and artifacts around; the user will decide later |
| `discard` | Throw away the worktree and any uncommitted changes |
| `apply` | Merge the worktree branch back into the project's default branch |

Successful response:

```json
{ "ok": true, "status": "accepted", "decision": "leave" }
```

`discard` / `apply` require the run to have produced a worktree, i.e. it ran
in `workspace_write` mode. Read-only runs never have a worktree and the bridge
MUST reject those decisions with HTTP 422 + `reason: "no_worktree"`:

```json
{
  "ok": false,
  "status": "rejected",
  "reason": "no_worktree",
  "message": "Run has no worktree to discard. Only write-mode runs produce worktrees."
}
```

`apply` may also fail with `reason: "merge_not_fast_forward"` if the default
branch moved on while the dev branch was active, or with `reason:
"checkout_failed"` if the default branch checkout failed. In both cases the
worktree is left intact so the user can try again or fall back to `discard`.

If the run is still active, the bridge MUST respond with HTTP 409 and reason
`run_not_terminal`. Unknown decisions return HTTP 400 with `invalid_decision`.

The bridge appends a `decision` event to the run's event stream regardless of
outcome so the App's local event log stays in sync.

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
| `decision` | User's post-run decision (leave / discard / apply) and bridge's response |

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
