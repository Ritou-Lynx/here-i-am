# Hub Go-Live P1 App handoff — 2026-10-07

## Result

The existing capture lifecycle implementation already covered the requested
`claude_web` behavior: a source revision updates the same generated card,
explicit source deletion removes only untouched generated output, and hidden,
permission-denied, empty, or unavailable views do not imply deletion. Those
paths were retained and re-run rather than reimplemented.

This change closes the App-side authorization gap that previously made the
real Core adapters impossible to configure safely:

- the wire parser remains backward-compatible with an optional scoped
  `domain_access` block, but chat pairing neither advertises that capability nor
  persists the block. Domain authority is imported only through the separate
  owner-controlled workflow, and the chat device token is never accepted as
  its bearer;
- the block is parsed strictly (binding IDs, generation, schema, scope
  whitelist and uniqueness, 32-byte canonical base64url HMAC secret) and is
  persisted separately in secure storage;
- captures and the three planning domains are attached only when their explicit
  read/ack scopes exist, using the independent bearer and current installation
  binding; attachment does not change a route or capture consumer owner;
- quick-capture create/patch and planning status actions sign the complete final
  intent after `op_id`, base revision, timestamps, and TTL are fixed, in the
  same database transaction as the outbox and UI evidence;
- the signature is
  `uia1.<key_id>.<base64url(HMAC-SHA256(canonicalJson(payload)))>`, where payload
  is `{protocol:'i-domain-ui-v1',domain,binding,intent}` and `intent` excludes
  `authorization_ref`;
- signed operations persist an authorization-sealed marker. Their base cannot
  be rewritten during first-send preparation, and a new signed action with an
  unresolved predecessor is rejected instead of being automatically re-signed;
- every later signature and HTTP domain request rechecks the complete secure
  connection/grant identity. Clear or credential rotation fails closed with
  `binding_changed`; it does not retarget or use the captured token;
- secure-storage read or optional domain attachment failure is contained at the
  optional startup boundary, reports only `hub_domain_access_unavailable`, and
  leaves the phone-local Hub entry usable; database initialization and runtime
  construction errors remain outside that boundary;
- capture ownership remains legacy by default. The port 47862 bridge is
  unchanged, and no second consumer is enabled.

The follow-up source candidate also adds an explicit, inert owner migration
workflow. It does not run at startup or from pairing:

- a legacy lease freezes the latest unique `external_note_import` receipts and
  the complete current card/source/field/link/relation/asset projection;
- pre-baseline slots, duplicate latest receipts, corrections, user-corrected
  fields/relations, changed/missing outputs, ambiguous ownership, and all old
  finance projections without an immutable creation witness block the whole
  migration. Current rows are never hashed and relabeled as generated history;
- Core's single `phase: adopt` report uses `i-domain-migration-v1`, strict
  binding/shape/time rules, owner+adopt scopes, and a domain-separated `mig1`
  HMAC. The App and Core fixed vector has the same canonical MAC;
- commit requires a typed, authenticated current Core operation/receipt
  refetch for every entry. It checks target/source IDs and revisions, Core,
  principal, policy, op, receipt ID/auth, and `adoption_binding_digest`;
- the final manifest is recomputed under the capture fence. Lifecycle ledgers,
  durable owner proof, consumer binding, owner=`core`, and route=`core` commit
  in one SQLite transaction. Any mismatch leaves the migration frozen with
  legacy/phone ownership;
- the seeded lifecycle retains the verified legacy projection source, so the
  first Core replica does not duplicate cards and later `i_remember` revisions
  and tombstones reuse the existing slots. User edits remain protected;
- a completed adoption records the time it was verified. Historical report
  expiry is enforced at first commit, while later Core consumption rechecks the
  atomic attestation, HMAC, full current credential binding, and revocation;
- proof freshness is rechecked after receipt/record refetch and synchronously
  inside the final transaction, so a slow Gate cannot cross expiry and commit;
- pairing and disconnect now explicitly rebuild the Hub runtime after the old
  sync pass drains. A public rebuild entry exists for an owner-controlled
  credential rotation/revocation path; it does not switch routes itself.

The product settings page now exposes that inert source workflow explicitly:

- domain authorization is imported only from the exact protected Core CLI
  envelope `i-core-domain-access-export-v1`; raw grants and unknown fields are
  rejected, the input is masked, and token/HMAC material is never rendered or
  logged. A successful paste import makes a best-effort clipboard clear;
