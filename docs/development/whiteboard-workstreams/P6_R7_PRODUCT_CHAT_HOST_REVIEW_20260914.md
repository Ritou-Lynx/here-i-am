# P6 R7 普通聊天宿主只读审计

日期：2026-09-14。读取基线 `v3-lab@389aa735ca6003f3141d12f16c734c9a64441c47` 及当前未提交源码；只新增本文。未启动 App、CLI、模型、网络、UAC 或数据库查询，未读取认证文件、个人聊天、私有原始日志，未连接现役 47831/47841。遵循[接线方案](P6_R7_PRODUCT_WIRING_PLAN_20260914.md)和[依赖图](P6_R7_PRODUCT_DEPENDENCY_MAP_20260914.md)。owned22/23 已通过的隔离恢复证据维持，不把它扩称为普通聊天入口已通过。

## 结论

同一个真实 `WorkbenchConversationCoordinator` 可以通过独立 ordinary-conversation gateway 调用 `manage_long_task_queue`，并把真正的后台任务交给现有零工具文字执行器。普通 `CodexAppServerAdapter` / `CodexAppServerClient` 已具备动态工具往返和会话关停基础，专用 ChatGPT 登录也可以继续由同一 CLI 自行使用；不需要 API key、新 provider 账户、复制凭据或重新登录。

但当前冻结宿主不能仅替换 `adapterFactory` 后直接承担该功能。其 HTTP guard、native RPC、broker、session 和 witness 都存在与普通聊天不兼容的明确限制。若选“全新受控ordinary进程”，应增加独立 ordinary 能力面，后台 `workbench_text_only_v1` 原规则完整保留。**这不是唯一可行方案**：主控补充要求比较复用现役普通 Gateway；该方案不天然需要新增普通native/witness角色，见下一节。既有受控真实验收授权延续，新增封包/实现/回归不是新授权门槛；本文也没有确认当前登录仍有效或已实际运行新 gateway。

## 两条路径的具体权衡

主控补充的B路径仅静态比较，本轮仍未连接或发送。原先“不接触47831”的工作包范围不构成架构上的物理必要性。

| 项目 | A：全新独立受控ordinary host | B：借用现役已获授权普通47831 Gateway |
|---|---|---|
| 实际接线 | 新独立DB/coordinator → 新ordinary endpoint；queue → 新App-owned text host | 新独立DB/coordinator → 现役ordinary endpoint；queue仍只注入新App-owned text host |
| 新增进程 | 新ordinary CLI/native owner；可与text共享App-owned Node但分能力面 | 不新建普通Bridge。创建新provider thread可能由现役Gateway惰性启动其普通CLI；不能未经核查就称零新增进程，但该CLI依旧由现役服务拥有，不能由候选结束整个共享服务 |
| native/witness | 新ordinary角色必须纳入整体owner终态，新封包必要 | **不必**把共享Bridge/CLI列为App-owned native角色，也不应为了关候选而停止它们。现有queue native witness继续只证明新候选拥有的App/Node/text执行资源 |
| 认证来源 | 明确沿用P6专用ChatGPT home绑定 | 默认普通用户登录/config：`start_bridge.ps1:47-70`、`README.md:75-93`及默认client环境说明其不切CODEX_HOME。不能据“都是Codex”推断它等于P6专用登录，也不能从源码断言当前实际账户相同 |
| 工具权限 | 新ordinary broker只允许queue，其他builtin也在响应门前拒绝 | 当前session dynamic_tools可缩到唯一queue，产品侧照常复核原话；但这只收窄产品动态工具，不证明现役CLI的builtin、工作目录或网络权限被同样收窄。现役普通聊天原有Gate只在其已接受范围可复用 |
| 数据足迹 | 候选App数据与受控provider本机状态均需明确 | Flutter chat/TaskRoom/binding全在新DB；`ephemeral:false`仍可能将本次公开聊天provider thread/rollout写在既有普通CODEX_HOME。这是新公开会话对既有服务的正常写入，**不等于复制/读取生产DB**，但不能称所有数据都只在新DB |
| 关窗 | owned sessions、CLI/native、listener全部实际关闭 | 只关闭本次exact sessions/turns与本地clients，shared服务保持运行。不能要求shared进程exit0；也不能把本地Dio.close或普通`DELETE`的HTTP200当成provider终态证明 |
| 成本 | 同登录来源可保持，但新协议/owner工程较大 | 可复用既有普通对话模型/计费路径及provider动态工具基础；需要确认实际source配置仍属于已有授权，不能暗改为专用home、另一个模型或API账户 |

