# Schema6 D4 candidate and explicit offline preflight

This package is a **candidate preparation / read-only preflight tool**, not a deployment launcher. It creates no listener, task, service, worker or phone connection. No `Start`, `Apply`, migration, rollback or backup-activation command exists. A passing report always has `deployment_ready:false`, `deployed:false`, `activation_supported:false`, `recovery_floor_verified:false`. It must not be used as evidence that D4 production deployment or recovery is complete.

## Candidate creation

Run in a trusted shell with Node injection variables absent. Node 24.14.1 must have SHA256 `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`.

```powershell
$env:NODE_OPTIONS=$null
$env:NODE_PATH=$null
& D:\Nodejs\node.exe .\tools\i_core\release_schema6\cli.mjs prepare C:\HereIAm\schema62-compat-20261006 C:\HereIAm\schema6-candidate-NEW D:\Git\bin\git.exe
```

Use a fresh output directory. Keep the returned manifest hash outside the candidate in an owner-protected local deployment receipt. The optional fourth prepare argument is `sourceCommit` (default `HEAD`); only `HEAD` or a full 40-hex commit is accepted and resolved with Git. Both Core files and wrappers come from that same committed tree. `source_commit`, `core_commit` and `wrapper_commit` record the resolved identity. The integrated branch must contain these files before packaging. Uncommitted changes never enter the candidate; no worker-only commit object is required. Retain the source commit with the external manifest hash so any clean clone containing that integrated commit can reproduce the same files. The manifest includes every transitive local ESM dependency, the mail dispatch PowerShell dependencies, domain migration/personal-domain support, all release wrappers and the copied Node executable. Dynamic/unlisted JS dependencies reject packaging. No `.state`, keys, tokens, grants, approval content or databases are packaged. Candidate verification requires the external manifest SHA and exact inventory; do not overwrite a release to update it. Local read-only file attributes alone are not an integrity boundary: protect the release ACL and external receipt separately.

## D4 owner boundary and backup preservation

Before touching production, the owner must authorize the exact runtime switch, identify the old release/hash and state path, use the established lock-owning supervisor to stop **all** Core writers, and verify its actual clean-stop receipt. This tool cannot prove that writers stopped. Do not synthesize `offlineProof`, clear live leases, change `database_role`, delete WAL/SHM, or infer an activity recovery floor. Require existing independently retained recovery-floor evidence and backup encryption key; unknown means blocked for migration/activation, even if this limited preflight passes.

Preserve the complete old release manifest/hash, SQLite database, grants, external approvals, owner domain configuration/credentials, ordinary device credentials, pairing/relay configuration, and the independent recovery-floor/key custody. The 72 bindings live both in `historical-replay-approvals.json` and `core_metadata.historical_replay_approvals_v1`; preserve both. Never re-pair a device as part of schema migration or rewrite origin/server sequences. Phone installation identity and credential storage are outside SQLite and must retain their existing owner custody. Do not put any of these inputs or receipts containing private paths into Git.

After a real clean stop and SQLite checkpoint through the existing owner procedure, use these commands only on the confirmed offline source. They reject sidecars instead of deleting or checkpointing them. Change the three explicit placeholders locally; use a new protected destination on a non-synced disk.

```powershell
$sourceState='C:\OWNER-SELECTED-OFFLINE-STATE'
$backup='C:\OWNER-SELECTED-PRIVATE-BACKUP-NEW'
$names=@('i-core.sqlite','local-transcript-grants.json','historical-replay-approvals.json')
if(Test-Path -LiteralPath $backup){throw 'fresh backup directory required'}
foreach($suffix in @('-wal','-shm','-journal')){
  if(Test-Path -LiteralPath (Join-Path $sourceState ('i-core.sqlite'+$suffix))){throw 'offline checkpoint required'}
}
foreach($name in $names){if(-not(Test-Path -LiteralPath (Join-Path $sourceState $name) -PathType Leaf)){throw 'required input missing'}}
New-Item -ItemType Directory -Path $backup | Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $backup /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F'
if($LASTEXITCODE -ne 0){throw 'backup ACL failed'}
$receipt=foreach($name in $names){
  $source=Join-Path $sourceState $name
  $before=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  Copy-Item -LiteralPath $source -Destination (Join-Path $backup $name)
  $copied=(Get-FileHash -LiteralPath (Join-Path $backup $name) -Algorithm SHA256).Hash
  $after=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  if($before -ne $copied -or $before -ne $after){throw 'snapshot changed'}
  [pscustomobject]@{file=$name;sha256=$copied}
}
$receipt | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $backup 'input-hashes.json')
```

