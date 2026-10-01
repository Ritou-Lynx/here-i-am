# Proposed ADR — `device.activity.v1`

> **Status:** proposed; non-authoritative MDA-0 design evidence.
> **Proposal revision:** 2, amended 2026-09-05 before deployment or fixture
> freeze. Wire contract remains `device.activity.v1` / `schema_version: 1`.
> **Owner:** M0-P2 activity contract worker.
> **Decision authority:** requires Lynx's contract review and a future Gate 1A-0
> authority ADR before any implementation, schema, credential, ingress, or
> retention change. It does not approve MDA-1.

## 1. Scope and boundary

`device.activity.v1` is a proposed, activity-only ingress vocabulary for
minimal probes. It deliberately excludes chat, Memory V3, User-truth, Cards,
window titles, application names, keystrokes, screen contents, notifications,
BLE packet bodies, health records, and any private text.

It is **not an existing iCore API**. Current iCore protocol `0.1` has device
pairing, chat submission, change feed, and cursor acknowledgement only; its
`capabilities_json` is a registration claim, not a server permission scope.
This proposal cannot expand it.

Before an implementation can accept an event, Gate 1A-0/1A-3 must specify the
single Core writer, durable Core `epoch`/instance identity, authority
registration, fencing validation, client outbox behavior, change-feed epoch,
and recovery/takeover invalidation. A probe may submit intent; only the active
Core in the accepted epoch may allocate acceptance state or projections.

## 2. Proposed envelope and acceptance rule

An owner-authorized pairing act assigns each probe lineage a cryptographically
random `event_id_prefix` with at least 128 bits of entropy. The wire encoding is
22--64 unpadded base64url characters (`[A-Za-z0-9_-]`). Pairing returns the
prefix separately from the write-only credential. The prefix is not a bearer
secret, but it is pseudonymous linkable data and must not be chosen by a probe.

Credential rotation preserves the prefix so an existing outbox can retry the
same immutable event. Deleting a probe retires the prefix permanently; a new
lineage receives a new prefix, and queued events from the deleted lineage must
be discarded or reported as terminal client action rather than rebound to the
new prefix.

`origin_sequence` records logical-event creation order inside that probe
lineage. The probe/outbox allocates a strictly increasing value for every new
logical event and never reuses a value in the same lineage, including after a
local drop, dead letter, retry exhaustion, credential rotation, or process
restart. A retry reuses the already materialized event and sequence. Transport
delivery may be delayed, duplicated, or out of order; wire arrival order is not
required to match logical creation order.

Each submitted item has this abstract JSON shape; field names are vocabulary,
not a production schema. The example uses an illustrative 22-character
synthetic prefix after fixture materialization.

```json
{
  "contract": "device.activity.v1",
  "schema_version": 1,
  "event_id": "AAAAAAAAAAAAAAAAAAAAAA.41",
  "device_id": "device-synthetic-windows",
  "probe_id": "probe-synthetic-wts",
  "origin_sequence": 41,
  "kind": "session.unlocked",
  "signal_at_ms": 1760000000000,
  "ttl_ms": 300000,
  "confidence": "high",
  "source": "windows_wts",
  "coverage": {
    "mode": "continuous",
    "window_start_ms": 1759999990000,
    "window_end_ms": 1760000000000,
    "expected_report_interval_ms": 30000
  },
  "payload": {}
}
```

`signal_at_ms` is the probe's best estimate of when the signal happened.
`received_at_ms` is **not a submission field**: Core assigns it after validation
and stores it only on the accepted record/receipt. A probe-supplied
`received_at_ms` is rejected as `unknown_field`. `ttl_ms` limits acceptance
freshness; it is not a retention promise.
The accepted record must retain both times and expose diagnostics rather than
silently rewriting signal time. Future skew and signal-time regression are
accepted into the immutable ledger with explicit `clock_health`
(`future_skew` or `clock_regression`) so evidence is not silently lost. Such a
clock-invalid event must not advance a concrete device projection: the affected
source summary is `unknown`, carries the clock-health reason, and cannot
contribute quiet, resting, sleep, or intervention evidence. TTL is still
evaluated against the Core receipt time and remains a rejection boundary.

