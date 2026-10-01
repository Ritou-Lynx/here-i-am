# P6 Long Task Queue Handoff

2026-09-29 最新：同一 Windows Debug App 哈希的隔离普通入口已由 [run11](P6_R7_RUN11_20260929.md) 与 [run13](P6_R7_RUN13_20260929.md) 覆盖 enqueue/status/start/failed/retry/pause/resume/cancel、短聊零任务、唯一精确完成结果、完成/取消态重启恢复及两代完整清理。生产 profile 保持拒绝；父 Goal 1 的唯一集成候选仍待收口。下方 9 月 7 日 R4/R3 与 W0 叙述为历史快照。

最新回收（2026-09-07）：[P6-R4](P6_R4_BEHAVIOR_VERIFICATION_PLAN.md) A/B 两包已集成，主控 Node 40/40；合法 exec 拒绝与协作查询实际执行已分辨，正常中断 terminal 与异常停止缺口已取证。生产拒绝门控和 P6 未通过状态不变，不操作原等待任务。

最新进展（2026-09-07）：[P6-R3](P6_R3_EXECUTION_ISOLATION_AUDIT.md) 三组隔离配置追加实测仍未通过；外层工具未被裁剪，当前 App Server 未查到正式全工具禁用参数。等待执行通道选择，原任务不自动启动；P6/Goal 1 未通过。

## P6-R2 已派发（2026-09-06）

用户已确认“派发吧”。[返修计划](P6_R2_REPAIR_PLAN.md) 登记 A 指定目标绑定、B 执行核心、C 权限预审及 C2 专用 Runtime profile。2026-09-07 主控已回收并选择性集成本地源码，122/122 组合回归、Bridge 31/31、9 文件 analyze 通过；不是新候选或真人通过。后文“只记录建议、未启动实现”及原始执行缺口属于派发前的旧候选验收历史。

生产后台执行在可验证 text-only 隔离完成前明确拒绝，不继承普通开发 Runtime 的工具权限。已有 synthetic pending 任务、验收 App 与手机连接保留，不自动执行。

## W0 当前真人验收与执行缺口（2026-09-06）

**当前结论：入队/等待态、指定任务只读 status 与 App 重启后 pending 保留样例通过，P6 整体未通过。** 后续写入真人 Gate 暂缓，先补指定任务强绑定及真实执行器。以下历史交付中的生命周期 API 只证明队列状态控制，不证明真实执行器已经接入。

- 同一桌面候选为 `4ba05b11` + 已记录 P5 源；exe SHA-256 `BD7B06FE74C589EC0F7443036E421674CBE76DA0E9B18D166F124CC9B83CA3CA`，kernel SHA-256 `28ED9BCA93D85AFA339D86DCB3C123651ECFFD802158FDBD2BB1A717978478AD`，本轮重新核对一致。四个 P6 关键源文件此前与候选 4/4 文本一致。
- 用户在 Here I Am 桌面请求只创建等待队列记录，不执行实际工作；回复报告已入队且没有开始工作。Computer Use 核对同轮回显，不代发或重复创建。
- 从 AppDatabase/drift 的当前用户 Documents 路径定位唯一应用数据库；以 SQLite `mode=ro` + `query_only` 只查询下列精确 ID 及其产物/决策计数，不检查其他任务/私人聊天，不复制数据库或保存截图。

| 指定测试任务字段 | 只读结果 |
|---|---|
| id | `fc91503a-0e59-4f7f-a480-14215e67cb05` |
| title / goal | P6 队列验收 / 验证队列记录能够保存 |
| status / progress | `pending` / `0` |
| executor / conversation | `workbench_runtime` / `persona:i` |
| host scope | `desktop_workbench_task_queue_v1` / conversation / `persona:i`，queue 与 permissions 匹配 |
| retryCount / maxRetries | `0 / 3` |
| created_at / updated_at | 均为 `1788699879844` |
| current_step / completed_at | 均为空 |
| artifact / decision counts | 均为 `0` |

**实现缺口（只读审计，未修改）**：

