# Gate 1A-0 Authority Root and Acceptance ADR

> **Status:** frozen and accepted by Lynx at the Gate 1A-0 human Gate on 2026-08-30; it does **not** switch a
> production writer, schema, storage format, device, credential, or network configuration.
>
> **Authority scope:** the target Core/desktop authority root and the acceptance
> vocabulary used by the Gate 1A migration harness. “Current runtime” facts are
> called out separately and remain governed by the existing implementation until
> a later Gate explicitly changes them.
>
> **Inputs:** [Goal](../../goals/GOAL-20260830-gate1a0-authority-recovery.md),
> [Core API v0](../../../companion-first/CORE_API_V0.md),
> [Core Sync Inventory](../../../companion-first/CORE_SYNC_DATA_INVENTORY.md),
> [preflight inventory](../../data-authority-preflight/A1_CURRENT_AUTHORITY_INVENTORY.md),
> [MDA-0 activity ADR](../../activity/mda0/DEVICE_ACTIVITY_V1_ADR.md), and
> [Product Roadmap](../../../companion-first/PRODUCT_ROADMAP.md).

## Decision

The private desktop Core is the **only target authority root** for every object
in the matrix below. A client, probe, local editor, parser, or worker may create
an intent and a durable local pending record, but none may call itself accepted,
allocate a canonical change, make downstream projections authoritative, or
revive a rejected/deleted object. The Core alone authenticates the principal,
validates scope and idempotency, commits the canonical domain change, and emits
the canonical receipt/change.

`accepted` therefore has one meaning: a request has been committed by the
active Core in its accepted authority epoch and is named by its Core-issued
receipt/change. Local optimistic UI, an outbox row, a parser result, a worker
lease, an object-store write, an FTS hit, and a backup manifest are not
acceptance. They are respectively pending state, input, execution permission,
or a derived/recovery copy.

This is a **target contract**, not a claim that the current Flutter/SQLite
runtime has already become a Core service. The preflight shows current local
SQLite writers for Card, User-truth, Source and Dreaming; `CORE_API_V0.md`
defines only a limited proposed v0 chat route and expressly excludes multi-Core
authority. No existing client is authorized by this ADR to bypass its current
runtime path before Gate 1A-3.

## Shared acceptance vocabulary

| Term | Frozen meaning |
|---|---|
| `intent` | A client/probe/worker request with a stable idempotency key. It may be queued locally, but cannot be read as canonical domain state. |
| `pending` | Local durable pre-accept state, including an encrypted bounded outbox where applicable. It is neither a Card, Source, User-truth fact, accepted chat message, nor activity evidence. |
| `accepted` | Core committed the canonical domain mutation in the active authority epoch and returned/published its receipt/change. |
| `rejected` | Core refused the intent without a canonical domain mutation. A non-retryable rejection is terminal for that intent. |
| `expired` | The Core refused a stale/retention-expired intent; it cannot be silently replayed as new. |
| `needs_resolution` | Core retained neither an implicit winner nor an automatic retry path. The conflicting intent and reason stay inspectable until an authorized user/system resolution creates a new intent. |
| receipt/change | A Core-issued opaque identity binding object ID, accepted operation/revision, authority epoch, and ordering/change cursor. A receipt proves only the named acceptance, not a backup or projection completion. |
| canonical domain record | The accepted object/revision/operation held by the authority root. It is the recovery source ahead of every index, cache, export, or client view. |

### Non-negotiable invariants

1. Every accepted object has exactly one Core-issued authority ID and one
   canonical receipt/change lineage. A derived view may retain the ID but may
   not mint a rival revision or receipt.
2. One domain has one accepted writer at a time: the active desktop Core.
   Internal workers write only through that Core after workload fencing; clients
   and probes only submit scoped intent.
3. Delete, revoke, supersede, retract, and restore are canonical operations
   controlled by the matrix delete owner. A local cache delete or an object
   storage lifecycle transition cannot silently redefine domain truth.
