# P6 R7 修复候选预检与清理诊断

**最新结论（2026-09-13 10:52，UTC+8）**：用户明确授权后的实际复查确认四项固定规则已全无，本次零删除，当前recovery_pending=false。未推断此前消失原因，原失败及App待验状态保留。详见[授权后实际结果](#授权后实际复查四项已缺席本次零删除)；下方较早的“仍存在/等待授权”仅描述当时状态。

2026-09-13，承接用户“可以”：已授权接收Windows人工确认，继续[运行中取消修复后的验收](P6_R7_APP_RUNNING_ACCEPTANCE_20260913.md)。主目录仍为 `v3-lab@68307c9ea837f11dc82e148e8f51feff89b50fb6`，空索引，保留并行修改；无提交、推送或生产启用。

## b966只读回查已实际通过

用户手动处理系统确认后，[实际只读报告](../../../tmp/p6-r7-review/app-lifecycle-running-01/b966-rule-inspect/app-native-rules-actual-01.json)在02:52:03–02:52:06（UTC+8）查询窗口内确认原实例的三个固定filter及一个sublayer均缺席。检查器和收集器均实际exit0，固定文件/ACL/进程不活跃、事务结束及资源关闭通过，零删除、零模型请求。

报告SHA `9c094a6a0aad633ccfcc2b45604945215b1d9e7f98b78814e139d4f3a43652be`，capture SHA `44b0becdf39a0ce644f4cfd403765c466bda6ae22be6d9930fc19211f30ca8d5`，收集器记录SHA `e26c4588742ca6287b6181a3cbd4e46ce900bcca56430d70a308dfd310041b9d`；原exe `cfaf2997…45c2c`和七项构建输入保持。独立审计17项通过。原native4及pending=true仍保留，当前规则缺席不补写历史完整关闭或App后台验收。

## 修复候选首个零模型预检未通过

使用已冻结 `.worktrees/p6-r7-close-receipt` 的[候选清单](../../../tmp/p6-r7-review/app-lifecycle-running-02/candidate-build.json) `d46eba2d…9c0f4`及18项Node闭包 `e56ea781…5fe04`。仅启动独立host与只读身份观察器，**没有启动App或派发模型任务**。

host launch `8f3dd712-050c-4779-8764-c44e465bab77`，Node43640 / `2026-09-13T02:53:08.4796419+08:00`，没有发布HTTP入口。预检attempt `52572f7d-e2d1-4177-888b-cc8e66cfc553`，native56172 / creation `134337127886622621`，broker15402；[独立身份观察](../../../tmp/p6-r7-review/app-lifecycle-running-02/native-identities.jsonl)在ready前确认PID/创建时间/映像/parent。

安装助手57348 / creation `134337127959210997` 的ready/ack/receipt齐全且已接受。CLI39700 / creation `134337127983684016`正常启动，profile绑定 local session `8f1c085b-30e9-4716-b9de-b5a81ec0b99a`、epoch `f76be095-41cb-4d0d-89fa-b105d62bf908`、provider thread `01a096f7-844d-7a72-b9af-affce9b4b835`，无turn。

02:53:18.950写入closed journal；02:55:21.754生成失败final。原生报告Process/Job/Stdio/Handles=true，Rules/Helpers=false、pending=true，实际exit4；host verified六事实均保留null、stop_receipt=null，arm/upstream0、broker最终drained。[安全事件](../../../tmp/p6-r7-review/app-lifecycle-running-02/events.jsonl)最终sequence11为shutdown_unconfirmed。

cleanup-ready/ack/receipt全无。v7只在主执行异常时发error帧，finally中的cleanup失败被吞掉；所以native_failure_code=null不能解释为没有helper失败，也不足以认定用户取消、未看见UAC或helper从未运行。启动成功和严格回收未确认必须分开记录。

原始固定输入：

| 文件 | SHA-256 |
|---|---|
| prepared | `c88585552f170a8b82ae0195ddb613a72346b9df08367d5c2bbaa2cf56f99dbe` |
| bound | `98819c684e41851897ce278431c1e03d26bb8fc34671f664691c01c2e7a127fa` |
| closed | `e049ad9ee68e60b6bba2f2358de63659ee9fe5abbb07e829507c131124c816a0` |
| final | `b1d15bdb2ff773c952c58321b7716bde2c2e1c16117659e93c3ffe8ba3fa2ffe` |
| install receipt | `cf9d193567743c83a0286fb765b6ef7bb4b1562c3480a169d2b70097045823ab` |
| install ready/ack | `bcea02945d150c865061a417d8928f903be6812d4196313c11a1d70e9a0b4e3a` |

scope `cc11bb68-4661-8446-6eb0-fd36f74fe17e`，assigned weight32766，AppId digest `1a9cc1408dee488a4d8d0ac7f27213f9cd71dbddc524288f49d9f1ed0e5c6649`。此阶段尚未检查实际规则，不复用b966的无child检查器；随后本次固定范围的实际检查结果见下文。

## 进程退役与后续

确认同v7映像/已知owner、CLI、install helper均不活跃、broker排空后，[精确退役本次Node](../../../tmp/p6-r7-review/app-lifecycle-running-02/host-retired-unconfirmed.json)。02:58:54+08记录其退出，原事件SHA `0d340d8e875588e5d78903f2e49a2693a488f38c0aad34a7d0f861bd72c52119`不变，现役47831/47841原PID/创建时间及监听保持。未将定向停用称为正常host shutdown，不改变原native4/pending。

随后准备本次八份原始记录及完整规则内容绑定的独立只读检查/精确回收候选，并补finally关闭失败的有限诊断，结果如下。任何实际回收只允许核验本次完整3+1规则后进行；部分存在、内容不符或未知状态拒绝。新诊断不放宽权限、超时或完整停止判定，也不替换原冻结证据。修复后的App取消UI、页面/后台、退出与未完成任务重启仍待实际验证；生产保持available=false/fail_closed=true，P6/Goal1/真人Gate未完成。

## 5257只读检查已完成，删除需要明确授权

用户随后确认“看到了，但未点‘是’”，作为本次后续系统弹窗的人工作业记录。它与清理回执缺失一致，但不补造原程序未记录的Win32错误码。

本次[精确候选](../../../tmp/p6-r7-review/app-lifecycle-running-02/5257-recovery/candidate-build.json)已编译并冻结：源码 `bcabf27a…ed1da4`、exe `d43b7e14…24519`，7项编译输入与12项原始/运行证据前后相符。主控纯测试3/3（self260、managed60）通过，规则完整性/事务算法与旧审阅模板相同；本次历史改为固定零模型预检events和独立observer。独立审查发现并修复捕获器的类型转换与重复键问题，真实报告验证函数55项纯检查通过；收集器明确保存stdout文本而非字节级原始流。

最初尝试组合“先inspect、再按完整匹配条件回收”被自动审批审查拒绝，原因是当前用户授权尚未明确包括删除三filter与一sublayer。该命令未创建进程、未执行删除。随后采用不包含apply调用的独立只读捕获器，03:15:29–03:15:34（UTC+8）[实际检查](../../../tmp/p6-r7-review/app-lifecycle-running-02/5257-recovery/inspect-actual-01.json)确认本次**完整精确3+1仍存在**；inspector与collector均exit0，身份/ACL/原始证据/完整规则内容/事务及资源关闭通过，零删除、零模型请求。报告SHA `ea4981ec2ac212ed3fe7f970cdb5ab0b6b5df2fb70b790c661f035c6bc766672`，capture SHA `3ee04f3b9c0039f77376f2d97094aedbe33137a879b7ef4fc3660ad9483041b8`。

待用户明确允许的删除范围已具体化为[本次四项临时规则回收说明](../../../tmp/p6-r7-review/app-lifecycle-running-02/5257-recovery/APPROVAL.md)。单独cleanup捕获器已准备并绑定上述只读结果；尚未执行apply，当前recovery_pending=true，原历史native4/pending继续保留。未获明确删除授权前，不得改用其他入口间接执行。

## 清理失败诊断候选已完成本地验证

[隔离候选清单](../../../tmp/p6-r7-review/native-cleanup-diagnostics-01/candidate-build.json)冻结源码SHA `3803d0b2e8af435d77858a88ddf53af91c5c338fdfa60542004b61bca9869b80`、exe SHA `f95ed6a039b5423af9955a1a41bf173ac85a892e90989a817c758dbaccd11397`，八项输入前后相符。候选将首个错误捕获与单次有限错误帧发送提取为实际Run使用的C#辅助路径；优先保留主执行错误，清理中出现首错时保留其错误码，发送失败也不会阻止后续关闭回执路径。六项关闭事实、最终记录、退出码策略及规则操作保持。

主控复跑C#辅助路径与Node传输组合测试2/2，通过实际C# helper及TaskEmitter检查首错保留和有限帧，不再以JS模拟帧替代被测实现；候选编译exit0、纯自测95项通过，独立审查未发现P1/P2。该证据不是完整原始线序回放，也未执行真实Run、UAC助手或WFP清理，不能据此追认5257的具体系统错误。候选仅保存在隔离审阅目录，未接入主线、未更换host固定v7映像、未重新启动App。

下一步仍是取得本次四项规则的明确删除授权，再由用户手动处理Windows确认并实际回收、复查。完成后才能用新的独立证据窗口继续App验收；不得复用已失败的running-02窗口。

## 授权后实际复查：四项已缺席，本次零删除

用户随后明确回复“是的，授权”，仅补足上文四项固定临时规则删除及复查范围。主控再次核对分支/HEAD/空索引、7项构建输入和5项候选/既有证据指纹，独立审阅确认捕获器 `8dfcfc99…11872df` 与exe `d43b7e14…ed24519` 未变；随后调用独立cleanup入口，由用户手动处理Windows确认，未自动操作安全弹窗。

实际原生检查窗口为10:52:38.3369917–10:52:54.0622177（UTC+8）。[原生报告](../../../tmp/p6-r7-review/app-lifecycle-running-02/5257-recovery/cleanup-actual-01.json)返回 `rules_before_count=0`、`current_rules_absent_verified=true`、`filters_deleted_count=0`、`sublayers_deleted_count=0`、`cleanup_performed=false`、`transaction_committed=false`；[收集结果](../../../tmp/p6-r7-review/app-lifecycle-running-02/5257-recovery/collection-actual-01.json)为 `absent_on_independent_apply_recheck_no_write`。因此可以确认当前四个固定key均缺席，但**本次没有删除任何规则**；03:15至10:52之间如何消失，没有证据支持归因。

检查器实际exit0；[stdout捕获](../../../tmp/p6-r7-review/app-lifecycle-running-02/5257-recovery/cleanup-capture-01.json)解析和执行前后固定映像核对通过。[外层实际记录](../../../tmp/p6-r7-review/app-lifecycle-running-02/5257-recovery/uac-cleanup-actual-01.json)确认collector35156 / `2026-09-13T10:52:37.3135392+08:00`、实际exit0。当前身份/原始历史/文件ACL、检查事务结束及资源关闭均通过，`recovery_pending=false`。原 `native4`、`historical_cleanup_pending=true`、`cleanup_pending=true` 及未通过的历史停止验收继续保留；当前缺席不追认历史回收成功。

| 新证据 | SHA-256 |
|---|---|
| cleanup actual | `bbfd76d4add5d95c591f8289220d6269caea419cd00b429546da4903e2e9b8df` |
| cleanup capture | `f300bf1cf106b1356f8772e8ef7113366a8b5040fac865a096b31659e54aec37` |
| collection | `f8c81b847027107dc7e5008b733f59bdf78e4473faf7a40b1cc7c5438e9c52bf` |
| UAC outer capture | `d260b0fac09ea9101a75e2b0a2f8b9ba7ec2c51a30b71a90e5f33cb5c00e9757` |

独立复核未发现新增P1/P2；实际报告与stdout哈希匹配，旧inspect/capture/events/observer、恢复exe/collector/v7指纹保持。独立审阅账户无法直接重算受保护原始目录文件哈希；该层依据固定原生检查器实际返回的历史完整性及文件ACL成功事实，不冒充审阅者直接读原文件成功。

本次四项规则残留回查已完成，无需再次删除。未启动App、模型回合或诊断候选，没有提交、推送或现役服务操作。P6/Goal1/真人Gate仍未完成；后续App取消UI、页面/后台、退出及未完成重启继续使用新的独立证据窗口，不能沿用失败的running-02作为新验收。
