# P4 — Canonical Authority / Recovery / Migration Harness Handoff

This revision records the eighth substantive review repair of P6 (the seventh
independent-final-review follow-up): fully fail-closed malformed-ledger
recovery on top of crash provenance, frozen Formal32, and six-domain work.

## Delivery scope

This repair changes only `tools/gate1a0_authority_recovery/**`,
`test/gate1a0_authority_recovery/**`, and this handoff. The narrow sixth owned
file, `lib/migration_case_catalog.dart`, contains only the literal migration
case catalog and formal 32-object schema catalog. It has no production import,
execution state machine, or I/O. All execution remains in
`synthetic_harness.dart` for one-place auditability.

No production library, SQLite/Vault/object store, network, device, credential,
or production migration is opened. Every report is `validate/simulate-only`,
`synthetic=true`, `migrationExecuted=false`, and
`migrationSimulated=true`.

## Closed-world registry and fixed sibling oracle

`SyntheticAuthorityRecoveryHarness._caseSpecs` binds exactly **202 IDs** to a
family, exhaustive operation enum, canonical result, invariant, and strict
input rule. The split is **56 authority/recovery** and **146 migration** cases.
The exact family counts are:

- authority-matrix 13;
- identity-fencing 11;
- outbox-crash 20;
- cursor-snapshot 8;
- delete-retention-mda 4;
- migration-recovery 146.

Every canonical scenario has exactly five top-level fields: `id`, `family`,
`schemaVersion`, sibling `input`, and sibling literal `expected`. Migration
`input` contains only raw legacy state, raw intent/transaction/crash facts,
observed hashes, and initial ledgers. It contains no `expectedTarget`,
`expectedRoundTrip`, expected convergence/count, expected manifest, or
`ledgersExactlyOnce` conclusion. Failure input contains only an exact raw-fact
record; the derived failure token exists only in sibling `expected.commit` and
computed evidence. Literal `expected` pins the computed result, target,
roundtrip, and commit structures. There is
deliberately no separate `expected.json`; the single `scenarios.json` is the
physical fixture while the sibling subtrees remain logical oracle boundaries.

`manifest.json` pins the exact scenario bytes and the canonical SHA-256 of the
`input` subtree for **all 202 cases**. Expected-only changes therefore leave a
case input digest unchanged and reach the post-simulation comparator, where
`actualMatchesLiteralExpected=false`. Code additionally pins
SHA-256(manifest bytes + NUL + scenario bytes) as
`e6007a58309fa36b7ef5e41da223251a2b9fb16c249a2ad084cd459b48fdc9a7`.
The runtime has no canonical migration-input or expected generator and never
calls a converter, roundtrip, or commit implementation to construct expected
data. It passes a deep copy of `input` alone to the simulator; only after the
actual structured result exists does an independent comparator read
`expected`.

During fixture maintenance, computed output was used once as a candidate for
the now-fixed literal tree; that temporary script was deleted and is not a
runtime or repository oracle. The checked-in values are reviewed by independent
contract assertions for exact sets/schemas, raw-derived counterfactuals,
blocked target absence, six-domain semantics, counts, and durable state. This
handoff therefore claims runtime/logical independence and fixed literal
pinning, not a separately authored expected file.

This prevents a fixture self-oracle. Changing raw input and literal expected
together, even while recomputing `scenarioSha` and that case's manifest input
digest, still fails the pinned whole-fixture digest. Expected-only tampering
passes the unchanged input digest boundary and fails the literal comparator.
Test-only raw simulation accepts no expected value and returns independently
computed actual/evidence; a separate test-only comparator proves the boundary.

The top-level report carries `contractVersion`, `fixtureDigest`, actual
`scenarioSha`, the exact 202-entry `caseInputDigests`, exact
family/classification/case counts, and per-case `wholeInputDigest`. Every case
has a non-empty `invariantResults` map with independently computed
`actualMatchesLiteralExpected` and `contractInvariantHeld`. A case passes only
when every value is true. `passedCases` and `allInvariantsHeld` reduce those
actual maps and cannot become true from a count constant or an empty `every()`.
The final classification counts are deterministic 87,
controlled_extension 38, degraded_preserved 5, blocked 16, and
not_applicable 56.

