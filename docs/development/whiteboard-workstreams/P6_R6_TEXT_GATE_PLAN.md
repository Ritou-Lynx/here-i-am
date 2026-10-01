# P6-R6 工具执行前拒绝：请求与响应双向文字门

更新：2026-09-11（工作跨 9 月 7–11 日）。承接 [R5](P6_R5_STOP_AND_EXECUTION_BOUNDARY.md)。专用登录与真实固定文字回合已通过；生产隔离和真人 Gate 未通过。

## 已确认口径与边界

- 用户已明确回复“同意”：保留 Codex，允许模型侧目录残留，但所有工具调用必须在执行前被拒绝。该决定不等于当前实现已通过；不再重复请求这项确认。
- 当前任务 `01a07b2e-1717-7582-8555-909389a9c03e`；起点为 `v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b` 加既有未提交成果。9 月 10 日恢复时 HEAD 已由其他工作推进到 `bbb8025d99fc0acaa846d58b4e5a94cef90f8756`；提交差异仅为 Android BLE 与相关文档，没有修改 Bridge / P6。原五项 staged 和其他工作保留；本任务不提交、推送或新建自动 Goal。
- 本轮先实现可验证的候选边界及 loopback 合成接线；生产 profile 持续拒绝，直到完整路径成立。真实账户、新候选和真人生命周期验收分别报告，不用合成证据替代。

## 选择理由

