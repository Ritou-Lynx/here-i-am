# P6-R2-A Target Lock Handoff

## Scope

- Baseline: `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`.
- Owned changes only: the queue host and its runtime-tool test coverage.
- No TaskRoom service, Runtime wrapper/coordinator, schema, dependency, P5,
  persona, generated-file, device, database, or UI changes.

## Delivery

- `WorkbenchTaskQueueAuthorization` now holds one trusted, per-turn exact
  `targetTaskId`, plus an explicit ambiguous-target marker. Runtime payloads
  cannot grant, replace, or omit that target for a write.
- Production authorization extracts only one explicit UUID from current user
  text. A direct internal authorization can still inject a synthetic task ID
  for bounded harness coverage; that is not production text extraction.
- `pause`, `resume`, `cancel`, and `retry` now require a matching exact target.
  “这个任务” without a reliable target returns `task_target_required` rather
  than selecting the newest task. A mismatched payload returns
  `task_target_not_authorized`; multiple named targets return
  `task_target_ambiguous`.
- An explicit-target `status` call is equally locked. Only targetless,
  user-authorized `status` preserves the scoped newest-task read-only path.
- Existing per-action negation remains in force before target resolution.
- `start` is separately authorized only by explicit start wording plus one
  user-named UUID; enqueue never starts a previously queued task. Target,
  action, and scope checks precede the optional execution-controller port.
  Without that port, start, pause, resume, and retry reject without a write.
- Controllerless cancel uses B's `cancelPendingTaskQueue` transaction to
  recheck that the task has never started; a stale pending snapshot cannot
  overwrite a concurrent execution claim. Active states require the controller.
- The shared controller methods return `Future<bool>` from durable claim/control
  results. Host `changed` never compares snapshots that background progress may
  alter. Replays reach B's ledger before state eligibility is checked.
- Fixed controller errors never expose arbitrary exception text;
  `text_only_isolation_unverified` explicitly reports that no task was started.

## Automated coverage

- Two same-scope tasks A/B: user authorizes A, while a model supplies B or no
  ID; both reject with zero write and B’s complete queue snapshot remains
  unchanged. The matching A control succeeds.
- Explicit status cannot read B or fall back when A was named. Generic status
  remains read-only and scoped. Multiple targets, targetless lifecycle wording,
  and a negated write are fail-closed.
- Existing unknown/cross-scope, payload-injected authorization, ordinary-chat,
  durable idempotency, lifecycle, and restart-recovery coverage is retained.
- Start coverage verifies explicit-ID authorization, no-controller zero-write
  rejection, controller-backed start, and targetless-start rejection. The
  test harness has a small controller fake; W0 must still inject production.

## Verification

- Final W0 integration (2026-09-07): A's 12 host tests are included in the
  single 122/122 combined run; all nine changed Dart files analyze cleanly.
  The SDK failures below describe the early isolated attempt, not final status.
- Targeted `dart format` on both changed Dart files: passed.
- `git diff --check`: passed after formatting.
- Targeted `dart analyze`: not passed because the shared Dart analysis server
  crashed while deleting its Windows perf witness file (`OS Error 1920`), exit
  code `4`; it did not report a source diagnostic before the host failure.
- Targeted Flutter test: not passed because Flutter `3.44.0` crashed before
  test discovery in `testCompilerBuildNativeAssets` with `Bad state: No
  element`. The generated local crash log was removed. No build, pub upgrade,
  device, real database, or UI action was run.
- This package intentionally depends on B's shared
  `TaskQueueSnapshot.executionPhase` and `resultPreview` fields. They do not
  exist in this old baseline, so A cannot compile alone until W0 integrates B's
  service patch; no fallback weakens the `pending + starting` guard.

## Integration notes

- This package intentionally does not add Runtime/controller host selection.
  A future reliable UI selection must populate the same host-owned exact target
  before this host boundary is invoked; it must not be inferred from a payload.