- before the first grant, the page copies a credential-free
  `i-core-phone-installation-binding-v1` containing the paired Core and the
  current App installation/device ID for the owner CLI. After authorization it
  copies `i-core-domain-access-binding-v1` with the principal for explicit
  rotate/revoke. The App uses one installation identity for pair `device_id`
  and domain `installation_id`, and now rejects a pair response that returns a
  different device ID;
- import requires the current chat-paired Core and current installation ID,
  keeps the domain bearer separate from the chat token, permits rotation only
  for the same Core/principal/installation with a higher generation, and
  rebuilds the Hub runtime immediately;
- revoke deletes only the independent domain grant, rebuilds the runtime, and
  leaves chat pairing, records, owner and route unchanged. It never falls back
  from an already selected Core owner to the legacy consumer;
- the settings workflow derives the legacy source instance from a stable hash
  of the configured Web-note root and takes its cursor from secure storage. A
  user cannot type source identity, cursor, record eligibility or a Gate bool;
- freeze returns the exact
  `i-core-capture-migration-manifest-export-v1` envelope and copies only the
  credential-free manifest. A frozen manifest can be exported again after an
  App restart;
- commit accepts only `i-core-capture-migration-proof-v1`, then runs the real
  HMAC verification, authenticated operation/current-record refetch, fenced
  manifest rebuild, lifecycle seeding and atomic owner+route commit. Abort is
  a separate explicit action and preserves legacy/phone ownership;
- a grant rotation never silently rewrites an existing Core route. If a route
  or committed capture owner is bound to an older generation, import stores
  the new credential, revokes old runtime use, reports the blocked route, and
  waits for a separately defined binding-rotation proof.

## Audit matrix

| Requirement | Source behavior | Synthetic evidence |
| --- | --- | --- |
| `claude_web` revision updates original card | stable source/output identity with version-aware in-place reconcile | `claude_web_note_feed_test.dart`, `capture_lifecycle_test.dart` |
| explicit deletion removes untouched generated output | tombstone/delete lifecycle only removes source-generated output whose snapshot still matches | `quick_capture_adapter_test.dart`, `capture_lifecycle_test.dart` |
| user-modified output survives source deletion | mismatch becomes a pending issue; user content remains | `quick_capture_adapter_test.dart`, `capture_consumer_ownership_test.dart` |
| hidden, denied, empty, or lost cache is not deletion | only an authenticated tombstone drives deletion; stale/empty snapshots preserve current state | `capture_lifecycle_test.dart`, `domain_sync_test.dart` |
| side-key capture uses the configured Core path | optional scoped capture store/transport and final-intent issuer are injected into the existing runtime; without the grant it stays phone-local | `domain_access_test.dart`, `personal_data_hub_runtime_test.dart` |
| Organizer consumes captures once | current consumer remains attached to the selected capture store; legacy/Core ownership fencing remains single-owner | `quick_capture_adapter_test.dart`, `capture_consumer_ownership_test.dart` |
| planning status is a direct trusted UI action | only `完成`/`放弃` status patches with matching item/status evidence are signed | `domain_access_test.dart`, `planning_service_test.dart` |
| clear/rotation revokes future App use | signer and HTTP transport re-read and compare the secure connection before each action/request | `domain_access_test.dart` |
| optional keystore failure keeps local capture available | optional credential loader returns no domain access and the runtime starts with its phone store | `personal_data_hub_runtime_test.dart` |
| evidence and outbox stay atomic | an outbox save fault after planning evidence insertion rolls back both | `planning_service_test.dart` |
| legacy owner migration is explicit and atomic | freeze/recompute/adopt/refetch/seed-ledger/owner+route commit; abort remains explicit | `capture_owner_migration_test.dart` |
| unverifiable history is not promoted | legacy slots, current mutations, duplicate receipts, and finance without immutable witness block | `capture_owner_migration_test.dart` |
| adopted captures remain one consumer | first Core revision is not re-extracted; later revise/delete reuse slots and preserve user edits | `capture_owner_migration_test.dart`, `capture_lifecycle_test.dart` |
| App/Core proof bytes agree | literal Core vector produces the same final `mig1` HMAC in Dart | `capture_owner_migration_test.dart`, Core `personal_domain_host.test.mjs` |
| protected grant lifecycle has a product caller | exact wrapper import, same-binding generation rotation, revoke, runtime reload and chat/domain credential separation | `core_domain_workflow_test.dart` |
| migration has a product caller | settings freeze/export, strict proof envelope, fresh refetch commit and explicit abort use the production workflow service | `capture_owner_migration_test.dart`, `core_sync_settings_page.dart` |