`sequence_regression` is a separate receipt diagnostic, not a clock-health
state: it means Core first saw a valid sequence smaller than the lineage's
highest previously seen sequence. That can be ordinary out-of-order network
delivery. A pure `sequence_regression` does not by itself force the source to
`unknown` and does not imply `clock_regression`; clock order is evaluated against
events in logical sequence order, not receipt order.

`event_id` has one exact wire construction:

```
<server-issued event_id_prefix>.<canonical decimal origin_sequence>
```

Canonical decimal is `0` or a positive base-10 integer with no sign, whitespace,
alternate radix, or leading zero. `origin_sequence` is a non-negative safe
integer. A lexically invalid ID is `invalid_event_id`; a well-formed ID with the
wrong issued prefix or a suffix different from `origin_sequence` is
`event_id_binding_mismatch`. Binding is checked before idempotency, TTL, rate
limit, or receipt lookup.

This is one logical idempotency coordinate represented by two defensive
database constraints: globally unique `event_id`, and unique
`(device_id, probe_id, origin_sequence)`. They are not independent client keys;
a valid wire request binds them to the same probe lineage. Repetition with the
same canonical payload digest while per-event replay detail is retained returns
`duplicate` and the original acceptance reference. The same coordinate with a
different digest is `idempotency_conflict` (no partial acceptance, no
replacement). After retention has removed the per-event digest/receipt and
advanced the durable lineage floor, any submission at or below that floor is
terminal `event_retained_out`; Core must not guess duplicate versus conflict.
The service canonicalizes a documented representation before hashing; clients
cannot select the digest.

`retained_origin_floor` is a per-lineage privacy-closure boundary, not a
minimum availability promise. Raw lifetime is measured from Core-assigned
`received_at_ms`, never from the probe clock. When any accepted raw event
reaches the selected 24-hour maximum, Core atomically advances the floor to
that event's origin sequence and retires every accepted raw replay detail at or
below the new floor. This prefix closure may retire a lower coordinate earlier
than its own receipt age; it never retains a sparse permanent event history.
A conforming probe expires locally materialized, queued, and in-flight
submissions no later than 24 hours after materialization. A delivery at or
below the floor is terminal `event_retained_out`, stores no new raw payload,
does not disclose an old receipt or digest, and cannot reopen a historical gap.
This means Core does not promise that an already accepted event remains exact-
replay-resolvable for a full 24 hours.

Core also tracks sequence coverage independently from replay/idempotency. When
no retained floor exists, the first accepted event establishes the initial
observed baseline; once a floor exists, the next contiguous coordinate is
exactly `retained_origin_floor + 1`. Thereafter, accepting a first-seen sequence
greater than `contiguous_origin_sequence + 1` records the missing interval as a real
`sequence_coverage_gap`. The event remains in the immutable ledger, but the gap
forces that source summary to `unknown` and prevents concrete projection
advance. A first-seen smaller sequence that is still above the retained floor
is accepted and marked `sequence_regression`; if it fills the final missing
coordinate, Core clears the gap and recomputes the replaceable projection in
logical sequence order. The source may then return to the latest concrete state
only if clock, TTL, permission, and ordinary coverage checks also pass. An event
at or below the retained floor remains terminal `event_retained_out`, even when
it appears to fill a historical gap. If privacy closure advances across an
unfilled interval, that historical interval is permanently closed; the source
remains `unknown` until events above the new floor establish fresh contiguous,
otherwise valid evidence.

The request is one atomic batch: validate authorization, epoch/fencing,
envelope, TTL, size, kind, and both database constraints for every item first. If
any item fails, accept none and return per-item machine-readable reasons.
Partial batch mode, if ever wanted, requires a later protocol version.

The proposed v1 protocol caps the UTF-8 encoded `payload` at 4,096 bytes. The
later Gate 1A/MDA-1 implementation ADR must additionally freeze a bounded whole
envelope, item count, and batch byte limit before an ingress can exist; until
then no endpoint is deployable. An implementation may choose stricter limits,
but cannot silently accept a larger body under this contract version.

