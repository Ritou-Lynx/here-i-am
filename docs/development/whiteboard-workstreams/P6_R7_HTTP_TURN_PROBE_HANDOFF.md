# P6 R7 HTTP turn candidate probe

2026-09-12, `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5` plus existing P6 working changes. This worker added only the HTTP turn probe, its test, and this handoff. Existing runtime/API/broker/native/old probes, production availability and actual queues are unchanged. No CLI/UAC/provider operation was executed by this worker.

## Explicit entry and fixed scope

`runHttpNativeTurnProbe({ executable, sha256, scenario })` accepts only `completed`, `interrupt`, or `turn-disconnect`. The CLI requires exactly `--<scenario> <absolute-exe> <lowercase-sha256> <new-absolute-report>`. It reserves the report with `wx` before acquiring resources. Production does not import this module.

Each invocation creates one candidate HTTP server on `127.0.0.1:0`, one native owner through the existing pinned transport, one authenticated cached-account check, one ephemeral thread and one fixed public text turn. Input is `Reply exactly: P6_R7_NATIVE_OK`. Broker/model/reconstruction policy remain the existing `gpt-5.6-sol`, low reasoning, tools disabled, single exchange gate. There is no caller input/model/home/provider override, credential file access, or prompt adjustment to slow a fast provider. Local HTTP uses a private Agent with empty `proxyEnv`; the real broker keeps the existing transport proxy behavior.

The default factories are real. Explicit test injection requires all four fake functions (broker, owner, client, exchange); injected results always carry `evidence: synthetic`, `actual_native: false`, and `passed: false`, even when structural checks pass.

## Scenario evidence

- `completed`: real HTTP create and turn POST, cursor-based HTTP JSON events, exact reconstructed fixed text, matching terminal, response gate release and exact bound DELETE stop receipt. The existing turn receipt outcome is `closed`, not `completed`; JSON receipts are structurally verified and do not use the in-memory WeakSet brand.
- `interrupt`: requires one native start dispatch, one upstream attempt, an exchange locally begun and still unsettled, and no matching terminal before the HTTP interrupt action. Then requires real interrupt dispatch, matching `turn/completed: interrupted`, strictly later terminal sequence, cancelled receipt, empty text and no response release. ACK alone fails. Fast completion fails instead of delaying the exchange or changing input.
- `turn-disconnect`: holds the already returned adapter turn result before the API receives it; after the same in-flight checks, destroys the actual HTTP client request, observes the server's real AbortSignal, then releases the hold. The facade captures the actual API's single closeSession call before final shutdown, independently of listener order; the API close may precede the probe's abort observer. The flow requires the real AbortSignal before adopting that exact-ID promise/result and never initiates a substitute adapter close. Requires no finished HTTP turn response and same-owner cleanup. Local resource closure, terminal status and cancellation are separate report fields. If broker revocation leads to `failed` instead of `interrupted`, local cleanup may be true while the scenario remains failed; no runtime contract is relaxed.

Exchange start, settlement and abort observations are local facts. They do not prove upstream server acceptance, active model computation, or cessation of provider billing. Reports contain only booleans, finite counters/status/error summaries and generated attempt/pin identity; no account fields, notification bodies, model text, prompt text or raw errors are persisted.

## Cleanup and limitations

The total deadline timer synchronously fences dispatch before rejecting; absolute-deadline checks precede each new HTTP socket and model request. Deadlines trigger the existing permanent API shutdown and bounded same-owner native/broker cleanup. Unknown native startup/close, failed drainage, unfinished HTTP handlers or open sockets remain pending. Resource objects for incomplete cleanup are retained in a private process-lifetime map; no second owner is substituted and no timeout manufactures a receipt. This harness does not implement cross-process recovery or automatically retry elevated helpers. Root owns any further action when actual cleanup is unconfirmed.

Success requires actual native owner exit 0, all six native closure facts, pending false, drained broker, finished handler/server shutdown, no host request and no generic adapter construction. Each scenario has exactly one broker arm/start/exchange. The real native transport still owns and validates actual process close and postpin. An outer actual run must independently observe probe exit and frozen-input checks before adopting its report. Production and human Gate remain false.

## Verification and freeze

New tests **11/11** pass using fake native/provider resources and real loopback HTTP. Cases include all three scenarios, early terminal refusal, revoke-before-interrupt failed terminal, ACK-only/missing dispatch/unmatched terminal, wrong text, config/exit/closure/drain errors, extra exchange refusal, private no-proxy Agent and explicit CLI argument rejection. Audit regressions prove a real abort with deliberately omitted API close cannot borrow final shutdown as success, late creation after total deadline produces zero turn HTTP sockets/arms/model requests/exchanges, and a forced API-close-before-probe-abort-observer order still captures the unique same-owner close. Latest probe plus runtime adapter/API lifecycle regression is **43/43**. Earlier broader old HTTP/native coverage was **63/63**. These tests do not constitute provider/native actual acceptance.

- Probe `tools/dev_agent_bridge/workbench_text_task_http_turn_probe.mjs`: SHA-256 `A6118B5F2C0D3DEBD9B873FB900CA61D61067D97DDEB4E320926291523BE1EF7`.
- Test `tools/dev_agent_bridge/workbench_text_task_http_turn_probe.test.mjs`: SHA-256 `6A4552189C150CF5395BD828F826EC8E2D90A95CD0F1448B81C8DD43B6C0A9EE`.

Root reported completed and interrupt actual01 passed with the prior `0F0DBAB8B5F885F86AB3CC278776A07362161D7DCCBF10E74E965A2FB789CE9C` source. Those exact-candidate records remain historical and are not inherited by this listener-order revision. Root must freeze and run all three scenarios for the final candidate; this worker has not executed or independently adopted those actual reports.

Code is paused for root freeze and independent review. Native v7 executable remains root-owned pin `73cbe6277fd4bf5b92bdc3189e00eee5ce78f208d6037d8d16a14df9bde4bc4e`; the detached native transport remains `8c4f80fc616bab9ef96ea0117ee3b54d57a70e06bb2794c5677fed42ba5a8a98`. No actual turn report is claimed here.
