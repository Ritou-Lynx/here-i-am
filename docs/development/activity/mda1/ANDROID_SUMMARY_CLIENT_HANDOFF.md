# MDA-1 Android summary reader handoff

This work package adds only a memory-only, read-only Dart transport for
`GET /v1/core/activity/summary`. It has no DI registration, UI, persistence,
platform channel, collector, BLE, foreground-service, sleep inference, or
person-state inference.

The client requires an ephemeral `baseUrl` plus summary-reader token and sends
only the required bearer/protocol/JSON-accept headers. It never caches a
response. Contract/schema/semantics and the complete current summary object
shape are validated fail-closed; malformed, non-JSON, network, timeout and all
HTTP errors return `Error`. Unknown state-like wire values map only to
`unknown`; identifiers are retained exactly, while a source outside the current
closed vocabulary is normalized to the fixed value `unknown` and cannot carry
a concrete state into the local model.

Evidence boundary: a successful unit test proves request construction and
strict local parsing with a Dio fake adapter. It does not prove a live Core,
real credentials, Android installation, device collection, coverage, sleep,
or any human Gate.

R1 verification: `flutter test --no-pub
test\\data\\services\\activity\\activity_summary_client_test.dart` completed
after fixing the unknown-enum test to inspect its deliberately mutated first
source (the fixture contains two sources). `dart analyze` over the client and
test files and `git diff --check` also completed. These remain local fake-
adapter checks only; they add no live-Core or device evidence.

R2 safety repair: the real just-paired Core source encoding (`coverage: {}`
with null event times and unknown state) is accepted only as no current
coverage and remains unknown. A concrete source/device state now requires the
complete matching healthy evidence set; credential, freshness, coverage,
clock, time, reason, unknown-enum and empty-source counterexamples are covered
by the fake-adapter tests. Reader tokens and base URLs are validated before
I/O, redirects are disabled, and a failed second fetch cannot return the first
response. Nonempty coverage and registration values enforce the current
window, positive interval/SLO, generated-server-time and concrete-evidence
consistency rules; explicit conflicts reject or downgrade only. The same
targeted `flutter test --no-pub`, two-file `dart analyze`, and `git diff
--check` were rerun locally. This is still not live Core,
credential, Android, collector, coverage, sleep, person-state, or human-Gate
evidence.

R2.1 verification: the targeted fake-adapter suite has 11 tests and was run
with `flutter test --no-pub
test\\data\\services\\activity\\activity_summary_client_test.dart`; all 11
passed. The two-file `dart analyze` result was `No issues found`, and `git diff
--check` passed. This narrows only parser/request safety: unknown or `none`
coverage modes, future received times, and TTL/expiry disagreement cannot
preserve a concrete state. It does not add any live activity conclusion.

R2.2 verification: the targeted fake-adapter suite now has 13 tests. `flutter
test --no-pub test\\data\\services\\activity\\activity_summary_client_test.dart`
completed with all 13 passing; two-file `dart analyze` reported `No issues
found`, and `git diff --check` passed. The added checks only reproduce
observable Core summary ordering conservatively: bounded durations, concrete
TTL/SLO compatibility, rank-before-time winner selection, and an unknown
result for hidden-order ties. They do not expose a new activity, sleep, or
person conclusion.

R3 adds fail-closed duplicate device/probe identity checks, a fixed summary
source vocabulary with inert `unknown`, and opaque-ID validation. These are
local parser checks only and do not make identifiers, activity, sleep, or
person-state available.

Integration verification on `codex/mda1-activity-core@fbcbceb0` repeated the
fake-adapter suite with all 15 tests passing and analyzed the client plus test
with `No issues found`. This still does not prove live Core credentials,
Android installation, a collector, device coverage, sleep, or a human Gate.

The overall MDA-1 synthetic three-probe report was separately accepted by Lynx
on 2026-09-06. That closes the MDA-1 human-review Gate but does not change this
reader's evidence boundary: it remains an unregistered, memory-only client
module rather than an installed Android feature or collector.