All schemas reject missing/extra fields, wrong types, unsupported enums,
unknown operations, ID/family/operation mismatch, and ID/phase mismatch. The
scenario ID set must equal the registry exactly. `mda-no-inference` requires a
canonical non-empty signal set. The simulator switch is exhaustive and has no
default accepted path.

## Executed authority and recovery state machines

### Acceptance A–F and ordered precheck

`crash-A` through `crash-F` execute local enqueue, Core precheck, atomic Core
event/receipt/change/idempotency acceptance, response loss, client
result/outbox transaction, and projection/cursor transaction. At the selected
phase the durable state is JSON-serialized, reconstructed, and replayed.

Precheck trace order is enforced by execution:

1. credential;
2. binding;
3. scope;
4. active Core;
5. epoch;
6. fence;
7. lineage state;
8. idempotency lookup;
9. parent/ref/resource reads;
10. commit.

Seven invalid precheck cases stop at the first invalid authority field with
zero event/receipt/change mutation, no idempotency lookup, and no resource
read. A same-key/different-digest case reaches idempotency and stops before
resource reads. Rejected zero-write cases do not report an exactly-once
violation.

Event, receipt, change, and idempotency ledgers are serializable append/count
collections rather than Sets. Same key plus same digest reuses the durable
bundle; same key plus different digest conflicts. A count=2 test injection
remains visible and produces `state_invariant_violation`. Successful replay
requires exactly one event, receipt, change, and ledger row and proves no
ghost, receipt-only bundle, outbox-before-result, cursor-ahead, or duplicate
side effect.

Snapshot validation starts from raw local state plus a snapshot envelope,
stages it, serializes/restarts, and atomically commits projection, receipt, and
cursor. Evidence carries the original cursor and original state digest;
`cursor_unchanged` compares both actual values back to those originals.
Invalid lineage/digest or a stage crash therefore turns red if either the
cursor advances or the local state is rewritten.
Delete, backup, and retention cases derive tombstone/access barrier, cleanup,
manifest exclusion/expiry, and recovery state from raw inputs. Non-empty MDA
weak signals produce zero human-state records.

## Raw-derived P5 migration simulation

The 146 migration cases cover ordinary Card/no accidental truth, authorized
truth provenance, body/title/ID conflicts, all frozen RichText block/mark/asset
and IME/history/cache cases, Source/Anchor, Evidence, TaskArtifact, the three
intake domains, formal 32-object classification, journal recovery, and full
old-new-old-new roundtrip.

`feature` is catalog routing metadata only. Conversion decisions come from raw
structured details. Card conversion compares stable ID, title, body,
authorization, and provenance. Intake executes from non-empty
stableIdentity/dedupeKey, existing/incoming digest, cancellation, parser
completion, failure phase, and restart phase. Same key plus different digest
is blocked with no target/head/digest/new manifest/receipt/change/projection or
downstream. Evidence proposal/authorization, Task promotion/partial failure,
and Anchor exact/ambiguous/orphan are likewise raw-derived.

Only Card may produce `hereiam-card-envelope-v1`. Intake, Source/Anchor,
Evidence, Task, Board/Dreaming, history, assets, and journal cases retain their
domain roles and cannot silently become Card, Claim, or User-truth. Blocked
cases preserve raw state plus a reason but have no accepted target head,
revision, new manifest, receipt, change, or projection.

RichText classification uses only `deterministic`, `controlled_extension`,
`degraded_preserved`, and `blocked`; the separate formal action is
`migrationAction`. Paragraph, heading, list, quote, code, empty, nested,
footnote, table, reference, and raw cases produce distinct concrete outputs.
Code fences are longer than the longest raw backtick run; list depth is closed
to 0..8. Strike, inline code, underline, bold, italic, and link marks use exact
UTF-16 ranges. Only `https` and `hereiam-card` links are accepted. Properly
nested marks render exact ranges; crossing marks become a controlled
extension. Raw HTML uses a separate base64 byte payload, not a Dart String.
The canonical case contains the non-UTF-8 byte sequence `FF FE 3C 00 41 80`;
conversion emits `encoding=base64`, `rawBytesBase64`, `byteLength=6`, and
SHA-256 over those exact six bytes. Recovery decodes the capsule and compares
byte-for-byte. Invalid base64, wrong length, and wrong raw-byte hash are three
distinct fail-closed controls.

