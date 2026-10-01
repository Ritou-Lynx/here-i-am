# P6-R4 Stop Semantics Handoff

## Scope and boundary

Baseline: `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`. This work package added only synthetic probe/audit files. It did not modify production adapter/client behavior, start the existing Bridge/App, read auth, call a real model, or enable `workbench_text_only_v1`.

The probe pins the supplied CLI SHA-256 before starting, then uses a new temporary `CODEX_HOME` and empty cwd, an allowlisted child environment, no MCP/hooks/project instruction budget/tool discovery configuration, `config/read` + `configRequirements/read` refusal checks, and a loopback-only Responses provider with `requires_openai_auth=false`. It rejects a non-empty user layer and mismatched effective `model_provider`, `base_url`, or auth requirement. All responses are fixed synthetic SSE.

## Actual CLI evidence

Command:

```powershell
& D:/Nodejs/node.exe tools/dev_agent_bridge/workbench_stop_semantics_probe.mjs 'C:/Users/ExampleUser/AppData/Local/OpenAI/Codex/bin/8e5b6932251c2c1c/codex.exe'
```

CLI SHA-256 was verified as `e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75`. The final report was written outside the repository at `C:\Users\ExampleUser\AppData\Local\Temp\hereiam-stop-semantics-ibijBy\report.json`; it contains only synthetic IDs/text and temporary paths. Its `probe_passed: true` is written to JSON before the report is printed or the process exits. It records effective `model_provider=synthetic_stop_probe`, loopback `base_url`, `requires_openai_auth=false`, and empty user/system layer config keys.

| Scenario | Observed terminal evidence | What it proves / does not prove |
|---|---|---|
| long SSE then `turn/interrupt` | one matching text delta was observed before interrupt; interrupt ACK returned at `1788764356303`, notification sequence 12; matching same-turn `turn/completed: interrupted` followed at sequence 14 / `1788764356304`; no later text notifications | ACK is acceptance, while the matching terminal notification is the completion receipt. This run observed both in order. |
| interrupted provider stream | response/socket close at `1788764356366`, after terminal; provider did not send `response.completed`; no terminal-late text delta | App Server released the synthetic stream after terminal in this run. HTTP close alone is still not proof that an arbitrary remote provider has cancelled work. |
| normal synthetic completion | matching `turn/completed: completed` at sequence 30 | Normal completion is distinct from cancellation. |
| synthetic stream disconnect without terminal SSE | matching `turn/completed: failed` at sequence 44 | A lost stream is an observed failure, not `interrupted`, and has no provider-terminal confirmation. |
| clean probe process shutdown | actual child `close` was observed at `1788764356751`, equal to stop return in this run | This only covers this clean process stop; it does not change timeout behavior below. |

`workbench_stop_semantics_probe.mjs` intentionally exits nonzero if any phase has an error, if no matching text delta was seen before interrupt, or if the three expected terminal states (`interrupted`, `completed`, `failed`) are not all observed. It does not treat process termination, ACK, socket close, or synthetic request teardown as substitutes for a matching terminal turn event.

## Current adapter/client semantic audit

1. `CodexAppServerAdapter.interruptTurn()` currently returns immediately after the provider interrupt ACK. Consumers needing a terminal receipt must wait for the matching `turn/completed`; the adapter does not include a terminal-confirmed stop receipt.
2. `CodexAppServerAdapter.closeSession()` does wait for a matching terminal event when `client.isReady`. But its `!isReady` branch locally records `INTERRUPTED` with `reason: runtime_unavailable_during_close`; that is a local fail-closed state, not a provider terminal confirmation.
3. `CodexAppServerClient.stop()` registers `child.once('close')`, but its timeout calls `child.kill()` and immediately resolves `stop()` without waiting for `close`. The new fake-child contract test verifies this exact distinction: stop resolution is not proof that a process close was observed.
4. The existing adapter close test covers the ready-client happy path with the repository fake app-server. It does not establish a real provider terminal receipt for the unavailable branch or for client-stop timeout.

Minimal future contract suggestion only: do not emit `provider_terminal_confirmed: true` unless a matching `(providerSessionId, turnId)` `turn/completed` terminal event was observed after the interrupt request. Return a distinct unconfirmed/failed close result for ACK-only, socket-loss, unavailable-client, or process-kill cases. No production change was made here.

## Verification

```powershell
& D:/Nodejs/node.exe --test tools/dev_agent_bridge/codex_app_server_client.test.mjs tools/dev_agent_bridge/codex_app_server_adapter.test.mjs tools/dev_agent_bridge/workbench_stop_semantics_probe_contract.mjs
```

Result: 21/21 passing. The dedicated contract uses a bounded keepalive so the client's intentionally unref'ed timeout is actually exercised. The actual CLI probe exited 0 only after its explicit three-phase terminal checks passed. No Flutter build, device/App action, deployment, commit, or push occurred.

Official semantic reference: [Codex App Server](https://learn.chatgpt.com/docs/app-server) specifies `turn/interrupt` returns `{}` and successful cancellation ends with `turn/completed` whose status is `interrupted`; `turn/completed` is the terminal turn notification.
