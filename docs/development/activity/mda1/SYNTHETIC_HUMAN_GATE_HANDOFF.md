# MDA-1 synthetic three-probe human-review harness handoff

## Scope

This isolated worktree adds only `tools/i_core/run_mda1_human_gate.mjs` and its
Node test.  It creates a fresh local SQLite Core in a uniquely owned system
temporary directory, binds only loopback HTTP, and removes that exact directory
after closing its Core.  Cleanup records the original lexical path, canonical
path, and file identity; a later junction/symlink, different canonical target,
or file-identity replacement is refused rather than recursively removed.
The exact lexical handle is registered immediately after `mkdtemp`; later
identity-read or canonical-binding failure therefore reaches cleanup as either
an exact safe removal or a fixed failed cleanup result.

## Evidence

The explicit `--human-gate` run exercises one reader and three fixed synthetic
probe identities: accepted/replayed events, least-privilege denials, individual
revocation, clean Core restart, conservative restart gap, fresh recovery, and
reader-visible accepted changes.  Its report is intentionally fixed and
redacted: no credentials, transport material, IDs, paths, URLs, receipts, or
error text are emitted.

The successful report is derived from the verified runtime ledger, including
the three probe rows and request counts.  Passing requires both the final Core
close and exact-owned cleanup to be confirmed; both fixed statuses are included
in every safe report.  A close failure reports only
`teardown_close`; a deletion error or remaining directory reports only
`teardown_cleanup`; an earlier business failure retains its own fixed check.
Every summary and changes view is checked for the no-sleep semantics and for
the closed state vocabulary.  Reader change pages verify contract/schema,
strictly increasing server sequence, complete-page cursor continuity, and the
accepted synthetic lineage; internal owner exports independently verify the
same exact event set at initial, restart, and final points without exposing it.
The expected set is created only after pairing, with each issued full event ID
and origin sequence retained in memory; reader changes and owner exports reject
a matching numeric suffix under any different prefix.

For the network-only probe, the current Core exposes restart uncertainty as
`state=unknown`, `coverage_status=core_restart_gap`, and `clock_health=unknown`.
Its source `status_reason=reachability_only` remains the network-kind label and
is never treated as fresh coverage or a human-state conclusion.

`passed_awaiting_human_acceptance` means the synthetic harness passed.  It is
not a human Gate pass, Android/device Gate, sleep inference, or authorization
to proceed to MDA-2.

This candidate supports clean-close, same-path Core restart and offline
integrity verification of a restored backup.  A formal backup is intentionally
a whole-Core read-only verification artifact: even when activity is dormant,
it cannot be launched as a writable chat Core.  Writable backup activation,
crash takeover, and migration recovery remain deferred to Gate 1A-3/1C.  Human
acceptance of this MDA-1 candidate includes that explicit compatibility boundary.

Known non-blocking P2: if Core startup fails during listen/activation and its
internal startup cleanup itself fails, the whole harness still returns `failed`, but
the server's idempotent no-op close can make that failed report's `close` field
look `confirmed`.  This path cannot produce a passing report; it remains an
honest resource-diagnostic limitation and must not be described as proof that
every startup-failure resource was closed.

## Human acceptance

On 2026-09-06, after reviewing the three-probe report, the three disclosed
non-blocking P2 items, and the whole-Core read-only backup boundary, Lynx
explicitly replied `通过`.  The MDA-1 human Gate is therefore PASS for the fixed
functional candidate `fbcbceb0`.  This acceptance does not convert the harness
output itself into device evidence and does not authorize a `v3-lab` merge,
MDA-2, a real collector, sleep inference, or intervention.

## Verification and commit exception

- `node --test tools/i_core/run_mda1_human_gate.test.mjs` passed: 11/11.
- `node --test --test-reporter=dot tools/i_core/activity_control_plane.test.mjs` passed with the existing Windows case-sensitive-path skip.
- `node tools/i_core/run_mda1_human_gate.mjs --human-gate` returned the safe pending-human report; `git diff --check` passed.

The integration window independently repeated the 11/11 suite and explicit CLI
on `codex/mda1-activity-core@fbcbceb0`; the report again had
`close=confirmed`, `cleanup=confirmed`, and `human_acceptance_pending`.

This isolated worker commit uses the authorized `SKIP_PROJECT_STATE=1` exception.
The integration window remains responsible for project-state and DEVLOG updates.
