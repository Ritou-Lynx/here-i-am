# P6 R7 App candidate acceptance entry design

2026-09-12. The original design below has now been implemented as an independent
debug-only candidate. See [current App acceptance](P6_R7_APP_ACCEPTANCE_20260912.md)
for the frozen build, completed-task/restart evidence, and remaining startup
cleanup/lifecycle checks. Production `workbench_text_only_v1` remains disabled;
this design document itself is not execution or human-Gate evidence.

## Goal and invariants

The acceptance entry must exercise the real Flutter lifecycle callback, the
existing `WorkbenchRuntimeTaskQueueTool.production` path,
`WorkbenchTaskQueueExecution`, `TaskRoomService` transactions, and
`WorkbenchTaskQueueLifecycleOwner`. It must not be a separate demo that calls
the native adapter directly.

It must run in a separate process against all of these explicit candidate
resources:

- one temporary database directory owned by the candidate run;
- one deterministic database filename within that directory so the same
  candidate can demonstrate restart persistence;
- one fixed public task title and one fixed public one-sentence goal; no user
  conversation, prompt, account data, or production task is copied into it;
- one dedicated loopback-only Bridge endpoint, whose listener identity and
  frozen native-candidate attestation are established before App launch;
- one explicit debug-only entry token. Absence of every token leaves the normal
  `main.dart`, production queue composition, and profile gate unchanged.

Fresh initialization must reject a non-loopback URI, a non-empty candidate
database location, a missing candidate-host attestation, or an ordinary
release/profile build before opening the database. The sole restart mode must
instead require the same candidate manifest, exact candidate directory, fixed
database filename, and a recognized candidate schema marker. It must reject
every other non-empty directory. It must never reuse port 47831 merely because
an existing Bridge happens to be listening there.

## Recommended shape: independent candidate main

Use an independent target such as `lib/p6_r7_candidate_main.dart`, selected
only with `flutter run -t` for a debug build and explicit candidate defines.
This is smaller and more truthful than an existing debug route.

The current debug routes are embedded in the ordinary application startup,
which initializes the application singleton database and services before UI.
Adding this case there risks opening the user database before the isolation
check. It would also make route presence look like a normal product feature.
A separate target can perform its database ownership check before creating any
application singleton, yet still render a real Flutter `MaterialApp` and
receive `WidgetsBindingObserver.didChangeAppLifecycleState` callbacks.

The candidate main is not a standalone controller demo. Its composition is:

```text
candidate-main
  -> isolated AppDatabase + TaskRoomService.init(temp database)
  -> WorkbenchTextTaskRuntimeClient(bridgeUrl: fixed candidate loopback URI)
  -> WorkbenchRuntimeTaskQueueTool.production(
       runtime: candidate client,
       lifecycleOwner: candidate owner)
  -> small Flutter page calling tool.invoke with the usual trusted
     WorkbenchTaskQueueAuthorization
  -> candidate lifecycle observer calls the same owner on detached
```

`WorkbenchRuntimeTaskQueueTool.production` is the important reuse point:
`lib/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart:40-76`
already creates the ordinary `WorkbenchTaskQueueExecution` and registers its
actual controller with the provided lifecycle owner. The page should invoke the
existing tool with a candidate-local `TaskQueueHostScope`, first enqueue the
one public task, then expose only start, status, pause, resume, cancel, and
retry for the exact returned task ID. It must not use the conversation
coordinator, persona message service, or a hand-written replacement controller.

The lifecycle observer must copy the production behavior rather than invent a
new cancellation policy: page dispose, navigation, paused, hidden, and
background do nothing; `detached` invokes
`candidateOwner.closeForHostLifecycle()` without awaiting it as a stop proof.
The owner and controller retain only their in-memory bindings and use the
bound text close receipt. The UI may display `blocked/interrupted`, but never
turn an interrupt ACK or completed HTTP request into cancelled/completed.

## Candidate inputs and startup checks

A minimal candidate configuration object should be constructed only by the
independent main and contain:

| Input | Constraint |
| --- | --- |
| candidate enable define | exact debug-only value, otherwise exit before DB open |
| database directory | Fresh mode requires a newly created, candidate-owned empty directory. Restart mode accepts only the same manifest-bound directory with its candidate schema marker; reject production/default and arbitrary non-empty locations. |
| database file | Fixed name under that directory; retained only across the intentional restart phase and verified against the same manifest. |
| bridge URI | exact loopback `http` URI and dedicated port registered in the frozen host attestation |
| host attestation | fixed safe fields: candidate hash, listener port, profile name, native-ready/close-proof capability booleans; no raw logs or account information |
| task text | hard-coded public sentence, bounded title/goal, not editable from the UI |

The host attestation is an admission check, not a substitute for turn or close
proof. The candidate main does not set Bridge environment variables, spawn
Node, select a Codex executable, read credentials, or replace an existing
listener. The separately started candidate host must already be verified as the
owner of its port. If it is unavailable, the page remains disabled and no task
row is written.

## Persistence and restart boundary

The temporary database is intentionally retained across exactly one controlled
candidate restart. Fresh mode writes its candidate schema marker before it
creates the fixed task. Restart mode must verify that marker, the manifest, and
the fixed database filename before it reopens the file; it must not treat a
merely non-empty directory as resumable candidate state.

The first process may enqueue and start the fixed task. On next start, the
existing `TaskRoomService.restoreInterruptedTaskRoomsOnce()` must run before
the UI exposes the row. Its current implementation reclassifies only durable
`running` rows and `pending` rows whose execution phase is `starting`,
`running`, or `stopping`, writing `blocked/interrupted_by_restart`; it does not
prove that a process killed before any durable write had persisted an outcome.
After that recovery pass, the candidate must not automatically dispatch a new
session or turn, and a recoverable row requires explicit Resume or Retry.

The restart acceptance does not prove recovery from OS kill. It proves only
that candidate-local durable state survives a controlled relaunch and does not
auto-run. If the prior exit cannot be matched to a durable row and the native
host evidence, the result is unknown; the candidate must not fabricate an
offline `blocked/interrupted` write. Removing the candidate directory belongs
after the acceptance result is recorded; it is not an App operation and must
not target an arbitrary path.

## Acceptance sequence

1. Freeze and independently attest the native host, including listener
   identity on the dedicated loopback port and no-turn startup/close evidence.
2. Start the debug candidate with an empty candidate directory and valid fixed
   config. Confirm the UI identifies the candidate database and host only by
   non-sensitive fixed labels.
3. Enqueue and start the one public task through the displayed real queue tool
   action. Confirm the ordinary controller receives a v2 isolation receipt
   before the turn can be reported started.
4. Exercise visible page navigation and backgrounding: the task remains owned
   and continues under the existing semantics.
5. Exercise explicit cancel. Accept `cancelled` only if the bound receipt
   proves cancellation; otherwise require `blocked/interrupted`.
6. Exercise a controlled detached/host-exit path. Treat the callback as
   best-effort; compare the native host's actual closure evidence separately.
7. Relaunch the same candidate database. Confirm no automatic task dispatch;
   inspect the one task and require explicit resume/retry if it is recoverable.

## What remains human and host evidence

Automated Dart and loopback tests can prove composition wiring, strict config
rejection, task-state serialization, and the owner’s fake receipt behavior.
They cannot establish the operating-system lifecycle delivery, real page exit
observation, Android background behavior, native child/Job/EOF convergence,
forced host loss, or provider completion. Those steps require a person using
the debug candidate plus the independent native-host evidence from the same
frozen candidate. A normal HTTP close, an interrupt ACK, and Flutter detached
event do not complete that evidence.
