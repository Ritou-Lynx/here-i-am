# Schema6 fixed candidate: login, shutdown, recovery and backup

Packaging alone does not register tasks, start services, migrate a real database or install a phone. Preparation/preflight continue to report `deployment_ready:false`, `deployed:false` and no whole-backup activation. This candidate adds automatic recovery of its explicitly bound canonical state; an inspection restore remains inspection-only. Production cutover requires the owner's separately reviewed window and configuration.

## Fixed source and authority

Use a fresh output directory and Node 24.14.1 SHA256 `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`. Run the repository CLI `prepare` with the sanitized repository, fresh output, Git binary; the CLI uses the pinned Node running it. The returned source and manifest anchors must both be retained. Only HEAD or a full 40-hex committed source identity is accepted. Core, wrappers, transitive ESM imports, PowerShell dependencies and copied Node are read from that same Git tree; uncommitted files never enter a release.

Retain the manifest SHA and source commit outside the release under the owner's protected custody. Every entry point verifies the complete fixed inventory, plain paths, hardlinks, ACLs and pinned executable. No state, configuration, grants, tokens, keys or databases enter the package. A local read-only file attribute is insufficient authority.

Protected Core configuration explicitly binds state, node, owner SID, release hash, credentials, transcript grants, replay approvals and recovery custody. Keep `companionUploadMode:'legacy_b3'`, `companionReplyJobsEnabled:false`, `activityAdminSecret:null` until separately approved; run only one uploader/consumer. Debug mail may remain disabled while its old configuration and journal are retained.

## Interactive login and normal shutdown

`lifecycle/prepare_login_schema6.ps1 -PrepareOnly` emits a hash-bound, least-privilege InteractiveToken logon task XML without registering or starting it. The login configuration supplies a fixed nonzero production port, independent control root, required managed-MCP configuration and optional protected backup configuration. The future task runs only after this user logs in.

`lifecycle/login_schema6.ps1` creates a new private session and empty control directory each time. Its hidden resident window receives WM_QUERYENDSESSION/WM_ENDSESSION without taking focus. Core supervisor, MCP and backup roots are placed into separate owned kill-on-close Windows Jobs before execution. MCP starts only after the actual Core ready record is bound to the current manifest and supervisor identity.

Normal shutdown stops dispatch, confirms the complete MCP tree has exited, bounds an active backup, then sends authenticated `request_stop close`, and checks actual Core/guardian/supervisor exit, Job emptiness, clean marker and lock release. The total shutdown budget is 30 seconds. Timeout never forges a clean receipt: the owned trees are terminated and the next login uses recovery. Cancelled shutdown starts a new generation with a fresh control. A previously ready Core/guardian death can trigger one same-session recovery restart after both Core and MCP owned trees are empty and their handles are released; 30 seconds of stable readiness renews the budget. A failed startup Gate or repeated immediate failure leaves a clear blocked result.

The protected login declaration adds mcp_configuration_path and mcp_configuration_sha256 as a pair. Its schema6-mcp-v1 file fixes executable bytes, full source inventory, entrypoint, arguments, explicit memory/policy/OAuth/identity paths, database binding, loopback port and a 0–3000ms grace. Mutable MCP .state stays outside the locked source tree. Inherited Node/proxy/application configuration is excluded; the supervisor injects the actual ready Core URL and fixed database/host/port. The unchanged legacy CLI has SIGINT/SIGTERM handlers, but CREATE_NO_WINDOW has no reliable Windows POSIX-signal channel: finite wait is followed by termination of only the owned MCP Job, recorded separately from Core clean close. Natural MCP exits or start failures are failures, including between timer ticks. MCP stop, backup stop, Core authentication/close and force cleanup share one monotonic 30-second deadline; MCP Job emptiness plus held process-handle exit proves release of that owned tree, while a final real exclusive DB open checks the closed endpoint. Other unmanaged readers must be quiesced during the separately authorized cutover; strict sidecar/offline checks remain unchanged.

No nightly manual stop phrase is required. Only inspection/check failure, custody rollback, or interrupted migration requires manual handling.

## Raw-before-open automatic recovery and legacy adoption

For missing/non-clean lifecycle evidence or DB/WAL/SHM/journal remnants, the fixed startup obtains genuine OS ownership/offline proof and **streams all original files into an authenticated AES-GCM archive before any SQLite open**. The original file set is unchanged during preparation. It then opens an isolated copy normally, lets SQLite replay committed WAL and discard uncommitted work, and verifies integrity, schema, canonical configuration/node binding and independently retained custody head/history commitments.

