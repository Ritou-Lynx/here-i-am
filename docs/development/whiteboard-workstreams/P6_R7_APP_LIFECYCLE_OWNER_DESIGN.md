# P6 R7 App lifecycle owner candidate

2026-09-12. This document records the ownership gap found by the initial
read-only audit and the current local candidate that addresses it. It does not
enable `workbench_text_only_v1`, establish production composition beyond the
candidate injection path, start an App, or establish native/provider/real-host
evidence.

## Historical gap closed by this candidate

Before this work, `WorkbenchRuntimeTaskQueueTool.production` cached an
execution controller in an `Expando` per `TaskRoomService`, but there was no
application-level owner to close those existing in-memory controllers. The
persona page is not that owner; page disposal must continue queued work. The
app lifecycle observer also had no text-session path. A generic HTTP DELETE,
an interrupt ACK, or a Dart `dispose` cannot prove a native child, Job, or
broker has stopped: only the bound v2 text stop receipt can do so.

The candidate preserves the confirmed product behavior: navigation, `paused`,
hidden, and background states continue existing work. It adds best-effort
lifecycle handling only for `AppLifecycleState.detached`. This does not add an
automatic restart: durable blocked/interrupted work remains recoverable only
through explicit resume or retry.

## Current implementation boundary

`WorkbenchTaskQueueLifecycleOwner`
(`lib/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart`)
is an application-level singleton with no database initialization side effect.
`WorkbenchRuntimeTaskQueueTool.production` registers the exact controller it
creates or retrieves for the existing `TaskRoomService` Expando identity. It
does not construct a replacement controller to perform shutdown, and it does
not scan durable task rows.

`WorkbenchTaskQueueExecution.closeForHostLifecycle` synchronously fences new
start/resume/retry work. It joins already registered control futures, then
closes only current in-memory attempts and retained unconfirmed bindings using
the existing bound text close route. `main.dart` starts this owner only for
`detached`; it observes the result without claiming success. Flutter cannot
guarantee that an asynchronous close completes after engine termination.
Native stdin EOF, lease, and Job behavior remain the authoritative final
convergence mechanisms for a host exit.

## Lifecycle truth rules

| Situation | Candidate behavior | Durable result |
| --- | --- | --- |
| Page disposal, navigation, paused, hidden, background | No lifecycle close | Existing task continues. |
| Explicit pause/cancel | Existing queue path | `paused`/`cancelled` only when its existing receipt rules prove it; otherwise blocked. |
| Runtime HTTP/read-events loss | Existing monitor attempts bound close | `blocked`, `runtime_connection_lost` when ordinary closure is unconfirmed. |
| `detached` | Best-effort owner close of existing in-memory bindings | Blocked/interrupted; no fabricated cancellation or completion. |
| Next start | No automatic in-memory recovery | Explicit resume/retry is required. |

The owner result is an aggregate boolean: `true` means every binding it owned
in that drain had an ordinary-close proof (or no session had ever been
created); `false` means at least one closure or durable interruption result
remained unknown. It is not an App process-exit guarantee.

## Four lifecycle audit fixes

1. The execution controller fences every asynchronous claim/create/write/turn
   seam and waits for registered controls during lifecycle close. A session
   returned after shutdown is closed by its exact record before a turn starts.
2. Monitor cleanup retains an attempt whenever ordinary close proof fails,
   instead of removing it from the active map and losing lifecycle retry
   ownership.
3. Each attempt fixes its first close binding (`interruptRequested`), shares an
   in-flight close, caches only a proven receipt, and resets a failed close for
   retry with that same binding. This prevents a monitor close from later being
   retried with incompatible parameters.
4. The lifecycle registry drains a stable epoch and per-controller close
   futures. Controllers registered while a drain is active are immediately
   fenced, included before the aggregate settles, and can make that aggregate
   `false`.

The post-claim boundary has a dedicated regression without a production test
hook. A test-only `TaskRoomService` subclass completes the real durable claim,
then delays delivery of its lease. Lifecycle close remains pending until that
lease reaches the controller; it is persisted blocked/interrupted and no
session, manifest, or turn input is created.

## Local verification and limits

- 43 focused Flutter fake-runtime tests passed across execution, lifecycle
  owner, and production-tool tests. They exercise delayed creation, delayed
  post-claim lease delivery, ordinary close retry with a fixed binding,
  monitor retention, multi-controller aggregation, and late registry members.
- `git diff --check` passed for the owned lifecycle paths.
- Direct `dart analyze` could not complete because the local analysis server
  failed while deleting its pre-existing `C:\Users\ExampleUser\AppData\Local\Dart\perf`
  witness directory (Windows error 1920). No SDK, cache, or permission repair
  was attempted; this is not a clean analyzer result.

Candidate hashes at this checkpoint:

- `workbench_task_queue_execution.dart`:
  `A91F20869C41FFD1F41930066A011DFC95E9D08D781A0E0B7EAB4494F36954A6`
- `workbench_task_queue_execution_test.dart`:
  `ADDAE7A9971305A61B69BB54C37A9A36A2E893CD4B46139163A7F21A13E26DDE`
- `workbench_task_queue_lifecycle_owner.dart`:
  `D9E88C04FA78A39F2AF45DC232500644DEB0987505C6CB1A4F16F44589FF6A0B`

This local evidence does not prove Android/App runtime behavior, controlled
bridge shutdown, native EOF/lease/Job cleanup, provider closure, forced host
loss, or a human acceptance Gate. Those require separate App and native-host
validation against one frozen candidate.
