# P6 R7 约一分钟执行失败的有限诊断

2026-09-13。承接[App退出修复与running-05/06复验](P6_R7_APP_RECHECK_20260913.md)，用户要求继续定位固定公开数字任务约一分钟后出现的 `provider_execution_failed`。running-08实际复现并取得 `exchange_failure_code=timeout`，失败后正常回收，当时尚未区分超时阶段；随后[running-09阶段诊断](P6_R7_TIMEOUT_PHASE_20260913.md)实测为收到body后未到EOF。旧失败、退出修复及其验收结果独立保留，下方为对应历史窗口记录。

## 候选范围与本地验证

新隔离工作树 `.worktrees/p6-r7-exchange-diag` / `codex/p6-r7-exchange-diag` 从当前 `v3-lab@b55386cfc896c98376a071009f349dcbc88dc84b` 创建。先按[基线记录](../../../.worktrees/p6-r7-exchange-diag/p6-r7-exchange-diag-baseline.json)逐字带入旧冻结host的18项闭包，以及必要测试输入；主目录及旧候选没有覆盖。

唯一生产逻辑差异在broker和App候选host：仅在已保留的实际 `exchange(...)` 调用抛出 `TextGateTransportError` 时记录 `exchange_failure_code`，允许值固定为 `timeout`、`aborted`、`http_status`、`unsupported_content_type`、`missing_body`、`request_rejected`、`response_rejected`、`transport_failed`，其它值均为null。host快照再次按同一闭集过滤。字段描述交换层分类；`aborted`不等于取消已确认，`request_rejected`不等于provider拒绝，均不能代替停止回执。

不保留message、cause、HTTP状态值、响应/请求/认证内容、gateCode、schemaLocation或诊断对象；exchange前后本地peer/输入/Buffer失败不得冒充该分类。transport、默认60000ms、重试、网络/原生隔离、整段响应校验和释放、停止/清理协议均未修改。

三个专项文件 **51/51、实际exit0**，覆盖8项分类、未知/伪装错误及敏感字段拒绝、HTTP恒定422、一次upstream与拒绝重试、成功路径配置保持、真实loopback卡流超时/响应校验失败、host二次过滤及快照不可变。[测试日志](../../../.worktrees/p6-r7-exchange-diag/p6-r7-exchange-diag-tests.log)对应当前候选。独立只读审阅无P1/P2，核对transport/native/runtime adapter与旧冻结输入一致。

## running-07 固定输入

使用[新宿主启动清单](../../../tmp/p6-r7-review/app-lifecycle-running-07/launcher-build.json)，SHA `4dfc779de1b1cdbe699c07e55288fbdba5b704d988bfeaa0d79ef8ca2f44d49a`，新18项closure SHA `789f0bef2e888b134bf8ccf1627176e1c82e2a23684c448f93b277657512baa4`。四启动/观察脚本语法检查通过；没有复制旧events、admission或测试DB。

App仍为旧冻结window-exit包：candidate清单 `60ef1a28…da5a2`，157源/152bundle全hash核对；exe `b2261b3a…63511`、kernel `6db65ffd…b4b10`及native `674f1591…fd02fc`保持。没有新Flutter构建，旧App93项/主目录91项不冒充本轮重跑；新host闭包与旧App候选分别绑定。

启动前实际只读检查成功，测试进程0，47831/PID32976与47841/PID25332的映像、创建时间保持，见[预检进程观察](../../../tmp/p6-r7-review/app-lifecycle-running-07/prestart-processes-verified.json)。本窗口只允许同一个已授权的固定数字任务；Windows安装/清理确认由用户手动处理。

## running-07：原生启动返回1223取消码，未派发模型

Node9608/创建13:24:31.7236144+08、launch `e06480e1-ed76-4383-9017-0592e73c844f`；零模型attempt `cc18c38c-6855-4b4b-9444-9c91c7127b16`，native24152/creation `134337506719122280`，broker45781。独立observer捕获真实native映像/创建时间/parent。05:24:32 UTC开始预检后，最终报告 `task_helper_shell_execute_win32_1223` 与 `native_startup_timeout`、native实际exit4；原生启动API返回取消码，用户随后反馈“还没看到弹窗”，不能确认实际显示过弹窗或推断是用户主动拒绝。

最终8帧events中startup/profile/turn/stop均null、arm/upstream/HTTP请求均0、broker drained=true、exchange_failure_code=null。App未启动，本轮未产生模型请求，**没有定位原一分钟执行失败的真实原因**。原native回执Rules/Helpers/Process/Stdio=false、Job/Handles=true、pending=true保持，不将不存在的模型回合记为验收失败或成功。

[只读原始目录摘要](../../../tmp/p6-r7-review/app-lifecycle-running-07/failed-preflight-files.json)确认顶层仅prepared/final-receipt/copied CLI/work/project0，phase=prepared、child=null、started=false；prepared SHA `3ef252420cc04193b32d46380b771377ee6ae458b4cf855b1290d51b990314c9`，final `851e31519d04c1d26ef16e83b0c01e3c315b68668ebf199cdc82ef37bc068a87`。这些证据与helper启动取消一致，但不代替WFP缺席实查。

