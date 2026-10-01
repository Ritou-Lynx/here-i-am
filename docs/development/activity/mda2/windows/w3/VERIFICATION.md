# MDA-2 W3 verification

## Final executable results

- W3 synthetic/local suite: 44/44, Node exit 0, `scratchRemoved=true`; final run used the reviewed execution path because the sandbox ancestor handles correctly tripped the protected-root guard in an earlier attempt.
- Frozen W2 compatibility suite on the W3 candidate and current baseline Core: 35/35, Node exit 0, inner scratch removed, temporary mirror removed.
- Native C# adapter: compiled locally; artifact size 10,752 bytes, SHA-256 `fc165e2afc7b781b24debb21c6d3c9ddf8b546f0b96286304f7c04fe27dd3642`. The artifact was temporary and is not committed.
- Default status: `mode=disabled`, real OS collection false, transport unconfigured, startup unregistered, production pairing false.
- Static checks: all W3 JavaScript modules pass `node --check`; `git diff --check` passes.

## Covered boundaries

The W3 suite covers strict/private frames; initial unknown lock state; current-session/nonce/epoch/source fences; idle tick wrap, regressions and full-32-bit-period ambiguity; quality gaps; bounded native buffering and overflow; rollback on partial startup; independent per-source allocation; strict loopback HTTP responses; timeout/429/5xx/disconnect/redirect/malformed/oversize/wrong-event cases; pre-start rejection of unregistered/bare/malformed asynchronous transports; started malformed-handle cleanup; rejected and malformed exit proof; response-complete/exit-pending concurrency, stop and close behavior; real-request write-throw closure; preserved retry bytes; bounded pending work; raw expiry, freeze, owner and late-receipt races; actual native/queue/transport exit; and the two-source synthetic end-to-end path through protected disk and a test-created Core HTTP server.

The compatibility replay additionally preserves all 35 frozen W2 process/protection/storage scenarios, including the 14 forged broker projections in its existing evidence.

## Deliberately not tested

No real WTS, keyboard/mouse, lock-screen, suspend/resume or production network action was performed. No active port 47841, production URL, real credential, existing database, startup registration, Android runtime or human/device evidence window was used. The compile result and synthetic suites do not establish any of those Gates.

## Reproduction

From the repository root:

```powershell
node tools/mda2_windows_collector/main.mjs --verify-synthetic
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/mda2_windows_collector/fixtures/run_w2_compat.ps1
node tools/mda2_windows_collector/main.mjs --status
```

The suites create their own scratch roots, synthetic secrets and random loopback endpoint. The W2 wrapper writes new W3 evidence, explicitly normalizes its new summary JSON to LF before hashing, and does not modify the imported W2 historical result.