The formal inventory directly consumes the exact 32-row JSON literal frozen in
`FORMAL_MIGRATION_MATRIX.md`; the converter does not reconstruct it from
defaults. Every row has exactly nine top-level keys: `objectType`,
`classification`, `stableIdMapping`, `authority`, `refs`, `rollback`,
`deleteRecovery`, `indexBackup`, and `blockedReason`. Routing-only
`targetRole`/`migrationAction` metadata remains outside the reported Formal32
inventory. Non-blocked rows require `blockedReason=""`; blocked reasons are
closed to the P5 machine allow-list.

`stableIdMapping.entries` is non-empty and every identity entry has exactly
seven keys: legacy/target kind, mode, source fields, target field, fallback
algorithm, and guard. Only `allocate_digest_if_missing` may use
`deterministic_namespace_plus_payload_sha256`; blocked/not-applicable entries
cannot emit a target ID. Rollback has four typed fields, delete/recovery four,
and index/backup three literal string arrays. The row-local values expose the
required differences: RichText cache is non-authoritative/rebuildable and only
its reversible capsule may allocate; operation/receipt/change is append-only;
derived index is rebuild-only, physically deletable, and excluded from backup;
backup media is a non-writer with retention expiry and no online rebuild.
There is no shared stable-ID, rollback, delete, or backup wrapper.

The runtime validator independently freezes the exact object order, nine-key
and nested schemas, mode/fallback rules, blocked-reason allow-list, and 32
canonical row digests. Tests deep-assert the special RichText,
operation/receipt/change, derived-index, and backup rows, mutate their literal
booleans/arrays/fallbacks, and also mutate every row authority. Synchronized
catalog/fixture changes therefore remain red unless the independently pinned
P5 contract is also changed.

### Crash/failure and commit ledgers

The P5 §9.1 catalog is represented exactly, with no coarse `stage`, `publish`,
seven-phase alias, or unknown legacy subphase. It contains **52 unique expanded
crash points**, each with one independent case, plus **26 failure cases** that
cover the exact **25 unique failure points**. The extra failure case is
required: `external_third_hash_conflict` is independently bound after
`after_file_publish:0` and `after_file_publish:1`.

Expansion is independently reconstructed from the 32 template literals and
the exact manifest/report `fixtureDimensions={files:2, objects:2,
rollbackCopies:2, projections:4, cleanupItems:2}`. The manifest and report both
emit the complete ordered `exactExpandedCrashPoints` and `exactFailurePoints`
lists. Missing, extra, or duplicate coverage is a Gate failure.

An ordered action machine executes identity precheck, idempotency, business
read, Tx-A, every stage write/fsync, directory fsync, Tx-B, every rollback
copy/fsync, publish phase, every file/object publish, activation,
invalidation, every projection start/finish, cursor, notification, response,
and every cleanup start/finish. A crash label only selects a stop boundary; it
does not directly populate report fields. Each case serializes the state
reached by the action prefix, restarts, validates granular state and hashes
against its raw-derived manifests, and only then rolls forward, rolls back, or
returns needs-resolution. Tampered publish or fsync hashes produce
needs-resolution.

Restart validation requires `actionTrace` to be the exact ordered prefix of
the frozen action machine: no unknown, missing, duplicate, or reordered action
is accepted. The validator replays that prefix from the serialized initial
ledgers and deep-compares the entire granular durable state. Thus trace derives
phase, authority checks, ordinals, hashes, projections, cleanup, and
receipt/change/projection ledgers in both directions; those fields are not
decorative report data. Paired controls clear both publish ordinal and hash,
change phase plus ordinals, keep trace while changing state, keep state while
changing trace, and clear/forge stage-fsync ordinal plus hash. Every one
converges to `needs_resolution`.

That internally valid prefix is also bound to the original scenario facts.
Recovery receives the canonical crash point and the transaction's original
initial ledgers. The embedded `initialLedgers` must deep-equal that input, and
the trace must equal the exact action prefix selected by that crash point.
Consequently, a complete valid state from `before_identity_precheck` cannot be
substituted into `after_file_publish:0`, and synchronously replacing embedded
initial ledgers plus all three current ledgers cannot create an accepted ghost
bundle. Final roll-forward is checked separately against the full action trace
while retaining the same original-ledger binding.