05:31:18.864 UTC按PID/创建时间/映像/完整命令及无相关子进程核对后[精确结束失败host](../../../tmp/p6-r7-review/app-lifecycle-running-07/host-retired-unconfirmed.json)，外层实际exit1；这是精确退役，不是正常宿主关闭。observer实际exit0。events SHA `2d591e355c8327cf68c4401c865b2c3ded1167c1c5d9bbe3676221880bfc40b9`保持，pending未改写。[退役后进程检查](../../../tmp/p6-r7-review/app-lifecycle-running-07/post-retirement-processes.json)候选进程0、现役服务身份保持。独立只读审阅确认以上边界和四文件集成指纹，无阻塞P1/P2。

## cc18固定规则只读复查

沿用b966已验证的固定只读检查器，仅替换cc18实例、原source/exe路径及hash；[候选清单](../../../tmp/p6-r7-review/app-lifecycle-running-07/cc18-rule-inspect/candidate-build.json)绑定源码 `8ea8e235af8cf0164ef62a0ecac53709c0a7fd3f220a1eb8af9a125a39c5cb18` 与exe `b6169b42b633a897c809ff801e4d62762fe810378727555839f81f80fdc585c8`。两项本地测试通过（self2052/managed104），主控复核唯一常量差异并对最终exe再跑纯自测2052、exit0。该自测不查询WFP。捕获脚本SHA `3710e65f5808d175f72be197a4287ebbdf0457899fc802e801f5fad487919466`，校验原prepared/final双hash，输出create-new。

主控通过[固定外层入口](../../../tmp/p6-r7-review/run-cc18-readonly-inspection.ps1)在05:37:55.236 UTC请求只读检查；[实际外层记录](../../../tmp/p6-r7-review/app-lifecycle-running-07/cc18-rule-inspect/readonly-uac-actual-01.json)于05:39:57.555结束，collector_started=false、没有collector exit或实际inspector报告，外层工具exit1。该次启动未取得可用Win32错误码，不能补写1223或称检查器已执行。等待期间仅从进程元数据看到consent与Explorer处于同一Session1，未观测/操作安全界面，不足以断言用户看到了弹窗。

[最终只读检查](../../../tmp/p6-r7-review/app-lifecycle-running-07/inspection-launch-final-observation.json)核对固定候选映像及原确认进程的PID/创建时间均无残留、现役服务保持；首次只按PID检查曾命中已复用为其它pwsh的34624，未进行任何停止操作，后续以原创建时间区分。当前WFP状态仍未核实，原pending保留；不把未启动检查器当成四key缺席或清理通过。running-08仅为同hash新观察目录准备，尚未启动。下一步需用户能处理系统确认后，先完成cc18固定四key只读复查，再执行同一固定数字任务。

## 本地集成

诊断已[选择性集成四文件](../../../tmp/p6-r7-review/exchange-diag-local-integration.json)，主目录保留原短测试goal与原native pin，不带入隔离候选来源/任务变更；host测试同时携带已验证的临时目录canonical父目录/固定前缀检查。主目录对应三文件 **51/51、实际exit0**，见[主目录专项日志](../../../tmp/p6-r7-review/exchange-diag-main-tests.log)。当前HEAD仍b55386cf、索引不变；未提交推送或启用生产。

## 用户再次就绪后：cc18四key当前缺席，零删除

用户“现在可以”后，经[第二次固定入口](../../../tmp/p6-r7-review/run-cc18-readonly-inspection-02.ps1)重新请求人工系统确认。[第二次外层回执](../../../tmp/p6-r7-review/app-lifecycle-running-07/cc18-rule-inspect/readonly-uac-actual-02.json)记录06:31:29.936至06:31:34.265 UTC，collector19444实际启动并exit0；[capture](../../../tmp/p6-r7-review/app-lifecycle-running-07/cc18-rule-inspect/app-native-rules-actual-01-capture.json)记录inspector实际exit0、pins保持。

[实际只读报告](../../../tmp/p6-r7-review/app-lifecycle-running-07/cc18-rule-inspect/app-native-rules-actual-01.json) SHA `97b065cec0ccadeb69f0220991ac0137e31dc7cc21b0dc314eafc86876200ccc`：固定3个filter与1个sublayer全部缺席，文件/ACL、原双hash、owner/映像不活动、事务结束与资源关闭均验证；cleanup_performed=false、删除0、模型请求0。独立只读审阅无新增P1/P2。报告保留的cleanup_pending=true属于原失败状态；historical_stop_receipt_verified/stop_receipt_verified仍false，不能改写为历史停止成功，也不能推断规则消失机制或当前Job已实查。

## running-08：实际复现完整响应超时