4. A projection/index/cache/backup may lag or be rebuilt. It must expose its
   source receipt/revision or be treated as stale; it is never a fallback writer.
5. Ordinary chat and activity evidence never auto-create User-truth. User-truth
   needs an explicit recording/correction/external-data acceptance path; an
   activity conclusion needs its own user confirmation before any User-truth
   write.
6. Unknown support, unavailable Core, invalid credential, stale epoch, deleted
   target, expired intent, or an unresolved conflict fail closed to the matching
   pending/rejected/expired/needs_resolution/unknown state. They do not produce
   a second authority or infer human state.

## Acceptance matrix

All rows are target contracts unless the last column explicitly says “current
runtime fact.” “Core accepted writer” means the active authority Core, not an
arbitrary desktop process or client-side SQLite connection.

| Domain object | Authority root / stable authority ID | Only accepted writer; allowed submitters | Pre-accept state and accepted receipt/change | Projection, index, cache, backup role | Delete owner and recovery source | Rejection / `needs_resolution` boundary |
|---|---|---|---|---|---|---|
| **Card** | Core canonical neutral Card catalog; `card_id`. Target body revision is the Core-selected canonical revision. | Core DomainCommand path only. Desktop/mobile UI and AI submit the same command intent; AI has no side door. | Draft/pending command may render as pending. Acceptance returns `card_id`, revision/parent hash and Card receipt/change. | Board placement, library/search, RichText compatibility state, FTS and exports are derived; backup copies are recovery media, not writers. | Core owns card delete/restore and tombstone. Recover canonical revision/operation lineage, then rebuild projections. | No implicit User-truth promotion; stale parent hash, invalid command, deleted target or concurrent unresolved edit becomes rejected/`needs_resolution`. |
| **User-truth** | Core canonical truth relation/record and its accepted provenance; `user_truth_id` (and linked `card_id` where displayed). | Core accepts only explicit record, user correction, approved external-data flow, or explicit promotion. Chat/activity/ordinary Card creation may submit nothing for this domain. | Explicit record/correction remains pending until a truth receipt/change binds provenance and scope. | Memory review, retrieval text, summaries, FTS and UI cards are projections; never evidence that a fact was accepted. | Core owns correction/delete/restore according to truth retention. Canonical accepted operations and provenance are recovery source. | Missing explicit user authorization/provenance, automatic chat capture, automated activity inference, or ambiguous conflicting correction is rejected or `needs_resolution`. |
| **Source** | Core source catalog plus immutable content identity; `source_id`, content hash and managed object reference. | Core accepts explicit import/managed-copy/authorized promotion intents. A parser and client may upload/stage only after capability validation. | Capture/import staging is pending. Acceptance allocates `source_id` and source receipt/change only after metadata/object integrity is committed. | Object-store replicas, previews, OCR/search, board references and backup manifests are derived/recovery copies. | Core owns source deletion/quarantine/restore; canonical source metadata plus verified managed original/version lineage recovers it. | Unverified object hash, unavailable source bytes, unauthorized external copy, duplicate identity conflict, or deleted source reference is rejected/`needs_resolution`; no placeholder Source. |
| **EvidenceClaim** | Core immutable claim ledger; `evidence_id`, pointing to exact SourceVersion/Unit/Anchor. | Core accepts explicit evidence-authoring/review intents only. UI/AI may propose; no Card or parser directly writes claim truth. | Proposal/review queue is pre-accept. Acceptance emits immutable claim receipt/change. Correction is a new supersede/retract change, never in-place mutation. | Evidence Card, matrices, statistics, search and reports are read projections keyed by `evidence_id`. | Core owns retract/delete policy; recovery is immutable claim lineage plus cited SourceVersion/Anchor. | Missing precise provenance/anchor, unsupported inference, source conflict, or edit to accepted claim is rejected or `needs_resolution`. Evidence display never creates User-truth. |
| **Dreaming fragment / episode / saga** | Core relationship-memory ledger; `fragment_id` / `episode_id` / `saga_id`. | Fenced Core dreaming worker submits through Core; user-approved correction/delete is submitted as intent. Chat clients cannot write it directly. | Worker candidate is internal pending work; accepted status/change is Core-issued. | FTS, saga snapshot, relationship display and cache are projections. | Core owns delete/status/retention and recovery from accepted fragment/episode/saga lineage. | It cannot become User-truth or a neutral Card merely by display. Old worker fencing, missing source-message lineage, or user correction conflict is rejected/`needs_resolution`. |
| **TaskArtifact** | Core task-lane canonical artifact record; `task_artifact_id`, scoped to `task_room_id`. | Core accepts TaskRoom/task execution intents in the isolated task lane. Promotion is a separate explicit user-authorized Core intent. | Task draft/generated output is pending/task-local until artifact receipt/change. | Task views, previews, search and export are projections; they must retain task-lane scope. | Core owns archive/delete/restore semantics; canonical task artifact lineage is recovery source. | No automatic Card/Source/User-truth promotion. Missing user authorization, cross-lane reference or archive conflict is rejected/`needs_resolution`. |
| **Capture** | Core capture intake ledger; `capture_id`, opaque and content-minimal. | Core accepts user-initiated capture intent only; a local share sheet/client may stage it. | Local capture/outbox row is pending; accepted capture receipt records intake only. | Local form state, dedupe hints and UI queue are not Source/Card indexes; backup is recovery copy of accepted intake. | Core owns cancellation/delete and recovery from accepted capture record plus original submitted payload policy. | Invalid/unsafe payload, unavailable Core, cancelled capture or duplicate key is rejected/duplicate/expired; acceptance must not create Card, Source, User-truth, index or downstream event. |
| **ImportCandidate** | Core import work ledger; `import_candidate_id`, linked to accepted `capture_id` or explicit user creation. | Core accepts a parser/import planner intent after capture acceptance; network parser execution is explicit and per-item. | Extracted metadata/URL is pending candidate data. Candidate receipt proves queue admission, not successful import. | Dedupe/materialization status, parser diagnostics and UI queue are projections. | Core owns cancel/delete and recovery from accepted candidate state/receipt. | Parser failure, unsupported source, login/CAPTCHA/risk boundary, stale source or duplicate conflict becomes failure/`needs_screenshot`/`needs_resolution`, never a fake Source/Card. |
| **Link Inbox Item** | Core pending-link intake ledger; `link_inbox_item_id` and normalized URL/note-id dedupe key. | Core accepts explicit local extraction/normalization/dedupe intent from user-delivered text; it does not authorize discovery/search/crawling. | Locally extracted links are pending. Inbox acceptance receipt proves only durable queue admission. | Inbox UI, status counters and parser queue are projections; no Source/Evidence/Card/FTS materialization before a later successful accepted import. | Core owns cancel/remove/expiry and recovers from accepted inbox ledger. | Duplicate returns existing accepted inbox identity; inaccessible/login/CAPTCHA/blocked links require `needs_screenshot` or `needs_resolution`, with no automatic retry or hidden WebView fallback. |
| **Chat message** | Core immutable chat message log; `sync_id` plus Core `server_sequence`/message change. | User client submits `sender=user` intent; only a correctly fenced Core companion worker may submit companion messages through Core. | Device outbox/optimistic bubble is pending. Accepted/duplicate response and change feed supply canonical sequence/receipt. | Recent-window cache, UI, notifications and search are projections; client cursor/ack is replication state, not authority. | Core owns retract/delete/edit-as-new-change policy; recover from immutable accepted message/event lineage. | Same `sync_id` different canonical content, origin-sequence conflict, bad token/protocol or unavailable capability is rejected; no local message becomes accepted without Core. Ordinary chat does not write User-truth. |
| **Activity event / shadow state** | Core activity evidence ledger and per-device shadow projection; `event_id` plus Core activity receipt/change. | Scoped paired probe submits write-only intent for its bound device/probe; active Core alone accepts, stores and projects. Admin is separate. | Probe spool is pending. Core stamps receipt time and accepts only valid epoch, credential, schema, sequence, TTL and scope. | Device/person shadow state, summary client view, retention reports and diagnostics are projections; no raw event cache is authority. | Core admin/delete policy owns event/projection deletion; recover from accepted retained evidence/authorized summary according to retention, never from client silence. | Unsupported ingress, invalid scope/token, replay, epoch/fencing failure, bad coverage, TTL expiry or unavailable Core is rejected/expired/unknown. Activity never writes chat/User-truth and never treats silence/network/HR as human-state proof. |