## 3. Event, status, and permission dictionary

### Event kinds (closed allow-list)

| Kind | Minimal payload | Meaning and explicit non-meaning |
|---|---|---|
| `probe.heartbeat` | `{}` | One probe report succeeded; never proves user activity or continuous coverage. |
| `session.locked` | `{}` | A session lock was observed; not proof the person is resting or asleep. |
| `session.unlocked` | `{}` | A session unlock was observed; supports `awake_evidence`, not continuous use. |
| `input.activity` | `{class: input_or_touch}` | Generic interaction category only; never key, app, title, content, or raw count detail. |
| `input.idle_bucket` | `{bucket: lt_1m|1_5m|5_15m|15m_plus}` | Session-scoped idle bucket; long reading/video can still mean awake. |
| `screen.interactive` | `{}` | The display became interactive; not proof a person is present. |
| `screen.non_interactive` | `{}` | The display became non-interactive; not rest or sleep. |
| `app.category_active` | `{category: chat|social|video|reading|work|other}` | Device-local category only; never an app/package name or content. |
| `focus.sleep_on` | `{}` | User/system sleep-focus intent; not evidence the person is asleep. |
| `focus.sleep_off` | `{}` | Sleep Focus ended; not by itself a complete wake interval. |
| `power.charging` | `{}` | Power transition only; not presence or sleep. |
| `power.unplugged` | `{}` | Power transition only; not presence or wakefulness. |
| `network.present` | `{}` | Low-confidence reachability only; never user activity. |
| `sensor.heart_rate_quality` | `{quality: fresh|stale|gap|unavailable, source_age_ms: integer}` | Cross-domain quality/freshness only; no raw BPM, RR, PPG, sleep or medical claim. |
| `probe.permission_changed` | `{capability: token, available: boolean}` | Readiness/permission transition; missing permission forces that source to `unknown`. |
| `probe.error` | `{code: bounded_token}` | Minimal failure category; no stack, token, URL, payload, or private content. |

Unknown `kind` is rejected with `unsupported_kind`. Unknown top-level or nested
fields are rejected with `unknown_field` in v1, so silent producer/consumer
drift cannot broaden data collection. A future additive version may negotiate
a new allow-list; it must not rely on silent field dropping.

### Source, confidence, coverage, and state vocabulary

`source` is a closed, server-assigned capability identifier (for example
`windows_wts`, `windows_last_input`, `android_usage_events`,
`android_screen_state`, `iphone_shortcuts`, or `android_ble_hrs_quality`). It is
evidence metadata, not permission. `confidence` is `high`, `medium`, or `low`
under a source-specific rule fixed by the later implementation ADR; it never
overrides freshness, coverage, or a contradictory positive interaction.

Every registered source capability declares a `coverage.mode`, current
coverage window, expected report interval, and expiry SLO. `continuous` means
the system API/probe can prove the whole window was observed;
`discrete_best_effort` and `heartbeat_only` prove only individual reports;
`none`/`unknown` prove no negative interval. Only fresh `continuous` coverage
may contribute to `quiet_observed`.

| Name | Enter only when | Must not be interpreted as |
|---|---|---|
| `active` (device) | fresh high-confidence unlock/input/app-category interaction | why the user is active or activity beyond TTL |
| `quiet_observed` (device) | fresh continuous coverage proves the whole interval and reports no allow-listed interaction | sleep, rest, or inactivity outside coverage |
| `locked` (device) | a still-fresh `session.locked` signal | the person is absent or asleep |
| `network_only` (device) | only network/heartbeat reachability is known | activity, presence, awake, or asleep |
| `unknown` (device/person) | coverage absent, stale, revoked, failed, unsupported, or conflicting | silence, sleep, or permission to infer |
| `awake_evidence` (person) | any device has a recent accepted high-confidence unlock/input/app interaction | continuously awake or available |
| `activity_candidate` (person) | weaker/sustained activity exists but recent human interaction is not proven | permission for high-intensity intervention |
| `resting_candidate` (person) | future multi-source, policy-approved shadow logic says evidence is compatible with rest | sleep or a health fact |
| `sleep_candidate` (person) | shadow-calibrated multi-source continuity includes a separately hardware-confirmed independent body/environment source and no conflict | a diagnosis, User-truth, or permission to intervene |

