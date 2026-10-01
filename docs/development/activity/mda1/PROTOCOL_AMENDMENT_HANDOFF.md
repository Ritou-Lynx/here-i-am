# MDA-1 protocol amendment handoff

> Baseline: `dd79debd1f4c69ff74270f48ec99fba93ffc315c`
>
> Branch: `codex/mda1-protocol-amendment`
>
> Scope: protocol documents and synthetic fixtures only. No Core code, test,
> Roadmap, Goal, project-state, DEVLOG, device, network, build, or deployment
> change is included.

## Decision

`device.activity.v1` remains a proposed, undeployed wire contract, so this is a
dated pre-deployment amendment within `schema_version: 1`, not a v2 wire bump.
The independent fixture/proposal revision is now `5`. If any real producer or
persisted outbox is later found to have emitted the former arbitrary event ID,
this decision must be reopened and compatibility/version negotiation added.

Pairing now normatively issues a cryptographically random event lineage prefix
with at least 128 bits of entropy. A wire event ID is exactly the issued prefix,
a dot, and the event's canonical decimal `origin_sequence`. Rotation preserves
the prefix. Deletion retires it permanently; an old outbox is discarded or
reported as terminal client action and is never rebound to a replacement
lineage.

This structured ID and `(device_id, probe_id, origin_sequence)` are two database
constraints over one logical idempotency coordinate, not independent client
keys. Exact duplicate/receipt recovery is available only while per-event replay
detail remains. At or below an advanced durable lineage floor the terminal
result is `event_retained_out` because Core no longer has enough detail to
distinguish duplicate from altered replay.

The prefix can remain an opaque pseudonymous handle. The complete event ID is a
structured pseudonymous, linkable identifier because it reveals lineage and
sequence; it is not opaque.

Future-skew and signal-time regression events are retained in the immutable
ledger with explicit clock health, but must not advance a concrete projection.
The affected source summary is `unknown` and cannot contribute quiet, resting,
sleep, or intervention evidence.

Within one probe lineage, every new logical event receives a strictly
increasing, never-reused `origin_sequence`; a retry reuses the materialized
event. Network delivery may be out of order. Core may ledger-accept a first-seen
smaller sequence above the retained floor and marks the receipt with the
separate `sequence_regression` diagnostic. That diagnostic alone does not force
`unknown`. A real missing sequence interval does: the source remains `unknown`
until all coordinates in the gap are legally filled, then Core recomputes the
projection in logical sequence order. Floor-and-below submissions remain
terminal `event_retained_out`.

The one-day raw and spool choice is a privacy maximum, not a per-event minimum
availability guarantee. `retained_origin_floor` therefore uses bounded prefix
closure: when an accepted raw event is due by Core `received_at_ms`, Core
atomically retires all accepted replay detail at or below that origin sequence
and advances the floor. A lower coordinate may be retired before its own Core
receipt age. Conforming probes expire materialized, queued, and in-flight work
within the same one-day maximum; late floor-and-below delivery is terminal,
stores no raw payload, and never reopens a closed historical gap. This lineage
floor is distinct from the server-feed `retained_watermark`: the former governs
ingress/replay `event_retained_out`, while the latter governs cursor
`resync_required`.

## Fixture revision 5

[`../mda0/fixtures/manifest.json`](../mda0/fixtures/manifest.json) declares the
pairing capture and event-ID recipe. Normal event templates omit `event_id`.
Only `noncanonical_event_id`, `wrong_event_id_prefix`, and
`event_id_sequence_mismatch` may use `wire_event_id_override`.

Fixtures contain no literal bearer credential/token, URL, secret, or private
content. They do contain restricted symbolic pairing-response references needed
for execution. `privacy_lint_contract` is the exact allow-list; the runner must
reject every other credential-shaped key/value before capture resolution and
must never serialize or log captured material.

The manifest contains 26 isolated cases:

- `valid_and_idempotency.json`: 10;
- `validation_and_clock.json`: 7;
- `coverage_scope_and_replay.json`: 6;
- `limits_and_atomicity.json`: 3.

Expected values separate the conceptual protocol outcome from the concrete
HTTP status/result/error code. Setup/precondition behavior is expressed as
ordered operations rather than free-text assumptions. No normal event carries
a hard-coded arbitrary legacy event ID.

