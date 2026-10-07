# Schema6 CI module search scope — 2026-10-06

- Base: exact `1cff9d084f42b10b46655241830573511bf2ca2a`; branch: `codex/schema6-ci-module-scope-20261006`.
- Ownership: CI test driver, new test-only module scope helper and its behavior tests, this handoff. No workflow/global state/production/inventory changes. No push.
- Integration owner handles workflow artifact and global project state. This authorized worker commit uses `SKIP_PROJECT_STATE=1` once, restoring its previous environment value in `finally`.

## Evidence and bounded conclusion

Read both sanitized probe reports for the exact base, jobs 112186109504 (push) and 112186133949 (PR). Timings in milliseconds:

| Fresh process stage | Push | PR |
| --- | ---: | ---: |
| No-op | 208 | 233 |
| Prepare protected synthetic root | 29726 | 34875 |
| Default Get-Acl | 20470 | 23299 |
| Default full Assert-ProtectedPath | 20526 | 23383 |
| PSHOME-only / explicit system module comparison Assert | 296 | 313 |
| Actual production 10000 ms gate, timeout | 10015 | 10013 |

Default fresh processes reported six module roots; the explicit comparison reported one. Both had 104 immediate system module directories. This isolates the large cost to default module discovery/loading, rather than basic PowerShell process startup. It does not identify a particular installed module, prove a cache mechanism, or establish a need to delete caches. The next hosted run must show whether this CI-only scope removes that cost while the original production check remains intact.

## Implementation and protection

`module_scope.ps1` only defines functions when dot-sourced. The driver runs its host guard before token-owner compilation/change or machine actions. It requires Windows, 64-bit PowerShell 5.1, and exact GitHub Actions/github-hosted/Windows runner markers. Explicit `-GuardOnly` always rejects, including with spoofed hosted environment variables. These markers are an execution boundary for an authorized disposable runner, not cryptographic host attestation.

The native adapter snapshots both existing HKLM/HKCU environment keys' PSModulePath raw values, registry kinds, and value presence before any mutation. Unexpected key absence or value kind rejects before mutation. It writes only the system PSHOME module root temporarily; original values are restored exactly, or the previously absent value is deleted. It does not modify the parent process environment or production cleanEnvironment.

When AllUsers Modules exists, its ancestors and itself must be canonical directories without reparse points. Volume/file identities bind the original directory and parent. The entire directory moves atomically on the same volume to a unique sibling outside all original fresh-process roots, parent inherited roots, and intended new roots. No module contents are deleted. A new empty Modules directory is created exclusively; its identity is captured.

Before the body, another fresh PowerShell process using the unchanged OS-only environment must report only the system module root and optional empty AllUsers root. Any additional root rejects the scope. The original probe then runs; its actual production protectedPath invocation is still unique and still has the original 10000 ms timeout. A failed probe prevents the unchanged full 151-test command from starting. A passed probe runs that command once while the scope remains active.

Every registry write/directory move/create is marked attempted before invocation. Restoration examines actual directory identities, including when a move took effect before a callback threw. Only the scope's same-identity empty directory is removed, nonrecursively; the original directory is moved back without overwrite. Unknown identity, nonempty content, replacement, or conflicts fail closed and preserve evidence. If identity capture failed after exclusive creation, the empty root and quarantined original are retained and cleanup is reported failed. Directory restoration failure does not skip either registry restoration. Any restoration failure makes CI fail, even if the body passed. If the original directory was absent, no persistent directory is created; an unexpected appearance causes cleanup failure.

The report emits only fixed phase, booleans, bounded body/exit status, and fixed format, never raw exception text, module paths, registry values, or subprocess output. It is printed and saved as `build/ci/schema6-module-scope.json`. Existing probe JSON/TAP outputs remain unchanged. The integration owner adds the report to workflow artifacts.

## Verification

Exact command from the worktree root:

```powershell
& 'D:\Nodejs\node.exe' --test tools/i_core/test_fixtures/release_schema6/module_scope.test.mjs tools/i_core/test_fixtures/release_schema6/ci_native_probe.test.mjs
```

Worker result: 14 tests / 14 pass / 0 skip / 0 fail, 3408.5965 ms. Parent independently reported 14/14, 2310.1204 ms.

New tests include PS5.1 parsing, compiling the native directory helper without invoking its directory APIs, both real runner rejection paths, pure root-boundary comparisons, and 23 memory-only transactional scenarios. These cover failures before/after writes and moves, failed identity capture, nonempty/replaced directories, absent originals, independent restoration attempts, safe reports, and body exit preservation. The actual wrapper with a fake failed probe never starts the full suite. Existing eight probe tests also passed. `git diff --check` passed.

All local verification used pure callbacks, parser/compiler checks, or rejecting entrypoints. No local registry values were read/written, no global module directory was queried/moved, and no service, account, task, live Core, database, or phone was touched. No full native suite was rerun locally. Actual registry/directory setup, restoration, final 10-second gate, and the full suite remain for the disposable hosted CI run. No cache deletion, blind retries, skips, production timeout increase, or production path/ACL weakening.