- `WorkbenchTaskQueueToolHost` 的 enqueue 调用 `enqueueTaskRoomIdempotent` 并固定 executor=workbench_runtime，后续仅 status 或 TaskRoomService 的状态迁移，没有启动/控制执行器。
- `TaskRoomService.resumeTaskRoom` 将可恢复 blocked 写为 running；pause/cancel/retry 也是队列元数据操作，并没有实际 executor 的暂停/恢复/取消握手。启动恢复确实会把持久 running 改为 blocked/interrupted，但当前队列没有诚实从 pending 启动执行的生产路径。
- `LinAiOrchestrator` 在另一个白板流程中创建自己的任务并调度自己的 router，不消费上述队列；不能借用它、手改 DB 或伪造 running/failed 来完成本 Gate。
- 需要补齐当前队列的真实执行 owner，才能完成执行层 pause/resume/retry 与运行中重启验证；该缺口与普通状态 API 可调用应分开记录，不能用现有自动状态机测试替代。

**status 样例（已通过，2026-09-06）**：用户返回同任务等待中、0%、重试 0 次且只查询。主窗再次以 SQLite `mode=ro` + `query_only` 只查询该 ID：上述 status/progress/retry、队列元数据、产物/决策计数不变，`updated_at=1788699879844` 仍等于入队基线。此轮未操作 UI，用户回显与 DB 证据分别记录；不扩张为全库无副作用。运行进程 `28892`、启动时间 `2026-09-06 17:57:53 +08:00`、P5 专用候选路径与两项完整 SHA 均再次核对，尚未重启。

**App 重启样例（已通过，2026-09-06）**：用户再次查询后返回 pending/0/retry0。主窗确认进程已从 `28892` 变为 `11748`，新启动时间 `2026-09-06 21:37:58.188888 +08:00`，同一候选路径及两项完整 SHA 不变；随后只读精确查询上述 ID，本轮复查的任务字段、__queue 元数据与产物/决策计数仍和入队基线一致，`updated_at=1788699879844` 不变。本轮未重新读取 permissionsJson。证明任务记录跨 App 进程保留，不只凭旧聊天文本；不覆盖 Bridge 重启或运行中恢复。

**取消预审新增缺口（源码证据，未实施实际写入）**：`WorkbenchTaskQueueAuthorization` 仅有 profileId/conversationId/allowedActions；factory 从用户原话匹配动作，不提取或保存被点名的 UUID。host `_resolveTask` 只检查 payload ID 属于当前会话 scope；省略 ID 会回落 latest。同 scope 内模型改传其他 ID/省略 ID 时，没有与用户点名目标相等的确定性校验。Runtime wrapper 与 coordinator 直接传递同一 authorization，没有外层目标绑定。故不能把“只取消这一条”的文字或一次正确模型调用说成强制目标边界。未观察到实际误取消，也未通过真实其他任务做反例测试。

**下一步**：返回现有 P6 工作包返修，先为用户指定目标建立宿主强绑定与错 ID/省略 ID/同 scope 非授权目标的合成拒绝回归，再补真实队列执行器并验证暂停/恢复/取消/重试及运行中恢复。此轮只记录建议，未启动实现、新 Goal 或取消测试；现有 synthetic pending 记录保留。手机只读授权到期不影响桌面队列能力，无需为了 P6 续期开权。

## Scope closed

- Queue core for `TaskRoomService`: enqueue, status lookup, pause, resume,
  cancel, retry, and interrupted-running-task recovery.
- Queue metadata is persisted in `TaskRoom.contextJson.__queue`; no Drift
  schema, migration, dependency, model payload permission, UI, Artifact Core,
  P4-T1, or mobile information-architecture change was made.
- Ordinary chat remains outside this API and does not create a `TaskRoom`.

## State and recovery contract

- `blocked` represents a paused task or a task interrupted by an app/Bridge
  restart. Recovery converts only persisted `running` tasks to `blocked` and
  writes an `interrupted_by_restart` marker, so status is never claimed to be
  still running after a restart.
- Retry is allowed only from `failed` to `pending`, is capped by persisted
  `maxRetries`, and increments persisted `retryCount`.
- Queue lifecycle metadata is host-owned and stored only under
  `contextJson.__queue`; model-provided payloads do not receive new authority.

## Changes

- `lib/data/memory_v3/models/task_room_enums.dart`: permit `failed -> pending`
  for retry.
- `lib/data/memory_v3/services/task_room_service.dart`: queue lifecycle APIs
  and metadata persistence/recovery.
- `test/data/memory_v3/services/task_room_service_test.dart`: lifecycle,
  invalid transition, failure/retry cap, idempotence, and restart-recovery
  coverage.

