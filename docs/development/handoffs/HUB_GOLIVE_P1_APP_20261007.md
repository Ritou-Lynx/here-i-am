# Hub Go-Live P1 App handoff — 2026-10-07

## Result

The existing capture lifecycle implementation already covered the requested
`claude_web` behavior: a source revision updates the same generated card,
explicit source deletion removes only untouched generated output, and hidden,
permission-denied, empty, or unavailable views do not imply deletion. Those
paths were retained and re-run rather than reimplemented.

This change closes the App-side authorization gap that previously made the
real Core adapters impossible to configure safely:

- pairing may carry an optional, separately scoped `domain_access` candidate
  block; the chat device token is never accepted as its bearer;
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

`pub get` was performed once by the parallel P2 worker. `pubspec.lock` stayed
unchanged, and the three generated Windows plugin files were restored to HEAD.

## Production blockers and switch Gates

Root independently reran the final eight-file App regression group after all
size, rollback and expiry fixes: **94/94 passed**. Analysis of the twelve final
source/test files reported **no issues**. Earlier groups above overlap.

The Core source now includes `freezePhoneCaptureMigration` and
`applyPhoneCaptureMigration` to join this exact App manifest to explicitly
supplied historical records. The adapter is inert; product UI, secure transfer
and production orchestration still require integration.

This is App support for a candidate pairing field, not a production closure.
The following remain required before any Core route or ownership switch:

1. Core source now has an owner-controlled grant/provision entry that binds an
   independent domain principal, generation, exact installation, scopes,
   bearer, and HMAC key. Production still needs explicit owner configuration,
   secure grant delivery, rotation/revocation wiring, and operational approval;
   pairing must not grant domains automatically.
2. The production launcher/pair response does not yet issue the optional block.
   An invalid block rejects that pairing attempt; a malformed block already in
   secure storage is discarded while the chat connection remains usable.
3. The capture migration workflow has no product/UI caller. The configured
   domain access exposes a real authenticated refetch adapter that queries the
   owner principal's durable operation and then the current record/tombstone;
   any 401/403/404/unknown or changed revision blocks commit. Production owner
   provisioning must make that same migration-capable phone principal perform
   adoption so its token may query the op. No default-true callback or implicit
   takeover exists.
4. No production manifest has been created and no owner/route was switched.
   Existing pre-baseline or finance rows may correctly block with aggregate
   `capture_migration_unresolved` / `finance_origin_unverified`; resolving them
   needs a separate evidence-preserving product decision, not weaker checks.
5. Runtime rebuild is invoked by current pair/disconnect and is callable by a
   future owner lifecycle. The production owner provision/rotation/revocation
   path still must call it and Core must reject already in-flight use after
   generation revocation. The method never performs migration or takeover.
6. The executable migration currently covers captures. Planning-domain source
   migrations, real fixed-package compatibility, rollback/recovery UX,
   production workflow invocation, build/install, and human/device Gates remain
   unverified. The 47862 bridge stays the sole legacy consumer until an
   explicitly authorized, successful commit.

No PR10 uploader, lifecycle launcher, schema/generated file, maintenance path,
or production state was enabled or changed.