[启动清单](../../../tmp/p6-r7-review/app-lifecycle-running-08/launcher-build.json) SHA `5c720d99f45d65a8137446258f45428d35e7595151295cbf8614eaa22c622352`，仍使用18项closure `789f0bef…baa4` 与原App清单 `60ef1a28…da5a2`。启动前重新核对157源/152bundle/18closure，cc18当前缺席、候选进程0、现役服务保持；[预检观察](../../../tmp/p6-r7-review/app-lifecycle-running-08/prestart-processes-verified.json)有实际回执。没有新构建、放宽60000ms、改任务、切模型或修改停止协议。

Node38500/创建14:34:20.9624630+08，launch `f105e500-41fa-490e-8bf3-804f4552036f`。零模型owner0 attempt `251db2f8-6dc4-4864-a617-1ed57a189523`，native26348；06:34:37.908 UTC ready前已native0、六项true/pendingfalse、upstream0。App18860/创建14:35:30.1666221+08，以全新隔离DB进入，固定公开1至2000任务只创建并开始一次。

真实owner1 attempt `fd717d64-bd4c-49de-9d02-d36b4c0f9471`，native38560；[独立身份观察](../../../tmp/p6-r7-review/app-lifecycle-running-08/native-identities.jsonl)绑定PID、创建时间、映像和host parent。task `e60eb55a-fcd8-4212-aa78-adf4c4b0fabe`，session `1bdf36f8-487f-450c-8580-b2f8cd0acf26`，epoch `887fd055-b8bf-4625-8c0e-85bf8cc055d4`，localturn `527835a5-1e99-46c4-9105-abf6b90e4504`，providerturn `01a0997f-1660-7c70-9fb7-0d87ff3fef8c` 在DB、turn与stop回执中吻合。

[events](../../../tmp/p6-r7-review/app-lifecycle-running-08/events.jsonl) frame13于06:40:38.290首次观察到upstream1，frame14于06:41:38.196首次记录 **exchange_failure_code=timeout**，观察差59.906秒（采样200ms，不能当作精确请求耗时）。总计arm1/upstream1/rejected1，response_released=false；没有自动重试。06:41:11的[运行态DB](../../../tmp/p6-r7-review/app-lifecycle-running-08/db-diagnostic-running-01.json)为running，最终[失败态DB](../../../tmp/p6-r7-review/app-lifecycle-running-08/db-diagnostic-terminal-01.json)为failed/provider_execution_failed、空结果，executionRequests仅start、retryCount0；UI实际显示失败。未点击取消或重试。

**诊断边界**：冻结broker向transport传入60000ms。transport从入口计时，覆盖请求验证、连接/等待响应头、整段body读取至EOF及最终gate校验。当前分类证明本地未在截止前得到完整可放行响应；不能区分等待响应头、首个body字节之前、读取中或最终校验，也不能证明远端模型在该时点尚未完成。旧running-04/06未含分类，不能追写其确诊结果。

## running-08退出与下一项

06:41:50.699 UTC frame16确认同绑定provider terminal `failed`、sequence12，interrupt_dispatched=false、cancellation_confirmed=false；native实际0、六项true/pendingfalse、broker drained。App随后正常关闭，06:42:17.617实际exit0；host经所属TTY正常shutdown，06:42:31.388记录[closed](../../../tmp/p6-r7-review/app-lifecycle-running-08/closed.json)，外层exit0；observer外层exit0、捕获两attempt。三项实际工具退出分别为c092a8/ee6260/424288，不用文件中的意图代替实际退出。

[退出后只读检查](../../../tmp/p6-r7-review/app-lifecycle-running-08/postclose-processes.json)成功：本轮App/native/两attempt目录映像/host及16821、16822、40504监听均无；47831/PID32976与47841/PID25332映像和原创建时间保持。比较过程中发现CIM亚微秒截断、JSON自动日期转换以及观察命令文本误匹配，均先纠正选择/时间比较再取成功结果；未对任何进程执行停止操作。[主控摘要](../../../tmp/p6-r7-review/app-lifecycle-running-08/actual-summary.json)再次核对157源/152bundle/18closure/7launcher及主目录4集成文件指纹，18帧证据与DB/退出断言通过。

独立只读复核无新增P1/P2：上述157/152/18/7项指纹、双attempt身份、18帧连续与最终快照、同任务失败/退出/DB绑定均吻合。events SHA `dcb561fd…1e9834`，closed SHA `7047d299…a95c64`；App在失败关闭回执后26.919秒退出，本轮不冒充运行中退出验收。

下一项可增加仅含固定枚举的本地超时阶段诊断（响应头前、首字节前、body读取、EOF后的最终校验），保留当前截止时间与完整响应门，再用同一任务取得新证据。此分段尚未实现或实测；本轮完成有限错误分类的真实验证，任务完成修复、其余App异常退出/显式恢复与完整真人Gate仍待，P6/Goal1未完成。无提交、推送、生产启用或真实队列操作。