- 普通 App Server 宿主请求只覆盖动态工具/审批子集，内建工具可以不经过此入口。原始事件是通知，没有同步 veto；收到后 interrupt 不构成执行前拒绝。
- 官方 [Hooks](https://learn.chatgpt.com/docs/hooks#tool-coverage) 明确 hosted 工具与部分特殊路径不覆盖；hook 失败可继续调用。因此不以通配 deny hook 作为完整边界，也不扩展现有宿主拦截来冒充全局分派器。
- 候选位置改为 **模型请求发出前 + 原始响应交给 Codex 前**。上游请求从允许字段重新构造，去掉所有工具目录、已有服务端会话引用和非文字输入；固定 `tools=[]`、`tool_choice=none`、`parallel_tool_calls=false`。这样 hosted 工具不会由本次请求授予。
- 原始响应有界缓冲，成功完成且全量通过严格白名单校验后，只提取 assistant 的 output_text，重建全新的安全 SSE。工具/未知项目、异常、截断或超限均拒绝；不透传原始事件和隐藏字段。工具名称/别名无须逐项猜测。
- 这仍需验证不可绕过的唯一接线、关闭和真实认证兼容；provider 自身履约不是本地合成测试可以证明的事项。

## 所有权与工作包

| 包 | 执行者 | 拥有路径 / 输出 | 状态 |
|---|---|---|---|
| 响应文字门与网络层 | 原 R5 停止 worker，Astra high | 隔离目录新增 response gate、transport、专项测试和自身 R6 handoff | 冻结后按哈希回收；见[响应交接](P6_R6_RESPONSE_GATE_HANDOFF.md)和[网络交接](P6_R6_TRANSPORT_HANDOFF.md) |
| 请求文字门、合成接线与登录准备 | 主控 Astra | request gate、CLI probe、专用登录 helper、有限 live probe 与脱敏诊断；本计划和全局状态 | 登录与真实固定文字回合已通过；生产接线仍待 |
| 边界与整合审计 | 原 R5 审计 worker，Astra high；恢复后 Terra medium | 只读本地协议/源码、官方文档及冻结交付 | 无未关闭 P1/P2；登录路径 junction 问题已修复并补 4 项测试 |

## 完成条件

1. 正常文字可到达 CLI 并完成，证明路径可用；固定合成工具正控能被未经门控的测试路径接收，避免无效 harness 误通过。
2. function/custom/hosted/未知工具项、混合文字与调用、截断和未知事件被响应门拒绝，零下游原始帧和零工具分派。
3. 出站请求仅包含重建的文字上下文和固定无工具设置；既有 response/conversation 引用、隐藏调用/工具输出及未知输入形态不能绕过。
4. 超限/错误/断连默认拒绝，不发布部分成功产物；测试与实际 CLI 都由同一门库执行。
5. 独立审计复核两道门与接线；不因单库或 loopback 测试通过启用真实执行。

## 已完成与证据

- 请求门重建文字上下文；响应门有界缓冲、全量校验后生成新的文字 SSE。网络层在 HTTP 正常 EOF 后才调用 finish；completed 后追加工具帧、断流、超时或取消都不能放行先前文字。重定向不跟随，认证/header 与上游地址只能由宿主固定配置提供。
- 9 月 10 日当前主目录组合 **102/102** 通过：请求 13、响应 66、网络 13、登录路径 4、生产拒绝 profile 6；0 fail / cancelled / skipped。仅 R6 CLI pin 更新后登录路径 **4/4** 再通过；未修改 R4/R5 旧 pin 或生产 profile。
- 旧 CLI `0.153.4` / SHA `e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75` 的两层 HTTP 合成报告后缀 `Y2OaNz` 为历史 **14/14**。桌面更新移除了该程序，因此没有继承为新程序通过。
- 新 CLI 仍报 `0.153.4`，SHA `ccdc9eb9dd71fbcfb03ad42c4eca2b0d6ff6fbd32ebe9416550e6244561e559b`，由 R6 独立 runtime pin 固定。新报告后缀 `y8hyD4` 重新 **14/14**：一个可实际分派的合成动态工具正控、一个正常文字正控、12 个负例。正常文字确实完成；12 个负例均零下游字节、零文字、零 host server request，分别覆盖调用/未知项/混合文本、未知事件、截断、终态后调用、断连和超时；所有进程实际 close。报告明确 `synthetic_only=true`、`production_isolation_passed=false`。
- 脱敏报告与源码指纹见 [R6 本地验证清单](../../../tmp/p6-r6-review/final-verification.json) 和 [新 CLI 合成报告](../../../tmp/p6-r6-review/cli-synthetic-report.json)。报告仅为 loopback 固定合成数据，不含账户、登录链接或 token。

下表为 9 月 10 日历史快照；9 月 11 日当前指纹见本节后的新验证清单。

| 门库 | SHA-256 |
|---|---|
| workbench_request_text_gate.mjs | `2A477A238E87DAFC726D859FA58DB72C60B2C9AE3CDF66C035AE8EF5A001CB05` |
| workbench_response_text_gate.mjs | `7FC87E7478F3D94575DD817BC43616359D48716F5C1F3ED8AC371232D188308E` |
| workbench_text_gate_transport.mjs | `B8BF7373DC767A910AA58BA7BF3AF00BCE0D266DA24F46479D2B087DA249C957` |

## 认证状态与当前剩余

- **专用登录已成功**：用户完成新的官方授权后，helper 返回 chatgpt_login_confirmed；新的独立进程 status 返回 chatgpt_login_available。两次均 model_requests_sent=0、process_close_observed=true。普通网页首页与专用 CLI 授权已分别核对，不再要求用户重复登录。
- 专用目录和路径/junction 防护保持；CLI 自己管理凭据。helper 只使用正常 account/login/start/account/read，不读取、复制或导出认证文件。此前超时、login_setup_failed 和设备码候选失败均属历史，不作为当前登录状态；登录专项现为 7/7。
- 有限 live probe 先查 ChatGPT 账户与严格配置，独立 --inspect 不创建 thread/turn。实际配置检查全部通过；认证存在只记 boolean。CLI 在账户和 thread 阶段查询 GET models，现最多 8 次仅返回本地常量 404，不转发、不占生成预算；带 body/encoding、越界路径或其它方法仍拒绝。
- CLI 把环境放在早期 user 消息：出站前验证最后一个 user 为唯一固定句，丢弃所有早期 user/system/developer/catalog 和缓存元数据，再仅用固定公开指令重建请求。assistant、不同最后文本、重复固定句及历史引用仍拒绝；一次运行最多一个固定 turn/一次 transport 尝试。
- live-01 至 live-04 均为本地检查拒绝，upstream_attempts=0。live-05 首次 transport 尝试失败；不带凭据的连接检查显示直连超时，沿用本机已有代理可达。主控 Node 显式使用 --use-env-proxy，未改全局网络设置，专用 CLI 仍只访问本地候选代理。
- live-06/07 在收到成功状态后因 Content-Type 缺失拒绝；live-08 的有界内存诊断识别完整 SSE。现仅精确官方目标、重建 stream=true、header 确实为 null 时选 SSE 解析；显式空/未知类型及其它目标不放宽，所有路径仍必须正常 EOF、严格 UTF-8/schema 校验后重建文字。
- 新增有限响应 metadata 和 message.phase 类型/枚举校验，全部验证后丢弃。tools 只能空、tool_choice 只能 none、parallel_tool_calls 只能 false；未知嵌套字段、工具项、错误、截断和 reasoning 新事件仍拒绝。已根据官方 Codex [SSE 消费类型](https://raw.githubusercontent.com/openai/codex/main/codex-rs/codex-api/src/sse/responses.rs) 与 [用量元数据类型](https://raw.githubusercontent.com/openai/codex/main/codex-rs/protocol/src/response_usage.rs) 另补有限 headers、usage_metadata、end_turn、用量预算及 reasoning.context/mode 校验；这些公开候选并未消除 live-10 的剩余未知字段，不能据数量对应猜测实际名称。类型参考 [官方 Response](https://raw.githubusercontent.com/openai/openai-python/main/src/openai/types/responses/response.py) 与 [消息 phase](https://raw.githubusercontent.com/openai/openai-python/main/src/openai/types/responses/response_output_message.py)。
- live-10 及更早拒绝保持历史证据；live-11 至 live-19 逐层定位 frequency_penalty、presence_penalty、tool_usage、usage.attribution、delta 随机填充及空终态输出，九次均未放行、实际 close。没有保存原始正文或字段值。
- 新的闭合本地兼容子集：两种 penalty 只接受 [-2,2] 有限数；tool_usage 只允许 image_gen/web_search 的已列明数值计数且全部必须为零；attribution 只允许受限 items 映射与 request_fields.instructions 数值计数，合法键、最多 64 项、非负安全整数及已列明 details。所有 metadata/标识被丢弃，未知字段/字符串内容/非零工具计数仍整流拒绝。该子集以实际字段形状和本地保守约束为依据，不宣称完整官方 Responses schema。数值词表参考 [官方图像 usage 类型](https://github.com/openai/openai-python/blob/main/src/openai/types/images_response.py#L11)，并不据此推断 backend 语义或工具实际执行情况。
- **最新真实固定句通过**：live-text-probe-20.json 为一次 transport 尝试；response_released=true、fixed_text_observed=true、turn_completed=true、process_close_observed=true、server_requests_rejected=0，status=fixed_text_confirmed。完整正常 EOF 后门控重建的文字确实到达 CLI，并收到匹配 thread/turn 完成通知；这不是执行中止回执，也不是 provider 的全局工具履约证明。
- 诊断默认关闭。协议键诊断仅允许固定官方地址、模型、公开指令/单句请求，在正常 EOF 且 unknown_field 拒绝后才附加；最多 256KiB/256 帧，固定路径、敏感名过滤与逐层 16 键上限。items 不输出任何动态键，仅 opt-in 聚合至多 64 个直接值的固定计数类型；不自动递归、不输出任何内容值，报告深冻结/模块品牌校验。审计发现的旧 items 键枚举泄露路径已移除并补小写动态键回归。
- 当前组合 **170/170** 全部通过，无失败/跳过/取消；同一 pin CLI 合成 **14/14**，12 负例零下游字节/文字/host 分派，所有进程 close。证据见 [当前验证清单](../../../tmp/p6-r6-review/real-text-turn-verification-20260911.json)、[真实通过报告](../../../tmp/p6-r6-review/live-text-probe-20.json)、[源码绑定](../../../tmp/p6-r6-review/live-text-probe-20-source-binding.json)、[当前 CLI 合成报告](../../../tmp/p6-r6-review/cli-synthetic-real-text-turn-report.json)。此前 102/102、154/154 和拒绝报告仍为历史快照，未覆盖。
- 剩余顺序：不可绕过的唯一代理/进程来源隔离，专用 exact provider thread/turn 停止回执，然后新候选取消/执行/恢复验收。专用登录已确认，常规电脑操作已有授权，不再重复登录或改接 API/费用来源。
- workbench_text_only_v1 持续 available=false、fail_closed=true，start/resume 拒绝。没有新 App 候选、真实队列操作、构建安装或提交推送；原五项 staged 保留，P6 与父 Goal 1 均未通过。

### 本次流式协议兼容的关键约束

- `response.output_text.delta.obfuscation` 仅允许最多 8192 字符的字符串，验证后丢弃；不扩展到 done 或其它事件，不进入文字。官方 [StreamOptions](https://github.com/openai/openai-node/blob/master/src/resources/responses/responses.ts#L10465) 说明 delta 默认使用随机填充；本地长度限制是保守策略。
- 仅 SSE 的 completed.output 明确为空数组时，允许从已有且全部通过 `output_item.done` 校验的项目重建；至少须有一个有效文字消息，非空终态仍逐项严格一致。JSON 空输出、缺失 item.done、文字冲突、工具项目和终态后追加帧均拒绝。官方 [Codex SSE 消费与测试](https://github.com/openai/codex/blob/main/codex-rs/codex-api/src/sse/responses.rs#L1309) 覆盖 item.done 后 completed.output=[]；本地的全流一致性验证仍保留。
- attribution.items 的 content 只允许一层、最多 64 项的数值计数数组；不接收正文、调用或再次嵌套的 content。诊断对该层也只聚合最多 64 个对象的字段类型，不输出动态映射键或任何值。
- 当前 170 项分组：请求 13、响应 82、网络 22、登录 7、生产拒绝 profile 6、live 20、诊断 20。当前源码和测试 20 项文件已与 live-20 前后指纹一致性绑定，后续真实候选须重新取证。
