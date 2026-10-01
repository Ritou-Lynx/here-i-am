# MDA-2 W3 Windows support matrix

This matrix describes the checked-in candidate only. A compile result or synthetic replay is not a device or production Gate.

| Capability | Candidate status | Evidence / boundary |
|---|---:|---|
| WTS lock/unlock mapping for the current session | Implemented, synthetic-only verified | Native adapter compiles; strict parser/session/epoch tests pass. No real lock/unlock event was collected. |
| `GetLastInputInfo` coarse idle mapping | Implemented, synthetic-only verified | Wrap, regression, full-period ambiguity and independent-source tests pass. No real keyboard/mouse activity was collected. |
| Power/loss/recovery quality gaps | Implemented, synthetic-only verified | A gap changes quality epoch and requires a new observation; it never counts as interaction. |
| Privacy-minimal native payload | Implemented and negative-tested | Frame admits only source, kind, ages/times, sequence, quality epoch and bounded value. Titles, app names, keys, screen/body and account enumeration are not collected. |
| Two explicitly authorized per-source queues | Implemented and synthetic-verified | Caller supplies both bindings and protected roots. No automatic pairing or shared sequence. |
| Protected disk queue / W2 recovery contract | Preserved with narrow adaptation | Frozen W2 suite passes 35/35 on the current Core. Same W2 limits remain. |
| Asynchronous dispatch with maintenance independence | Implemented and synthetic-verified | Trusted two-phase adapter is validated before start; response completion remains active until exact independent exit proof. Raw expiry, freeze, stop and close races are covered. |
| Bounded HTTP test transport | Implemented, test authority only | Only a test-created literal `127.0.0.1` random port is accepted; redirects and active port 47841 are rejected. Start failure after request creation waits for real request close. |
| Production endpoint / real credentials | Unsupported | No production URL, credentials or existing database were used. |
| Real Windows collection | Not executed | Native adapter was compiled but never launched in `--production-explicit` mode. |
| Startup registration / service installation | Unsupported | Default mode is disabled; no task, service or autostart mutation exists. |
| Production pairing / runtime switch | Unsupported | No active configuration or shared runtime was changed. |
| Broker cold-start recovery | Unsupported | W2 continuity still requires the broker/age-provider trust domain described in its handoff. |
| Whole-trust-domain rollback detection | Unsupported | Explicitly deferred. |
| Punctual physical hard deletion | Unsupported | Logical retention behavior remains; physical hard-delete guarantee is not claimed. |
| Android/mobile observation UI | Out of scope | No Flutter or Android path changed. |
| Human/device Gate | Not performed | 44/44 and 35/35 are local executable evidence only. |
