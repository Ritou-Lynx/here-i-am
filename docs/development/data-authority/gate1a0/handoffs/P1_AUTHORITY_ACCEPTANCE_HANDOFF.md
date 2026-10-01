# P1 Handoff — Authority Root and Cross-Domain Acceptance Matrix

> **Work package:** `1A0-P1` in
> [GOAL-20260830-gate1a0-authority-recovery](../../../goals/GOAL-20260830-gate1a0-authority-recovery.md)
>
> **Baseline supplied by the acceptance window:**
> `v3-lab@2edaf17a3f8bb733e6ac6f54024941267d7f32a4`
>
> **Scope delivered:** documentation only. No production Dart/Flutter/SQLite,
> schema, dependency, device, external configuration, Goal, Roadmap,
> `I_PROJECT_STATE.md`, or `DEVLOG.md` changed.

## Delivered conclusion

[`AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md`](../AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md)
selects one target acceptance root: the private desktop Core. It freezes the
rule that clients/probes/workers submit intent while only the active Core emits
accepted canonical changes and receipts. It covers Card, User-truth, Source,
EvidenceClaim, Dreaming, TaskArtifact, Capture, ImportCandidate, Link Inbox
Item, chat and activity; every row names pre-accept state, accepted writer and
receipt, derived/recovery roles, deletion/recovery ownership, and
rejection/`needs_resolution` boundaries.

The ADR explicitly distinguishes target contract from current runtime facts.
In particular it does not claim that the current local SQLite writers have been
replaced, that Core API v0 has every domain endpoint, that MDA-0 ingress exists,
or that backups/recovery are operationally proven.

## Key contract points for P2/P3/P4

| Consumer | Contract to preserve |
|---|---|
| P2 identity / epoch / fencing | An accepted receipt/change is valid only in the active Core authority epoch. Old credential, old holder, old Core, or stale fencing must fail before resource lookup or projection mutation. |
| P3 outbox / cursor / deletion / recovery | `pending` is never canonical state. Cursor/ack is replication state. Delete/restore/retract are Core-owned canonical operations; caches and backups cannot revive a deleted or superseded lineage. |
| P4 fixtures / harness | Treat the matrix as the domain dictionary. Fixtures must use synthetic data only, keep `migrationExecuted=false`, assert one accepted writer/receipt per object, and exercise rejected/expired/`needs_resolution` paths without creating downstream objects before acceptance. |
| W0 integration | Preserve the explicit `target` versus `current runtime` labels. Do not silently turn an ADR choice into an implementation claim, nor broaden 1A-0 into 1A-1/1A-2/1A-3, Gate 1B, or 1C. |

## Open risks and required cross-package decisions

1. The neutral Card catalog, User-truth relation, physical IDs and migration
   mapping are deliberately deferred to 1A-1. The matrix uses target names,
   not claims of existing schema.
2. The canonical Card body format and cross-medium intent/journal/recovery
   phases are deferred to 1A-2; current RichText/SQLite behavior remains a
   runtime fact until then.
3. Core credential generations, instance identity, fencing, outbox capacity and
   TTL, cursor/watermark resync, and disaster takeover are the P2/P3/1A-3
   boundary. P1 does not invent an endpoint or persistence layout.
4. Source object lifecycle, EvidenceClaim schema, import parsing, Link Inbox UI,
   and all activity ingress are future work. MDA-0 remains proposed and iPhone
   activity ingress remains unsupported; neither can be represented as accepted
   runtime data.
5. Retention windows, backup implementation, real restore drills and deletion
   propagation are Gate 1C evidence. This matrix supplies owner/source
   semantics, not a fulfilled recovery promise.

## Verification performed

- Reviewed the Goal, Product Roadmap, Core API v0, Core Sync Inventory,
  authority-preflight A1 inventory/options/matrix, and MDA-0 activity Goal/ADR.
- Checked that all 11 required domains appear exactly once in the acceptance
  matrix and that every row includes the requested authority, writer,
  pre-accept, receipt/change, derived/recovery, delete/recovery, and failure
  fields.
- Markdown relative links and `git diff --check` remain for W0 to run after all
  shared-worktree writers finish; this package does not modify any other path.

## Suggested main-window next action

Cross-audit P2 and P3 against the definitions in the ADR before releasing P4.
Reject any fixture or contract that lets an outbox, local SQLite row, parser
result, cache, projection, backup, ordinary chat, or activity signal appear as
accepted User-truth/Card/Source state without the Core receipt/change.
