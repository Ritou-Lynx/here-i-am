# P6 R7 超时阶段诊断

2026-09-13。承接[running-08完整响应超时](P6_R7_EXCHANGE_DIAGNOSTICS_20260913.md)，用户要求继续定位等待响应、接收内容或EOF后处理阶段。

## 实现与验证

新隔离工作树 `.worktrees/p6-r7-timeout-phase` / `codex/p6-r7-timeout-phase` 从本地 `v3-lab@c5d7cbfe559eb517b3b1110f27e07dc8308d6442` 创建。按[基线](../../../.worktrees/p6-r7-timeout-phase/p6-r7-timeout-phase-baseline.json)复制原冻结18项host闭包及4项测试输入；旧候选、App及native保持。

transport只新增本地观察里程碑，实际超时路径将其作为 `TextGateTransportError.timeoutPhase`；broker在原实际exchange窄catch输出 `exchange_timeout_phase`，host再次要求错误类别为timeout且阶段为原始string闭集成员，否则null。固定词汇如下：

| 阶段 | 只能证明的本地观察 |
|---|---|
| request_preparation | 尚在请求准备 |
| before_response_headers | 已进入fetch，尚未取得响应对象 |
| response_headers_before_body_byte | 已取得响应对象，未观察到非空body chunk |
| response_body_before_eof | 已收到非空body chunk，尚未观察到reader EOF |
| after_response_eof | 已观察到reader EOF，可能在校验或最终清理；不代表校验成功或provider完成 |

阶段赋值位于相应既有deadline检查之前，空chunk不冒充收到首字节；标准响应和可选拒绝格式诊断的读取路径一致。原EOF权威、外部abort优先级、broker60000ms与transport10000ms默认、原网络/执行边界、完整响应门、输出释放、重试和停止协议不变。不新增响应正文、header、认证、原始错误、provider状态或细节采集。

transport专项44/44；主控三文件组合 **75/75、实际exit0**，见[隔离日志](../../../.worktrees/p6-r7-timeout-phase/p6-r7-timeout-phase-tests.log)。覆盖真实loopback响应头前/首字节前/EOF前超时、准备与EOF后校验/清理、外部abort优先、未知/伪装/非timeout字段、无私密内容、无重试/放行和快照不变。独立只读复核最终6项无P1/P2。

[六文件本地集成](../../../tmp/p6-r7-review/timeout-phase-local-integration.json)保留主目录原native pin及短测试goal，host仅按精确两处文本修改。准备比较先因主目录末尾混合换行差异拒绝且没有写入，核对实际diff后按原字节保留其余正文。集成后三文件组合 **75/75、实际exit0**，见[主目录日志](../../../tmp/p6-r7-review/timeout-phase-main-tests.log)。未提交推送或启用生产。

## running-09 固定候选

[新启动清单](../../../tmp/p6-r7-review/app-lifecycle-running-09/launcher-build.json) SHA `1178bd455299fe58aa51f62bb67cd796671d98f6690bdf5d06720a759c083c35`，18项closure `1dc8d1256afe6b09f4d969f3ab928a09de128dcb601bd43583b4dbf4cd22f6bc`。准备仅改变host import至新工作树和新观察目录，四脚本语法通过，未复制旧events/admission/DB。App仍为window-exit清单 `60ef1a28…da5a2`、157源/152bundle；native仍 `674f1591…fd02fc`，没有新Flutter构建。

[启动前实际观察](../../../tmp/p6-r7-review/app-lifecycle-running-09/prestart-processes-verified.json)重新核对157/152/18项指纹、旧测试进程0与现役服务原身份。零模型预检owner `272f254f-9845-4936-bbae-31774b234d09`、native30860；07:26:27.415 UTC取得ready、native0/六项true/pendingfalse、upstream0。Node11388/创建15:26:12.6839853+08，launch `a01571eb-8118-45aa-9f15-f011d4a147f8`，port13804。