## Current runtime facts that remain unchanged

This ADR does not rewrite the following facts; they are explicitly not evidence
that the target acceptance matrix is already implemented.

- Current Card storage is split across local SQLite `memory_cards` and
  `whiteboard_card_extras`; the preflight records `WhiteboardDriftStore` as a
  current writer and identifies the ordinary-Card-to-`user_truth` coupling as a
  migration red light.
- Current explicit User-truth writing uses `RecordOrganizerServiceV3`; ordinary
  role chat is contractually not an auto-capture path.
- Current Source and SourceVersion metadata are local SQLite structures with
  object references. Current EvidenceClaim production storage is absent.
- Current Dreaming and TaskArtifact have independent local table families.
- `CORE_API_V0.md` specifies proposed chat pairing/message/change semantics and
  same-Core worker fencing, but explicitly does not implement multi-Core
  authority, Card/Source/Activity APIs, or disaster takeover.
- MDA-0 activity documents are proposed evidence contracts. Activity ingress is
  not enabled by this ADR, and current iPhone activity ingress remains
  `unsupported` as recorded by its Goal.

## Gate boundaries

### This Gate 1A-0

This ADR freezes names, roots, accepted-writer boundaries and the matrix for
fixtures/harness review. It does not change the default runtime authority,
create an import UI, create a database migration, grant credentials, or prove
real-data migration/recovery.