## Verification

- `git diff --check` passed before the handoff was added.
- `dart analyze` on the three changed Dart files: timed out after 60 seconds
  without output; not passed.
- Targeted `flutter test test/data/memory_v3/services/task_room_service_test.dart --no-pub --reporter expanded`:
  timed out after 60 seconds without output; not passed.
- Re-run analysis and the targeted test in a healthy Flutter toolchain before
  integration; also run `git diff --check` on the final staged package.

## Commit and remaining gates

- Implementation commit: `722594a8 feat(task-room): add long task queue core`.
- Handoff commit: recorded by this following P6-only documentation commit.
- Human Gate: validate Bridge/App restart with an actual long-running runtime
  task, confirming it becomes visibly resumable rather than falsely running.
- Human Gate: confirm short ordinary chat turns never call `enqueueTaskRoom`.

## W0 repair (2026-08-24)

- Repair implementation commit: `1dc8c33b fix(task-room): make queue recovery durable`.
- Production recovery: `MemexRouter` now awaits
  `TaskRoomService.restoreInterruptedTaskRoomsOnce()` immediately after
  `TaskRoomService.init`, before Bridge or UI can observe TaskRoom state. The
  per-service Future makes this startup recovery execute once.
- Atomicity: queue lifecycle transitions now re-read, validate, and persist
  both `TaskRooms.status` and `contextJson.__queue` inside one Drift
  transaction. This covers pause, resume, retry, failed-state metadata, and
  restart recovery; generic status/context updates preserve the same queue
  contract.
- Blocked semantics: only queue-marked `paused` or `interrupted` tasks may
  resume. Generic status updates also reject `blocked -> running` without that
  queue marker, and reject `failed -> pending` outside `retryTaskRoom`.
- Input and boundary guards: negative `maxRetries` is rejected; the standard
  `PersonaChatService.addUserMessage` path has an automated assertion that it
  creates no TaskRoom.

### Repair verification

- `flutter test test/data/memory_v3/services/task_room_service_test.dart --no-pub --reporter expanded`: 42/42 passed.
- `flutter test test/data/services/persona_chat_service_test.dart --no-pub --reporter expanded`: 11/11 passed.
- Changed-file `dart analyze` for the TaskRoom service, MemexRouter, and both
  test files: passed with no issues.
- `git diff --check`: passed before the repair implementation commit.
- Still required human Gate: validate a real Bridge/App restart while an
  actual long-running runtime task is active, and confirm its visible state is
  resumable rather than running.

## Production Runtime reachability repair (2026-08-26)

### Delivery

- Implementation commit: `21b74f42 feat(task-room): expose scoped runtime queue tool`.
- `WorkbenchConversationCoordinator.instance` now registers the
  provider-neutral `manage_long_task_queue` dynamic tool beside the existing
  search tool and dispatches its calls through a product-owned host adapter.
- The tool supports `enqueue`, `status`, `pause`, `resume`, `cancel`, and
  `retry`. When `task_id` is omitted, control resolves only the newest task in
  the current product conversation and host profile.
- Enqueue is reachable from ordinary desktop production chat only when the
  actual user text explicitly combines a long/background-task or task-queue
  marker with a create/start/queue verb. Lifecycle actions likewise require an
  explicit task/queue action in the current user text. Ambiguous short chat has
  no queue authorization.

### Host-owned scope and honest state

- Runtime payloads contain no `authorization`, `scope`, executor, task type,
  retry limit, permissions, or conversation field. Unknown fields are rejected.
- The host derives the exact `conversation_id` from the product call, stores a
  profile/scope marker under the existing `contextJson.__queue`, and writes the
  same scope to the existing TaskRoom conversation/permissions fields. A task
  must match all host scope markers before status or lifecycle control is
  allowed. Unknown and cross-conversation task IDs both return
  `task_not_available`.
- Queue metadata remains backward compatible: the new owner/scope keys are
  optional, while legacy `maxRetries`, `retryCount`, pause/interruption, and
  failure markers retain their existing wire names and semantics. There is no
  schema, migration, dependency, generated-file, UI, Artifact, P4, P5, mobile,
  or general Orchestrator change.
