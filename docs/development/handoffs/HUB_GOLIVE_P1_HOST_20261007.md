# Hub Go-Live P1 Core Personal-Domain Host Handoff

Date: 2026-10-07

## Result

The non-release Core source now has an explicit, default-disabled personal-domain host and local owner boundary. Importing the modules does nothing. A caller must construct a private authority registry, set every durable domain mode, and pass `host.serverOptions` to `createICoreServer`.

Implemented source:

- `tools/i_core/personal_domain_host.mjs`
  - `createPersonalDomainHost(...)`
  - `configurePersonalDomains(...)`
  - `transitionPersonalDomainMode(...)`
- `tools/i_core/personal_domain_owner.mjs`
  - `createPersonalDomainAuthorityRegistry(...)`
  - `createPersonalDomainOwner(...)`
  - explicit phone grant, rotate, and revoke
  - frozen-manifest registration, apply, durable receipt validation, and adoption report signing
- `tools/i_core/personal_domain_migration.mjs`
  - strict canonical migration digests
  - strict `i-domain-migration-v1` adoption proof sign and verify
- `tools/i_core/phone_capture_migration.mjs`
  - strict adapter from the App's frozen `i-domain-migration-manifest-v1`
    projection plus caller-supplied closed-snapshot records
  - separate freeze and apply calls; no file discovery, grant, or automatic apply
- `tools/i_core/i_core_store.mjs` and `tools/i_core/i_core_server.mjs`
  - synchronous `domainConfigure` injection after schema-6 `DomainStore` construction
- `tools/i_core/domain_store.mjs`
  - optional projection proof in adoption request identity
  - Core-HMAC adoption record and binding authenticators in durable metadata
  - `adoption_binding_digest` covered by the production receipt authenticator

## Explicit host construction

```js
const registry = createPersonalDomainAuthorityRegistry({
  coreInstanceId,
  stateAdapter: ownerControlledPrivateAdapter,
});

const host = createPersonalDomainHost({
  enabled: true,
  coreInstanceId,
  authorityRegistry: registry,
  domainModes: {
    captures: 'authoritative',
    plan_items: 'off',
    plan_weeks: 'off',
    plan_days: 'off',
  },
  verifyWebAuthorization: trustedWebVerifier,
});

const core = createICoreServer({
  databasePath,
  ...host.serverOptions,
});
```

`enabled` defaults to false. An enabled host requires schema 6, the exact Core identity, an authority registry, and either one unambiguous common `mode` or an exact four-domain `domainModes` map. Existing registration is validated and never overwritten. A persisted frozen mode remains frozen unless a trusted local caller explicitly invokes `transitionPersonalDomainMode` and then updates the next startup configuration to match.

Web actions default to denial. The host only composes an injected synchronous verifier. The current trusted implementation is `createTrustedWebAuthorizationVerifier(...)` from `tools/i_core/web_action_authorization.mjs`; key selection and trusted-UI private-key deployment remain outside this module.

## Phone owner boundary

`grantPhoneAccess` rejects an existing durable principal instead of replacing it. A successful explicit call returns the current App `domain_access` shape:

```text
protocol_version, core_instance_id, principal_id, credential_generation,
installation_id, policy_version, schema_version, token, scopes,
authorization { scheme, key_id, secret }
```

The domain token and 32-byte HMAC signing secret are independently generated. The signing secret is held only by the injected private state adapter and returned by explicit grant or rotation. It is not stored in Core domain tables. Rotation increments the durable principal generation, replaces both secrets, removes manifests signed by the old key, and makes the old token and authorization references unusable. Revocation removes the private grant and revokes the durable principal.

The default phone grant covers existing capture and planning UI scopes. Migration authority is never automatic. The owner must explicitly add `captures:owner` and `captures:adopt`, list every allowed adoption source, and provide the allowed historical origin principals. Only that explicit grant gains the `import` actor, `import_sources`, and bounded `origins`; ordinary grants remain `origin_device_only`.

The origin allowlist permits controlled adoption, read and refetch of the named
historical origins. Ordinary phone UI patch/delete still pass through the capture
business hook, which denies them unless the record origin principal or device
matches that phone principal or device. The allowlist does not bypass that check.

## Local adoption orchestration

The migration-capable phone owner principal performs adoption so the current App bearer can refetch the resulting operation through the existing domain HTTP transport. The historical record's mapped author and device remain unchanged; the phone principal is the accepting authority and is not substituted as the historical author. The synthetic end-to-end fixture uses `source_kind:claude_web_note`, record provenance `i_remember`, and an explicitly allowed `legacy-web` origin.

The executable sequence is:

1. The App freezes its source and mapped-output manifest locally.
2. The owner explicitly grants the phone principal owner/adopt scopes, both source kinds used by the migration, and the mapped historical origin allowlist. A local caller passes the App's frozen manifest and the matching closed-snapshot Core records to `freezePhoneCaptureMigration`. The adapter validates the App protocol, binding, source, 1..5000 records, exact source/target identity and revision, slot/projection references, and aggregate source/output digests before it calls `freezeAdoptionManifest`.
3. Core recomputes aggregate digests. The current contract preserves source ID and revision exactly, so each source ID/revision must equal its target ID/revision.
4. `applyAdoptionManifest({migrationId, adoptionToken, records})` authenticates the same current phone owner generation, runs every dry-run preflight, then calls `DomainStore.adoptLegacyRecord` for each exact frozen record using a projection proof bound to the private manifest and owner-phone consumer binding.
5. Core produces a report only after every production receipt is found again in `domain_receipts`, its `receipt_auth` is verified, the matching owner-principal `domain_ops` row is a local legacy adoption with the exact source, batch, mapping, projection, and HMAC record binding, the current owner generation is active, and the current record revision/tombstone still matches.
6. The returned signed `phase:'adopt'` proof has `pending_ops:0` and `conflict_count:0`. Shadow, partial, conflicting, stale-generation, forged-receipt, ordinary-create-receipt, or post-adoption-edited state cannot produce a report. A lost response is recovered by retrying the same adoption identity and durable receipt.

The App completes local verification and commit. Core does not sign separate freeze and verify phases.

The local source adapter is invoked explicitly:

```js
const frozen = freezePhoneCaptureMigration({
  owner,
  appManifest,
  legacyRecords,
  batchId,
  mappingVersion: PHONE_CAPTURE_MAPPING_VERSION,
  expiresAt,
});

const applied = applyPhoneCaptureMigration({
  owner,
  migrationId: frozen.migration_id,
  adoptionToken: phoneAccess.token,
  legacyRecords,
});
```

`legacyRecords` comes from a separately authorized closed snapshot supplied by
the caller. The adapter does not read it from disk or infer trust. The App's
`output_digest` remains the App projection digest and is never replaced with a
Core record-body hash.

## Cross-language proof contract

The proof protocol is `i-domain-migration-v1`; the reference is:

```text
mig1.<key_id>.<base64url HMAC-SHA256(canonical JSON of proof without proof_ref)>
```

Only `phase:'adopt'` is accepted. Unknown fields are rejected. Time is canonical UTC with milliseconds: `issued_at <= now`, `expires_at > now`, and lifetime at most 24 hours. There are 1 to 5000 entries, source IDs and target IDs are independently unique, and the current source-preserving contract also requires source ID/revision to equal target ID/revision.

An entry contains:

```text
source_id, source_revision, source_digest,
target_id, target_revision, is_tombstone,
adopted_op_id, receipt_id, receipt_auth, adoption_binding_digest,
output_ids, output_digest
```

`adoption_binding_digest` is a Core-secret HMAC, not a plaintext record hash. The App checks that the signed entry and refetched production receipt contain the same value and `receipt_auth`; it cannot independently calculate the Core HMAC.

The migration report intentionally uses the explicitly granted phone HMAC secret with protocol-domain separation from `uia1`. This proves transport, binding, and manifest integrity within the trusted App/Core installation. Because trusted App code holds the shared secret, it is not a verify-only signature that is unforgeable by that App. A future requirement for asymmetric Core-only report authorship needs a distinct public-key protocol and credential shape.

## Validation

Synthetic tests use temporary databases and loopback HTTP only. No production data, configuration, key, launcher, or service was read or changed.

Final scoped command covered these files:

- `personal_domain_host.test.mjs`
- `domain_adoption.test.mjs`
- `personal_data_http.test.mjs`
- `phone_ui_authorization.test.mjs`
- `web_action_authorization.test.mjs`
- `import_personal_notes.test.mjs`
- `import_local_plan.test.mjs`

Result: 53 tests passed, 0 failed.

Root integration recheck: 175/175 across the Core host, domain store/HTTP,
authorization, importer, adoption, and server suites. After adding the source
adapter, its combined adapter/host/adoption group passed 20/20. These overlap.

The additional phone capture source-adapter test passed 1/1. It uses a real
schema-6 Core owner, a current App-shaped frozen manifest, a historical Web
origin record, production adoption, and authenticated loopback operation and
current-record refetch. Invalid ID, revision, mapping version, and aggregate
digest cases are rejected, and the App output digest remains distinct from the
Core record digest.

Coverage includes default-disabled/schema-5 fail-closed behavior, mixed-mode reopen, durable frozen mismatch, real schema-6 HTTP phone create, rotation and revocation, default Web denial, injected real Ed25519 Web approval, rejected async verifier containment, principal collision, preserved historical Web origin, phone-owner operation refetch, full-record manifest binding, forged/non-adoption receipt rejection, post-adoption edit rejection, stale generation, fixed cross-language HMAC vector, old no-projection request digest compatibility, and lost-response reopen replay.

## Remaining deployment and human Gates

The source modules are executable, but production activation remains incomplete until the main window supplies all of the following:

- a protected synchronous private-state adapter and its backup/recovery policy;
- a fixed-package or installed-host configuration path that explicitly constructs this host;
- the exact four-domain startup modes and migration transition runbook;
- trusted Web UI key ownership and private-key deployment;
- owner-authorized phone migration scopes, source kinds, and historical-origin allowlist for the intended installation;
- App/Core cross-language fixture pass in the integrated tree;
- a reviewed local migration manifest and human acceptance of the final report before local commit.

No release-schema package, maintenance command, lifecycle/session launcher, or field checklist was changed here.