### Gate 1A-1 — neutral Card / User-truth separation

1A-1 may choose and implement the neutral Card catalog and truth relation,
including stable mappings and backward compatibility. Until it passes, this ADR
does not assert that `card_id`/`user_truth_id` tables or a migration exist.

### Gate 1A-2 — Markdown Vault switch

1A-2 may activate the selected canonical Card body/revision format and the
cross-medium journal/recovery protocol. Until it passes, RichText/current
SQLite representations remain runtime facts; this ADR does not claim Markdown
is the live writer.

### Gate 1A-3 — Core intent, epoch and fencing integration

1A-3 may implement Core-only acceptance, bounded durable outboxes, credential
generations, epochs/fencing, cursor/resync and old-writer rejection. Before
that Gate passes, “Core accepted” remains the target semantic used by the
harness, not an available production endpoint for every row.

### Gate 1B and Gate 1C

1B may build basic operations/external-file loops only after Gate 1A is fully
human-approved; it must consume this contract rather than create another
writer. 1C may make backup, retention and recovery media operational and prove
them with real recovery exercises; a backup in this matrix is deliberately not
an acceptance writer or a claim that RPO/deletion recovery has been proven.

## Required review questions

The human Gate must be able to trace three timelines against this ADR:

1. A normal client/probe intent stays pending until the desktop Core assigns the
   named receipt/change, after which projections can converge.
2. Core unavailability leaves remote work pending/expired/unknown as applicable;
   it never creates local accepted Card, Source, User-truth, chat, or activity
   truth.
3. A future new Core epoch invalidates old credentials/fences. A returning old
   writer's intent is rejected or needs explicit resolution, and its cache or
   backup cannot overwrite the new accepted lineage.
