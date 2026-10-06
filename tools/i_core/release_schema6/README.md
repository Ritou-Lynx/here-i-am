# Schema6 D4 candidate and explicit offline preflight

Candidate preparation and read-only preflight retain `deployment_ready:false`, `deployed:false`, `activation_supported:false`, `recovery_floor_verified:false`. The separately verified `lifecycle/start_schema6.ps1` is an owner-controlled Windows Job launcher for qualified canonical live state, with authenticated stop, native exit/Job evidence and independently retained recovery custody. Recovery and full encrypted inventory backup APIs are now packaged from the same source tree. None of these tools acts on tasks, services or a phone merely by being packaged. First adoption of the current unsupervised fixed schema4 runtime still requires a reviewed legacy handoff adapter and specific owner authorization; obtaining its lock is not a clean-stop receipt. No whole-backup activation or database overwrite is supported. See the staged runbook at `docs/development/handoffs/SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md` in the source repository.

## Candidate creation

Run in a trusted shell with Node injection variables absent. Node 24.14.1 must have SHA256 `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`.

```powershell
$env:NODE_OPTIONS=$null
$env:NODE_PATH=$null
& D:\Nodejs\node.exe .\tools\i_core\release_schema6\cli.mjs prepare C:\HereIAm\core-deploy-readiness-20261006 C:\HereIAm\schema6-candidate-NEW D:\Git\bin\git.exe
```

Use a fresh output directory. Keep the returned manifest hash outside the candidate in an owner-protected local deployment receipt. The optional fourth prepare argument is `sourceCommit` (default `HEAD`); only `HEAD` or a full 40-hex commit is accepted and resolved with Git. Both Core files and wrappers come from that same committed tree. `source_commit`, `core_commit` and `wrapper_commit` record the resolved identity. The integrated branch must contain these files before packaging. Uncommitted changes never enter the candidate; no worker-only commit object is required. Retain the source commit with the external manifest hash so any clean clone containing that integrated commit can reproduce the same files. The manifest includes every transitive local ESM dependency, the mail dispatch PowerShell dependencies, domain migration/personal-domain support, lifecycle/recovery/backup wrappers and the copied Node executable. Unlisted static dependencies and dynamic Core dependencies reject packaging; the two fixed wrappers load only manifest-verified local modules. No `.state`, keys, tokens, grants, approval content or databases are packaged. Candidate verification requires the external manifest SHA and exact inventory; do not overwrite a release to update it. Local read-only file attributes alone are not an integrity boundary: protect the release ACL and external receipt separately.

## D4 owner boundary and backup preservation

Before touching production, the owner must authorize the exact runtime switch, identify the old release/hash and state path, use the established lock-owning supervisor to stop **all** Core writers, and verify its actual clean-stop receipt. This tool cannot prove that writers stopped. Do not synthesize `offlineProof`, clear live leases, change `database_role`, delete WAL/SHM, or infer an activity recovery floor. Require existing independently retained recovery-floor evidence and backup encryption key; unknown means blocked for migration/activation, even if this limited preflight passes.

Preserve the complete old release manifest/hash, SQLite database, grants, external approvals, owner domain configuration/credentials, ordinary device credentials, pairing/relay configuration, and the independent recovery-floor/key custody. The 72 bindings live both in `historical-replay-approvals.json` and `core_metadata.historical_replay_approvals_v1`; preserve both. Never re-pair a device as part of schema migration or rewrite origin/server sequences. Phone installation identity and credential storage are outside SQLite and must retain their existing owner custody. Do not put any of these inputs or receipts containing private paths into Git.

For a production canonical-state backup, use `backup_bundle_schema6.ps1` only after the separately accepted writer handoff and checkpoint. For inspection while production continues, use separately consistent read-only SQLite backup copies and stable file copies in a new private directory; bind the spec to that copy, explicitly retain `inventory_only`, and do not claim a globally atomic or stopped production snapshot. The specification must explicitly list all nine roles and the complete old release tree, with independently retained per-file digests. See `SCHEMA6_FULL_BACKUP_20261006.md` and the deployment runbook for the exact specification. Sidecars reject; the tool never checkpoints or deletes them. A disabled component still needs its own configuration-bound evidence file. A three-file SQLite/grant/replay copy is not a complete runtime backup.