`discrete_best_effort`, `heartbeat_only`, `none`, and `unknown` cannot produce
`quiet_observed`. No single heart-rate value/quality stream, heartbeat, network
fact, app foreground heartbeat, no reply, or absence of events may produce
`resting_candidate` or `sleep_candidate`. Positive fresh interaction wins over
all quiet/body signals and immediately returns the person to `awake_evidence`.

### Proposed scopes and principals

| Principal | Scope | Proposed authority |
|---|---|---|
| paired probe credential | `activity.write` | submit only its bound `device_id`/`probe_id` and server-allowed kinds; no reads |
| main Android summary client | `activity.read_summary` | read only the minimal per-device projection with source/freshness; no raw event/chat read |
| Core owner/admin principal | `activity.admin` | pair/revoke/delete, assign capabilities, and inspect minimal audit metadata; never derived from a device token |
| active Core authority (internal) | acceptance authority, not a probe scope | validate epoch/fencing and make the sole acceptance/projection decision |

The server assigns scopes and allowed kinds/capabilities during an explicit,
audited administrative act. A submitted `source.capability`, pairing-time
`capabilities_json`, platform label, or payload claim is evidence metadata,
**never permission**. No activity credential may read chat feeds or write
Memory, Cards, User-truth, or companion actions.

## 4. Device projection and candidate state

The future projection is derived and replaceable, not an event source and not
User-truth. At minimum it carries: authenticated device/probe identity, active
Core epoch, highest-seen and contiguous origin sequences, unresolved sequence
intervals, last receipt time, latest source coverage, clock-health and sequence
diagnostics, credential status, and a derived state from the dictionary above.
It must show `unknown` on expiry, revocation, epoch change, ordinary coverage
gap, or `sequence_coverage_gap`. A pure `sequence_regression` after a gap is
filled does not independently require `unknown`. The projection never stores a
private body and never turns a candidate into a fact.

Candidate states (`awake_evidence`, `activity_candidate`, `resting_candidate`,
`sleep_candidate`) are shadow-only until separately approved. They must retain input receipt IDs,
coverage interval, policy version, and explanation category; no automatic
chat, notification, call, or User-truth write may be triggered before a later
single-executor/cooldown/receipt contract is accepted.

## 5. Threat model and required controls

| Threat / failure | Required proposed control | Fixture |
|---|---|---|
| cross-device impersonation | authenticate credential; bind `device_id`/`probe_id` to it; reject mismatch | `cross_device_impersonation` |
| wrong or escalated scope | server-side scope check and per-credential kind allow-list | `wrong_scope` |
| write-only token reads chat/private feeds | route/activity scope isolation; reject before resource lookup | `write_token_chat_read_denied` |
| probe claims admin via payload/capabilities | separate owner principal; never derive `activity.admin` from probe input | `probe_admin_escalation` |
| revoked credential replay | durable revocation generation checked before idempotency lookup; reject all replay | `revoked_replay` |
| stale Core / double writer | persistent epoch and fencing token checked at acceptance transaction | `stale_epoch_or_fencing` |
| malformed or cross-lineage event ID | pairing-issued prefix, canonical decimal suffix, exact binding before lookup | `noncanonical_event_id`, `wrong_event_id_prefix`, `event_id_sequence_mismatch` |
| duplicate / altered retry | one lineage coordinate, two DB constraints, canonical digest conflict rule, retained floor | `duplicate_same_payload`, `duplicate_different_payload`, `retained_out_retry` |
| clock spoof, future or rollback | Core stamps receipt time; retain immutable raw evidence but force source summary to `unknown` with clock health | `future_clock`, `clock_regression` |
| out-of-order delivery or missing sequence | probe allocates strictly increasing new-event sequences; Core ledger-accepts first-seen values above the retained floor, diagnoses receipt-order regression separately, and holds the source `unknown` only while a real sequence gap remains | `sequence_gap_then_out_of_order_fill` |
| expired queue / delayed replay | TTL checked against Core receipt time before acceptance | `ttl_expired` |
| missing coverage made into silence | model absence as `unknown`, never `quiet_observed` | `no_coverage_silence` |
| oversized/malicious payload | strict byte limit before JSON persistence; closed fields and bounded strings/batches | `oversized_payload` |
| mixed-validity batch | validate all items and atomically reject the batch | `batch_atomic_rejection` |
| inference/data creep | minimal kinds/payloads, reject unknown fields, no content collection | all fixtures |
| token disclosure or logging | device-bound write-only blast radius, immediate rotation/revoke, redact credentials/URLs/bodies from diagnostics | human security review + revoke fixtures |
| transport interception/public exposure | authenticated HTTPS ingress inside the chosen topology; no plaintext or loopback URL in a Shortcut | M0-P3 iPhone/topology human Gate |

