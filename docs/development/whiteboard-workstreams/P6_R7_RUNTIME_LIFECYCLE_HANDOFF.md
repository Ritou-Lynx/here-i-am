# P6 R7 HTTP 与宿主生命周期候选交接

更新：2026-09-12。当前工作从 `v3-lab@1b6a2961` 继续，保留共享目录既有改动，未提交、推送、构建或安装 App。

## 最新真实验收与 App 候选

2026-09-12 当前：6946c568 精确恢复 v2 已实际完成，原失败保留。修复 adapter 提前 revoke 的关闭顺序，并为 HTTP 候选显式使用已有代理；最终 completed05、interrupt05、turn-disconnect03 和 inflight host-fault actual03 四项真实验收通过，逐项26/26/26/31输入匹配，当前资源均已回收。主控45/45专项、独立关闭顺序审查及host-fault221项断言通过。仅关闭独立HTTP/native执行中阶段；App候选入口仍只有设计，生产available=false/fail_closed=true，真实App/生产/真人Gate及P6/Goal1未完成。详细见[执行中验收记录](P6_R7_INFLIGHT_ACCEPTANCE_20260912.md)。下文为此前阶段快照。

本轮新 HTTP/TaskSession 组合已独立实跑：v6 的创建/DELETE、创建途中断连、候选宿主正常关闭三项通过；各自 native 实际 exit0、六项回收 true、pending false，逐次 25 项输入前后相符。全部无模型请求。v7 新增受保护的最终文件凭据通道，已编译、独立审阅、本地 native/probe 12/12，并另行通过同一新 pin 的真实无模型 HTTP 创建/DELETE；详情与逐实例证据见 [HTTP/native 真实验收](P6_R7_HTTP_NATIVE_ACCEPTANCE_20260912.md)。这些结果不等于默认三 pipe 宿主强制终止验收。

App 已增加实际 controller registry、detached best-effort 入口、跨 claim/create 的退出栅栏、共享且固定参数的 close 与未知 binding 保留。独立审计发现的四项竞态均已修复；主控重新运行 **43/43** 本地 fake-runtime 测试，9 项输入前后相符。[验证清单](../../../tmp/p6-r7-review/app-lifecycle-local-20260912-01.json) SHA `DEC320C7A27B5103A983109E58AEF9290C55D31BA398706FA63B2CF05BE69B52`。页面/后台继续执行语义保持；未运行真实 App。Dart analyze 被现有 perf-witness 目录权限故障中断，没有静态分析通过结论。见 [App 生命周期候选](P6_R7_APP_LIFECYCLE_OWNER_DESIGN.md)。

默认三 pipe 的真实 host-fault 已完成：actual02 暴露 native owner 随 Node 被直接结束，未留下最终凭据；旧实例精确3+1规则已由固定恢复程序实查并清理，历史失败保留。最小修复 `detached:true` 和严格的退出后 held-handle 核验后，actual03 `4e8a1205` 实际 witness0/native3/Node77/child0、EOF、stdout最终发送失败、最终文件同绑定、六项回收true/pending false；30项输入相符，独立154项产物断言通过。最终同一组合正常HTTP关闭 `c9bd148a` 亦实测通过，25项输入相符。两者均为无模型turn；原先断连/正常宿主退出结果只属于原transport pin。

下一步补最终候选的执行中模型停止、HTTP断连及宿主意外退出证据，再进入真实 App 界面生命周期验收。生产接线与真人 Gate 仍未完成，生产 profile 继续拒绝。以下模拟验证、旧实例回查是上一轮记录，实际后续步骤以本节及真实验收页为准。

## 结果与证据级别

已实现专用 `WorkbenchTextTaskRuntimeAdapter`、按 session ID 固定 owner 的 HTTP 路由，以及先等待 runtime 回收再关闭 HTTP 的宿主正常退出路径。仅显式构造的候选宿主可注入 `textAdapterFactory`；现有生产 Bridge 未注入它，profile 继续 available=false/fail_closed=true。

此轮 runtime/HTTP/退出测试使用模拟 native、账户与 provider；串联测试使用真实本地 HTTP socket 和真实候选 adapter、TaskSession、停止回执 ledger。它验证字段和生命周期组合，不证明 Windows 强制隔离、真实 App 操作或宿主崩溃后的回收。

同一冻结 native v6 的真实固定文字/精确取消证据仍是 [actual09/10](P6_R7_NATIVE_TRANSPORT_HANDOFF.md)，没有由此继承到本轮新 HTTP 生命周期候选。

## 实现边界

