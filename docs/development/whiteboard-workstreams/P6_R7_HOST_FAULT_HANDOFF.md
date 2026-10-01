# P6 R7 default-pipe host-fault witness candidate

Root acceptance update: frozen witness03/exact native v7 and detached transport passed actual03 `4e8a1205-fc25-4289-b6fd-4273bad3b8c0`: exact Node terminated, native exit3, final receipt bound with EOF/stdout failure/all six cleanup facts, witness actual exit0, 30/30 inputs unchanged. The same final combination also passed no-turn HTTP normal close. Failed actual02 remains failed and its exact rules were separately recovered. See [root evidence and scope](P6_R7_HTTP_NATIVE_ACCEPTANCE_20260912.md). The worker-only statements below describe who performed the implementation and do not negate these later root actual results.

2026-09-12; `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5` plus current P6 candidate sources. This worker added the target, pure contract/test, standalone witness source, and this handoff only. The frozen HTTP probe/test were not changed. No native executor, CLI, UAC, provider/model, or host-fault scenario was executed by this worker. No production profile or installed service changed.

## Scope and explicit entry

The C# witness is standalone and references only framework `System.Web.Extensions.dll`. No native executor/helper source, WFP routine, or credential reader is compiled into it. No arguments and `--plan` emit non-executing plan JSON; `--self-test` runs pure checks.

Actual candidate invocation has exactly nine arguments: `--apply-host-fault`, absolute Node executable, its SHA-256, absolute target `.mjs`, target SHA-256, absolute frozen native v7 executable, its SHA-256, absolute new report path, and absolute closure manifest path. The report is opened `CreateNew` before resource acquisition. Root must independently freeze/review these inputs and observe actual witness exit 0 as well as the report. A persisted `passed:true` with nonzero/unknown witness exit is insufficient.

The manifest schema is exactly `{ "schema":"p6_r7_host_fault_closure_v1", "files":[{"path":"absolute .mjs path","sha256":"64 hex digits"}] }`. It includes exactly the recursive local static import closure of the target, including the target itself, in the same directory. Current closure has 19 modules. Builtin `node:` imports are allowed; missing/extra members, dynamic imports/require, relative escape, non-`.mjs`, or nonlocal package imports reject. Root supplies this manifest. Every listed file, the manifest, target, Node image, and native image is pinned through non-reparse canonical ancestors and held files; closure/image hashes are checked before kill and after native exit.

SHA comparisons against pins are case-insensitive. Prepared/bound/final binding strings are compared exactly to one another. This matches current lowercase `TokenProof.Hash` and `CliStartupContract.Pin` without rewriting persisted evidence.

## Target and ownership

Witness starts exactly its own Node with `--use-env-proxy`, a private redirected stdin/stdout/stderr control channel, and no visible window. The target uses real temporary `127.0.0.1:0` HTTP, API, RuntimeAdapter, broker, attached client, and unchanged `launchWorkbenchTextNativeExecutor` three-pipe topology. Its local HTTP uses a private empty-`proxyEnv` Agent. Generic adapter construction, broker arm, and `turn/start` reject. A ready barrier requires actual HTTP creation/config/thread evidence and no model/upstream work; bounded local `/v1/models` metadata 404s remain allowed.

The target reports only its held attempt and native-started CLI child binding, fixed evidence booleans, and broker port. It does not read journals or private home files. The witness derives the one fixed attempt directory, opens prepared/bound on held canonical non-reparse handles, bounds/strictly parses their JSON, checks the full shared binding and owner token digest equality, then opens the exact native owner and CLI child process handles. Prepared child fields must be null; bound child fields must match the target's existing startup identity.

The witness holds an explicit noninheritable duplicate of its own Node process handle plus noninheritable query/synchronize handles for native owner and CLI child. It verifies PID, creation FILETIME, canonical image, and pinned image hash. Immediately before kill all three processes must still be live and correctly bound, and the final receipt path must be absent. The only termination call targets the witness-owned Node's exact held handle; it never kills a tree, PID-selected replacement, native owner, or CLI child. Witness retains no native pipe endpoint, so Node death actually closes those default pipe ends.

The environment passed to Node is reconstructed from a fixed Windows path/profile/temp and proxy whitelist. `NODE_OPTIONS`, `NODE_PATH`, unknown keys, and unrelated credential environment variables are excluded. This prevents preload/import injection from bypassing the held source closure. Proxy settings remain available through the explicitly selected Node flag; no process/global environment is mutated or reported.

## Exit and durable evidence

After Node termination, witness observes actual native process exit on its held handle and the CLI child's actual exit. It then reads the same attempt's v7 final receipt through a held file handle. The whole binding, six closure facts, false cleanup pending, started state, no close command, `input_eof`, failed final stdout emission, and v7 pending-exit-commit marker must agree. Although v7 generally supports exit 0 or 3, this particular stdout-broken host-fault combination requires actual exit **3**. An observed `operation_failure` trigger remains a distinct unsuccessful outcome, never relabeled as EOF.

The report distinguishes native cleanup from witness cleanup, with separate checked raw process handles, pinned file handles, joined sole stdout/stderr reader tasks, and disposed managed streams/process wrappers. Native/child/Node raw handles receive checked closes; managed disposal is separately reported and is not presented as Win32 close-return evidence. The report's own final write/flush/disposal is committed only by the actual witness exit 0, expressed by `requires_actual_witness_exit_0` and `pending_actual_witness_exit_commit`.

## Failure behavior