Ledger shape is validated before any ledger copy, initial-state construction,
or action replay. Initial ledgers must be an exact
`receipt/change/projection` map; every current and initial ledger must be a
list of exact `{key,digest}` maps with bounded non-empty strings. Malformed
durable ledgers never reach an unsafe cast: the invalid-state branch uses a
safe counter that returns zero for bad shape, reports
`convergence=needs_resolution`, and fixes `ledgersExactlyOnce=false`. In
contrast, malformed original transaction ledgers are rejected as
`inputRejected`, since they are invalid scenario facts rather than recoverable
durable corruption. No broad exception handler or malformed-as-empty
roll-forward path exists.

Durable evidence separately records stage writes/fsyncs/directory fsync,
rollback copies/fsyncs, file/object ordinals and hashes, activation,
invalidation, projection start/completion ordinals, cursor, notification,
response, and cleanup in-progress/completed ordinals. Before item `n` contains
all completed `0..n-1` items. `after_file_publish:0` and
`before_file_publish:1` have the same logical action state and include file 0's
manifest hash; the object pair has the corresponding property. Separate cases
use separate raw transactions, so their content hashes are validated against
their own manifests rather than asserted byte-equal across transactions.

All 25 failure tokens are derived from exact raw facts: ordered authority
fields, existing/incoming digest, parent/ref state, disk capacity and bytes,
permissions, YAML validity, Source hashes, external file state, observed versus
old/new hash, activation/projection/notification outcomes, and staging/rollback
manifest validity. No conclusion-style failure selector remains in input or
the canonical case catalog. Third-party conflict is specifically derived by
comparing observed hash with both old and new hashes. Receipt/change/projection
ledgers append and idempotently reuse matching entries. Injected duplicate
ledgers retain count 2 and turn the actual result red.

### Full roundtrip

The full roundtrip executes raw old baseline -> first migration -> post-cutover
new write -> rollback to legacy-readable state while retaining that write ->
remigration. It is not a deep copy with a format label: each domain encodes to
a different new physical schema/row key, rollback produces a domain-tagged
legacy-readable envelope, and remigration decodes that envelope and rebuilds
new physical rows. The five-step trace carries actual physical-state digests.
`evidence.fullRoundTrip.domains` has exactly the six P5 §9.2 keys:
`cardContent`, `userTruthSet`, `sourceAnchor`, `operationLog`,
`revisionHistory`, and `derivedIndex`.

Every domain has exactly the same ten fields:
`oldBaselineSemanticDigest`, `newAfterFirstMigrationSemanticDigest`,
`postCutoverNewWriteSetDigest`, `oldAfterRollbackSemanticDigest`,
`newAfterRemigrationSemanticDigest`, `stableIdSetDigest`,
`operationIdSetDigest`, `newWritesPreserved`, `duplicateAcceptedCount`, and
`domainInvariantHeld`. These values are computed from the actual state and
append ledgers at each stage. The derived index is rebuilt from the remigrated
accepted states of the other five domains; raw legacy index bytes cannot be
reused as its target. Top-level `allSixRoundTripDomainsHeld` is a dynamic
exact-key/ten-field/domain-invariant reduction and migration validity requires
it.

Counts are recomputed from structured revision/operation/event/truth ledgers.
Every domain, including `userTruthSet`, has a non-empty post-cutover write.
Stable-ID and operation-ID uniqueness, reference closure, non-empty write
preservation, rollback/remigration semantic equality, and differing physical
digests are computed from state. The first migration must also preserve the
old semantic digest for all six domains. `derivedIndex` obtains its comparable
baseline by rebuilding from the old accepted domain states, while its old
physical cache bytes remain distinct from the first-migration physical rows.
Stable-ID sets must be equal through the first
migration and expand only by retained post-cutover writes through rollback and
remigration. Separate injections for Card and derived-index first-migration
semantic drift, duplicate record, duplicate stable ID, duplicate operation ID,
and dangling reference make the corresponding domain and top aggregate false.