## Verification

No production service, database, credential, phone installation, route change,
or consumer takeover was used.

- focused authorization/planning/runtime/capture/protocol set: **52/52 passed**;
- adjacent `claude_web`, capture lifecycle, finance lifecycle, consumer
  ownership, domain sync, connection store, and protocol set: **131/131 passed**;
- post-revocation focused signer/transport plus full domain-sync set:
  **74/74 passed**;
- final startup fallback, four clear/rotation guard windows, and authorization
  rollback set: **37/37 passed**;
- bounded Flutter analysis of the 15 changed source/test files: **no issues**.
- owner-migration plus adjacent ownership/lifecycle/finance/domain/runtime/
  protocol regression set after the follow-up: **91/91 passed**.
- final migration boundary/fault set after the size guard, rollback fixture,
  and slow-refetch expiry check: **8/8 passed**; bounded analysis: **no issues**.
- product workflow grant/rotation/revoke and migration-envelope set:
  **13/13 passed**, including same-grant retry after a runtime rebuild failure.
- adjacent domain authorization, secure connection store and sync protocol set
  together with the product workflow: **36/36 passed**.

`pub get` was performed once by the parallel P2 worker. `pubspec.lock` stayed
unchanged, and the three generated Windows plugin files were restored to HEAD.

## Production blockers and switch Gates

Root independently reran the final eight-file App regression group after all
size, rollback and expiry fixes: **94/94 passed**. Analysis of the twelve final
source/test files reported **no issues**. Earlier groups above overlap.

The Core source now includes the owner CLI and the phone migration bridge that
join the exact App manifest to explicitly supplied historical records. The App
settings page now supplies the matching import/export/commit/abort caller. No
production grant, manifest, proof or route transition was used.

The cross-end wrappers are aligned: Core `grant-phone --binding` accepts the
App's installation binding and verifies its device in the durable registry;
Core rotate/revoke accept the App's principal-bearing domain binding. Owner
policy still selects principal/scopes separately, so the phone cannot grant
itself authority.

This is App support for a candidate pairing field, not a production closure.
The following remain required before any Core route or ownership switch:

1. Core source has an owner-controlled grant/provision CLI that binds an
   independent domain principal, generation, exact installation, scopes,
   bearer, and HMAC key. Production still needs an operator-approved run,
   protected transfer of its output file to this App import page, and verified
   deletion/retention handling for that file. Pairing must not grant domains
   automatically.
2. No production grant should be imported and no migration should begin before
   the planned post-2026-10-17 deployment window, the fixed package is
   installed, the Core URL/TLS reachability is verified, and the owner confirms
   the displayed Core/principal/installation binding. These are human/device
   Gates, not properties of synthetic tests.
3. The configured App caller refetches the migration-capable phone principal's
   durable operation and current record/tombstone. Production owner tooling
   must use that same phone principal for adopt/apply and preserve the explicit
   legacy-origin allowlist; any 401/403/404/410 mismatch/unknown or changed
   revision must be treated as a blocked commit, never an instruction to retry
   with weaker evidence.
4. No production manifest has been created and no owner/route was switched.
   Existing pre-baseline or finance rows may correctly block with aggregate
   `capture_migration_unresolved` / `finance_origin_unverified`; resolving them
   needs a separate evidence-preserving product decision, not weaker checks.
5. Import/revoke now invoke runtime rebuild and subsequent operations recheck
   the secure binding. A generation rotation while a Core route/owner is already
   committed deliberately pauses that route: a signed old-to-new binding
   rotation attestation and atomic owner/route rebinding contract are still
   required before continuity across such a rotation can be claimed. The new
   grant is never used to silently rewrite historical ownership proof.
6. The executable source migration currently covers captures. Planning-domain
   source
   migrations, real fixed-package compatibility, rollback/recovery UX,
   build/install, production Core CLI execution, and human/device Gates remain
   unverified. The 47862 bridge stays the sole legacy consumer until an
   explicitly authorized, successful commit; after commit the seeded lifecycle
   and owner fence keep exactly one consumer.

No PR10 uploader, lifecycle launcher, schema/generated file, maintenance path,
or production state was enabled or changed.