```powershell
& <fixed-release>\tools\i_core\release_schema6\backup_bundle_schema6.ps1 `
  -Operation Create -ReleaseDirectory <fixed-release> -ManifestSha256 <external-manifest-sha> `
  -SpecPath <private-inventory-json> -SpecSha256 <external-spec-sha> `
  -OutputDirectory <fresh-private-backup-directory> -KeyDirectory <fresh-private-backup-key-directory> -CreateKey
& <fixed-release>\tools\i_core\release_schema6\backup_bundle_schema6.ps1 `
  -Operation Verify -ReleaseDirectory <fixed-release> -ManifestSha256 <external-manifest-sha> `
  -ArtifactPath <encrypted-artifact> -ArtifactSha256 <external-artifact-sha> -KeyDirectory <private-backup-key-directory>
```

These are parameter templates, not executable production instructions. The wrapper verifies the fixed release before reading CurrentUser-DPAPI material, holds the blob against replacement, supplies the key only through a redirected memory pipe, and authenticates every preserved byte. No plaintext key file or live activation is offered. `RestoreInspection` authenticates the archive before writing only a fresh protected directory, then starts the actual Core in explicit immutable inspection mode on the restored database. It requires the externally retained Create `databaseInspection.dataSha256`, compares node/schema/devices and all table fingerprints, refuses business/pairing/write routes, closes the listener and confirms unchanged database bytes and no sidecars. It never executes restored launchers or writes original `source_path` destinations. Keep the backup and recovery key directories independent; do not invoke `key_custody.ps1 -Action Read` interactively or log its raw stdout. DPAPI recovery depends on the original Windows user/profile custody. Reports deliberately retain `inventory_only` and `production_completeness_not_attested:true`: encrypting a supplied inventory does not prove all dependencies were discovered or writers stopped.

`recovery_adapter.mjs` additionally creates the existing migration's verified encrypted database backup under a genuine native offline lease and an independently retained current recovery head. It never accepts an arbitrary caller boolean, callback or JSON proof. Existing schema5/6 custody cannot be synthesized from the target's own history. Schema4 genesis additionally needs a verified full runtime artifact; the fixed lifecycle entry still refuses the current legacy schema4 first handoff until its separate adapter is accepted.

An inspection restore uses the same verified wrapper:

```powershell
& <fixed-release>\tools\i_core\release_schema6\backup_bundle_schema6.ps1 `
  -Operation RestoreInspection -ReleaseDirectory <fixed-release> -ManifestSha256 <external-manifest-sha> `
  -ArtifactPath <encrypted-artifact> -ArtifactSha256 <external-artifact-sha> -KeyDirectory <private-backup-key-directory> `
  -OutputDirectory <fresh-private-inspection-directory> -ExpectedDatabaseFingerprintSha256 <Create-databaseInspection-dataSha256>
```

The restored directory is marked inspection-only and rejects normal Core startup. This is a recovery inspection, not the missing legacy-v4 production adoption or unclean repair workflow. Secondary component databases are preserved files; their inspection checks must be recorded separately.

## Baseline anchors and preflight

Make a local JSON configuration (not in the release or repository):

```json
{
  "format":"schema6-preflight-v1",
  "mode":"legacy_b3",
  "companion_reply_jobs":false,
  "activity_enabled":false,
  "domain_policy":"owner_managed",
  "database_path":"C:\\PRIVATE-OFFLINE-COPY\\i-core.sqlite",
  "approvals_path":"C:\\PRIVATE-OFFLINE-COPY\\historical-replay-approvals.json",
  "grants_path":"C:\\PRIVATE-OFFLINE-COPY\\local-transcript-grants.json"
}
```

Use `preflight_schema6.ps1 -ReleaseDirectory <release> -ManifestSha256 <externally retained hash> -ConfigurationPath <local JSON> -CompanionUploadMode legacy_b3 -CaptureBaseline` on the independently approved old offline baseline. This validates both exact nonempty 72-record sets, existing message digests/identity/event sequence, grant/current Android credential binding, clean live role and no pending/claimed phone-character jobs, then emits proposed hash anchors only. `baseline_capture_only:true` is **not approval**. Owner retains these anchors externally; do not capture a fresh baseline from a failed target just to make it pass.