Reference closure extracts actual domain fields rather than treating arbitrary
strings as refs: User-truth checks `cardId`, Source/Anchor checks
`sourceVersionId`, revision history checks `cardId` and non-null
`parentRevisionId`, operation log checks its target, and every domain also
checks explicit `refs` against the global accepted stable-ID set. Independent
missing-ID injections cover User-truth, Source/Anchor, revision parent, and the
generic refs list.

The derived index obtains operation IDs from the deterministic union of the
currently accepted non-index domains. Baseline and first migration contain
only `operation-migrate-1`; post-cutover, rollback, and remigration naturally
contain it plus `operation-new-write-1`. No future operation is hard-coded into
the baseline. Evidence emits every stage operation set, and a first-migration
future-operation injection turns the derived-index domain and top aggregate
red.

## Negative and isolation evidence

The **20 targeted test groups** include counterexamples for:

- synchronized input/expected tampering, expected-only comparator failure,
  missing/extra literal expected fields, and converter-result drift;
- unknown operation/ID, extra/missing/type/enum/family/phase mismatch, and
  empty signals;
- invalid precheck, digest conflict, and count=2 authority ledgers;
- one actual-evidence semantic violation for every one of the 19
  non-migration operations, plus exact coverage of all 20 operation enum
  values, while each canonical literal comparator remains independently true;
- legacy bytes/head, target head/manifest, roundtrip digest/counts, formal
  catalog fields and special-row policies, commit ledgers, third-party hashes,
  every crash phase, paired trace/granular-state corruption, all 52
  different-trace whole-boundary substitutions, and synchronized ghost-ledger
  replacement, plus missing/wrong-type/bad-element/extra/missing/empty ledger
  fields across receipt, change, projection, embedded initial, and original
  input ledgers;
- raw mark/range/fingerprint, exact nested/partial-link output, crossing mark,
  unsafe/missing href, backticks, list depth 9, asset hash/storage, IME,
  intake identity/dedupe/digest/cancel/parser, Evidence/Task authorization,
  Anchor selector, and Card/truth conflicts;
- blocked target absence, intake zero downstream, full 32-row non-Card roles,
  non-UTF-8 raw-HTML base64/length/hash/bytewise recovery, and exact
  six-domain/ten-field roundtrip with real User-truth, Source/Anchor, revision,
  and generic-reference failures;
- deterministic bytes, redaction, fixture immutability, allowlist, strict
  system-temp output, production-root/non-empty-output, and link rejection.

All malformed fixtures and filesystem probes are created only under the system
temp root.

## Verification

- Format: final three Dart files formatted.
- Analyze: `No issues found!` for harness, catalog, and targeted test.
- Targeted: **20/20 test groups passed**.
- Combined old preflight plus repaired harness: **27/27 passed**.
- CLI run 1: **202/202**, 1,409,842 bytes, SHA-256
  `7E868CDDD330AE92A112A23405D6156EC006D294773FE3BD8741DD83739D78A3`.
- CLI run 2: **202/202**, 1,409,842 bytes, the same SHA-256.
- The report bytes are intentionally unchanged by this repair: canonical
  scenario states already carry their declared trace and original ledgers, so
  the new provenance checks affect only substituted/ghost recovery inputs and
  test diagnostics, not any accepted canonical outcome or fixture literal.
- Both reports: `allInvariantsHeld=true`, `migrationSimulated=true`,
  `migrationExecuted=false`, `allSixRoundTripDomainsHeld=true`,
  `contractVersion=gate1a0-synthetic-contract-v6`, 202 input digests, 52/52
  expanded crash points, and 26 cases / 25 unique failure points.
- Fixture files: manifest SHA-256
  `9D73B12A617D49AC04C90CD8F7C456199E414C0893BD24AA42F32B58164A0004`;
  scenarios SHA-256
  `30D038701AEF031494DFB854A23C1DEEDF36EF8CBD5827221A6CF76C31F1DF01`.

## Limits / next owner

This is synthetic proof of the frozen 1A-0 contract, not 1A-2 real-I/O
evidence. It does not execute a production Drift migration, real fsync/atomic
replace, filesystem watcher, actual Core process restart, third-party
filesystem mutation, real-data clone, device test, or human Gate. The modeled
journal exposes those boundaries for later fault injection, but only real I/O
tests can close 1A-2. Production authority remains unchanged.