B是较小的产品纵切候选，是否可采用取决于真实已接受边界，而不是“新阶段”。若既有普通Gateway身份/配置/Gate本来就覆盖此次公开普通聊天，且用户并未要求ordinary也使用P6专用home或全量builtin前置拒绝，则复用它无需复制普通provider基础设施；严格零工具仍只施加于后台text执行器。P4/P5普通聊天或动态工具通路的历史通过只能延续到其相同配置和范围，不能证明新DB注入、新queue execution或本次会话关闭已经通过。本文没有读取这些Gate的全部原始证据，所以不据此重新判定其现势。

B实施前最小工程/核验应限定如下：

1. 用非敏感服务身份/固定进程来源、健康/能力和已授权认证类型/模型摘要辨认exact现役Gateway；不要读取auth、历史聊天或真实队列。`getAuthStatus()`源码会ensureReady，因而不能把这类查询无条件标成“零进程/零网络”；主控应按已获普通运行授权选择实际检查。发现与原批准账户/模型/权限不一致才列出该具体变化。
2. 在新App根只注入ordinary endpoint和同一候选queue tool，禁止default生产singletons、关系/搜索/白板工具。新的会话ID与provider绑定只记录本次候选，resume不能引用现役其他thread。用户公开输入仍先持久化候选ChatStore，再走同一coordinator。
3. 收集本次ordinary session/turn/tool-call identity的有界ownership台账，正常关窗拒绝新queue/回传，调用exact `DELETE /sessions/{id}`并审查其`stop_evidence.turns`、匹配provider terminal；当前`WorkbenchRuntimeClient.closeSession():231`只返回void，需要一个受控客户端/关闭适配层保留可审摘要。不得调用共享 `api.stop` / client.stop / closeAll。
4. App死亡时现役Gateway不会因候选stdin EOF自动消失。若有未决普通turn/tool-call，必须由本次App-owned Node的有限cleanup guardian按预登记exact session关闭并拒绝迟到回调；只允许向固定既有endpoint做exact session清理，不能扫描全服务。未注册成功、请求派发后session结果丢失、关闭超时和未见provider终态都记unknown，不能报告普通会话已收尾。为此可能需一个窄的普通请求代理，让所有session创建先经过guardian并在返回App前登记，而不是改共享Bridge。
5. 这不必增加普通**native** witness角色，但增加了本次借用会话的关闭义务。queue witness可原样保持其native证明范围；新组合的app_closed/整体Gate必须另有本次ordinary关闭事实，不能把现有queue host_closed当作shared ordinary已关闭。App死亡恢复时先关闭/隔离旧ordinary会话，恢复App仅创建新的候选绑定，绝不重放旧工具调用。若决定整体恢复permit必须由witness承载该外部session义务，只增其有限session证明合同，不新增shared进程exit条件。

因此B的真实差异是：ordinary采用既有普通登录/配置而非可证明的P6专用home；公开provider会话可能保存在既有home；其builtins延续既有普通权限；共享服务保留运行但本次session必须实际结束。若这些已在既有授权/Gate内，主控可直接完成上述受控工程与验收；若不在，则精确说明那一项差异，不泛称“新增费用/需要重登”。A只有在确需全新专用ordinary数据/权限边界时才值得支付新增broker/native/witness工程成本。

## 可直接复用的接点与不可直接复用的配置