On success it records a recovery event, publishes the validated canonical copy and starts Core using the new control directory. A protected interruption marker prevents guessing after a migration or multi-file publication was interrupted. After publication begins, preserve the failed state and repair forward; do not downgrade it with v4 or restore an old head over new writes. SIGINT/SIGTERM can produce a clean close when the actual close succeeds.

Old v4 first takeover uses this same copy mechanism after a separately approved freeze of its old task and bound process tree. It preserves the raw originals, opens/migrates 4→5→6 on the copy, validates legacy data and only then replaces canonical files. Before replacement, rollback is restarting the exact old v4 against its untouched files. This is not a separate irreversible phase chain.

An inspection directory or `backup_read_only` database cannot become live through this path. Existing schema5/6 custody must come from independent authority, not be synthesized from the target. Previously generated activity-only floors require exact closed Core bytes; this candidate's new bounded history witness allows validated current Core progress. Activity remains disabled: its older mutable retention semantics require separate compatibility work before enablement.

## Complete backup and portable password recovery

Preserve all nine runtime roles, not just SQLite/grant/replay: complete Core release/state/custody, transcript grant, both exact 72-record approval sets, MCP .state credentials/ledgers, i_memory policy/snapshots, bridge state, tunnel configuration, retained Tailscale configuration (without its machine private key), and authorized phone database copies. A component that is disabled still needs configuration-bound evidence.

`backup_bundle_schema6.ps1` creates/verifies/restores the authenticated full inventory. Online automatic backups use consistent SQLite snapshot copies and stable configured files; do not call that a globally atomic snapshot of independent components. Unknown auxiliary SQLite requires explicit consistent capture. Sidecar-free regular bundles and raw crash archives are different formats with different purposes.

`portable_backup_schema6.ps1` additionally wraps the same backup key with scrypt (N=131072, r=8, p=1) and AES-GCM. Password input uses SecureString and a one-shot memory pipe: never command arguments, environment, logs or repository. Keep the artifact, password envelope, authenticated binding and external digests together. DPAPI remains the convenient local unlock; the recovery password is independently user-held. This does not make every DPAPI-protected service credential portable.

`scheduler_once_schema6.ps1` runs the protected automatic policy: default daily capture, default 30-day retention, optional configurable ciphertext mirror. An offline mirror retains local success and marks pending; reconnect backfills existing bundles without recapturing. Unknown directories are not pruned. A native lock excludes cross-process overlap and automatically releases on exit; a residual lock pathname is harmless.

Password-only RestoreInspection authenticates the archive before writing a fresh private directory, then starts the actual immutable/read-only Core. It compares node/schema/devices/all table counts and fingerprints, rejects business/pairing writes and verifies unchanged bytes after exit. It neither writes original source paths nor activates restored state. Secondary databases require their own inspection. Another Windows user/machine is a separately reported Gate; same-user DPAPI-unavailable evidence must not be called a cross-machine test.

Tailscale machine private key is intentionally excluded per owner decision. A replacement computer logs in to the same tailnet, retains the original machine name, recreates the approved Serve protocol/path/47862 mapping, and verifies phone numeric IP or MagicDNS addresses plus credentials/cursors. Service credentials that relied on the old Windows profile may require a reviewed rebind.

## Preflight, tests and operations

The read-only preflight retains the legacy baseline contract: nonempty matching 72 bindings, exact grant bytes and current device binding, message identity/digests/sequences, no pending companion reply jobs and explicit domain authority. Captured anchors are proposals, not approval. Inputs must be quiescent/plain/sidecar-free. Only the fixed CLI verifies package identity; low-level inspectInputs alone reports `package_verified:false`.

Run `node --test tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs`. Windows CI additionally exercises the real pinned Node, native Jobs/locks, hidden-window messages, shutdown deadline, DPAPI and password-only inspection. Synthetic path normalization and token owner setup are test/CI-only; production path/ACL/link guards remain strict. Linux verifies the portable suites and independent-history packaging checks; actual Windows integration is Windows-only.

Operator handoffs in the source tree:
- `docs/development/handoffs/SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md`: one-page owner steps.
- `SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md`: stop scope, copy adoption, rollback/forward repair.
- `SCHEMA6_AUTOMATIC_MAIN_ACCEPTANCE_20261006.md`: exact integrated evidence and six drills.
- `SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md`: password custody, replacement computer and Tailscale.
