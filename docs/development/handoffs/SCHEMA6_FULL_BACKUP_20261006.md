# Schema 6 full runtime backup worker handoff (2026-10-06)

## Scope and evidence

This work package implements an explicit-inventory encrypted runtime preservation artifact. It does not acquire or attest an offline writer lease, start/stop production, activate a backup, overwrite a database, or supply a schema downgrade. All exercised data/configuration/keys were generated in synthetic temporary roots. The integration owner retains package/CLI/CI/global-state ownership; dependency files copied into this worker checkout are excluded from this commit.

## API

- `createRuntimeBackup({spec, outputDirectory, key})`: fresh owner/System-protected output directory; returns verified report plus `artifactPath`, `artifactSha256`.
- `verifyRuntimeBackup({artifactPath, artifactSha256, key})`: independently retained ciphertext digest is mandatory, then AES-256-GCM authentication and every encrypted inventory entry SHA-256/length are verified. No extraction or plaintext staging file is created.
- `verifyInitialRuntimeBackup({artifactPath, artifactSha256, key, databasePath, nodeId})`: additionally requires schema 4, matching encrypted canonical path/node and encrypted database digest equal to the current stable database bytes; actual read-only database metadata/integrity is checked. Returns `verified`, `databaseSha256`, `nodeId`, `databasePath`, `sourceSchema:4`, `artifactSha256`, `inventorySha256`, and the restrictive scope flags. It accepts no caller boolean proof.

All keys are independent 32-byte binary values supplied in memory. Reusing the source Core cursor secret is rejected. The report always says `scope:inventory_only`, `production_completeness_not_attested:true`, `activation_supported:false`.

## Explicit source specification

`spec` has exactly `format:'i-core-runtime-backup-spec-v1'`, `source_schema:4|5|6`, `node_id`, `canonical_database_path`, `old_release_root`, `old_release_manifest_sha256`, and `entries`.

Every entry has `role`, relative logical `name`, absolute `source_path`, and externally retained lowercase `sha256`; optional `state` is `present` or `disabled`. Required roles: `database`, `release`, `configuration`, `task`, `credentials`, `domain_policy`, `transcript_grants`, `replay_approvals`, `recovery_custody`. The database role is singleton. Names and physical source paths cannot be reused across roles; hardlinks also reject. Release entries must enumerate the entire old release tree, including its manifest, private launchers and empty files, with names equal to the tree-relative path. Both tree membership and bytes are checked again after streaming.

A disabled task/credentials/domain-policy/grants/replay component must still have its own inventoried nonempty controlled evidence file: `{format:'i-core-runtime-component-state-v1',role,enabled:false,configuration_sha256}`. Its configuration digest must identify a listed configuration entry. Database/release/configuration/recovery custody cannot be disabled. Unknown states, omitted roles, source links/junctions, sidecars, inconsistent metadata and missing external anchors reject.

For multiple recovery custody files, exactly one entry has `custody_context:true`. Preserve independent current-head, hash-addressed floor/head-chain objects, and custody configuration as distinct additional `recovery_custody` entries. With one custody entry it is the context implicitly. Schema 4 context is `{format:'i-core-recovery-custody-v1',mode:'initial_schema4',node_id,database_path}`. Schema 5/6 context uses `mode:'activity_floor'` plus `activity_recovery_floor`, checked against the database by `assertActivityRecoveryFloorForDatabase`. An adapter's camelCase `activityRecoveryFloor` must be supplied in this context field without re-signing or inventing a floor; the original envelope/head files are separately preserved.

The tool cannot discover unlisted production secrets or prove that the owner inventoried all configuration/task/credential sources. Production inventory and exact input/output/key paths remain an owner-reviewed prerequisite, along with the supervisor's real lease check before and after this operation. No format tag is a completeness attestation.

## Format and limits

Binary format is magic `ICRUNB01`, random 12-byte nonce, AES-256-GCM ciphertext, final 16-byte authentication tag; magic is authenticated AAD. Encrypted payload is a 4-byte manifest length, bounded UTF-8 manifest, and exact concatenated file bytes. No compression is supported. Verification streams without extracting. Limits: 10,000 files, 8 MiB manifest, 2 GiB per source, 4 GiB total source bytes, 64 KiB IO chunks, 1 MiB custody/disabled evidence. Output is flushed then atomically published without replacing an existing filename, using a temporary internal hardlink removed before verification; all published files remain single-link. Windows uses owner/System ACLs. POSIX uses 0700 directory/0600 file and directory fsync. Sources are checked for identity, length, timestamps and hashes before/after; stable snapshots are not substitutes for stopped writers.

## Windows DPAPI entry points

`backup_bundle_schema6.ps1` runs only from its own exact release. It checks the external manifest digest, every release file, full inventory, pinned Windows Node hash and Node `verifyRelease` before loading key material. Both native calls use `ProcessStartInfo`/actual exit codes with a cleared environment, not shell file-extension resolution. `Create` requires spec path/SHA, fresh output directory, separate key directory and optionally explicit `CreateKey`; `Verify` requires artifact path/external SHA. The Node child consumes binary 32-byte key followed by operation JSON only on redirected stdin. stdout contains hashes/count/scope/status, never keys or private source paths. Runtime/read errors are redacted.

`key_custody.ps1 -Action Create|Read|Library -KeyDirectory <absolute independent directory> -Purpose backup|recovery`:

- `Create` requires a fresh directory, generates a random key and CurrentUser-DPAPI blob, and prints only status.
- `Read` writes exactly 32 raw bytes to stdout for fixed child-process memory capture only; never run it as an interactive key-printing command or forward captured stdout to logs.
- `Library` defines `Get-RuntimeBackupKey -KeyDirectory -Purpose [-Create]`, returning byte[] in memory.
- Blob basename is fixed `runtime-backup.dpapi` or `runtime-recovery.dpapi`. Entropy binds purpose and normalized key directory; moving a blob breaks verification. Directory/file owner and protected allow-only ACL must be current owner and SYSTEM. Single-link blob reads hold a handle denying writes/deletes. The backup wrapper additionally holds its blob read lock throughout the child operation and compares a second DPAPI load before proceeding. Windows PowerShell uses its own PSHOME modules, avoiding inherited PowerShell 7 modules.

DPAPI is local current-user custody, not cross-machine portable recovery. No secret is accepted via CLI or environment, and no raw secret temporary file is written. The helper/package must be part of the externally anchored release before production use.

## Verification and integration

Windows Node 24.14.1: the final complete 23-test suite passed (23 pass, 0 fail, 0 skip; approximately 30 seconds). After adding the wrapper-long DPAPI blob read lock and in-memory reload comparison, the affected full fixed-release wrapper test was rerun separately. Coverage includes correct full-inventory roundtrip, exact schema4 DB binding, 9-role omissions, whole release same-count substitution, duplicate physical source, empty release files, fixed external digests, wrong key/ciphertext/tag/truncation, authenticated malformed manifests, traversal/size/compression rejection, concurrent source mutation, singleton/multiple custody, DPAPI roundtrip/bad blob/purpose/path/ACL/hardlink, fixed-release Create/Verify, inherited NODE_OPTIONS isolation, mismatched spec, overwrite rejection and helper tampering. DPAPI and PS wrapper tests are Windows-only; all cryptographic/inventory/source-boundary tests remain portable and do not skip on Linux. No Linux run is claimed.

Worker commit uses the authorized one-time `SKIP_PROJECT_STATE=1` exception only for owned files and this handoff, restoring the prior process variable in `finally`. No push, PR or merge. The integration owner must commit package inventory/CLI wiring and record global state, then re-run the integrated suite against that exact candidate.
