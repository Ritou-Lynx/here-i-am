# P6 R7 180秒隔离比较

2026-09-13。用户继续已授权的同一固定公开数字任务，承接[running-09的60秒超时](P6_R7_TIMEOUT_PHASE_20260913.md)。本轮比较已完成，数字任务仍失败；180秒设置仅在隔离候选，未集成到主目录。

## 候选与验证

`.worktrees/p6-r7-deadline-180` / `codex/p6-r7-deadline-180` 从本地 `v3-lab@c5d7cbfe559eb517b3b1110f27e07dc8308d6442` 创建。[基线](../../../.worktrees/p6-r7-deadline-180/p6-r7-deadline-180-baseline.json)固定来自timeout-phase的22项输入；只改变host及其测试：非preflight创建broker时明确注入180000ms，零模型预检保留原args。其余20项输入保持字节哈希，broker默认60000ms、transport默认10000ms、完整响应门、无重试、停止与清理逻辑保持。

主控三文件组合[75/75、actual exit0](../../../.worktrees/p6-r7-deadline-180/p6-r7-deadline-180-tests.log)，测试包含真实loopback首次及DELETE后owner的180000ms与预检未覆盖默认。独立源码审计无P1/P2。host之外的本地链路审计未发现更短的整回合定时器；CLI内部及远端策略未穷尽验证，不将此当作180秒内必能完成的保证。

[running-10启动清单](../../../tmp/p6-r7-review/app-lifecycle-running-10/launcher-build.json) SHA `b432230b3ddcb5bf38c1df592349b9aed05d774c87eff6a1b0e1e0747a1b0136`；18项closure `2ceaa3d3a7437cf33ce08e27deb95610061c0c6e5ed85f6f8681996db600c509`；host `109eb3e43a31643f66837c8d6471a56a61bc4545de1abd9f8f112b356598799d`。四启动/观察脚本仅替换host工作树及观察目录，语法通过。原App仍用window-exit清单 `60ef1a28…da5a2`、157源/152bundle，native仍 `674f1591…fd02fc`；未重新构建App。

冻结前检查脚本先因日志实际采用spec而非TAP格式拒绝，继而在沙箱读取受保护CLI时被拒绝；两次均在生成冻结产物前停止。修正日志格式检查并使用获准的哈希读取后完成冻结，未改变测试记录或被测代码。

## 实际比较

[启动前检查](../../../tmp/p6-r7-review/app-lifecycle-running-10/prestart-processes-verified.json)确认无本轮候选进程、原服务身份保持。零模型预检attempt `ea3f1587-9b12-44b1-9d4e-0786960487e0`、native15108在08:18:05.877 UTC取得ready及native0/六项true/pendingfalse，upstream0。host41876/创建16:17:24.1215644+08，launch `3f99693e-4d08-45b6-b9b6-d05009490d3e`，port59215。

App29560/创建16:18:43.3799556+08以全新隔离DB启动，通过实际UI仅创建并开始一次：`只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。`。真实owner attempt `e54159d7-2f03-40d5-ab0b-5e657c689cbe`、native34892、broker13261；独立观察绑定创建时间、映像与host parent。没有点击暂停、取消、继续或重试。

| 本轮观察 | UTC / 结果 |
|---|---|
| frame11首次upstream | 08:20:03.945；arm1/upstream1 |
| frame12拒绝 | 08:21:37.411；`response_rejected`，timeout phase=null |
| 观察时间差 | 93.466秒；200ms采样，不作为精确请求耗时 |
| frame14关闭证明 | 08:21:42.090；两个owner native0、六项true、pendingfalse |
| App正常退出 | 08:22:31.9571725；actual exit0 |
| host正常关闭 | 08:22:38.728；所属TTY shutdown，actual exit0 |

[运行DB](../../../tmp/p6-r7-review/app-lifecycle-running-10/db-deadline180-running-01.json)及[最终DB](../../../tmp/p6-r7-review/app-lifecycle-running-10/db-deadline180-terminal-01.json)为同一task `fb16e44c-0863-46bd-b421-26c9302137e7`，running转failed/provider_execution_failed、空resultText、retryCount0、executionRequests只有start。session `e6ad84ec-c014-4366-98c1-1042bb7e4b35`、epoch `da819e72-46be-4b2f-8ad4-e81df6998c04`、localturn `5d10f424-a293-4d24-9d8f-97330d2554cb`、providerturn `01a099da-1e8e-74c0-9f1c-af0cb7d35f1f`在DB/turn/停止证据吻合。provider terminal failed/sequence12、interrupt_dispatched=false、cancellation_confirmed=false；broker rejected1、未释放响应且drained。UI实际显示失败。

App、host和observer外层实际exit0工具记录分别为1ba8bd、8d3e57、3fa9ee。[退出后检查](../../../tmp/p6-r7-review/app-lifecycle-running-10/postclose-processes.json)成功，本轮App/native/host/两attempt目录映像无活动进程，59215/59216/13261无监听；现役47831/PID32976及47841/PID25332映像和原创建时间保持。

## 解释与剩余事项

`response_rejected`由transport捕获`ResponseTextGateError`映射：既可能在读取中的`gate.push`抛出，也可能在reader EOF之后的`gate.finish`抛出。因此只能确认严格文本响应校验拒绝；不能证明EOF、具体拒绝规则、上游完成或工具执行。broker仍关闭额外响应/协议诊断，未保存正文、header、认证、未知字段、原始错误或细分gateCode。本轮不能补写未采集的拒绝细节，也不能反推running-09的超时在更长时间下必然产生同一种拒绝。

[主控摘要](../../../tmp/p6-r7-review/app-lifecycle-running-10/actual-summary.json)复核157源/152bundle/18closure/7launcher及主目录原6项集成指纹、16帧连续事件、closed最终快照与退出顺序；独立只读终审无新增P1/P2。events SHA `34403ce90e382768329b114d3f812b2aefa97f4058ce8d1b6671495b3d4b2d0e`，closed SHA `df1bd7892d3140e4f3f15e036aced0bb1da475ae0e512782a0d82d001601cf23`；旧running-09事件及关闭指纹保持，running-07失败/pending历史保留。

结论：本次180秒候选越过旧60秒截止后仍失败，延长时限没有使数字任务完成。下一项最小诊断可只区分响应校验拒绝发生于EOF前或后，以闭集字段经broker/host二次过滤，不放宽文本门。该诊断尚未实施；180秒不进入主目录，P6/Goal1、App异常退出/显式恢复和完整真人Gate仍待。无提交推送、生产启用或真实队列操作。
