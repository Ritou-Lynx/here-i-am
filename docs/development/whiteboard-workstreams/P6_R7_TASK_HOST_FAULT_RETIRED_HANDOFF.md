# P6 R7 host-fault actual02 fixed retirement candidate

Root recovery update: frozen source `9C9DA837…` and exe `DEB245A5…` were independently reviewed, compiled and actually run. Inspect confirmed all three exact filters plus sublayer; cleanup committed removal of3+1 and verified current absence, closed resources and recovery_pending=false. Both captured actual exits were0. Historical actual02 failure/pending and unknown original Job/child-close remain unchanged. Full reports, pins and scope: [root actual evidence](P6_R7_HTTP_NATIVE_ACCEPTANCE_20260912.md).

2026-09-12. This worker owns only the new `windows_text_gate_task_host_fault_retired.cs`, its `.test.mjs`, and this handoff. No original executor, helper proof, witness, failed report, attempt directory, ACL, or global document was modified. No actual native/WFP/UAC/provider operation was executed.

## Fixed scope and entry

The candidate addresses only attempt `796e21fa-e29f-45c6-a856-bae0b8e6e6c3`, scope `fe8b92a0-0b63-b62f-ce9f-75b96a7b6883`, broker port `59838`.

- No arguments / `--plan`: no resource inspection or mutation.
- `--self-test`: pure checks only.
- `--inspect`: explicit elevated, read-only four-key WFP inspection. Exit 0 means a complete inspection of either all four exact owned rules or all four absent, with evidence and handles checked. Presence is **not** cleanup success: `recovery_pending` remains true.
- `--apply-cleanup`: explicit elevated exact retirement. All four absent produces no mutation; otherwise only all three exact filters plus exact sublayer permit a write transaction. Partial or mismatched ownership rejects without deletion.
- Extra arguments, custom attempt/path/port/key inputs, and other modes reject.

The only mutation surface is three `FwpmFilterDeleteByKey0` calls and one `FwpmSubLayerDeleteByKey0`, inside a transaction after current retirement and complete ownership revalidation. No process action, Job query, rule enumeration, directory/file creation, ACL mutation, normal helper launch, credential/home read, RPC, or model call exists in this entrypoint.

Four keys:

| Role | Key |
| --- | --- |
| allow4 | `9ccb9dd2-7bba-7442-0bf0-a3afc24cee47` |
| deny4 | `ddb0f120-5398-fd2a-baf8-bb96210566cc` |
| deny6 | `6724fd21-54ae-0db6-f548-40539f366c69` |
| sublayer | `81b233d6-f77d-0f63-bc3d-ac3f5f8cdaf9` |

## Evidence and retirement predicates

The exact native v7 image/source, copied CLI, original failed report, prepared/spawning/bound journals, install receipt, and install ready/ack files are held through canonical, non-reparse ancestor/file handles and exact SHA-256 pins. Root supplied private journal metadata; this worker did not open the restricted attempt directory. The fixed top-level inventory is exactly `project0`, `work`, `bound.json`, `codex.exe`, `install-ack.json`, `install-ready.json`, `install-receipt.json`, `prepared.json`, `spawning.json`; the two directory entries are not traversed. Unexpected closed/cleanup/final records reject rather than being invented.

The root and attempt directories must retain the same caller SID as owner, protected ACLs, and precisely the user/System/Administrators inheritable full-control ACEs. The caller must be elevated primary High integrity, non-AppContainer; its elevated token never substitutes for the historical Medium token.

Current inactivity is checked for owner `56908 / 134336784614518281`, child `38784 / 134336784695544734`, and install helper `47304 / 134336784674193355`. Missing PID is accepted only for OpenProcess error 87. Access denial, invalid wait status, zero creation time, or ambiguous identity rejects. A reused PID is accepted only with different creation time. Bounded process snapshots (maximum 8192 entries) additionally reject any live process using the exact original v7 path, including helper actions, or this attempt's copied CLI path. Checks run before WFP access, inside the removal transaction before and after deletes, and after commit. No PID is killed; historical Node PID 6400 is never acted upon.