Any failure before intentional kill sends the fixed graceful control command to the same target and waits up to 180 seconds. The target permanently stops its API and retains unknown same-owner cleanup instead of replacing it. If graceful stop cannot be confirmed, witness emits a finite `needs_attention` notice, retains all exact handles, and does not exit or automatically kill anything. It accepts only the exact stdin line `{"type":"graceful"}` for a user/root-directed retry; it does not loop automatic UAC retries. It continues observing held process exits and finishes only after the retained target/native ownership has exited, including explicit external intervention. Post-kill native timeout likewise retains ownership and needs attention. Such a path never becomes a passed host-fault test.

The candidate-02 control fix explicitly writes LF from the witness. Both control parsers accept LF or a single CR immediately before LF, with no general trimming or command expansion. Target control buffers are bounded and malformed/oversized lines are discarded without poisoning later valid retries. A failed `needs_attention` stdout write is best effort and cannot escape the ownership-retention loop. The final report records only a finite failure stage: preflight, source_closure, node_start, http_ready, journal_binding, native_binding, child_binding, kill, native_exit, final_receipt, or post_close.

Ready and post-kill native waits are each bounded at 180 seconds; Node kill-exit wait is 10 seconds, reader joins are 5 seconds. The needs-attention ownership retention is intentionally not a timed escape hatch. Unknown failure reports remain conservative; neither timeout, target exit alone, nor stdout EOF substitutes for the bound native final receipt and actual exit.

## Verification

`node --test tools/dev_agent_bridge/workbench_text_task_host_fault_contract.test.mjs`: **5/5** pass. This includes standalone managed compile, default plan, and **37** C# pure self-test assertions. Real fragmented LF/CRLF byte streams verify that an unconfirmed first close can receive a second valid retry; malformed controls never become commands. C# assertions cover notice-output failure without losing the retention decision. The target passes Node syntax check. Read-only import discovery finds 19 local closure modules and no dynamic imports. These results do not prove actual Windows host-fault recovery.

JS pure validators reject wrong binding, reused PID/creation, wrong pin, unheld/dead ownership, partial journals/receipts, exit 4/0, guessed EOF, missing kill, and conflicting final fields. Pure results always have `actual_native:false` and `passed:false`, even if a caller supplies an extra synthetic flag. The actual C# checks also cover decoded duplicate JSON keys, lowercase persisted pins, environment preload exclusion, and non-exit retention decisions.

Final candidate-02 review hashes (candidate-01 is superseded for actual execution):

- target: `B30F2916F36DBF92F3A2E73353351652BF29221677CA7250F6A8BE746E8EF368`
- pure contract: `AE73AC0DE832F579E0DB3A32CDD367B63E4DDCDF93208ECA83EE624F94D25269`
- tests: `FB04C83070789D46DCE7E80F2AE841FEEAD67171749BDB628BC37EB2F23D512A`
- C# witness: `6E222B9F8695C90A68EB23A40521F2B52067A570B09F9D5889BA1DA48030D6A7`

Root owns final independent audit, frozen manifest/executable generation, any actual UAC/host-fault acceptance, and integration state. This worker has not established an actual host-fault pass or production availability.

## Candidate03: detached native owner and exited-handle validation

This candidate follows failed actual02; that report and its frozen inputs are preserved. Two separate defects were diagnosed. Node 24.14.1/libuv 1.51.0 puts non-detached children into a KILL_ON_JOB_CLOSE Job, plausibly preventing native finalization after the target dies. The transport now adds only `detached:true`, retaining three pipes, windowsHide, filtered env, cwd, pinned argv, process reference and close/postpin policy. Job membership was not directly observed in actual02; a new frozen actual run remains necessary.

A self-exiting dummy independently showed QueryFullProcessImageNameW succeeds while alive but fails with Win32 31 after normal exit0. On the same held handle, Wait was signaled and PID/creation/GetExitCode remained valid. Witness03 therefore still requires live wait state and canonical image verification before kill, and requires exact same held PID/creation plus signaled wait and successful GetExitCode after exit. It retains/rechecks all held image hashes and the complete import closure. Live handles, reused identities and failed waits cannot take the exited path. Node/child numeric exit codes are recorded without requiring child exit0. The native exit3, input EOF, failed stdout final emission, complete bound durable receipt, six closure facts, pendingfalse and outer witness exit0 requirements remain unchanged.

Validation: native transport/HTTP probe/runtime adapter **42/42**; adding host-fault contract tests yields **47/47**, including standalone managed compile, default plan and **44 C# assertions**. No native/UAC/provider actual was executed by this worker. Dummy source/result are `tmp/p6-r7-review/image-after-exit-dummy-01/image_after_exit_dummy.cs` / `result.json`, SHA-256 `375F099B909C9F696AF1336DDD5F03D09AD089C5FE72CAF28988E35C12A47A57` / `27F8F7A6195768199BE5C96B53351EE2DC8EAF97D7F547C1D32167EA1243519E`; its checked raw-handle close succeeded.

Freeze source hashes (SHA-256):
- witness: `A931E876F8FA4C198946E867BA0A24BC7C142A32CF3738C693BA34D920246C8F`
- target (unchanged): `B30F2916F36DBF92F3A2E73353351652BF29221677CA7250F6A8BE746E8EF368`
- contract (unchanged): `AE73AC0DE832F579E0DB3A32CDD367B63E4DDCDF93208ECA83EE624F94D25269`
- contract test: `49FA742D5987D20926AA29AC5DF1D428CCEFC59926CB5535106ADFE21582610E`
- native transport: `8C4F80FC616BAB9EF96EA0117EE3B54D57A70E06BB2794C5677FED42BA5A8A98`
- transport test: `EFBF3394B9B247B6216088B4B1C7F577E05E4CE5CF026BEF7DD5EC52E4018329`

Current code is ready for root-controlled freeze/review. Native v7 and frozen HTTP probe are unchanged. This is candidate implementation plus local verification, not successful host-fault evidence or production enablement.
