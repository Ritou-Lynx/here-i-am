# P6 R7 受控产品会话组合交接

日期：2026-09-14。范围仅为产品入口将来可注入的受控队列会话组合；未接入 coordinator、默认生产配置、host 启动或应用关闭链。

## 本次交付

- `WorkbenchTaskProductSession` 必须显式接收已打开的 `TaskRoomService`、已经过上游验证的 text runtime 与其 `startTextSession` 函数。构造只组合资源：不使用 `production()`、`TaskRoomService.instance` 或 lifecycle 单例，也不 admission、scan、recover、启动 host 或执行任务。
- 会话创建唯一的 `WorkbenchTaskProductSessionExecution`、本地或显式注入的 `WorkbenchTaskQueueLifecycleOwner`，并以同一 execution 供应 `WorkbenchRuntimeTaskQueueTool`。执行器沿用队列状态机，额外保留每个 start/resume/retry 的旧 monitor tail。
- `WorkbenchTaskProductSessionBinding` 是可信产品 bootstrap 必须提供的最小检查口；必需的 `afterInvoke` 则在每个实际 host result 返回前完成 trusted binding。它们只接收原 authorization factory 的 authorization 和已经穿过 host 的 result；模型 payload 仍不能指定 TaskRoom、scope、task 或 native 身份。首轮单 task/可信 host 绑定应在该接口实现中核验，不能由本模块推断。
- 所有 tool invoke 按会话串行。实际 dispatch 前重新核验 binding，result callback 完成后才允许下一次；callback 异常会保留已有队列记录并永久冻结会话，返回固定 `task_queue_session_unavailable`，不伪造 rollback。`quiesce()` 先同步关闭新 invoke，再等待已获接受的调用；排队但未 dispatch 的调用在重新核验时拒绝，因此不会产生 quiesce 后 DB 写。旧 tool 引用之后也返回同一固定失败。`drainAcceptedInvocations()` 与 `execution.drainExecutionTails()` 供关闭编排分别 join invoke 与 retained monitor，但本模块不关闭 host、Store 或 client，也不主张 native 终态。

## 验证

专属测试覆盖独立内存库不串写、每会话唯一 owner、构造和拒绝 binding 零执行副作用、首次 enqueue result 绑定前并发调用不越过、callback 失败冻结但保留队列记录、quiesce 等待已接受 invoke 且拒绝未 dispatch 排队项，以及原 authorization factory 的否定原话和 scope 限制。

验证使用可写 Flutter SDK 环境执行目标测试和新增文件 analyze；未构建、安装、提交或推送。
