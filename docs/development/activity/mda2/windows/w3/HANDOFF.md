# MDA-2 W3 Windows collector/queue handoff

## Identity and commits

- Task: `01a09699-5a54-7fb0-8b05-f69972c3b118`
- Branch: `codex/mda2-w3-windows-wiring-20260913`
- Exact baseline: `68307c9ea837f11dc82e148e8f51feff89b50fb6`
- Frozen-W2 seed: `0c4dbd37113537ab8915c4b249ca2583525c38c4`
- Seed provenance correction: `b4efcfd6bcc1339a5e194b719a997d9987aac8e5`
- Prior delivery rejected by W0 lifecycle review: `7bdf72b7622a8d5418b42d4ac45a01a7af4924e2`
- Repair delivery commit: recorded by the final task response after this document is committed.

Task commits use the master-authorized one-command `SKIP_PROJECT_STATE=1` exception. The variable is not persisted. No push or main-checkout integration was performed.

## Delivered candidate

The candidate adds a disabled-by-default Windows collector boundary and wires two caller-authorized sources to the frozen W2 protected disk queues and a bounded asynchronous transport. WTS is limited to lock/unlock for the current session. Last-input is coarse idle only. Power, overflow and restart are quality gaps and never interaction evidence. The native frame cannot carry window/app/key/screen/body/account content.

Native capture time is sampled inside the private native boundary and accepted only with the broker-issued nonce, epoch, session and source. The candidate keeps capture, IPC arrival, durable enqueue and dispatch coordinates distinct. Each source has its own binding, queue, sequence and allocation chain; one held source cannot block the other.

The W2 queue delta is limited to four runtime files plus one fixture declaration and archived exactly in `W2_TO_W3_QUEUE.patch`: authority validates before any channel move and binds raw bytes/attempt/owner/fence; broker transport is detached from broker serialization with pending/backoff/deadline bounds and late-result fencing; queue releases only failed in-memory in-flight work; worker exposes that release command; `fixtures/broker_host.mjs` marks its existing immediate transport as a synchronous fixture. The other four W2 execution sources are byte-identical to the frozen source. Current baseline Core is unchanged.

The only HTTP implementation is a test-authority, two-phase bounded adapter. Its side-effect-free `prepare` returns the complete lifecycle handle before the broker authorizes bytes, records the dispatch and calls `start`. Bare Promises, unregistered functions and malformed handles are rejected before transport start. Completion cannot settle a queue or free concurrency until independent `exited` resolves with exact `{closed:true}`; rejection or malformed exit remains unknown and makes stop/close fail. If a real request exists when start throws, it is destroyed and only its real `close` event can prove exit. The adapter still accepts only literal loopback and a test-created random port, rejects redirects and active port 47841, and bounds reply size and total/idle time. There is no production address selection, startup installation, automatic pairing or active runtime switch.

## Verification summary

- W3: 44/44 synthetic/local scenarios, exit 0, scratch removed; the final run used the reviewed path after a sandbox ancestor-handle rejection was retained as a failed attempt.
- Frozen W2 compatibility on the current Core and W3 queue candidate: 35/35, exit 0, inner scratch and mirror removed.
- Native adapter compiled; it was not run against real OS activity.
- Default status is disabled and unconfigured.
- Frozen W2 patch, verification and source-manifest hashes still match their accepted values.
- Current Core checkout hashes still match the accepted baseline values.

Detailed evidence and limitations: `VERIFICATION.md`, `SUPPORT_MATRIX.md`, `SOURCE_MANIFEST.json`, `RESULT.json`, `W2_COMPAT_SUMMARY.json`, `W2_COMPAT_RESULT.json`, and `DEVELOPMENT_FAILURES.md`.

## Acceptance boundary and open loops

This is a local wiring candidate, not production acceptance. Real Windows signal collection, production transport/credentials, production pairing, autostart, active runtime switch, broker cold-start recovery, whole-trust-domain rollback detection, punctual physical hard deletion, Android/UI work and a human/device evidence window remain open. The imported W2 recovery limits remain authoritative.

The master task should independently inspect the four-file W2 delta, rerun at least the default status and targeted suites from a clean candidate, verify the final commit/file hashes, then decide whether to integrate. Integration must update the shared project state and run its normal gate; this worker did not modify global project documents.