- 创建开始前登记资源责任；broker、native transport、attached client 与 task 都归同一 owner。创建中断、晚到结果和失败均回收同一实例；未知结果保留重试责任。
- 新会话和新 turn 的响应只有到 `writableFinished` 才结束请求的取消责任。提前断开只清理本次已进入的尝试；正常响应完成、普通事件 GET 断开、尚未进入启动或明确被拒绝的请求不误关原 turn。
- turn 在进入执行前同步预约；重复或并发 POST 返回 409，不中断首次合法 turn。无法确认的启动、已发布故障触发同 owner 自动回收；回收尝试不等于成功停止回执。
- 创建/turn/事件/DELETE 保持 Dart v2 字段与精确 session/epoch/thread/turn 绑定。`turn_status.status` 位于事件顶层。DELETE 只输出真实 ledger 品牌产生的完整回执；关闭失败不包装成成功。
- HTTP 错误仅输出固定 code/message；只有本地已标记的 profile 拒绝对象可保留 availability 说明，不回传 native 路径、账户或原始错误。
- `stop()` 同步拒绝新启动，先发起所有 native closeAll 并立即观察拒绝，再等待 pending 请求。跨越 stop 的旧请求不能在后续恢复期重新启动。失败保留同 owner；普通成功 stop 后可按原行为新建；`permanent:true` 永久关闭启动入口。
- SIGINT/SIGTERM 通过可测试路径等待 experimental runtime 回收，再关闭 HTTP。Windows 强制终止/崩溃/断电不能保证执行此异步路径；这里不宣称整个宿主或其他 legacy run 已取得原生关闭证明。

## 旧 v4 独立回查

对旧 `9ad201c0` 实例执行固定只读检查，actual exit0：精确三条 filter 与一个 sublayer 全部缺席，检查前后绑定 owner/映像无活进程，检查器资源已关闭。没有删除规则，没有账户或模型请求。原失败报告的 `cleanup_pending=true` 和缺失停止证明保留；原 Windows session 不在证据中，当前 Job 未查询。

冻结 inspector source `500257BE…D05E6` / exe `2DB3AED9…805AC`；原始 report SHA `2D061EF1…92BCA`。独立复核 63/63 产物断言、8 项指纹相符，详见 [只读回查交接](P6_R7_TASK_RETIRED_INSPECT_HANDOFF.md)。当前规则遗留疑问已收口，历史失败没有被改成成功。

## 本地主控验证

最终组合 **156/156 通过**，包括普通 client/adapter 相邻回归、native transport/probe 的模拟测试、专用 adapter/session/ledger、HTTP/profile、正常退出、串联 HTTP 契约以及只读检查器编译测试。25 个源码/测试输入在运行前后指纹一致。

原始 [TAP 输出](../../../tmp/p6-r7-review/runtime-lifecycle-local-tests-20260912-01.tap) 与 [验证清单](../../../tmp/p6-r7-review/runtime-lifecycle-local-verification-20260912-01.json) 已保存；清单 SHA `1301942217C898A43C4059F5F8F5614423539BE408391E0F24D1E4AF360E95F8`。API/正常退出的独立审阅另跑 25/25，无 P1/P2；主控随后复核内部 notification fault 增量并纳入上述最终组合。

本轮 TaskSession 增加了默认关闭的内部故障通知接口；当前 JS 输入已不同于 actual09/10 当时的 14 项清单。先前真实报告保留为原冻结组合的证据，不能据此称当前 HTTP/JS 组合已实跑。

## 上一轮列出的后续实际验收（进度以顶部为准）

1. 冻结当前 JS/原生候选输入，在独立候选 HTTP 宿主完成真实创建、响应未完成时断开、正常 DELETE 与宿主正常退出；逐个实例保留实际 native 回收和精确停止证据。
2. 独立注入宿主意外退出，验证原生 stdin EOF/lease/Job 收敛；不能把 SIGINT 单元测试当成这项证明。
3. 给 App 的任务执行层补应用/运行宿主级生命周期 owner。当前 execution controller、runtime client 没有 dispose/closeAll；页面退出不是长任务取消。现有显式暂停/取消保留精确 receipt 核验；无法确认则 blocked/runtime_stop_unconfirmed。
4. 重启按已授权语义标记 interrupted/recoverable，不自动重新执行旧任务；恢复由明确操作开始新 run。原 `P6 队列验收` 任务本轮没有查询或改变，旧 pending 快照不是实时状态。

在这些实际入口与真人 Gate 完成前，P6/Goal1 仍未完成。专用登录、既有账户与受限执行口径已经授权，无须重复登录或改换费用来源。

## 产物入口

- [候选 runtime adapter](../../../tools/dev_agent_bridge/workbench_text_task_runtime_adapter.mjs) / [其专项交接](P6_R7_NATIVE_RUNTIME_ADAPTER_HANDOFF.md)
- [HTTP 路由](../../../tools/dev_agent_bridge/experimental_runtime_api.mjs) / [HTTP 生命周期测试](../../../tools/dev_agent_bridge/experimental_runtime_api_text_lifecycle.test.mjs)
- [正常退出模块](../../../tools/dev_agent_bridge/bridge_runtime_shutdown.mjs) / [串联契约测试](../../../tools/dev_agent_bridge/workbench_text_task_http_contract.test.mjs)
- [设计与字段契约](P6_R7_NATIVE_ADAPTER_INTEGRATION_AUDIT.md)
