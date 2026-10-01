# P6 R7 产品 host 组合独立复核

日期：2026-09-14。本包只修改 `tools/dev_agent_bridge/workbench_text_task_app_candidate_host.test.mjs` 并新增本文，不改两代host、guardian、binding或其他实现文件。对象是主控新增的第三参数 `productBinding`、真实HTTP产品路由、受绑定任务的text输入以及组合关闭hook；不是对guardian自身重复验收。

最终状态：主控修复两条同根因的零资源拒绝路径后，42/42本机合成组合测试自然退出通过（chunk `335c80`）。下文保留最初失败及修复过程，末节固定最终源码哈希；不代表真实App/native或provider验收。

## 初次结果：发现一项P2，具有两个可重现后果

**[P2] 产品manifest在分配host record/count之后被拒绝，污染没有native请求的记录与后续owner索引。**

首代 `workbench_text_task_app_candidate_host.mjs` 的 `newAdapter` 先执行 `occupied=r; records.add(r); count++`（本轮读取时225-228行），然后其facade.startSession在320行才检查 `productBinding.permitsTextSession(manifest)`。错误task_id或execution_mode在此被拒绝，尚未创建broker/native，也没有发送witness owner_requested。

两项新增回归的实际后果：

1. 固定任务已绑定 → 提交wrong task manifest → HTTP拒绝；fixture仍仅preflight一个资源，witness ownerCount=1，但host保留第二个空record。正常shutdown随后在 `witnessOwnerClosed` 的 `witnessBound/nativeEvidence/resourceProof` 要求处失败，最后返回 `runtime_stop_unconfirmed`，HTTP listener没有按正常链关闭。
2. 拒绝wrong execution_mode → 再提交同绑定合法manifest；host count已消耗一次，新的record.index=2，但witness下一项index=1，owner绑定失败。实际合法session创建得到503，而预期200。

这是拒绝路径产生的可用性/生命周期缺陷，不是已知非法任务绕过native权限。两代host都先分配record再检查product manifest；首代audited链产生上述两个确定后果。successor没有同一独立witness索引路径，仍应避免无资源拒绝占用有限记录额度。

最小修复方向：在分配record/count/occupied前验证product manifest，或只在证明未创建broker、owner、requestedAttempt、未向witness提交intent时回滚该allocation并保持后续index连续。不要为修复空记录而跳过任何真实owner的原held identity、actual exit、六项资源证明或witness回执。`ExperimentalRuntimeApi`会先取得adapter再调用startSession，需照顾这条调用顺序及其保留的adapter集合，不能只从host Set删除却留facade.closeAll继续要求不存在的资源。

## 新增组合覆盖

测试沿用原 `files` / `fixture` / `client` / `auditedFixture`；fixture只增加可选expectedInput与armInput记录，默认固定公开数字input不变。新普通transport全是内存fake，不接现役Gateway。HTTP使用真实 `IncomingMessage`、新申请的127.0.0.1临时listener和现有认证headers，通过新 `readWorkbenchProductRequest` 而非直接调用binding.handle。

首轮新增13项顶层case，后补1项同根因的配置拒绝回归，共14项：

- 两代各验证正确capability后才有ordinary会话创建、turn、动态queue事件/真实工具回传、旧call拒绝及close路由；错token、launch、Origin、Content-Type、非唯一queue定义不进入ordinary transport。
- 两代各验证wrong task scope不产生native、已绑定动态goal经原text runtime真实调用fake broker.arm；固定数字旧goal、裸goal、篡改input被拒绝且不增加owner或arm。
- 两代各验证ordinary返回不完整/offline终态时整体shutdown拒绝，同时已有text owner仍实际走fake cleanup；首代owner_closed都收到但不发witness.host_closed。
- 两代各验证通过HTTP进入的ordinary start还在pending时shutdown，late session ID由guardian登记后exact DELETE，HTTP不再把成功session交给App；不会停止共享Gateway。
- 两代各验证只有真实WeakSet品牌binding可注入，结构相似的伪binding在资源分配前拒绝。
- 首代原App EOF验证：先记录真正该入口触发的app_stdin_eof；ordinary DELETE故意等待时text owner可完成关闭，但witness.host_closed尚无；释放ordinary合法关闭后才记录host_closed，并核对snapshot hash。
- 首代两项上述P2回归保留目标正确断言，不写成“错误行为应该成功”的测试。

