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

`pub get` was performed once by the parallel P2 worker. `pubspec.lock` stayed
unchanged, and the three generated Windows plugin files were restored to HEAD.

## Production blockers and switch Gates

This is App support for a candidate pairing field, not a production closure.
The following remain required before any Core route or ownership switch:

1. Core needs an owner-controlled provision/rotation/revocation path that binds
   an independent domain principal, generation, exact installation, scopes,
   bearer, and HMAC key. Pairing must not grant domains automatically.
2. The production launcher/pair response does not yet issue the optional block.
   An invalid block rejects that pairing attempt; a malformed block already in
   secure storage is discarded while the chat connection remains usable.
3. Domain routes remain `phone`. A separately reviewed migration must freeze,
   drain, adopt with authenticated receipts and exact IDs, reconcile, then
   explicitly switch each domain. Attachment alone cannot perform this Gate.
4. Capture consumer ownership remains legacy. Core selection still requires
   the production Gate verifier and adoption proof; the 47862 bridge remains
   active until that explicit handoff completes.
5. A clear or rotation immediately blocks subsequent signing/network starts,
   but the current runtime is not dynamically detached or rebuilt. A newly
   provisioned grant takes effect only after runtime reconstruction. A request
   already past the App preflight may finish, so Core must also enforce current
   principal generation and revocation.
6. Production endpoint compatibility, real owner provisioning, adoption
   receipts, rollback, build/install, and human/device Gates are unverified.

No PR10 uploader, lifecycle launcher, schema/generated file, maintenance path,
or production state was enabled or changed.