Add the four returned `expected_*_sha256` fields to the local config and run the same command without `-CaptureBaseline`. `expected_bindings_sha256` canonicalizes all five fields of every binding, independent of row/file order. `expected_identity_sha256` covers node ID, cursor secret, all device rows and message/server-sequence high-water marks. `expected_grants_sha256` protects exact grant-file bytes. `expected_domain_authority_sha256` covers existing domain registry/principals/phone capabilities/primary character without altering them; schema5 has no domain authority. For schema5→6, preserve the first three anchors and get a separately reviewed domain-authority hash after the existing authorized offline migration. Do not carry the schema5 null-domain hash forward or silently approve newly introduced domain grants.

Only boolean/count/hash outputs are emitted (plus fixed error/status labels); paths, IDs, credentials, messages and JSON payloads are never printed. Either external approvals or ledger missing rejects; empty sets reject; same count but different bindings rejects; a changed history body with a stale digest rejects; changed credentials/platform or sequence collisions reject. Inputs must be quiescent, sidecar-free, plain nonlinked paths. The database is opened immutable/read-only; hashes are checked again after close. Live DB inspection with WAL is deliberately unsupported.

The explicit runtime policy for the owner-controlled launcher is `companionUploadMode:'legacy_b3'`, `companionReplyJobsEnabled:false`, `activityAdminSecret:null` and unchanged existing owner-managed domain policy. Pairing, worker, mail and activity configuration must come from explicit protected configuration, never inherited environment. The preflight wrapper drops inherited Core/Node/model/proxy/PowerShell variables before starting the pinned Node process. The dedicated lifecycle entry can start only qualified state under a real lock-owning Job/guardian. It rejects unbound prior state, incomplete clean-close evidence, injected enablement and unsupported backup activation. Actual first legacy adoption and production post-start schema/grant/replay/device checks remain separate D4 work.

## Rollback and recovery

1. Retain the failed candidate and report. Stop its writers through the owner supervisor and preserve any new data before rollback. Do not overwrite a live schema6 database with the old schema4/5 binary or snapshot.
2. Verify the retained encrypted inventory against its external artifact hash and original key custody without extracting or replacing files. Retain the original source and independently current recovery head. Same-count replacement or token rotation requires owner investigation, not re-anchoring. This package has no whole-runtime restore/activation path.
3. A `backup_read_only` whole-Core export is intentionally rejected. Existing migration/recovery verification may inspect it with a real recovery floor, but activation is unsupported. Never flip that role or forge a floor to make startup succeed.
4. `rollbackEmptyDomainSchema` is usable only through the existing trusted offline adapter with proof/key/floor and its built-in empty-domain checks. If domain data exists or authority/cursors moved, no automated downgrade is offered: retain schema6 and obtain an owner-approved recovery plan that preserves new writes.
5. Only after separate owner approval and existing supervisor checks may routing return to the exact old release and original compatible state. This runbook does not operate tasks/services/phone or claim deployment complete. Post-switch health, exact 72 duplicate replay, both senders, stable device/node identity and no reply jobs must be verified on that exact candidate.

## Test boundaries

CI uses Node 24.14.1. Run `node --test tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs`. Portable suites run in Linux CI; Windows lifecycle and DPAPI cases run in the dedicated Windows job. The read-only input validation, generic inventory validation and independent Git history tests are cross-platform and never skip on Linux. Only actual pinned Windows executable packaging/PowerShell subprocess integration is Windows-only. The synthetic source repository has independent history without the worker Core commit and proves wrappers are read from committed bytes even when its working copy changes. Linux CI remains the runtime verification authority for the portable tests; a Windows pass is not a claimed Linux run.

`inspectInputs` and `verifyInventory` are separable low-level checks for tests and review. `inspectInputs` always reports `package_verified:false`. They are not production entry points. The CLI always uses `preflight`, which requires the external manifest anchor, exact inventory and fixed Windows Node hash before and after checking inputs, and alone reports `package_verified:true`. No environment variable or command-line option selects a synthetic validator or different Node hash.