Rate limits, minimum retry backoff, and spool capacity are intentionally
unresolved implementation policy. They must be enforced by the accepting Core,
return a non-ambiguous `rate_limited`/`spool_full` outcome, and never convert
dropped signals into a human state. Retention defaults and physical backup
deletion remain the separate M0-P3 proposal.

## 6. Privacy and non-inference rules

Payloads use category tokens and coarse buckets only. They must not contain
private text, app or window names, URLs, keystrokes, screen/notification data,
raw BLE packets, account identifiers, audio, images, or bearer credentials.
`event_id_prefix`, device/probe IDs, and receipt IDs are opaque pseudonymous
handles, not names. A complete `event_id` is instead a structured pseudonymous
identifier: it contains no private content or device name, but it deliberately
reveals stable probe-lineage linkage and the canonical origin sequence. It must
therefore not be described as opaque or logged as harmless diagnostic text.
Diagnostics may explain rejection category and coverage, but not reconstruct
private activity.

The system must not infer a person is awake, resting, asleep, at a location,
alone, medically unwell, or available from any prohibited source or from
silence without valid continuous coverage. Activity evidence is not medical
evidence and must not enter User-truth automatically.

## 7. Review and mechanical checks

The proposal-revision-2 fixtures in
[`fixtures/manifest.json`](fixtures/manifest.json) and its referenced files are
synthetic scenario templates and intentionally contain no literal bearer
credential/token, URL, secret, or private content. Normal events omit an
explicit `event_id`: setup pairs the probe,
captures the server response prefix, and `event_id_recipe` materializes the
wire ID from that prefix and the template's `origin_sequence`. Only cases whose
purpose is malformed or wrong binding may use `wire_event_id_override`.
`expected.outcome` names the conceptual contract result;
`expected.http.status`, `result_status`, and `error_code` independently freeze
the observable HTTP result. An implementation must satisfy both and may not
collapse a precise protocol error into a generic validation or authentication
error merely because the conceptual outcome is similar.

Mechanical checks must parse every JSON file, cover every manifest case, reject
unused fixture fields, validate recipe/override use, ensure each `kind`,
`coverage`, conceptual outcome, and expected HTTP result appears in the
dictionaries above, and reject literal bearer credentials/tokens, URLs,
secrets, private content, and unapproved credential-shaped keys or values.
Restricted symbolic references are necessary to drive pairing: the manifest
allow-list permits only its exact pairing-response capture/reference keys and
non-secret generation/fencing counters. A runner must scan the raw fixture
before interpretation and fail closed on every credential-shaped key/value not
matched by that allow-list; it must never serialize a captured token into a
fixture, log, snapshot, or failure output. A later implementation Gate must
execute the materialized fixtures through the real HTTP pairing and activity
endpoints; replacing a fixture ID in a test helper or calling the store directly
is not fixture-to-HTTP evidence. Human Gate remains: review this proposed
contract and approve, amend, or reject it; it has not passed.
