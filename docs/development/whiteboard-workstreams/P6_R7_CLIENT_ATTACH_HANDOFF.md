# P6 R7 client attached-transport handoff

## Scope

Implemented the bounded attached-native-RPC path in `tools/dev_agent_bridge/codex_app_server_client.mjs`. It is an alternative to the existing spawned stdio child; no provider, real CLI, network, Android build, install, or production availability change was exercised.

## Contract

- `attachedTransport` is mutually exclusive with `commandSpec` and an explicitly supplied `spawnImpl`.
- The transport is an already-established EventEmitter-style object with `send(message, { onDispatched })`, `close()`, and `message`, `error`, and `close` events. `send` returns a promise; `onDispatched` is the actual native stdin-write acknowledgement, not an enqueue acknowledgement. `close()` and the `close` event carry a receipt.
- Attach-mode `start()` sends `initialize` and `initialized` over that transport without spawning a child. Parsed transport notifications retain their observed order, including notifications that precede a later native write acknowledgement; the session ledger uses those original sequence values to reject a terminal that occurred before an interrupt was actually written.
- A response before the matching native dispatch acknowledgement is `response_before_dispatch` and makes the transport unavailable. A timed-out request retains its dispatch callback, so a late actual acknowledgement remains visible to the owner.
- Only `process_close_observed: true` is process-close evidence. `error`, IPC loss, or a close receipt without that proof leaves the transport owned and retryable (`unavailable` / `stop_unconfirmed`); it never fabricates a child close.

## Evidence

`node --test tools/dev_agent_bridge/codex_app_server_client.test.mjs` covers attach initialization without spawning, delayed dispatch after request timeout, no unbounded notification deferral when an ACK never arrives, response-before-ACK fail-closed behavior, IPC loss without close proof, failed initialization that retains cleanup ownership, and both terminal-before-ACK and terminal-after-ACK receipts through a real `WorkbenchTextTaskSession`. Existing spawned-client lifecycle and stop-receipt cases also run in the same suite.

## Limits

The tests are in-memory transport fixtures. They establish the client contract and lifecycle behavior only; they do not prove a real native helper, account/provider behavior, process isolation, or a human Gate.
