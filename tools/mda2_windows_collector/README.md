# MDA-2 W3 Windows local wiring candidate

This package wires two caller-authorized Windows activity bindings to two independent protected W2 queues. It contains a compilable native adapter for current-session WTS lock/unlock callbacks, coarse `GetLastInputInfo`, and power-quality gaps. The default entry point is disabled and performs no OS collection or transport:

```powershell
node tools/mda2_windows_collector/main.mjs --status
```

The only bundled transport factory is test-only: it requires an in-process test authority, rejects every host except literal `127.0.0.1`, rejects port `47841`, does not follow redirects, and uses a random loopback service created by the test. The production native mode additionally requires the explicit `productionAuthorized: true` argument and verifies that its requested session is the native process current session. This W3 package does not provide production pairing, credentials, endpoint configuration, startup registration, scheduled tasks, deployment, or runtime switching.

## Verification

From the repository root, through the normal review mechanism needed by the unchanged Windows queue protection helper:

```powershell
node tools/mda2_windows_collector/fixtures/run_tests.mjs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\mda2_windows_collector\fixtures\run_w2_compat.ps1
```

The first command compiles the native source and runs only synthetic callbacks, protected temporary queues, temporary Core databases, synthetic credentials, and test-created random loopback servers. It never launches the native adapter in production mode. The second command reruns the frozen W2 suite in a validated temporary mirror and writes separate W3 evidence instead of overwriting W2 history.

## Minimal programmatic contract

The caller must supply two bindings returned by an already-authorized pairing flow and two distinct protected roots. This package never fabricates, discovers, or rebinds them:

```js
const broker = new WindowsQueueBroker({ clock, transport, maintenanceMs: 1000 });
const wiring = await WindowsCollectorWiring.open({
  broker,
  bindings: [authorizedWtsBinding, authorizedLastInputBinding],
  roots: {
    windows_wts: protectedWtsRoot,
    windows_last_input: protectedLastInputRoot,
  },
  sessionId: trustedCurrentSessionId,
  ttlMs: authorizedTtlMs,
  nativeExecutable: compiledNativeAdapter,
  nativeMode: 'production-explicit',
  productionAuthorized: true,
});
```

`WindowsCollectorWiring.open` is fail-closed: if the second queue, native channel, or native process cannot start, it closes already-started workers and retires the dedicated broker. Protocol validation stays serialized, while final protected allocation is separately bounded per source. `flush(source)` persists an attempt before dispatch; a caller wait timeout leaves it `attempted_unknown`. Maintenance, freeze, and stop continue while the network request is pending. Stop succeeds only after the owned queue process and transport outlet both report actual exit.

The formal asynchronous transport is a trusted two-phase adapter with `kind: 'mda2_bounded_async_transport_v1'`. Its side-effect-free `prepare(binding, context)` must return exactly `start`, `cancel`, `completion`, and independent `exited` members. The broker validates that handle, authorizes the original bytes, records the dispatch, and only then calls `start(bytes)`. A bare Promise, unregistered function, incomplete handle, rejected exit proof, or anything except the exact `{closed: true}` exit receipt cannot retire the outlet. Response completion also remains within the concurrency/stop boundary until that separate exit proof arrives.

Legacy synchronous in-memory W2 fixtures remain available only with the explicit `allowSynchronousFixtureTransport: true` constructor flag and must return an immediate reply. They are not an asynchronous or production transport interface.

Power suspend/resume, callback gaps, tick anomalies, permission loss, and restart are acquisition-quality changes only. They never create new wire kinds or a person/sleep inference. Initial lock state is unknown, and post-resume eligibility returns only after a fresh valid observation.
