# P6-R2-B 独立文字执行接线返修

2026-09-07；基线 `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`，分支 `codex/whiteboard-w0-p6-r2-execution`。按主窗最后指令交付可选择性集成的源差异，未提交、未推送、未构建、未操作真实 Bridge / App / 设备 / 数据库。

## 当前结论

执行 owner、持久请求去重、epoch fence 与生产接线已实现并通过合成验证；**真实文字执行仍未启用，P6 / Goal 1 未完成**。C2 发现请求 `input.additional_tools` 仍包含内建能力，专用 `workbench_text_only_v1` 当前必须在 Bridge 返回 501 / unsupported_capability；不能退回普通聊天 Runtime。所有成功执行与停止回执测试均为 fake transport 证据，不代表真实模型或真人 Gate。

## B 拥有文件

- `lib/data/memory_v3/services/task_room_service.dart`
- `lib/data/workbench_ai/workbench_runtime_client.dart`
- `lib/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart`
- `lib/data/workbench_ai/task_queue/workbench_task_queue_execution_controller.dart`
- `lib/data/workbench_ai/task_queue/workbench_task_queue_execution.dart`
- `test/data/workbench_ai/task_queue/workbench_task_queue_execution_test.dart`
- `test/data/workbench_ai/task_queue/workbench_text_task_runtime_client_test.dart`
- 本 handoff。

A 的 host 与既有 runtime queue tool test 仅机械复制进本 worktree 作为验证依赖；host 最后按主窗授权补两项 lint（if 花括号、移除冗余 String 判断）。不将 A 的完整源差异冒称 B 独立交付。`WorkbenchConversationCoordinator.instance` 已调用 `.production()`，无需改 coordinator 源；主目录 P5 的 coordinator 测试改动未触碰。

## 行为与接口

- controller 五方法 `start/resume/retry/pause/cancel` 均为 `Future<bool>`，参数 `id/scope/requestId` 必填。返回值表示本请求是否真正接受状态变更；持久重放返回 false，不依赖可能受后台事件影响的快照比较。
- enqueue 与构造 owner 均不启动任务、不扫库。明确 start 才 claim 指定任务；starting 保持 pending，真实 startTurn 返回后才 running。running 期间比例保持未知（0），只有真实非空 completed 事件才 100。
- `__queue.execution` 保存 epoch、phase、序号与有界文字；输出上限 24,000 字符、status preview 上限 500 字符、每次尝试最长 10 分钟。结果不写主对话、Card、TaskArtifact 或 User-truth。
- resume 在全新受限 session 按目标和保存的部分文本重新执行，明确不是恢复同一 provider turn。retry 原子增加既有持久上限计数。请求 ledger 不驱逐旧键，上限 128；到上限明确拒绝。
- `cancelPendingTaskQueue({id,scope,requestId}) -> Future<bool>` 在同一事务检查从未开始的 pending 与执行 claim 竞争；无 controller 时只能走此纯等待态取消。start 与 stop 都核对 queue scope、conversation 和 permissions。
- pause/cancel 先原子标记 stopping 阻止迟到事件，再 interrupt + terminal-confirming close；无法确认即 blocked/interrupted，不声称已停止。丢失 owner 的 interrupted 不直接冒称 cancelled。进程恢复额外识别 pending/starting，旧纯 pending 不变；恢复后旧 epoch 事件不可写入。
- 专用 client 固定发送 `config.runtime_profile=workbench_text_only_v1`。成功必须存在 `execution_profile_receipt:{profile:'workbench_text_only_v1',version:1,isolation_verified:true,tools_disabled:true}`；停止必须存在 `stop_receipt:{profile:'workbench_text_only_v1',version:1,session_id:<exact local session>,provider_terminal_confirmed:true}`。C2 同意此未来启用契约，本轮没有生产成功回执。
- 旧 Bridge 200 无隔离回执时先尝试清理，再拒绝任何 turn；清理失败显式标记未启动但关闭未确认。未认证 profile 的固定 host 错误为 `text_only_isolation_unverified`。专用 client 对同 session 并发 turn 同步占位，拒绝重复启动。

## 验证

- 初版核心 + service：62/62。
- B + A 五文件组合（execution、text client、runtime tool、旧 client、service）：86/86。
- 组合后补清理失败与同 session 并发启动两个回归，受影响 text client 9 + execution 20：最终 29/29。最终五文件总数应为 88，由主窗独立复验，不把分批结果伪称单次 88/88。
- 最终 changed-file analyze：No issues；diff check 通过。
- 验证覆盖真实执行 owner + fake gateway + 内存 Drift / 临时文件数据库重开；重放 start/resume 完成态、retry 新 owner 去重、旧 pause 不停新 attempt、stop 与晚完成、queued cancel 两个事务顺序、旧 pending 保留、profile 501 零 turn、旧 Bridge 无 receipt 拒绝与清理、停止回执缺失或错 session 拒绝。
- 初次 flutter.bat 无输出后已结束该工具进程；直接 snapshot 在沙箱因共享 SDK lockfile 权限失败，受控提升后测试成功。未修改 SDK、依赖声明、lock、schema 或生成源。Drift 的多数据库 debug 提示来自测试中独立内存 DB 与临时文件 DB 同时存在，不共用 QueryExecutor。

## 主窗下一步

2026-09-07 W0 已选择性集成 B 七个源码/测试文件、A host/test 和 C2 Bridge 包；Dart 9/9 与冻结源文本一致，原 P5 coordinator 差异 198+/4- 保留。主目录单次组合 122/122（P6 五文件 88 + 普通聊天 26 + 关系/只读上下文 8），Bridge 31/31，9 文件 analyze 零问题，diff check 通过。

后续须先证明真实无内建工具、MCP、hooks、额外上下文和外部副作用的隔离运行时及可信停止回执，再启用专用 profile、构建唯一候选并做真实执行与恢复 Gate；本轮不构建或重启候选，P6/Goal 1 未通过。