- Status responses expose persisted `pending/running/blocked/failed/...`, retry
  counts, resumability, current step, and persisted failure/interruption reason.
  Rejected/invalid/host-failed paths use explicit error codes and are returned
  to Runtime as failed tool calls; the adapter never reports a failed action as
  success.
- A new `TaskRoomService` instance still converts persisted `running` to
  `blocked + resumableState=interrupted + interrupted_by_restart`, preserving
  the host scope so the same product conversation can resume it after restart.

### Test code and deferred verification

- Added service coverage for host-scope round trip, legacy queue compatibility,
  and latest-task isolation by conversation.
- Added adapter/coordinator coverage for production dynamic-tool registration,
  enqueue plus full lifecycle, failure visibility, cross-scope/unknown ID
  rejection, payload authorization injection rejection, ordinary short-turn
  zero TaskRoom, and a fresh-service restart recovery.
- Per the repair-wave concurrency instruction, no Flutter/Dart test, format, or
  analyze command was run in this worker. `git diff --check` passed on the full
  staged implementation package before commit.
- W0 should run serially:

```text
flutter test test/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool_test.dart --no-pub --reporter expanded
flutter test test/data/memory_v3/services/task_room_service_test.dart --no-pub --reporter expanded
flutter test test/data/workbench_ai/workbench_conversation_coordinator_test.dart --no-pub --reporter expanded
flutter test test/data/services/persona_chat_service_test.dart --no-pub --reporter expanded
dart analyze lib/data/memory_v3/services/task_room_service.dart lib/data/workbench_ai/workbench_conversation_coordinator.dart lib/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart lib/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart test/data/memory_v3/services/task_room_service_test.dart test/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool_test.dart
git diff --check 7f7af225..HEAD
```

### Remaining gates and limits

- This repair exposes durable queue state and controls; it does not add a queue
  worker, claim that a `pending` task is already executing, mirror a provider
  Agent tree, or place TaskArtifacts on a board. Pause/resume apply only after
  the existing execution owner has honestly moved a task to `running` or after
  restart recovery has produced an interrupted `blocked` task. Retry applies
  only to an honestly persisted `failed` task.
- W0 still needs the single-candidate Windows/Bridge human Gate: enqueue an
  explicit long task from desktop chat, exercise eligible lifecycle actions,
  restart during a genuinely running task, verify the visible result is
  resumable interrupted rather than falsely running, and confirm ordinary
  short chat creates no TaskRoom.

## W0 audit follow-up: durable idempotency and negation (2026-08-26)

### Audit return

- W0 returned the first reachability delivery because `request_id` was only
  echoed: repeating the same enqueue could create multiple TaskRooms and did
  not satisfy the stable-ID/idempotency contract.
- W0 also found that positive keyword matching admitted explicitly negated
  writes such as “不要创建长任务” and “不要暂停任务”.

### Narrow repair

- Enqueue now persists `requestId` as an optional, backward-compatible
  `contextJson.__queue` field. `TaskRoomService` performs exact
  `host scope + requestId` lookup, payload comparison, and insertion in one
  Drift transaction.
- Repeating the same scope/key with the same normalized title/goal returns the
  original stable TaskRoom and `changed=false`, including through a newly
  constructed service instance. Reusing the key with different title/goal
  returns fixed `task_queue_request_conflict` and creates no row.
- Current-turn authorization now removes only the explicitly negated action.
  It recognizes narrow Chinese prefixes (`不要/别/不/无需/不用/不能`) and
  English forms (`do not/don't/dont/never/no need to`) directly attached to
  that action verb. It does not perform broad sentiment or NLP inference.
  Therefore “不要暂停任务，只查看任务状态” authorizes only `status`.

### Added evidence and deferred execution

- Service tests cover same-process replay, replay with a new service instance,
  stable TaskRoom ID, persisted request lookup, payload conflict, and row-count
  invariants.
- Runtime tool tests cover durable replay, fixed conflict, and Chinese/English
  per-action negation. Coordinator coverage proves a model-attempted enqueue on
  a negated turn is rejected and writes zero TaskRooms while an explicitly
  requested status action remains authorized.
- Only the four involved Dart files were passed to targeted `dart format`.
  Per W0 instruction, no Flutter/Dart test or analyze command was run. Final
  `git diff --check` and clean-state evidence are recorded in the worker return.
- Follow-up delivery commit: the commit containing this handoff section.
