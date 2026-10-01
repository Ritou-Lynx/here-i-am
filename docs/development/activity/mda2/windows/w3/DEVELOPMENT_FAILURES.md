# MDA-2 W3 retained development failures

These are implementation-time failures kept separate from the final passing results. They were used to tighten the candidate and are not presented as acceptance evidence.

1. The first frozen-W2 replay was rejected by the unchanged ancestor-handle protection check (`windows_protection_rejected_ancestor_handles_path_lock_failed_5`, exit 1). No result was parsed and the named mirror was removed. The reviewed replay then passed in a fresh self-created mirror.
2. An early authority fixture used the wrong epoch and was rejected as `native_packet_unverified`. The fixture now uses the broker-issued channel coordinates; authority validation remains fail-closed before state moves.
3. The first native build wrapper assumed a newer PowerShell hash command. It was replaced with a .NET Framework-compatible SHA-256 implementation and rerun successfully.
4. Early HTTP oversize handling surfaced a generic abort. The adapter now records the bounded terminal reason and waits for actual request closure.
5. A raw-expiry race initially let transport cancellation mask the late-receipt fence. The controlled fixture now holds the real request through expiry; the broker clears raw material, requests cancellation and separately fences any late completion.
6. A synthetic identifier accidentally contained a forbidden endpoint-like token and was correctly rejected. The fixture identifier was narrowed; the production boundary was not relaxed.
7. The first compatibility wrapper treated Node's SQLite experimental warning as a PowerShell failure. Output capture was corrected without suppressing the warning or changing the W2 tests.
8. One manually interrupted iteration left a single task-owned protected scratch directory. Its exact resolved path and lack of a matching live process were checked before it was removed. Final W3 and W2 runs both report scratch cleanup.
9. The post-hardening W3 replay inside the Windows sandbox again encountered the unchanged ancestor-handle guard during a rollback fixture. The full replay used the reviewed execution path, exited 0 and removed scratch; the protection check was not weakened.
10. W0 rejected `7bdf72b7` because rejected `exited` Promises were marked as successful exits and bare Promises could enter transport without cancellation/independent exit proof. The repair introduces a prevalidated two-phase adapter and keeps response completion active until exact exit proof.
11. The first repair replay exposed the raw exit rejection (`no_exit_proof`) instead of the stable fail-closed result. The adapter cause is retained internally while callers and lifecycle controls now receive `transport_exit_unconfirmed`.
12. W0 then reproduced a synchronous HTTP `write` throw after a real request existed; the intermediate catch had issued a false closed receipt. The repair installs error/close listeners first, destroys an existing request, and resolves `exited` only from its real `close`. A real loopback negative test preserves this distinction.

No failed run overwrote the frozen W2 evidence. Final evidence is in `RESULT.json`, `W2_COMPAT_RESULT.json`, `W2_COMPAT_SUMMARY.json`, and `W2_COMPAT_RUN.log`.