successor没有首代 `appStdinEof`独立见证接口，其原入口stdin结束调用shutdown；本包覆盖其相同shutdown hook，不声称补齐后继独立held-exit证据。auditedFixture执行真实JS witness协议客户端，但其server是合成响应器，不执行C# Core的真实App origin/task绑定或原生句柄核验；这些仍由新实际封包和主控Gate证明。

## 初次真实测试记录

- chunk `d6dc1c`：普通 `node --test tools/dev_agent_bridge/workbench_text_task_app_candidate_host.test.mjs`。旧28项通过，新11项通过，P2两项失败。因失败路径保留本机synthetic listener，测试runner尚未自然退出。
- chunk `9f3920`：仅对本次工具session41935发送Ctrl-C，结果exit1；这不是host正常关闭或native退出证明。
- chunk `949138`：`node --test --test-force-exit tools/dev_agent_bridge/workbench_text_task_app_candidate_host.test.mjs`，**41项/39通过/2失败，exit1**。force-exit仅为合成失败清理与完整失败摘要，不代替产品关闭证据。失败分别为shutdown `runtime_stop_unconfirmed`和合法创建 `503 !== 200`。

两项目标回归已经发送主控修复。修复后需重跑同41项，正常方式自然退出；实际Gate仍未运行。没有读取auth/私人日志/生产DB、没有连接47831/47841、没有启动真实provider/UAC/native，也没有修改已有隔离或P6验收定义。

## 首轮修复复核与相邻拒绝路径

主控为两代host增加product-only lazy `textAdapter()`：manifest通过前不调用newAdapter；未分配actual时closeAll仅resolve，既不制造收据也不消耗index；已有actual仍完整走原close链。未改变non-product或preflight路径。

chunk `f48883`：修复后原 **41/41通过，exit0，正常自然退出**，没有force-exit。两个已报告manifest回归都已通过。

继续复核同一条零资源前置拒绝路径发现：合法product manifest配 `config:{runtime_profile:'workbench_text_only_v1',tools:[]}` 仍会先分配actual/host record，再由 `WorkbenchTextTaskRuntimeAdapter.startSession`的严格配置检查拒绝，重现空record污染。增加第42项回归后，chunk `372cc0` 定向运行该一项：**0/1，exit1**；错误仍为shutdown `runtime_stop_unconfirmed`。使用force-exit仅清理该合成失败listener。

主控追加修复已复核：lazy wrapper在newAdapter前执行text config的exact(runtime_profile)+固定profile值检查，并前置检查extra只允许signal、signal须为AbortSignal且未aborted。manifest仍由严格binding验证task/epoch/mode；原text adapter保留最终重复验证。允许值没有扩大，真实owner收据没有例外。

## 最终本机合成结论

chunk `335c80`：正常 `node --test tools/dev_agent_bridge/workbench_text_task_app_candidate_host.test.mjs`，**42项/42通过/0失败，exit0，3581ms，自然退出**；未使用force-exit。上述manifest和config空record缺陷均由目标回归证实修复，已审查host hooks中没有剩余已识别P1/P2。普通关闭unknown仍阻止整体成功，text实际分配后的原严格关闭先决保持不变。

本次最终读取的SHA-256（chunk `9c9e21`）：

| 文件 | SHA-256 |
| --- | --- |
| `tools/dev_agent_bridge/workbench_text_task_app_candidate_host.mjs` | `4885875CA7A74A21C66884AD34FD86AA50D303474B492A47D67A5E01F10D0E27` |
| `tools/dev_agent_bridge/workbench_text_task_app_successor_host.mjs` | `840EDB8B16E830A333BFAC9515668CE68DEC41AB820FEC5D8C0459BB34563DF3` |
| `tools/dev_agent_bridge/workbench_text_task_app_candidate_host.test.mjs` | `9AC231C4E046B8DD15D14D9494138666E6BB4D5A79D67ED4C6DB3752C4296E84` |

这仅为fake ordinary transport与新本机loopback的组合证据，不能提升为真实Gateway/provider、App、UAC/native或Witness实际验收。审查worker仅改本测试与本交接文档；host修复由主控完成，未提交。
