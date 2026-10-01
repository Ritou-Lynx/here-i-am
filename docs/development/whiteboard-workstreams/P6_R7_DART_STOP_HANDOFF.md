# P6 R7 Dart v2 stop receipt

更新：2026-09-11。此包只收紧文字任务队列的 Dart 消费端；不启用
`workbench_text_only_v1`，不改变普通会话 Runtime 路径。

## v2 绑定

启动回执必须为 `workbench_text_only_v1` / version `2`，并精确绑定
`local_session_id`、非空、有界的租约字符串 `execution_epoch`、`provider_thread_id` 与
`provider_metadata.provider_session_id`，同时仅接受
`isolation_verified=true` 和 `tools_disabled=true`。

文字 turn 回应必须带有同一 `local_session_id`、`provider_thread_id`、
`execution_epoch`、非空 `local_turn_id` 和 `provider_turn_id`。调用发起后
在回应未知期间保留为 reserved；它不能作为无 turn 的成功关闭。

停止回执必须精确回显 profile/version/session/epoch/thread，并有
`local_child_close_observed=true` 和 `proxy_drained=true`。有 turn 的普通
关闭只接受绑定的 `closed`、终态 confirmed、允许的
`completed|failed|interrupted` 和正的 terminal sequence。队列暂停或取消
额外要求本次 interrupt 已派发及 sequence、终态为 `interrupted`、
`cancellation_confirmed=true`，且 `provider_terminal_sequence` 必须严格大于
非负的 `interrupt_dispatch_sequence`；completed/failed 只能是普通关闭，不能让
队列宣称已暂停或取消。无 turn 只接受未派发 interrupt 的
`closed_without_turn`，并明确回显空的 `local_turn_id`、`turn_id` 和
`interrupt_dispatch_sequence`。

若 turn POST 已发出但结果仍 reserved，Dart 会先将 canonical session 标为
closing，再只发一次绑定 session 的 DELETE，让 host 关闭 CLI/proxy；无论其
回执为何都只返回 `runtime_stop_unconfirmed`。迟到的 POST 回应不能把 closing
session 重新标为 started。每个 canonical session 的 close future 会合并并发
调用，避免重复 DELETE。

当前 Dart 缓存会保留一次 close 的 transport failure，避免把未确认的
teardown 错称已关闭；它尚未提供跨进程的 owned-child retry/recovery。该恢复
责任留给后续 host 候选超时与进程所有权接线，不能据此启用生产 profile。

## 验证

- `dart analyze`：两个 Dart 源文件和两个专项测试，无诊断。
- `flutter test`：`workbench_text_task_runtime_client_test.dart` 与
  `workbench_task_queue_execution_test.dart` 通过。

这些是本地 fake/transport 回归。真实 provider、不可旁路生产代理、进程
来源隔离和用户生命周期 Gate 仍是生产放行前置。
