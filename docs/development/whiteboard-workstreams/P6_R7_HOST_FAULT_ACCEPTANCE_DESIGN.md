# P6 R7：宿主故障验收设计（未执行）

日期：2026-09-12。初始阶段为只读代码审计与验收设计；主控随后明确授权 v7 durable 增量，实现交接见末节。两阶段都没有实际启动 native / UAC / provider 或执行进程终止。主控先完成既定 v6 真实 HTTP、零模型请求场景；本文不把它们提前认定为宿主崩溃验收。

## 结论与当前候选

**当前 v6 在 Node 宿主终止后具备尝试清理的路径，但不能据源码断言所有资源必然正常回收。默认 stdin/stdout 管道同时随宿主丢失时，六项最终关闭证明存在明确的可观测缺口。若原始 Gate 要求默认管道下真实 crash 后的完整关闭证明，需要 native 的独立最终落盘回执；改变 stdout 拓扑只能作为另一个 EOF 诊断场景。**

复核时文件指纹：

| 文件 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_task_executor.cs` | `F0639BBD955F16C8739A75EDA9B45B22B704BAE670B1FEC4125518B946C120E6` |
| `tools/dev_agent_bridge/workbench_text_task_native_executor.mjs` | `86312753587445ED1D4FE4F784724C60E6FDB10F0A5F5FEC38E8BB314945E8B1` |
| `tmp/p6-r7-helper/windows_text_gate_task_executor.v6.exe` | `166637F47E38348CB33B715A0A666CC8A664667BBC5110F2BADF002843F456C9` |

本文行号绑定上述源码快照，后续修改须重新核验。

## 行级路径与观测下界

| 代码位置 | 已有行为 | 能支持的结论 |
|---|---|---|
| native `TaskPump.Poll`，L88 | `PeekNamedPipe` 失败只接受 109；设置 Eof，要求没有残留半帧 | 最后输入写端关闭后有 EOF 检测路径；其他错误或半帧触发异常路径 |
| native `Run`，L330 | stdin 由 `GetStdHandle(-10)` 建泵，stdout 回执写 `GetStdHandle(-11)`；安装前后及 resume 前检查输入 | 启动阶段宿主消失也可进入 finally，但未启动子进程时不能产生六项全真证明 |
| native `Run`，L331–334 | runtime 每轮先读输入；Eof 直接 break；异常设置 failed，尝试输出有限 error | ready 后空闲是最小、最可归因的注入点；不必先发模型请求 |
| native `Run`，L335–338 | 结束 CLI stdin，关闭 child-side pipe ends；`child.Stop()`；分别 drain CLI stdout/stderr | 清理不依赖 Node 的 JS finally；是否成功取实际 Stop/Drain 结果 |
| native `TaskChild.Stop`，L254 | 先等待，再按必要性终止 Job / 子进程；核 held PID/creation、signaled、Job Active/Total | kill API 返回值本身不是已关闭证明，实际字段由随后核验决定 |
| native `Run`，L340–350 | 确认 install helper，再按 exact owned scope 发 cleanup helper；关闭 helper/pipes/child/files | 清理可能继续请求 UAC；取消、超时、检查失败不会升级为成功 |
| native `Run`，L351–353；`TaskExitPolicy`，L74 | 汇总 Handles，输出 closed；只有完整 Send 返回才设 finalEmitSucceeded；缺 finalEmit 必须 exit 4 | stdout 读端已经消失时，最终输出失败会使完整历史证明不可得；exit 4 不能解释为无规则，也不能解释为一定有规则 |
| Node transport，L303–320 | 默认 `spawn(..., stdio: ['pipe','pipe','pipe'])`；没有供独立见证者使用的持久回执通道 | Node 终止会失去其管道端及 JS 监听器；默认代码无法在死后保存闭合 frame |
| Node transport，L178–181、L255–271 | 接受 exact closed schema；只有 actual owner exit 0/3、六项真且 pending false、postpin 才确认关闭 | stdout frame、退出码或进程缺席，任一单独都不够 |

Windows 进程终止会关闭其句柄；持有另一个进程的 process handle 会保留该内核对象以便等待/查询，但不会阻止它进入 signaled/退出状态。它与持有 stdin pipe writer 是不同对象。匿名管道读取的终止条件涉及所有写句柄关闭，因此 witness 不得保留或继承 native stdin 的写端。[Microsoft：进程终止](https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-process)、[匿名管道操作](https://learn.microsoft.com/en-us/windows/win32/ipc/anonymous-pipe-operations)。

## 现有文件不能拼成完整六项关闭证明

以下均以文件的路径、ACL、hash、attempt/nonce/owner/child/auth 绑定及冻结源码可信为前提；单独看到文件名没有证明力。

| 已有证据 | 最多支持什么 | 仍缺什么 |
|---|---|---|
| witness 预先持有的 native process handle，随后 signaled + GetExitCodeProcess | 原生 supervisor 的精确身份确已退出，actual exit code 已知 | 子 CLI 的历史 exact close、stdio EOF、规则缺席、helper actual exit、关闭 API 是否成功 |
| `closed.json` | L345 仅在 install.Accepted、JobZero 且 child.ExactClosed 分支写入；因此是到达该清理阶段的绑定标记 | L338 的 Stdio 结果不是 L345 写文件的前置条件；也没有之后 helper/全部句柄/最终输出状态 |
| `cleanup-ready.json` / `cleanup-ack.json` | 同 attempt 的 cleanup helper 身份/握手阶段信息 | 不是 helper exit，不是规则清除成功 |
| `cleanup-receipt.json` | helper 已在固定 scope 做过 RemoveAfterZero 与后验证，且写文件前 boundary/proof close 条件通过 | L317 在写 receipt 后才执行 `files.CloseVerified()` 并决定最终退出码；文件存在不证明 helper 最终 exit 0 或全部文件句柄关闭，也不含 supervisor stdio/句柄汇总 |
| install receipt + started barrier | 冻结 native 到达 started 时曾要求 install helper Accepted | 不替代后来 cleanup helper 的 actual exit |
| 后来的 exact 四键缺席检查 | 检查窗口中的规则不存在 | 不能倒推原操作的完整历史 stop receipt |

若 witness 恰好在 cleanup helper 退出前打开并绑定其 PID/creation/image handle，再观察 actual exit 0，可补该 helper 的实际退出信息；轮询 ready 文件不保证及时取得句柄。取得失败或只看到 PID 已不存在必须记 unknown，不能补写 true。即使取得 helper exit，现有材料仍没有 supervisor 的 Stdio drain 与全部 close 结果汇总。

**默认 v6 crash 的可观测下界：** 可保留绑定的宿主终止事实、native actual exit、上述有限阶段文件、必要时另做当前规则缺席检查；不能把它们合成为原始七字段 closed 回执。没有完整回执时保留 cleanup-unconfirmed；不修改旧 report。

## 推荐实施顺序

1. 主控完成已经安排的 v6 真实 HTTP、零模型请求场景，各自使用新 attempt / 新报告。
2. 若下一验收是默认 pipe 的 host crash，先实现并冻结下述最小 durable-final-receipt 增量；补纯测试/错误注入并独立复核，不先靠替换 stdout 结构宣告原始 Gate 通过。
3. 第一次 crash 只做 **no-auth、started 后空闲、零 RPC/零 turn**。它验证 native 宿主丢失后的进程/规则生命周期，不扩展成 HTTP/App/真实任务中断 Gate。
4. 再按后续授权扩展到真实 HTTP session-ready、零 turn；任务执行中 crash、网络失败、UAC 拒绝等各自独立验收。模型请求已发出的场景不能从空闲 crash 继承取消或服务端停止证明。

## 最小真实故障注入器与 witness

拟新增独立测试工具，例如 `windows_text_gate_host_fault_witness.exe --host-crash-after-started-no-auth`。此名称为设计入口，当前没有实现/执行。工具内部固定本轮 host 脚本/Node/native pins、一个新 attempt 与唯一故障点；不接受任意 kill PID、任意进程名或目录。

进程关系：独立 witness 创建专用 Node 测试宿主；Node 使用原 `launchWorkbenchTextNativeExecutor` 创建 native supervisor；native 创建并持有受限 CLI 与 cleanup helper。witness 自己不处在“随测试 Node 关闭即终止”的 Job 中，也不给测试 Node 创建会连带杀 native 的 Job。

最小时序：

1. witness 验证 Node、测试脚本、native 源码/产物与新证据父目录；建立一次性 attempt/nonce。witness 亲自创建测试 Node，保留返回的精确 process handle、PID、creation/image，不从外部任意 PID 获取终止授权。
2. Node 只调用固定 no-auth native 入口：`--apply-task-executor <本次新 attempt> <本次固定 loopback port>`。启动 helper 的 UAC 正常由用户处理。broker 不 arm；不初始化账号、不读登录 home、不发送任何 RPC 或 turn。等待 native `started` frame，经现有严格 transport 校验。
3. Node 以新建的有界 metadata 文件/私有握手通知 witness：本次 attempt/nonce、native PID/creation、started 已验证；不记录原始 RPC、输入、账号或凭据。witness 打开 native process handle，仅 `PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE`（0x1000 | 0x100000），核 live、PID/creation、精确 pinned image、与本次已创建 host 的绑定。未完成此步骤不注入。
4. witness 在注入前再次核测试 Node handle 的 PID/creation/image/live；只对该 held handle 调用 `TerminateProcess`，固定测试退出码如 197。随后 WaitForSingleObject + GetExitCodeProcess 确认精确宿主实际退出。禁止 SIGINT/CTRL+C/SIGTERM、`/host/stop`、`owner.close()`、stdin.end()，也禁止 taskkill `/T`、杀父进程树或 native/helper。TerminateProcess 是异步的，必须等待目标实际终止。[Microsoft API 契约](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-terminateprocess)。
5. witness **不继承、不复制、不保留 native stdin writer**；不接管或继续发送 stdin，不伪造 close command。默认 Gate 也不复制 stdout/stderr reader，保持原 pipe 断开条件。process handle 不延长 stdin 生命周期。
6. native 应继续运行并尝试 cleanup。保留正常交互 session，不提前结束外层终端/witness。cleanup UAC 由仍存活的 native supervisor 发起，其 proof 要求的是 native owner 本人存活和同 session，不依赖已经终止的 Node（L267–268、L288–304）。用户正常完成 UAC；若取消/超时，记录失败或 unknown，不把它变成无规则。witness 不代写 ack、不另起清理 helper。
7. witness 用已持有的 native handle 等待实际退出；native 提前随宿主一起被外部 Job/树终止，则本次不能归因为 native EOF 清理成功。超时只产出未确认状态，保留 handle/观察能力及原生清理机会，不为了结束测试自动杀 native/helper。
8. native signaled 后，记录 actual exit、重新核候选 pins，再严格读取本次唯一最终回执与必要 metadata；关闭 witness 自有句柄也须记录结果。所有输出 CreateNew、有界、无原异常/原始任务数据。报告绑定 candidate/host/witness hashes 与双方 PID/creation，不以 process-name 搜索缺席代替 held-handle 历史证明。

现有 v6 没有 `shutdown_reason` telemetry。`closed.command_id=0`、没有 close 命令、宿主已退出等只能结合冻结 L331 路径推断 EOF 触发，不应输出“直接观察到 stdin EOF”字段。新增 durable 回执可以由 native 在确认 `input.Eof` 时写有限 `shutdown_trigger=stdin_eof`，将这一点变为直接程序证据。

## 默认 pipe crash 所需的最小 native durable 增量（仅设计）

不改 WFP ownership/delete、Job/child 创建、Auth/home、helper 提权授权、生产 profile 可用性；保留默认三根 pipe。只增加当前 attempt 内一个固定、受保护、有限大小的最终证据文件及其验证规则。

- 固定新文件名，例如 `final-receipt.json`，只能位于本次 canonical protected attempt。提前用 CreateNew 取得受控写句柄并 hold 必要祖先，拒绝已有文件、重定向/reparse、错误 ACL 或任意外部路径。不读取/复制凭据；只写 attempt/scope/nonce、native/child身份、candidate hash、auth/home class、有限 shutdown reason、六项关闭事实和 pending。
- 先完成现有 child/stdio/helper/rules/native handles 清理与 pending writer 收敛。stdout 输出仍可尝试；失败应保留有限 operation-failed 状态，不能因此跳过清理或让 durable 文件自动宣称成功。
- **文件内容不能单独成为 commit。** 最终 JSON 写完、Flush(true)、该证据文件及其祖先句柄实际关闭、所有 sticky close failure 检查之后，才可产生允许接受回执的 actual exit。任何写/flush/close/postpin失败都必须是不可接受的退出码，并保留 pending/未确认。不要重演“已写 handles=true 后 evidence writer close 失败仍 exit 3”的旧漏洞。
- 建议沿用 exit 0 / 3 / 4 的明确分工：0 正常完成且完整关闭；3 操作或 stdout 丢失失败但独立 durable close 已完整；4 任一必需关闭/证据提交未确认。**现有 exit 4 不得因文件存在被外部降格接受。** 新逻辑须在所有最后写入和关闭之后计算 exit policy，纯测试覆盖完整真值表。
- 最终证据文件与写入它的句柄存在最后一步自证问题：采用“文件是待 actual-exit 验证的回执”的联合契约。文件字段说明该回执只有绑定进程实际 exit 0/3 才有效；observer 必须持有原 native handle，并确认新候选 exit policy 已包含证据写句柄关闭成功。不要把文件先出现当作完整关闭。
- stdout `closed` schema 可保持现状；独立 observer 使用新 durable schema，要求字段精确、类型严格、无重复字段、单对象/无尾随数据、大小有界，且 attempt/nonce/owner/child/hash 与启动绑定一致。Node 还活着的正常路径仍按原 stdout + actual exit + postpin 验收；已死 Node 的新 witness 不伪装成原 RuntimeAdapter session receipt。
- 缺文件、空/截断文件、错误身份/hash/nonce、错误 exit、关闭失败、helper 未确认、stdio drain 失败都必须 fail closed。no-child 失败仍不可伪造 Process/Stdio 真。

该增量的新 native SHA 与二进制必须独立冻结。v6 completed/interrupt 历史结果不能替新 native 候选完成回归；至少跑纯编译/协议/exit truth、正常零 turn 完整关闭以及默认 pipe 真实 host crash，之后再决定后续真实模型场景。

## 可选旁证：保留 stdout 的 EOF 场景

如果仅需先研究 EOF 清理，而暂不改 native，可用测试专用 launch 将 native stdout/stderr 送到独立新建的受限文件；Node 仍是 stdin 唯一 writer，witness 只读文件、持 process handle。只在 no-auth/无 RPC 的最小场景使用，避免落盘账号/任务内容。现有 exported launch 硬编码 pipe，因此需要单独测试 launcher；不能称为直接运行了原默认 launch。

这能让宿主死后 native 继续输出 `closed` 并由 witness 配合 actual exit 验证六项结果；可以支持 **“宿主终止、stdin EOF、stdout 独立可写”** 的清理证据。它没有同时施加 stdout reader 丢失故障，不覆盖默认三 pipe 的宿主 crash，也不关闭上面的默认可观测缺口。复制 stdout reader 给 witness 同样改变故障条件，且在 Node 仍读时存在竞争消费，不是更好的默认 Gate 方案。

## 最终报告必须分开的字段

- 注入：`fault_kind=terminate_exact_test_host`、新 attempt、host PID/creation、注入前绑定、TerminateProcess result、host actual exit。
- 拓扑：`default_stdio_pipes_unchanged`、`witness_owns_stdin_writer=false`、`witness_preserves_stdout_reader=false`；旁证场景必须如实改变相应字段。
- native：held PID/creation、still-live-after-host-exit、actual exit、新候选 SHA/postpin、shutdown trigger 的来源（直接 telemetry 或代码推断）。
- 关闭：六项事实、durable receipt hash、native final-exit commit verified、witness handles closed；与模型/provider terminal/用户 turn stop receipt 分开。
- 未覆盖项：UAC 非交互容错、UAC 拒绝、宿主与 native 同时崩溃、系统掉电、服务端计算停止、运行中模型任务、App/production/human Gate。任何单次进程缺席都不是这些事实的替代。

建议下一 native crash 的验收结论只写“本冻结候选、默认 pipe、已启动空闲 CLI，在精确宿主强制终止后，独立 witness 确认六项关闭与原生实际退出”。在 durable 增量及对应实测完成前，不写该结论为已通过。

## v7 durable 候选实现交接（未 actual）

主控确认上述最小契约后，worker 修改了 `tools/dev_agent_bridge/windows_text_gate_task_executor.cs` 与对应 `.test.mjs`。没有新增编译模块，没有修改 JS native transport 或共享产品文件；冻结 v6 source06 / exe 不变，v6 的任何 actual 均不提升为 v7 实证。

| 项目 | 指纹 / 结果 |
|---|---|
| 当前 native source | `47D3DA743598E17F92F2B3B7764226376097D015A7E337C3F27A9E7D8FBD5F92` |
| 当前 native `.test.mjs` | `0F1BA3A8669D4780F3C3343984AADA03998C19191E9B97554A2F0CF53D84BB26` |
| 相对 source06 diff | 70 行增加、7 行删除 |
| 独立待做 | 主控代码复核、冻结 source07/exe、真实零 turn 正常回归与默认 pipe host crash |

实现位置（此段绑定 v7 source）：

- `TaskExitPolicy` L71–74：必须六项完整、durableCommitSucceeded 且无 sticky close failure。stdout 失败归为 operation failure；正常成功 exit 0，完整清理的 operation/stdout 失败 exit 3；durable 任一失败强制 exit 4。
- `TaskFinalWrite` L155：纯委托事务，按 verify / absent / open / output pin / write / flush / output pin / post verify / output close / evidence close 顺序执行。任一异常/false 关闭结果使 commit 失败，有限关闭重试不改变第一次失败。
- `TaskFinalContract` L163：只选取十个 primitive binding 字段并重新校验；不复制 journal/token 对象。报告严格使用 `input_eof`、`close_command`、`operation_failure`，保留 started、close_command_id；关闭命令与 trigger 关系不匹配则拒绝。
- `TaskFinalReceipt` L187：prepared 后取得第二组只读 `TaskFiles` evidence pins，复用原 strict ACL/canonical/root/self/copied-CLI 验证，不访问 dedicated home；直到现有资源及最终 stdout writer 收敛后才创建文件。固定 `final-receipt.json`，CreateNew（Win32 disposition 1）、仅 share-read、验证新文件 final path、完整 WriteFile 计数、FlushFileBuffers、同句柄读回 SHA，最后检查两组 close。
- `Run` L390–416：EOF 分支记录 input_eof，显式 close 记录 close_command；原 Stop/Drain/helper/WFP/close 流程保留。stdout final Send 后再次 ClosePending，任何失败降低 Handles；然后写最终 durable 报告，并在全部证据关闭检查之后计算实际退出码。

新最终报告是 **21 字段**的 `p6_r7_task_final_receipt_v1`：schema；十个身份 binding 字段；child_pid/child_creation；started/close_command_id/shutdown_trigger/operation_failed/stdout_final_emit_succeeded；原七字段 receipt；`requires_actual_exit_0_or_3=true`；`receipt_write_state=pending_actual_exit_commit`。

该文件在写出时故意不声称自己的 writer/evidence 句柄已经关闭；强制以绑定 native actual exit 0/3 和 postpin 完成联合验收。文件可能已完整写出而后来的 writer/evidence close 失败，此时实际 exit 必须为 4、外部必须拒绝采用。正常 stdout 路径同样不能在 durable 失败时返回成功；现有 JS transport 会因实际 exit 4 拒绝原 stdout closed frame。

纯测试已运行：`node --test tools/dev_agent_bridge/windows_text_gate_task_executor.test.mjs`，**2/2 通过，self-test 95 项、managed harness 712 项**。其中 64 组 exit 真值组合、六项 closure facts 分别 false、stdout broken、durable write/flush/close/祖先 pin/ACL/postpin 失败、重复最终文件拒绝、超限证据、错误/缺少/对象化 binding、错误 trigger、no-child 失败均覆盖；所有异常只走合成委托。测试继续逐字比较冻结 WFP 块，未放宽规则实现。

测试用 x64 C# `/warnaserror+` 联合编译后，仅运行 plan / self-test / managed harness / 无效参数；随机临时目录自验证后删除。没有执行新的实际 native/app-server/helper/WFP 入口，也没有新 v7 实测报告。源码及依赖在测试前后做 SHA 核验。

编译仍为原五个依赖加当前 native source，显式 `/main:HereIAm.R7.TaskExecutorProgram`、`/platform:x64 /warnaserror+ /target:exe /reference:System.Web.Extensions.dll`；产物由主控用新 v7 路径生成，不能覆盖 v6。

| 编译依赖 | 固定 SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_isolation_helper.cs` | `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs` | `C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs` | `C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311` |
| `tmp/p6-r7-review/native-appid-matrix-contract-01.cs` | `F70FFB86CE5EFEA2572532E1986F77DDE9622893AD4B90A74F9EC40DA5BA6774` |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.cs` | `F2D3B35A1E6D1763930BA7F9A82AB8DBB595E02D5D720216A0161DBCE8A0D0AB` |

主控 witness 的强制采用条件：新候选实际 native PID/creation handle 被持有并 signaled；exit 为 0/3；exe/source/postpin 和本次 attempt/nonce/owner/child/auth 绑定精确；durable 文件 strict schema 与 SHA；六项全部 true、receipt.cleanup_pending=false；writer/evidence commit 由该新候选的实际 exit 契约确认。以默认三 pipe、无 stdout reader 副本实施 host crash，才对应本文原始 Gate；仅落盘文件出现或 PID 缺席都不能采用。
