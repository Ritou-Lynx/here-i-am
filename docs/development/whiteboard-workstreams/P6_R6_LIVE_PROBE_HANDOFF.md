# P6 R6 有限真实文字探针候选交接

日期：2026-09-10。基线：`v3-lab@bbb8025d99fc0acaa846d58b4e5a94cef90f8756` 加当前 R6 未提交依赖。仅新增本交接、`tools/dev_agent_bridge/workbench_text_gate_live_probe.mjs` 及对应 `.test.mjs`；未提交、未操作 index，未改全局状态。

## 已完成

- CLI 必须显式传入 `--live <R6 固定指纹的绝对可执行文件路径>`；缺省只输出拒绝报告。可选 `--report <主控指定的绝对报告路径>` 只排他创建新文件；未指定则只输出脱敏 JSON。worker 没有运行真实 CLI 或真实 provider。
- 复用 `prepareDedicatedHome`、`CodexAppServerClient`、`restrictions(false)`、R6 runtime pin、`exchangeTextOnly`。不读取、复制认证文件，不读取环境 token；仅转发本次 CLI HTTP 请求中的合法 Authorization Bearer 和可选 ChatGPT-Account-Id，报告只含 presence boolean。
- 独立 home/cwd、最小环境、空 cwd 校验、agents false、无持久历史。custom provider 指向本进程唯一 loopback listener，`requires_openai_auth=true`，websocket/压缩/两种 retry 关闭。配置读取必须先通过保守验证；已有配置、MCP、非空 hooks、认证覆盖及非候选 URL 均拒绝。
- account/read 必须确认 ChatGPT 才创建一个 ephemeral thread。固定 `gpt-5.6-sol`、`Reply exactly: P6_TEXT_GATE_OK`、dynamicTools 空、approval never、read-only、无环境/工作区/能力 roots。唯一 turn；匹配 thread/turn 的完成事件才用于本次报告。任何 serverRequest 立即报错拒绝并解除放行。
- 代理仅接受 `POST /v1/responses`、无 query、JSON、无压缩、64 KiB/16 messages 上限；拒绝错误模型、不同 user 文本、历史、assistant/tool output。CLI 编译 catalog、system/developer 内容及 instructions 均在验证后丢弃，重建固定公开合成指令/单条 user 文本，避免本机路径、缓存、元数据和工具目录出站。
- 唯一候选上游固定为 `https://chatgpt.com/backend-api/codex/responses`。request body 不能覆盖 target/model/auth。进程级不可重置 live budget 和同步占位将真实 transport 调用限制为最多一次；body 收集后重查，覆盖并发竞态。失败后无重试。
- 只有 `exchangeTextOnly` 观察真实 EOF 且整个响应门接受后，才把重建 SSE 一次性发给 CLI。上游 error message/gateCode、header 值、账户/email/id、原始请求/响应、stderr 均不进入报告或 console。HTTP status 仅受限整数；其他错误只用本模块稳定 code 白名单。
- 成功或失败均 disarm/abort、调用真实 client.stop 等待 process close、关闭本地 listener。不会签发 stop_receipt。即使固定文本成功，`production_isolation_passed=false` 和 `human_gate_passed=false` 始终保持。

## 本地验证

`node --test tools/dev_agent_bridge/workbench_text_gate_live_probe.test.mjs`：11/11 通过，全部 fake/in-memory/loopback；没有真实 CLI、真实 auth/provider、真实队列或设备动作。

覆盖：固定上下文重建；模型/目标/header body 注入拒绝；未放行、错误路径/格式/体积/缺少 auth 零上游；五个并发请求最多一个 transport 调用；失败无重试；错误/账号/headers 脱敏；环境与 provider 配置；缺少 ChatGPT 登录时零 thread/turn/上游；唯一 ephemeral turn 参数；host callback 拒绝；stop 失败不能成功；缺少 `--live` 默认拒绝。

## 未验证与限制

- 主控登录尚待确认。本 worker 没有验证账户可用性、真实请求、真实配置回显或真实模型行为。
- 真实 config 回显尚未验证，可能保守拒绝。例如弃用/未知 feature flag 不回显会返回 `config_rejected`，不得据合成测试声称全部 CLI feature 已生效。依照已有 R6 检查仅允许 hooks 所有值为空数组，以及 provider headers/query 的 null/空对象；没有删去必要边界。
- `requires_openai_auth` 的官方支持与候选 backend URL/header 是否实际可用是不同证据。此 URL/header 组合尚未真实证实；401/403、HTTP 其他状态或请求拒绝均必须如实记录，不能尝试别的 URL、凭据来源或自动重试。
- 当前 response gate 只覆盖严格合成子集；真实 usage/model 等字段可能返回 `response_rejected`。此子包没有扩大 schema，也不允许抓取全上游正文来调试。`upstream_attempts` 是一次 transport 调用尝试数，不声称服务器已接收或计费。
- 本候选是有限主动探针，不是生产隔离证明。loopback listener 的本机来源未做 OS 级 CLI 身份认证；随机端口、放行窗口和一次预算不能当生产安全能力。认证仍由专用 CLI 账户流持有，本候选仅被动接收此次请求 headers。
- 主控仍须复核 diff、精确 CLI 指纹与实际配置/停止证据后决定后续动作；本交接不扩大用户授权。

## 主控 2026-09-11 较早快照（被下文真实回合结果取代）

专用 Codex 官方登录已成功，独立 status 确认 ChatGPT 账户可用（登录/查询各 0 模型请求、实际 close）。固定公开测试句通过配置及出站重建检查；沿用本机已有代理后收到 HTTP 200 和完整 SSE，当前真实响应仍因未支持的字段而被整段拒绝，未放行文字。当前本地组合 154/154、同一新 pin CLI 合成 14/14；生产仍拒绝，唯一代理/进程来源隔离、专用 exact-turn 停止回执及生命周期真人 Gate 仍待，P6/Goal 1 未通过。不再要求重复登录，未切换 API 或费用来源。

上文 11/11、登录待确认、只支持单条 user 等为 worker 初版快照。主控增加 --inspect、实际配置/路由脱敏分类、本地最多 8 次模型目录 GET 常量拒绝、丢弃早期 user 环境前缀、已有代理连接、有限响应 metadata/phase 兼容及 EOF 后脱敏结构诊断。当前 live 专项 20/20，完整组合 154/154；请求/响应拒绝与一次预算未取消。当前精确结果和未覆盖字段见 [R6 认证状态](P6_R6_TEXT_GATE_PLAN.md#认证状态与当前剩余)。

## 主控 2026-09-11 真实固定文字回合通过

专用登录保持可用；固定公开文字真实回合已通过：请求重建后只带测试句和无工具设置，完整 EOF 与响应门校验后仅放行重建文字，CLI 确认 P6_TEXT_GATE_OK、匹配 turn/completed，实际子进程 close。当前组合 170/170、同一 pin CLI 合成 14/14，12 个负例零输出/分派且所有进程关闭。此结果仅为固定文字点测；生产 profile 仍拒绝，唯一代理/进程来源隔离、专用 exact-turn 停止回执及取消/执行/恢复验收仍待，P6/Goal 1 未通过。

新增有限字段/零工具计数校验与仅固定公开探针可启用的协议键诊断；items 动态键一律不输出。正文全量验证后重建，真实完整回合通过不生成停止回执。当前候选与报告绑定见 [验证清单](../../../tmp/p6-r6-review/real-text-turn-verification-20260911.json)；详细边界和未完成项见 [R6 当前状态](P6_R6_TEXT_GATE_PLAN.md#认证状态与当前剩余)。