| 层 | 源证据 | 最小处理 |
|---|---|---|
| 普通 coordinator | `lib/data/workbench_ai/workbench_conversation_coordinator.dart:366,406,693` | 注入真实 `WorkbenchConversationRuntimeGateway`；只装配候选 queue tool，保留 `_dynamicTools`、当前原话授权及实际 tool dispatch。ordinary 与 text 客户端不能互换。 |
| App HTTP 客户端 | `lib/data/workbench_ai/workbench_runtime_client.dart:85,110,129,210,231` | 新端口 + 固定 admission headers 可通过显式 `bridgeUrl` / Dio 装配。现有创建/恢复默认 `ephemeral:false`，候选需要显式处理本机 provider 会话持久化边界，不能只隔离 Flutter DB。 |
| Runtime 路由 | `tools/dev_agent_bridge/experimental_runtime_api.mjs:176,363,386,496,555` | ordinary 使用独立实例的 `adapterFactory`；其 `textAdapterFactory` 为空，文字请求仍 fail closed。后台实例只提供原 text factory。可在同一个 App-owned Node 内使用两个独立 listener/能力令牌，避免为了 gateway 再增加一个 Node。 |
| 动态工具 adapter | `tools/dev_agent_bridge/codex_app_server_adapter.mjs:185,741,1062,1110` | 复用 `dynamic_tools` → `dynamicTools`，`item/tool/call` → 产品事件，及 `respondToToolCall`。candidate wrapper 必须固定唯一工具定义/参数 schema，不能相信 HTTP 请求能自行扩大目录。 |
| 普通 adapter 环境 | `tools/dev_agent_bridge/experimental_runtime_api.mjs:163`；`codex_app_server_client.mjs:44,146` | **现有 `createExperimentalRuntimeAdapter({env})` 没有把 env 传入 `clientOptions`**，只读取 command/model/cwd；直接调用它不能证明使用专用环境。用显式 `new CodexAppServerAdapter({clientOptions:{commandSpec,cwd,env,experimentalApi:true},...})`，或更小地修复传递。不得继承默认全局环境、PATH resolver、真实工作目录。 |
| Provider thread 参数 | `codex_app_server_adapter.mjs:741-763` | 现有 `_threadParams` 不传 `modelProvider`、`baseInstructions`、空 environments/workspace roots；如接新增 native ordinary owner，需要窄的可信 wrapper/client seam 构造固定合同参数。不能原样接当前 native text RPC。 |

ordinary gateway 可以沿用现有普通 adapter 的动态工具协议，但不能把“普通 adapter 支持”说成“本次 pin 的所有动态工具能力已实测”。真实发送前需核对封包的非敏感能力/认证摘要；不打印 account identity 或完整 config 层，更不读取 auth 内容。

## 登录、provider 与费用来源

`workbench_text_gate_login.mjs:17-35,68-101` 已定义独立 home、隔离工作目录、`cli_auth_credentials_store=file` 和 ChatGPT 类型校验。当前 native 真实路径不能只照旧逻辑字符串拼接：`windows_text_gate_task_executor.cs:118-140` 固定验证 packaged Codex 的物理 home 与逻辑 home 指向同一目录，之后只把 dedicated home 注入 `CODEX_HOME`，其余 HOME/USERPROFILE/TEMP 仍是本 attempt 空目录。新 ordinary owner 应复用这个**目录绑定机制**，由 CLI 读取既有登录；不复制 auth、不放松路径/ACL 检查。

后台本地 provider 名 `p6_native_startup` 是受控 broker 的别名，不代表 API 计费账户：`windows_text_gate_isolation_helper.cs:720-738` 固定 loopback Responses provider，`windows_text_gate_task_executor.cs:128-129` 仅在 authenticated 模式改为 `requires_openai_auth=true`；`workbench_text_task_broker.mjs:14-17,105-118,191-198` 最终仍使用 CLI 的 ChatGPT authorization/account-id 请求 `https://chatgpt.com/backend-api/codex/responses`。

因此 ordinary 可以保留同一 ChatGPT/Codex 路径及账户费用来源，单独增加允许动态工具的协议门。后台模型固定 `gpt-5.6-sol / low` 的既有合同不变。ordinary 模型/effort必须取封包明确的已授权配置；不能因主控当前模型或新环境默认值而暗改。静态源码不能证明当前额度、账户状态或模型可用性；实际运行按新候选返回的有限摘要核对，失败则拒绝且保留原因，不自动切 API。

普通聊天加工具结果续轮本来就会产生额外模型 exchange，不能承诺与单次文字任务“相同消耗量”；它仍可使用同一费用来源。已授权普通入口实际验收覆盖这些受控合法往返，不因每次 exchange 重问许可。

