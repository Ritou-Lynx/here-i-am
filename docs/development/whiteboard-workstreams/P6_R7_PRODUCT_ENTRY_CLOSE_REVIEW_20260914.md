# P6 R7 产品入口与关闭复核（限定只读）

日期：2026-09-14。复核对象限定为两处已跟踪修改：
`lib/data/services/persona_chat_service.dart`、`lib/ui/character/widgets/persona_chat_screen.dart`；以及四个新文件：
`lib/data/workbench_ai/product/workbench_task_product_close.dart`、其测试、
`lib/data/workbench_ai/workbench_desktop_user_message_store.dart`、
`lib/data/workbench_ai/workbench_desktop_conversation_entry.dart`。

未读取真实 DB / auth，未运行 App、provider、UAC 或 worker。本轮只检查源码、局部 diff 和已有测试声明：close `11/11`（实际 `575a06`）与 analyze `92f5e8` 已由主控报告通过；helper 提取与 session 组合 `40/40`（实际 `77ce42`，含既有 whiteboard 36）已报告通过；四文件合并 analyze 仍在 `20066`，本复核不把它写成已通过。

## 结论

在限定范围内未发现可验证的 P1 或 P2 问题。新候选代码尚未接入普通 `main.dart`，也没有构成 native / 实机 Gate；本结论仅说明本次关闭状态机与共享桌面发送 helper 的静态合同没有发现阻断性矛盾。

## 关闭状态机

`WorkbenchTaskProductClose.close()` 在返回前同步将 phase 从 `accepting` 切到 `quiescing` 并执行 `fenceNewWork`。同一未完成 Future 会被并发调用复用，因此输入/关窗重入不会启动两条 close 链。fence 抛错会永久保持非 accepting 并阻止后续资源阶段。

确认的顺序为：关闭 conversation → join 已发 queue invocation → close queue lifecycle → close owned host → drain execution / Store / client → record `app_closed`。每一前项都先确认，后项才可开始；因此 DB/client 不会先于 owner / host 关闭。`P6R7CandidateSessionResources.close()` 的 unknown 结果被缓存，witness 写入也被缓存；后续 no-op close 不会把 resources 或 witness 的未知状态重新解释为成功。conversation、queue、host 的未知结果允许使用同一 owner 重试，仍保持 fence，不恢复接受新工作。

现有 close 测试覆盖了同步 fence、pending close 的 future 共享、conversation/queue/host 重试、未 join 的 invocation 阻断、resource/witness unknown sticky、fence 失败和 fence 内 reentrant close。没有发现资源顺序、并发重入或 unknown sticky 的 P1/P2 缺口。

## 原话入口与兼容性

新的 `WorkbenchDesktopUserMessageStore` 只抽取 `addUserMessage` 的既有窄签名，没有提供 DB 默认值或队列能力。`PersonaChatService implements WorkbenchDesktopUserMessageStore` 保持其公开方法签名与原有普通 singleton 行为。

`sendPersonaDesktopConversationEntry()` 仍先持久化 `userText`，再调用 `afterPersist`，最后才调用 coordinator connector；因此 helper 没有把 Runtime / queue 调用移到持久化之前。它传递原样 `userText` 和 stable conversation id，保留 queue factory 以这两项计算原话授权的合同；持久化 `userMessageId` 继续随 coordinator 传递，供白板消息证据使用。

`PersonaChatScreen` 只改为 import/re-export 该 helper，原有导出符号 `PersonaDesktopConversationConnector`、`connectPersonaDesktopConversation`、`sendPersonaDesktopConversationEntry` 仍可从原 screen 路径取得。该接口抽取为候选受控 chat store 注入提供必要 seam，没有新增 `MemexRouter`、`AppDatabase`、provider、endpoint 或自动后台依赖。

## 后续小检查

等待 `20066` 的四文件 analyze 真实结果；若失败，只按报出的文件与诊断做小修。接线阶段还需单独证明候选 composition 实际使用该 helper 和 close controller，并继续禁止其经由普通 `main.dart`、默认全局 provider 或现役 host 获得隐式数据/执行路径。
