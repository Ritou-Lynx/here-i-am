# P6 R7 native runtime adapter candidate

2026-09-12; workspace baseline `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5` plus existing P6 changes. This worker owns only the two new runtime adapter files and this handoff. No staging, commit, production profile change, native execution, UAC, network request, model turn, or App build occurred.

## Candidate interface

`WorkbenchTextTaskRuntimeAdapter` extends `RuntimeAdapter`. Construction requires explicit trusted host `nativeOptions: { executable, sha256 }`, or complete synchronous `factories: { createBroker, createOwner, createClient }` for injected resources. Factories return ownership synchronously; `broker.listen`, `owner.ready`, and `client.start` perform their asynchronous work. A throwing acquisition remains an unknown obligation. Importing this module creates no resources, and default production APIs do not instantiate it.

Methods: `startSession(config, contextManifest, {signal}?)`, `startTurn(id, input, params={})`, `readEvents(id, {afterSequence}?)`, `interruptTurn(id, localTurnId)`, `closeSession(id)`, `closeAll()`, and `stop()`. Resume, steer, approval, and tool responses retain the base adapter's unsupported errors. `closeAll` permanently blocks new work on this instance; a host may explicitly create a new instance afterward.

HTTP config accepts exactly `runtime_profile: workbench_text_only_v1`. Context requires an opaque bounded `execution_epoch` and optionally accepts bounded `task_id` and exact `execution_mode: isolated_text_only`; only the epoch survives into local binding. No HTTP executable, hash, home, model, provider, environment, tools, or config overrides are accepted. Input is one nonempty valid UTF-8 string up to 32 KiB; turn params must be empty.

## Creation and evidence

The adapter registers an ownership record before acquiring resources. It follows broker → pinned native owner in `chatgpt` mode → attached client → strict config and requirements verification → cached `account/read` with `refreshToken:false` and type-only acceptance → fixed ephemeral thread → existing `WorkbenchTextTaskSession`. Config verification includes `features.respect_system_proxy=false`; the native v6 environment/CLI contract remains in its existing owner. Account values are neither returned nor stored in the adapter record. Ordinary authorized input is supplied only at `startTurn`; session creation never arms the broker or emits a model turn.

The Dart v2 execution receipt is issued only after native mode, attempt, identity, CLI hash, singleton Job, network evidence, effective configuration, account type, and returned fixed thread fields are checked. The public response contains only local binding/provider thread metadata. Turn responses use the five exact Dart binding fields. Event output preserves `event.status` at the top level and exposes bounded task text or fixed error codes, never raw host request/error payloads.

## Closure and failure

Creation cancellation revokes the broker and immediately asks the already-held owner to close, even while `ready` or an RPC remains pending. Creation must settle before its remaining resources are released; an abort signal is removed after creation ends. A fault during creation leaves the creation failure path responsible for cleanup, avoiding a second cleanup that waits on unfinished creation. A fault after publication schedules best-effort cleanup of the same record, including broker listener closure; it remains unknown and cannot issue a stop receipt.

`WorkbenchTextTaskSession` accepts an optional internal `onFault(code)` observer. The default remains absent for independent callers, and observer failure cannot alter session events or receipt facts. The candidate adapter subscribes only for its own record, so notification-originated faults such as malformed terminal status, output limits, or text after terminal take the same asynchronous published-record cleanup path as transport faults. This avoids polling or copying events and does not wait recursively during creation.

After input and fresh-session validation have passed, a `turn/start` failure automatically attempts cleanup of that same reserved record before returning its fixed unknown-start error. This covers a dispatched write whose response is lost. Validation or stale-state rejection happens before reservation and does not close a legitimate active session. Cleanup failure stays attached to the same owner for close/retry and never replaces an unknown start with success.

The adapter records `turnReserved` synchronously before entering `WorkbenchTextTaskSession.startTurn`. A concurrent or later repeat receives fixed `turn_not_active`/HTTP 409 before task-session dispatch and cannot close, interrupt, or revoke the first turn. The first reserved call keeps its unknown-start cleanup obligation if its own request fails.

Native closure is accepted only with all six native closure facts true, `cleanup_pending:false`, and the owner's `cleanupPending:false`. Both the real task ledger and broker drain must then support the branded bound stop receipt. Interrupt acknowledgement never substitutes for terminal evidence. Failed or unknown turn start cannot become a successful no-turn receipt after local cleanup.