## A路径为什么需要独立 ordinary allowlist

现有 text 链必须保持如下限制：

1. `workbench_text_task_app_candidate_host.mjs` / `workbench_text_task_app_successor_host.mjs` 的 HTTP guard 仅接受 text sessions/events/turns/interrupt/DELETE，不接受普通 `tool-calls` 回传或 thread resume；ordinary factory直接抛错。
2. `windows_text_gate_task_executor.cs:379-388` 原生 RPC 只允许有限方法；`thread/start.dynamicTools` 必须为空。返回 provider server request 时只接受 `{id,error:-32601}`，不接受动态工具 `{id,result}`；没有 `model/list` 或 `thread/resume`。
3. `workbench_text_task_broker.mjs:86-102,136-166,180-194` 重建单一授权用户输入，删除工具、历史与 assistant 内容，固定 `tools:[] / tool_choice:none`，并只准一次 upstream exchange。工具回传及普通连续对话不能经过它。
4. `workbench_request_text_gate.mjs:31-42` 丢弃整个 `additional_tools`；`workbench_response_text_gate.mjs` 的完整响应校验不允许工具结果成为通过响应。`workbench_text_task_session.mjs:37-41` 对所有 server request 都失败并关闭。

**采用受限 CLI→broker 网络边界时，ordinary 必须有单独的新 allowlist；不修改上述 text gate 来兼容聊天。** 最小 ordinary 协议应做到：

- 固定唯一 `manage_long_task_queue` schema；剥除/拒绝 builtin、MCP、collaboration、嵌套 `additional_tools`、任意 namespace。普通 adapter 的动态工具 allowlist只能拦产品 server request，不能证明 CLI 内建工具从未执行；功能开关或 read-only sandbox 也不替代该证明。
- 对完整 provider 响应完成校验后，才释放允许的 queue `function_call`；保留对应 call-id/thread/turn 绑定，只接受该调用的真实产品结果继续一轮。超界、重复、未知工具和未匹配 output 都 fail closed。SSE 不能先透传未知工具再事后拒绝。
- 允许受控多次 exchange，且每个 continuation 都有计数/字节/时限、实际已提交工具结果和 owner 绑定。不能复用 text broker 的 `used` 单次位，也不能让 CLI 自带历史、任意 tool-output 或 remote thread id 扩大上下文。
- native ordinary RPC 单独允许匹配 `item/tool/call` 的有限 `result` 及必需元数据方法，保持其余请求拒绝；若复用 adapter `_ensureReady`，需支持其 `account/read` 与 `model/list`，或用真实固定能力核验后的窄 seam，不能用 mock account/models 绕过。
- ordinary 的 admission 声明它允许队列工具；绝不发 `workbench_text_only_v1` receipt。text 客户端对该 receipt 必须拒绝。

直接启动普通 unrestricted app-server 虽然不需要新 broker，也可能使用同一登录，但会绕开这条受控网络门，且普通配置没有证明仅可运行 queue tool；本候选不把这种方式默认为已有隔离通过，也不以现役 Bridge 或默认 CLI配置替代。

## A路径生命周期与 native witness 的最小关联

普通会话关停已有基础，但不是完整进程收尾：`codex_app_server_adapter.mjs:564-667` 会拒绝挂起工具/approval、对活动回合 interrupt 并等待匹配终态；它的 `local_binding_closed` 不等于 native child 已退出。`adapter.stop():675` 只委托 client.stop；`experimental_runtime_api.mjs:521-544` 停止普通 adapter 时不逐个调用 closeSession，pending 跟踪也主要面向 text。新 ordinary owner 必须先封新请求/回传，保有启动中的 ownership，逐个关闭会话、join实际在途调用，再等待 client/原生进程及管道关闭。

`codex_app_server_client.mjs:227-270,514-522` 区分 signal/kill 与实际 `close`；`attachedTransport` 路径 `:200-221` 必须得到 `process_close_observed`。可复用这些机制，但不要把一个直接子进程 `close` 推升为整个新 ordinary 进程树/网络规则已收回。采用独立 native owner 时应与后台一样提供真实受持句柄、job empty、双 EOF、规则和 helper收尾；如果采用不同的 owner 合同，要具体记录不同证明，不能伪造 text receipt。