`deleted_lineage_outbox_not_rebound` now carries a complete explicit
`replacement_pair`: it keeps the synthetic device but uses a distinct synthetic
probe identity, and the owner pairing response captures a new prefix and token
reference. The runner may not synthesize either value. After pairing, the old
captured outbox bytes are rejected and discarded locally; they are never
rewritten with the replacement prefix or identity.

Revision 5 also makes the static fixture gate consume each declared Core clock,
retention, authority/fencing, credential-generation, revocation, and payload
materialization witness. The five fixture documents must all declare proposal
revision 5. The deleted-lineage fixture separately captures the exact queued
outbox bytes and later resolves that bytes capture; a future runner must retain
and diagnose the same Buffer for the old-credential and replacement-lineage
rejections before local discard. This is still a static contract check, not evidence that Core's HTTP
implementation enforces the behavior.

Revision 5 additionally freezes the exact `expected` root-key and nested HTTP
key shape for every canonical case and step. A field that is legal in another
fixture witness is not legal here; this prevents a runner from acquiring new
owner/admin, export, or reader-feed side effects through an unrecognized
expected assertion.

R5.1 keeps the fixture proposal at revision 5 and closes only the static leaf
type gap: every expected string, boolean, counter, HTTP detail, and array item
is fail-closed before witness semantics run. Arrays reject nested objects and
arrays; sequence `missing` accepts only unique nonnegative safe integers.

The amendment does not claim the fixtures are already connected to HTTP. The
required next Gate must pair through `/v1/core/activity/probes/pair`, capture the
actual response prefix, materialize every template, submit through the real
HTTP route, fail on an unused fixture field or skipped manifest case, and
compare both conceptual and HTTP expectations. A helper that overwrites the
fixture ID or a direct store call is not this Gate.

## P1 code-alignment red lights at candidate `83534bb2`

These are deliberate, precise fixture expectations; the fixture must not be
weakened merely to make the candidate green.

1. Unknown event kind currently returns `invalid_request`; revision-3 fixture
   expects HTTP `unsupported_kind`.
2. Missing required fields currently collapse to `invalid_request` without the
   required field detail; fixture expects HTTP `missing_required_field` with
   `details.field`.
3. A probe token sent to the chat change route currently falls through legacy
   device authentication as `401 unauthorized`; fixture expects an explicit
   `403 chat_read_forbidden` before resource lookup.
4. A probe token sent to an owner route currently returns
   `401 activity_admin_unauthorized`; fixture expects the explicit
   `403 admin_escalation_forbidden` category.
5. An older clock-regression event is stored, but when a concrete projection
   already exists the candidate can leave that projection intact. Revision 2
   requires the affected source summary to become `unknown` with
   `clock_regression`.
6. The oversized-payload vector materializes a 4,097-byte payload and expects
   `413 payload_too_large`; candidate field validation may return another error
   before enforcing the payload byte boundary.
7. The candidate test helper accepts an `eventId` option but ignores it, and
   the only imported MDA-0 event is rewritten before a direct store call. A
   fixture-to-HTTP runner and dead-argument repair remain required in P1-owned
   code/tests.
8. The candidate does not yet prove durable per-lineage sequence coverage,
   ledger acceptance of an out-of-order first-seen value above the retained
   floor, or logical-order projection recomputation after the last gap is
   filled. The `sequence_gap_then_out_of_order_fill` HTTP fixture must remain
   red until all three transitions are observed.
9. No real runner yet enforces the raw-fixture privacy allow-list before pairing
   resolution. P1 must reject unapproved credential-shaped keys/values and
   prevent a captured token from appearing in logs, snapshots, or assertion
   failure output.

## Verification recorded by this commit

- JSON parse: `5/5` JSON files parsed.
- Fixture lint: `26` manifest cases, `27` event templates, `23` normal
  recipes, `3` allow-listed overrides, and `37` expected assertions checked;
  every manifest filename/case matched exactly once, with no normal explicit
  `event_id`, literal bearer credential/token, URL, secret, or prohibited
  private content. Credential-shaped fixture keys/values matched the restricted
  symbolic reference/counter allow-list; this does not claim credential fields
  are entirely absent.
- Stale wording scan: no arbitrary legacy event ID, rejected-clock outcome,
  design-only/no-parser status, old double-idempotency wording, or opaque full
  event-ID claim remains in the owned amendment surface.
- `git diff --check`: passed.
- Device/network/build/install: not run and not authorized.