App40024/创建15:27:26.8400974+08，以新隔离DB启动；固定公开1至2000任务仅创建并开始一次。

## 实际结果：已收到body，截止时未观察到EOF

真实owner attempt `e1cc146f-ca0d-4827-b0d7-d55d6835d0e9`，native7456；[独立身份观察](../../../tmp/p6-r7-review/app-lifecycle-running-09/native-identities.jsonl)记录其创建时间、映像、host parent及broker40889。task `f358d0fd-2f19-4cac-8d3b-41af1b47f0e2`，session `0c95da8a-62a6-4a21-a3a0-b02572e1693d`，epoch `b329eba0-32ab-4905-921e-25e186bd2401`，localturn `d207139f-7299-4ae9-bc9c-853ec759eeb5`，providerturn `01a099ab-6c62-7a30-b206-b95726328951` 在task/turn/停止证据中吻合。

[events](../../../tmp/p6-r7-review/app-lifecycle-running-09/events.jsonl) frame12于07:29:03.815首次观察到唯一upstream；frame13于07:30:03.869首次记录 **timeout / response_body_before_eof**。观察差60.054秒，采样周期200ms，不当作精确请求耗时。总计arm1/upstream1/rejected1、response_released=false；无重试。该阶段说明本地已收到非空body chunk、尚未观察到reader EOF，能排除“从未取得响应对象/从未收到任何body字节”这两类本地状态；不能将任意body chunk当成模型文字、持续生成、完成事件或远端完成证明，也不能据此认定整个流一直停滞。

[运行态DB](../../../tmp/p6-r7-review/app-lifecycle-running-09/db-timeout-phase-running-01.json)与[最终DB](../../../tmp/p6-r7-review/app-lifecycle-running-09/db-timeout-phase-terminal-01.json)为同一任务，running转failed/provider_execution_failed、空结果、executionRequests只有start、retryCount0；UI实际显示失败。没有点击取消或重试。

07:30:08.956 frame15记录同绑定provider terminal failed/sequence12，interrupt_dispatched=false、cancellation_confirmed=false；native实际0、六项true/pendingfalse、broker drained。两个owner均正常回收。App随后在07:31:11.839正常exit0，host在07:31:18.156经所属TTY正常关闭并写入[closed](../../../tmp/p6-r7-review/app-lifecycle-running-09/closed.json)，host及observer外层均exit0。对应实际工具退出为76e020、4eb1b0、e8568b；本轮App在失败后关闭，不冒充运行中退出试验。

[退出后实查](../../../tmp/p6-r7-review/app-lifecycle-running-09/postclose-processes.json)查询成功，本轮App/native/host/两attempt目录映像均无活动进程，13804/13805/40889无监听；现役47831/PID32976和47841/PID25332的映像与原创建时间保持。[主控摘要](../../../tmp/p6-r7-review/app-lifecycle-running-09/actual-summary.json)再次核对157源/152bundle/18closure/7launcher和主目录6集成指纹，17帧连续证据与DB、停止绑定及退出顺序通过。旧running-07 native4/pending与08未记录阶段的历史不改写。

独立只读终审实际记录与主目录六文件无新增P1/P2：17帧连续、closed等于最终快照，157/152/18/7及集成6项指纹吻合，两份组合日志75/75；旧running-08 events/closed指纹不变。本轮events SHA `a8030de3…d9e1f7`，closed SHA `c7b3627a…820ce3`。

本轮已完成五阶段诊断的实现、本地集成和同任务实际验证；长任务未完成。下一项可在独立候选中对比更长的有限总时限，并继续保留完整响应门、取消和清理回执，判断固定任务能否自然完成；若仍无EOF，再按无内容的进度事实收窄停滞位置。该期限调整尚未实施，本轮60000ms保持。P6/Goal1、其余App异常退出/显式恢复及完整真人Gate仍未完成；无提交推送、生产启用或真实队列操作。