Witness04 不能原样登记 ordinary：

- `tmp/p6-r7-review/owned-recovery-witness-04/OwnedRecoveryCore.cs:234-255` 要求 owner顺序增加、上一个已关闭，非首个 owner必须已有 `originBound && taskBound`，并固定同一个 NativeHash。普通 chat必须先于 enqueue存在，且可能与后台任务重叠，因此不适用这个序列。
- 同文件 `:283-330` 的 host_closed / app_closed / claim 固定现有 owner清单与单一 App/Node关系；`workbench_owned_recovery_witness.mjs:109-127` 也只有 text owner的统一 native hash/六项合同。不能加一个 Node/CLI后，只读 PID 或隐瞒它便继续签发恢复许可。
- `OwnedRecoveryBootstrapConfig.cs:33-79` 固定schema、path/pin allowlist和host闭包；新 ordinary模块/原生程序需要新封包，不改 Witness04冻结文件或沿用旧清单冒充。

建议最小扩展是**同一 App-owned Node下的独立 ordinary runtime角色**：登记独立 role/closure/native pin、进程/child identity、gateway token、会话集合及终态；允许 ordinary先于 task绑定和与唯一 text任务并存。queue侧仍保留单 task、顺序 attempts及一次 successor，ordinary角色不增加队列任务数或放宽同库恢复。

新 witness 的 host_closed 必须同时要求 ordinary 全关闭与 text全部owner全关闭；正常关窗之后才close两客户端/Store、提交app_closed。App异常死亡后仍要求原 App held exit、原 Node有序EOF收尾、所有角色实际终态及原 Node held0，才授予一次恢复；ordinary未终止、启动结果未知或关停缺证据时继续冻结。恢复后队列仍为 interrupted/等待、显式继续；不能重放恢复前未决 queue tool-call 自动执行动作。普通对话可从候选本机消息重新创建短会话，provider thread恢复必须另有精确同候选绑定；不得从专用home扫描历史thread补齐。

当前 `WorkbenchTaskProductClose` 的 `closeConversation` / `closeOwnedHost` seam 可承接上述顺序，但一个 `true` callback本身不构成 native收据。候选实际关窗仍须绑定该新owner合同。关窗前封queue写入与关闭ordinary回传应原子进入closing，避免迟到模型工具结果在close之后创建或恢复任务。

## A路径最小工程与验证清单

1. 新 ordinary gateway/host wrapper及其请求响应门：固定已授权来源、schema、candidate endpoint和唯一queue工具；普通 adapter/client复用，显式环境注入。text模块只作既有回归基线。
2. 新 ordinary native启动/RPC合同与transport绑定：复用安全启动、固定home、网络及进程owner机制，单独处理合法queue工具回传，绝不修改冻结零工具能力定义。
3. 新候选witness/bootstrap支持独立ordinary角色，保留单task/单successor；完善普通session pending start、matched terminal、真正process close、未决tool拒绝和late-response屏障。
4. 与独立 CandidateChatStore、同一 coordinator、同一 queue authorization factory装配；UI目标来自用户原话，禁止固定数字按钮、mock coordinator、手改DB或真实单例fallback。
5. 本地验证只覆盖增量：动态queue往返/未知工具拒绝/错call-id/关闭竞态、环境不继承、无admission零spawn、ordinary与text不能互换、关窗及App死亡时ordinary缺证据拒绝恢复。构建/新候选实际Gate由主控按已授权范围串行完成，不能拿单测替代普通入口与新进程组合的实证。

没有从源码发现必须更换认证或费用来源的事实。真正会改变授权边界的情况应精确识别：改为API key或其他账户/provider；把新ordinary当作可读任意本机文件/可运行额外工具的进程；连接真实个人库或现役service；改变后台零工具执行定义。这些均不是本文建议的实现。新role、新封包、新动态工具allowlist及与其相关的实际验证是完成已授权普通入口所需工程，不应笼统写成“新阶段所以需重新批准”。

验证：静态源码/非敏感固定合同审读，文档路径和diff检查；未运行产品、模型或测试。本报告由worker交主控复核及统一项目closeout，不改全局状态。