The protected files above are a local offline rollback set, not the `backup_read_only` encrypted whole-Core export and not a claim of cross-machine portable recovery. Keep them under the user's disk encryption and ACL policy. `domain_migrate.mjs` additionally creates its verified encrypted backup when the existing trusted supervisor calls `migrateDomainSchema` with genuine `offlineProof`, independently retained `activityRecoveryFloor`, 32-byte `backupKey` and private `backupDirectory`. Its ordinary CLI only inspects. This package does not supply a production proof adapter or bypass that boundary.

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

The explicit runtime policy for the future owner-controlled launcher is `companionUploadMode:'legacy_b3'`, `companionReplyJobsEnabled:false`, `activityAdminSecret:null` and unchanged existing owner-managed domain policy. Pairing, worker, mail and activity configuration must come from explicit protected configuration, never inherited environment. The preflight wrapper drops inherited Core/Node/model/proxy/PowerShell variables before starting the pinned Node process. This package **does not start that runtime**. Production supervisor locking, clean stop/start receipts, recovery-floor validation and exact post-start schema/grant/replay/device checks remain D4 integration work.

## Rollback and recovery

1. Retain the failed candidate and report. Stop its writers through the owner supervisor and preserve any new data before rollback. Do not overwrite a live schema6 database with the old schema4/5 binary or snapshot.
2. Stage the complete previously retained SQLite + approvals + grants set into a **new protected offline directory** using the copy/hash procedure above. Compare against the original externally retained input-hashes, manifest and identity/grant/binding anchors; run preflight on the staged set. Keep the old source set untouched. Same-count replacement or token rotation requires owner investigation, not re-anchoring.
3. A `backup_read_only` whole-Core export is intentionally rejected. Existing migration/recovery verification may inspect it with a real recovery floor, but activation is unsupported. Never flip that role or forge a floor to make startup succeed.
4. `rollbackEmptyDomainSchema` is usable only through the existing trusted offline adapter with proof/key/floor and its built-in empty-domain checks. If domain data exists or authority/cursors moved, no automated downgrade is offered: retain schema6 and obtain an owner-approved recovery plan that preserves new writes.
5. Only after separate owner approval and existing supervisor checks may routing return to the exact old release and original compatible state. This runbook does not operate tasks/services/phone or claim deployment complete. Post-switch health, exact 72 duplicate replay, both senders, stable device/node identity and no reply jobs must be verified on that exact candidate.

## Test boundaries

CI uses Node 24.14.1. Run `node --test tools/i_core/release_schema6/release.test.mjs`. The read-only input validation, generic inventory validation and independent Git history tests are cross-platform and never skip on Linux. Only actual pinned Windows executable packaging/PowerShell subprocess integration is Windows-only. The synthetic source repository has independent history without the worker Core commit and proves wrappers are read from committed bytes even when its working copy changes. Linux CI remains the runtime verification authority for the portable tests; a Windows pass is not a claimed Linux run.

`inspectInputs` and `verifyInventory` are separable low-level checks for tests and review. `inspectInputs` always reports `package_verified:false`. They are not production entry points. The CLI always uses `preflight`, which requires the external manifest anchor, exact inventory and fixed Windows Node hash before and after checking inputs, and alone reports `package_verified:true`. No environment variable or command-line option selects a synthetic validator or different Node hash.
