# P6 R7 Dart close retry handoff

## Latest invalid-creation cleanup fix (2026-09-12)

An invalid execution-profile receipt or malformed provider binding still triggers best-effort DELETE of the newly allocated session ID. A generic HTTP success cannot verify native child/Job/broker closure, so `WorkbenchTextTaskIsolationException.cleanupConfirmed` now remains **false** whether that DELETE succeeds or fails. No new endpoint, fallback, or production availability is introduced. Regressions cover both invalid receipt and malformed provider metadata; root reran both targeted suites after the change: **44/44 passed**.

The latest standalone Dart analysis attempts exited 1 during the SDK analysis server's `server.shutdown`: its performance socket deletion raised Windows `ERROR_CANT_ACCESS_FILE` (1920). Those attempts were verification-tool failures, not clean results. Root then used the **same SDK's cached Flutter analysis entry point** on the same file: **No issues found, exit 0**. This follows the separate shutdown-path workaround recorded in [Dart SDK issue 63343](https://github.com/dart-lang/sdk/issues/63343). No SDK or global settings were changed. The earlier successful direct Dart analysis below belongs to the earlier source snapshot.

## Implemented scope

`WorkbenchTextTaskRuntimeClient.closeTextTaskSession` now records an immutable close binding for the exact session, optional turn identity, interrupt policy, and whether turn start was already unknown. An in-flight close remains shared by concurrent callers. A failed DELETE or invalid receipt removes only that in-flight future, allowing the exact same binding to issue another idempotent DELETE. A successful result remains cached.

Retries cannot change the turn or interrupt policy. Reserved/unknown start remains unknown across every retry and therefore cannot become a successful no-turn close even if a later DELETE response contains such a receipt. Retrying does not issue another start POST or interrupt request.

Targeted tests were added for failure-then-success, unknown-start retry, changed policy/turn rejection without another DELETE, and successful-close caching. The existing reserved-start retry expectation now reflects the second idempotent DELETE.

## Root verification (2026-09-12): passed

Root corrected the reserved-start test's first/retry DELETE counts to 1 then 2, and schedules the first close using `Future.microtask` so the in-flight binding is published before a reentrant transport callback. Direct Dart analysis of `lib/data/workbench_ai/workbench_runtime_client.dart` reported no issues. The targeted runtime-client and task-queue execution tests passed **44/44** using the existing cached Flutter tool entry point. No App build, installation, real queue mutation or human acceptance was performed.

The SDK batch wrapper was diagnosed separately; root used the cached Dart/Flutter entry point and did not edit SDK scripts. Worker-launched hanging command wrappers were closed after exact process identity checks. These local tests do not establish production native execution or real cancellation.

## Earlier worker verification: initially unverified

No Dart or Flutter test result was obtained. Scoped verification commands were started but the execution runner later reported `CreateProcess ... timed out after 15000ms waiting for runner spawn_ready`. No retry, process termination, configuration change, real runtime, device, network, or build action was performed after that failure. Root should inspect the scoped command sessions and run the target test and `dart analyze` only if its runtime is available.
