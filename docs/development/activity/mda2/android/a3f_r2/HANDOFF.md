# A3F-R2 notification startup handoff

## Candidate and boundary

- Parent: `aae59e18f142e0854c033a0b2e31c65bc3fd0e88` (A3F-R1).
- Authorized isolated branch: `codex/mda2-a3f-r1-late-events-20260916`; candidate is the commit containing this handoff (`git log -1 --format=%H -- <this path>`).
- Scope: Activity-only startup confirmation, Service/bridge integration and local tests. No APK build/install, device, network transport, Core/wire/outbox/schema, dependency, Manifest, Dart, production DI/entry, BLE, or global project-state modifications.
- Model route remains the delegated Astra/high. No child agents.

## Implemented behavior

The process-local startup coordinator owns one token from request dispatch through notification confirmation and epoch activation. Its 10 s deadline uses `elapsedRealtime`, with 100 ms asynchronous observation. The notification requests `FOREGROUND_SERVICE_IMMEDIATE` on API 31+. These times concern startup readiness only; neither is an event-publication watermark.

Only the AppOps watcher registers before confirmation. Initial denied access fails immediately. Missing first notification/foreground observation remains pending; no screen receiver, epoch, UsageEvents query, or enabled result starts while pending. Policy denial, timeout, cancellation, destroy, or activation exception ends the attempt. Any AppOps edge synchronously fences unconfirmed completion, then posts Service cleanup to the main looper. Exception cleanup also unregisters the watcher and removes the pending observation Runnable.

A claimed terminal attempt remains occupied until that exact service instance releases it. Duplicate or already-active opt-in cannot renew an attempt. Timeout targets its token, never a broad `stopService`; old callbacks/destroy cannot cancel a successor. The bridge separately fences pending replies and delivery listeners by generation/token. Deactivate completes the still-live pending result once; detach invalidates it without calling a dead engine and only cancels an unconfirmed start, retaining R1 active-FGS engine-loss behavior. A queued success rechecks current live active state and token/instance when dispatched; if stop/destroy won, it returns `collector_disabled` instead of resurrecting the bridge.

## Real local verification

1. Before Service modification, new `notificationMayAppearAfterStartForegroundWithoutPrematureStop` ran against baseline compiled/mirrored production source: **32 tests / 1 failed / 0 errors**, exit 1, 1m22s. Old 31 passed. Failure is the immediate `!notificationVisible` rejection; this is a production-source contract reproduction, **not** Android notification-runtime injection.
2. Final targeted Kotlin run: **53 tests / 0 failures / 0 errors**, exit 0, Gradle **15s / 22 tasks**. Breakdown: old ledger 7, epoch 10, policy 12, late-publication 2; new startup state machine 16 and Service/Channel source integration 6. Production Service and bridge compile with Android SDK and Flutter embedding. All harness-owned sources/tests match candidate bytes.
3. The preceding intermediate run was 51/0 and 17s, before the independently identified posted-success race. The final 53/0 includes that fix and regression. No failed final tests were omitted.
4. R2-only static gate checks the eight-path allowlist, protected zero-diff paths, startup/callback fences and no new transport/private-data projection. `git diff --check` is required before commit.

Exact command: `verify_a3_android.ps1 -FlutterSdk D:\flutter -AndroidSdk <existing Android SDK> -Gradle <existing Gradle 8.14 executable> -JavaHome <existing JDK 17> -ReuseHarness`. It uses cached offline dependencies; no dependency changes. Existing harness reused to bound disk use. Run static with `verify_a3f_r2_static.ps1 -BaseCommit aae59e18f142e0854c033a0b2e31c65bc3fd0e88 -WorkingTree` or omit `-WorkingTree` for the committed candidate.

Ignored local evidence (not committed):
- `test/data/services/activity/mda2_android/.verification_android/r2-red/startup-contract-red.xml`
- `test/data/services/activity/mda2_android/.verification_android/r2-red/receipt.json` (baseline Service SHA256 `fe463b4557ef7b349afda058424c026ea150965aa4178978f47937a95c64db18`; failure XML `2c8bb50a2b8a900cb76131ece4a39c8f730d086f9dc3701b7b72ff93542a10a4`).
- `test/data/services/activity/mda2_android/.verification_android/r2-green/` (all six final XML files and source-hash receipt).

Lifecycle coverage: delayed foreground/notification, full dispatch deadline, queued/waiting cancellation, denied/revoked authorization and edge during confirming, notification policy denial, activation failure, exact-owner destroy, stale callback/token/timeout, duplicate opt-in, bridge stop/detach and post-confirmation/pre-dispatch destroy. Source assertions bind state-machine use to real Service scheduling, preconfirmation collection exclusion, exception cleanup and bridge generation checks. They are not instrumented Android lifecycle tests.

## Path manifest

- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityStartupConfirmation.kt`
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`
- `android/app/src/test/kotlin/com/memexlab/memex/activity/ActivityStartupConfirmationTest.kt`
- `android/app/src/test/kotlin/com/memexlab/memex/activity/ActivityStartupServiceIntegrationTest.kt`
- `test/data/services/activity/mda2_android/verify_a3_android.ps1`
- `test/data/services/activity/mda2_android/verify_a3f_r2_static.ps1`
- `docs/development/activity/mda2/android/a3f_r2/HANDOFF.md`

## Open gates and commit handling

W0 must independently review/freeze this commit, compile its unique candidate APK, and test real notification startup plus the original human screen-event Gate. Local success does not prove the reported device failure was notification publication delay, that the new notification is visible on that device, or that Android event publication is lossless. R1 best-effort/TTL/omission semantics are unchanged. No device Gate is claimed here.

W0 owns global state/DEVLOG. This delegated commit uses the explicitly authorized one-command `SKIP_PROJECT_STATE=1` exemption; its prior environment value is restored in `finally`. No push. Source hashes at final unit verification:

- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`: `e7ca3adfa8c72488de77e5abb5d8062e99c49fb5b6bdb712db78e1a8f4558ca6`
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityStartupConfirmation.kt`: `c1047ac961d8e78f1cc37d95cccba75d875a6be3789a0c0986aeb8166fd68b7c`
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`: `ee42db5898535a5732dd53b2393271ae58b5ca927480c94cc5fee62266e20d6c`