Failed native/resource close keeps the same owner and retry obligation. Concurrent closes share in-flight work. Successful close retains a frozen tombstone for idempotent retries; unknown closure never deletes the record. Fully cleaned failed creation may be removed without issuing any stop receipt. `closeAll` reports resource shutdown only after every owned record resolves; no unknown obligation becomes success. Raw exceptions, paths, account values, and error causes are masked as fixed `RuntimeAdapterError` responses.

## Verification and limits

Pure injected-resource tests pass **19/19**. Combined adapter, task-session, and stop-ledger tests pass **46/46**:

`node --test --test-concurrency=1 tools/dev_agent_bridge/workbench_text_task_runtime_adapter.test.mjs tools/dev_agent_bridge/workbench_text_task_session.test.mjs tools/dev_agent_bridge/workbench_text_stop_receipt.test.mjs`

Coverage includes exact Dart schemas, no model at creation, override rejection, config/mode/thread mismatch, resource failure, unknown acquisition, abort before/during startup, concurrent shutdown, closure retry/tombstones, concurrent/repeated turn fencing without side effects, no-DELETE cleanup for unknown turn start and published host/process/protocol/notification faults, terminal-vs-ACK distinction, fixed host request rejection, and error sanitization.

Candidate hashes:

- adapter source: `018C39B1371A6B4F22A8E9D63C182E68CBB6A24BB8B63478B5A399A9DBD478C7`
- adapter tests: `ECA031EDAD4FF5E43B1795E2F1A8116ACE47E20549E2365BC1CC98E784A306E5`
- TaskSession source: `3985DA101481CF7A4C87929C10ECEC8504F257F3EB30E7CCA078995834D54D96`
- TaskSession tests: `40D2B4CDD25CFCC6F6FAA393EA5DEADA6F7AE47F8E2CD35FD9AE39F35B793806`

This is a candidate integration with fake verification, not new actual native/App/provider evidence. Production availability remains unchanged. Root owns HTTP request dispatch/abandonment, session-owner mapping, Bridge shutdown/launcher environment, independent review, and any actual acceptance. The adapter retains up to 64 records including closed tombstones, then refuses more creation; the host can drain and explicitly replace the instance. Trusted injected factories must honor synchronous ownership acquisition and bounded asynchronous completion. Unknown factory acquisition intentionally prevents successful shutdown because ownership cannot be proven absent.

## 2026-09-12 ordered task cleanup correction

Root's final HTTP `turn-disconnect01` attempt `b47fb1a9` observed the exact API abort/one close and one pending exchange, but the adapter revoked the broker before TaskSession could complete its interrupt RPC. The provider terminal was failed, not a verified cancellation. Native exit0/all six closure facts/drain were separate local cleanup evidence; they did not repair the failed scenario.

The adapter's only behavior change is in `#cleanup`: when `record.task` exists, let its existing `close()` own interrupt dispatch/ACK, broker revoke, bounded matching-terminal wait and native cleanup. Only the resource-only path without a TaskSession directly revokes here. `#cancel`/`#fault` still revoke immediately, and the explicit native/broker fallback is unchanged. TaskSession, broker, ledger, HTTP API, acceptance checks and production factories were not changed.

Verification: **48/48** adapter + TaskSession + stop-ledger tests pass. The new deterministic provider fixture emits failed if revoke occurs before interrupt ACK. Correct close is checked while ACK remains pending (no revoke or native close), then records a matching interrupted terminal and later revoke/native closure with exact binding, ordered sequence and cancellation true. An explicitly premature revoke still yields failed/cancellation false. A startup failure with no task proves immediate revoke before native fallback; existing fault tests now assert synchronous revocation.

Final source SHA-256: `6B4DF3357077E0080972623B0FED3D4C309183284468D4BBB73ED2187661654C`.
Final test SHA-256: `B45910A3E6F21AF05B712A6DD3C59AAFDA34D1FA5F7DC3DA712A2D0719A67374`.

Code is paused for root review and freeze. No actual native/UAC/provider request was executed by this worker. This adapter change creates a new composition: prior 26/31-input HTTP and host-fault evidence stays historical, and root must freeze and rerun completed/interrupt/disconnect/host-fault against the new inputs before adopting current-candidate results. Production remains unavailable.