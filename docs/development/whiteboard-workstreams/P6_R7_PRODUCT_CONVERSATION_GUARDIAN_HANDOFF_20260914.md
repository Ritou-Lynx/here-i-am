# P6 R7 ordinary conversation guardian 本地交付

日期：2026-09-14。基线 `v3-lab@389aa735ca6003f3141d12f16c734c9a64441c47`。本包只新增以下三文件，未改现有源码、生产配置、witness 或全局状态；未提交，未连接47831/47841，未启动CLI、真实provider、App或UAC。

- `tools/dev_agent_bridge/workbench_product_conversation_guardian.mjs`
- `tools/dev_agent_bridge/workbench_product_conversation_guardian.test.mjs`
- 本文。

采用[审计B路径](P6_R7_PRODUCT_CHAT_HOST_REVIEW_20260914.md)：新候选借用既有普通Gateway的一条新公开会话，队列执行仍交给独立App-owned严格text host。本模块只负责借用会话，不停止shared Gateway/client/CLI，不扫描session、provider thread或真实队列，不声明text-only receipt。

## 接口

```js
const guardian = new WorkbenchProductConversationGuardian({
  conversationId,    // 可信bootstrap固定值
  dynamicTool,       // 主控固定的现有manage_long_task_queue定义
  transport,         // async ({method, path, body?}) => 真实Adapter的已解析JSON
  closeTimeoutMs: 30000, // 可省略；范围1..180000，只限制guardian收尾等待
});

guardian.startSession(config = {}, contextManifest = {});
guardian.startTurn(sessionId, input, params = {});
guardian.readEvents(sessionId, {afterSequence = 0} = {});
guardian.respondToToolCall(toolCallId, {success, content_items});
guardian.interruptTurn(sessionId, turnId);
guardian.closeSession(sessionId); // 有效关闭时返回原Adapter snapshot/stop_evidence，否则抛固定code
guardian.closeForHostLifecycle(); // 永远返回有限closed/unknown结果；并行调用共用promise
guardian.snapshot();             // 仅身份、计数、状态，无对话/工具参数或凭据
```

transport必须由主控固定目标、身份校验、有限响应体和请求超时后注入；本模块不实现fetch，不接收URL/headers/auth/model/command参数。`path`只能由模块生成：固定前缀下的本次session创建、events、turns、interrupt、exact tool-call reply及DELETE。没有resume、steer、approval、全局stop或枚举接口。主控仍须核验现役身份/来源属于原授权范围后才允许真实连接。

`startSession`固定 `ephemeral:false`、`service_name:here_i_am_workbench` 和唯一exact dynamicTool；调用方可省略这些字段，若提供则必须一致。动态工具的name必须是 `manage_long_task_queue`，schema由可信宿主提供并冻结；请求不能改schema/说明、增加或清空工具。manifest固定 `{conversation_id, profile:'workbench', scope:'desktop_chat'}`，不能放入模型可控授权或endpoint。保留ordinary既有profile，不伪装为后台零工具profile。

## ownership、事件与关闭语义

- 一条guardian只允许创建一次session。POST成功返回的exact本地session/provider thread先登记，再交App。早到EOF时登记late结果后不再交App，并由同一cleanup tail发送exact DELETE。
- 无session ID、丢失创建回执或turn/start结果未知都sticky unknown；不通过provider枚举、PID或DELETE中出现的额外turn猜测缺失身份。返回exact session ID但其余字段异常时仍保留它做DELETE，不能因此认证成功关闭。
- 开新turn须所有已登记turn有匹配的provider terminal，且无未决tool。未响应/发送结果未知的旧tool不被新turn清空。一条turn可顺序处理多次队列调用。
- events按本session、已登记turn、连续sequence及event identity校验；只有本会话事件中的唯一queue call才登记为pending。重读旧cursor不会再次交付已见tool_call，旧call-id不能重放。未知工具、外来session/turn、伪造终态、重复call-id与历史缺口均冻结为unknown。
- closing同步封新ordinary请求及回传。close先等待必要的session创建登记，随后立即DELETE，不先等待pending模型/tool回复。现有Adapter `closeSession`会先fail-close pending tool callbacks，再interrupt并等待匹配 `turn/completed`；已在途的turn start、read、reply、interrupt仍保留并join，late event不会交App。
- 关闭只接受 `_sessionSnapshot`真实字段：exact session及provider ID、status closed、local_binding_closed true、完整且无重复的已登记turn集合。每条必须有 `provider_terminal_confirmed:true`、`source:'turn/completed'`、匹配provider/turn ID、正整数provider sequence、completed/failed/interrupted，并与此前已知terminal一致。ACK、HTTP200、local closed或offline unavailable均不能提升。
- 零turn的已创建session可关闭，但只接受 `turns:[]`、aggregate provider_terminal_confirmed false且无未知start或tool义务；它证明session关闭，不证明发生过provider terminal。从未尝试创建时，lifecycle close可零请求完成。
- 同一close只发一次DELETE。close失败/收据错误/超时sticky unknown，不自动重试共享服务。超时后已拥有的cleanup tail不被丢弃；late session ID仍会得到DELETE，但不会把原unknown改写为closed。普通tool reply仅传输回执丢失时禁止重发/开新turn，后续exact session terminal close可解决其关闭义务；这不同于session/turn start未知。

`closeForHostLifecycle()`返回：

```js
{status:'closed'|'unknown', conversation_id, session_id,
 turn_ids, reason:null|fixedCode, shared_gateway_stopped:false}
```

root必须把ordinary closure与queue shutdown作为同级先决。unknown不能签发组合host_closed、app_closed或成功exit0；保留Node与cleanup ownership。该结果不是native资源收据。App死亡时需由实际原stdin EOF调用同一方法；只读PID不触发替代证明。App侧queue写入必须与guardian closing一起封住，防止已交付工具在关窗竞态中继续执行。模块本身不操作DB或赋予queue授权。

## 有限边界

本地上限为1 session、64 turns、512 tool-call identities、16384 event identities；每次读最多1000条，与当前Adapter事件缓存上限一致。历史有缺口时拒绝，不跳过未知工具。新产品候选不据此宣称无限普通聊天或多session恢复能力。

当前普通Gateway按原配置运行；guardian只限制候选的产品动态工具和会话ownership，不证明shared CLI全部builtin在执行前已被拒绝。公开provider会话仍可能保存于既有普通CODEX_HOME。专用后台的登录、费用来源和零工具执行器不改变。实际Gateway身份/授权核验、Node产品host/HTTP端点/令牌接线、bootstrap、App关窗/EOF集成及真实普通入口Gate由主控完成。

## 验证

实际命令 `node --test tools/dev_agent_bridge/workbench_product_conversation_guardian.test.mjs`：**24/24通过，exit0**。全部使用注入假transport；额外合同测试使用真实 `CodexAppServerAdapter`配内存EventEmitter client，没有child、listener或真实请求。

覆盖foreign ID/单工具定义、EOF期间late session/turn、丢失startsticky unknown、close timeout后的late cleanup、多次tool正常往返、旧工具重放、pending reply及poll与关闭竞态、关闭先DELETE避免tool deadlock、有效/错绑/offline/ACK终态收据、并行exact-once close、closing后拒绝新动作。真实Adapter合同测试确认DELETE先返回pending tool的失败结果，随后观察同turn的 `turn/completed`；shared client.stop计数为0。

三文件链接/空白检查与语法检查通过。仅局部本地合同验证，不代表已连接现役Gateway、新App候选已集成，或普通入口真人Gate通过。由主控复核diff、接线、验证并统一项目closeout。