Task v2 journal relationships and install lease/receipt fields are validated with frozen TaskRecords helpers. Assigned sublayer weight is exactly `32766`; current AppID bytes must hash to `b5449e34dd6fed323c777bd2ccf27cb6b9c5cf18a9268ba44c2fdcbbda314a07`. Existing frozen v7 `TaskBoundary.ExactFilter`, `ExactSublayer`, and `ReadbackAllowed` remain the rule ownership predicates. Read-only preflight uses `FWPM_TXN_READ_ONLY=1`; present rules are re-read inside the subsequent write transaction. Abort, engine-close, and handle-close failures remain sticky even if a bounded release retry succeeds.

## Output meaning and limitations

The original report SHA is `42498f1032a8803212ec7dc52d15243ec0daeac3e57660fba8902846c1961bbe`. It records failure at `native_exit`, native exit 0, no final receipt verification, and cleanup pending. Its shape and failure values are checked, but its missing exact witness exit is not manufactured. The candidate never repairs that history:

- `historical_host_fault_passed=false`, `historical_stop_receipt_verified=false`, `historical_cleanup_pending=true`, and `cleanup_pending=true` remain fixed.
- Only `current_rules_absent_verified`, `inspection_complete`, and `recovery_pending` describe this separate current resource check/removal.
- `exact_child_closed=null`, `job_active0=null`, and `job_current_inspection=not_performed_original_session_unavailable` are retained; the prior task inspector's unrelated historical Job-zero result is not inherited.
- `helper_actual_exit_verified=false` remains: current inactivity is not historical orderly helper exit.
- No production or human Gate is enabled.

Root must freeze this source plus a newly compiled executable, independently review inputs and output, and observe the recovery executable's actual exit before adopting its report. This candidate emits stdout only and writes no report into the old attempt. An unsuccessful or incomplete run cannot establish current absence. An all-present successful `--inspect` is merely eligibility for the separately authorized `--apply-cleanup`.

## Compile and pure verification

Standalone selected entry: `HereIAm.R7.TaskHostFaultRetiredProgram`. Joint-compile `/platform:x64 /warnaserror+ /target:exe /reference:System.Web.Extensions.dll`, selecting that `/main`, with these six dependencies plus the new source:

| Dependency | SHA-256 |
| --- | --- |
| `tools/dev_agent_bridge/windows_text_gate_isolation_helper.cs` | `d22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs` | `c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs` | `c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311` |
| `tmp/p6-r7-review/native-appid-matrix-contract-01.cs` | `f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774` |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.cs` | `f2d3b35a1e6d1763930ba7f9a82ab8dbb595e02d5d720216a0161dbce8a0d0ab` |
| `tmp/p6-r7-review/native-task-executor-07.cs` | `47d3da743598e17f92f2b3b7764226376097d015a7e337c3f27a9e7d8fbd5f92` |

`node --test tools/dev_agent_bridge/windows_text_gate_task_host_fault_retired.test.mjs`: **4/4 pass**, including x64 warnings-as-errors compilation, **260** native pure self assertions and **356** managed synthetic assertions. Dependency pins are checked before and after. Tests cover missing/altered journal and lease fields, frozen identities and port/weight, exact inventory, token rejection, PID reuse/error semantics, historical failure invariants, write transaction failure points/abort order, partial rule-set rejection without delete, and sticky failed-close retries. Actual entrypoints are never invoked by these tests.

Final candidate:

- Source SHA-256: `9C9DA837E2F50F6152EEF606C264B26B4CC03F1A0E3CB49E10B05BAC799CDBC3`
- Test SHA-256: `649297CE589C3E83E3900E212AD27B5023E2FF42CC6D6902625FD6EE85821F3A`

No commit or actual recovery was performed by this worker. Root owns independent review, actual current-rule inspection/cleanup, and integration documentation.
